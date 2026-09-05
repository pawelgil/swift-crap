import CrapCore
import Foundation

public struct CompilerCoverageDecoder: CoverageDecoding, Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> CoverageImport {
        let document = try CoverageJSON.document(from: data)
        if document["type"] != nil {
            return try LLVMCoverageDecoder().decode(document)
        }
        if document["targets"] != nil {
            return try XCCovCoverageDecoder().decode(document)
        }
        throw CoverageDecodingError.unsupportedSchema
    }
}
