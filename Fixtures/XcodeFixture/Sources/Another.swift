public func another() -> Int {
    2
}

#if os(iOS) && targetEnvironment(simulator)
    public func simulatorOnly() -> Int {
        3
    }
#else
    public func nonSimulatorOnly() -> Int {
        4
    }
#endif
