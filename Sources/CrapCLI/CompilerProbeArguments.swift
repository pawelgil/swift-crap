struct CompilerProbeArguments {
    func prepare(_ arguments: [String]) throws -> [String] {
        let removedValues: Set = ["-o", "-output-file-map", "-emit-module-path", "-emit-module-interface-path",
                                  "-emit-private-module-interface-path", "-emit-objc-header-path",
                                  "-serialize-diagnostics-path",
                                  "-index-store-path", "-index-unit-output-path", "-module-cache-path", "-num-threads",
                                  "-j", "-filelist",
                                  "-supplementary-output-file-map", "-emit-dependencies-path",
                                  "-emit-reference-dependencies-path",
                                  "-emit-module-doc-path", "-emit-module-source-info-path",
                                  "-emit-const-values-path",
                                  "-emit-abi-descriptor-path", "-save-optimization-record-path", "-emit-tbd-path",
                                  "-primary-file"]
        let removed: Set = ["-c", "-emit-module", "-emit-library", "-emit-executable", "-emit-object",
                            "-emit-objc-header", "-emit-dependencies", "-emit-module-interface",
                            "-serialize-diagnostics",
                            "-incremental", "-enable-batch-mode", "-disable-batch-mode", "-parseable-output",
                            "-use-frontend-parseable-output",
                            "-whole-module-optimization",
                            "-wmo", "-profile-generate", "-profile-coverage-mapping", "-frontend", "-typecheck",
                            "-v"]
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if removedValues.contains(argument) {
                guard index < arguments.count else { throw ProvenanceError.invalid("missing value for \(argument)") }
                index += 1
            } else if argument == "-Xcc" || argument == "-Xfrontend" {
                guard index < arguments.count else { throw ProvenanceError.invalid("missing value for \(argument)") }
                result += [argument, arguments[index]]
                index += 1
            } else if argument.hasPrefix("@") {
                throw ProvenanceError.invalid("unexpanded compiler response file: \(argument)")
            } else if !removed.contains(argument), !argument.hasSuffix(".swift"),
                      !(argument.hasPrefix("-j") && Int(argument.dropFirst(2)) != nil)
            {
                result.append(argument)
            }
        }
        return result
    }
}
