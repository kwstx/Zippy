// MARK: - ExtractedReceipt.swift

import Foundation

/// A single line item extracted or manually entered for a receipt.
struct ReceiptItem: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var price: Double
    var quantity: Int
    var isShared: Bool

    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        quantity: Int = 1,
        isShared: Bool = false
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.isShared = isShared
    }

    enum CodingKeys: String, CodingKey {
        case name, price, quantity, isShared
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.price = try container.decode(Double.self, forKey: .price)
        self.quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        self.isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(price, forKey: .price)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(isShared, forKey: .isShared)
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
    let createdAt: String?

    var parsedCategory: ReceiptCategory? {
        get { ReceiptCategory(flexibleString: category) }
        set { category = newValue?.rawValue }
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
