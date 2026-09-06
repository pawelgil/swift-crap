import CrapApplication
import Foundation

struct ReceiptSourceSelector: SourceSelecting {
    let receipt: CaptureReceipt

    func select(_ request: SourceSelectionRequest) throws -> SelectedSources {
        if case let .xcode(selection) = request.scope {
            return try xcode(selection, exclusions: request.exclusions)
        }
        let selected = try LocalSourceSelector().select(request)
        let files = try selected.files.map { source in
            guard source.path.hasPrefix(receipt.root + "/") else {
                throw ProvenanceError.invalid("selected source escapes captured root: \(source.path)")
            }
            return SelectedSource(
                path: source.path,
                relativePath: String(source.path.dropFirst(receipt.root.count + 1)),
            )
        }
        return SelectedSources(root: receipt.root, files: files)
    }

    private func xcode(_ selection: XcodeSelection, exclusions: [String]) throws -> SelectedSources {
        try requireMatchingXcodeSelection(selection)
        let paths = try Set(receipt.contexts.flatMap { context in
            try context.sources.map { try CanonicalPath().resolve($0, relativeTo: context.directory) }
        })
        let files = try paths.sorted().flatMap { try capturedFile(at: $0, exclusions: exclusions) }
        return SelectedSources(root: receipt.root, files: files)
    }

    private func requireMatchingXcodeSelection(_ selection: XcodeSelection) throws {
        guard let captured = receipt.xcode else {
            throw ProvenanceError.invalid("receipt has no captured Xcode selection")
        }
        let project = try CanonicalPath().resolve(selection.project)
        guard project == captured.project,
              selection.scheme == captured.scheme,
              selection.target == captured.target,
              selection.configuration == captured.configuration,
              selection.destination == captured.destination
        else {
            throw ProvenanceError.invalid("requested Xcode selection differs from capture")
        }
    }

    private func capturedFile(at path: String, exclusions: [String]) throws -> [SelectedSource] {
        guard path.hasPrefix(receipt.root + "/") else {
            throw ProvenanceError.invalid("captured Xcode source escapes root: \(path)")
        }
        let relative = String(path.dropFirst(receipt.root.count + 1))
        guard receipt.inputs[relative] != nil else {
            throw ProvenanceError.invalid("captured Xcode source is not an input: \(relative)")
        }
        return try LocalSourceSelector().select(SourceSelectionRequest(
            scope: .file(path),
            rootOverride: receipt.root,
            exclusions: exclusions,
        )).files
    }
}
