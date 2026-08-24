// MARK: - CreateSubscriptionRecordMigration.swift

import Fluent

struct CreateSubscriptionRecordMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("subscription_records")
            .id()
            .field("user_id", .string, .required)
            .field("tier", .string, .required)
            .field("product_id", .string)
            .field("original_transaction_id", .string)
            .field("expires_at", .datetime)
            .field("is_active", .bool, .required)
            .field("receipt_token", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("subscription_records").delete()
    }
}
