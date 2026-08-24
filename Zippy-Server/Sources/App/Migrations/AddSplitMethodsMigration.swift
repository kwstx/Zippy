import Fluent

/// Non-destructive migration to add split method and allocation columns to split_sessions.
struct AddSplitMethodsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("split_sessions")
            .field("split_method", .string)
            .field("percentage_allocations", .json)
            .field("share_allocations", .json)
            .field("exact_allocations", .json)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("split_sessions")
            .deleteField("split_method")
            .deleteField("percentage_allocations")
            .deleteField("share_allocations")
            .deleteField("exact_allocations")
            .update()
    }
}
