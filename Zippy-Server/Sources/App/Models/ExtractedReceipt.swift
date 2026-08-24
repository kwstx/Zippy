import Vapor
import Fluent

/// A single line item extracted from a receipt.
struct ReceiptItem: Codable, Content {
    var name: String
    var price: Double
    var quantity: Int
    var isShared: Bool
    var originalCurrency: String?
    var convertedPrice: Double?
    var targetCurrency: String?
    var exchangeRate: Double?

    init(
        name: String,
        price: Double,
        quantity: Int = 1,
        isShared: Bool = false,
        originalCurrency: String? = "USD",
        convertedPrice: Double? = nil,
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0
    ) {
        self.name = name
        self.price = price
        self.quantity = quantity
        self.isShared = isShared
        self.originalCurrency = originalCurrency ?? "USD"
        self.convertedPrice = convertedPrice ?? price
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = exchangeRate ?? 1.0
    }
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

    /// Original currency code (e.g., "USD", "EUR", "GBP", "JPY", "CAD", "AUD").
    @OptionalField(key: "currency")
    var currency: String?

    /// Target / converted base currency code (default: "USD").
    @OptionalField(key: "target_currency")
    var targetCurrency: String?

    /// Live exchange rate captured at calculation time (1 source currency = X target currency).
    @OptionalField(key: "exchange_rate")
    var exchangeRate: Double?

    /// Converted grand total in targetCurrency at calculation time.
    @OptionalField(key: "converted_total")
    var convertedTotal: Double?

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
        category: String? = nil,
        currency: String? = "USD",
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0,
        convertedTotal: Double? = nil
    ) {
        self.id = id
        self.referenceId = referenceId
        self.items = items
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.total = total
        self.category = category
        self.currency = currency ?? "USD"
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = exchangeRate ?? 1.0
        let rate = exchangeRate ?? 1.0
        self.convertedTotal = convertedTotal ?? (rate != 1.0 ? (total * rate * 100).rounded() / 100 : total)
    }
}
