// MARK: - ReceiptService.swift

import Foundation

/// Response from the server after finalizing a split session.
struct SplitSessionResponse: Decodable {
    let id: UUID
    let receiptId: UUID
    let participants: [SplitParticipantDTO]
    let balances: [SplitBalanceDTO]
    let receiptTotal: Double
    let shareableURL: String?
    let createdAt: String?

    struct SplitParticipantDTO: Decodable {
        let id: UUID
        let name: String
    }

    struct SplitBalanceDTO: Decodable, Identifiable {
        var id: UUID { participantId }
        let participantId: UUID
        let name: String
        let itemsSubtotal: Double
        let taxShare: Double
        let tipShare: Double
        let total: Double
    }
}

extension SplitSessionResponse {
    /// Converts server balance DTOs to the app's PersonBalance model.
    var appBalances: [PersonBalance] {
        balances.map {
            PersonBalance(
                participantId: $0.participantId,
                name: $0.name,
                itemsSubtotal: $0.itemsSubtotal,
                taxShare: $0.taxShare,
                tipShare: $0.tipShare,
                total: $0.total
            )
        }
    }
}

/// Defines the response structure expected from the backend
struct UploadResponse: Decodable {
    let referenceId: String
}

/// A service to handle receipt uploads and extraction
enum ReceiptService {
    static let baseURL = "http://localhost:8080/api/receipts"
    
    /// Uploads image data via a multipart/form-data POST request
    /// - Parameter imageData: The compressed JPEG data
    /// - Returns: The referenceId from the server
    static func upload(imageData: Data) async throws -> String {
        guard let url = URL(string: "\(baseURL)/upload") else {
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
    
    /// Triggers AI extraction for a previously uploaded receipt.
    /// - Parameter referenceId: The reference ID returned from upload.
    /// - Returns: The full extracted receipt data.
    static func extractReceipt(referenceId: String) async throws -> ExtractedReceiptResponse {
        guard let url = URL(string: "\(baseURL)/\(referenceId)/extract") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // AI extraction can take a while
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ReceiptService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Extraction failed: \(body)"]
            )
        }
        
        let decoder = JSONDecoder()
        let receipt = try decoder.decode(ExtractedReceiptResponse.self, from: data)
        return receipt
    }

    /// Sends split data to the server for authoritative computation and persistence.
    /// - Parameters:
    ///   - receiptId: The database UUID of the extracted receipt.
    ///   - participants: The people splitting the bill.
    ///   - assignments: Item index (as string) → array of participant UUIDs.
    /// - Returns: The server-computed split session response.
    static func finalizeSplit(
        receiptId: UUID,
        participants: [Participant],
        assignments: [String: [UUID]]
    ) async throws -> SplitSessionResponse {
        guard let url = URL(string: "http://localhost:8080/api/splits") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct CreateSplitRequest: Encodable {
            let receiptId: UUID
            let participants: [ParticipantPayload]
            let assignments: [String: [UUID]]

            struct ParticipantPayload: Encodable {
                let id: UUID
                let name: String
            }
        }

        let payload = CreateSplitRequest(
            receiptId: receiptId,
            participants: participants.map { .init(id: $0.id, name: $0.name) },
            assignments: assignments
        )

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ReceiptService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Split finalization failed: \(body)"]
            )
        }

        return try JSONDecoder().decode(SplitSessionResponse.self, from: data)
    }

    /// Fetches a previously finalized split session by its ID (for shareable links).
    /// - Parameter sessionId: The UUID of the split session.
    /// - Returns: The split session data.
    static func getSplit(sessionId: UUID) async throws -> SplitSessionResponse {
        guard let url = URL(string: "http://localhost:8080/api/splits/\(sessionId)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SplitSessionResponse.self, from: data)
    }
}
