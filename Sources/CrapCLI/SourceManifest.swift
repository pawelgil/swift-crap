struct SourceManifest: Decodable {
    let root: String
    let targets: [String: [String]]
}
