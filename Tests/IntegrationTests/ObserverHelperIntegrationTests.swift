import CrapCore
import Testing

#if os(macOS)
    struct ObserverHelperIntegrationTests {
        @Test(arguments: AssignmentScenario.cases)
        func `observed counter counts only changed assignments`(_ scenario: AssignmentScenario) throws {
            let fixture = try CompilerFixture(source: source, entry: entry)

            #expect(try fixture.output(input: scenario.input) == scenario.output)
        }

        @Test func `observed counter helper remains measured across guard paths`() throws {
            let fixture = try CompilerFixture(source: source, entry: entry)
            let callables = try fixture.callables()
            let report = try analyze(fixture, missing: .zero)
            let helper = try #require(report.functions
                .first { $0.callable.name == "Counter.valueDidChange(from: Int)" })
            let observer = try #require(report.functions.first { $0.callable.name == "Counter.value.didSet" })

            #expect(callables.map(\.name) == ["Counter.value.didSet", "Counter.valueDidChange(from: Int)"])
            #expect((helper.callable.complexity, helper.coverage, helper.coverageStatus, helper.crap) == (
                2,
                1,
                "measured",
                2,
            ))
            #expect((observer.coveredLines, observer.executableLines, observer.coverageStatus) == (0, 0, "assumedZero"))
            #expect(report.summary.assumedFunctions == 1)
        }

        @Test func `missing observer is rejected by strict policy`() throws {
            let fixture = try CompilerFixture(source: source, entry: entry)
            let observer = try #require(fixture.callables().first { $0.name == "Counter.value.didSet" })

            #expect(throws: AnalysisError.missingCoverage(callableID: observer.id)) {
                try analyze(fixture, missing: .error)
            }
        }

        private func analyze(
            _ fixture: CompilerFixture,
            missing: MissingCoveragePolicy,
        ) throws -> AnalysisReport {
            let coverage = try [0, 1].flatMap { try fixture.coverage(input: $0) }
            return try AnalysisEngine().analyze(
                callables: fixture.callables(),
                coverage: coverage,
                root: fixture.directory.path,
                missing: missing,
                threshold: 30,
            )
        }

        private var entry: String {
            """
            let counter = Counter()
            counter.value = Int(CommandLine.arguments[1]) ?? 0
            print(counter.changeCount)
            """
        }

        private var source: String {
            """
            import Observation

            @Observable
            final class Counter {
                var value = 0 {
                    didSet { valueDidChange(from: oldValue) }
                }
                private(set) var changeCount = 0
                private func valueDidChange(from oldValue: Int) {
                    guard value != oldValue else { return }
                    changeCount += 1
                }
            }
            """
        }

        struct AssignmentScenario: CustomTestStringConvertible {
            let input: Int
            let output: String

            var testDescription: String {
                input == 0 ? "unchanged assignment" : "changed assignment"
            }

            static let cases = [
                AssignmentScenario(input: 0, output: "0\n"),
                AssignmentScenario(input: 1, output: "1\n"),
            ]
        }
    }
#endif
