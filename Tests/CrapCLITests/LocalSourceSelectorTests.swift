import CrapApplication
@testable import CrapCLI
import Foundation
import Testing

struct LocalSourceSelectorTests {
    @Test func `default file root rejects symlink escape`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let outside = fixture.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".swift")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("func outside() {}".utf8).write(to: outside)
        let link = fixture.directory.appendingPathComponent("Link.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let sut = createSUT()

        #expect(throws: SourceSelectionError.escapedRoot(outside.path)) {
            try sut.select(SourceSelectionRequest(scope: .file(link.path)))
        }
    }

    @Test func `invalid package root fails before metadata process`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let invalidRoot = fixture.directory.appendingPathComponent("Absent")
        let spy = PackageDescribingSpy()
        let sut = createSUT(packageDescriber: spy)

        #expect(throws: SourceSelectionError.missingPath(invalidRoot.path)) {
            try sut.select(SourceSelectionRequest(
                scope: .package(directory: fixture.directory.path, target: nil),
                rootOverride: invalidRoot.path,
            ))
        }
        #expect(spy.paths.isEmpty)
    }

    @Test func `root override permits external alias targeting root`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let source = fixture.directory.appendingPathComponent("Source.swift")
        try Data("func source() {}".utf8).write(to: source)
        let links = try makeFixture()
        defer { links.remove() }
        let link = links.directory.appendingPathComponent("Link.swift")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let sut = createSUT()

        let result = try sut.select(SourceSelectionRequest(
            scope: .file(link.path),
            rootOverride: fixture.directory.path,
        ))

        #expect(result.files == [SelectedSource(path: source.path, relativePath: "Source.swift")])
    }

    @Test func `absolute manifest root has distinct error`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent("sources.json")
        try Data(#"{"root":"/outside","targets":{"App":["App.swift"]}}"#.utf8).write(to: manifest)
        let sut = createSUT()

        #expect(throws: SourceSelectionError.invalidManifestRoot("/outside")) {
            try sut.select(SourceSelectionRequest(scope: .manifest(file: manifest.path, target: "App")))
        }
    }

    @Test func `file scope rejects directory`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let sut = createSUT()

        #expect(throws: SourceSelectionError.notFile(fixture.directory.path)) {
            try sut.select(SourceSelectionRequest(scope: .file(fixture.directory.path)))
        }
    }

    @Test func `manifest source entries must be relative`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent("sources.json")
        try Data(#"{"root":".","targets":{"App":["/outside/App.swift"]}}"#.utf8).write(to: manifest)
        let sut = createSUT()

        #expect(throws: SourceSelectionError.invalidManifestSource("/outside/App.swift")) {
            try sut.select(SourceSelectionRequest(scope: .manifest(file: manifest.path, target: "App")))
        }
    }

    @Test func `exclusion applies after file symlink resolution`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let excluded = fixture.directory.appendingPathComponent("Excluded", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: false)
        let source = excluded.appendingPathComponent("Source.swift")
        try Data("func source() {}".utf8).write(to: source)
        let alias = fixture.directory.appendingPathComponent("Alias.swift")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let sut = createSUT()

        let result = try sut.select(SourceSelectionRequest(
            scope: .project(fixture.directory.path),
            exclusions: ["Excluded"],
        ))

        #expect(result.files.isEmpty)
    }

    @Test func `project filtering applies after file symlink resolution`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let tests = fixture.directory.appendingPathComponent("Tests", isDirectory: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: false)
        let source = tests.appendingPathComponent("Decoy.swift")
        try Data("func decoy() {}".utf8).write(to: source)
        let alias = fixture.directory.appendingPathComponent("Alias.swift")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let sut = createSUT()

        let result = try sut.select(SourceSelectionRequest(scope: .project(fixture.directory.path)))

        #expect(result.files.isEmpty)
    }

    @Test func `project selection excludes SwiftPM manifests`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let source = fixture.directory.appendingPathComponent("App.swift")
        try Data("func app() {}".utf8).write(to: source)
        try Data("import PackageDescription".utf8)
            .write(to: fixture.directory.appendingPathComponent("Package.swift"))
        try Data("import PackageDescription".utf8)
            .write(to: fixture.directory.appendingPathComponent("Package@swift-6.0.swift"))
        let sut = createSUT()

        let result = try sut.select(SourceSelectionRequest(scope: .project(fixture.directory.path)))

        #expect(result.files == [SelectedSource(path: source.path, relativePath: "App.swift")])
    }

    @Test func `Xcode selection uses resolved target membership`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let project = fixture.directory.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let included = fixture.directory.appendingPathComponent("Included.swift")
        let adjacent = fixture.directory.appendingPathComponent("Adjacent.swift")
        try Data("func included() {}".utf8).write(to: included)
        try Data("func adjacent() {}".utf8).write(to: adjacent)
        let xcode = XcodeProjectDescribingSpy(sourceFiles: [included.path])
        let sut = createSUT(xcodeDescriber: xcode)

        let result = try sut.select(SourceSelectionRequest(scope: .xcode(XcodeSelection(
            project: project.path,
            scheme: "App",
            target: "App",
        ))))

        #expect(result.files == [SelectedSource(path: included.path, relativePath: "Included.swift")])
        #expect(xcode.selections == [XcodeSelection(
            project: project.path,
            scheme: "App",
            target: "App",
        )])
    }

    @Test func `Xcode membership cannot escape project root`() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let project = fixture.directory.appendingPathComponent("App.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let outside = fixture.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".swift")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("func outside() {}".utf8).write(to: outside)
        let sut = createSUT(xcodeDescriber: XcodeProjectDescribingSpy(sourceFiles: [outside.path]))

        #expect(throws: SourceSelectionError.escapedRoot(outside.path)) {
            try sut.select(SourceSelectionRequest(scope: .xcode(XcodeSelection(
                project: project.path,
                scheme: "App",
                target: "App",
            ))))
        }
    }

    private func createSUT(
        packageDescriber: any PackageDescribing = PackageDescribingSpy(),
        xcodeDescriber: any XcodeProjectDescribing = XcodeProjectDescribingSpy(),
    ) -> LocalSourceSelector {
        LocalSourceSelector(packageDescriber: packageDescriber, xcodeDescriber: xcodeDescriber)
    }

    private func makeFixture() throws -> TemporaryFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return TemporaryFixture(directory: directory)
    }
}

private final class XcodeProjectDescribingSpy: XcodeProjectDescribing {
    private(set) var selections: [XcodeSelection] = []
    private let sourceFiles: [String]

    init(sourceFiles: [String] = []) {
        self.sourceFiles = sourceFiles
    }

    func describe(_ selection: XcodeSelection) throws -> XcodeProjectMetadata {
        selections.append(selection)
        return XcodeProjectMetadata(sourceFiles: sourceFiles, compilerContexts: [])
    }
}

private final class PackageDescribingSpy: PackageDescribing {
    private(set) var paths: [String] = []

    func describe(packageAt path: String) throws -> PackageMetadata {
        paths.append(path)
        return PackageMetadata(targets: [])
    }
}

private struct TemporaryFixture {
    let directory: URL

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
