struct XcodeBuildSettingsMetadata: Decodable {
    let target: String
    let buildSettings: [String: String]
}
