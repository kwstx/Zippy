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
}

/// The complete result of splitting a receipt among participants.
struct SplitResult: Codable, Equatable {
    let balances: [PersonBalance]
    /// Sum of only the items that have been assigned to at least one person.
    let assignedSubtotal: Double
}
