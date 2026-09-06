public func included(_ value: Bool) -> Int {
    if value {
        return 1
    }
    return 0
}

#if DEBUG
    public func configuration() -> String {
        "debug"
    }
#else
    public func configuration() -> String {
        "release"
    }
#endif
