// MARK: - RecurringExpenseModels.swift

import Foundation

/// Plain text frequency options for recurring expense templates.
enum RecurringFrequency: String, CaseIterable, Identifiable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var id: String { rawValue }

    /// Plain text display title.
    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// Short plain text badge.
    var shortCode: String {
        switch self {
        case .daily: return "DAILY"
        case .weekly: return "WEEKLY"
        case .biweekly: return "2-WEEKS"
        case .monthly: return "MONTHLY"
        case .yearly: return "YEARLY"
        }
    }

    /// Descriptive schedule helper text.
    var cadenceDescription: String {
        switch self {
        case .daily: return "Clones every day into group history"
        case .weekly: return "Clones every 7 days into group history"
        case .biweekly: return "Clones every 14 days into group history"
        case .monthly: return "Clones every month into group history"
        case .yearly: return "Clones every year into group history"
        }
    }
}

/// A recurring expense template stored on the backend and cloned on schedule.
struct RecurringExpenseTemplate: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let groupId: UUID
    var title: String
    var amount: Double
    var currency: String
    var payerId: UUID
    var payerName: String
    var splitMemberIds: [UUID]
    var splits: [LedgerSplit]
    var frequency: String
    var note: String?
    var isActive: Bool
    var nextDueDate: Date
    var lastGeneratedAt: Date?
    var occurrencesGenerated: Int
    var createdAt: Date?

    var frequencyEnum: RecurringFrequency {
        RecurringFrequency(rawValue: frequency.lowercased()) ?? .monthly
    }

    var formattedAmount: String {
        String(format: "%.2f %@", amount, currency)
    }

    enum CodingKeys: String, CodingKey {
        case id, groupId, title, amount, currency, payerId, payerName
        case splitMemberIds, splits, frequency, note, isActive
        case nextDueDate, lastGeneratedAt, occurrencesGenerated, createdAt
    }
}

/// Payload sent to create a new recurring expense template on the backend.
struct CreateRecurringExpensePayload: Encodable {
    let title: String
    let amount: Double
    let currency: String
    let payerId: UUID
    let splitMemberIds: [UUID]?
    let splits: [AddGroupExpensePayload.LedgerSplitPayload]?
    let frequency: String
    let note: String?
    let startDate: Date?
}

/// Response returned when running the recurring cron processor on demand.
struct ProcessRecurringExpensesResponse: Codable {
    let processedCount: Int
    let generatedEventsCount: Int
    let generatedEvents: [LedgerEvent]
}
