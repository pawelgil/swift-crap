import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { readFile, writeFile, copyFile, access } from 'node:fs/promises';
import { join } from 'node:path';
import { Fixture } from './fixture.mjs';

let fixture;
let receipt;
let coverage;
let context;

before(async () => {
    fixture = await Fixture.create();
    receipt = join(fixture.directory, 'capture-receipt.json');
    coverage = join(fixture.directory, 'captured-coverage.json');
    context = join(fixture.directory, 'compiler-context.json');
    const compiler = process.platform === 'darwin'
        ? (await fixture.tool('--find', ['swiftc'])).stdout.trim()
        : (await fixture.tool('which', ['swiftc'])).stdout.trim();
    const arguments_ = process.platform === 'darwin'
        ? ['-sdk', (await fixture.tool('--show-sdk-path', [])).stdout.trim()] : [];
    await writeFile(context, JSON.stringify([{
        compiler, arguments: arguments_, directory: fixture.project, moduleName: 'subject',
        sources: [fixture.source, join(fixture.project, 'Adapters', 'Adapter.swift')],
    }]));
    const script = join(fixture.directory, 'capture.mjs');
    await writeFile(script, `import { Fixture } from ${JSON.stringify(new URL('./fixture.mjs', import.meta.url).href)};
const fixture = new Fixture(${JSON.stringify(fixture.directory)});
fixture.coverage = ${JSON.stringify(coverage)};
await fixture.generateCoverage();
`);
    const result = await fixture.cli(['capture', '--root', fixture.project, '--output', receipt,
        '--coverage', coverage, '--build-context', context, '--', process.execPath, script]);
    assert.equal(result.code, 0, result.stderr);
});

after(async () => fixture?.dispose());

function analyze(extra = []) {
    return fixture.cli(['analyze', '--project', fixture.project, '--coverage', coverage,
        '--provenance', receipt, '--format', 'json', ...extra]);
}

test('captured coverage scores with explicit verified provenance', async () => {
    const result = await analyze();
    assert.equal(result.code, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.verification, 'captured');
    assert.match(report.buildIdentity, /^[0-9a-f]{64}$/);
    assert.equal(report.summary.assumedFunctions, 0);
});

test('unverified import requires explicit opt-in and labels output', async () => {
    const denied = await fixture.cli(['analyze', '--file', fixture.source, '--coverage', coverage]);
    assert.equal(denied.code, 1);
    assert.match(denied.stderr, /provenance/);
    const allowed = await fixture.cli(['analyze', '--file', fixture.source, '--coverage', coverage,
        '--trust-coverage', 'unverified', '--format', 'json']);
    assert.equal(allowed.code, 0, allowed.stderr);
    const report = JSON.parse(allowed.stdout);
    assert.equal(report.verification, 'unverified');
    assert.equal(report.buildIdentity, undefined);
});

test('same-length source changes invalidate provenance', async () => {
    const original = await readFile(fixture.source, 'utf8');
    try {
        await writeFile(fixture.source, original.replace('positive', 'negative'));
        const result = await analyze();
        assert.equal(result.code, 1);
        assert.match(result.stderr, /inputs differ/);
    } finally { await writeFile(fixture.source, original); }
});

test('coverage artifact modification invalidates provenance', async () => {
    const original = await readFile(coverage);
    try {
        await writeFile(coverage, Buffer.concat([original, Buffer.from('\n')]));
        const result = await analyze();
        assert.equal(result.code, 1);
        assert.match(result.stderr, /artifact.*changed/);
    } finally { await writeFile(coverage, original); }
});

test('capture refuses old coverage outputs before invoking command', async () => {
    const result = await fixture.cli(['capture', '--root', fixture.project,
        '--output', join(fixture.directory, 'second.json'), '--coverage', coverage,
        '--build-context', context, '--', process.execPath, '-e', 'process.exit(72)']);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /already exists/);
});

test('a copied artifact is not silently accepted as captured', async () => {
    const copy = join(fixture.directory, 'copied.json');
    await copyFile(coverage, copy);
    const result = await fixture.cli(['analyze', '--file', fixture.source, '--coverage', copy,
        '--provenance', receipt]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /not captured/);
});

test('failed build commands never create a receipt', async () => {
    const output = join(fixture.directory, 'failed-receipt.json');
    const result = await fixture.cli(['capture', '--root', fixture.project, '--output', output,
        '--coverage', join(fixture.directory, 'failed-coverage.json'), '--build-context', context,
        '--', process.execPath, '-e', 'process.exit(72)']);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /command failed with exit 72/);
    await assert.rejects(access(output));
});

test('file and package scopes reuse the captured root and inventory', async () => {
    for (const scope of [['--file', fixture.source], ['--package', fixture.project, '--target', 'Logic']]) {
        const result = await fixture.cli(['analyze', ...scope, '--coverage', coverage,
            '--provenance', receipt, '--format', 'json']);
        assert.equal(result.code, 0, result.stderr);
        assert.ok(JSON.parse(result.stdout).functions.every(row => row.callable.file === 'AppLogic/Decision.swift'));
    }
});

test('captured analysis rejects an unverified baseline', async () => {
    const legacy = await fixture.analyze(['--file', fixture.source]);
    assert.equal(legacy.code, 0, legacy.stderr);
    const baseline = join(fixture.directory, 'unverified-baseline.json');
    await writeFile(baseline, legacy.stdout);
    const result = await analyze(['--baseline', baseline]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /requires a captured baseline/);
});

test('captured analysis accepts an unchanged captured baseline', async () => {
    const current = await analyze();
    assert.equal(current.code, 0, current.stderr);
    const baseline = join(fixture.directory, 'captured-baseline.json');
    await writeFile(baseline, current.stdout);
    const result = await analyze(['--baseline', baseline]);
    assert.equal(result.code, 0, result.stderr);
});

test('captured analysis rejects a baseline from a different build identity', async () => {
    const current = await analyze();
    assert.equal(current.code, 0, current.stderr);
    const report = JSON.parse(current.stdout);
    report.buildIdentity = '0'.repeat(64);
    const baseline = join(fixture.directory, 'different-build-baseline.json');
    await writeFile(baseline, JSON.stringify(report));

    const result = await analyze(['--baseline', baseline]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /baseline build identity differs/);
});
