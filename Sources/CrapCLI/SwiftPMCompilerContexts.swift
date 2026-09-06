import CrapApplication
import Foundation

struct SwiftPMCompilerContexts {
    func read(at path: String, root: String) throws -> [CompilerContext] {
        let description = try JSONDecoder().decode(Description.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard !description.swiftCommands.isEmpty else {
            throw ProvenanceError.invalid("build description contains no Swift compiler commands")
        }
        return description.swiftCommands.values.sorted { $0.moduleName < $1.moduleName }.map {
            CompilerContext(
                compiler: $0.executable,
                arguments: ["-I", $0.importPath] + $0.otherArguments,
                directory: root,
                sources: $0.sources,
                moduleName: $0.moduleName,
            )
        }
    }

    private struct Description: Decodable {
        let swiftCommands: [String: Command]
    }

    private struct Command: Decodable {
        let executable: String
        let importPath: String
        let moduleName: String
        let otherArguments: [String]
        let sources: [String]
    }
}
