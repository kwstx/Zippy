import Fluent

struct CreateLedgerEventMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("group_ledger_events")
            .id()
            .field("group_id", .uuid, .required, .references("persistent_groups", "id", onDelete: .cascade))
            .field("event_type", .string, .required)
            .field("title", .string, .required)
            .field("amount", .double, .required)
            .field("payer_id", .uuid, .required)
            .field("payer_name", .string, .required)
            .field("payee_id", .uuid)
            .field("payee_name", .string)
            .field("splits", .json, .required)
            .field("receipt_id", .uuid)
            .field("note", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("group_ledger_events").delete()
    }
}
