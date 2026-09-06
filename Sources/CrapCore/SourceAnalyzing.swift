public protocol SourceAnalyzing {
    func analyze(source: String, file: String) throws -> [Callable]
}
