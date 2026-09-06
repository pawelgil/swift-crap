public func included(_ value: Bool) -> Int {
    if value {
        return 1
    }
    return 0
}

public func selectClosure(_ useFirst: Bool) -> Int {
    choose({ 1 }, second: { 2 }, useFirst: useFirst)
}

private func choose(_ first: () -> Int, second: () -> Int, useFirst: Bool) -> Int {
    useFirst ? first() : second()
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
