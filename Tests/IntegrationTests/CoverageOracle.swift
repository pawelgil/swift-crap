struct CoverageOracle: Decodable {
    let data: [Dataset]

    struct Dataset: Decodable {
        let files: [File]
        let functions: [Function]
    }

    struct File: Decodable {
        let filename: String
        let summary: Summary
    }

    struct Function: Decodable {
        let filenames: [String]
        let name: String
        let regions: [[Int]]

        var startLine: Int? {
            regions.first?.first
        }
    }

    struct Summary: Decodable {
        let lines: Lines
    }

    struct Lines: Decodable {
        let count: Int
        let covered: Int
    }
}
