import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct ReceiptVerifierTests {
    @Test func `receipt rejects changed artifact and project input`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("File.swift")
        let coverage = fixture.appendingPathComponent("coverage.json")
        let output = fixture.appendingPathComponent("receipt.json")
        try Data("func run() {}".utf8).write(to: source)
        try Data("coverage".utf8).write(to: coverage)
        let inputs = try InputSnapshot().read(root: fixture.path, excluding: [coverage.path, output.path])
        let receipt = try CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: fixture.path,
            command: ["tests"],
            inputs: inputs,
            artifacts: [coverage.path: ArtifactDigest().read(at: coverage.path)],
            contexts: [CompilerContext(
                compiler: "/compiler",
                arguments: [],
                directory: fixture.path,
                sources: [source.path],
                moduleName: "App",
            )],
            callables: [],
        )
        try ReceiptVerifier().validate(receipt, at: output.path, coverage: [coverage.path])
        try Data("changed".utf8).write(to: coverage)
        #expect(throws: ProvenanceError.invalid("coverage artifact is not captured or has changed: \(coverage.path)")) {
            try ReceiptVerifier().validate(receipt, at: output.path, coverage: [coverage.path])
        }
        try Data("coverage".utf8).write(to: coverage)
        try Data("func new() {}".utf8).write(to: source)
        #expect(throws: ProvenanceError.invalid("project inputs differ from captured sources")) {
            try ReceiptVerifier().validate(receipt, at: output.path, coverage: [coverage.path])
        }
    }

    @Test func `artifact directory digest detects nested changes`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let data = fixture.appendingPathComponent("chunk")
        try Data("first".utf8).write(to: data)
        let initial = try ArtifactDigest().read(at: fixture.path)
        try Data("other".utf8).write(to: data)
        #expect(try ArtifactDigest().read(at: fixture.path) != initial)
    }

    @Test func `artifact aliases validate against canonical receipt key`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("File.swift")
        let coverage = fixture.appendingPathComponent("coverage.json")
        let output = fixture.appendingPathComponent("receipt.json")
        try Data("func run() {}".utf8).write(to: source)
        try Data("coverage".utf8).write(to: coverage)
        let inputs = try InputSnapshot().read(root: fixture.path, excluding: [coverage.path, output.path])
        let receipt = try CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: fixture.path,
            command: ["tests"],
            inputs: inputs,
            artifacts: [coverage.path: ArtifactDigest().read(at: coverage.path)],
            contexts: [CompilerContext(
                compiler: "/compiler",
                arguments: [],
                directory: fixture.path,
                sources: [source.path],
                moduleName: "App",
            )],
            callables: [],
        )
        let alias = fixture.appendingPathComponent("coverage-alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: coverage)

        try ReceiptVerifier().validate(receipt, at: output.path, coverage: [alias.path])
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.resolvingSymlinksInPath()
    }
}
