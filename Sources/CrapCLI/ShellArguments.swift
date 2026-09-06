import Foundation

struct ShellArguments {
    func parse(_ text: String) throws -> [String] {
        var parser = Parser()
        for character in text {
            parser.consume(character)
        }
        return try parser.finish()
    }

    private struct Parser {
        private var state = State.unquoted
        private var token = ""
        private var result: [String] = []
        private var started = false

        mutating func consume(_ character: Character) {
            switch state {
            case .doubleQuoted: consumeDoubleQuoted(character)
            case .escapedDoubleQuoted: consumeEscaped(character, returningTo: .doubleQuoted)
            case .escapedUnquoted: consumeEscaped(character, returningTo: .unquoted)
            case .singleQuoted: consumeSingleQuoted(character)
            case .unquoted: consumeUnquoted(character)
            }
        }

        mutating func finish() throws -> [String] {
            guard state == .unquoted else {
                throw SourceSelectionError.invalidXcodeMetadata("malformed SwiftDriver command line")
            }
            appendToken()
            return result
        }

        private mutating func consumeUnquoted(_ character: Character) {
            if character == "\\" {
                state = .escapedUnquoted
                started = true
            } else if character == "'" {
                state = .singleQuoted
                started = true
            } else if character == "\"" {
                state = .doubleQuoted
                started = true
            } else if character.isWhitespace {
                appendToken()
            } else {
                append(character)
            }
        }

        private mutating func consumeSingleQuoted(_ character: Character) {
            if character == "'" {
                state = .unquoted
            } else {
                append(character)
            }
        }

        private mutating func consumeDoubleQuoted(_ character: Character) {
            if character == "\"" {
                state = .unquoted
            } else if character == "\\" {
                state = .escapedDoubleQuoted
            } else {
                append(character)
            }
        }

        private mutating func consumeEscaped(_ character: Character, returningTo state: State) {
            append(character)
            self.state = state
        }

        private mutating func append(_ character: Character) {
            token.append(character)
            started = true
        }

        private mutating func appendToken() {
            guard started else { return }
            result.append(token)
            token = ""
            started = false
        }
    }

    private enum State {
        case doubleQuoted
        case escapedDoubleQuoted
        case escapedUnquoted
        case singleQuoted
        case unquoted
    }
}
