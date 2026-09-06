import CrapCore
import SwiftSyntax

struct AccessorOwner {
    let declaration: Syntax
    let getterKind: CallableKind
    let setterKind: CallableKind
    let signature: String

    init?(node: Syntax) {
        var ancestor = node.parent
        while let current = ancestor {
            if let binding = current.as(PatternBindingSyntax.self),
               let variable = current.firstAncestor(VariableDeclSyntax.self)
            {
                declaration = Syntax(binding)
                getterKind = .getter
                setterKind = .setter
                signature = SignatureFormatter.variable(binding, declaration: variable)
                return
            }
            if let subscriptDeclaration = current.as(SubscriptDeclSyntax.self) {
                declaration = Syntax(subscriptDeclaration)
                getterKind = .subscriptGetter
                setterKind = .subscriptSetter
                signature = SignatureFormatter.subscriptDeclaration(subscriptDeclaration)
                return
            }
            ancestor = current.parent
        }
        return nil
    }
}

private extension Syntax {
    func firstAncestor<Node: SyntaxProtocol>(_ type: Node.Type) -> Node? {
        var ancestor = parent
        while let current = ancestor {
            if let match = current.as(type) {
                return match
            }
            ancestor = current.parent
        }
        return nil
    }
}
