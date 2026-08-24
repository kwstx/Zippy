import Fluent

struct CreateSplitSession: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("split_sessions")
            .id()
            .field("receipt_id", .uuid, .required)
            .field("participants", .json, .required)
            .field("assignments", .json, .required)
            .field("balances", .json, .required)
            .field("share_token", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("split_sessions").delete()
    }
}
