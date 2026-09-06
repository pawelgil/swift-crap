@testable import CrapCLI
import Foundation
import Testing

struct XcodeProjectDescriberTests {
    @Test func `source membership does not require compiler context metadata`() throws {
        let data = try metadata([
            "/project/Included.swift": ["LanguageDialect": "Xcode.SourceCodeLanguage.Swift"],
            "/project/ObjectiveC.m": ["LanguageDialect": "Xcode.SourceCodeLanguage.Objective-C"],
        ])

        let result = try XcodeProjectDescriber().sourceFiles(data, target: "App")

        #expect(result == ["/project/Included.swift"])
    }

    private func metadata(_ entries: [String: [String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["App": entries], options: [.sortedKeys])
    }
}
