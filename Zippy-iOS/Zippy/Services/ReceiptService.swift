// MARK: - ReceiptService.swift

import Foundation

/// Defines the response structure expected from the backend
struct UploadResponse: Decodable {
    let referenceId: String
}

/// A service to handle receipt uploads
enum ReceiptService {
    static let baseURL = "http://localhost:8080/api/receipts/upload"
    
    /// Uploads image data via a multipart/form-data POST request
    /// - Parameter imageData: The compressed JPEG data
    /// - Returns: The referenceId from the server
    static func upload(imageData: Data) async throws -> String {
        guard let url = URL(string: baseURL) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add the image part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End the multipart form data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        return uploadResponse.referenceId
    }
}
