import Vapor
import Fluent
import Foundation

/// Defines a persistent template for recurring group expenses (e.g. rent, internet, subscriptions).
/// Cloned into concrete `LedgerEvent` expense records by the background recurring cron worker.
final class RecurringExpenseTemplate: Model, Content, @unchecked Sendable {
    static let schema = "group_recurring_templates"

    @ID(key: .id)
    var id: UUID?

    /// Foreign key referencing the parent group.
    @Field(key: "group_id")
    var groupId: UUID

    /// Description / title of the recurring expense (e.g. "Apartment Rent", "WiFi Subscription").
    @Field(key: "title")
    var title: String

    /// Amount in original currency.
    @Field(key: "amount")
    var amount: Double

    /// Currency code (e.g., "USD", "EUR", "GBP").
    @Field(key: "currency")
    var currency: String

    /// The participant UUID who pays for this recurring expense.
    @Field(key: "payer_id")
    var payerId: UUID

    /// Display name of the designated payer.
    @Field(key: "payer_name")
    var payerName: String

    /// Optional subset of member IDs splitting this expense equally.
    @Field(key: "split_member_ids")
    var splitMemberIds: [UUID]

    /// Optional custom split breakdown.
    @Field(key: "splits")
    var splits: [LedgerSplitDTO]

    /// Plain text frequency: "daily", "weekly", "biweekly", "monthly", "yearly".
    @Field(key: "frequency")
    var frequency: String

    /// Optional memo/notes.
    @OptionalField(key: "note")
    var note: String?

    /// Whether this recurring template is currently active.
    @Field(key: "is_active")
    var isActive: Bool

    /// When the next clone run is scheduled to occur.
    @Field(key: "next_due_date")
    var nextDueDate: Date

    /// When the template was last cloned into a ledger expense event.
    @OptionalField(key: "last_generated_at")
    var lastGeneratedAt: Date?

    /// Count of ledger event clones created from this template.
    @Field(key: "occurrences_generated")
    var occurrencesGenerated: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        groupId: UUID,
        title: String,
        amount: Double,
        currency: String = "USD",
        payerId: UUID,
        payerName: String,
        splitMemberIds: [UUID] = [],
        splits: [LedgerSplitDTO] = [],
        frequency: String = "monthly",
        note: String? = nil,
        isActive: Bool = true,
        nextDueDate: Date = Date(),
        lastGeneratedAt: Date? = nil,
        occurrencesGenerated: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.amount = amount
        self.currency = currency
        self.payerId = payerId
        self.payerName = payerName
        self.splitMemberIds = splitMemberIds
        self.splits = splits
        self.frequency = frequency.lowercased()
        self.note = note
        self.isActive = isActive
        self.nextDueDate = nextDueDate
        self.lastGeneratedAt = lastGeneratedAt
        self.occurrencesGenerated = occurrencesGenerated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Computes the subsequent due date based on the chosen frequency option.
    static func computeNextDueDate(from date: Date, frequency: String) -> Date {
        let calendar = Calendar.current
        let normalized = frequency.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "daily":
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
        case "weekly":
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 86400)
        case "biweekly", "bi-weekly", "every 2 weeks":
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date.addingTimeInterval(14 * 86400)
        case "monthly":
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86400)
        case "yearly", "annually":
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date.addingTimeInterval(365 * 86400)
        default:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date.addingTimeInterval(30 * 86400)
        }
    }
}
