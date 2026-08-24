// MARK: - SplitResult.swift

import Foundation

/// How much a single participant owes, broken down by component.
struct PersonBalance: Identifiable, Codable, Equatable {
    var id: UUID { participantId }
    let participantId: UUID
    let name: String
    let itemsSubtotal: Double
    let taxShare: Double
    let tipShare: Double
    let total: Double
    var isPaid: Bool
    var paidAt: Date?
    var paymentMethod: String?

    init(
        participantId: UUID,
        name: String,
        itemsSubtotal: Double,
        taxShare: Double,
        tipShare: Double,
        total: Double,
        isPaid: Bool = false,
        paidAt: Date? = nil,
        paymentMethod: String? = nil
    ) {
        self.participantId = participantId
        self.name = name
        self.itemsSubtotal = itemsSubtotal
        self.taxShare = taxShare
        self.tipShare = tipShare
        self.total = total
        self.isPaid = isPaid
        self.paidAt = paidAt
        self.paymentMethod = paymentMethod
    }
}

/// The complete result of splitting a receipt among participants.
struct SplitResult: Codable, Equatable {
    let balances: [PersonBalance]
    /// Sum of only the items that have been assigned to at least one person.
    let assignedSubtotal: Double
}
