import CrapApplication
import Foundation

final class CompilerProbe: CompilerConditionEvaluating {
    private let context: CompilerContext
    private let arguments: [String]
    private var answers: [String: Bool] = [:]

    init(context: CompilerContext) throws {
        self.context = context
        arguments = try CompilerProbeArguments().prepare(context.arguments)
    }

    func evaluate(_ condition: String) throws -> Bool {
        if let answer = answers[condition] { return answer }
        let capture = try CaptureFiles()
        defer { capture.remove() }
        let source = capture.directory.appendingPathComponent("Condition.swift")
        let text = "#if \(condition)\n#error(\"SWIFT_CRAP_TRUE\")\n#else\n#error(\"SWIFT_CRAP_FALSE\")\n#endif\n"
        try Data(text.utf8).write(to: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: context.compiler)
        process.currentDirectoryURL = URL(fileURLWithPath: context.directory)
        process.arguments = arguments + ["-typecheck", "-module-cache-path", capture.cacheURL.path, source.path]
        process.standardOutput = capture.output
        process.standardError = capture.error
        try process.run()
        process.waitUntilExit()
        capture.close()
        let diagnostics = try String(decoding: capture.errorData(), as: UTF8.self)
        let answer = try interpret(diagnostics, status: process.terminationStatus, condition: condition)
        answers[condition] = answer
        return answer
    }

    private func interpret(_ diagnostics: String, status: Int32, condition: String) throws -> Bool {
        let errors = diagnostics.split(separator: "\n").filter { $0.contains(": error:") }
        guard status != 0, errors.count == 1, let error = errors.first,
              !diagnostics.contains(": warning:")
        else {
            throw ProvenanceError.invalid("compiler cannot evaluate \(condition): \(diagnostics)")
        }
        if error.hasSuffix(": error: SWIFT_CRAP_TRUE") { return true }
        if error.hasSuffix(": error: SWIFT_CRAP_FALSE") { return false }
        throw ProvenanceError.invalid("compiler cannot evaluate \(condition): \(diagnostics)")
    }
}
