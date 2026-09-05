import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const execute = promisify(execFile);

export class Fixture {
    static async create() {
        const directory = await mkdtemp(join(tmpdir(), 'swift-crap-e2e-'));
        const fixture = new Fixture(directory);
        await fixture.prepare();
        return fixture;
    }

    constructor(directory) {
        this.directory = directory;
        this.project = join(directory, 'project with spaces');
        this.source = join(this.project, 'AppLogic', 'Decision.swift');
        this.coverage = join(directory, 'coverage.json');
    }

    async prepare() {
        await mkdir(join(this.project, 'AppLogic'), { recursive: true });
        await mkdir(join(this.project, 'Adapters'), { recursive: true });
        await mkdir(join(this.project, 'Tests'), { recursive: true });
        await writeFile(join(this.project, 'Package.swift'), this.manifest);
        await writeFile(this.source, this.logic);
        await writeFile(join(this.project, 'Adapters', 'Adapter.swift'), 'enum Adapter { static func answer() -> Int { 42 } }\n');
        await writeFile(join(this.project, 'Tests', 'Decoy.swift'), 'func decoy() -> Int { 42 }\n');
        await writeFile(join(this.directory, 'main.swift'), 'print(Decision.choose(1))\n');
        await this.generateCoverage();
    }

    async generateCoverage() {
        const binary = join(this.directory, 'subject');
        const profile = join(this.directory, 'default.profraw');
        const merged = join(this.directory, 'default.profdata');
        await this.tool('swiftc', ['-profile-generate', '-profile-coverage-mapping', this.source,
            join(this.project, 'Adapters', 'Adapter.swift'), join(this.directory, 'main.swift'), '-o', binary]);
        await execute(binary, [], { env: { ...process.env, LLVM_PROFILE_FILE: profile } });
        await this.tool('llvm-profdata', ['merge', '-sparse', profile, '-o', merged]);
        const { stdout } = await this.tool('llvm-cov', ['export', binary, '-instr-profile', merged]);
        await writeFile(this.coverage, stdout);
    }

    async tool(name, args) {
        const command = process.platform === 'darwin' ? 'xcrun' : name;
        const parameters = process.platform === 'darwin' ? [name, ...args] : args;
        return execute(command, parameters, { timeout: 120_000, maxBuffer: 8 * 1024 * 1024 });
    }

    async cli(args) {
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

    analyze(scope, extra = []) {
        return this.cli(['analyze', ...scope, '--coverage', this.coverage, '--format', 'json', ...extra]);
    }

    async dispose() {
        await rm(this.directory, { recursive: true, force: true });
    }

    async sourceContents() {
        return readFile(this.source, 'utf8');
    }

    get manifest() {
        return `// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "Fixture", targets: [
    .target(name: "Logic", path: "AppLogic"),
    .target(name: "Adapters", path: "Adapters")
])
`;
    }

    get logic() {
        return `enum Decision {
    static func choose(_ value: Int) -> String {
        if value > 0 {
            return "positive"
        }
        return "other"
    }
    static func unused(_ value: Int) -> Int {
        if value > 0 {
            return value
        }
        return -value
    }
}
`;
    }
}
