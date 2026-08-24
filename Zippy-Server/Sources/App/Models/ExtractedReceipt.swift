import Vapor
import Fluent

/// A single line item extracted from a receipt.
struct ReceiptItem: Codable, Content {
    var name: String
    var price: Double
    var quantity: Int
    var isShared: Bool
}

/// Persisted result of AI extraction for one receipt image.
final class ExtractedReceipt: Model, Content, @unchecked Sendable {
    static let schema = "extracted_receipts"

    @ID(key: .id)
    var id: UUID?

    /// The referenceId linking back to the uploaded image file.
    @Field(key: "reference_id")
    var referenceId: String

    /// Line items extracted from the receipt, stored as JSONB.
    @Field(key: "items")
    var items: [ReceiptItem]

    @Field(key: "subtotal")
    var subtotal: Double

    @Field(key: "tax")
    var tax: Double

    @Field(key: "tip")
    var tip: Double

    @Field(key: "total")
    var total: Double

    /// Optional category tag: "restaurants", "trips", "roommates", "everyday".
    @OptionalField(key: "category")
    var category: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        referenceId: String,
        items: [ReceiptItem],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        category: String? = nil
    ) {
        self.id = id
        self.referenceId = referenceId
        self.items = items
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.total = total
        self.category = category
    }
}
