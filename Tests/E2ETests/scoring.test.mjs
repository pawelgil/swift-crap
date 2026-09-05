import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { writeFile } from 'node:fs/promises';
import { Fixture } from './fixture.mjs';

let fixture;
before(async () => { fixture = await Fixture.create(); });
after(async () => { await fixture?.dispose(); });

test('single-file scoring uses measured coverage and stable relative paths', async () => {
    const result = await fixture.analyze(['--file', fixture.source, '--root', fixture.project]);
    assert.equal(result.code, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.metric, 'crap-line-v1');
    assert.equal(report.functions.length, 2);
    assert.deepEqual([...new Set(report.functions.map(f => f.callable.file))], ['AppLogic/Decision.swift']);
    const unused = report.functions.find(f => f.callable.name.includes('unused'));
    assert.equal(unused.coverage, 0);
    assert.equal(unused.crap, 6);
    assert.equal(unused.coverageStatus, 'measured');
});

test('whole-project scoring excludes test sources', async () => {
    const result = await fixture.analyze(['--project', fixture.project]);
    assert.equal(result.code, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.deepEqual([...new Set(report.functions.map(f => f.callable.file))].sort(),
        ['Adapters/Adapter.swift', 'AppLogic/Decision.swift']);
});

test('package scoring uses declared custom target paths', async () => {
    const result = await fixture.analyze(['--package', fixture.project]);
    assert.equal(result.code, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).functions.length, 3);
});

test('target scoring selects exact SwiftPM membership', async () => {
    const result = await fixture.analyze(['--package', fixture.project, '--target', 'Logic']);
    assert.equal(result.code, 0, result.stderr);
    const files = JSON.parse(result.stdout).functions.map(f => f.callable.file);
    assert.deepEqual([...new Set(files)], ['AppLogic/Decision.swift']);
});

test('unknown target is an input failure', async () => {
    const result = await fixture.analyze(['--package', fixture.project, '--target', 'Absent']);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /target|Absent/i);
});

test('explicit manifest selects a target for other build systems', async () => {
    const manifest = join(fixture.directory, 'sources.json');
    await writeFile(manifest, JSON.stringify({ root: './project with spaces', targets: { MacApp: ['AppLogic'] } }));
    const result = await fixture.analyze(['--sources-manifest', manifest, '--target', 'MacApp']);
    assert.equal(result.code, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).functions.length, 2);
});

test('threshold violation produces JSON and exit two', async () => {
    const result = await fixture.analyze(['--file', fixture.source], ['--threshold', '1']);
    assert.equal(result.code, 2, result.stderr);
    assert.equal(JSON.parse(result.stdout).summary.violations, 2);
});

test('identical analyses produce identical JSON bytes', async () => {
    const args = ['--file', fixture.source];
    const first = await fixture.analyze(args);
    const second = await fixture.analyze(args);
    assert.equal(first.code, 0, first.stderr);
    assert.equal(second.stdout, first.stdout);
});

test('identical baseline permits existing debt without false regressions', async () => {
    const first = await fixture.analyze(['--file', fixture.source], ['--threshold', '1']);
    const baseline = join(fixture.directory, 'baseline.json');
    await writeFile(baseline, first.stdout);
    const second = await fixture.analyze(['--file', fixture.source], ['--threshold', '1', '--baseline', baseline]);
    assert.equal(second.code, 0, second.stderr);
    assert.equal(JSON.parse(second.stdout).summary.violations, 0);
});

test('malformed coverage is never a successful gate', async () => {
    const coverage = join(fixture.directory, 'bad.json');
    await writeFile(coverage, '{broken');
    const result = await fixture.cli(['analyze', '--file', fixture.source, '--coverage', coverage]);
    assert.equal(result.code, 1);
    assert.notEqual(result.stderr.trim(), '');
});

test('missing required coverage fails and zero must be explicit', async () => {
    const path = join(fixture.directory, 'Unbuilt.swift');
    await writeFile(path, 'func unbuilt() -> Int { 42 }\n');
    const missing = await fixture.analyze(['--file', path]);
    assert.equal(missing.code, 1);
    const assumed = await fixture.analyze(['--file', path], ['--missing', 'zero']);
    assert.equal(assumed.code, 0, assumed.stderr);
    const score = JSON.parse(assumed.stdout).functions[0];
    assert.equal(score.coverageStatus, 'assumedZero');
    assert.equal(score.crap, 2);
});

test('analysis leaves source bytes unchanged', async () => {
    const before = await fixture.sourceContents();
    const result = await fixture.analyze(['--file', fixture.source]);
    assert.equal(result.code, 0, result.stderr);
    assert.equal(await fixture.sourceContents(), before);
});

test('help and version require no coverage artifact', async () => {
    const help = await fixture.cli(['--help']);
    const version = await fixture.cli(['--version']);
    assert.equal(help.code, 0);
    assert.match(help.stdout, /--coverage/);
    assert.equal(version.code, 0);
    assert.match(version.stdout, /\d+\.\d+/);
});

test('invalid numeric threshold is an input error', async () => {
    const result = await fixture.analyze(['--file', fixture.source], ['--threshold', 'nan']);
    assert.equal(result.code, 1);
});
