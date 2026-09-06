public protocol SourceSelecting {
    func select(_ request: SourceSelectionRequest) throws -> SelectedSources
}
