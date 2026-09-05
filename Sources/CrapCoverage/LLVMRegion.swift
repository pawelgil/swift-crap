import CrapCore

struct LLVMRegion {
    let start: SourcePosition
    let end: SourcePosition
    let count: Int
    let fileIndex: Int
    let kind: Int
}
