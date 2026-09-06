import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct CapturedCoverageReceiptTests {
    @Test func `legacy receipt decodes without frozen exports`() throws {
        let receipt = makeReceipt(root: "/repo", exports: nil)
        let data = try JSONEncoder().encode(receipt)
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let decoded = try JSONDecoder().decode(CaptureReceipt.self, from: data)

        #expect(document["coverageExports"] == nil)
        #expect(decoded.coverageExports == nil)
    }

    @Test func `frozen evidence survives receipt serialization`() throws {
        let exports = ["/repo/Tests.xcresult": Data("native compiler coverage".utf8)]
        let data = try JSONEncoder().encode(makeReceipt(root: "/repo", exports: exports))

        let decoded = try JSONDecoder().decode(CaptureReceipt.self, from: data)

        #expect(decoded.coverageExports == exports)
    }

    @Test func `unbound frozen evidence is rejected`() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let receipt = makeReceipt(root: directory.path, exports: ["/other/Tests.xcresult": Data([1])])

        #expect(throws: ProvenanceError.invalid("coverage export is not bound to a captured artifact")) {
            try ReceiptVerifier().validate(
                receipt,
                at: directory.appendingPathComponent("receipt.json").path,
                coverage: [],
            )
        }
    }

    @Test func `empty frozen evidence is rejected before scoring`() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let receipt = makeReceipt(root: directory.path, exports: [directory.path + "/Tests.xcresult": Data()])

        #expect(throws: ProvenanceError.invalid("capture contains empty coverage export")) {
            try ReceiptVerifier().validate(
                receipt,
                at: directory.appendingPathComponent("receipt.json").path,
                coverage: [],
            )
        }
    }

    private func makeReceipt(root: String, exports: [String: Data]?) -> CaptureReceipt {
        CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: root,
            command: ["tests"],
            inputs: ["File.swift": "source-digest"],
            artifacts: [root + "/Tests.xcresult": "artifact-digest"],
            contexts: [CompilerContext(
                compiler: "/compiler",
                arguments: [],
                directory: root,
                sources: [root + "/File.swift"],
                moduleName: "App",
            )],
            callables: [],
            coverageExports: exports,
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.resolvingSymlinksInPath()
    }
}
