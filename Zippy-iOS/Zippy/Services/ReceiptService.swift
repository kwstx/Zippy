// MARK: - ReceiptService.swift

import Foundation

/// Response from the server after finalizing a split session.
struct SplitSessionResponse: Decodable {
    let id: UUID
    let receiptId: UUID
    let participants: [SplitParticipantDTO]
    let balances: [SplitBalanceDTO]
    let receiptTotal: Double
    let category: String?
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
        let isPaid: Bool?
        let paidAt: Date?
        let paymentMethod: String?
        let settlementStatus: SettlementStatus?
    }
}

/// Response returned when selecting an external payment method.
struct SelectPaymentMethodResponse: Decodable {
    let success: Bool
    let participantId: UUID
    let paymentMethod: String
    let settlementStatus: SettlementStatus
    let deepLink: String?
    let instructions: String?
    let message: String
}

/// Response returned from Vapor minimum-cash-flow algorithm.
struct SimplifyExpensesAPIResponse: Decodable {
    let transfers: [SimplifiedPayment]
    let lines: [String]
    let totalTransferred: Double
    let originalExpenseCount: Int
    let transferCount: Int
}

/// An expense sent to the backend for debt simplification.
struct ExpenseDTO: Codable {
    let id: UUID?
    let title: String?
    let amount: Double
    let paidBy: UUID
    let splitWith: [UUID]?
    let splits: [ExpenseSplitDTO]?

    struct ExpenseSplitDTO: Codable {
        let participantId: UUID
        let amount: Double?
    }

    init(
        id: UUID? = nil,
        title: String? = nil,
        amount: Double,
        paidBy: UUID,
        splitWith: [UUID]? = nil,
        splits: [ExpenseSplitDTO]? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.paidBy = paidBy
        self.splitWith = splitWith
        self.splits = splits
    }
}


extension SplitSessionResponse {
    /// Converts server balance DTOs to the app's PersonBalance model.
    var appBalances: [PersonBalance] {
        balances.map {
            let status = $0.settlementStatus ?? ($0.isPaid == true ? .settled : ($0.paymentMethod != nil ? .pendingConfirmation : .unpaid))
            return PersonBalance(
                participantId: $0.participantId,
                name: $0.name,
                itemsSubtotal: $0.itemsSubtotal,
                taxShare: $0.taxShare,
                tipShare: $0.tipShare,
                total: $0.total,
                isPaid: $0.isPaid ?? (status == .settled),
                paidAt: $0.paidAt,
                paymentMethod: $0.paymentMethod,
                settlementStatus: status
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

    /// Creates a manually entered receipt directly on the backend.
    /// - Parameter payload: Receipt line items, subtotal, tax, tip, total, and category.
    /// - Returns: Newly created ExtractedReceiptResponse with server-assigned UUID.
    static func createManualReceipt(payload: PatchReceiptPayload) async throws -> ExtractedReceiptResponse {
        guard let url = URL(string: "\(baseURL)/manual") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ReceiptService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create manual receipt: \(body)"]
            )
        }

        return try JSONDecoder().decode(ExtractedReceiptResponse.self, from: data)
    }

    /// Immediately PATCH-es receipt modifications to the Vapor backend for re-validation and link state updates.
    /// - Parameters:
    ///   - id: The receipt's UUID.
    ///   - payload: Updated fields (items, subtotal, tax, tip, total, category).
    /// - Returns: PatchReceiptResponse containing validated receipt, validation report, and updated shareable link.
    static func patchReceipt(id: UUID, payload: PatchReceiptPayload) async throws -> PatchReceiptResponse {
        guard let url = URL(string: "\(baseURL)/\(id)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ReceiptService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to PATCH receipt: \(body)"]
            )
        }

