import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct XcodeNativeCoverageExporterTests {
    @Test func `exports validated debug dylib coverage for exact result device`() throws {
        let fixture = try ExportFixture()
        let runner = fixture.runner(native: fixture.native(first: 1, second: 0))
        let sut = fixture.exporter(runner: runner)

        let result = try sut.export(
            resultBundle: fixture.resultBundle,
            selection: fixture.selection,
            contexts: [fixture.context],
            command: fixture.command,
            root: fixture.root,
        )

        #expect(result == fixture.native(first: 1, second: 0))
        #expect(runner.invocations.contains(fixture.arguments(binary: fixture.debugDylib)))
    }

    @Test func `exports macOS app debug dylib beside selected launcher`() throws {
        let fixture = try ExportFixture(macOSApp: true)
        let runner = fixture.runner(native: fixture.native(first: 1, second: 0))
        let sut = fixture.exporter(runner: runner)

        _ = try sut.export(
            resultBundle: fixture.resultBundle,
            selection: fixture.selection,
            contexts: [fixture.context],
            command: fixture.command,
            root: fixture.root,
        )

        #expect(runner.invocations.contains(fixture.arguments(binary: fixture.debugDylib)))
    }

    @Test func `returns only selected source files and whole function records`() throws {
        let fixture = try ExportFixture()
        let runner = try fixture.runner(native: fixture.nativeWithUnrelatedEvidence())
        let sut = fixture.exporter(runner: runner)

        let result = try sut.export(
            resultBundle: fixture.resultBundle,
            selection: fixture.selection,
            contexts: [fixture.context],
            command: fixture.command,
            root: fixture.root,
        )
        let document = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
        let units = try #require(document["data"] as? [[String: Any]])
        let unit = try #require(units.first)
        let files = try #require(unit["files"] as? [[String: Any]])
        let functions = try #require(unit["functions"] as? [[String: Any]])

        #expect(files.count == 1)
        #expect(functions.count == 3)
        #expect(unit["totals"] == nil)
        #expect(functions.allSatisfy { ($0["filenames"] as? [String]) == [fixture.source] })
    }

    @Test func `rejects stale profile with equal file totals and swapped same-line closures`() throws {
        let fixture = try ExportFixture()
        let runner = fixture.runner(native: fixture.native(first: 0, second: 1))
        let sut = fixture.exporter(runner: runner)

        #expect(throws: XcodeNativeCoverageExportError.candidateFailures([
            "\(fixture.product): native Xcode coverage export failed: xcrun "
                +
                "\(fixture.arguments(binary: fixture.product).joined(separator: " ")) exited 1: launcher has no coverage",
            "\(fixture.debugDylib): invalid Xcode coverage evidence: subrange execution differs for "
                + "\(fixture.source):1:10",
        ])) {
            try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
        }
    }

    @Test func `rejects missing xccov function evidence`() throws {
        let fixture = try ExportFixture()
        let runner = fixture.runner(native: fixture.native(first: 1, second: 0), includeFunctions: false)
        let sut = fixture.exporter(runner: runner)

        do {
            _ = try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
            Issue.record("expected missing function evidence rejection")
        } catch {
            #expect(String(describing: error).contains("cannot decode xccov report"))
        }
    }

    @Test func `rejects function aggregates that disagree despite matching file regions`() throws {
        let fixture = try ExportFixture()
        let native = fixture.native(first: 1, second: 0, firstFunction: 0, secondFunction: 0)
        let runner = fixture.runner(native: native)
        let sut = fixture.exporter(runner: runner)

        do {
            _ = try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
            Issue.record("expected function aggregate rejection")
        } catch {
            #expect(String(describing: error).contains("function aggregates differ"))
        }
    }

    @Test func `preserves every binary candidate failure`() throws {
        let fixture = try ExportFixture()
        let runner = fixture.runner(native: nil, debugError: "debug image has no profile")
        let sut = fixture.exporter(runner: runner)

        #expect(throws: XcodeNativeCoverageExportError.candidateFailures([
            "\(fixture.product): native Xcode coverage export failed: xcrun "
                +
                "\(fixture.arguments(binary: fixture.product).joined(separator: " ")) exited 1: launcher has no coverage",
            "\(fixture.debugDylib): native Xcode coverage export failed: xcrun "
                + "\(fixture.arguments(binary: fixture.debugDylib).joined(separator: " ")) "
                + "exited 1: debug image has no profile",
        ])) {
            try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
        }
    }

    @Test func `rejects a source-intersecting report for another build product`() throws {
        let fixture = try ExportFixture()
        let other = fixture.directory.appendingPathComponent("DerivedData/Build/Products/Debug/Other").path
        let runner = fixture.runner(native: fixture.native(first: 1, second: 0), reportedProduct: other)
        let sut = fixture.exporter(runner: runner)

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "xccov report does not identify exactly one selected build product intersecting selected sources",
        )) {
            try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
        }
    }

    @Test func `rejects result destination id that can escape profile directory`() throws {
        let fixture = try ExportFixture()
        let runner = fixture.runner(native: fixture.native(first: 1, second: 0), device: "../other")
        let sut = fixture.exporter(runner: runner)

        #expect(throws: XcodeNativeCoverageExportError.invalidEvidence(
            "result bundle has invalid destination device id",
        )) {
            try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: ["xcodebuild", "-destination", "platform=macOS", "test"],
                root: fixture.root,
            )
        }
    }

    @Test func `filters generated context sources and permits authored files absent from both formats`() throws {
        let fixture = try ExportFixture()
        let declaration = URL(fileURLWithPath: fixture.root).appendingPathComponent("Declarations.swift").path
        let generated = fixture.directory.appendingPathComponent("DerivedSources/Generated.swift").path
        FileManager.default.createFile(atPath: declaration, contents: Data("enum Declarations {}\n".utf8))
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: generated).deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        FileManager.default.createFile(atPath: generated, contents: Data("let generated = 1\n".utf8))
        let context = CompilerContext(
            compiler: fixture.context.compiler,
            arguments: [],
            directory: fixture.root,
            sources: [fixture.source, declaration, generated],
            moduleName: fixture.context.moduleName,
        )
        let expected = fixture.native(first: 1, second: 0)
        let sut = fixture.exporter(runner: fixture.runner(native: expected))

        let result = try sut.export(
            resultBundle: fixture.resultBundle,
            selection: fixture.selection,
            contexts: [context],
            command: fixture.command,
            root: fixture.root,
        )

        #expect(result == expected)
    }

    @Test func `rejects successful candidates with different export bytes`() throws {
        let fixture = try ExportFixture()
        let direct = fixture.native(first: 1, second: 0)
        var altered = try #require(JSONSerialization.jsonObject(with: direct) as? [String: Any])
        altered["diagnostic"] = "different image"
        let debug = try JSONSerialization.data(withJSONObject: altered, options: [.sortedKeys])
        let runner = fixture.runner(native: debug, direct: direct)
        let sut = fixture.exporter(runner: runner)

        #expect(throws: XcodeNativeCoverageExportError.conflictingCandidates([
            fixture.product, fixture.debugDylib,
        ])) {
            try sut.export(
                resultBundle: fixture.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: fixture.command,
                root: fixture.root,
            )
        }
    }
}

