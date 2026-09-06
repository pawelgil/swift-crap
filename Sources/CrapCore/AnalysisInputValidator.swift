struct AnalysisInputValidator {
    private let geometry = SourceGeometry()
    private let path = AnalysisPath()

    func validate(threshold: Double) throws {
        guard threshold.isFinite, threshold >= 0 else {
            throw AnalysisError.invalidThreshold
        }
    }

    func validate(root: String) throws -> String {
        try path.root(root)
    }

    func validate(callables: [Callable]) throws {
        guard !callables.isEmpty else {
            throw AnalysisError.emptyCallableInventory
        }
        try validateCallableSet(callables)
    }

    func validateCallableSet(_ callables: [Callable]) throws {
        var indexed: [String: Callable] = [:]
        for callable in callables {
            try validate(callable: callable)
            guard indexed.updateValue(callable, forKey: callable.id) == nil else {
                throw AnalysisError.duplicateCallableID(callable.id)
            }
        }
        for callable in callables {
            try validateParent(of: callable, indexed: indexed)
        }
    }

    func validate(coverage: [CoverageRecord]) throws {
        for record in coverage {
            try validate(record: record)
        }
    }

    private func validate(callable: Callable) throws {
        let normalizedFile = path.normalizedRelative(callable.file)
        let valid = !callable.id.isEmpty
            && normalizedFile == callable.file
            && !callable.file.hasPrefix("/")
            && !callable.file.contains("\\")
            && !callable.name.isEmpty
            && callable.complexity > 0
            && geometry.isValid(callable.span)
            && geometry.isValid(callable.bodySpan)
            && geometry.contains(callable.span, callable.bodySpan)
        guard valid else {
            throw AnalysisError.invalidCallable(callable.id)
        }
    }

    private func validateParent(of callable: Callable, indexed: [String: Callable]) throws {
        guard let parentID = callable.parentID else {
            return
        }
        guard parentID != callable.id,
              let parent = indexed[parentID],
              parent.file == callable.file,
              geometry.strictlyContains(parent.span, callable.span)
        else {
            throw AnalysisError.invalidCallable(callable.id)
        }
    }

    private func validate(record: CoverageRecord) throws {
        guard !record.file.isEmpty,
              !record.name.isEmpty,
              geometry.isValid(record.anchor),
              record.span.map(geometry.isValid) ?? true,
              record.span.map({ $0.contains(record.anchor) }) ?? true
        else {
            throw invalidCoverage(record)
        }
        try validateRepresentation(record)
    }

    private func validateRepresentation(_ record: CoverageRecord) throws {
        if let lines = record.lines {
            guard record.coveredLines == nil,
                  record.executableLines == nil,
                  Set(lines.map(\.line)).count == lines.count,
                  lines.allSatisfy({ $0.line > 0 }),
                  record.span.map({ span in lines.allSatisfy { geometry.intersects(span, line: $0.line) } }) ?? true
            else {
                throw invalidCoverage(record)
            }
            return
        }
        guard let covered = record.coveredLines,
              let executable = record.executableLines,
              covered >= 0,
              executable >= 0,
              covered <= executable
        else {
            throw invalidCoverage(record)
        }
    }

    private func invalidCoverage(_ record: CoverageRecord) -> AnalysisError {
        .invalidCoverage(recordName: record.name, file: record.file)
    }
}
