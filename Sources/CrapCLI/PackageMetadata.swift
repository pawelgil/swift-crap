struct PackageMetadata: Decodable {
    let targets: [Target]

    struct Target: Decodable {
        let name: String
        let path: String?
        let sources: [String]?
        let type: String
    }
}