        return try JSONDecoder().decode(PatchReceiptResponse.self, from: data)
    }

    /// Sends split data to the server for authoritative computation and persistence.
    /// - Parameters:
    ///   - receiptId: The database UUID of the extracted receipt.
    ///   - participants: The people splitting the bill.
    ///   - assignments: Item index (as string) → array of participant UUIDs.
    ///   - category: Optional category tag ("restaurants", "trips", "roommates", "everyday").
    /// - Returns: The server-computed split session response.
    static func finalizeSplit(
        receiptId: UUID,
        participants: [Participant],
        assignments: [String: [UUID]],
        category: String? = nil
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
            let category: String?

            struct ParticipantPayload: Encodable {
                let id: UUID
                let name: String
            }
        }

        let payload = CreateSplitRequest(
            receiptId: receiptId,
            participants: participants.map { .init(id: $0.id, name: $0.name) },
            assignments: assignments,
            category: category
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

    /// Records the chosen payment method on the backend.
    static func selectPaymentMethod(
        token: String,
        participantId: UUID,
        method: String
    ) async throws -> SelectPaymentMethodResponse {
        guard let url = URL(string: "http://localhost:8080/s/\(token)/select-payment-method") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable {
            let participantId: UUID
            let paymentMethod: String
        }

        request.httpBody = try JSONEncoder().encode(Payload(participantId: participantId, paymentMethod: method))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SelectPaymentMethodResponse.self, from: data)
    }

    /// Manually confirms settlement for a participant.
    static func confirmSettlement(
        token: String,
        participantId: UUID
    ) async throws {
        guard let url = URL(string: "http://localhost:8080/s/\(token)/confirm") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Encodable {
            let participantId: UUID
            let confirmedBy: String?
        }

        request.httpBody = try JSONEncoder().encode(Payload(participantId: participantId, confirmedBy: "host"))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
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

    /// Fetches a previously finalized split session by its short share token.
    /// - Parameter token: The cryptographically random share token.
    /// - Returns: The split session data.
    static func getSplitByToken(token: String) async throws -> SplitSessionResponse {
        guard let url = URL(string: "http://localhost:8080/s/\(token)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SplitSessionResponse.self, from: data)
    }

    /// Calls the pure-Swift minimum-cash-flow engine on the Vapor backend to optimize multiple expenses.
    static func simplifyExpenses(
        participants: [Participant],
        expenses: [ExpenseDTO]
    ) async throws -> SimplifyExpensesAPIResponse {
        guard let url = URL(string: "http://localhost:8080/api/splits/simplify") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct RequestBody: Encodable {
            let participants: [ParticipantPayload]
            let expenses: [ExpenseDTO]

            struct ParticipantPayload: Encodable {
                let id: UUID
                let name: String
            }
        }

        let payload = RequestBody(
            participants: participants.map { .init(id: $0.id, name: $0.name) },
            expenses: expenses
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SimplifyExpensesAPIResponse.self, from: data)
    }

    /// Fetches simplified payments for a token from the Vapor backend.
    static func getSimplifiedPayments(token: String) async throws -> SimplifyExpensesAPIResponse {
        guard let url = URL(string: "http://localhost:8080/s/\(token)/simplified") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(SimplifyExpensesAPIResponse.self, from: data)
    }

    /// Updates the optional category tag on an extracted receipt.
    static func updateReceiptCategory(receiptId: UUID, category: String?) async throws {
        guard let url = URL(string: "http://localhost:8080/api/receipts/\(receiptId)/category") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct CategoryPayload: Encodable {
            let category: String?
        }

        request.httpBody = try JSONEncoder().encode(CategoryPayload(category: category))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Updates the optional category tag on an active split session via token.
    static func updateSplitCategory(token: String, category: String?) async throws {
        guard let url = URL(string: "http://localhost:8080/s/\(token)/category") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct CategoryPayload: Encodable {
            let category: String?
        }

        request.httpBody = try JSONEncoder().encode(CategoryPayload(category: category))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Fetches receipt and split history powered by optional category and search filters.
    static func fetchHistory(
        category: ReceiptCategory? = nil,
        search: String? = nil
    ) async throws -> [HistoryItem] {
        var components = URLComponents(string: "http://localhost:8080/api/splits/history")
        var queryItems: [URLQueryItem] = []

        if let cat = category {
            queryItems.append(URLQueryItem(name: "category", value: cat.rawValue))
        }
        if let q = search, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: q.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryItem].self, from: data)
    }
}

/// A historical receipt or split session entry returned by search/history filtering.
struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let receiptId: UUID?
    let title: String
    let category: String?
    let total: Double
    let createdAt: Date?
    let participantCount: Int
    let isSettled: Bool
    let shareableURL: String?
    let itemsSummary: [String]?

    var parsedCategory: ReceiptCategory? {
        ReceiptCategory(flexibleString: category)
    }
}

