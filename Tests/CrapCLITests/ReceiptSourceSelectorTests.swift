import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct ReceiptSourceSelectorTests {
    @Test func `captured Xcode selection reuses compiler source membership`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sut = ReceiptSourceSelector(receipt: fixture.receipt)

        let result = try sut.select(SourceSelectionRequest(scope: .xcode(fixture.selection)))

        #expect(result == SelectedSources(
            root: fixture.root.path,
            files: [SelectedSource(path: fixture.source.path, relativePath: "Included.swift")],
        ))
    }

    @Test func `captured Xcode selection rejects a different configuration`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sut = ReceiptSourceSelector(receipt: fixture.receipt)
        let selection = XcodeSelection(
            project: fixture.selection.project,
            scheme: fixture.selection.scheme,
            target: fixture.selection.target,
            configuration: "Release",
            destination: fixture.selection.destination,
        )

        do {
            _ = try sut.select(SourceSelectionRequest(scope: .xcode(selection)))
            Issue.record("expected mismatched configuration to fail")
        } catch {
            #expect(String(describing: error) == "invalid provenance: requested Xcode selection differs from capture")
        }
    }

    @Test func `captured Xcode selection applies exclusions without metadata discovery`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sut = ReceiptSourceSelector(receipt: fixture.receipt)

        let result = try sut.select(SourceSelectionRequest(
            scope: .xcode(fixture.selection),
            exclusions: ["Included.swift"],
        ))

        #expect(result.files.isEmpty)
    }

    @Test func `Xcode selection requires captured Xcode identity`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let receipt = CaptureReceipt(
            schemaVersion: fixture.receipt.schemaVersion,
            metric: fixture.receipt.metric,
            root: fixture.receipt.root,
            command: fixture.receipt.command,
            inputs: fixture.receipt.inputs,
            artifacts: fixture.receipt.artifacts,
            contexts: fixture.receipt.contexts,
            callables: fixture.receipt.callables,
        )

        do {
            _ = try ReceiptSourceSelector(receipt: receipt)
                .select(SourceSelectionRequest(scope: .xcode(fixture.selection)))
            Issue.record("expected missing Xcode identity to fail")
        } catch {
            #expect(String(describing: error) == "invalid provenance: receipt has no captured Xcode selection")
        }
    }

    private func makeFixture() throws -> ReceiptSourceFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-receipt-source-\(UUID())", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let project = root.appendingPathComponent("Empty.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("Included.swift")
        try Data("func included() {}".utf8).write(to: source)
        let selection = XcodeSelection(project: project.path, scheme: "App", target: "App")
        let context = CompilerContext(
            compiler: "/compiler",
            arguments: [],
            directory: root.path,
            sources: [source.path],
            moduleName: "App",
        )
        let receipt = CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: root.path,
            command: ["xcodebuild"],
            inputs: ["Included.swift": "digest"],
            artifacts: ["/coverage": "digest"],
            contexts: [context],
            callables: [],
            xcode: selection,
        )
        return ReceiptSourceFixture(root: root, source: source, selection: selection, receipt: receipt)
    }
}

private struct ReceiptSourceFixture {
    let root: URL
    let source: URL
    let selection: XcodeSelection
    let receipt: CaptureReceipt
}
