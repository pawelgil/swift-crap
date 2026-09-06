struct XcodeSourceMetadata: Decodable {
    let languageDialect: String

    private enum CodingKeys: String, CodingKey {
        case languageDialect = "LanguageDialect"
    }
}
