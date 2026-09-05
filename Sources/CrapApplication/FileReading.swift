import Foundation

public protocol FileReading {
    func read(at path: String) throws -> Data
}