private final class NativeCoverageRunnerSpy: XcodeNativeCoverageCommandRunning {
    private(set) var invocations: [[String]] = []
    private let response: ([String]) throws -> (Data, Data, Int32)

    init(response: @escaping ([String]) throws -> (Data, Data, Int32)) {
        self.response = response
    }

    func run(arguments: [String]) throws -> (output: Data, error: Data, status: Int32) {
        invocations.append(arguments)
        return try response(arguments)
    }
}

private struct StubBuildProductResolver: XcodeBuildProductResolving {
    let path: String

    func product(selection _: XcodeSelection, command _: [String], workingDirectory _: String) -> String {
        path
    }
}

private final class ExportFixture {
    let command: [String]
    let context: CompilerContext
    let debugDylib: String
    let device = "DEVICE-123"
    let directory: URL
    let product: String
    let profile: String
    let resultBundle: String
    let root: String
    let selection: XcodeSelection
    let source: String

    init(macOSApp: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-crap-native-export-\(UUID())", isDirectory: true)
        root = directory.appendingPathComponent("Project", isDirectory: true).path
        source = URL(fileURLWithPath: root).appendingPathComponent("Subject.swift").path
        let productDirectory = macOSApp
            ? "DerivedData/Build/Products/Debug/Subject.app/Contents/MacOS"
            : "DerivedData/Build/Products/Debug/Subject.app"
        product = directory.appendingPathComponent("\(productDirectory)/Subject").path
        debugDylib = directory.appendingPathComponent("\(productDirectory)/Subject.debug.dylib").path
        profile = directory
            .appendingPathComponent("DerivedData/Build/ProfileData/\(device)/Coverage.profdata").path
        resultBundle = directory.appendingPathComponent("Result Bundle.xcresult").path
        command = [
            "xcodebuild", "-destination", "platform=iOS Simulator,id=\(device)",
            "-resultBundlePath", resultBundle, "test",
        ]
        context = CompilerContext(
            compiler: "/usr/bin/swiftc",
            arguments: [],
            directory: root,
            sources: [source],
            moduleName: "Subject",
        )
        selection = XcodeSelection(project: "\(root)/Subject.xcodeproj", scheme: "Subject", target: "Subject")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source, contents: Data("func subject() {}\n".utf8))
    }

    func exporter(runner: NativeCoverageRunnerSpy) -> XcodeNativeCoverageExporter {
        XcodeNativeCoverageExporter(runner: runner, productResolver: StubBuildProductResolver(path: product))
    }

    func arguments(binary: String) -> [String] {
        ["llvm-cov", "export", binary, "-instr-profile=\(profile)", "--sources", source]
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func runner(
        native: Data?,
        direct: Data? = nil,
        debugError: String = "unused",
        device: String? = nil,
        includeFunctions: Bool = true,
        reportedProduct: String? = nil,
    ) -> NativeCoverageRunnerSpy {
        NativeCoverageRunnerSpy { [self] arguments in
            switch arguments.prefix(4) {
            case ["xccov", "view", "--report", "--json"]:
                return try (report(product: reportedProduct ?? product, includeFunctions: includeFunctions), Data(), 0)
            case ["xccov", "view", "--archive", "--json"]:
                return try (archive(), Data(), 0)
            case ["xcresulttool", "get", "test-results", "summary"]:
                return try (summary(device: device ?? self.device), Data(), 0)
            default:
                if arguments.starts(with: self.arguments(binary: product).dropLast()) {
                    if let direct { return (direct, Data(), 0) }
                    return (Data(), Data("launcher has no coverage".utf8), 1)
                }
                if arguments.starts(with: self.arguments(binary: debugDylib).dropLast()), let native {
                    return (native, Data(), 0)
                }
                return (Data(), Data(debugError.utf8), 1)
            }
        }
    }

    func native(
        first: Int,
        second: Int,
        firstFunction: Int? = nil,
        secondFunction: Int? = nil,
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "type": "llvm.coverage.json.export",
            "version": "2.0.1",
            "data": [[
                "files": [[
                    "filename": source,
                    "segments": [
                        [1, 1, 10, true, true, false],
                        [1, 10, first, true, true, false],
                        [1, 13, 10, true, false, false],
                        [1, 20, second, true, true, false],
                        [1, 23, 10, true, false, false],
                        [2, 1, 0, false, false, false],
                    ],
                    "summary": ["lines": ["count": 1, "covered": 1]],
                ]],
                "functions": [
                    function(name: "parent", start: 1, end: 24, count: 10),
                    function(name: "first", start: 10, end: 13, count: firstFunction ?? first),
                    function(name: "second", start: 20, end: 23, count: secondFunction ?? second),
                ],
            ]],
        ], options: [.sortedKeys])
    }

    func nativeWithUnrelatedEvidence() throws -> Data {
        var document = try #require(JSONSerialization.jsonObject(
            with: native(first: 1, second: 0),
        ) as? [String: Any])
        var units = try #require(document["data"] as? [[String: Any]])
        var unit = try #require(units.first)
        let dependency = directory.appendingPathComponent("Dependency.swift").path
        var files = try #require(unit["files"] as? [[String: Any]])
        files.append([
            "filename": dependency,
            "segments": [[1, 1, 99, true, true, false], [2, 1, 0, false, false, false]],
            "summary": ["lines": ["count": 1, "covered": 1]],
        ])
        var functions = try #require(unit["functions"] as? [[String: Any]])
        functions.append([
            "count": 99,
            "filenames": [dependency],
            "name": "dependency",
            "regions": [[1, 1, 1, 18, 99, 0, 0, 0]],
        ])
        unit["files"] = files
        unit["functions"] = functions
        unit["totals"] = ["lines": ["count": 2, "covered": 2]]
        units[0] = unit
        document["data"] = units
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    private func function(name: String, start: Int, end: Int, count: Int) -> [String: Any] {
        [
            "count": count,
            "filenames": [source],
            "name": name,
            "regions": [[1, start, 1, end, count, 0, 0, 0]],
        ]
    }

    private func report(product: String, includeFunctions: Bool) throws -> Data {
        var file: [String: Any] = [
            "coveredLines": 1,
            "executableLines": 1,
            "path": source,
        ]
        if includeFunctions {
            file["functions"] = [
                ["coveredLines": 1, "executableLines": 1, "lineNumber": 1],
                ["coveredLines": 1, "executableLines": 1, "lineNumber": 1],
                ["coveredLines": 0, "executableLines": 1, "lineNumber": 1],
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "targets": [[
                "buildProductPath": product,
                "files": [file],
            ]],
        ])
    }

    private func archive() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            source: [[
                "executionCount": 10,
                "isExecutable": true,
                "line": 1,
                "subranges": [
                    ["column": 10, "executionCount": 1, "length": 3],
                    ["column": 20, "executionCount": 0, "length": 3],
                ],
            ]],
        ])
    }

    private func summary(device: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "devicesAndConfigurations": [["device": ["deviceId": device]]],
        ])
    }
}
