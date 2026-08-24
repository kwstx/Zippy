import Vapor
import Foundation

/// Request payload to create a new recurring expense template.
public struct CreateRecurringExpenseRequest: Content {
    public let title: String
    public let amount: Double
    public let currency: String?
    public let payerId: UUID
    public let splitMemberIds: [UUID]?
    public let splits: [LedgerSplitDTO]?
    public let frequency: String
    public let note: String?
    public let startDate: Date?

    public init(
        title: String,
        amount: Double,
        currency: String? = "USD",
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [LedgerSplitDTO]? = nil,
        frequency: String = "monthly",
        note: String? = nil,
        startDate: Date? = nil
    ) {
        self.title = title
        self.amount = amount
        self.currency = currency ?? "USD"
        self.payerId = payerId
        self.splitMemberIds = splitMemberIds
        self.splits = splits
        self.frequency = frequency
        self.note = note
        self.startDate = startDate
    }
}

/// Serialized representation of a recurring expense template.
public struct RecurringExpenseResponseDTO: Content {
    public let id: UUID
    public let groupId: UUID
    public let title: String
    public let amount: Double
    public let currency: String
    public let formattedAmount: String
    public let payerId: UUID
    public let payerName: String
    public let splitMemberIds: [UUID]
    public let splits: [LedgerSplitDTO]
    public let frequency: String
    public let frequencyDisplay: String
    public let note: String?
    public let isActive: Bool
    public let nextDueDate: Date
    public let lastGeneratedAt: Date?
    public let occurrencesGenerated: Int
    public let createdAt: Date?

    public init(
        id: UUID,
        groupId: UUID,
        title: String,
        amount: Double,
        currency: String,
        payerId: UUID,
        payerName: String,
        splitMemberIds: [UUID] = [],
        splits: [LedgerSplitDTO] = [],
        frequency: String,
        note: String? = nil,
        isActive: Bool = true,
        nextDueDate: Date,
        lastGeneratedAt: Date? = nil,
        occurrencesGenerated: Int = 0,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.amount = amount
        self.currency = currency
        self.formattedAmount = String(format: "%.2f %@", amount, currency)
        self.payerId = payerId
        self.payerName = payerName
        self.splitMemberIds = splitMemberIds
        self.splits = splits
        self.frequency = frequency
        self.frequencyDisplay = Self.formatFrequencyDisplay(frequency)
        self.note = note
        self.isActive = isActive
        self.nextDueDate = nextDueDate
        self.lastGeneratedAt = lastGeneratedAt
        self.occurrencesGenerated = occurrencesGenerated
        self.createdAt = createdAt
    }

    private static func formatFrequencyDisplay(_ freq: String) -> String {
        switch freq.lowercased() {
        case "daily": return "Daily"
        case "weekly": return "Weekly"
        case "biweekly", "bi-weekly": return "Bi-weekly"
        case "monthly": return "Monthly"
        case "yearly", "annually": return "Yearly"
        default: return freq.capitalized
        }
    }
}

/// Response returned when running the recurring cron-like processor.
public struct ProcessRecurringExpensesResultDTO: Content {
    public let processedCount: Int
    public let generatedEventsCount: Int
    public let generatedEvents: [LedgerEventResponseDTO]

    public init(
        processedCount: Int,
        generatedEventsCount: Int,
        generatedEvents: [LedgerEventResponseDTO]
    ) {
        self.processedCount = processedCount
        self.generatedEventsCount = generatedEventsCount
        self.generatedEvents = generatedEvents
    }
}
