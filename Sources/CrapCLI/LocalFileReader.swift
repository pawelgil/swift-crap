import CrapApplication
import Foundation

struct LocalFileReader: FileReading {
    func read(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }
}
