import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct CapturedBuildIdentityTests {
    @Test func `source inventory and output arguments do not change build identity`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let first = makeReceipt(
            root: fixture,
            arguments: ["-D", "DEBUG", "-o", "/tmp/first.o", fixture.appendingPathComponent("First.swift").path],
            sources: [fixture.appendingPathComponent("First.swift").path],
        )
        let second = makeReceipt(
            root: fixture,
            arguments: ["-D", "DEBUG", "-o", "/tmp/second.o", fixture.appendingPathComponent("Second.swift").path],
            sources: [fixture.appendingPathComponent("Second.swift").path],
        )
        let selection = SourceSelectionRequest(scope: .project(fixture.path))
        let firstIdentity = try identity(first, selection)
        let secondIdentity = try identity(second, selection)

        #expect(firstIdentity == secondIdentity)
    }

    @Test func `different root or compiler arguments change build identity`() throws {
        let firstRoot = try makeFixture()
        let secondRoot = try makeFixture()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let first = makeReceipt(root: firstRoot, arguments: ["-D", "DEBUG"])
        let otherRoot = makeReceipt(root: secondRoot, arguments: ["-D", "DEBUG"])
        let otherArguments = makeReceipt(root: firstRoot, arguments: ["-D", "RELEASE"])
        let firstIdentity = try identity(first, .init(scope: .project(firstRoot.path)))
        let otherRootIdentity = try identity(otherRoot, .init(scope: .project(secondRoot.path)))
        let otherArgumentsIdentity = try identity(otherArguments, .init(scope: .project(firstRoot.path)))

        #expect(firstIdentity != otherRootIdentity)
        #expect(firstIdentity != otherArgumentsIdentity)
    }

    @Test func `different Xcode configuration changes build identity`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let project = fixture.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let receipt = makeReceipt(root: fixture, arguments: ["-D", "DEBUG"])
        let debug = SourceSelectionRequest(scope: .xcode(XcodeSelection(
            project: project.path,
            scheme: "App",
            target: "App",
            configuration: "Debug",
        )))
        let release = SourceSelectionRequest(scope: .xcode(XcodeSelection(
            project: project.path,
            scheme: "App",
            target: "App",
            configuration: "Release",
        )))
        let debugIdentity = try identity(receipt, debug)
        let releaseIdentity = try identity(receipt, release)

        #expect(debugIdentity != releaseIdentity)
    }

    @Test func `compiler context order does not change build identity`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let firstContext = makeContext(root: fixture, module: "First", arguments: ["-D", "FIRST"])
        let secondContext = makeContext(root: fixture, module: "Second", arguments: ["-D", "SECOND"])
        let first = makeReceipt(root: fixture, contexts: [firstContext, secondContext])
        let second = makeReceipt(root: fixture, contexts: [secondContext, firstContext])
        let selection = SourceSelectionRequest(scope: .project(fixture.path))
        let firstIdentity = try identity(first, selection)
        let secondIdentity = try identity(second, selection)

        #expect(firstIdentity == secondIdentity)
    }

    private func identity(_ receipt: CaptureReceipt, _ selection: SourceSelectionRequest) throws -> String {
        try CapturedBuildIdentity().read(receipt: receipt, selection: selection)
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-build-identity-\(UUID())", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeReceipt(
        root: URL,
        arguments: [String],
        sources: [String] = [],
    ) -> CaptureReceipt {
        makeReceipt(root: root, contexts: [makeContext(
            root: root,
            module: "App",
            arguments: arguments,
            sources: sources,
        )])
    }

    private func makeReceipt(root: URL, contexts: [CompilerContext]) -> CaptureReceipt {
        CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: root.path,
            command: ["build"],
            inputs: ["input": "digest"],
            artifacts: ["artifact": "digest"],
            contexts: contexts,
            callables: [],
        )
    }

    private func makeContext(
        root: URL,
        module: String,
        arguments: [String],
        sources: [String] = [],
    ) -> CompilerContext {
        CompilerContext(
            compiler: "/compiler/swiftc",
            arguments: arguments,
            directory: root.path,
            sources: sources,
            moduleName: module,
        )
    }
}
