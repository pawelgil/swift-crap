import SwiftIfConfig
import SwiftSyntax

final class ConditionalAccessorCollector: SyntaxVisitor {
    private(set) var accessors: [(FunctionCallExprSyntax, String, [String])] = []
    private let accessorBlockID: SyntaxIdentifier
    private let borrowAndMutateEnabled: Bool
    private let configuredRegions: ConfiguredRegions
    private var conditionalContexts: [String] = []

    init(
        accessorBlockID: SyntaxIdentifier,
        configuredRegions: ConfiguredRegions,
        borrowAndMutateEnabled: Bool,
    ) {
        self.accessorBlockID = accessorBlockID
        self.configuredRegions = configuredRegions
        self.borrowAndMutateEnabled = borrowAndMutateEnabled
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !conditionalContexts.isEmpty,
              let item = node.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self),
              list.parent?.is(IfConfigClauseSyntax.self) == true,
              isAtAccessorBoundary(node),
              let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
              let specifier = specifiers.first(where: { $0 == reference.baseName.text }),
              node.trailingClosure != nil
        else {
            return .visitChildren
        }
        accessors.append((node, specifier, conditionalContexts))
        return .skipChildren
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let activeClause = configuredRegions.activeClause(for: node) else {
            return .skipChildren
        }
        conditionalContexts.append(SignatureFormatter.conditionalClause(activeClause))
        if let elements = activeClause.elements {
            walk(elements)
        }
        conditionalContexts.removeLast()
        return .skipChildren
    }

    private var specifiers: [String] {
        let ownership = borrowAndMutateEnabled ? ["borrow", "mutate"] : []
        return ownership + ["unsafeAddress", "unsafeMutableAddress", "_modify", "_read"]
    }

    private func isAtAccessorBoundary(_ node: FunctionCallExprSyntax) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if let accessorBlock = current.as(AccessorBlockSyntax.self) {
                return accessorBlock.id == accessorBlockID
            }
            guard current.is(CodeBlockItemSyntax.self)
                || current.is(CodeBlockItemListSyntax.self)
                || current.is(IfConfigClauseSyntax.self)
                || current.is(IfConfigClauseListSyntax.self)
                || current.is(IfConfigDeclSyntax.self)
            else { return false }
            ancestor = current.parent
        }
        return false
    }
}
