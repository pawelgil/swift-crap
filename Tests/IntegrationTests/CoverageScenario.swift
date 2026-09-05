import Testing

struct CoverageScenario: CustomTestStringConvertible {
    let name: String
    let body: String
    let input: Int

    var testDescription: String {
        name
    }

    var source: String {
        "enum Subject {\n    static func run(_ value: Int) -> Int {\n\(body)\n    }\n}"
    }

    static let cases: [CoverageScenario] = [
        .init(name: "same-line else executes", body: "if value > 0 { return 1 } else { return 2 }", input: 0),
        .init(name: "same-line then executes", body: "if value > 0 { return 1 } else { return 2 }", input: 1),
        .init(name: "multiline ternary second arm", body: "return value > 0\n    ? 1\n    : 2", input: 0),
        .init(name: "multiline ternary first arm", body: "return value > 0\n    ? 1\n    : 2", input: 1),
        .init(name: "guard early exit", body: "guard value > 0 else {\n    return 0\n}\nreturn value", input: 0),
        .init(name: "guard continuation", body: "guard value > 0 else {\n    return 0\n}\nreturn value", input: 1),
        .init(
            name: "switch second case",
            body: "switch value {\ncase 1: return 1\ncase 2: return 2\ndefault: return 0\n}",
            input: 2,
        ),
        .init(
            name: "empty loop",
            body: "var sum = 0\nfor n in 0..<value where n > 0 {\n    sum += n\n}\nreturn sum",
            input: 0,
        ),
        .init(
            name: "executed loop",
            body: "var sum = 0\nfor n in 0..<value where n > 0 {\n    sum += n\n}\nreturn sum",
            input: 3,
        ),
        .init(
            name: "short circuit skips rhs",
            body: "if value > 0 &&\n    value < 3 {\n    return 1\n}\nreturn 0",
            input: 0,
        ),
        .init(
            name: "short circuit executes rhs",
            body: "if value > 0 &&\n    value < 3 {\n    return 1\n}\nreturn 0",
            input: 1,
        ),
        .init(
            name: "defer and early return",
            body: "var result = value\ndefer { result += 1 }\nif value == 0 { return result }\nreturn result * 2",
            input: 0,
        ),
        .init(
            name: "compile-time conditional",
            body: "#if NEVER_DEFINED\nreturn value * 2\n#else\nreturn value\n#endif",
            input: 1,
        ),
    ]
}
