import CrapApplication
import Foundation

struct XcodeCoverageFileReader: FileReading {
    private let fileReader: any FileReading
    private let exporter: any XCCovExporting

    init(
        fileReader: any FileReading = LocalFileReader(),
        exporter: any XCCovExporting = XCCovExporter(),
    ) {
        self.fileReader = fileReader
        self.exporter = exporter
    }

    func read(at path: String) throws -> Data {
        if URL(fileURLWithPath: path).pathExtension.lowercased() == "xcresult" {
            return try exporter.report(at: path)
        }
        return try fileReader.read(at: path)
    }
}
