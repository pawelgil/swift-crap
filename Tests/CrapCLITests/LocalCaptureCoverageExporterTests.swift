import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct LocalCaptureCoverageExporterTests {
    @Test func `package capture does not export Xcode coverage`() throws {
        let sut = LocalCaptureCoverageExporter(exporter: UnusedNativeExporter())

        let result = try sut.read(request: makeRequest(xcode: nil), paths: makePaths(), contexts: [])

        #expect(result.isEmpty)
    }

    @Test func `Xcode capture freezes declared result bundle`() throws {
        let bytes = Data("precise native evidence".utf8)
        let sut = LocalCaptureCoverageExporter(exporter: StubNativeExporter(data: bytes))

        let result = try sut.read(request: makeRequest(), paths: makePaths(), contexts: [])

        #expect(result == ["/repo/Tests.xcresult": bytes])
    }

    @Test func `undeclared result bundle is rejected before exporting`() throws {
        let sut = LocalCaptureCoverageExporter(exporter: UnusedNativeExporter())

        #expect(throws: ProvenanceError.invalid("Xcode result bundle must be a declared coverage artifact")) {
            try sut.read(request: makeRequest(), paths: makePaths(coverage: ["/repo/Other.xcresult"]), contexts: [])
        }
    }

    @Test func `native export failure is not replaced by aggregate coverage`() throws {
        let sut = LocalCaptureCoverageExporter(exporter: UnusedNativeExporter())

        #expect(throws: CocoaError(.fileReadNoSuchFile)) {
            try sut.read(request: makeRequest(), paths: makePaths(), contexts: [])
        }
    }

    private func makeRequest(
        xcode: XcodeSelection? = XcodeSelection(project: "/repo/App.xcodeproj", scheme: "App", target: "App"),
    ) -> CaptureRequest {
        CaptureRequest(
            root: "/repo",
            output: "/repo/receipt.json",
            coverage: ["/repo/Tests.xcresult"],
            buildDescription: nil,
            buildContext: nil,
            command: ["xcodebuild", "-resultBundlePath", "/repo/Tests.xcresult", "test"],
            xcode: xcode,
        )
    }

    private func makePaths(coverage: [String] = ["/repo/Tests.xcresult"]) -> CapturePaths {
        CapturePaths(root: "/repo", output: "/repo/receipt.json", coverage: coverage)
    }
}

private struct UnusedNativeExporter: XcodeNativeCoverageExporting {
    func export(
        resultBundle _: String,
        selection _: XcodeSelection,
        contexts _: [CompilerContext],
        command _: [String],
        root _: String,
    ) throws -> Data {
        throw CocoaError(.fileReadNoSuchFile)
    }
}

private struct StubNativeExporter: XcodeNativeCoverageExporting {
    let data: Data

    func export(
        resultBundle _: String,
        selection _: XcodeSelection,
        contexts _: [CompilerContext],
        command _: [String],
        root _: String,
    ) -> Data {
        data
    }
}
