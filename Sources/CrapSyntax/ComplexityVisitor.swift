import SwiftSyntax

final class ComplexityVisitor: SyntaxVisitor {
    private(set) var complexity = 1
    private let rootID: SyntaxIdentifier

    static func measure(_ body: some SyntaxProtocol) -> Int {
        let visitor = ComplexityVisitor(rootID: body.id)
        let syntax = Syntax(body)
        if let closure = syntax.as(ClosureExprSyntax.self) {
            visitor.walk(closure.statements)
        } else if let accessorBlock = syntax.as(AccessorBlockSyntax.self),
                  case let .getter(statements) = accessorBlock.accessors
        {
            visitor.walk(statements)
        } else {
            visitor.walk(syntax)
        }
        return visitor.complexity
    }

    private init(rootID: SyntaxIdentifier) {
        self.rootID = rootID
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        node.id == rootID ? .visitChildren : .skipChildren
    }

    override func visit(_: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if ["&&", "||", "??"].contains(node.operator.text) {
            complexity += 1
        }
        return .visitChildren
    }

    override func visit(_: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        node.id == rootID ? .visitChildren : .skipChildren
    }

    override func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: ConditionElementListSyntax) -> SyntaxVisitorContinueKind {
        complexity += max(0, node.count - 1)
        return .visitChildren
    }

    override func visit(_: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += node.whereClause == nil ? 1 : 2
        return .visitChildren
    }

    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_: IfExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if case .case = node.label {
            complexity += 1
        }
        return .visitChildren
    }

    override func visit(_: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }

    override func visit(_: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        return .visitChildren
    }
}
