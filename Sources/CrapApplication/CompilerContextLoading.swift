public protocol CompilerContextLoading {
    func load(_ request: CaptureRequest, root: String) throws -> [CompilerContext]
}
