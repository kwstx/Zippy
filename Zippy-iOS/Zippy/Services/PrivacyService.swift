// MARK: - PrivacyService.swift

import Foundation

/// Service communicating with the Vapor backend privacy and data controls & deletion endpoints.
enum PrivacyService {
    static let baseURL = "http://localhost:8080/api/privacy"

    /// Privacy and data control toggle preferences.
    struct PrivacyControls: Codable {
        var storeReceiptImages: Bool
        var retainReceiptHistory: Bool
        var retainSplitSessions: Bool
        var retainGroupLedgers: Bool
        var allowAutomatedReminders: Bool
        var telemetryAndAnalytics: Bool
    }

    /// Payload for patching privacy control toggles.
    struct PatchPrivacyControlsPayload: Encodable {
        var storeReceiptImages: Bool?
        var retainReceiptHistory: Bool?
        var retainSplitSessions: Bool?
        var retainGroupLedgers: Bool?
        var allowAutomatedReminders: Bool?
        var telemetryAndAnalytics: Bool?
    }

    /// Response returned by privacy deletion and patch endpoints.
    struct PrivacyActionResponse: Decodable {
        let success: Bool
        let controls: PrivacyControls?
        let deletedCounts: [String: Int]
        let message: String
    }

    /// Shared device identity header for authenticated requests.
    private static var deviceId: String {
        SubscriptionManager.shared.deviceId
    }

    // MARK: - Controls (GET & PATCH)

    /// Fetches the user's active privacy controls and data retention toggles.
    static func fetchControls() async throws -> PrivacyControls {
        guard let url = URL(string: "\(baseURL)/controls") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Failed to fetch privacy controls"
            throw NSError(
                domain: "PrivacyService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        return try JSONDecoder().decode(PrivacyControls.self, from: data)
    }

    /// Authenticated PATCH that updates privacy toggles and immediately permanently purges associated
    /// records and object-storage files on the Vapor backend if toggled off.
    static func patchControls(_ payload: PatchPrivacyControlsPayload) async throws -> PrivacyActionResponse {
        guard let url = URL(string: "\(baseURL)/controls") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Failed to update privacy controls"
            throw NSError(
                domain: "PrivacyService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: body]
            )
        }

        return try JSONDecoder().decode(PrivacyActionResponse.self, from: data)
    }

    // MARK: - Explicit DELETE Endpoints

    /// Builds a DELETE request with the device identity header.
    private static func makeDeleteRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        return request
    }

    /// Executes a DELETE request and decodes the response.
    private static func executeDelete(path: String) async throws -> PrivacyActionResponse {
        let request = try makeDeleteRequest(path: path)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "PrivacyService",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Privacy delete failed: \(body)"]
            )
        }

        return try JSONDecoder().decode(PrivacyActionResponse.self, from: data)
    }

    /// Permanently deletes all receipt records and their on-disk image files.
    static func deleteReceipts() async throws -> PrivacyActionResponse {
        try await executeDelete(path: "receipts")
    }

    /// Permanently deletes all split sessions.
    static func deleteSplits() async throws -> PrivacyActionResponse {
        try await executeDelete(path: "splits")
    }

    /// Permanently deletes all groups, ledger events, and recurring expense templates.
    static func deleteGroups() async throws -> PrivacyActionResponse {
        try await executeDelete(path: "groups")
    }

    /// Permanently deletes all payment reminder logs.
    static func deleteReminders() async throws -> PrivacyActionResponse {
        try await executeDelete(path: "reminders")
    }

    /// Full account wipe: deletes all receipts, splits, groups, reminders, and subscription records.
    static func deleteAllData() async throws -> PrivacyActionResponse {
        try await executeDelete(path: "all")
    }
}
