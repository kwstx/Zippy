// MARK: - SubscriptionRecord.swift

import Vapor
import Fluent
import Foundation

/// Persisted subscription record representing an app user's or device's active subscription tier.
final class SubscriptionRecord: Model, Content, @unchecked Sendable {
    static let schema = "subscription_records"

    @ID(key: .id)
    var id: UUID?

    /// Unique user or device identifier.
    @Field(key: "user_id")
    var userId: String

    /// The current subscription tier: "free" or "pro".
    @Field(key: "tier")
    var tier: String

    /// The Apple StoreKit Product ID (e.g., "com.zippy.app.pro.monthly", "com.zippy.app.pro.annual").
    @OptionalField(key: "product_id")
    var productId: String?

    /// The StoreKit original transaction ID.
    @OptionalField(key: "original_transaction_id")
    var originalTransactionId: String?

    /// Expiration date of the Pro subscription (nil for non-expiring or lifetime).
    @OptionalField(key: "expires_at")
    var expiresAt: Date?

    /// Active state flag.
    @Field(key: "is_active")
    var isActive: Bool

    /// StoreKit JWS token or transaction payload for server-side verification.
    @OptionalField(key: "receipt_token")
    var receiptToken: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userId: String,
        tier: String = "free",
        productId: String? = nil,
        originalTransactionId: String? = nil,
        expiresAt: Date? = nil,
        isActive: Bool = true,
        receiptToken: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.tier = tier
        self.productId = productId
        self.originalTransactionId = originalTransactionId
        self.expiresAt = expiresAt
        self.isActive = isActive
        self.receiptToken = receiptToken
    }
}
