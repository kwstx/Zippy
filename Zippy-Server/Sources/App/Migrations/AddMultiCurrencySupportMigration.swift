import Fluent

/// Non-destructive migration to add multi-currency columns across receipts, split sessions, groups, and ledger events.
struct AddMultiCurrencySupportMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("extracted_receipts")
            .field("currency", .string)
            .field("target_currency", .string)
            .field("exchange_rate", .double)
            .field("converted_total", .double)
            .update()

        try await database.schema("split_sessions")
            .field("currency", .string)
            .field("target_currency", .string)
            .field("exchange_rate", .double)
            .update()

        try await database.schema("persistent_groups")
            .field("currency", .string)
            .update()

        try await database.schema("ledger_events")
            .field("currency", .string)
            .field("target_currency", .string)
            .field("exchange_rate", .double)
            .field("converted_amount", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("extracted_receipts")
            .deleteField("currency")
            .deleteField("target_currency")
            .deleteField("exchange_rate")
            .deleteField("converted_total")
            .update()

        try await database.schema("split_sessions")
            .deleteField("currency")
            .deleteField("target_currency")
            .deleteField("exchange_rate")
            .update()

        try await database.schema("persistent_groups")
            .deleteField("currency")
            .update()

        try await database.schema("ledger_events")
            .deleteField("currency")
            .deleteField("target_currency")
            .deleteField("exchange_rate")
            .deleteField("converted_amount")
            .update()
    }
}
