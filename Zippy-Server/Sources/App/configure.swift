import Vapor
import Foundation

// configures your application
public func configure(_ app: Application) async throws {
    // Set max body size for uploads (e.g., 10MB)
    app.routes.defaultMaxBodySize = "10mb"
    
    // Determine storage path from environment or use default
    let storagePath = Environment.get("RECEIPT_STORAGE_PATH") ?? "./Storage/Receipts/"
    
    // Ensure the directory exists
    let fm = FileManager.default
    if !fm.fileExists(atPath: storagePath) {
        do {
            try fm.createDirectory(atPath: storagePath, withIntermediateDirectories: true, attributes: nil)
            app.logger.info("Created storage directory at \(storagePath)")
        } catch {
            app.logger.error("Failed to create storage directory at \(storagePath): \(error)")
            throw error
        }
    } else {
        app.logger.info("Using existing storage directory at \(storagePath)")
    }
    
    // Store configuration in app.storage for easy access in controllers
    app.storage[ReceiptStorageKey.self] = storagePath

    // register routes
    try routes(app)
}

struct ReceiptStorageKey: StorageKey {
    typealias Value = String
}
