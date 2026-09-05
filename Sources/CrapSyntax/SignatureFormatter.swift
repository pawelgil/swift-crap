import SwiftSyntax

enum SignatureFormatter {
    static func conditionalClause(_ node: IfConfigClauseSyntax) -> String {
        guard let clauses = node.parent?.as(IfConfigClauseListSyntax.self) else {
            return conditionalHeader(node)
        }
        var headers: [String] = []
        for clause in clauses {
            headers.append(conditionalHeader(clause))
            if clause.id == node.id {
                break
            }
        }
        return headers.joined(separator: "/")
    }

    static func extensionName(_ node: ExtensionDeclSyntax) -> String {
        tokenText(node.extendedType) + requirements(node.genericWhereClause, brackets: true)
    }

    static func function(_ node: FunctionDeclSyntax) -> String {
        declarationModifier(node.modifiers)
            + node.name.text
            + genericParameters(node.genericParameterClause)
            + parameters(node.signature.parameterClause.parameters)
            + effects(node.signature.effectSpecifiers)
            + returnType(node.signature.returnClause)
            + requirements(node.genericWhereClause)
    }

    static func initializer(_ node: InitializerDeclSyntax) -> String {
        "init"
            + (node.optionalMark?.text ?? "")
            + genericParameters(node.genericParameterClause)
            + parameters(node.signature.parameterClause.parameters)
            + effects(node.signature.effectSpecifiers)
            + requirements(node.genericWhereClause)
    }

    static func subscriptDeclaration(_ node: SubscriptDeclSyntax) -> String {
        declarationModifier(node.modifiers)
            + "subscript"
            + genericParameters(node.genericParameterClause)
            + parameters(node.parameterClause.parameters)
            + returnType(node.returnClause)
            + requirements(node.genericWhereClause)
    }

    static func variable(_ binding: PatternBindingSyntax, declaration: VariableDeclSyntax) -> String {
        declarationModifier(declaration.modifiers) + tokenText(binding.pattern)
    }

    private static func effects(_ effects: FunctionEffectSpecifiersSyntax?) -> String {
        effects.map { " " + tokenText($0) } ?? ""
    }

    private static func genericParameters(_ clause: GenericParameterClauseSyntax?) -> String {
        clause.map(tokenText) ?? ""
    }

    private static func parameters(_ parameters: FunctionParameterListSyntax) -> String {
        let values = parameters.map { parameter in
            let label = parameter.firstName.text
            let type = parameterType(parameter)
            return label + ": " + type
        }
        return "(" + values.joined(separator: ", ") + ")"
    }

    private static func parameterType(_ parameter: FunctionParameterSyntax) -> String {
        let components = [
            tokenText(parameter.attributes),
            tokenText(parameter.modifiers),
            tokenText(parameter.type),
        ].filter { !$0.isEmpty }
        return components.joined(separator: " ") + (parameter.ellipsis == nil ? "" : "...")
    }

    private static func requirements(_ clause: GenericWhereClauseSyntax?) -> String {
        requirements(clause, brackets: false)
    }

    private static func requirements(_ clause: GenericWhereClauseSyntax?, brackets: Bool) -> String {
        guard let clause else {
            return ""
        }
        let value = tokenText(clause)
        return brackets ? "[" + value + "]" : " " + value
    }

    private static func returnType(_ clause: ReturnClauseSyntax?) -> String {
        clause.map { " -> " + tokenText($0.type) } ?? ""
    }

    private static func declarationModifier(_ modifiers: DeclModifierListSyntax) -> String {
        guard let modifier = modifiers.first(where: { ["class", "static"].contains($0.name.text) }) else {
            return ""
        }
        return modifier.name.text + " "
    }

    private static func conditionalHeader(_ node: IfConfigClauseSyntax) -> String {
        let condition = node.condition.map { " " + tokenText($0) } ?? ""
        return node.poundKeyword.text + condition
    }

    private static func tokenText(_ node: some SyntaxProtocol) -> String {
        let spaced = node.tokens(viewMode: .sourceAccurate).map(\.text).joined(separator: " ")
        return [
            (" < ", "<"), (" <", "<"), ("< ", "<"), (" >", ">"),
            (" (", "("), ("( ", "("), (" )", ")"),
            (" [", "["), ("[ ", "["), (" ]", "]"),
            (" .", "."), (". ", "."), (" ,", ","), (" :", ":"),
            (" ?", "?"), (" !", "!"), (" @ ", "@"), ("@ ", "@"),
        ].reduce(spaced) { result, replacement in
            result.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }
}
