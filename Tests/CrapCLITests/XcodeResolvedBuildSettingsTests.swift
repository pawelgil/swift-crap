import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct XcodeResolvedBuildSettingsTests {
    @Test func `missing resolved compiler fails closed`() {
        #expect(throws: SourceSelectionError.invalidXcodeMetadata("target has no SWIFT_EXEC or TOOLCHAIN_DIR")) {
            try XcodeResolvedBuildSettings.compiler([:])
        }
    }

    @Test(arguments: ["SWIFT_EXEC", "TOOLCHAIN_DIR"])
    func `invalid resolved compiler fails closed`(setting: String) {
        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "\(setting) does not identify an executable Swift compiler",
        )) {
            try XcodeResolvedBuildSettings.compiler([setting: "/missing"])
        }
    }

    @Test func `matching settings resolve exact target identity and product`() throws {
        let fixture = try ResolvedSettingsFixture()

        let result = try XcodeResolvedBuildSettings(
            fixture.settings,
            selection: fixture.selection,
            workingDirectory: fixture.directory.path,
        )

        #expect(result.projectDirectory == fixture.directory.path)
        #expect(result.moduleName == "Fixture")
        #expect(result.objectFileDirectory == fixture.objects.path)
        #expect(result.buildProductPath == fixture.product.path)
        #expect(result.compiler == fixture.compiler.path)
    }

    @Test func `settings for another project fail closed`() throws {
        let fixture = try ResolvedSettingsFixture()
        var settings = fixture.settings
        settings["PROJECT_FILE_PATH"] = fixture.directory.appendingPathComponent("Other.xcodeproj").path

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "PROJECT_FILE_PATH does not match selected Xcode project",
        )) {
            try XcodeResolvedBuildSettings(
                settings,
                selection: fixture.selection,
                workingDirectory: fixture.directory.path,
            )
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
            try XcodeResolvedBuildSettings.compiler(["TOOLCHAIN_DIR": relativeToolchain])
        }
    }

    @Test(arguments: ["/absolute/product", "../escaped/product"])
    func `unsafe executable path fails closed`(_ executable: String) throws {
        let fixture = try ResolvedSettingsFixture()
        var settings = fixture.settings
        settings["EXECUTABLE_PATH"] = executable

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "EXECUTABLE_PATH is not contained by TARGET_BUILD_DIR",
        )) {
            try XcodeResolvedBuildSettings(
                settings,
                selection: fixture.selection,
                workingDirectory: fixture.directory.path,
            )
        }
    }

    private func relativePath(to path: String) -> String {
        let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).pathComponents
        let target = URL(fileURLWithPath: path).pathComponents
        let shared = zip(base, target).prefix { $0.0 == $0.1 }.count
        return (Array(repeating: "..", count: base.count - shared) + Array(target.dropFirst(shared)))
            .joined(separator: "/")
    }
}

private final class ResolvedSettingsFixture {
    let compiler: URL
    let directory: URL
    let objects: URL
    let product: URL
    let project: URL
    let selection: XcodeSelection
    let settings: [String: String]

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        project = directory.appendingPathComponent("Fixture.xcodeproj", isDirectory: true)
        objects = directory.appendingPathComponent("Derived/Objects-normal", isDirectory: true)
        let products = directory.appendingPathComponent("Derived/Products", isDirectory: true)
        product = products.appendingPathComponent("Fixture.framework/Fixture")
        compiler = directory.appendingPathComponent("Toolchain/usr/bin/swiftc")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: compiler.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("#!/bin/sh\n".utf8).write(to: compiler)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: compiler.path)
        selection = XcodeSelection(project: project.path, scheme: "Fixture", target: "Fixture")
        settings = [
            "EXECUTABLE_PATH": "Fixture.framework/Fixture",
            "OBJECT_FILE_DIR_normal": objects.path,
            "PRODUCT_MODULE_NAME": "Fixture",
            "PROJECT_DIR": directory.path,
            "PROJECT_FILE_PATH": project.path,
            "SWIFT_EXEC": compiler.path,
            "TARGET_BUILD_DIR": products.path,
        ]
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
