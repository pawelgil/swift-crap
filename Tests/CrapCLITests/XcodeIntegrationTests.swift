import CrapApplication
@testable import CrapCLI
import CrapCoverage
import Foundation
import Testing

#if os(macOS)
    struct XcodeIntegrationTests {
        @Test func `synchronized group membership comes from Xcode`() throws {
            let fixture = try XcodeFixture()

            let result = try LocalSourceSelector().select(SourceSelectionRequest(scope: .xcode(fixture.selection)))

            #expect(result.files.map(\.relativePath) == ["Sources/Another.swift", "Sources/Included.swift"])
        }

        @Test func `real result bundle loads measured xccov counts`() throws {
            let fixture = try XcodeFixture()
            let resultBundle = try fixture.test()
            let expected = try fixture.nativeCoverage(resultBundle: resultBundle)

            let data = try XcodeCoverageFileReader().read(at: resultBundle.path)
            let coverage = try CompilerCoverageDecoder().decode(data)

            let included = try #require(coverage.records.first { record in
                record.file.hasSuffix("/Sources/Included.swift") && record.name.contains("included")
            })
            #expect(included.coveredLines == expected.covered)
            #expect(included.executableLines == expected.executable)
            #expect(expected.covered < expected.executable)
        }

        @Test func `matching build context resolves compiled module`() throws {
            let fixture = try XcodeFixture()
            let resultBundle = try fixture.test()
            let sut = XcodeProjectDescriber()

            let metadata = try sut.describe(
                fixture.selection,
                matchingXcodebuildCommand: fixture.testCommand(resultBundle: resultBundle),
                workingDirectory: XcodeFixture.fixtureRoot.path,
            )

            let context = try #require(metadata.compilerContexts.first)
            #expect(metadata.compilerContexts.count == 1)
            #expect(try CompilerProbe(context: context).evaluate("canImport(XcodeFixture)"))
        }

        @Test func `universal build context fails closed`() throws {
            let fixture = try XcodeFixture()
            let resultBundle = fixture.directory.appendingPathComponent("Universal.xcresult", isDirectory: true)
            let command = fixture.testCommand(resultBundle: resultBundle) + [
                "ARCHS=arm64 x86_64",
                "ONLY_ACTIVE_ARCH=NO",
            ]

            do {
                _ = try XcodeProjectDescriber().describe(
                    fixture.selection,
                    matchingXcodebuildCommand: command,
                    workingDirectory: XcodeFixture.fixtureRoot.path,
                )
                Issue.record("expected universal build metadata to fail")
            } catch {
                #expect(String(describing: error).contains("capture builds multiple architectures (arm64, x86_64)"))
            }
        }
    }

    private final class XcodeFixture {
        let directory: URL
        let project: URL
        let selection: XcodeSelection

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-crap-xcode-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            project = Self.fixtureRoot.appendingPathComponent("XcodeFixture.xcodeproj", isDirectory: true)
            selection = XcodeSelection(project: project.path, scheme: "XcodeFixture", target: "XcodeFixture")
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func test() throws -> URL {
            let resultBundle = directory.appendingPathComponent("Tests.xcresult", isDirectory: true)
            _ = try run("xcodebuild", Array(testCommand(resultBundle: resultBundle).dropFirst()))
            return resultBundle
        }

        func testCommand(resultBundle: URL) -> [String] {
            [
                "xcodebuild",
                "-project", project.path,
                "-scheme", "XcodeFixture",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", directory.appendingPathComponent("DerivedData").path,
                "-resultBundlePath", resultBundle.path,
                "-enableCodeCoverage", "YES",
                "test",
            ]
        }

        func nativeCoverage(resultBundle: URL) throws -> XcodeNativeCoverage {
            let output = try run("xccov", [
                "view", "--report", "--functions-for-file", "Included.swift", resultBundle.path,
            ])
            let text = String(decoding: output, as: UTF8.self)
            guard let line = text.split(separator: "\n").first(where: { $0.contains("included") }),
                  let opening = line.lastIndex(of: "("),
                  let closing = line.lastIndex(of: ")"),
                  opening < closing
            else {
                throw XcodeFixtureError.missingNativeCoverage(text)
            }
            let counts = line[line.index(after: opening) ..< closing].split(separator: "/")
            guard counts.count == 2,
                  let coveredText = counts.first,
                  let executableText = counts.last,
                  let covered = Int(coveredText),
                  let executable = Int(executableText)
            else {
                throw XcodeFixtureError.missingNativeCoverage(text)
            }
            return XcodeNativeCoverage(covered: covered, executable: executable)
        }

        private func run(_ command: String, _ arguments: [String]) throws -> Data {
            let capture = directory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: capture.path, contents: nil)
            let handle = try FileHandle(forWritingTo: capture)
            defer { try? handle.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [command] + arguments
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = try String(decoding: Data(contentsOf: capture), as: UTF8.self)
                throw XcodeFixtureError.commandFailed(command, message)
            }
            return try Data(contentsOf: capture)
        }

        static let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Fixtures/XcodeFixture")
            .standardizedFileURL
    }

    private struct XcodeNativeCoverage: Equatable {
        let covered: Int
        let executable: Int
    }

    private enum XcodeFixtureError: Error {
        case commandFailed(String, String)
        case missingNativeCoverage(String)
    }
#endif
