@testable import CrapCLI
import Testing

struct CompilerProbeArgumentsTests {
    @Test func `compiler context retains conditional and import options without outputs`() throws {
        let result = try CompilerProbeArguments().prepare([
            "-target", "arm64-apple-macosx13", "-sdk", "/SDK", "-DDEBUG", "-I", "/Modules", "-F", "/Frameworks",
            "-swift-version", "6", "-enable-experimental-feature", "Lifetimes", "-Xcc", "-DFEATURE",
            "-c", "-primary-file", "/Source.swift", "-o", "/output.o", "-module-cache-path", "/cache",
            "-emit-module-source-info-path", "/output.swiftsourceinfo", "-profile-generate",
            "-use-frontend-parseable-output", "-j12",
        ])
        #expect(result == ["-target", "arm64-apple-macosx13", "-sdk", "/SDK", "-DDEBUG", "-I", "/Modules", "-F",
                           "/Frameworks", "-swift-version", "6", "-enable-experimental-feature", "Lifetimes",
                           "-Xcc", "-DFEATURE"])
    }

    @Test(arguments: [["-o"], ["-primary-file"], ["-Xcc"], ["@response.txt"]])
    func `incomplete or unexpanded arguments are rejected`(arguments: [String]) {
        #expect(throws: (any Error).self) { try CompilerProbeArguments().prepare(arguments) }
    }
}
