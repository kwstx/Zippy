import Fluent

struct CreatePersistentGroupMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("persistent_groups")
            .id()
            .field("name", .string, .required)
            .field("members", .json, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("persistent_groups").delete()
    }
}
