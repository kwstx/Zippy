import Fluent

/// Migration creating the `group_recurring_templates` table.
struct CreateRecurringExpenseTemplateMigration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(RecurringExpenseTemplate.schema)
            .id()
            .field("group_id", .uuid, .required, .references(PersistentGroup.schema, "id", onDelete: .cascade))
            .field("title", .string, .required)
            .field("amount", .double, .required)
            .field("currency", .string, .required)
            .field("payer_id", .uuid, .required)
            .field("payer_name", .string, .required)
            .field("split_member_ids", .array(of: .uuid), .required)
            .field("splits", .array(of: .custom(LedgerSplitDTO.self)), .required)
            .field("frequency", .string, .required)
            .field("note", .string)
            .field("is_active", .bool, .required)
            .field("next_due_date", .datetime, .required)
            .field("last_generated_at", .datetime)
            .field("occurrences_generated", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(RecurringExpenseTemplate.schema).delete()
    }
}
