import Vapor

/// The expected multipart/form-data payload for a receipt upload.
struct ReceiptUpload: Content {
    /// The uploaded image file.
    let image: File
}

/// The expected multipart/form-data payload for a CSV file import.
struct CSVImportUpload: Content {
    /// The uploaded CSV file.
    let file: File?
    let csv: File?
    let data: String?
}
