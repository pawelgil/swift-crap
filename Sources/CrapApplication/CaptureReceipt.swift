import CrapCore
import Foundation

public struct CaptureReceipt: Codable, Sendable {
    public let schemaVersion: Int
    public let metric: String
    public let root: String
    public let command: [String]
    public let inputs: [String: String]
    public let artifacts: [String: String]
    public let contexts: [CompilerContext]
    public let callables: [Callable]
    public let xcode: XcodeSelection?
    public let coverageExports: [String: Data]?

    public init(
        schemaVersion: Int,
        metric: String,
        root: String,
        command: [String],
        inputs: [String: String],
        artifacts: [String: String],
        contexts: [CompilerContext],
        callables: [Callable],
        xcode: XcodeSelection? = nil,
        coverageExports: [String: Data]? = nil,
    ) {
        self.schemaVersion = schemaVersion
        self.metric = metric
        self.root = root
        self.command = command
        self.inputs = inputs
        self.artifacts = artifacts
        self.contexts = contexts
        self.callables = callables
        self.xcode = xcode
        self.coverageExports = coverageExports
    }
}
