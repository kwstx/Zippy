import Vapor

/// The expected multipart/form-data payload for a receipt upload.
struct ReceiptUpload: Content {
    /// The uploaded image file.
    let image: File
}
