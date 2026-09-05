import CrapCore
import CrapCoverage
import CrapSyntax
import Foundation

final class CompilerFixture {
    let directory: URL
    private let sourceURL: URL
    private let binaryURL: URL
    private let source: String

    init(
        source: String = CompilerFixture.source,
        entry: String = "print(Subject.classify(Int(CommandLine.arguments[1]) ?? 0))",
    ) throws {
        self.source = source
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("swift-crap-integration-\(UUID())")
        sourceURL = directory.appendingPathComponent("Subject.swift")
        binaryURL = directory.appendingPathComponent("subject")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        let main = directory.appendingPathComponent("main.swift")
        try "import Foundation\n\(entry)\n"
            .write(to: main, atomically: true, encoding: .utf8)
        _ = try run(
            "swiftc",
            ["-profile-generate", "-profile-coverage-mapping", sourceURL.path, main.path, "-o", binaryURL.path],
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func score(inputs: [Int]) throws -> AnalysisReport {
        let records = try inputs.flatMap { try coverage(input: $0) }
        let callables = try SwiftSourceAnalyzer().analyze(source: source, file: "Subject.swift")
        return try AnalysisEngine().analyze(
            callables: callables, coverage: records, root: directory.path,
            missing: .error, threshold: 30,
        )
    }

    func coverage(input: Int) throws -> [CoverageRecord] {
        try CompilerCoverageDecoder().decode(coverageExport(input: input)).records
    }

    func coverageExport(input: Int) throws -> Data {
        let raw = directory.appendingPathComponent("run-\(input).profraw")
        let merged = directory.appendingPathComponent("run-\(input).profdata")
        _ = try run(binaryURL.path, [String(input)], environment: ["LLVM_PROFILE_FILE": raw.path])
        _ = try run("llvm-profdata", ["merge", "-sparse", raw.path, "-o", merged.path])
        return try run("llvm-cov", ["export", binaryURL.path, "-instr-profile", merged.path])
    }

    func nativeLineCoverage(input: Int, symbolSuffix: String) throws -> NativeLineCoverage {
        _ = try coverageExport(input: input)
        let profile = directory.appendingPathComponent("run-\(input).profdata")
        let output = try run("llvm-cov", [
            "report", binaryURL.path, "-instr-profile", profile.path, "-show-functions", sourceURL.path,
        ])
        let rows = String(decoding: output, as: UTF8.self).split(separator: "\n")
            .map { $0.split(whereSeparator: \.isWhitespace) }
        guard let row = rows.first(where: { $0.first?.hasSuffix(symbolSuffix) == true }),
              row.count >= 7,
              let executable = Int(row[4]), let missed = Int(row[5])
        else { throw FixtureError.missingNativeFunction(symbolSuffix) }
        return NativeLineCoverage(executable: executable, covered: executable - missed)
    }

    private func run(_ command: String, _ arguments: [String], environment: [String: String] = [:]) throws -> Data {
        let output = directory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = invocation(command, arguments)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
        process.standardOutput = handle
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0
        else { throw FixtureError.commandFailed(command, process.terminationStatus) }
        return try Data(contentsOf: output)
    }

    private func invocation(_ command: String, _ arguments: [String]) -> [String] {
        #if os(macOS)
            return command.hasPrefix("/") ? [command] + arguments : ["xcrun", command] + arguments
        #else
            return [command] + arguments
        #endif
    }

    static let source = """
    enum Subject {
        static func classify(_ value: Int) -> String {
            if value > 0 {
                return "positive"
            }
            return "other"
        }
    }
    """
}
