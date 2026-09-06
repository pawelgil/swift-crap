import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Fixture } from './fixture.mjs';

let fixture;
before(async () => { fixture = await Fixture.create(); });
after(async () => { await fixture?.dispose(); });

test('exclusions match complete path components', async () => {
    const excluded = join(fixture.project, 'Generated');
    const retained = join(fixture.project, 'Generatedness');
    await mkdir(excluded);
    await mkdir(retained);
    await writeFile(join(excluded, 'Excluded.swift'), 'func excluded() {}\n');
    await writeFile(join(retained, 'Retained.swift'), 'func retained() {}\n');

    try {
        const result = await fixture.analyze(
            ['--project', fixture.project],
            ['--exclude', 'Generated', '--missing', 'zero'],
        );

        assert.equal(result.code, 0, result.stderr);
        const files = JSON.parse(result.stdout).functions.map(score => score.callable.file);
        assert.ok(files.includes('Generatedness/Retained.swift'));
        assert.ok(!files.includes('Generated/Excluded.swift'));
    } finally {
        await rm(excluded, { force: true, recursive: true });
        await rm(retained, { force: true, recursive: true });
    }
});

test('excluded build symlink is pruned without following it', async () => {
    const external = join(fixture.directory, 'external build');
    const link = join(fixture.project, '.build');
    await mkdir(external);
    await writeFile(join(external, 'Dependency.swift'), 'func dependency() {}\n');
    await symlink(external, link);

    try {
        const result = await fixture.analyze(['--project', fixture.project]);

        assert.equal(result.code, 0, result.stderr);
    } finally {
        await rm(link, { force: true });
    }
});

test('selected source directory symlink cannot escape root', async () => {
    const external = join(fixture.directory, 'external sources');
    const link = join(fixture.project, 'EscapedSources');
    await mkdir(external);
    await writeFile(join(external, 'Escaped.swift'), 'func escaped() {}\n');
    await symlink(external, link);

    try {
        const result = await fixture.analyze(['--project', fixture.project]);

        assert.equal(result.code, 1);
        assert.match(result.stderr, /escape|root/i);
    } finally {
        await rm(link, { force: true });
    }
});

test('explicit file scope includes files beneath Tests', async () => {
    const source = join(fixture.project, 'Tests', 'Decoy.swift');

    const result = await fixture.analyze(['--file', source], ['--missing', 'zero']);

    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout).functions.map(score => score.callable.file), ['Decoy.swift']);
});

test('file root override produces stable project-relative paths', async () => {
    const result = await fixture.analyze(['--file', fixture.source, '--root', fixture.project]);

    assert.equal(result.code, 0, result.stderr);
    assert.deepEqual(
        [...new Set(JSON.parse(result.stdout).functions.map(score => score.callable.file))],
        ['AppLogic/Decision.swift'],
    );
});

test('package metadata inspection does not mutate the package', async () => {
    const manifest = join(fixture.project, 'Package.swift');
    const sourceBefore = await fixture.sourceContents();
    const manifestBefore = await readFile(manifest);

    const result = await fixture.analyze(['--package', fixture.project]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(await fixture.sourceContents(), sourceBefore);
    assert.deepEqual(await readFile(manifest), manifestBefore);
    await assert.rejects(access(join(fixture.project, '.build')));
    await assert.rejects(access(join(fixture.project, 'Package.resolved')));
});

test('missing source path is an actionable input failure', async () => {
    const missing = join(fixture.project, 'Absent.swift');

    const result = await fixture.analyze(['--file', missing]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /does not exist|Absent\.swift/i);
});

test('unknown package target names the failed target', async () => {
    const result = await fixture.analyze(['--package', fixture.project, '--target', 'Absent']);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /target.*Absent|Absent.*target/i);
});

test('file symlink cannot redefine its default root outside lexical parent', async () => {
    const external = join(fixture.directory, 'Outside.swift');
    const link = join(fixture.project, 'Linked.swift');
    await writeFile(external, 'func outside() {}\n');
    await symlink(external, link);

    try {
        const result = await fixture.analyze(['--file', link], ['--missing', 'zero']);

        assert.equal(result.code, 1);
        assert.match(result.stderr, /escape|root/i);
    } finally {
        await rm(link, { force: true });
    }
});

test('invalid source analysis names the source artifact', async () => {
    const source = join(fixture.project, 'Broken.swift');
    await writeFile(source, 'func broken( {\n');

    try {
        const result = await fixture.analyze(['--file', source]);

        assert.equal(result.code, 1);
        assert.ok(result.stderr.includes(source));
    } finally {
        await rm(source, { force: true });
    }
});

test('coverage read failure names the coverage artifact', async () => {
    const coverage = join(fixture.directory, 'AbsentCoverage.json');

    const result = await fixture.cli([
        'analyze', '--file', fixture.source, '--coverage', coverage, '--format', 'json',
        '--trust-coverage', 'unverified',
    ]);

    assert.equal(result.code, 1);
    assert.ok(result.stderr.includes(coverage));
});

test('absolute manifest root is reported as a manifest root error', async () => {
    const manifest = join(fixture.directory, 'invalid-root.json');
    await writeFile(manifest, JSON.stringify({ root: '/outside', targets: { App: ['App.swift'] } }));

    const result = await fixture.analyze(['--sources-manifest', manifest, '--target', 'App']);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /manifest root.*outside/i);
});

test('file scope rejects directories instead of recursing', async () => {
    const result = await fixture.analyze(['--file', fixture.project]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /regular file|file scope/i);
});

test('manifest target entries reject absolute source paths', async () => {
    const manifest = join(fixture.directory, 'absolute-source.json');
    await writeFile(manifest, JSON.stringify({
        root: './project with spaces',
        targets: { App: [fixture.source] },
    }));

    const result = await fixture.analyze(['--sources-manifest', manifest, '--target', 'App']);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /root-relative|manifest entry/i);
});

test('exclusion applies to a file symlink resolved inside excluded path', async () => {
    const excluded = join(fixture.project, 'Excluded');
    const source = join(excluded, 'Source.swift');
    const alias = join(fixture.project, 'Alias.swift');
    await mkdir(excluded);
    await writeFile(source, 'func excluded() {}\n');
    await symlink(source, alias);

    try {
        const result = await fixture.analyze(
            ['--project', fixture.project],
            ['--exclude', 'Excluded'],
        );

        assert.equal(result.code, 0, result.stderr);
        const files = JSON.parse(result.stdout).functions.map(score => score.callable.file);
        assert.ok(!files.includes('Excluded/Source.swift'));
    } finally {
        await rm(alias, { force: true });
        await rm(excluded, { force: true, recursive: true });
    }
});

test('project filtering rejects a file symlink resolved beneath Tests', async () => {
    const alias = join(fixture.project, 'TestAlias.swift');
    const decoy = join(fixture.project, 'Tests', 'Decoy.swift');
    await symlink(decoy, alias);

    try {
        const result = await fixture.analyze(['--project', fixture.project]);

        assert.equal(result.code, 0, result.stderr);
        const files = JSON.parse(result.stdout).functions.map(score => score.callable.file);
        assert.ok(!files.includes('Tests/Decoy.swift'));
    } finally {
        await rm(alias, { force: true });
    }
});
