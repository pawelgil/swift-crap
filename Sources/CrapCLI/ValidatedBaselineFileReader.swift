import CrapApplication
import Foundation

struct ValidatedBaselineFileReader: FileReading {
    private let baseline: ValidatedBaseline?
    private let fileReader: any FileReading

    init(fileReader: any FileReading, baseline: ValidatedBaseline?) {
        self.fileReader = fileReader
        self.baseline = baseline
    }

    func read(at path: String) throws -> Data {
        if let baseline, path == baseline.path {
            return baseline.data
        }
        return try fileReader.read(at: path)
    }
}
