// MARK: - ExtractedReceipt.swift

import Foundation

/// A single line item extracted or manually entered for a receipt.
struct ReceiptItem: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var price: Double
    var quantity: Int
    var isShared: Bool
    var originalCurrency: String?
    var convertedPrice: Double?
    var targetCurrency: String?
    var exchangeRate: Double?

    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        quantity: Int = 1,
        isShared: Bool = false,
        originalCurrency: String? = "USD",
        convertedPrice: Double? = nil,
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.isShared = isShared
        self.originalCurrency = originalCurrency ?? "USD"
        self.convertedPrice = convertedPrice ?? price
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = exchangeRate ?? 1.0
    }

    enum CodingKeys: String, CodingKey {
        case name, price, quantity, isShared
        case originalCurrency, convertedPrice, targetCurrency, exchangeRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.price = try container.decode(Double.self, forKey: .price)
        self.quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        self.isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        self.originalCurrency = try container.decodeIfPresent(String.self, forKey: .originalCurrency) ?? "USD"
        self.convertedPrice = try container.decodeIfPresent(Double.self, forKey: .convertedPrice) ?? self.price
        self.targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency) ?? "USD"
        self.exchangeRate = try container.decodeIfPresent(Double.self, forKey: .exchangeRate) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(price, forKey: .price)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(isShared, forKey: .isShared)
        try container.encodeIfPresent(originalCurrency, forKey: .originalCurrency)
        try container.encodeIfPresent(convertedPrice, forKey: .convertedPrice)
        try container.encodeIfPresent(targetCurrency, forKey: .targetCurrency)
        try container.encodeIfPresent(exchangeRate, forKey: .exchangeRate)
    }
}

/// Full extraction / manual receipt result returned by the server.
struct ExtractedReceiptResponse: Codable, Identifiable, Equatable {
    let id: UUID?
    var referenceId: String
    var items: [ReceiptItem]
    var subtotal: Double
    var tax: Double
    var tip: Double
    var total: Double
    var category: String?
    var currency: String?
    var targetCurrency: String?
    var exchangeRate: Double?
    var convertedTotal: Double?
    let createdAt: String?

    var parsedCategory: ReceiptCategory? {
        get { ReceiptCategory(flexibleString: category) }
        set { category = newValue?.rawValue }
    }

    var effectiveCurrency: String {
        currency ?? "USD"
    }

    init(
        id: UUID? = nil,
        referenceId: String = "manual-\(UUID().uuidString.prefix(8))",
        items: [ReceiptItem] = [],
        subtotal: Double = 0,
        tax: Double = 0,
        tip: Double = 0,
        total: Double = 0,
        category: String? = nil,
        currency: String? = "USD",
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0,
        convertedTotal: Double? = nil,
        createdAt: String? = nil
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
        self.convertedTotal = convertedTotal ?? ((total * rate * 100).rounded() / 100)
        self.createdAt = createdAt
    }
}

/// Server validation report returned during PATCH re-validation.
struct ReceiptValidationReport: Codable, Equatable {
    let isValid: Bool
    let isMathConsistent: Bool
    let computedSubtotal: Double
    let computedTotal: Double
    let subtotalDiscrepancy: Double
    let totalDiscrepancy: Double
    let warnings: [String]
    let errors: [String]
}

/// Payload sent to immediately PATCH receipt fields to the Vapor backend.
struct PatchReceiptPayload: Encodable {
    let items: [ReceiptItem]?
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let total: Double?
    let category: String?
    let referenceId: String?
    let currency: String?
    let targetCurrency: String?
}

/// Response returned from Vapor after immediately patching receipt edits.
struct PatchReceiptResponse: Decodable {
    let success: Bool
    let receipt: ExtractedReceiptResponse
    let validation: ReceiptValidationReport
    let splitSession: SplitSessionResponse?
    let shareableURL: String?
    let message: String
}
