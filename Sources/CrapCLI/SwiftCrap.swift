import CrapApplication
import CrapCore
import CrapCoverage
import CrapSyntax
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Foundation

@main
struct SwiftCrap {
    static func main() {
        do {
            let action = try CLIArgumentParser().parse(Array(CommandLine.arguments.dropFirst()))
            switch action {
            case let .analyze(request, format):
                try analyze(request, format: format)
            case let .capture(request):
                try capture(request)
            case .help:
                write(Data((HelpText.value + "\n").utf8), to: .standardOutput)
            case .version:
                write(Data("swift-crap 1.0.0\n".utf8), to: .standardOutput)
            }
        } catch {
            write(Data((message(for: error) + "\n").utf8), to: .standardError)
            terminate(1)
        }
    }

    private static func capture(_ request: CaptureRequest) throws {
        let workflow = CaptureWorkflow(
            artifactDigest: ArtifactDigest(),
            commandRunner: LocalCaptureCommandRunner(),
            contextLoader: LocalCompilerContextLoader(),
            coverageExporter: LocalCaptureCoverageExporter(),
            inventory: CaptureInventory(),
            pathPreparer: LocalCapturePathPreparer(),
            receiptWriter: JSONCaptureReceiptWriter(),
            snapshot: InputSnapshot(),
        )
        try workflow.execute(request)
    }

    private static func analyze(_ request: AnalysisRequest, format: OutputFormat) throws {
        let receipt = try receipt(for: request)
        let buildIdentity = try receipt.map {
            try CapturedBuildIdentity().read(receipt: $0, selection: request.selection)
        }
        let baseline = try BaselineTrustValidator().validate(
            path: request.baselineFile,
            buildIdentity: buildIdentity,
        )
        let result = try analysisUseCase(receipt: receipt, baseline: baseline).execute(request)
        try revalidate(receipt, for: request)
        let report = report(from: result, receipt: receipt, buildIdentity: buildIdentity)
        try writeReport(report, format: format)
    }

    private static func receipt(for request: AnalysisRequest) throws -> CaptureReceipt? {
        let receipt = try request.provenanceFile.map {
            try ReceiptVerifier().read(at: $0, coverage: request.coverageFiles)
        }
        guard receipt != nil || request.trustUnverifiedCoverage else {
            throw ProvenanceError
                .invalid("use --provenance RECEIPT or explicitly opt in with --trust-coverage unverified")
        }
        return receipt
    }

    private static func analysisUseCase(
        receipt: CaptureReceipt?,
        baseline: ValidatedBaseline?,
    ) throws -> AnalyzeProject {
        let selector: any SourceSelecting = receipt.map { ReceiptSourceSelector(receipt: $0) } ?? LocalSourceSelector()
        let analyzer: any SourceAnalyzing = receipt.map { CapturedSourceAnalyzer(receipt: $0) } ?? SwiftSourceAnalyzer()
        let reader = try CapturedCoverageFileReader(
            exports: receipt?.coverageExports ?? [:],
            fallback: XcodeCoverageFileReader(),
        )
        return AnalyzeProject(
            sourceSelector: selector,
            fileReader: ValidatedBaselineFileReader(fileReader: reader, baseline: baseline),
            sourceAnalyzer: analyzer,
            coverageDecoder: CompilerCoverageDecoder(),
        )
    }

    private static func revalidate(_ receipt: CaptureReceipt?, for request: AnalysisRequest) throws {
        guard let receipt, let path = request.provenanceFile else { return }
        try ReceiptVerifier().validate(receipt, at: path, coverage: request.coverageFiles)
    }

    private static func report(
        from result: AnalysisReport,
        receipt: CaptureReceipt?,
        buildIdentity: String?,
    ) -> AnalysisReport {
        AnalysisReport(
            metric: result.metric,
            functions: result.functions,
            summary: result.summary,
            verification: receipt == nil ? "unverified" : "captured",
            buildIdentity: buildIdentity,
        )
    }

    private static func writeReport(_ report: AnalysisReport, format: OutputFormat) throws {
        try write(ReportRenderer().render(report, as: format), to: .standardOutput)
        if report.summary.violations > 0 {
            terminate(2)
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? AnalysisFailure {
            switch error {
            case let .invalidBaseline(path): return "invalid baseline: \(path)"
            case let .invalidCoverage(file, reason): return "invalid coverage \(file): \(reason)"
            case let .invalidSource(file, reason): return "invalid source \(file): \(reason)"
            case let .invalidSourceEncoding(path): return "source is not UTF-8: \(path)"
            case .noCallables: return "no callable inventory"
            case .noCoverageFiles: return "no coverage files"
            case .noSources: return "no usable sources"
            }
        }
        return String(describing: error)
    }

    private static func write(_ data: Data, to handle: FileHandle) {
        handle.write(data)
    }

    private static func terminate(_ code: Int32) -> Never {
        #if canImport(Darwin)
            Darwin.exit(code)
        #elseif canImport(Glibc)
            Glibc.exit(code)
        #else
            fatalError("unsupported platform")
        #endif
    }
}
