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

        @Test func `matching simulator build context uses actual destination`() throws {
            let fixture = try XcodeFixture()
            let destination = try fixture.simulatorDestination()
            let resultBundle = try fixture.test(destination: destination, sdk: "iphonesimulator")
            let selection = XcodeSelection(
                project: fixture.project.path,
                scheme: "XcodeFixture",
                target: "XcodeFixture",
                destination: destination,
            )

            let metadata = try XcodeProjectDescriber().describe(
                selection,
                matchingXcodebuildCommand: fixture.testCommand(
                    resultBundle: resultBundle,
                    destination: destination,
                    sdk: "iphonesimulator",
                ),
                workingDirectory: XcodeFixture.fixtureRoot.path,
            )

            let context = try #require(metadata.compilerContexts.first)
            #expect(context.arguments.contains(where: { $0.contains("iPhoneSimulator") }))
            #expect(context.arguments.contains(where: { $0.hasSuffix("-simulator") }))
            #expect(try CompilerProbe(context: context).evaluate("os(iOS)"))
            #expect(try CompilerProbe(context: context).evaluate("targetEnvironment(simulator)"))
        }

        @Test func `incremental result without compilation fails clearly`() throws {
            let fixture = try XcodeFixture()
            _ = try fixture.test()
            let incrementalResult = try fixture.test(resultBundleName: "Incremental.xcresult")

            #expect(throws: SourceSelectionError.invalidXcodeMetadata(
                "result bundle has no SwiftDriver invocation for target XcodeFixture; rebuild the target during capture",
            )) {
                try XcodeProjectDescriber().describe(
                    fixture.selection,
                    matchingXcodebuildCommand: fixture.testCommand(resultBundle: incrementalResult),
                    workingDirectory: XcodeFixture.fixtureRoot.path,
                )
            }
        }

        @Test func `matching build context uses resolved Swift compiler override`() throws {
            let fixture = try XcodeFixture()
            let swiftCompiler = try fixture.makeSwiftCompilerWrapper()
            let resultBundle = try fixture.test(swiftCompiler: swiftCompiler)

            let metadata = try XcodeProjectDescriber().describe(
                fixture.selection,
                matchingXcodebuildCommand: fixture.testCommand(
                    resultBundle: resultBundle,
                    swiftCompiler: swiftCompiler,
                ),
                workingDirectory: XcodeFixture.fixtureRoot.path,
            )

            let context = try #require(metadata.compilerContexts.first)
            #expect(context.compiler == swiftCompiler)
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

        @Test func `explicit destination architecture does not hide universal build context`() throws {
            let fixture = try XcodeFixture()
            let resultBundle = fixture.directory.appendingPathComponent("Universal.xcresult", isDirectory: true)
            let destination = "platform=macOS,arch=\(XcodeFixture.nativeArchitecture)"
            let selection = XcodeSelection(
                project: fixture.project.path,
                scheme: "XcodeFixture",
                target: "XcodeFixture",
                destination: destination,
            )
            let command = fixture.testCommand(resultBundle: resultBundle, destination: destination) + [
                "ARCHS=arm64 x86_64",
                "ONLY_ACTIVE_ARCH=NO",
            ]

            #expect(throws: SourceSelectionError.xcodeCommand(
                "capture builds multiple architectures (arm64, x86_64); set ARCHS to one architecture or "
                    + "ONLY_ACTIVE_ARCH=YES",
            )) {
                try XcodeProjectDescriber().describe(
                    selection,
                    matchingXcodebuildCommand: command,
                    workingDirectory: XcodeFixture.fixtureRoot.path,
                )
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

        func makeSwiftCompilerWrapper() throws -> String {
            let wrapper = directory.appendingPathComponent("SelectedToolchain/usr/bin/swiftc")
            let libraries = directory.appendingPathComponent("SelectedToolchain/usr/lib")
            try FileManager.default.createDirectory(
                at: wrapper.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let selectedCompiler = try String(decoding: run("--find", ["swiftc"]), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedLibraries = URL(fileURLWithPath: selectedCompiler)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("lib")
            try FileManager.default.createSymbolicLink(
                at: libraries,
                withDestinationURL: selectedLibraries,
            )
            try Data("#!/bin/sh\nexec /usr/bin/xcrun swiftc \"$@\"\n".utf8).write(to: wrapper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
            return wrapper.path
        }

        func simulatorDestination() throws -> String {
            let text = try String(decoding: run("xcodebuild", [
                "-project", project.path,
                "-scheme", "XcodeFixture",
                "-showdestinations",
            ]), as: UTF8.self)
            guard let line = text.split(separator: "\n").first(where: {
                $0.contains("platform:iOS Simulator, arch:") && !$0.contains("placeholder")
            }), let id = field("id", in: String(line)) else {
                throw XcodeFixtureError.missingSimulatorDestination(text)
            }
            return "platform=iOS Simulator,id=\(id)"
        }

        func test(
            swiftCompiler: String? = nil,
            destination: String = "platform=macOS",
            sdk: String? = nil,
            resultBundleName: String = "Tests.xcresult",
        ) throws -> URL {
            let resultBundle = directory.appendingPathComponent(resultBundleName, isDirectory: true)
            _ = try run("xcodebuild", Array(testCommand(
                resultBundle: resultBundle,
                swiftCompiler: swiftCompiler,
                destination: destination,
                sdk: sdk,
            ).dropFirst()))
            return resultBundle
        }

        func testCommand(
            resultBundle: URL,
            swiftCompiler: String? = nil,
            destination: String = "platform=macOS",
            sdk: String? = nil,
        ) -> [String] {
            var arguments = [
                "xcodebuild",
                "-project", project.path,
                "-scheme", "XcodeFixture",
                "-configuration", "Debug",
                "-destination", destination,
                "-derivedDataPath", directory.appendingPathComponent("DerivedData").path,
                "-resultBundlePath", resultBundle.path,
                "-enableCodeCoverage", "YES",
            ]
            if let sdk {
                arguments += ["-sdk", sdk, "ARCHS=\(Self.nativeArchitecture)", "ONLY_ACTIVE_ARCH=YES"]
            }
            if let swiftCompiler {
                arguments.append("SWIFT_EXEC=\(swiftCompiler)")
            }
            arguments.append("test")
            return arguments
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

        private func field(_ name: String, in destination: String) -> String? {
            let prefix = "\(name):"
            return destination.split(separator: ",").lazy
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
        }

        static let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Fixtures/XcodeFixture")
            .standardizedFileURL

        static var nativeArchitecture: String {
            #if arch(arm64)
                "arm64"
            #elseif arch(x86_64)
                "x86_64"
            #else
                fatalError("unsupported macOS architecture")
            #endif
        }
    }

    private struct XcodeNativeCoverage: Equatable {
        let covered: Int
        let executable: Int
    }

    private enum XcodeFixtureError: Error {
        case commandFailed(String, String)
        case missingNativeCoverage(String)
        case missingSimulatorDestination(String)
    }
#endif
