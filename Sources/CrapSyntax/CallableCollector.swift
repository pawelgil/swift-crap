import CrapCore
import SwiftIfConfig
import SwiftSyntax

final class CallableCollector: SyntaxVisitor {
    private(set) var callables: [Callable] = []

    private let file: String
    private let locations: SourceLocationConverter
    private let configuredRegions: ConfiguredRegions?
    private let borrowAndMutateEnabled: Bool
    private var callableContexts: [CallableContext] = []
    private var closureCounts: [String: Int] = [:]
    private var conditionalContexts: [String] = []
    private var pushedCallableNodes: Set<SyntaxIdentifier> = []
    private var typeContexts: [String] = []

    init(
        file: String,
        syntax: SourceFileSyntax,
        configuredRegions: ConfiguredRegions?,
        borrowAndMutateEnabled: Bool,
    ) {
        self.file = file
        self.configuredRegions = configuredRegions
        self.borrowAndMutateEnabled = borrowAndMutateEnabled
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

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let configuredRegions else {
            return .visitChildren
        }
        if let activeClause = configuredRegions.activeClause(for: node) {
            conditionalContexts.append(SignatureFormatter.conditionalClause(activeClause))
            if let elements = activeClause.elements {
                walk(elements)
            }
            conditionalContexts.removeLast()
        }
        return .skipChildren
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
        guard let owner = AccessorOwner(node: Syntax(node)) else {
            return .visitChildren
        }
        if let recovered = recoveredHelperCall(in: node) {
            addRecoveredGetter(node: node, owner: owner, helperBody: recovered)
            return .skipChildren
        }
        guard case .getter = node.accessors else { return .visitChildren }
        if let configuredRegions {
            let collector = ConditionalAccessorCollector(
                accessorBlockID: node.id,
                configuredRegions: configuredRegions,
                borrowAndMutateEnabled: borrowAndMutateEnabled,
            )
            collector.walk(node)
            if !collector.accessors.isEmpty {
                addConditionalAccessors(collector.accessors, owner: owner)
                return .skipChildren
            }
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
            complexity: ComplexityVisitor.measure(body, configuredRegions: configuredRegions),
            parentID: callableContexts.last?.id,
        )
        callables.append(callable)
    }

    private func addConditionalAccessors(
        _ accessors: [(FunctionCallExprSyntax, String, [String])],
        owner: AccessorOwner,
    ) {
        for (node, specifier, contexts) in accessors {
            guard let body = node.trailingClosure, let kind = accessorKind(specifier) else { continue }
            conditionalContexts.append(contentsOf: contexts)
            addCallable(
                node: node,
                body: body,
                name: qualified(owner.signature + "." + accessorSuffix(specifier)),
                kind: kind(owner),
            )
            pushCallable(nodeID: node.id)
            walk(body.statements)
            popCallable(nodeID: node.id)
            conditionalContexts.removeLast(contexts.count)
        }
    }

    private func addRecoveredGetter(
        node: AccessorBlockSyntax,
        owner: AccessorOwner,
        helperBody: CodeBlockSyntax,
    ) {
        let name = qualified(owner.signature + ".getter")
        addCallable(node: owner.declaration, body: node, name: name, kind: owner.getterKind)
        pushCallable(nodeID: node.id)
        addCallable(node: helperBody, body: helperBody, name: nextClosureName(), kind: .closure)
        pushCallable(nodeID: helperBody.id)
        walk(helperBody.statements)
        popCallable(nodeID: helperBody.id)
        popCallable(nodeID: node.id)
    }

    private func recoveredHelperCall(in node: AccessorBlockSyntax) -> CodeBlockSyntax? {
        guard !borrowAndMutateEnabled,
              case let .accessors(accessors) = node.accessors,
              accessors.count == 1,
              let accessor = accessors.first,
              ["borrow", "mutate"].contains(accessor.accessorSpecifier.text)
        else { return nil }
        return accessor.body
    }

    private func accessorKind(_ specifier: String) -> ((AccessorOwner) -> CallableKind)? {
        switch specifier {
        case "borrow" where borrowAndMutateEnabled:
            { $0.getterKind }
        case "get", "unsafeAddress", "_read":
            { $0.getterKind }
        case "mutate" where borrowAndMutateEnabled:
            { $0.setterKind }
        case "set", "unsafeMutableAddress", "_modify":
            { $0.setterKind }
        case "didSet", "willSet":
            { _ in .observer }
        default:
            nil
        }
    }

    private func accessorSuffix(_ specifier: String) -> String {
        switch specifier {
        case "get": "getter"
        case "set": "setter"
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
