struct CoverageOracle: Decodable {
    let data: [Dataset]

    struct Dataset: Decodable {
        let files: [File]
    }

    struct File: Decodable {
        let filename: String
        let summary: Summary
    }

    struct Summary: Decodable {
        let lines: Lines
    }

    struct Lines: Decodable {
        let count: Int
        let covered: Int
    }
}
