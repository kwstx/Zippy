// MARK: - ScanReceiptViewModel.swift

import SwiftUI
import Combine

@MainActor
final class ScanReceiptViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var isUploading: Bool = false
    @Published var isExtracting: Bool = false
    @Published var referenceId: String?
    @Published var extractedReceipt: ExtractedReceiptResponse?
    @Published var errorMessage: String?
    
    /// Compresses the selected image on a background queue and initiates the upload.
    func compressAndUpload() async {
        guard let image = selectedImage else { return }
        
        isUploading = true
        errorMessage = nil
        referenceId = nil
        extractedReceipt = nil
        
        do {
            // Compress image on a background task
            let compressedData = try await Task.detached(priority: .userInitiated) {
                guard let data = image.jpegData(compressionQuality: 0.7) else {
                    throw UploadError.compressionFailed
                }
                return data
            }.value
            
            // Upload
            let refId = try await ReceiptService.upload(imageData: compressedData)
            
            self.referenceId = refId
            self.selectedImage = nil // Reset after success
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isUploading = false
    }
    
    /// Triggers AI extraction on the server for the uploaded receipt.
    func extractReceipt() async {
        guard let referenceId = referenceId else {
            errorMessage = "No uploaded receipt to extract."
            return
        }
        
        isExtracting = true
        errorMessage = nil
        
        do {
            let receipt = try await ReceiptService.extractReceipt(referenceId: referenceId)
            self.extractedReceipt = receipt
        } catch {
            self.errorMessage = "Extraction failed: \(error.localizedDescription)"
        }
        
        isExtracting = false
    }
}

enum UploadError: Error, LocalizedError {
    case compressionFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress the image."
        }
    }
}
