import CrapCore
import SwiftSyntax

final class CallableCollector: SyntaxVisitor {
    private(set) var callables: [Callable] = []

    private let file: String
    private let locations: SourceLocationConverter
    private var callableContexts: [CallableContext] = []
    private var closureCounts: [String: Int] = [:]
    private var conditionalContexts: [String] = []
    private var pushedCallableNodes: Set<SyntaxIdentifier> = []
    private var typeContexts: [String] = []

    init(file: String, syntax: SourceFileSyntax) {
        self.file = file
        locations = SourceLocationConverter(fileName: file, tree: syntax)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text)
    }

    override func visitPost(_: ActorDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text)
    }

    override func visitPost(_: ClassDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        let name = nextClosureName()
        addCallable(node: node, body: node, name: name, kind: .closure)
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        popCallable(nodeID: node.id)
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .visitChildren
        }
        let name = qualified("deinit")
        addCallable(node: node, body: body, name: name, kind: .deinitializer)
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) {
        popCallable(nodeID: node.id)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text)
    }

    override func visitPost(_: EnumDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(SignatureFormatter.extensionName(node))
    }

    override func visitPost(_: ExtensionDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .visitChildren
        }
        let name = qualified(SignatureFormatter.function(node))
        addCallable(node: node, body: body, name: name, kind: .function)
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        popCallable(nodeID: node.id)
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else {
            return .visitChildren
        }
        let name = qualified(SignatureFormatter.initializer(node))
        addCallable(node: node, body: body, name: name, kind: .initializer)
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        popCallable(nodeID: node.id)
    }

    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        conditionalContexts.append(SignatureFormatter.conditionalClause(node))
        return .visitChildren
    }

    override func visitPost(_: IfConfigClauseSyntax) {
        conditionalContexts.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text)
    }

    override func visitPost(_: ProtocolDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text)
    }

    override func visitPost(_: StructDeclSyntax) {
        typeContexts.removeLast()
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        guard case .getter = node.accessors,
              let owner = AccessorOwner(node: Syntax(node))
        else {
            return .visitChildren
        }
        let name = qualified(owner.signature + ".getter")
        addCallable(node: owner.declaration, body: node, name: name, kind: owner.getterKind)
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: AccessorBlockSyntax) {
        popCallable(nodeID: node.id)
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body,
              let kind = accessorKind(node.accessorSpecifier.text),
              let owner = AccessorOwner(node: Syntax(node))
        else {
            return .visitChildren
        }
        let suffix = accessorSuffix(node.accessorSpecifier.text)
        let name = qualified(owner.signature + "." + suffix)
        addCallable(node: node, body: body, name: name, kind: kind(owner))
        pushCallable(nodeID: node.id)
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        popCallable(nodeID: node.id)
    }

    private func addCallable(
        node: some SyntaxProtocol,
        body: some SyntaxProtocol,
        name: String,
        kind: CallableKind,
    ) {
        let id = ([file, kind.rawValue, name] + conditionalContexts).joined(separator: "::")
        let callable = Callable(
            id: id,
            file: file,
            name: name,
            kind: kind,
            span: span(of: node),
            bodySpan: span(of: body),
            complexity: ComplexityVisitor.measure(body),
            parentID: callableContexts.last?.id,
        )
        callables.append(callable)
    }

    private func accessorKind(_ specifier: String) -> ((AccessorOwner) -> CallableKind)? {
        switch specifier {
        case "get", "_read":
            { $0.getterKind }
        case "set", "_modify":
            { $0.setterKind }
        case "didSet", "willSet":
            { _ in .observer }
        default:
            nil
        }
    }

    private func accessorSuffix(_ specifier: String) -> String {
        switch specifier {
        case "get", "_read": "getter"
        case "set", "_modify": "setter"
        default: specifier
        }
    }

    private func nextClosureName() -> String {
        let prefix = qualifiedPrefix()
        let ownerKey = ([callableContexts.last?.id ?? "scope", prefix] + conditionalContexts).joined(separator: "::")
        let count = closureCounts[ownerKey, default: 0] + 1
        closureCounts[ownerKey] = count
        return [prefix, "$closure\(count)"].filter { !$0.isEmpty }.joined(separator: ".")
    }

    private func popCallable(nodeID: SyntaxIdentifier) {
        guard pushedCallableNodes.remove(nodeID) != nil else {
            return
        }
        callableContexts.removeLast()
    }

    private func pushCallable(nodeID: SyntaxIdentifier) {
        guard let callable = callables.last else {
            return
        }
        callableContexts.append(CallableContext(id: callable.id, name: callable.name, typeDepth: typeContexts.count))
        pushedCallableNodes.insert(nodeID)
    }

    private func pushType(_ name: String) -> SyntaxVisitorContinueKind {
        typeContexts.append(name)
        return .visitChildren
    }

    private func qualified(_ name: String) -> String {
        let prefix = qualifiedPrefix()
        return [prefix, name].filter { !$0.isEmpty }.joined(separator: ".")
    }

    private func qualifiedPrefix() -> String {
        guard let callableContext = callableContexts.last else {
            return typeContexts.joined(separator: ".")
        }
        let localTypes = typeContexts.dropFirst(callableContext.typeDepth)
        return ([callableContext.name] + localTypes).joined(separator: ".")
    }

    private func span(of node: some SyntaxProtocol) -> SourceSpan {
        SourceSpan(
            start: position(node.positionAfterSkippingLeadingTrivia),
            end: position(node.endPositionBeforeTrailingTrivia),
        )
    }

    private func position(_ absolutePosition: AbsolutePosition) -> SourcePosition {
        let location = locations.location(for: absolutePosition)
        return SourcePosition(line: location.line, column: location.column)
    }
}
