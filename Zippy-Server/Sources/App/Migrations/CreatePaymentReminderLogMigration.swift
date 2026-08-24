import Fluent

struct CreatePaymentReminderLogMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("payment_reminder_logs")
            .id()
            .field("split_session_id", .uuid)
            .field("group_id", .uuid)
            .field("participant_id", .uuid, .required)
            .field("participant_name", .string, .required)
            .field("amount", .double, .required)
            .field("currency", .string, .required)
            .field("channel", .string, .required)
            .field("recipient_contact", .string)
            .field("status", .string, .required)
            .field("notification_payload", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("payment_reminder_logs").delete()
    }
}
