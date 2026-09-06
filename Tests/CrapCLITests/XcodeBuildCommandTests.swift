import CrapApplication
@testable import CrapCLI
import Testing

struct XcodeBuildCommandTests {
    @Test func `matching invocation preserves compiler overrides`() throws {
        let selection = makeSelection()
        let sut = XcodeBuildCommand()

        let result = try sut.metadataArguments([
            "xcodebuild", "-project", selection.project,
            "-scheme", selection.scheme,
            "-configuration", selection.configuration,
            "-destination", selection.destination,
            "-derivedDataPath", "/tmp/XcodeDerivedData",
            "-resultBundlePath", "Tests.xcresult",
            "-enableCodeCoverage", "YES",
            "-xcconfig", "Build.xcconfig",
            "FEATURE=YES", "test",
        ], matching: selection)

        #expect(result == [
            "-derivedDataPath", "/tmp/XcodeDerivedData",
            "-xcconfig", "Build.xcconfig", "FEATURE=YES",
        ])
    }

    @Test func `mismatched configuration is rejected`() {
        let selection = makeSelection()
        let sut = XcodeBuildCommand()

        #expect(throws: SourceSelectionError.xcodeCommand("-configuration must match Debug")) {
            try sut.metadataArguments([
                "xcodebuild", "-project", selection.project,
                "-scheme", selection.scheme,
                "-configuration", "Release",
                "-destination", selection.destination,
                "test",
            ], matching: selection)
        }
    }

    @Test func `relative command project matches absolute selection in command working directory`() throws {
        let selection = makeSelection()

        let result = try XcodeBuildCommand().metadataArguments([
            "xcodebuild", "-project", "App.xcodeproj",
            "-scheme", selection.scheme,
            "-configuration", selection.configuration,
            "-destination", selection.destination,
            "test",
        ], matching: selection, workingDirectory: "/project")

        #expect(result.isEmpty)
    }

    @Test func `result bundle resolves from command working directory`() throws {
        let result = try XcodeBuildCommand().resultBundlePath([
            "xcodebuild", "-resultBundlePath", "Build/Tests.xcresult", "test",
        ], workingDirectory: "/project")

        #expect(result == "/project/Build/Tests.xcresult")
    }

    @Test func `missing result bundle is rejected`() {
        #expect(throws: SourceSelectionError.xcodeCommand(
            "capture command must provide exactly one -resultBundlePath",
        )) {
            try XcodeBuildCommand().resultBundlePath(["xcodebuild", "test"])
        }
    }

    @Test func `shell wrapper is rejected`() {
        let selection = makeSelection()
        let sut = XcodeBuildCommand()

        #expect(throws: SourceSelectionError.xcodeCommand("capture command must invoke xcodebuild directly")) {
            try sut.metadataArguments(["sh", "-c", "xcodebuild test"], matching: selection)
        }
    }

    private func makeSelection() -> XcodeSelection {
        XcodeSelection(
            project: "/project/App.xcodeproj",
            scheme: "App",
            target: "App",
            configuration: "Debug",
            destination: "platform=macOS",
        )
    }
}
