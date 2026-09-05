import CrapApplication
import CrapCore

struct ParsedValues {
    var baseline: String?
    var coverage: [String] = []
    var exclusions: [String] = []
    var file: String?
    var format = OutputFormat.text
    var manifest: String?
    var missing = MissingCoveragePolicy.error
    var package: String?
    var project: String?
    var root: String?
    var target: String?
    var threshold = 30.0

    mutating func append(option: String, value: String) throws {
        switch option {
        case "--baseline": baseline = try unique(baseline, option, value)
        case "--coverage": coverage.append(value)
        case "--exclude": exclusions.append(value)
        case "--file": file = try unique(file, option, value)
        case "--format": format = try parse(OutputFormat.self, option, value)
        case "--missing": missing = try parse(MissingCoveragePolicy.self, option, value)
        case "--package": package = try unique(package, option, value)
        case "--project": project = try unique(project, option, value)
        case "--root": root = try unique(root, option, value)
        case "--sources-manifest": manifest = try unique(manifest, option, value)
        case "--target": target = try unique(target, option, value)
        case "--threshold": threshold = try thresholdValue(option, value)
        default: throw CLIError.invalidOption(option)
        }
    }

    func action() throws -> CLIAction {
        guard !coverage.isEmpty else {
            throw CLIError.missingOption("--coverage")
        }
        let request = try AnalysisRequest(
            selection: selectionRequest(),
            coverageFiles: coverage,
            missing: missing,
            threshold: threshold,
            baselineFile: baseline,
        )
        return .analyze(request, format)
    }

    private func selectionRequest() throws -> SourceSelectionRequest {
        let selectors = [project, package, file, manifest].compactMap(\.self)
        guard selectors.count == 1 else {
            throw CLIError.selection("exactly one source selector is required")
        }
        if let project {
            try reject(target != nil, "--target requires --package or --sources-manifest")
            try reject(root != nil, "--root is only valid with --package or --file")
            return SourceSelectionRequest(scope: .project(project), exclusions: exclusions)
        }
        if let package {
            return SourceSelectionRequest(
                scope: .package(directory: package, target: target),
                rootOverride: root,
                exclusions: exclusions,
            )
        }
        if let file {
            try reject(target != nil, "--target requires --package or --sources-manifest")
            return SourceSelectionRequest(scope: .file(file), rootOverride: root, exclusions: exclusions)
        }
        guard let manifest, let target else {
            throw CLIError.missingOption("--target")
        }
        try reject(root != nil, "--root is only valid with --package or --file")
        return SourceSelectionRequest(scope: .manifest(file: manifest, target: target), exclusions: exclusions)
    }

    private func unique(_ current: String?, _ option: String, _ value: String) throws -> String {
        guard current == nil else {
            throw CLIError.invalidValue(option: option, value: "specified more than once")
        }
        return value
    }

    private func parse<Value: RawRepresentable>(_: Value.Type, _ option: String, _ value: String) throws -> Value
        where Value.RawValue == String
    {
        guard let parsed = Value(rawValue: value) else {
            throw CLIError.invalidValue(option: option, value: value)
        }
        return parsed
    }

    private func thresholdValue(_ option: String, _ value: String) throws -> Double {
        guard let threshold = Double(value), threshold.isFinite, threshold >= 0 else {
            throw CLIError.invalidValue(option: option, value: value)
        }
        return threshold
    }

    private func reject(_ condition: Bool, _ message: String) throws {
        if condition {
            throw CLIError.selection(message)
        }
    }
}
