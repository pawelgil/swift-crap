import CrapCore
import Foundation

public struct AnalyzeProject {
    private let sourceSelector: any SourceSelecting
    private let fileReader: any FileReading
    private let sourceAnalyzer: any SourceAnalyzing
    private let coverageDecoder: any CoverageDecoding
    private let engine: AnalysisEngine

    public init(
        sourceSelector: any SourceSelecting,
        fileReader: any FileReading,
        sourceAnalyzer: any SourceAnalyzing,
        coverageDecoder: any CoverageDecoding,
        engine: AnalysisEngine = AnalysisEngine(),
    ) {
        self.sourceSelector = sourceSelector
        self.fileReader = fileReader
        self.sourceAnalyzer = sourceAnalyzer
        self.coverageDecoder = coverageDecoder
        self.engine = engine
    }

    public func execute(_ request: AnalysisRequest) throws -> AnalysisReport {
        guard !request.coverageFiles.isEmpty else {
            throw AnalysisFailure.noCoverageFiles
        }
        let sources = try sourceSelector.select(request.selection)
        guard !sources.files.isEmpty else {
            throw AnalysisFailure.noSources
        }
        let callables = try analyze(sources.files)
        guard !callables.isEmpty else {
            throw AnalysisFailure.noCallables
        }
        let coverage = try decodeCoverage(request.coverageFiles)
        let baseline = try decodeBaseline(request.baselineFile)
        return try engine.analyze(
            callables: callables,
            coverage: coverage,
            root: sources.root,
            missing: request.missing,
            threshold: request.threshold,
            baseline: baseline,
        )
    }

    private func analyze(_ files: [SelectedSource]) throws -> [Callable] {
        try files.flatMap { file in
            let data: Data
            do {
                data = try fileReader.read(at: file.path)
            } catch {
                throw AnalysisFailure.invalidSource(file: file.path, reason: String(describing: error))
            }
            guard let source = String(data: data, encoding: .utf8) else {
                throw AnalysisFailure.invalidSourceEncoding(file.path)
            }
            do {
                return try sourceAnalyzer.analyze(source: source, file: file.relativePath)
            } catch {
                throw AnalysisFailure.invalidSource(file: file.path, reason: String(describing: error))
            }
        }
    }

    private func decodeCoverage(_ files: [String]) throws -> [CoverageRecord] {
        try files.flatMap { file in
            do {
                let data = try fileReader.read(at: file)
                return try coverageDecoder.decode(data).records
            } catch {
                throw AnalysisFailure.invalidCoverage(file: file, reason: String(describing: error))
            }
        }
    }

    private func decodeBaseline(_ file: String?) throws -> AnalysisReport? {
        guard let file else {
            return nil
        }
        do {
            return try JSONDecoder().decode(AnalysisReport.self, from: fileReader.read(at: file))
        } catch {
            throw AnalysisFailure.invalidBaseline(file)
        }
    }
}
