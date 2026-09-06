import CrapCore
import Foundation
import Testing

struct CompilerCoverageIntegrationTests {
    @Test(arguments: CoverageScenario.cases)
    func `control flow line counts match compiler`(_ scenario: CoverageScenario) throws {
        let fixture = try CompilerFixture(
            source: scenario.source,
            entry: "print(Subject.run(Int(CommandLine.arguments[1]) ?? 0))",
        )
        let native = try fixture.nativeLineCoverage(input: scenario.input, symbolSuffix: "3runyS2iFZ")

        let report = try fixture.score(inputs: [scenario.input])

        let score = try #require(report.functions.first)
        #expect(report.functions.count == 1)
        #expect(score.executableLines == native.executable)
        #expect(score.coveredLines == native.covered)
    }

    @Test func `complementary executions fully cover the function`() throws {
        let fixture = try CompilerFixture()

        let report = try fixture.score(inputs: [1, 0])

        let function = try #require(report.functions.first)
        #expect(report.functions.count == 1)
        #expect(function.callable.complexity == 2)
        #expect(function.coverage == 1)
        #expect(function.crap == 2)
    }

    @Test func `one execution leaves an uncovered branch`() throws {
        let fixture = try CompilerFixture()

        let report = try fixture.score(inputs: [1])

        let function = try #require(report.functions.first)
        #expect(function.coveredLines > 0)
        #expect(function.coveredLines < function.executableLines)
        #expect(function.crap > 2)
        #expect(function.crap < 6)
    }

    @Test func `duplicate observations do not change scores`() throws {
        let fixture = try CompilerFixture()

        let once = try fixture.score(inputs: [1])
        let twice = try fixture.score(inputs: [1, 1])

        #expect(once == twice)
    }

    @Test func `coverage input order does not change report bytes`() throws {
        let fixture = try CompilerFixture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let forward = try fixture.score(inputs: [1, 0])
        let reverse = try fixture.score(inputs: [0, 1])

        #expect(try encoder.encode(forward) == encoder.encode(reverse))
    }

    @Test func `line counts match the compiler coverage oracle`() throws {
        let fixture = try CompilerFixture()
        let json = try fixture.coverageExport(input: 1)
        let export = try JSONDecoder().decode(CoverageOracle.self, from: json)
        let native = try #require(export.data.first?.files.first { $0.filename.hasSuffix("/Subject.swift") })

        let report = try fixture.score(inputs: [1])

        let score = try #require(report.functions.first)
        #expect(score.executableLines == native.summary.lines.count)
        #expect(score.coveredLines == native.summary.lines.covered)
    }

    @Test func `same line sibling cannot borrow executed coverage`() throws {
        let source = "enum Subject { static func yes() -> Int { 1 }; static func no() -> Int { 2 } }"
        let fixture = try CompilerFixture(source: source, entry: "print(Subject.yes())")

        let report = try fixture.score(inputs: [1])

        let yes = try #require(report.functions.first { $0.callable.name.contains("yes") })
        let no = try #require(report.functions.first { $0.callable.name.contains("no") })
        #expect(yes.coverage == 1)
        #expect(no.coverage == 0)
    }

    @Test func `returned uncalled closure remains uncovered`() throws {
        let source = "enum Subject { static func make() -> (Int) -> Int { { n in if n > 0 { return n }; return 0 } } }"
        let fixture = try CompilerFixture(
            source: source,
            entry: "let operation = Subject.make()\nprint(type(of: operation))",
        )

        let report = try fixture.score(inputs: [1])

        let closure = try #require(report.functions.first { $0.callable.kind == .closure })
        #expect(closure.callable.complexity == 2)
        #expect(closure.coverage == 0)
        #expect(closure.crap == 6)
    }

    @Test func `implicit autoclosure cannot replace explicit closure`() throws {
        let source = """
        enum Subject {
            static func accept(_ value: @autoclosure () -> Bool) { print(value()) }
            static func make() -> () -> Void {
                {
                    accept(true)
                    print("done")
                }
            }
        }
        """
        let fixture = try CompilerFixture(source: source, entry: "Subject.make()()")
        let native = try fixture.nativeLineCoverage(input: 1, symbolSuffix: "cfU_")

        let report = try fixture.score(inputs: [1])

        let closure = try #require(report.functions.first { $0.callable.kind == .closure })
        #expect(report.functions.count == 3)
        #expect(closure.executableLines == native.executable)
        #expect(closure.coveredLines == native.covered)
    }

    @Test func `async function uses its own compiler coverage`() throws {
        let source = "enum Subject { static func run(_ n: Int) async -> Int { if n > 0 { return n }; return 0 } }"
        let fixture = try CompilerFixture(source: source, entry: "print(await Subject.run(1))")

        let report = try fixture.score(inputs: [1])

        let function = try #require(report.functions.first)
        #expect(report.functions.count == 1)
        #expect(function.callable.complexity == 2)
        #expect(function.coverage == 1)
    }

    @Test func `initializer and getters match compiler functions`() throws {
        let source = """
        struct Subject {
            let value: Int
            init(_ n: Int) { if n > 0 { value = n } else { value = 0 } }
            var doubled: Int { if value > 0 { return value * 2 }; return 0 }
            subscript(offset: Int) -> Int { value + offset }
        }
        """
        let fixture = try CompilerFixture(
            source: source,
            entry: "let subject = Subject(1)\nprint(subject.doubled + subject[2])",
        )

        let report = try fixture.score(inputs: [1])

        #expect(report.functions.map(\.callable.kind) == [.initializer, .getter, .subscriptGetter])
        #expect(report.functions.map(\.callable.complexity) == [2, 2, 1])
        #expect(report.functions.map(\.coverage) == [1, 1, 1])
    }

    @Test func `addressors match native compiler coverage`() throws {
        let source = """
        final class Subject {
            let pointer: UnsafeMutablePointer<Int>
            init(_ value: Int) {
                pointer = .allocate(capacity: 1)
                pointer.initialize(to: value)
            }
            deinit {
                pointer.deinitialize(count: 1)
                pointer.deallocate()
            }
            var value: Int {
                unsafeAddress { UnsafePointer(pointer) }
                unsafeMutableAddress { pointer }
            }
        }
        """
        let fixture = try CompilerFixture(
            source: source,
            entry: "let subject = Subject(1)\nsubject.value += 1\nprint(subject.value)",
        )

        let report = try fixture.score(inputs: [1])

        let addressors = report.functions.filter { $0.callable.name.contains("unsafe") }
        #expect(addressors.map(\.callable.name) == [
            "Subject.value.unsafeAddress",
            "Subject.value.unsafeMutableAddress",
        ])
        #expect(addressors.map(\.coverage) == [1, 1])
        #expect(addressors.allSatisfy { $0.callable.parentID == nil })
        #expect(addressors.allSatisfy { $0.callable.span.contains($0.callable.bodySpan.start) })
    }
}
