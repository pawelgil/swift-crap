protocol CompilerConditionEvaluating: AnyObject {
    func evaluate(_ condition: String) throws -> Bool
}
