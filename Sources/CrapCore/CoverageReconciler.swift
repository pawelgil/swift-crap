struct CoverageReconciler {
    private let geometry = SourceGeometry()
    private let path = AnalysisPath()
    private let root: String

    init(root: String) {
        self.root = root
    }

    func reconcile(_ records: [CoverageRecord], with callables: [Callable]) throws -> [String: [CoverageRecord]] {
        let indexed = Dictionary(grouping: callables) { path.canonical($0.file, root: root) }
        var result: [String: [CoverageRecord]] = [:]
        for record in records {
            let normalized = normalized(record)
            guard let candidates = indexed[normalized.file],
                  let match = try match(normalized, candidates: candidates)
            else {
                continue
            }
            guard owns(normalized, callable: match) else {
                throw AnalysisError.invalidCoverage(recordName: normalized.name, file: normalized.file)
            }
            result[match.id, default: []].append(normalized)
        }
        return result
    }

    private func normalized(_ record: CoverageRecord) -> CoverageRecord {
        CoverageRecord(
            file: path.canonical(record.file, root: root),
            name: record.name,
            span: record.span,
            anchor: record.anchor,
            lines: record.lines,
            coveredLines: record.coveredLines,
            executableLines: record.executableLines,
        )
    }

    private func match(_ record: CoverageRecord, candidates: [Callable]) throws -> Callable? {
        switch CoverageRecordClassification(name: record.name) {
        case .authoredClosure:
            return try matchClosure(record, candidates: candidates.filter { $0.kind == .closure })
        case .generated:
            return nil
        case .named:
            break
        }
        let exact = candidates.filter { $0.span.contains(record.anchor) }
        if !exact.isEmpty {
            return try selectExact(record, candidates: exact)
        }
        guard record.anchor.column == 1 else {
            return nil
        }
        let lineMatches = candidates.filter { geometry.intersects($0.span, line: record.anchor.line) }
        return try lineMatches.isEmpty ? nil : selectUncertain(record, candidates: lineMatches)
    }

    private func matchClosure(_ record: CoverageRecord, candidates: [Callable]) throws -> Callable? {
        let exact = candidates.filter { $0.span.start == record.anchor }
        if !exact.isEmpty {
            return try exact.count == 1 ? exact.first : uniqueName(record, candidates: exact)
        }
        guard record.anchor.column == 1 else {
            return nil
        }
        let lineMatches = candidates.filter { $0.span.start.line == record.anchor.line }
        return try lineMatches.isEmpty ? nil : selectUncertain(record, candidates: lineMatches)
    }

    private func selectExact(_ record: CoverageRecord, candidates: [Callable]) throws -> Callable? {
        let mostSpecific = candidates.filter { candidate in
            !candidates.contains { other in
                other.id != candidate.id && geometry.strictlyContains(candidate.span, other.span)
            }
        }
        return try mostSpecific.count == 1 ? mostSpecific.first : uniqueName(record, candidates: mostSpecific)
    }

    private func selectUncertain(_ record: CoverageRecord, candidates: [Callable]) throws -> Callable? {
        try candidates.count == 1 ? candidates.first : uniqueName(record, candidates: candidates)
    }

    private func uniqueName(_ record: CoverageRecord, candidates: [Callable]) throws -> Callable? {
        let named = candidates.filter { $0.name == record.name }
        guard named.count == 1 else {
            throw AnalysisError.ambiguousCoverage(recordName: record.name, file: record.file)
        }
        return named.first
    }

    private func owns(_ record: CoverageRecord, callable: Callable) -> Bool {
        let ownsSpan = record.span.map { geometry.contains(callable.span, $0) } ?? true
        let ownsLines = record.lines?.allSatisfy { geometry.intersects(callable.span, line: $0.line) } ?? true
        return ownsSpan && ownsLines
    }
}
