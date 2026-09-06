import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct XcodeBuildLogReaderTests {
    @Test func `actual Swift driver response becomes compiler context`() throws {
        let fixture = try XcodeBuildLogFixture()
        let compiler = try fixture.executable("Selected Toolchain/usr/bin/swiftc")
        let first = try fixture.source("Sources/First File.swift")
        let second = try fixture.source("Sources/Second.swift")
        let fileList = try fixture.fileList([first, second])
        let command = [
            escaped(compiler), "-module-name", "Fixture", "@\(escaped(fileList))",
            "-DDEBUG", "-sdk", "/SDKs/iPhoneSimulator.sdk", "-target", "arm64-apple-ios-simulator",
            "-output-file-map", "\(escaped(fixture.directory.path))/Objects-normal/Fixture.json",
            "-working-directory", escaped(fixture.directory.path),
        ].joined(separator: " ")
        let data = try buildLog("""
        SwiftDriver Fixture normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Fixture' from project 'App')
            cd \(fixture.directory.path)
            builtin-SwiftDriver -- \(command)
        """)

        let result = try XcodeBuildLogReader().decode(
            data,
            project: "/project/App.xcodeproj",
            settings: fixture.settings(compiler),
            target: "Fixture",
        )

        let context = try #require(result.compilerContexts.first)
        #expect(result.sourceFiles == [first, second])
        #expect(context.compiler == compiler)
        #expect(context.moduleName == "Fixture")
        #expect(context.directory == fixture.directory.path)
        #expect(context.sources == [first, second])
        #expect(context.arguments.contains("-DDEBUG"))
        #expect(context.arguments.contains("arm64-apple-ios-simulator"))
        #expect(!context.arguments.contains(where: { $0.hasPrefix("@") }))
    }

    @Test func `different compiler from resolved settings fails closed`() throws {
        let fixture = try XcodeBuildLogFixture()
        let selected = try fixture.executable("Selected/usr/bin/swiftc")
        let logged = try fixture.executable("Logged/usr/bin/swiftc")
        let source = try fixture.source("Sources/Included.swift")
        let data = try buildLog("""
        SwiftDriver Fixture normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Fixture' from project 'App')
            builtin-SwiftDriver -- \(logged) -module-name Fixture \(source) -output-file-map \(
                fixture.directory.path
            )/Objects-normal/Fixture.json -working-directory \(fixture.directory.path)
        """)

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "target Fixture SwiftDriver compiler differs from resolved build settings",
        )) {
            try XcodeBuildLogReader().decode(
                data,
                project: "/project/App.xcodeproj",
                settings: fixture.settings(selected),
                target: "Fixture",
            )
        }
    }

    @Test func `result without selected target compilation fails closed`() throws {
        let fixture = try XcodeBuildLogFixture()
        let compiler = try fixture.executable("Toolchain/usr/bin/swiftc")
        let data = try buildLog("CompileSwift normal arm64")

        #expect(throws: SourceSelectionError.invalidXcodeMetadata(
            "result bundle has no SwiftDriver invocation for target Fixture; rebuild the target during capture",
        )) {
            try XcodeBuildLogReader().decode(
                data,
                project: "/project/App.xcodeproj",
                settings: fixture.settings(compiler),
                target: "Fixture",
            )
        }
    }

    @Test func `same target name from another project is ignored`() throws {
        let fixture = try XcodeBuildLogFixture()
        let compiler = try fixture.executable("Toolchain/usr/bin/swiftc")
        let source = try fixture.source("Sources/Included.swift")
        let selected = driver(compiler: compiler, source: source, directory: fixture.directory.path, project: "App")
        let dependency = driver(
            compiler: "/different/swiftc",
            source: source,
            directory: fixture.directory.path,
            project: "Dependency",
        )
        let data = try buildLog([dependency, selected])

        let result = try XcodeBuildLogReader().decode(
            data,
            project: "/project/App.xcodeproj",
            settings: fixture.settings(compiler),
            target: "Fixture",
        )

        #expect(result.compilerContexts.count == 1)
        #expect(result.compilerContexts.first?.compiler == compiler)
    }

    @Test func `same project and target names from another directory are ignored`() throws {
        let fixture = try XcodeBuildLogFixture()
        let compiler = try fixture.executable("Toolchain/usr/bin/swiftc")
        let source = try fixture.source("Sources/Included.swift")
        let selected = driver(compiler: compiler, source: source, directory: fixture.directory.path, project: "App")
        let dependency = driver(compiler: compiler, source: source, directory: "/dependency", project: "App")
        let data = try buildLog([dependency, selected])

        let result = try XcodeBuildLogReader().decode(
            data,
            project: "/project/App.xcodeproj",
            settings: fixture.settings(compiler),
            target: "Fixture",
        )

        #expect(result.compilerContexts.count == 1)
        #expect(result.compilerContexts.first?.directory == fixture.directory.path)
    }

    @Test func `same project target and directory with another object root is ignored`() throws {
        let fixture = try XcodeBuildLogFixture()
        let compiler = try fixture.executable("Toolchain/usr/bin/swiftc")
        let source = try fixture.source("Sources/Included.swift")
        let selected = driver(compiler: compiler, source: source, directory: fixture.directory.path, project: "App")
        let dependency = selected.replacingOccurrences(of: "/Objects-normal/", with: "/Other-Objects/")
        let data = try buildLog([dependency, selected])

        let result = try XcodeBuildLogReader().decode(
            data,
            project: "/project/App.xcodeproj",
            settings: fixture.settings(compiler),
            target: "Fixture",
        )

        #expect(result.compilerContexts.count == 1)
        #expect(result.compilerContexts.first?.arguments.contains(where: { $0.contains("/Objects-normal/") }) == true)
    }

    private func buildLog(_ commandDetails: String) throws -> Data {
        try buildLog([commandDetails])
    }

    private func buildLog(_ commandDetails: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "subsections": [["messages": commandDetails.map { ["commandDetails": $0] }]],
        ])
    }

    private func driver(compiler: String, source: String, directory: String, project: String) -> String {
        """
        SwiftDriver Fixture normal arm64 com.apple.xcode.tools.swift.compiler (in target 'Fixture' from project '\(
            project
        )')
            builtin-SwiftDriver -- \(compiler) -module-name Fixture \(source) -output-file-map \(
                directory
            )/Objects-normal/Fixture.json -working-directory \(directory)
        """
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: " ", with: "\\ ")
    }
}

