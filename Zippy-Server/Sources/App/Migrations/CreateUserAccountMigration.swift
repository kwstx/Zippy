import Fluent

/// Migration creating the `user_accounts` table for lightweight organizer accounts.
struct CreateUserAccountMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("user_accounts")
            .id()
            .field("email", .string)
            .field("apple_user_id", .string)
            .field("display_name", .string)
            .field("auth_provider", .string, .required)
            .field("magic_link_token", .string)
            .field("magic_link_expires_at", .datetime)
            .field("session_token", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "email")
            .unique(on: "apple_user_id")
            .unique(on: "session_token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("user_accounts").delete()
    }
}
