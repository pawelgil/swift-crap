struct XcodeSourceMetadata: Decodable {
    let languageDialect: String
    let swiftASTCommandArguments: [String]?
    let swiftASTModuleName: String?
    let toolchains: [String]?

    private enum CodingKeys: String, CodingKey {
        case languageDialect = "LanguageDialect"
        case swiftASTCommandArguments
        case swiftASTModuleName
        case toolchains
    }
}
