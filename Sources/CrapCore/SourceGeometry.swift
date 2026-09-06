struct SourceGeometry {
    func isValid(_ position: SourcePosition) -> Bool {
        position.line > 0 && position.column > 0
    }

    func isValid(_ span: SourceSpan) -> Bool {
        isValid(span.start) && isValid(span.end) && span.start < span.end
    }

    func contains(_ outer: SourceSpan, _ inner: SourceSpan) -> Bool {
        outer.start <= inner.start && inner.end <= outer.end
    }

    func strictlyContains(_ outer: SourceSpan, _ inner: SourceSpan) -> Bool {
        outer != inner && contains(outer, inner)
    }

    func intersects(_ span: SourceSpan, line: Int) -> Bool {
        span.start.line <= line
            && (line < span.end.line || line == span.end.line && span.end.column > 1)
    }
}
