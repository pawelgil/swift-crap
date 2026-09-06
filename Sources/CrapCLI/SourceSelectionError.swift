enum SourceSelectionError: Error, CustomStringConvertible, Equatable {
    case escapedRoot(String)
    case invalidExclusion(String)
    case invalidManifest(String)
    case invalidManifestRoot(String)
    case invalidManifestSource(String)
    case invalidPackageMetadata
    case invalidXcodeMetadata
    case invalidXcodeProject(String)
    case missingPath(String)
    case notFile(String)
    case packageDescription(String)
    case target(String)
    case xcodeDescription(String)
    case xcodeCommand(String)
    case xcodeTargetHasNoSwiftSources(String)

    var description: String {
        switch self {
        case let .escapedRoot(path): "path escapes source root: \(path)"
        case let .invalidExclusion(path): "invalid exclusion prefix: \(path)"
        case let .invalidManifest(path): "invalid sources manifest: \(path)"
        case let .invalidManifestRoot(path): "invalid sources manifest root: \(path)"
        case let .invalidManifestSource(path): "sources manifest entry must be root-relative: \(path)"
        case .invalidPackageMetadata: "swift package describe returned invalid metadata"
        case .invalidXcodeMetadata: "xcodebuild returned invalid source metadata"
        case let .invalidXcodeProject(path): "Xcode project must be an .xcodeproj directory: \(path)"
        case let .missingPath(path): "source path does not exist: \(path)"
        case let .notFile(path): "file scope requires a regular file: \(path)"
        case let .packageDescription(message): "swift package describe failed: \(message)"
        case let .target(name): "target not found or ambiguous: \(name)"
        case let .xcodeDescription(message): "xcodebuild source discovery failed: \(message)"
        case let .xcodeCommand(message): "invalid xcodebuild capture command: \(message)"
        case let .xcodeTargetHasNoSwiftSources(name): "Xcode target has no Swift sources: \(name)"
        }
    }
}
