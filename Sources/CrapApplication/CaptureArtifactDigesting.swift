public protocol CaptureArtifactDigesting {
    func read(at path: String) throws -> String
}
