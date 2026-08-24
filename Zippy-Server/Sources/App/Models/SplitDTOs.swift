import Vapor

/// Request body for creating or updating a split session.
struct CreateSplitRequest: Content {
    let receiptId: UUID
    let participants: [ParticipantDTO]
    /// Item index (as string key) → array of participant UUIDs assigned to that item.
    let assignments: [String: [UUID]]
}

/// A participant in a bill split.
struct ParticipantDTO: Codable {
    let id: UUID
    let name: String
}

/// Server-computed per-person balance breakdown.
struct PersonBalanceDTO: Codable {
    let participantId: UUID
    let name: String
    let itemsSubtotal: Double
    let taxShare: Double
    let tipShare: Double
    let total: Double
}

/// Response returned after creating/fetching a split session.
struct SplitSessionResponse: Content {
    let id: UUID
    let receiptId: UUID
    let participants: [ParticipantDTO]
    let balances: [PersonBalanceDTO]
    let receiptTotal: Double
    let shareableURL: String?
    let createdAt: Date?
}
