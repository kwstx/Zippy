import Fluent

/// Migration adding `owner_id` to the `persistent_groups` table to associate groups with organizer accounts.
struct AddOrganizerToGroupsMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("persistent_groups")
            .field("owner_id", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("persistent_groups")
            .deleteField("owner_id")
            .update()
    }
}
