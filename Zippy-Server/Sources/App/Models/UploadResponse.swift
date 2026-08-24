import Vapor

/// The response returned after a successful receipt upload.
struct UploadResponse: Content {
    /// A temporary reference identifier for the uploaded receipt.
    let referenceId: String
}
