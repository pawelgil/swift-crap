import CrapApplication
import Foundation

struct XcodeResolvedBuildSettings {
    let buildProductPath: String
    let compiler: String
    let moduleName: String
    let objectFileDirectory: String
    let projectDirectory: String

    init(
        _ settings: [String: String],
        selection: XcodeSelection,
        workingDirectory: String? = nil,
    ) throws {
        let project = try Self.absolute("PROJECT_FILE_PATH", in: settings)
        let selected = try CanonicalPath().resolve(selection.project, relativeTo: workingDirectory)
        try Self.validateProject(project, selected: selected)
        projectDirectory = try Self.absolute("PROJECT_DIR", in: settings)
        objectFileDirectory = try Self.absolute("OBJECT_FILE_DIR_normal", in: settings)
        moduleName = try Self.required("PRODUCT_MODULE_NAME", in: settings)
        compiler = try Self.compiler(settings)
        buildProductPath = try Self.product(settings)
    }

    private static func validateProject(_ project: String, selected: String) throws {
        guard project == selected else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "PROJECT_FILE_PATH does not match selected Xcode project",
            )
        }
    }

    static func compiler(_ settings: [String: String]) throws -> String {
        if let swiftCompiler = nonempty(settings["SWIFT_EXEC"]) {
            return try compiler(path: swiftCompiler, setting: "SWIFT_EXEC")
        }
        guard let toolchain = nonempty(settings["TOOLCHAIN_DIR"]) else {
            throw SourceSelectionError.invalidXcodeMetadata("target has no SWIFT_EXEC or TOOLCHAIN_DIR")
        }
        guard toolchain.hasPrefix("/") else {
            throw SourceSelectionError
                .invalidXcodeMetadata("TOOLCHAIN_DIR does not identify an executable Swift compiler")
        }
        let path = URL(fileURLWithPath: toolchain, isDirectory: true).appendingPathComponent("usr/bin/swiftc").path
        return try compiler(path: path, setting: "TOOLCHAIN_DIR")
    }

    private static func product(_ settings: [String: String]) throws -> String {
        let directory = try absolute("TARGET_BUILD_DIR", in: settings)
        let executable = try required("EXECUTABLE_PATH", in: settings)
        guard !executable.hasPrefix("/") else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "EXECUTABLE_PATH is not contained by TARGET_BUILD_DIR",
            )
        }
        let path = try CanonicalPath().resolve(executable, relativeTo: directory)
        guard path.hasPrefix(directory + "/") else {
            throw SourceSelectionError.invalidXcodeMetadata(
                "EXECUTABLE_PATH is not contained by TARGET_BUILD_DIR",
            )
        }
        return path
    }

    private static func absolute(_ name: String, in settings: [String: String]) throws -> String {
        let value = try required(name, in: settings)
        guard value.hasPrefix("/") else {
            throw SourceSelectionError.invalidXcodeMetadata("target has no absolute \(name)")
        }
        return try CanonicalPath().resolve(value)
    }

    private static func required(_ name: String, in settings: [String: String]) throws -> String {
        guard let value = nonempty(settings[name]) else {
            throw SourceSelectionError.invalidXcodeMetadata("target has no \(name)")
        }
        return value
    }

    private static func compiler(path: String, setting: String) throws -> String {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw SourceSelectionError.invalidXcodeMetadata("\(setting) does not identify an executable Swift compiler")
        }
        return try CanonicalPath().resolvePreservingLastComponent(path)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
