import Foundation

protocol XCCovExporting {
    func report(at path: String) throws -> Data
}
