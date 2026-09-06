import Foundation

public protocol CoverageDecoding {
    func decode(_ data: Data) throws -> CoverageImport
}
