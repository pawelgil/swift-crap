import Foundation

struct XcodeResultBundleCopy {
    func read<Value>(at path: String, operation: (String) throws -> Value) throws -> Value {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appendingPathComponent("Read.xcresult")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)
        return try operation(copy.path)
    }
}
