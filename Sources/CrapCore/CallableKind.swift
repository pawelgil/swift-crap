public enum CallableKind: String, Codable, Sendable {
    case closure
    case deinitializer
    case function
    case getter
    case initializer
    case observer
    case setter
    case subscriptGetter
    case subscriptSetter
}
