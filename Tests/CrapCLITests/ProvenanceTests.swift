@testable import CrapCLI
import Foundation
import Testing

struct ProvenanceTests {
    @Test func `snapshot detects changed source with identical length`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = fixture.appendingPathComponent("Subject.swift")
        try Data("func a() {}".utf8).write(to: source)
        let before = try InputSnapshot().read(root: fixture.path, excluding: [])
        try Data("func b() {}".utf8).write(to: source)
        #expect(try InputSnapshot().read(root: fixture.path, excluding: []) != before)
    }

    @Test func `snapshot detects added deleted files and configuration`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let before = try InputSnapshot().read(root: fixture.path, excluding: [])
        let configuration = fixture.appendingPathComponent("Settings.xcconfig")
        try Data("SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG".utf8).write(to: configuration)
        let after = try InputSnapshot().read(root: fixture.path, excluding: [])
        #expect(before != after)
        try FileManager.default.removeItem(at: configuration)
        #expect(try InputSnapshot().read(root: fixture.path, excluding: []) == before)
    }

    @Test func `snapshot ignores build products but includes tests`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        for folder in [".build", "DerivedData", "Tests"] {
            let directory = fixture.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("input".utf8).write(to: directory.appendingPathComponent("File.swift"))
        }
        let paths = try InputSnapshot().read(root: fixture.path, excluding: []).keys.sorted()
        #expect(paths == ["Tests/File.swift"])
    }

    @Test func `snapshot rejects external symlink`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try FileManager.default.createSymbolicLink(
            atPath: fixture.appendingPathComponent("external").path,
            withDestinationPath: "/etc/hosts",
        )
        #expect(throws: (any Error).self) { try InputSnapshot().read(root: fixture.path, excluding: []) }
    }

    @Test func `snapshot prunes build directory symlink before following it`() throws {
        let fixture = try makeFixture()
        let external = try makeFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: external)
        }
        try Data("product".utf8).write(to: external.appendingPathComponent("App"))
        try FileManager.default.createSymbolicLink(
            at: fixture.appendingPathComponent(".build"),
            withDestinationURL: external,
        )

        #expect(try InputSnapshot().read(root: fixture.path, excluding: []).isEmpty)
    }

    @Test func `snapshot excludes an output symlink before following it`() throws {
        let fixture = try makeFixture()
        let external = try makeFixture().appendingPathComponent("receipt.json")
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: external.deletingLastPathComponent())
        }
        try Data("receipt".utf8).write(to: external)
        let output = fixture.appendingPathComponent("receipt.json")
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: external)

        #expect(try InputSnapshot().read(root: fixture.path, excluding: [output.path]).isEmpty)
    }

    @Test func `snapshot follows contained relative directory symlink`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let common = fixture.appendingPathComponent("Common")
        let plugin = fixture.appendingPathComponent("Plugin")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: false)
        try Data("func run() {}".utf8).write(to: common.appendingPathComponent("File.swift"))
        try FileManager.default.createSymbolicLink(
            atPath: plugin.appendingPathComponent("Common").path,
            withDestinationPath: "../Common",
        )

        let result = try InputSnapshot().read(root: fixture.path, excluding: [])

        #expect(Set(result.keys) == ["Common/File.swift", "Plugin/Common/File.swift"])
    }

    @Test func `content digest uses sha256`() {
        #expect(ContentDigest().hash(Data("abc".utf8)) ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
