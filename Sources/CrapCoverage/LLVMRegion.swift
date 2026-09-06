import CrapCore

package struct LLVMRegion {
    package let start: SourcePosition
    package let end: SourcePosition
    package let count: Int
    package let fileIndex: Int
    package let kind: Int

    package init(start: SourcePosition, end: SourcePosition, count: Int, fileIndex: Int, kind: Int) {
        self.start = start
        self.end = end
        self.count = count
        self.fileIndex = fileIndex
        self.kind = kind
    }
}
