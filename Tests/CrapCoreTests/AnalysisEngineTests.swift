import CrapCore
import Foundation
import Testing

struct AnalysisEngineTests {
    @Test func `measured line coverage produces crap score`() throws {
        let callable = makeCallable(complexity: 2)
        let coverage = makeLineCoverage([true, false])
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        let score = try #require(report.functions.first)
        #expect(score.coveredLines == 1)
        #expect(score.executableLines == 2)
        #expect(score.coverage == 0.5)
        #expect(score.crap == 2.5)
        #expect(score.coverageStatus == "measured")
    }

    @Test func `complementary line observations union coverage`() throws {
        let callable = makeCallable()
        let first = makeLineCoverage([true, false])
        let second = makeLineCoverage([false, true])
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [first, second],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        let score = try #require(report.functions.first)
        #expect(score.coveredLines == 2)
        #expect(score.executableLines == 2)
        #expect(score.coverage == 1)
    }

    @Test func `inconsistent line universes throw`() {
        let callable = makeCallable()
        let first = makeLineCoverage([true, false])
        let second = makeLineCoverage([true, false, true])
        let sut = createSUT()

        #expect(throws: AnalysisError.inconsistentLineUniverse(callableID: callable.id)) {
            try sut.analyze(
                callables: [callable],
                coverage: [first, second],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `nonidentical aggregate observations throw`() {
        let callable = makeCallable()
        let first = makeAggregateCoverage(covered: 1, executable: 2)
        let second = makeAggregateCoverage(covered: 2, executable: 2)
        let sut = createSUT()

        #expect(throws: AnalysisError.ambiguousAggregateCoverage(callableID: callable.id)) {
            try sut.analyze(
                callables: [callable],
                coverage: [first, second],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `equal aggregate totals with different anchors throw`() {
        let callable = makeCallable()
        let first = makeAggregateCoverage(anchorLine: 1, covered: 1, executable: 2)
        let second = makeAggregateCoverage(anchorLine: 2, covered: 1, executable: 2)
        let sut = createSUT()

        #expect(throws: AnalysisError.ambiguousAggregateCoverage(callableID: callable.id)) {
            try sut.analyze(
                callables: [callable],
                coverage: [first, second],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `aggregate observations deduplicate after path normalization`() throws {
        let callable = makeCallable()
        let first = makeAggregateCoverage(file: "/workspace/Feature.swift")
        let second = makeAggregateCoverage(file: "/workspace/./Feature.swift")
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [first, second],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `measured zero differs from assumed zero`() throws {
        let measuredCallable = makeCallable(id: "measured", name: "measured()")
        let missingCallable = makeCallable(id: "missing", name: "missing()", startLine: 10, endLine: 13)
        let coverage = makeAggregateCoverage(name: "measured()", covered: 0, executable: 2)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [measuredCallable, missingCallable],
            coverage: [coverage],
            root: "/workspace",
            missing: .zero,
            threshold: 30,
        )

        let measured = try #require(report.functions.first { $0.callable.id == "measured" })
        let assumed = try #require(report.functions.first { $0.callable.id == "missing" })
        #expect((measured.coveredLines, measured.executableLines, measured.coverageStatus) == (0, 2, "measured"))
        #expect((assumed.coveredLines, assumed.executableLines, assumed.coverageStatus) == (0, 0, "assumedZero"))
        #expect(report.summary.measuredFunctions == 1)
        #expect(report.summary.assumedFunctions == 1)
    }

    @Test func `exact canonical path matches`() throws {
        let callable = makeCallable(file: "Sources/Feature.swift")
        let coverage = makeAggregateCoverage(file: "/workspace/Sources/./Feature.swift")
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `matching path suffix from different root is ignored`() {
        let callable = makeCallable(file: "Sources/Feature.swift")
        let coverage = makeAggregateCoverage(file: "/other/Sources/Feature.swift")
        let sut = createSUT()

        #expect(throws: AnalysisError.missingCoverage(callableID: callable.id)) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `ambiguous location match throws`() {
        let first = makeCallable(id: "first")
        let second = makeCallable(id: "second")
        let coverage = makeAggregateCoverage()
        let sut = createSUT()

        #expect(throws: AnalysisError.ambiguousCoverage(recordName: coverage.name, file: coverage.file)) {
            try sut.analyze(
                callables: [first, second],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `columnless same line match does not guess by span size`() {
        let first = makeCallable(
            id: "first",
            name: "first()",
            endLine: 1,
            startColumn: 10,
            endColumn: 30,
        )
        let second = makeCallable(
            id: "second",
            name: "second()",
            endLine: 1,
            startColumn: 35,
            endColumn: 45,
        )
        let coverage = makeAggregateCoverage(name: "compiler symbol")
        let sut = createSUT()

        #expect(throws: AnalysisError.ambiguousCoverage(recordName: coverage.name, file: coverage.file)) {
            try sut.analyze(
                callables: [first, second],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `overlapping record without owned anchor is ignored`() {
        let callable = makeCallable(startLine: 3, endLine: 6)
        let coverage = CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "unrelated()",
            span: makeSpan(startLine: 1, endLine: 4),
            anchor: SourcePosition(line: 1, column: 1),
            lines: [CoverageLine(line: 1, covered: true)],
            coveredLines: nil,
            executableLines: nil,
        )
        let sut = createSUT()

        #expect(throws: AnalysisError.missingCoverage(callableID: callable.id)) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `unrepresented implicit closure does not attach to parent`() throws {
        let parent = makeCallable(name: "run()", startLine: 1, endLine: 8)
        let parentCoverage = makeAggregateCoverage(name: "run()", anchorLine: 1)
        let implicitCoverage = makeAggregateCoverage(name: "implicit closure #1 in run()", anchorLine: 3)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent],
            coverage: [parentCoverage, implicitCoverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `mangled autoclosure does not attach to parent`() throws {
        let parent = makeCallable(name: "value()", startLine: 1, endLine: 5)
        let parentCoverage = makeAggregateCoverage(name: "module:$s5valueyyF", anchorLine: 1)
        let autoclosureCoverage = makeAggregateCoverage(name: "module:$sSiyKXEfu_", anchorLine: 3)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent],
            coverage: [parentCoverage, autoclosureCoverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `implicit closure nested in explicit closure is ignored`() throws {
        let parent = makeCallable(id: "parent", name: "run()", startLine: 1, endLine: 8)
        let closure = makeCallable(
            id: "closure",
            name: "run().$closure1",
            kind: .closure,
            startLine: 3,
            endLine: 7,
            parentID: parent.id,
        )
        let closureCoverage = makeAggregateCoverage(name: "module:$syycfU_", anchorLine: 3)
        let implicitCoverage = makeAggregateCoverage(name: "module:$syycfU_7LoggingVyXEfu_", anchorLine: 4)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent, closure],
            coverage: [closureCoverage, implicitCoverage],
            root: "/workspace",
            missing: .zero,
            threshold: 30,
        )

        let closureScore = try #require(report.functions.first { $0.callable.id == closure.id })
        #expect(closureScore.coverageStatus == "measured")
    }

    @Test func `implicit collection thunk does not attach to function`() throws {
        let parent = makeCallable(name: "simulator()", startLine: 1, endLine: 5)
        let closure = makeCallable(
            id: "closure",
            name: "simulator().$closure1",
            kind: .closure,
            startLine: 2,
            endLine: 3,
            startColumn: 40,
            endColumn: 70,
            parentID: parent.id,
        )
        let parentCoverage = makeAggregateCoverage(name: "module:$syyF", anchorLine: 1)
        let thunkCoverage = makeAggregateCoverage(name: "module:$sArraycfu_", anchorLine: 2)
        let closureCoverage = CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "module:$sPredicateXEfU_",
            span: nil,
            anchor: SourcePosition(line: 2, column: 40),
            lines: nil,
            coveredLines: 1,
            executableLines: 1,
        )
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent, closure],
            coverage: [parentCoverage, thunkCoverage, closureCoverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 2)
    }

    @Test func `generated default argument does not attach to function`() throws {
        let callable = makeCallable(name: "request(value:)")
        let functionCoverage = makeAggregateCoverage(name: "module:$srequestyyF")
        let defaultArgumentCoverage = makeAggregateCoverage(name: "module:$srequestyyFfA_", anchorLine: 2)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [functionCoverage, defaultArgumentCoverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test(arguments: ["autoclosure()", "cfU()"])
    func `closure-like function names remain functions`(_ name: String) throws {
        let callable = makeCallable(name: name)
        let coverage = makeAggregateCoverage(name: name)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.summary.measuredFunctions == 1)
    }

    @Test func `coverage line outside record span throws`() {
        let callable = makeCallable()
        let coverage = CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: makeSpan(startLine: 1, endLine: 3),
            anchor: SourcePosition(line: 1, column: 1),
            lines: [CoverageLine(line: 4, covered: true)],
            coveredLines: nil,
            executableLines: nil,
        )
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCoverage(recordName: coverage.name, file: coverage.file)) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `coverage anchor outside record span throws`() {
        let callable = makeCallable()
        let coverage = CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: makeSpan(startLine: 2, endLine: 4),
            anchor: SourcePosition(line: 1, column: 1),
            lines: nil,
            coveredLines: 1,
            executableLines: 1,
        )
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCoverage(recordName: coverage.name, file: coverage.file)) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `coverage span outside matched callable throws`() {
        let callable = makeCallable(startLine: 2, endLine: 5)
        let coverage = CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: makeSpan(startLine: 1, endLine: 6),
            anchor: SourcePosition(line: 2, column: 1),
            lines: [CoverageLine(line: 2, covered: true)],
            coveredLines: nil,
            executableLines: nil,
        )
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCoverage(recordName: coverage.name, file: coverage.file)) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `missing callable parent throws`() {
        let child = makeCallable(id: "child", parentID: "missing")
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCallable(child.id)) {
            try sut.analyze(
                callables: [child],
                coverage: [makeAggregateCoverage()],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `self callable parent throws`() {
        let child = makeCallable(id: "child", parentID: "child")
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCallable(child.id)) {
            try sut.analyze(
                callables: [child],
                coverage: [makeAggregateCoverage()],
                root: "/workspace",
                missing: .error,
                threshold: 30,
            )
        }
    }

    @Test func `parent from another file throws`() {
        let parent = makeCallable(id: "parent", file: "Other.swift", startLine: 1, endLine: 8)
        let child = makeCallable(id: "child", startLine: 2, endLine: 4, parentID: parent.id)
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCallable(child.id)) {
            try sut.analyze(
                callables: [parent, child],
                coverage: [],
                root: "/workspace",
                missing: .zero,
                threshold: 30,
            )
        }
    }

    @Test func `noncontaining callable parent throws`() {
        let parent = makeCallable(id: "parent", startLine: 1, endLine: 3)
        let child = makeCallable(id: "child", startLine: 4, endLine: 6, parentID: parent.id)
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidCallable(child.id)) {
            try sut.analyze(
                callables: [parent, child],
                coverage: [],
                root: "/workspace",
                missing: .zero,
                threshold: 30,
            )
        }
    }

    @Test func `nested callable owns its anchored observation`() throws {
        let parent = makeCallable(id: "parent", startLine: 1, endLine: 10)
        let child = makeCallable(id: "child", startLine: 2, endLine: 5, parentID: parent.id)
        let coverage = makeAggregateCoverage(name: "compiler symbol", anchorLine: 3)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent, child],
            coverage: [coverage],
            root: "/workspace",
            missing: .zero,
            threshold: 30,
        )

        let childScore = try #require(report.functions.first { $0.callable.id == child.id })
        #expect(childScore.coverageStatus == "measured")
    }

    @Test func `implicit closure record matches closure only`() throws {
        let parent = makeCallable(id: "parent", name: "run()", startLine: 1, endLine: 8)
        let closure = makeCallable(
            id: "closure",
            name: "run().closure#1",
            kind: .closure,
            startLine: 3,
            endLine: 5,
            parentID: parent.id,
        )
        let parentCoverage = makeAggregateCoverage(name: "run()", anchorLine: 1, covered: 2, executable: 2)
        let closureCoverage = makeAggregateCoverage(
            name: "closure #1 in run()",
            anchorLine: 3,
            covered: 0,
            executable: 1,
        )
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [parent, closure],
            coverage: [parentCoverage, closureCoverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        let parentScore = try #require(report.functions.first { $0.callable.id == parent.id })
        let closureScore = try #require(report.functions.first { $0.callable.id == closure.id })
        #expect(parentScore.coverage == 1)
        #expect(closureScore.coverage == 0)
    }

    @Test func `existing violation that does not increase is permitted`() throws {
        let callable = makeCallable(complexity: 5)
        let coverage = makeAggregateCoverage(covered: 0, executable: 1)
        let baseline = makeBaseline(callable: callable, complexity: 6)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 20,
            baseline: baseline,
        )

        #expect(report.functions.first?.crap == 30)
        #expect(report.summary.violations == 0)
    }

    @Test func `increased existing violation fails gate`() throws {
        let callable = makeCallable(complexity: 5)
        let coverage = makeAggregateCoverage(covered: 0, executable: 1)
        let baseline = makeBaseline(callable: callable, complexity: 4)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 20,
            baseline: baseline,
        )

        #expect(report.summary.violations == 1)
    }

    @Test func `existing score increase below threshold fails gate`() throws {
        let callable = makeCallable(complexity: 2)
        let coverage = makeAggregateCoverage(covered: 0, executable: 1)
        let baseline = makeBaseline(callable: callable, complexity: 1)
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [callable],
            coverage: [coverage],
            root: "/workspace",
            missing: .error,
            threshold: 30,
            baseline: baseline,
        )

        #expect(report.functions.first?.crap == 6)
        #expect(report.summary.violations == 1)
    }

    @Test func `incompatible baseline throws`() {
        let callable = makeCallable()
        let coverage = makeAggregateCoverage()
        let baseline = AnalysisReport(
            schemaVersion: 2,
            functions: [],
            summary: makeSummary(),
        )
        let sut = createSUT()

        #expect(throws: AnalysisError.incompatibleBaseline) {
            try sut.analyze(
                callables: [callable],
                coverage: [coverage],
                root: "/workspace",
                missing: .error,
                threshold: 30,
                baseline: baseline,
            )
        }
    }

