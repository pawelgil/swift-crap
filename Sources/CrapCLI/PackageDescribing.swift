protocol PackageDescribing {
    func describe(packageAt path: String) throws -> PackageMetadata
}
