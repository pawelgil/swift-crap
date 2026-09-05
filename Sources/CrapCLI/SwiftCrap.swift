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

    private static func analyze(_ request: AnalysisRequest, format: OutputFormat) throws {
        let useCase = AnalyzeProject(
            sourceSelector: LocalSourceSelector(),
            fileReader: LocalFileReader(),
            sourceAnalyzer: SwiftSourceAnalyzer(),
            coverageDecoder: CompilerCoverageDecoder(),
        )
        let report = try useCase.execute(request)
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
