@testable import CrapCLI
import Testing

struct CaptureArgumentParserTests {
    @Test func `capture preserves command arguments without shell reinterpretation`() throws {
        let action = try CLIArgumentParser().parse(["capture", "--root", "/repo", "--output", "/receipt.json",
                                                    "--coverage", "/coverage.json", "--build-context", "/context.json",
                                                    "--", "tool", "a b", "$value", "--help"])
        guard case let .capture(request) = action else { Issue.record("expected capture"); return }
        #expect(request.command == ["tool", "a b", "$value", "--help"])
        #expect(request.root == "/repo")
        #expect(request.buildContext == "/context.json")
    }

    @Test(arguments: [
        ["capture", "--root", "/repo"],
        ["capture", "--root", "/repo", "--output", "/out", "--coverage", "/cov", "--"],
        ["capture", "--root", "/repo", "--output", "/out", "--coverage", "/cov", "--", "true"],
        ["capture", "--root", "/repo", "--root", "/other", "--", "true"],
        ["capture", "--root", "/repo", "--output", "/out", "--coverage", "/cov", "--build-description", "/desc",
         "--build-context", "/context", "--", "true"],
        ["capture", "--root", "/repo", "--output", "/out", "--coverage", "/cov", "--scheme", "App", "--", "true"],
    ]) func `malformed capture is rejected`(arguments: [String]) {
        #expect(throws: (any Error).self) { try CLIArgumentParser().parse(arguments) }
    }

    @Test func `analysis rejects conflicting trust modes`() {
        #expect(throws: (any Error).self) {
            try CLIArgumentParser().parse(["analyze", "--file", "/file.swift", "--coverage", "/coverage.json",
                                           "--provenance", "/receipt.json", "--trust-coverage", "unverified"])
        }
    }

    @Test func `xcode selection retains build configuration`() throws {
        let action = try CLIArgumentParser().parse(["analyze", "--xcode-project", "/App.xcodeproj", "--scheme", "App",
                                                    "--target", "App", "--configuration", "Release", "--coverage",
                                                    "/coverage.xcresult"])
        guard case let .analyze(request, _) = action,
              case let .xcode(selection) = request.selection.scope else { Issue.record("expected Xcode"); return }
        #expect(selection.configuration == "Release")
        #expect(selection.target == "App")
    }
}
