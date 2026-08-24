// MARK: - ExtractedReceipt.swift

import Foundation

/// A single line item extracted from the receipt.
struct ReceiptItem: Codable, Identifiable, Equatable {
    var id: String { "\(name)-\(price)-\(quantity)" }
    let name: String
    let price: Double
    let quantity: Int
    let isShared: Bool
}

/// Full extraction result returned by the server.
struct ExtractedReceiptResponse: Codable, Identifiable, Equatable {
    let id: UUID?
    let referenceId: String
    let items: [ReceiptItem]
    let subtotal: Double
    let tax: Double
    let tip: Double
    let total: Double
    let createdAt: String?
}
