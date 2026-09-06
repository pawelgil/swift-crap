import CrapApplication

struct XcodeProjectMetadata: Equatable {
    let sourceFiles: [String]
    let compilerContexts: [CompilerContext]
}
