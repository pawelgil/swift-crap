public protocol CaptureCommandRunning {
    func run(_ command: [String], root: String) throws
}
