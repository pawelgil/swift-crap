import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct XcodeCoverageFileReaderTests {
    @Test func `xcresult path exports its embedded report`() throws {
        let path = "/project/Tests.xcresult"
        let expected = Data("xccov".utf8)
        let exporter = XCCovExportingSpy(data: expected)
        let sut = createSUT(exporter: exporter)

        let result = try sut.read(at: path)

        #expect(result == expected)
        #expect(exporter.paths == [path])
    }

    @Test func `ordinary coverage path reads file data`() throws {
        let path = "/project/coverage.json"
        let expected = Data("json".utf8)
        let reader = FileReadingSpy(data: expected)
        let sut = createSUT(fileReader: reader)

        let result = try sut.read(at: path)

        #expect(result == expected)
        #expect(reader.paths == [path])
    }

    private func createSUT(
        fileReader: any FileReading = FileReadingSpy(),
        exporter: any XCCovExporting = XCCovExportingSpy(),
    ) -> XcodeCoverageFileReader {
        XcodeCoverageFileReader(fileReader: fileReader, exporter: exporter)
    }
}

private final class FileReadingSpy: FileReading {
    private(set) var paths: [String] = []
    private let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    func read(at path: String) throws -> Data {
        paths.append(path)
        return data
    }
}

private final class XCCovExportingSpy: XCCovExporting {
    private(set) var paths: [String] = []
    private let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    func report(at path: String) throws -> Data {
        paths.append(path)
        return data
    }
}
