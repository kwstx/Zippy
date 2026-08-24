import Vapor
import Fluent
import Foundation

struct ReceiptController {
    
    // MARK: - Handlers
    
    @Sendable
    func upload(req: Request) async throws -> UploadResponse {
        // Decode the multipart form-data
        let input: ReceiptUpload
        do {
            input = try req.content.decode(ReceiptUpload.self)
        } catch {
            req.logger.warning("Failed to decode receipt upload: \(error)")
            throw Abort(.badRequest, reason: "Invalid upload format or missing 'image' field.")
        }
        
        let imageFile = input.image
        
        // Basic validation: ensure we have data
        guard imageFile.data.readableBytes > 0 else {
            throw Abort(.badRequest, reason: "Uploaded image is empty.")
        }
        
        // Determine storage path
        guard let storageDir = req.application.storage[ReceiptStorageKey.self] else {
            throw Abort(.internalServerError, reason: "Storage configuration missing.")
        }
        
        // Generate temporary reference identifier
        let referenceId = UUID().uuidString
        let fileName = "\(referenceId).jpg"
        
        let fileURL = URL(fileURLWithPath: storageDir).appendingPathComponent(fileName)
        
        // Write bytes to disk
        do {
            let data = Data(buffer: imageFile.data)
            try data.write(to: fileURL)
            req.logger.info("Successfully saved receipt to \(fileURL.path)")
        } catch {
            req.logger.error("Failed to write receipt image to disk: \(error)")
            throw Abort(.internalServerError, reason: "Failed to save the receipt image.")
        }
        
        return UploadResponse(referenceId: referenceId)
    }
    
    /// Triggers AI extraction on a previously uploaded receipt image.
    @Sendable
    func extract(req: Request) async throws -> ExtractedReceipt {
        guard let referenceId = req.parameters.get("referenceId") else {
            throw Abort(.badRequest, reason: "Missing referenceId parameter.")
        }
        
        // Check if already extracted
        if let existing = try await ExtractedReceipt.query(on: req.db)
            .filter(\.$referenceId == referenceId)
            .first() {
            return existing
        }
        
        // Run AI extraction
        let receipt = try await ExtractionService.extract(
            referenceId: referenceId,
            app: req.application
        )
        
        // Save to database
        try await receipt.save(on: req.db)
        
        req.logger.info("Extracted and saved receipt for referenceId: \(referenceId)")
        return receipt
    }
    
    /// Retrieves a previously extracted receipt by its database ID.
    @Sendable
    func getResult(req: Request) async throws -> ExtractedReceipt {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid or missing receipt ID.")
        }
        
        guard let receipt = try await ExtractedReceipt.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "No extracted receipt found with ID: \(id)")
        }
        
        return receipt
    }
}
