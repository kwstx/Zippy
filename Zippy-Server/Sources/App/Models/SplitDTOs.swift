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

/// Status of a participant's balance settlement.
enum SettlementStatus: String, Codable, Content {
    case unpaid = "unpaid"
    case pendingConfirmation = "pending_confirmation"
    case settled = "settled"
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
    var settlementStatus: SettlementStatus

    enum CodingKeys: String, CodingKey {
        case participantId, name, itemsSubtotal, taxShare, tipShare, total, isPaid, paidAt, paymentMethod, settlementStatus
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
        paymentMethod: String? = nil,
        settlementStatus: SettlementStatus = .unpaid
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
        self.settlementStatus = isPaid ? .settled : settlementStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantId = try container.decode(UUID.self, forKey: .participantId)
        name = try container.decode(String.self, forKey: .name)
        itemsSubtotal = try container.decode(Double.self, forKey: .itemsSubtotal)
        taxShare = try container.decode(Double.self, forKey: .taxShare)
        tipShare = try container.decode(Double.self, forKey: .tipShare)
        total = try container.decode(Double.self, forKey: .total)
        let paid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
        isPaid = paid
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        let method = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        paymentMethod = method

        if let decodedStatus = try container.decodeIfPresent(SettlementStatus.self, forKey: .settlementStatus) {
            settlementStatus = decodedStatus
        } else if paid {
            settlementStatus = .settled
        } else if method != nil {
            settlementStatus = .pendingConfirmation
        } else {
            settlementStatus = .unpaid
        }
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

/// Request body for selecting an external payment method.
struct SelectPaymentMethodRequest: Content {
    let participantId: UUID
    /// "Venmo", "PayPal", "Cash App", "Bank transfer"
    let paymentMethod: String
    let handleOrAccount: String?
}

/// Response returned after choosing an external payment method.
struct SelectPaymentMethodResponse: Content {
    let success: Bool
    let participantId: UUID
    let paymentMethod: String
    let settlementStatus: SettlementStatus
    let deepLink: String?
    let instructions: String?
    let message: String
}

/// Request body for unauthenticated guest payments.
struct GuestPaymentRequest: Content {
    let participantId: UUID
    let paymentMethod: String // "Venmo", "PayPal", "Cash App", "Bank transfer", "apple_pay", "card"
    let transactionReference: String?
}

/// Request body to manually confirm settlement for a participant.
struct ConfirmSettlementRequest: Content {
    let participantId: UUID
    let confirmedBy: String?
}

/// Response returned after a guest payment or confirmation submission.
struct GuestPaymentResponse: Content {
    let success: Bool
    let participantId: UUID
    let isPaid: Bool
    let settlementStatus: SettlementStatus
    let paidAt: Date
    let totalPaid: Double
    let message: String
}

/// Webhook payload received from external payment providers.
struct PaymentWebhookPayload: Content {
    let event: String?
    let sessionId: UUID?
    let shareToken: String?
    let participantId: UUID?
    let amount: Double?
    let paymentMethod: String?
    let status: String?
    let transactionReference: String?
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
        let settlementStatus: SettlementStatus
        let paidAt: Date?
        let paymentMethod: String?
    }
}
