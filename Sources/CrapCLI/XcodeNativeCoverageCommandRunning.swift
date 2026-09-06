import Foundation

protocol XcodeNativeCoverageCommandRunning {
    func run(arguments: [String]) throws -> (output: Data, error: Data, status: Int32)
}
