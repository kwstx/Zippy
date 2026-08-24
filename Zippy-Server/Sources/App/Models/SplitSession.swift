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

    /// Active split method: "equal", "itemized", "percentage", "shares", "exact".
    @OptionalField(key: "split_method")
    var splitMethod: String?

    /// Item index (string key) → array of assigned participant UUIDs.
    @Field(key: "assignments")
    var assignments: [String: [UUID]]

    /// Percentage allocation per participant ID (string key) → percentage value.
    @OptionalField(key: "percentage_allocations")
    var percentageAllocations: [String: Double]?

    /// Share count allocation per participant ID (string key) → share weight.
    @OptionalField(key: "share_allocations")
    var shareAllocations: [String: Double]?

    /// Exact dollar allocation per participant ID (string key) → dollar amount.
    @OptionalField(key: "exact_allocations")
    var exactAllocations: [String: Double]?

    /// Server-computed authoritative balances (storing both original and converted amounts).
    @Field(key: "balances")
    var balances: [PersonBalanceDTO]

    /// Original currency code (e.g. "USD", "EUR", "GBP").
    @OptionalField(key: "currency")
    var currency: String?

    /// Target / converted base currency code (default: "USD").
    @OptionalField(key: "target_currency")
    var targetCurrency: String?

    /// Live exchange rate at calculation time.
    @OptionalField(key: "exchange_rate")
    var exchangeRate: Double?

    /// Cryptographically random token for the shareable short link.
    @OptionalField(key: "share_token")
    var shareToken: String?

    /// Optional category tag: "restaurants", "trips", "roommates", "everyday".
    @OptionalField(key: "category")
    var category: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        receiptId: UUID,
        participants: [ParticipantDTO],
        splitMethod: String? = "itemized",
        assignments: [String: [UUID]] = [:],
        percentageAllocations: [String: Double]? = nil,
        shareAllocations: [String: Double]? = nil,
        exactAllocations: [String: Double]? = nil,
        balances: [PersonBalanceDTO],
        currency: String? = "USD",
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0,
        shareToken: String? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.receiptId = receiptId
        self.participants = participants
        self.splitMethod = splitMethod
        self.assignments = assignments
        self.percentageAllocations = percentageAllocations
        self.shareAllocations = shareAllocations
        self.exactAllocations = exactAllocations
        self.balances = balances
        self.currency = currency ?? "USD"
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = exchangeRate ?? 1.0
        self.shareToken = shareToken
        self.category = category
    }
}
