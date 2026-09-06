public protocol CapturePathPreparing {
    func prepare(_ request: CaptureRequest) throws -> CapturePaths
}
