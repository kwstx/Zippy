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
    @MainActor
    static func fetchGroups() async throws -> [PersistentGroup] {
        guard let url = URL(string: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in AuthService.shared.authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try jsonDecoder.decode([PersistentGroup].self, from: data)
    }

    /// Creates a new persistent group with an initial roster of participants and base currency.
    @MainActor
    static func createGroup(name: String, members: [Participant], currency: String = "USD") async throws -> PersistentGroup {
        guard let url = URL(string: baseURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in AuthService.shared.authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let ownerId = AuthService.shared.currentUser?.id.uuidString
        let payload = CreateGroupPayload(
            name: name,
            members: members.map { .init(id: $0.id, name: $0.name) },
            currency: currency,
            ownerId: ownerId
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to create group"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let group = try jsonDecoder.decode(PersistentGroup.self, from: data)
        if AuthService.shared.isAuthenticated {
            Task {
                await AuthService.shared.refreshProfile()
            }
        }
        return group
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

    /// Appends an expense transaction event into the group's backend ledger with currency conversion.
    static func addExpense(
        groupId: UUID,
        title: String,
        amount: Double,
        currency: String = "USD",
        targetCurrency: String = "USD",
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
            currency: currency,
            targetCurrency: targetCurrency,
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

    /// Appends a settlement transaction event into the group's backend ledger with currency conversion.
    static func addSettlement(
        groupId: UUID,
        payerId: UUID,
        payeeId: UUID,
        amount: Double,
        currency: String = "USD",
        targetCurrency: String = "USD",
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
            currency: currency,
            targetCurrency: targetCurrency,
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

    // MARK: - Recurring Expenses

    /// Fetches all recurring expense templates configured for a group.
    static func fetchRecurringExpenses(groupId: UUID) async throws -> [RecurringExpenseTemplate] {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/recurring-expenses") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to fetch recurring templates"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode([RecurringExpenseTemplate].self, from: data)
    }

    /// Stores a new recurring expense template on the backend.
    static func createRecurringExpense(
        groupId: UUID,
        title: String,
        amount: Double,
        currency: String = "USD",
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [AddGroupExpensePayload.LedgerSplitPayload]? = nil,
        frequency: RecurringFrequency = .monthly,
        note: String? = nil,
        startDate: Date? = nil
    ) async throws -> RecurringExpenseTemplate {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/recurring-expenses") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CreateRecurringExpensePayload(
            title: title,
            amount: amount,
            currency: currency,
            payerId: payerId,
            splitMemberIds: splitMemberIds,
            splits: splits,
            frequency: frequency.rawValue,
            note: note,
            startDate: startDate
        )
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to create recurring template"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(RecurringExpenseTemplate.self, from: data)
    }

    /// Deletes a recurring expense template.
    static func deleteRecurringExpense(groupId: UUID, templateId: UUID) async throws {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/recurring-expenses/\(templateId.uuidString)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Toggles the active state of a recurring expense template.
    static func toggleRecurringExpense(groupId: UUID, templateId: UUID) async throws -> RecurringExpenseTemplate {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/recurring-expenses/\(templateId.uuidString)/toggle") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to toggle recurring template"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(RecurringExpenseTemplate.self, from: data)
    }

    /// Triggers immediate cron-like cloning evaluation for recurring templates in a group.
    static func processRecurringExpenses(groupId: UUID) async throws -> ProcessRecurringExpensesResponse {
        guard let url = URL(string: "\(baseURL)/\(groupId.uuidString)/recurring-expenses/process") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to process recurring expenses"
            throw NSError(domain: "GroupService", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        return try jsonDecoder.decode(ProcessRecurringExpensesResponse.self, from: data)
    }
}
