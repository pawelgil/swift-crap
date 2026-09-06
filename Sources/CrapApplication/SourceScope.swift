public enum SourceScope: Equatable, Sendable {
    case file(String)
    case manifest(file: String, target: String)
    case package(directory: String, target: String?)
    case project(String)
    case xcode(XcodeSelection)
}
