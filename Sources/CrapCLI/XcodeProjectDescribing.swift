import CrapApplication

protocol XcodeProjectDescribing {
    func describe(_ selection: XcodeSelection) throws -> XcodeProjectMetadata
}
