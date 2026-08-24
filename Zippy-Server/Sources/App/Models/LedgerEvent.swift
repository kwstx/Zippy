import Vapor
import Fluent
import Foundation

/// Append-only ledger event stream record for group expenses and settlements.
final class LedgerEvent: Model, Content, @unchecked Sendable {
    static let schema = "group_ledger_events"

    @ID(key: .id)
    var id: UUID?

    /// Foreign key referencing the parent group.
    @Field(key: "group_id")
    var groupId: UUID

    /// Event discriminator: "expense" or "settlement".
    @Field(key: "event_type")
    var eventType: String

    /// Description / title of the transaction (e.g. "Trader Joe's groceries", "Settlement: Sam -> Alex").
    @Field(key: "title")
    var title: String

    /// Total amount of the transaction.
    @Field(key: "amount")
    var amount: Double

    /// The participant UUID who paid for this expense or made the settlement transfer.
    @Field(key: "payer_id")
    var payerId: UUID

    /// The display name of the payer at the time of the transaction.
    @Field(key: "payer_name")
    var payerName: String

    /// For settlements: the participant UUID who received the settlement transfer.
    @OptionalField(key: "payee_id")
    var payeeId: UUID?

    /// For settlements: the display name of the payee.
    @OptionalField(key: "payee_name")
    var payeeName: String?

    /// Breakdown of split shares per participant (for expenses).
    @Field(key: "splits")
    var splits: [LedgerSplitDTO]

    /// Optional link to an extracted receipt if this expense originated from a scanned bill.
    @OptionalField(key: "receipt_id")
    var receiptId: UUID?

    /// Optional memo or notes for the transaction.
    @OptionalField(key: "note")
    var note: String?

    /// Strictly ordered immutable timestamp representing the event sequence.
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        groupId: UUID,
        eventType: String,
        title: String,
        amount: Double,
        payerId: UUID,
        payerName: String,
        payeeId: UUID? = nil,
        payeeName: String? = nil,
        splits: [LedgerSplitDTO] = [],
        receiptId: UUID? = nil,
        note: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.eventType = eventType
        self.title = title
        self.amount = amount
        self.payerId = payerId
        self.payerName = payerName
        self.payeeId = payeeId
        self.payeeName = payeeName
        self.splits = splits
        self.receiptId = receiptId
        self.note = note
        self.createdAt = createdAt
    }
}
