public protocol CaptureReceiptWriting {
    func write(_ receipt: CaptureReceipt, to path: String) throws
}
