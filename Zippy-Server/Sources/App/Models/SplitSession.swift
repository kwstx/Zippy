import Vapor
import Fluent

/// Persisted split session linking participants and assignments to a receipt.
final class SplitSession: Model, Content, @unchecked Sendable {
    static let schema = "split_sessions"

    @ID(key: .id)
    var id: UUID?

    /// References the extracted receipt's database UUID.
    @Field(key: "receipt_id")
    var receiptId: UUID

    /// The people participating in this split.
    @Field(key: "participants")
    var participants: [ParticipantDTO]

    /// Item index (string key) → array of assigned participant UUIDs.
    @Field(key: "assignments")
    var assignments: [String: [UUID]]

    /// Server-computed authoritative balances.
    @Field(key: "balances")
    var balances: [PersonBalanceDTO]

    /// Cryptographically random token for the shareable short link.
    @OptionalField(key: "share_token")
    var shareToken: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        receiptId: UUID,
        participants: [ParticipantDTO],
        assignments: [String: [UUID]],
        balances: [PersonBalanceDTO],
        shareToken: String? = nil
    ) {
        self.id = id
        self.receiptId = receiptId
        self.participants = participants
        self.assignments = assignments
        self.balances = balances
        self.shareToken = shareToken
    }
}
