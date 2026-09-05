import Foundation

enum CoverageRecordClassification {
    case authoredClosure
    case generated
    case named

    init(name: String) {
        let generatedDemangled = #"(?i)(?:implicit closure|autoclosure) #[0-9]+ in "#
        let authoredDemangled = #"(?i)closure #[0-9]+ in "#
        let generatedMangled = #"(?:cfu|XEfu|FfA)[0-9]*_$"#
        let authoredMangled = #"(?:cfU|XEfU)[0-9]*_$"#
        if Self.matches(name, pattern: generatedDemangled)
            || Self.matchesMangled(name, pattern: generatedMangled)
        {
            self = .generated
        } else if Self.matches(name, pattern: authoredDemangled)
            || Self.matchesMangled(name, pattern: authoredMangled)
        {
            self = .authoredClosure
        } else {
            self = .named
        }
    }

    private static func matches(_ name: String, pattern: String) -> Bool {
        name.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matchesMangled(_ name: String, pattern: String) -> Bool {
        name.contains("$s") && matches(name, pattern: pattern)
    }
}
