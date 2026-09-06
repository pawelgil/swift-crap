import CrapCore

public struct CaptureWorkflow {
    private let artifactDigest: any CaptureArtifactDigesting
    private let commandRunner: any CaptureCommandRunning
    private let contextLoader: any CompilerContextLoading
    private let inventory: any CallableInventoryCapturing
    private let pathPreparer: any CapturePathPreparing
    private let receiptWriter: any CaptureReceiptWriting
    private let snapshot: any CaptureInputSnapshotting

    public init(
        artifactDigest: any CaptureArtifactDigesting,
        commandRunner: any CaptureCommandRunning,
        contextLoader: any CompilerContextLoading,
        inventory: any CallableInventoryCapturing,
        pathPreparer: any CapturePathPreparing,
        receiptWriter: any CaptureReceiptWriting,
        snapshot: any CaptureInputSnapshotting,
    ) {
        self.artifactDigest = artifactDigest
        self.commandRunner = commandRunner
        self.contextLoader = contextLoader
        self.inventory = inventory
        self.pathPreparer = pathPreparer
        self.receiptWriter = receiptWriter
        self.snapshot = snapshot
    }

    public func execute(_ request: CaptureRequest) throws {
        try validate(request)
        let paths = try pathPreparer.prepare(request)
        try validate(paths)
        let exclusions = [paths.output] + paths.coverage
        let before = try snapshot.read(root: paths.root, excluding: exclusions)
        try commandRunner.run(request.command, root: paths.root)
        let contexts = try contextLoader.load(request, root: paths.root)
        let callables = try inventory.read(contexts: contexts, root: paths.root, inputs: before)
        let artifacts = try Dictionary(uniqueKeysWithValues: paths.coverage.map {
            try ($0, artifactDigest.read(at: $0))
        })
        let after = try snapshot.read(root: paths.root, excluding: exclusions)
        guard before == after else { throw CaptureFailure.inputsChanged }
        let receipt = CaptureReceipt(
            schemaVersion: 1,
            metric: "crap-line-v1",
            root: paths.root,
            command: request.command,
            inputs: before,
            artifacts: artifacts,
            contexts: contexts,
            callables: callables,
            xcode: paths.xcode,
        )
        try receiptWriter.write(receipt, to: paths.output)
    }

    private func validate(_ request: CaptureRequest) throws {
        guard !request.root.isEmpty, !request.output.isEmpty, !request.coverage.isEmpty, !request.command.isEmpty else {
            throw CaptureFailure.invalidRequest("capture request is incomplete")
        }
        let contextSources = [request.buildDescription, request.buildContext].compactMap(\.self).count
            + (request.xcode == nil ? 0 : 1)
        guard contextSources == 1 else {
            throw CaptureFailure.invalidRequest("capture requires exactly one compiler context source")
        }
    }

    private func validate(_ paths: CapturePaths) throws {
        let outputs = [paths.output] + paths.coverage
        guard !paths.root.isEmpty, !paths.output.isEmpty, !paths.coverage.isEmpty,
              Set(outputs).count == outputs.count
        else {
            throw CaptureFailure.invalidRequest("capture paths are incomplete or duplicated")
        }
    }
}
