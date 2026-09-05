enum FixtureError: Error {
    case missingNativeFunction(String)
    case commandFailed(String, Int32)
}
