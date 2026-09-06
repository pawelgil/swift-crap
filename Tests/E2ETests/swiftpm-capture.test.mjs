import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { after, before, test } from 'node:test';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { Fixture } from './fixture.mjs';

const execute = promisify(execFile);
let fixture;
let source;
let coverage;
let receipt;

before(async () => {
    fixture = new Fixture(await createDirectory());
    source = join(fixture.project, 'Sources', 'Logic', 'Decision.swift');
    coverage = join(fixture.directory, 'captured-coverage.json');
    receipt = join(fixture.directory, 'capture-receipt.json');
    await mkdir(join(fixture.project, 'Sources', 'Logic'), { recursive: true });
    await mkdir(join(fixture.project, 'Tests', 'LogicTests'), { recursive: true });
    await writeFile(join(fixture.project, 'Package.swift'), manifest);
    await writeFile(source, logic);
    await writeFile(join(fixture.project, 'Tests', 'LogicTests', 'DecisionTests.swift'), tests);
    await swift(['build', '--build-tests', '--enable-code-coverage']);
    const binPath = (await swift(['build', '--show-bin-path'])).stdout.trim();
    const captureScript = join(fixture.directory, 'capture.mjs');
    await writeFile(captureScript, captureCommand(fixture.project, coverage));
    const result = await fixture.cli(['capture', '--root', fixture.project, '--output', receipt,
        '--coverage', coverage, '--build-description', join(binPath, 'description.json'),
        '--', process.execPath, captureScript]);
    assert.equal(result.code, 0, result.stderr);
});

after(async () => fixture?.dispose());

test('native SwiftPM capture preserves active target semantics across selectors', async () => {
    const scopes = [
        ['--package', fixture.project],
        ['--package', fixture.project, '--target', 'Logic'],
        ['--file', source],
    ];
    for (const scope of scopes) {
        const result = await analyze(scope);
        assert.equal(result.code, 0, result.stderr);
        const report = JSON.parse(result.stdout);
        assert.equal(report.verification, 'captured');
        assert.equal(report.summary.totalFunctions, 1);
        assert.equal(report.summary.measuredFunctions, 1);
        assert.equal(report.summary.assumedFunctions, 0);
        assert.equal(report.functions[0].callable.complexity, 2);
        assert.equal(report.functions[0].coverage, 1);
        assert.match(report.functions[0].callable.id, /#if canImport\(Logic\) && AUDIT_ACTIVE/);
    }
});

test('native SwiftPM capture rejects a source change', async () => {
    const original = await readFile(source, 'utf8');
    try {
        await writeFile(source, original.replace('positive', 'negative'));
        const result = await analyze(['--package', fixture.project, '--target', 'Logic']);
        assert.equal(result.code, 1);
        assert.match(result.stderr, /inputs differ/);
    } finally {
        await writeFile(source, original);
    }
});

function analyze(scope) {
    return fixture.cli(['analyze', ...scope, '--coverage', coverage, '--provenance', receipt, '--format', 'json']);
}

function swift(arguments_) {
    return execute('swift', arguments_, { cwd: fixture.project, timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
}

async function createDirectory() {
    return mkdtemp(join(tmpdir(), 'swift-crap-swiftpm-e2e-'));
}

const manifest = `// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "CaptureFixture", products: [
    .library(name: "Logic", targets: ["Logic"]),
], targets: [
    .target(name: "Logic", swiftSettings: [.define("AUDIT_ACTIVE")]),
    .testTarget(name: "LogicTests", dependencies: ["Logic"]),
])
`;

const logic = `public enum Decision {
#if canImport(Logic) && AUDIT_ACTIVE
    public static func choose(_ value: Int) -> String {
        if value > 0 {
            return "positive"
        }
        return "other"
    }
#else
    public static func choose(_ value: Int) -> String {
        switch value {
        case 1: "one"
        case 2: "two"
        default: "other"
        }
    }
#endif
}
`;

const tests = `import Testing
@testable import Logic

@Test func choosesBothPaths() {
    #expect(Decision.choose(1) == "positive")
    #expect(Decision.choose(0) == "other")
}
`;

function captureCommand(project, output) {
    return `import { copyFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execute = promisify(execFile);
const options = { cwd: ${JSON.stringify(project)}, timeout: 120_000, maxBuffer: 8 * 1024 * 1024 };
await execute('swift', ['test', '--enable-code-coverage'], options);
const result = await execute('swift', ['test', '--show-codecov-path'], options);
await copyFile(result.stdout.trim(), ${JSON.stringify(output)});
`;
}
