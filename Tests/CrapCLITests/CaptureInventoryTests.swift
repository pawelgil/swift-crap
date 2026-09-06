import CrapApplication
@testable import CrapCLI
import CrapCore
import Foundation
import Testing

struct CaptureInventoryTests {
    @Test func `relative source paths use compiler working directory`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = try makeSource(in: fixture)
        let recorder = AnalyzerRecorder()
        let sut = CaptureInventory(makeAnalyzer: recorder.make)

        let result = try sut.read(
            contexts: [makeContext(directory: fixture.path, sources: ["Sources/App.swift"])],
            root: fixture.path,
            inputs: ["Sources/App.swift": "digest"],
        )

        #expect(recorder.contexts.count == 1)
        #expect(recorder.files == ["Sources/App.swift"])
        #expect(result.map(\.file) == [String(source.path.dropFirst(fixture.path.count + 1))])
    }

    @Test func `identical duplicate contexts analyze source once`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        _ = try makeSource(in: fixture)
        let recorder = AnalyzerRecorder()
        let context = makeContext(directory: fixture.path, sources: ["Sources/App.swift"])

        let result = try CaptureInventory(makeAnalyzer: recorder.make).read(
            contexts: [context, context],
            root: fixture.path,
            inputs: ["Sources/App.swift": "digest"],
        )

        #expect(recorder.contexts.count == 1)
        #expect(recorder.files == ["Sources/App.swift"])
        #expect(result.count == 1)
    }

    @Test func `different contexts with equivalent inventories are accepted`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        _ = try makeSource(in: fixture)
        let recorder = AnalyzerRecorder()
        let first = makeContext(directory: fixture.path, sources: ["Sources/App.swift"])
        let second = CompilerContext(
            compiler: first.compiler,
            arguments: first.arguments + ["-I", "/tool/include"],
            directory: first.directory,
            sources: first.sources,
            moduleName: first.moduleName,
        )

        let result = try CaptureInventory(makeAnalyzer: recorder.make).read(
            contexts: [first, second],
            root: fixture.path,
            inputs: ["Sources/App.swift": "digest"],
        )

        #expect(recorder.contexts == [first, second])
        #expect(result.count == 1)
    }

    @Test func `different contexts with different inventories are rejected`() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let source = try makeSource(in: fixture)
        let recorder = AnalyzerRecorder(name: { context in
            context.arguments.contains("-DOTHER") ? "other()" : "run()"
        })
        let first = makeContext(directory: fixture.path, sources: ["Sources/App.swift"])
        let second = CompilerContext(
            compiler: first.compiler,
            arguments: first.arguments + ["-DOTHER"],
            directory: first.directory,
            sources: first.sources,
            moduleName: first.moduleName,
        )

        #expect(throws: ProvenanceError.invalid("ambiguous compiler contexts: \(source.path)")) {
            try CaptureInventory(makeAnalyzer: recorder.make).read(
                contexts: [first, second],
                root: fixture.path,
                inputs: ["Sources/App.swift": "digest"],
            )
        }
    }

    private func makeContext(directory: String, sources: [String]) -> CompilerContext {
        CompilerContext(
            compiler: "/usr/bin/swiftc",
            arguments: ["-DDEBUG"],
            directory: directory,
            sources: sources,
            moduleName: "App",
        )
    }

    private func makeFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory.resolvingSymlinksInPath()
    }

    private func makeSource(in fixture: URL) throws -> URL {
        let directory = fixture.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = directory.appendingPathComponent("App.swift")
        try Data("func run() {}".utf8).write(to: source)
        return source
    }
}

private final class AnalyzerRecorder {
    private(set) var contexts: [CompilerContext] = []
    private(set) var analyzers: [RecordingAnalyzer] = []
    private let complexity: (CompilerContext) -> Int
    private let name: (CompilerContext) -> String

    var files: [String] {
        analyzers.flatMap(\.files)
    }

    init(
        name: @escaping (CompilerContext) -> String = { _ in "run()" },
        complexity: @escaping (CompilerContext) -> Int = { _ in 1 },
    ) {
        self.name = name
        self.complexity = complexity
    }

    func make(_ context: CompilerContext) -> any SourceAnalyzing {
        contexts.append(context)
        let analyzer = RecordingAnalyzer(name: name(context), complexity: complexity(context))
        analyzers.append(analyzer)
        return analyzer
    }
}

private final class RecordingAnalyzer: SourceAnalyzing {
    private(set) var files: [String] = []
    private let complexity: Int
    private let name: String

    init(name: String, complexity: Int) {
        self.name = name
        self.complexity = complexity
    }

    func analyze(source _: String, file: String) -> [Callable] {
        files.append(file)
        let span = SourceSpan(
            start: SourcePosition(line: 1, column: 1),
            end: SourcePosition(line: 1, column: 2),
        )
        return [Callable(
            id: file + "::" + name,
            file: file,
            name: name,
            kind: .function,
            span: span,
            bodySpan: span,
            complexity: complexity,
            parentID: nil,
        )]
    }
}
