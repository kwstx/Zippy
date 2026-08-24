import Fluent

struct CreateExtractedReceipt: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("extracted_receipts")
            .id()
            .field("reference_id", .string, .required)
            .field("items", .json, .required)
            .field("subtotal", .double, .required)
            .field("tax", .double, .required)
            .field("tip", .double, .required)
            .field("total", .double, .required)
            .field("created_at", .datetime)
            .unique(on: "reference_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("extracted_receipts").delete()
    }
}
