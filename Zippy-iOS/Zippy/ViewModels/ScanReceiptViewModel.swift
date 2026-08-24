// MARK: - ScanReceiptViewModel.swift

import SwiftUI
import Combine

@MainActor
final class ScanReceiptViewModel: ObservableObject {
    @Published var selectedImage: UIImage?
    @Published var isUploading: Bool = false
    @Published var referenceId: String?
    @Published var errorMessage: String?
    
    /// Compresses the selected image on a background queue and initiates the upload.
    func compressAndUpload() async {
        guard let image = selectedImage else { return }
        
        isUploading = true
        errorMessage = nil
        referenceId = nil
        
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
            self.selectedImage = nil // Reset after success if desired
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isUploading = false
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
