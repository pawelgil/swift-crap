import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { after, before, test } from 'node:test';
import { access, cp, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execute = promisify(execFile);
const repository = join(dirname(fileURLToPath(import.meta.url)), '../..');
const sourceFixture = join(repository, 'Fixtures', 'XcodeFixture');
let directory;
let fixture;
let project;
let resultBundle;

before(async () => {
    if (process.platform !== 'darwin') return;
    directory = await mkdtemp(join(tmpdir(), 'swift crap xcode e2e-'));
    fixture = join(directory, 'XcodeFixture');
    project = join(fixture, 'XcodeFixture.xcodeproj');
    resultBundle = join(directory, 'Tests.xcresult');
    await cp(sourceFixture, fixture, { recursive: true });
    await execute('xcodebuild', [
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', 'platform=macOS',
        '-derivedDataPath', join(directory, 'DerivedData'),
        '-resultBundlePath', resultBundle,
        '-enableCodeCoverage', 'YES',
        'test',
    ], { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
});

after(async () => {
    if (directory) await rm(directory, { recursive: true, force: true });
});

test('Xcode target and unambiguous xcresult analyze through the executable', {
    skip: process.platform !== 'darwin',
}, async () => {
    const binary = process.env.SWIFT_CRAP_BINARY;
    if (!binary) throw new Error('SWIFT_CRAP_BINARY must point to the built executable');

    const { stdout } = await execute(binary, [
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--coverage', resultBundle,
        '--trust-coverage', 'unverified',
        '--exclude', 'Sources/Included.swift',
        '--missing', 'zero',
        '--format', 'json',
    ], { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });

    const report = JSON.parse(stdout);
    assert.deepEqual([...new Set(report.functions.map(score => score.callable.file))], [
        'Sources/Another.swift',
    ]);
    assert.equal(report.verification, 'unverified');
});

test('Xcode aggregate coverage rejects ambiguous same-line closures', {
    skip: process.platform !== 'darwin',
}, async () => {
    const analyzed = await cli([
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--coverage', resultBundle,
        '--trust-coverage', 'unverified',
        '--missing', 'zero',
    ]);

    assert.equal(analyzed.code, 1);
    assert.match(analyzed.stderr, /matches multiple source callables/);
});

test('Xcode capture records active configuration and xcresult provenance', {
    skip: process.platform !== 'darwin',
}, async () => {
    const capturedResult = join(directory, 'Captured.xcresult');
    const capturedDerivedData = join(directory, 'CapturedDerivedData');
    const receipt = join(directory, 'capture.json');
    const command = [
        'xcodebuild',
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', 'platform=macOS',
        '-derivedDataPath', capturedDerivedData,
        '-resultBundlePath', capturedResult,
        '-enableCodeCoverage', 'YES',
        'test',
    ];

    const capture = await cli([
        'capture',
        '--root', fixture,
        '--output', receipt,
        '--coverage', capturedResult,
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--', ...command,
    ]);
    assert.equal(capture.code, 0, capture.stderr);
    const recorded = JSON.parse(await readFile(receipt, 'utf8'));
    const frozenCoverage = Object.values(recorded.coverageExports ?? {});
    assert.equal(frozenCoverage.length, 1);
    assert.match(frozenCoverage[0], /^[A-Za-z0-9+/]+=*$/);
    await rm(capturedDerivedData, { recursive: true });
    await access(capturedResult);

    const analyzed = await cli([
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--coverage', capturedResult,
        '--provenance', receipt,
        '--format', 'json',
    ]);

    assert.equal(analyzed.code, 0, analyzed.stderr);
    const report = JSON.parse(analyzed.stdout);
    assert.equal(report.verification, 'captured');
    assert.match(report.buildIdentity, /^[0-9a-f]{64}$/);
    assert.equal(report.functions.filter(score => score.callable.name.includes('configuration')).length, 1);
    assert.ok(report.functions.some(score => score.callable.name.includes('included')));
    assert.ok(report.functions.every(score => score.callable.file !== 'Sources/Excluded.swift'));
    const closures = closureScores(report);
    assert.deepEqual(closures.map(score => score.callable.span.start.column), [12, 27]);
    assert.deepEqual(closures.map(score => [score.coveredLines, score.executableLines]), [[1, 1], [0, 1]]);

    const mismatched = await cli([
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Release',
        '--destination', 'platform=macOS',
        '--coverage', capturedResult,
        '--provenance', receipt,
    ]);
    assert.equal(mismatched.code, 1);
    assert.match(mismatched.stderr, /Xcode selection differs from capture/);

    await writeFile(join(capturedResult, 'tampered'), 'tampered');
    const tampered = await cli([
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--coverage', capturedResult,
        '--provenance', receipt,
    ]);
    assert.equal(tampered.code, 1);
    assert.match(tampered.stderr, /coverage artifact.*changed/);
});

test('Xcode simulator capture records actual destination compiler context', {
    skip: process.platform !== 'darwin',
}, async () => {
    const destination = await simulatorDestination();
    const hostArchitecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';
    const capturedResult = join(directory, 'Simulator.xcresult');
    const simulatorDerivedData = join(directory, 'SimulatorDerivedData');
    const receipt = join(directory, 'simulator-capture.json');
    const command = [
        'xcodebuild',
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', destination,
        '-sdk', 'iphonesimulator',
        '-derivedDataPath', simulatorDerivedData,
        '-resultBundlePath', capturedResult,
        '-enableCodeCoverage', 'YES',
        `ARCHS=${hostArchitecture}`,
        'ONLY_ACTIVE_ARCH=YES',
        'CODE_SIGNING_ALLOWED=NO',
        'test',
    ];

    const capture = await cli([
        'capture',
        '--root', fixture,
        '--output', receipt,
        '--coverage', capturedResult,
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', destination,
        '--', ...command,
    ]);

    assert.equal(capture.code, 0, capture.stderr);
    const recorded = JSON.parse(await readFile(receipt, 'utf8'));
    const context = recorded.contexts.find(value => value.moduleName === 'XcodeFixture');
    assert.ok(context.arguments.some(value => value.includes('/iPhoneSimulator.platform/')));
    assert.ok(context.arguments.some(value => value.endsWith('-simulator')));
    assert.ok(recorded.callables.some(value => value.name.includes('simulatorOnly')));
    assert.ok(recorded.callables.every(value => !value.name.includes('nonSimulatorOnly')));
    await rm(simulatorDerivedData, { recursive: true });

    const analyzed = await cli([
        'analyze',
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', destination,
        '--coverage', capturedResult,
        '--provenance', receipt,
        '--format', 'json',
    ]);
    assert.equal(analyzed.code, 0, analyzed.stderr);
    const report = JSON.parse(analyzed.stdout);
    assert.equal(report.verification, 'captured');
    assert.ok(report.functions.some(value => value.callable.name.includes('simulatorOnly')));
    assert.ok(report.functions.every(value => !value.callable.name.includes('nonSimulatorOnly')));
    assert.deepEqual(
        closureScores(report).map(score => [score.coveredLines, score.executableLines]),
        [[1, 1], [0, 1]],
    );
});

test('Xcode capture does not write a receipt when precise coverage export fails', {
    skip: process.platform !== 'darwin',
}, async () => {
    const capturedResult = join(directory, 'NoCoverage.xcresult');
    const receipt = join(directory, 'no-coverage-capture.json');
    const command = [
        'xcodebuild',
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', 'platform=macOS',
        '-derivedDataPath', join(directory, 'NoCoverageDerivedData'),
        '-resultBundlePath', capturedResult,
        '-enableCodeCoverage', 'NO',
        'test',
    ];

    const capture = await cli([
        'capture',
        '--root', fixture,
        '--output', receipt,
        '--coverage', capturedResult,
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', 'platform=macOS',
        '--', ...command,
    ]);

    assert.equal(capture.code, 1);
    assert.match(capture.stderr, /coverage|xccov/i);
    await access(capturedResult);
    await assert.rejects(access(receipt), { code: 'ENOENT' });
});

test('Xcode capture rejects universal build with explicit host destination architecture', {
    skip: process.platform !== 'darwin',
}, async () => {
    const hostArchitecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';
    const destination = `platform=macOS,arch=${hostArchitecture}`;
    const capturedResult = join(directory, 'Universal.xcresult');
    const receipt = join(directory, 'universal-capture.json');
    const command = [
        'xcodebuild',
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', destination,
        '-derivedDataPath', join(directory, 'UniversalDerivedData'),
        '-resultBundlePath', capturedResult,
        '-enableCodeCoverage', 'YES',
        'ARCHS=arm64 x86_64',
        'ONLY_ACTIVE_ARCH=NO',
        'test',
    ];

    const capture = await cli([
        'capture',
        '--root', fixture,
        '--output', receipt,
        '--coverage', capturedResult,
        '--xcode-project', project,
        '--scheme', 'XcodeFixture',
        '--target', 'XcodeFixture',
        '--configuration', 'Debug',
        '--destination', destination,
        '--', ...command,
    ]);

    assert.equal(capture.code, 1);
    assert.match(capture.stderr, /capture builds multiple architectures \(arm64, x86_64\)/);
    await access(capturedResult);
    await assert.rejects(access(receipt), { code: 'ENOENT' });
});

async function cli(args) {
    const binary = process.env.SWIFT_CRAP_BINARY;
    if (!binary) throw new Error('SWIFT_CRAP_BINARY must point to the built executable');
    try {
        const output = await execute(binary, args, { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
        return { ...output, code: 0 };
    } catch (error) {
        if (typeof error.code !== 'number') throw error;
        return { stdout: error.stdout, stderr: error.stderr, code: error.code };
    }
}

function closureScores(report) {
    return report.functions
        .filter(score => score.callable.file === 'Sources/Included.swift'
            && score.callable.span.start.line === 9)
        .sort((left, right) => left.callable.span.start.column - right.callable.span.start.column);
}

async function simulatorDestination() {
    const { stdout } = await execute('xcodebuild', [
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-showdestinations',
    ], { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
    const line = stdout.split('\n').find(value =>
        value.includes('platform:iOS Simulator, arch:') && !value.includes('placeholder'));
    const id = line?.match(/\bid:([^,}]+)/)?.[1]?.trim();
    if (!id) throw new Error(`No concrete iOS Simulator destination:\n${stdout}`);
    return `platform=iOS Simulator,id=${id}`;
}
