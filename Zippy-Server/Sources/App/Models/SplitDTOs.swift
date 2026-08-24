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

/// Server-computed per-person balance breakdown with payment tracking.
struct PersonBalanceDTO: Codable {
    let participantId: UUID
    let name: String
    let itemsSubtotal: Double
    let taxShare: Double
    let tipShare: Double
    let total: Double
    var isPaid: Bool
    var paidAt: Date?
    var paymentMethod: String?

    enum CodingKeys: String, CodingKey {
        case participantId, name, itemsSubtotal, taxShare, tipShare, total, isPaid, paidAt, paymentMethod
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantId = try container.decode(UUID.self, forKey: .participantId)
        name = try container.decode(String.self, forKey: .name)
        itemsSubtotal = try container.decode(Double.self, forKey: .itemsSubtotal)
        taxShare = try container.decode(Double.self, forKey: .taxShare)
        tipShare = try container.decode(Double.self, forKey: .tipShare)
        total = try container.decode(Double.self, forKey: .total)
        isPaid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
    }
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

/// Request body for unauthenticated guest payments.
struct GuestPaymentRequest: Content {
    let participantId: UUID
    let paymentMethod: String // "apple_pay", "card", "cash", "venmo"
    let transactionReference: String?
}

/// Response returned after a guest payment submission.
struct GuestPaymentResponse: Content {
    let success: Bool
    let participantId: UUID
    let isPaid: Bool
    let paidAt: Date
    let totalPaid: Double
    let message: String
}

/// Real-time polling status response for guests.
struct SplitStatusResponse: Content {
    let sessionId: UUID
    let total: Double
    let totalCollected: Double
    let isFullySettled: Bool
    let participants: [ParticipantStatusDTO]

    struct ParticipantStatusDTO: Content {
        let id: UUID
        let name: String
        let total: Double
        let isPaid: Bool
        let paidAt: Date?
        let paymentMethod: String?
    }
}
