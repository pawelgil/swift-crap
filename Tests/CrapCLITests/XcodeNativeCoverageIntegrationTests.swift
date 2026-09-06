import CrapApplication
@testable import CrapCLI
import CrapCoverage
import Foundation
import Testing

#if os(macOS)
    struct XcodeNativeCoverageIntegrationTests {
        @Test func `real result bundle exports column-precise same-line closure coverage`() throws {
            let fixture = try NativeCoverageIntegrationFixture()
            let run = try fixture.test(label: "Current", useFirst: true)
            let originalDigest = try ArtifactDigest().read(at: run.resultBundle)

            let data = try XcodeNativeCoverageExporter().export(
                resultBundle: run.resultBundle,
                selection: fixture.selection,
                contexts: [fixture.context],
                command: run.command,
                root: fixture.root.path,
            )
            let coverage = try CompilerCoverageDecoder().decode(data)
            let closures = coverage.records.filter {
                $0.file.hasSuffix("/Sources/Included.swift") && $0.anchor.line == 9
            }.sorted { $0.anchor.column < $1.anchor.column }

            #expect(closures.count == 2)
            #expect(closures.map(\.anchor.column) == [12, 27])
            #expect(closures.map { $0.lines?.first?.covered } == [true, false])
            #expect(try ArtifactDigest().read(at: run.resultBundle) == originalDigest)
        }

        @Test func `stale native profile with equal file totals and swapped closure coverage is rejected`() throws {
            let fixture = try NativeCoverageIntegrationFixture()
            let current = try fixture.test(label: "Current", useFirst: true)
            let stale = try fixture.test(label: "Stale", useFirst: false)
            let currentEvidence = try fixture.reportEvidence(current.resultBundle)
            let staleEvidence = try fixture.reportEvidence(stale.resultBundle)
            let staleProfile = try fixture.profile(in: stale.derivedData)
            let currentProfile = try fixture.profile(in: current.derivedData)

            #expect(currentEvidence.totals == staleEvidence.totals)
            #expect(currentEvidence.closureExecutions == [1, 0])
            #expect(staleEvidence.closureExecutions == [0, 1])
            try Data(contentsOf: staleProfile).write(to: currentProfile)

            do {
                _ = try XcodeNativeCoverageExporter().export(
                    resultBundle: current.resultBundle,
                    selection: fixture.selection,
                    contexts: [fixture.context],
                    command: current.command,
                    root: fixture.root.path,
                )
                Issue.record("expected stale profile rejection")
            } catch {
                #expect(String(describing: error).contains("subrange execution differs"))
            }
        }
    }

    private final class NativeCoverageIntegrationFixture {
        let context: CompilerContext
        let directory: URL
        let root: URL
        let selection: XcodeSelection

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-crap-native-integration-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            root = directory.appendingPathComponent("XcodeFixture", isDirectory: true)
            try FileManager.default.copyItem(at: Self.fixtureRoot, to: root)
            let copiedRoot = root
            let sources = ["Another.swift", "Included.swift"].map {
                copiedRoot.appendingPathComponent("Sources/\($0)").path
            }
            context = CompilerContext(
                compiler: "/usr/bin/swiftc",
                arguments: [],
                directory: root.path,
                sources: sources,
                moduleName: "XcodeFixture",
            )
            selection = XcodeSelection(
                project: root.appendingPathComponent("XcodeFixture.xcodeproj").path,
                scheme: "XcodeFixture",
                target: "XcodeFixture",
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func test(label: String, useFirst: Bool) throws -> Run {
            try selectFirst(useFirst)
            let bundle = directory.appendingPathComponent("\(label).xcresult", isDirectory: true).path
            let derivedData = directory.appendingPathComponent("\(label)-DerivedData", isDirectory: true)
            let command = command(resultBundle: bundle, derivedData: derivedData)
            let result = try run(command)
            guard result.status == 0 else {
                throw NativeCoverageIntegrationError.xcodebuild(String(decoding: result.error, as: UTF8.self))
            }
            return Run(command: command, derivedData: derivedData, resultBundle: bundle)
        }

        func reportEvidence(_ resultBundle: String) throws -> ReportEvidence {
            let result = try run(["xccov", "view", "--report", "--json", resultBundle])
            guard result.status == 0,
                  let document = try JSONSerialization.jsonObject(with: result.output) as? [String: Any],
                  let targets = document["targets"] as? [[String: Any]],
                  let files = targets.flatMap({ $0["files"] as? [[String: Any]] ?? [] })
                  .first(where: { ($0["path"] as? String)?.hasSuffix("/Sources/Included.swift") == true }),
                  let covered = files["coveredLines"] as? Int,
                  let executable = files["executableLines"] as? Int,
                  let functions = files["functions"] as? [[String: Any]]
            else {
                throw NativeCoverageIntegrationError.invalidReport
            }
            let closures = functions.filter {
                ($0["name"] as? String)?.contains("closure #") == true
                    && ($0["name"] as? String)?.contains("selectClosure") == true
            }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            guard closures.count == 2,
                  closures.allSatisfy({ $0["executionCount"] is Int })
            else {
                throw NativeCoverageIntegrationError.invalidReport
            }
            return ReportEvidence(
                closureExecutions: closures.compactMap { $0["executionCount"] as? Int },
                totals: [covered, executable],
            )
        }

        func profile(in derivedData: URL) throws -> URL {
            let profileData = derivedData.appendingPathComponent("Build/ProfileData", isDirectory: true)
            let enumerator = FileManager.default.enumerator(at: profileData, includingPropertiesForKeys: nil)
            let profiles = (enumerator?.allObjects as? [URL] ?? [])
                .filter { $0.lastPathComponent == "Coverage.profdata" }
            guard profiles.count == 1, let profile = profiles.first else {
                throw NativeCoverageIntegrationError.invalidProfile
            }
            return profile
        }

        private func command(resultBundle: String, derivedData: URL) -> [String] {
            [
                "xcodebuild",
                "-project", root.appendingPathComponent("XcodeFixture.xcodeproj").path,
                "-scheme", "XcodeFixture",
                "-configuration", "Debug",
                "-destination", "platform=macOS",
                "-derivedDataPath", derivedData.path,
                "-resultBundlePath", resultBundle,
                "-enableCodeCoverage", "YES",
                "test",
            ]
        }

        private func selectFirst(_ selected: Bool) throws {
            let path = root.appendingPathComponent("Tests/IncludedTests.swift")
            let original = try String(contentsOf: path, encoding: .utf8)
            let first = "#expect(selectClosure(true) == 1)"
            let second = "#expect(selectClosure(false) == 2)"
            let updated = original.replacingOccurrences(of: selected ? second : first, with: selected ? first : second)
            try Data(updated.utf8).write(to: path)
        }

        private func run(_ arguments: [String]) throws -> (output: Data, error: Data, status: Int32) {
            let capture = try CaptureFiles()
            defer { capture.remove() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.standardOutput = capture.output
            process.standardError = capture.error
            try process.run()
            process.waitUntilExit()
            capture.close()
            return try (capture.outputData(), capture.errorData(), process.terminationStatus)
        }

        static let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Fixtures/XcodeFixture")
            .standardizedFileURL

        struct Run {
            let command: [String]
            let derivedData: URL
            let resultBundle: String
        }

        struct ReportEvidence {
            let closureExecutions: [Int]
            let totals: [Int]
        }
    }

    private enum NativeCoverageIntegrationError: Error {
        case invalidProfile
        case invalidReport
        case xcodebuild(String)
    }
#endif
