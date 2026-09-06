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
            try XcodeProjectDescriber().decode(data, target: "App", compiler: "/selected/swiftc")
        }
    }

    @Test func `resolved compiler takes precedence over supplemental Metal toolchain`() throws {
        let data = try metadata([
            "/project/Included.swift": [
                "LanguageDialect": "Xcode.SourceCodeLanguage.Swift",
                "swiftASTCommandArguments": ["-working-directory", "/project", "/project/Included.swift"],
                "swiftASTModuleName": "App",
                "toolchains": [
                    "com.apple.dt.toolchain.Metal.32023.883",
                    "com.apple.dt.toolchain.XcodeDefault",
                ],
            ],
        ])

        let result = try XcodeProjectDescriber().decode(data, target: "App", compiler: "/selected/swiftc")

        #expect(result.compilerContexts.map(\.compiler) == ["/selected/swiftc"])
    }

    @Test func `missing resolved compiler fails closed`() {
        #expect(throws: SourceSelectionError.invalidXcodeMetadata("target has no SWIFT_EXEC or TOOLCHAIN_DIR")) {
            try XcodeProjectDescriber().compiler(buildSettings: [:])
        }
    }

    @Test(arguments: ["SWIFT_EXEC", "TOOLCHAIN_DIR"])
    func `invalid resolved compiler fails closed`(setting: String) {
        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "\(setting) does not identify an executable Swift compiler",
        )) {
            try XcodeProjectDescriber().compiler(buildSettings: [setting: "/missing"])
        }
    }

    @Test func `relative toolchain directory fails before resolving against current directory`() throws {
        let toolchain = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let compiler = toolchain.appendingPathComponent("usr/bin/swiftc")
        defer { try? FileManager.default.removeItem(at: toolchain) }
        try FileManager.default.createDirectory(
            at: compiler.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("#!/bin/sh\n".utf8).write(to: compiler)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: compiler.path)
        let relativeToolchain = relativePath(to: toolchain.path)
        let resolvedCompiler = URL(fileURLWithPath: relativeToolchain).appendingPathComponent("usr/bin/swiftc").path
        #expect(FileManager.default.isExecutableFile(atPath: resolvedCompiler))

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "TOOLCHAIN_DIR does not identify an executable Swift compiler",
        )) {
            try XcodeProjectDescriber().compiler(buildSettings: ["TOOLCHAIN_DIR": relativeToolchain])
        }
    }

    private func relativePath(to path: String) -> String {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).pathComponents
        let target = URL(fileURLWithPath: path).pathComponents
        let shared = zip(base, target).prefix { $0.0 == $0.1 }.count
        return (Array(repeating: "..", count: base.count - shared) + Array(target.dropFirst(shared)))
            .joined(separator: "/")
    }

    private func metadata(_ entries: [String: [String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["App": entries], options: [.sortedKeys])
    }
}
