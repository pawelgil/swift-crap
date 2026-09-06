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

    @Test func `missing compiler arguments identify the rejected source`() throws {
        let data = try metadata([
            "/project/Included.swift": [
                "LanguageDialect": "Xcode.SourceCodeLanguage.Swift",
                "swiftASTModuleName": "App",
                "toolchains": ["com.apple.dt.toolchain.XcodeDefault"],
            ],
        ])

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "source /project/Included.swift has no Swift compiler arguments",
        )) {
            try XcodeProjectDescriber().decode(data, target: "App")
        }
    }

    @Test func `multiple toolchains fail with their identifiers`() throws {
        let data = try metadata([
            "/project/Included.swift": [
                "LanguageDialect": "Xcode.SourceCodeLanguage.Swift",
                "swiftASTCommandArguments": ["-working-directory", "/project", "/project/Included.swift"],
                "swiftASTModuleName": "App",
                "toolchains": ["toolchain.first", "toolchain.second"],
            ],
        ])

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "source /project/Included.swift has ambiguous toolchains: toolchain.first, toolchain.second",
        )) {
            try XcodeProjectDescriber().decode(data, target: "App")
        }
    }

    private func metadata(_ entries: [String: [String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["App": entries], options: [.sortedKeys])
    }
}
