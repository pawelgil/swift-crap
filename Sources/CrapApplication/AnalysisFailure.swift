public enum AnalysisFailure: Error, Equatable {
    case invalidBaseline(String)
    case invalidCoverage(file: String, reason: String)
    case invalidSource(file: String, reason: String)
    case invalidSourceEncoding(String)
    case noCallables
    case noCoverageFiles
    case noSources
}
