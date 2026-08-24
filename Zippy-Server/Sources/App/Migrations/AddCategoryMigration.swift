import Fluent

/// Non-destructive migration to add optional category column to existing tables.
struct AddCategoryMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("extracted_receipts")
            .field("category", .string)
            .update()

        try await database.schema("split_sessions")
            .field("category", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("extracted_receipts")
            .deleteField("category")
            .update()

        try await database.schema("split_sessions")
            .deleteField("category")
            .update()
    }
}
