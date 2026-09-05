enum SourceSelectionError: Error, CustomStringConvertible, Equatable {
    case escapedRoot(String)
    case invalidExclusion(String)
    case invalidManifest(String)
    case invalidManifestRoot(String)
    case invalidManifestSource(String)
    case invalidPackageMetadata
    case missingPath(String)
    case notFile(String)
    case packageDescription(String)
    case target(String)

    var description: String {
        switch self {
        case let .escapedRoot(path): "path escapes source root: \(path)"
        case let .invalidExclusion(path): "invalid exclusion prefix: \(path)"
        case let .invalidManifest(path): "invalid sources manifest: \(path)"
        case let .invalidManifestRoot(path): "invalid sources manifest root: \(path)"
        case let .invalidManifestSource(path): "sources manifest entry must be root-relative: \(path)"
        case .invalidPackageMetadata: "swift package describe returned invalid metadata"
        case let .missingPath(path): "source path does not exist: \(path)"
        case let .notFile(path): "file scope requires a regular file: \(path)"
        case let .packageDescription(message): "swift package describe failed: \(message)"
        case let .target(name): "target not found or ambiguous: \(name)"
        }
    }
}
