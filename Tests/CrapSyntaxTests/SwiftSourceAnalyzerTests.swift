import CrapCore
import CrapSyntax
import SwiftIfConfig
import SwiftSyntax
import Testing

struct SwiftSourceAnalyzerTests {
    @Test func `inventories qualified overloads and stable IDs`() throws {
        let source = """
        struct Box<Element> {
            func map<T>(_ value: T) -> Element where T: Sequence { fatalError() }
            func map<T>(value: T) -> Element where T: Collection { fatalError() }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Sources/Box.swift")

        #expect(callables.map(\.name) == [
            "Box.map<T>(_: T) -> Element where T: Sequence",
            "Box.map<T>(value: T) -> Element where T: Collection",
        ])
        #expect(Set(callables.map(\.id)).count == 2)
        #expect(callables.allSatisfy { !$0.id.contains(":1:") })
    }

    @Test func `named IDs ignore source position changes`() throws {
        let source = "func work(value: Int) {}"
        let shiftedSource = "\n\nfunc work(value: Int) {}"

        let original = try createSUT().analyze(source: source, file: "Work.swift")
        let shifted = try createSUT().analyze(source: shiftedSource, file: "Work.swift")

        #expect(original.map(\.id) == shifted.map(\.id))
    }

    @Test func `reports UTF-8 half open spans`() throws {
        let source = """
        func café() {
            print("ok")
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Unicode.swift")

        let callable = try #require(callables.first)
        #expect(callable.span == span(1, 1, 3, 2))
        #expect(callable.bodySpan == span(1, 14, 3, 2))
    }

    @Test func `counts decision points`() throws {
        let source = """
        func decisions(_ a: Bool, _ b: Bool, _ value: Int?) {
            if a && b, value != nil { }
            guard a || b, let value else { return }
            for item in [1, 2] where item > 0 { }
            while a { break }
            repeat { } while b
            do { throw Failure.bad } catch { }
            switch value {
            case .some: break
            case .none: break
            default: break
            }
            let x = a ? 1 : 0
            let y = value ?? x
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Decisions.swift")

        let callable = try #require(callables.first)
        #expect(callable.complexity == 16)
    }

    @Test func `counts every boolean operator across precedence groups`() throws {
        let source = "func choose(_ a: Bool, _ b: Bool, _ c: Bool, _ d: Bool) { _ = a && b || c && d }"

        let callables = try createSUT().analyze(source: source, file: "Operators.swift")

        #expect(callables.map(\.complexity) == [4])
    }

    @Test func `parent complexity excludes nested callables`() throws {
        let source = """
        func outer() {
            if true { }
            func inner() {
                if true { }
            }
            let closure = {
                guard true else { return }
            }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Nested.swift")

        #expect(callables.map(\.complexity) == [2, 2, 2])
        let outer = try #require(callables.first)
        #expect(callables.map(\.parentID) == [nil, outer.id, outer.id])
    }

    @Test func `implicit getter counts its own decisions`() throws {
        let source = "var value: Int { if true { return 1 }; return 0 }"

        let callables = try createSUT().analyze(source: source, file: "Getter.swift")

        #expect(callables.map(\.complexity) == [2])
    }

    @Test func `closure complexity excludes captures and nested types`() throws {
        let source = """
        func make(_ a: Bool, _ b: Bool) {
            _ = { [captured = a && b] in
                struct Local { var value = a || b }
                return captured ? 1 : 0
            }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "ClosureBody.swift")

        #expect(callables.map(\.complexity) == [1, 2])
    }

    @Test func `inventories callable kinds`() throws {
        let source = """
        final class Sample {
            var implicit: Int { 1 }
            var explicit: Int {
                get { 1 }
                set { _ = newValue }
            }
            var observed = 0 {
                willSet { _ = newValue }
                didSet { _ = oldValue }
            }
            subscript(index: Int) -> Int {
                get { index }
                set { _ = newValue }
            }
            init(value: Int) { observed = value }
            deinit { print(observed) }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Sample.swift")

        #expect(callables.map(\.kind) == [
            .getter, .getter, .setter, .observer, .observer,
            .subscriptGetter, .subscriptSetter, .initializer, .deinitializer,
        ])
        #expect(callables.map(\.name) == [
            "Sample.implicit.getter",
            "Sample.explicit.getter",
            "Sample.explicit.setter",
            "Sample.observed.willSet",
            "Sample.observed.didSet",
            "Sample.subscript(index: Int) -> Int.getter",
            "Sample.subscript(index: Int) -> Int.setter",
            "Sample.init(value: Int)",
            "Sample.deinit",
        ])
    }

    @Test func `accessor spellings have distinct callable identities`() throws {
        let source = """
        var streamed: Int {
            get { 1 }
            _read { yield 1 }
            set { _ = newValue }
            _modify { yield &storage }
        }
        var addressed: Int {
            unsafeAddress { fatalError() }
            unsafeMutableAddress { fatalError() }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Accessors.swift")

        #expect(callables.map(\.name) == [
            "streamed.getter",
            "streamed._read",
            "streamed.setter",
            "streamed._modify",
            "addressed.unsafeAddress",
            "addressed.unsafeMutableAddress",
        ])
        #expect(callables.map(\.kind) == [.getter, .getter, .setter, .setter, .getter, .setter])
        #expect(Set(callables.map(\.id)).count == callables.count)
    }

    @Test func `ordinary helper call with accessor spelling remains inside getter`() throws {
        let source = """
        func borrow(_ body: () -> Int) -> Int { body() }
        var value: Int { borrow { 7 } }
        """

        let configuration = TestingBuildConfiguration(importableModules: [], features: [])
        let callables = try createSUT(configuration: configuration)
            .analyze(source: source, file: "AccessorCall.swift")

        #expect(callables.map(\.name) == ["borrow(_: () -> Int) -> Int", "value.getter", "value.getter.$closure1"])
        #expect(callables.map(\.kind) == [.function, .getter, .closure])
    }

    @Test func `conditional accessor spelling nested in closure remains a helper call`() throws {
        let source = """
        func _read(_ body: () -> Int) -> Int { body() }
        func wrapper(_ body: () -> Int) -> Int { body() }
        var value: Int {
            wrapper {
            #if ENABLED
                _read { 7 }
            #else
                0
            #endif
            }
        }
        """
        let configuration = TestingBuildConfiguration(
            importableModules: [],
            features: [],
            customConditions: ["ENABLED"],
        )

        let callables = try createSUT(configuration: configuration)
            .analyze(source: source, file: "AccessorCall.swift")

        #expect(callables.map(\.name) == [
            "_read(_: () -> Int) -> Int",
            "wrapper(_: () -> Int) -> Int",
            "value.getter",
            "value.getter.$closure1",
            "value.getter.$closure1.$closure1",
        ])
        #expect(callables.map(\.kind) == [.function, .function, .getter, .closure, .closure])
    }

    @Test func `borrow and mutate accessors are inventoried when enabled`() throws {
        let source = """
        var value: Int {
            borrow { 1 }
            mutate { fatalError() }
        }
        """
        let configuration = TestingBuildConfiguration(
            importableModules: [],
            features: ["BorrowAndMutateAccessors"],
        )

        let callables = try createSUT(configuration: configuration).analyze(source: source, file: "Accessors.swift")

        #expect(callables.map(\.name) == ["value.borrow", "value.mutate"])
        #expect(callables.map(\.kind) == [.getter, .setter])
    }

    @Test func `nearest declaration owns nested subscript accessors`() throws {
        let source = """
        var outer: Int {
            struct Local {
                subscript(index: Int) -> Int { index }
            }
            return Local()[0]
        }
        """

        let callables = try createSUT().analyze(source: source, file: "NearestOwner.swift")

        #expect(callables.map(\.kind) == [.getter, .subscriptGetter])
        #expect(callables.map(\.name) == [
            "outer.getter",
            "outer.getter.Local.subscript(index: Int) -> Int.getter",
        ])
    }

    @Test func `protocol requirements do not create callables`() throws {
        let source = """
        protocol Service {
            func execute(value: Int)
            var value: Int { get set }
            subscript(index: Int) -> Int { get set }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Service.swift")

        #expect(callables.isEmpty)
    }

    @Test func `escaped identifiers remain in signatures`() throws {
        let source = "func `repeat`(_ `class`: Int) { }"

        let callables = try createSUT().analyze(source: source, file: "Escaped.swift")

        #expect(callables.map(\.name) == ["`repeat`(_: Int)"])
    }

    @Test func `multi binding property names its accessor binding`() throws {
        let source = "var stored = 0, computed: Int { 1 }"

        let callables = try createSUT().analyze(source: source, file: "Bindings.swift")

        #expect(callables.map(\.name) == ["computed.getter"])
        #expect(callables.map(\.span.start.column) == [17])
    }

    @Test func `closures have lexical identity and parents`() throws {
        let source = """
        func transform() {
            let first = { true }
            let second = { { false } }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Closure.swift")

        #expect(callables.map(\.name) == [
            "transform()",
            "transform().$closure1",
            "transform().$closure2",
            "transform().$closure2.$closure1",
        ])
        let function = try #require(callables.first { $0.kind == .function })
        let secondClosure = try #require(callables.first { $0.name == "transform().$closure2" })
        #expect(callables.map(\.parentID) == [nil, function.id, function.id, secondClosure.id])
    }

    @Test func `identity includes static and extension constraints`() throws {
        let source = """
        struct Value {
            func run() { }
            static func run() { }
        }
        extension Array where Element: Equatable {
            func run() { }
        }
        extension Array where Element: Hashable {
            func run() { }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Identity.swift")

        #expect(callables.map(\.name) == [
            "Value.run()", "Value.static run()",
            "Array[where Element: Equatable].run()",
            "Array[where Element: Hashable].run()",
        ])
        #expect(Set(callables.map(\.id)).count == 4)
    }

    @Test func `local type remains in qualified identity`() throws {
        let source = """
        func outer() {
            struct Local {
                func run() { }
            }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Local.swift")

        #expect(callables.map(\.name) == ["outer()", "outer().Local.run()"])
    }

    @Test func `local callable lineage uses its nearest parent`() throws {
        let source = """
        func outer() {
            func local() {
                _ = { true }
            }
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Lineage.swift")

        let outer = try #require(callables.first { $0.name == "outer()" })
        let local = try #require(callables.first { $0.name == "outer().local()" })
        let closure = try #require(callables.first { $0.kind == .closure })
        #expect(local.parentID == outer.id)
        #expect(closure.parentID == local.id)
    }

    @Test func `signature identity ignores type trivia`() throws {
        let plain = "func work(value: [String: Int]) { }"
        let commented = "func work(value: [String /* note */ : Int]) { }"

        let plainCallables = try createSUT().analyze(source: plain, file: "Trivia.swift")
        let commentedCallables = try createSUT().analyze(source: commented, file: "Trivia.swift")

        #expect(plainCallables.map(\.id) == commentedCallables.map(\.id))
    }

    @Test func `normalizes callable file separators`() throws {
        let source = "func work() { }"

        let callables = try createSUT().analyze(source: source, file: "./Sources\\Work.swift")

        #expect(callables.map(\.file) == ["Sources/Work.swift"])
    }

    @Test func `inventories every conditional compilation clause`() throws {
        let source = """
        #if os(macOS)
        func platform() { }
        #else
        func platform() { }
        #endif
        """

        let callables = try createSUT().analyze(source: source, file: "Conditional.swift")

        #expect(callables.map(\.name) == ["platform()", "platform()"])
        #expect(Set(callables.map(\.id)).count == 2)
    }

    @Test func `conditional else identities are unique and position stable`() throws {
        let source = """
        #if A
        #else
        func selected() { }
        #endif
        #if B
        #else
        func selected() { }
        #endif
        """
        let shifted = source.replacingOccurrences(of: "#if A", with: "\n#if   A")

        let original = try createSUT().analyze(source: source, file: "Conditions.swift")
        let moved = try createSUT().analyze(source: shifted, file: "Conditions.swift")

        #expect(Set(original.map(\.id)).count == 2)
        #expect(original.map(\.id) == moved.map(\.id))
    }

    @Test func `configured analysis inventories only the active clause`() throws {
        let source = """
        #if ENABLED
        func enabled() {
            if true { }
        }
        #else
        func disabled() {
            if true { }
            if true { }
        }
        #endif
        """
        let configuration = makeConfiguration(customConditions: ["ENABLED"])

        let callables = try createSUT(configuration: configuration)
            .analyze(source: source, file: "Conditional.swift")

        #expect(callables.map(\.name) == ["enabled()"])
        #expect(callables.map(\.complexity) == [2])
    }

    @Test func `inventory mode excludes conditional operators from complexity`() throws {
        let source = """
        func run() {
        #if FIRST && SECOND || THIRD
            if true { }
        #else
            while false { }
        #endif
        }
        """

        let callables = try createSUT().analyze(source: source, file: "Conditional.swift")

        #expect(callables.map(\.complexity) == [3])
    }

    @Test func `configured analysis selects else when conditions are false`() throws {
        let source = """
        #if ENABLED
        func enabled() { }
        #else
        func disabled() { }
        #endif
        """

        let callables = try createSUT(configuration: makeConfiguration())
            .analyze(source: source, file: "Conditional.swift")

        #expect(callables.map(\.name) == ["disabled()"])
    }

    @Test func `active nested clauses determine switch complexity`() throws {
        let source = """
        func classify(_ value: Int) {
            switch value {
            #if OUTER && SECOND
                #if INNER
                case 1: break
                #else
                case 2: break
                case 3: break
                #endif
            #else
                case 4: break
                case 5: break
                case 6: break
            #endif
            default: break
            }
        }
        """
        let configuration = makeConfiguration(customConditions: ["OUTER", "SECOND", "INNER"])

        let callables = try createSUT(configuration: configuration)
            .analyze(source: source, file: "Switch.swift")

        #expect(callables.map(\.complexity) == [2])
    }

    @Test func `active analysis retains original source coordinates`() throws {
        let source = """
        #if OMITTED
        func omitted() { }
        #else

        func retained() {
            print("retained")
        }
        #endif
        """

        let callables = try createSUT(configuration: makeConfiguration())
            .analyze(source: source, file: "Coordinates.swift")

        let callable = try #require(callables.first)
        #expect(callable.span == span(5, 1, 7, 2))
        #expect(callable.bodySpan == span(5, 17, 7, 2))
    }

    @Test func `configuration answers compiler conditions`() throws {
        let source = """
        #if canImport(CompilerKnown) && compiler(>=6.3) && swift(>=6) && hasFeature(StrictConcurrency)
        func supported() { }
        #else
        func unsupported() { }
        #endif
        """
        let configuration = TestingBuildConfiguration(
            importableModules: ["CompilerKnown"],
            features: ["StrictConcurrency"],
        )

        let callables = try createSUT(configuration: configuration)
            .analyze(source: source, file: "CompilerConditions.swift")

        #expect(callables.map(\.name) == ["supported()"])
    }

    @Test func `unparsed future accessor retains active inventory`() throws {
        let configuration = TestingBuildConfiguration(
            importableModules: [],
            features: ["Lifetimes", "NonescapableTypes"],
        )

        let callables = try createSUT(configuration: configuration)
            .analyze(source: ownershipSource, file: "Ownership.swift")

        #expect(callables.map(\.name) == [
            "Resource.init(_: consuming Value)",
            "Resource.value.unsafeAddress",
            "Resource.value.unsafeMutableAddress",
            "Resource.release()",
        ])
    }

    @Test func `unparsed future syntax errors are ignored`() throws {
        let configuration = TestingBuildConfiguration(importableModules: [], features: [])

        let callables = try createSUT(configuration: configuration)
            .analyze(source: futureSyntax(condition: "compiler(>=99)"), file: "Future.swift")

        #expect(callables.map(\.name) == ["current()"])
    }

    @Test func `active future syntax errors throw`() {
        let configuration = TestingBuildConfiguration(importableModules: [], features: [])

        #expect(throws: (any Error).self) {
            try createSUT(configuration: configuration)
                .analyze(source: futureSyntax(condition: "compiler(>=6.3)"), file: "Future.swift")
        }
    }

    @Test func `parsed inactive syntax errors throw`() {
        let configuration = TestingBuildConfiguration(importableModules: [], features: [])

        #expect(throws: (any Error).self) {
            try createSUT(configuration: configuration)
                .analyze(source: futureSyntax(condition: "FUTURE"), file: "Future.swift")
        }
    }

    @Test func `unavailable compiler condition answer throws`() {
        let source = """
        #if canImport(CompilerKnown)
        func supported() { }
        #else
        func unsupported() { }
        #endif
        """

        #expect(throws: (any Error).self) {
            try createSUT(configuration: makeConfiguration())
                .analyze(source: source, file: "Unavailable.swift")
        }
    }

    @Test func `unknown conditional expression throws`() {
        let source = """
        #if futureCondition(value)
        func future() { }
        #endif
        """

        #expect(throws: (any Error).self) {
            try createSUT(configuration: makeConfiguration())
                .analyze(source: source, file: "Unknown.swift")
        }
    }

    @Test func `traverses written macro closures`() throws {
        let source = "#perform { if true { } }"

        let callables = try createSUT().analyze(source: source, file: "Macro.swift")

        #expect(callables.map(\.kind) == [.closure])
        #expect(callables.map(\.complexity) == [2])
    }

    @Test func `malformed source throws`() {
        let source = "func broken( {"

        #expect(throws: (any Error).self) {
            try createSUT().analyze(source: source, file: "Broken.swift")
        }
    }

    private func createSUT() -> SwiftSourceAnalyzer {
        SwiftSourceAnalyzer()
    }

    private func createSUT(configuration: some BuildConfiguration) -> SwiftSourceAnalyzer {
        SwiftSourceAnalyzer(configuration: configuration)
    }

    private func makeConfiguration(customConditions: Set<String> = []) -> StaticBuildConfiguration {
        StaticBuildConfiguration(
            customConditions: customConditions,
            languageVersion: VersionTuple(6),
            compilerVersion: VersionTuple(6, 3),
        )
    }

    private func futureSyntax(condition: String) -> String {
        """
        #if \(condition)
        func future() {
            let value =
        }
        #else
        func current() { }
        #endif
        """
    }

    private var ownershipSource: String {
        """
        @safe
        struct Resource<Value: ~Copyable>: ~Copyable {
            init(_ value: consuming Value) {
                unsafe _ = value
            }
            var value: Value {
            #if compiler(>=6.4) && PREVIEW
                borrow { _pointer.pointee }
                mutate { &_pointer.pointee }
            #else
                unsafeAddress { fatalError() }
                unsafeMutableAddress { fatalError() }
            #endif
            }
            consuming func release() {
                discard self
            }
        }
        """
    }

    private func span(_ startLine: Int, _ startColumn: Int, _ endLine: Int, _ endColumn: Int) -> SourceSpan {
        SourceSpan(
            start: SourcePosition(line: startLine, column: startColumn),
            end: SourcePosition(line: endLine, column: endColumn),
        )
    }
}

