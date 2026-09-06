import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { after, before, test } from 'node:test';
import { access, cp, mkdtemp, rm } from 'node:fs/promises';
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
    directory = await mkdtemp(join(tmpdir(), 'swift-crap-xcode-e2e-'));
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

test('Xcode target and xcresult analyze through the executable', {
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
        '--missing', 'zero',
        '--format', 'json',
    ], { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });

    const report = JSON.parse(stdout);
    assert.deepEqual([...new Set(report.functions.map(score => score.callable.file))], [
        'Sources/Another.swift',
        'Sources/Included.swift',
    ]);
    const included = report.functions.find(score => score.callable.name.includes('included'));
    assert.equal(included.coveredLines, 5);
    assert.equal(included.executableLines, 6);
    assert.equal(report.verification, 'unverified');
});

test('Xcode capture records active configuration and xcresult provenance', {
    skip: process.platform !== 'darwin',
}, async () => {
    const capturedResult = join(directory, 'Captured.xcresult');
    const receipt = join(directory, 'capture.json');
    const command = [
        'xcodebuild',
        '-project', project,
        '-scheme', 'XcodeFixture',
        '-configuration', 'Debug',
        '-destination', 'platform=macOS',
        '-derivedDataPath', join(directory, 'CapturedDerivedData'),
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
