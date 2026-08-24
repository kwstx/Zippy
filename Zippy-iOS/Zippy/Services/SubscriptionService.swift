// MARK: - SubscriptionService.swift

import Foundation

/// Service communicating with the Vapor backend subscription endpoints.
enum SubscriptionService {
    static let baseURL = "http://localhost:8080/api/subscription"

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Fetches the current user's subscription status and feature gates from the backend.
    static func fetchStatus(userId: String) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/status/\(userId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userId, forHTTPHeaderField: "X-Device-Id")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to fetch subscription status"
            throw NSError(domain: "SubscriptionService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(SubscriptionStatus.self, from: data)
    }

    /// Submits a native StoreKit transaction token to the backend for authoritative verification and tier activation.
    static func verifyStoreKitTransaction(
        userId: String,
        productId: String,
        originalTransactionId: String,
        transactionReceipt: String? = nil,
        expiresAt: Date? = nil
    ) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/verify") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-Device-Id")

        struct VerifyPayload: Encodable {
            let userId: String
            let productId: String
            let originalTransactionId: String
            let transactionReceipt: String?
            let expiresAt: Date?
        }

        let payload = VerifyPayload(
            userId: userId,
            productId: productId,
            originalTransactionId: originalTransactionId,
            transactionReceipt: transactionReceipt,
            expiresAt: expiresAt
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to verify transaction with backend"
            throw NSError(domain: "SubscriptionService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(SubscriptionStatus.self, from: data)
    }

    /// Upgrades the user tier directly for testing or server promotions.
    static func upgradeTier(
        userId: String,
        tier: String = "pro",
        productId: String? = "com.zippy.app.pro.monthly"
    ) async throws -> SubscriptionStatus {
        guard let url = URL(string: "\(baseURL)/upgrade") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-Device-Id")

        struct UpgradePayload: Encodable {
            let userId: String
            let tier: String
            let productId: String?
            let durationDays: Int?
        }

        let payload = UpgradePayload(userId: userId, tier: tier, productId: productId, durationDays: 365)
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to upgrade tier"
            throw NSError(domain: "SubscriptionService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(SubscriptionStatus.self, from: data)
    }
}