private struct TestingBuildConfiguration: BuildConfiguration {
    let importableModules: Set<String>
    let features: Set<String>
    var customConditions: Set<String> = []

    func isCustomConditionSet(name: String) -> Bool {
        customConditions.contains(name)
    }

    func hasFeature(name: String) -> Bool {
        features.contains(name)
    }

    func hasAttribute(name _: String) -> Bool {
        false
    }

    func canImport(importPath: [(TokenSyntax, String)], version _: CanImportVersion) -> Bool {
        guard let module = importPath.first?.1 else { return false }
        return importableModules.contains(module)
    }

    func isActiveTargetOS(name _: String) -> Bool {
        false
    }

    func isActiveTargetArchitecture(name _: String) -> Bool {
        false
    }

    func isActiveTargetEnvironment(name _: String) -> Bool {
        false
    }

    func isActiveTargetRuntime(name _: String) -> Bool {
        false
    }

    func isActiveTargetPointerAuthentication(name _: String) -> Bool {
        false
    }

    func isActiveTargetObjectFormat(name _: String) -> Bool {
        false
    }

    var targetPointerBitWidth: Int {
        64
    }

    var targetAtomicBitWidths: [Int] {
        [32, 64]
    }

    var endianness: SwiftIfConfig.Endianness {
        .little
    }

    var languageVersion: VersionTuple {
        VersionTuple(6)
    }

    var compilerVersion: VersionTuple {
        VersionTuple(6, 3)
    }
}