    @Test func `functions are sorted deterministically`() throws {
        let laterFile = makeCallable(id: "later", file: "Z.swift")
        let laterPosition = makeCallable(id: "middle", file: "A.swift", startLine: 8, endLine: 11)
        let earlierPosition = makeCallable(id: "first", file: "A.swift", startLine: 2, endLine: 5)
        let coverage = [
            makeAggregateCoverage(file: "/workspace/Z.swift"),
            makeAggregateCoverage(file: "/workspace/A.swift", anchorLine: 8),
            makeAggregateCoverage(file: "/workspace/A.swift", anchorLine: 2),
        ]
        let sut = createSUT()

        let report = try sut.analyze(
            callables: [laterFile, laterPosition, earlierPosition],
            coverage: coverage,
            root: "/workspace",
            missing: .error,
            threshold: 30,
        )

        #expect(report.functions.map(\.callable.id) == ["first", "middle", "later"])
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -0.1])
    func `invalid threshold throws`(_ threshold: Double) {
        let sut = createSUT()

        #expect(throws: AnalysisError.invalidThreshold) {
            try sut.analyze(
                callables: [makeCallable()],
                coverage: [makeAggregateCoverage()],
                root: "/workspace",
                missing: .error,
                threshold: threshold,
            )
        }
    }

    private func createSUT() -> AnalysisEngine {
        AnalysisEngine()
    }

    private func makeCallable(
        id: String = "callable",
        file: String = "Feature.swift",
        name: String = "feature()",
        kind: CallableKind = .function,
        startLine: Int = 1,
        endLine: Int = 4,
        startColumn: Int = 1,
        endColumn: Int = 1,
        complexity: Int = 1,
        parentID: String? = nil,
    ) -> Callable {
        Callable(
            id: id,
            file: file,
            name: name,
            kind: kind,
            span: makeSpan(
                startLine: startLine,
                endLine: endLine,
                startColumn: startColumn,
                endColumn: endColumn,
            ),
            bodySpan: makeSpan(
                startLine: startLine,
                endLine: endLine,
                startColumn: startColumn,
                endColumn: endColumn,
            ),
            complexity: complexity,
            parentID: parentID,
        )
    }

    private func makeLineCoverage(_ covered: [Bool]) -> CoverageRecord {
        CoverageRecord(
            file: "/workspace/Feature.swift",
            name: "feature()",
            span: makeSpan(startLine: 1, endLine: 4),
            anchor: SourcePosition(line: 1, column: 1),
            lines: covered.enumerated().map { CoverageLine(line: $0.offset + 1, covered: $0.element) },
            coveredLines: nil,
            executableLines: nil,
        )
    }

    private func makeAggregateCoverage(
        file: String = "/workspace/Feature.swift",
        name: String = "feature()",
        anchorLine: Int = 1,
        covered: Int = 1,
        executable: Int = 1,
    ) -> CoverageRecord {
        CoverageRecord(
            file: file,
            name: name,
            span: nil,
            anchor: SourcePosition(line: anchorLine, column: 1),
            lines: nil,
            coveredLines: covered,
            executableLines: executable,
        )
    }

    private func makeSpan(
        startLine: Int,
        endLine: Int,
        startColumn: Int = 1,
        endColumn: Int = 1,
    ) -> SourceSpan {
        SourceSpan(
            start: SourcePosition(line: startLine, column: startColumn),
            end: SourcePosition(line: endLine, column: endColumn),
        )
    }

    private func makeBaseline(callable: Callable, complexity: Int) -> AnalysisReport {
        let baselineCallable = makeCallable(
            id: callable.id,
            file: callable.file,
            name: callable.name,
            complexity: complexity,
        )
        let score = makeBaselineScore(callable: baselineCallable)
        return AnalysisReport(functions: [score], summary: makeSummary(total: 1, measured: 1))
    }

    private func makeBaselineScore(callable: Callable) -> FunctionScore {
        let crap = Double(callable.complexity * callable.complexity + callable.complexity)
        return FunctionScore(
            callable: callable,
            coveredLines: 0,
            executableLines: 1,
            coverage: 0,
            crap: crap,
            coverageStatus: "measured",
        )
    }

    private func makeSummary(total: Int = 0, measured: Int = 0) -> ReportSummary {
        ReportSummary(
            totalFunctions: total,
            measuredFunctions: measured,
            assumedFunctions: 0,
            violations: 0,
            threshold: 30,
        )
    }
}
