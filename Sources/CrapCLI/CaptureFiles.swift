import Foundation

struct CaptureFiles {
    let directory: URL
    let outputURL: URL
    let errorURL: URL
    let scratchURL: URL
    let cacheURL: URL
    let output: FileHandle
    let error: FileHandle

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        outputURL = directory.appendingPathComponent("stdout")
        errorURL = directory.appendingPathComponent("stderr")
        scratchURL = directory.appendingPathComponent("scratch", isDirectory: true)
        cacheURL = directory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        output = try FileHandle(forWritingTo: outputURL)
        error = try FileHandle(forWritingTo: errorURL)
    }

    func close() {
        try? output.close()
        try? error.close()
    }

    func outputData() throws -> Data {
        try Data(contentsOf: outputURL)
    }

    func errorData() throws -> Data {
        try Data(contentsOf: errorURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
