public struct CoverageImport: Sendable {
    public let records: [CoverageRecord]
    public let format: String

    public init(records: [CoverageRecord], format: String) {
        self.records = records
        self.format = format
    }
}
