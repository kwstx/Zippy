// MARK: - GroupService.swift

import Foundation

/// Service communicating with the Vapor backend for persistent groups and ledger tables.
enum GroupService {
    static let baseURL = "http://localhost:8080/api/groups"

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

    /// Fetches all persistent groups with calculated running balances.
    static func fetchGroups() async throws -> [PersistentGroup] {
        guard let url = URL(string: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try jsonDecoder.decode([PersistentGroup].self, from: data)
    }

    /// Creates a new persistent group with an initial roster of participants.
    static func createGroup(name: String, members: [Participant]) async throws -> PersistentGroup {
        guard let url = URL(string: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateGroupPayload(
            name: name,
            members: members.map { .init(id: $0.id, name: $0.name) }
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to create group"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(PersistentGroup.self, from: data)
    }

    /// Loads the complete append-only event stream history and member balances from the backend ledger tables.
    static func fetchGroupHistory(groupId: UUID) async throws -> GroupLedgerHistoryResponse {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/history") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to load ledger history"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(GroupLedgerHistoryResponse.self, from: data)
    }

    /// Appends an expense transaction event into the group's backend ledger.
    static func addExpense(
        groupId: UUID,
        title: String,
        amount: Double,
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [AddGroupExpensePayload.LedgerSplitPayload]? = nil,
        receiptId: UUID? = nil,
        note: String? = nil
    ) async throws -> LedgerEvent {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/expenses") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AddGroupExpensePayload(
            title: title,
            amount: amount,
            payerId: payerId,
            splitMemberIds: splitMemberIds,
            splits: splits,
            receiptId: receiptId,
            note: note
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to append expense"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(LedgerEvent.self, from: data)
    }

    /// Appends a settlement transaction event into the group's backend ledger.
    static func addSettlement(
        groupId: UUID,
        payerId: UUID,
        payeeId: UUID,
        amount: Double,
        note: String? = nil
    ) async throws -> LedgerEvent {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/settlements") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = AddGroupSettlementPayload(
            payerId: payerId,
            payeeId: payeeId,
            amount: amount,
            note: note
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to append settlement"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(LedgerEvent.self, from: data)
    }

    /// Fetches continuous simplified debt transfers calculated by the server's minimum-cash-flow algorithm for a group.
    static func fetchSimplifiedPayments(groupId: UUID) async throws -> SimplifyExpensesAPIResponse {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/simplified") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to fetch simplified payments"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(SimplifyExpensesAPIResponse.self, from: data)
    }

    /// Deletes a persistent group and its append-only ledger entries.
    static func deleteGroup(groupId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
