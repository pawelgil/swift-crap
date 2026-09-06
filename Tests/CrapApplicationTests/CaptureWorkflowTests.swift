import CrapApplication
import CrapCore
import Testing

struct CaptureWorkflowTests {
    @Test func `invalid request does not run command`() {
        let runner = SpyCommandRunner()
        let sut = createSUT(commandRunner: runner)
        let request = CaptureRequest(
            root: "/repo",
            output: "/repo/receipt.json",
            coverage: [],
            buildDescription: nil,
            buildContext: nil,
            command: [],
        )

        #expect(throws: (any Error).self) {
            try sut.execute(request)
        }
        #expect(!runner.didRun)
    }

    @Test func `duplicate prepared artifacts are rejected without trap`() {
        let runner = SpyCommandRunner()
        let sut = createSUT(commandRunner: runner, pathPreparer: DuplicatePathPreparer())

        #expect(throws: (any Error).self) {
            try sut.execute(makeRequest())
        }
        #expect(!runner.didRun)
    }

    @Test func `changed input during command rejects capture`() {
        let writer = SpyReceiptWriter()
        let sut = createSUT(
            receiptWriter: writer,
            snapshot: SnapshotSequence(values: [["Source.swift": "before"], ["Source.swift": "after"]]),
        )

        #expect(throws: CaptureFailure.inputsChanged) {
            try sut.execute(makeRequest())
        }
        #expect(writer.receipt == nil)
    }

    @Test func `failed command rejects capture`() {
        let sut = createSUT(commandRunner: ThrowingCommandRunner())

        #expect(throws: TestError.failed) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `missing coverage artifact rejects capture`() {
        let sut = createSUT(artifactDigest: ThrowingArtifactDigest())

        #expect(throws: TestError.failed) {
            try sut.execute(makeRequest())
        }
    }

    @Test func `successful capture writes bound receipt`() throws {
        let writer = SpyReceiptWriter()
        let sut = createSUT(receiptWriter: writer)

        try sut.execute(makeRequest())

        let receipt = try #require(writer.receipt)
        #expect(receipt.root == "/repo")
        #expect(receipt.command == ["swift", "test"])
        #expect(receipt.inputs == ["Source.swift": "digest"])
        #expect(receipt.artifacts == ["/repo/coverage.json": "coverage-digest"])
        #expect(receipt.xcode == StubPathPreparer.selection)
        #expect(writer.path == "/repo/receipt.json")
    }

    private func createSUT(
        artifactDigest: any CaptureArtifactDigesting = StubArtifactDigest(),
        commandRunner: any CaptureCommandRunning = StubCommandRunner(),
        contextLoader: any CompilerContextLoading = StubContextLoader(),
        inventory: any CallableInventoryCapturing = StubInventory(),
        pathPreparer: any CapturePathPreparing = StubPathPreparer(),
        receiptWriter: any CaptureReceiptWriting = SpyReceiptWriter(),
        snapshot: any CaptureInputSnapshotting = SnapshotSequence(),
    ) -> CaptureWorkflow {
        CaptureWorkflow(
            artifactDigest: artifactDigest,
            commandRunner: commandRunner,
            contextLoader: contextLoader,
            inventory: inventory,
            pathPreparer: pathPreparer,
            receiptWriter: receiptWriter,
            snapshot: snapshot,
        )
    }

    private func makeRequest() -> CaptureRequest {
        CaptureRequest(
            root: "/repo",
            output: "/repo/receipt.json",
            coverage: ["/repo/coverage.json"],
            buildDescription: nil,
            buildContext: nil,
            command: ["swift", "test"],
            xcode: XcodeSelection(project: "/repo/App.xcodeproj", scheme: "App", target: "App"),
        )
    }
}

private enum TestError: Error {
    case failed
}

private struct StubArtifactDigest: CaptureArtifactDigesting {
    func read(at _: String) -> String {
        "coverage-digest"
    }
}

private struct ThrowingArtifactDigest: CaptureArtifactDigesting {
    func read(at _: String) throws -> String {
        throw TestError.failed
    }
}

private struct StubCommandRunner: CaptureCommandRunning {
    func run(_: [String], root _: String) {}
}

private struct ThrowingCommandRunner: CaptureCommandRunning {
    func run(_: [String], root _: String) throws {
        throw TestError.failed
    }
}

private final class SpyCommandRunner: CaptureCommandRunning {
    private(set) var didRun = false

    func run(_: [String], root _: String) {
        didRun = true
    }
}

private struct StubContextLoader: CompilerContextLoading {
    func load(_: CaptureRequest, root: String) -> [CompilerContext] {
        [CompilerContext(
            compiler: "/swiftc",
            arguments: [],
            directory: root,
            sources: [root + "/Source.swift"],
            moduleName: "Subject",
        )]
    }
}

private struct StubInventory: CallableInventoryCapturing {
    func read(contexts _: [CompilerContext], root _: String, inputs _: [String: String]) -> [Callable] {
        []
    }
}

private struct StubPathPreparer: CapturePathPreparing {
    static let selection = XcodeSelection(project: "/repo/App.xcodeproj", scheme: "App", target: "App")

    func prepare(_: CaptureRequest) -> CapturePaths {
        CapturePaths(
            root: "/repo",
            output: "/repo/receipt.json",
            coverage: ["/repo/coverage.json"],
            xcode: Self.selection,
        )
    }
}

private struct DuplicatePathPreparer: CapturePathPreparing {
    func prepare(_: CaptureRequest) -> CapturePaths {
        CapturePaths(
            root: "/repo",
            output: "/repo/receipt.json",
            coverage: ["/repo/coverage.json", "/repo/coverage.json"],
        )
    }
}

private final class SnapshotSequence: CaptureInputSnapshotting {
    private var values: [[String: String]]

    init(values: [[String: String]] = [["Source.swift": "digest"], ["Source.swift": "digest"]]) {
        self.values = values
    }

    func read(root _: String, excluding _: [String]) -> [String: String] {
        values.removeFirst()
    }
}

private final class SpyReceiptWriter: CaptureReceiptWriting {
    private(set) var path: String?
    private(set) var receipt: CaptureReceipt?

    func write(_ receipt: CaptureReceipt, to path: String) {
        self.path = path
        self.receipt = receipt
    }
}
