import CrapCore

public protocol CallableInventoryCapturing {
    func read(contexts: [CompilerContext], root: String, inputs: [String: String]) throws -> [Callable]
}
