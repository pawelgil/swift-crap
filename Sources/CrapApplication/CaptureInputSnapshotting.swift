public protocol CaptureInputSnapshotting {
    func read(root: String, excluding paths: [String]) throws -> [String: String]
}
