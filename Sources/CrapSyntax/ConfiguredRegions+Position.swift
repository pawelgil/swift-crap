import SwiftIfConfig
import SwiftSyntax

extension ConfiguredRegions {
    func state(at position: AbsolutePosition) -> IfConfigRegionState {
        reversed().first { region in
            let clause = region.ifClause
            let start = clause.condition?.endPosition
                ?? clause.elements.map { Syntax($0).position }
                ?? clause.poundKeyword.endPosition
            return (start ... clause.endPosition).contains(position)
        }?.state ?? .active
    }
}
