@testable import CrapCLI
import Testing

struct ShellArgumentsTests {
    @Test func `quotes spaces and backslashes preserve argument boundaries`() throws {
        let result = try ShellArguments().parse(
            #"one\ two 'three four' "five six" -DVALUE\=1 path\\name '' """#,
        )

        #expect(result == ["one two", "three four", "five six", "-DVALUE=1", "path\\name", "", ""])
    }

    @Test(arguments: ["'unterminated", "\"unterminated", "trailing\\"])
    func `malformed quoting fails closed`(_ text: String) {
        #expect(throws: SourceSelectionError.invalidXcodeMetadata("malformed SwiftDriver command line")) {
            try ShellArguments().parse(text)
        }
    }
}