private final class XcodeBuildLogFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func executable(_ path: String) throws -> String {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func fileList(_ sources: [String]) throws -> String {
        let url = directory.appendingPathComponent("Fixture.SwiftFileList")
        try Data((sources.map { $0.replacingOccurrences(of: " ", with: "\\ ") }.joined(separator: "\n") + "\n").utf8)
            .write(to: url)
        return url.path
    }

    func settings(_ compiler: String) throws -> XcodeResolvedBuildSettings {
        let objects = directory.appendingPathComponent("Objects-normal", isDirectory: true)
        let products = directory.appendingPathComponent("Products", isDirectory: true)
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        return try XcodeResolvedBuildSettings(
            [
                "EXECUTABLE_PATH": "Fixture.framework/Fixture",
                "OBJECT_FILE_DIR_normal": objects.path,
                "PRODUCT_MODULE_NAME": "Fixture",
                "PROJECT_DIR": directory.path,
                "PROJECT_FILE_PATH": "/project/App.xcodeproj",
                "SWIFT_EXEC": compiler,
                "TARGET_BUILD_DIR": products.path,
            ],
            selection: XcodeSelection(project: "/project/App.xcodeproj", scheme: "App", target: "Fixture"),
        )
    }

    func source(_ path: String) throws -> String {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("func value() {}\n".utf8).write(to: url)
        return url.path
    }
}
