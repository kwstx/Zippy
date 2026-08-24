import Vapor

public enum ReceiptCategory: String, Codable, CaseIterable, Content {
    case restaurants = "restaurants"
    case trips = "trips"
    case roommates = "roommates"
    case everyday = "everyday"

    public var displayName: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .trips: return "Trips"
        case .roommates: return "Roommates"
        case .everyday: return "Everyday purchases"
        }
    }
}

/// Request body for creating or updating a split session.
struct CreateSplitRequest: Content {
    let receiptId: UUID
    let participants: [ParticipantDTO]
    /// Item index (as string key) → array of participant UUIDs assigned to that item.
    let assignments: [String: [UUID]]
    let category: String?
}

/// Request body for patching an extracted receipt with manual corrections or edits.
struct PatchReceiptRequest: Content {
    let items: [ReceiptItem]?
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let total: Double?
    let category: String?
    let referenceId: String?
}

/// Request body for manually entering a brand new receipt.
struct CreateManualReceiptRequest: Content {
    let referenceId: String?
    let items: [ReceiptItem]
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let total: Double?
    let category: String?
}

/// Response returned after patching a receipt, including validation report and updated split session.
struct PatchReceiptResponse: Content {
    let success: Bool
    let receipt: ExtractedReceipt
    let validation: ReceiptValidationReport
    let splitSession: SplitSessionResponse?
    let shareableURL: String?
    let message: String
}

/// Request body for updating receipt or split category.
struct UpdateCategoryRequest: Content {
    let category: String?
}

/// Query parameters for history and search filtering.
struct HistoryFilterQuery: Content {
    let category: String?
    let search: String?
    let limit: Int?
    let offset: Int?
}

/// A historical entry returned by history & search filters.
struct HistoryItemDTO: Content {
    let id: UUID
    let receiptId: UUID?
    let title: String
    let category: String?
    let total: Double
    let createdAt: Date?
    let participantCount: Int
    let isSettled: Bool
    let shareableURL: String?
    let itemsSummary: [String]?
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
    let category: String?
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

/// An individual split share within an expense.
public struct ExpenseSplitDTO: Codable, Content {
    public let participantId: UUID
    public let amount: Double?

    public init(participantId: UUID, amount: Double? = nil) {
        self.participantId = participantId
        self.amount = amount
    }
}

/// Represents an expense incurred by a participant in a group.
public struct ExpenseDTO: Codable, Content {
    public let id: UUID?
    public let title: String?
    public let amount: Double
    public let paidBy: UUID
    /// Participant IDs sharing this expense equally.
    public let splitWith: [UUID]?
    /// Custom weighted or fixed splits for this expense.
    public let splits: [ExpenseSplitDTO]?

    public init(
        id: UUID? = nil,
        title: String? = nil,
        amount: Double,
        paidBy: UUID,
        splitWith: [UUID]? = nil,
        splits: [ExpenseSplitDTO]? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.paidBy = paidBy
        self.splitWith = splitWith
        self.splits = splits
    }
}

/// A direct transfer computed by the minimum-cash-flow algorithm.
public struct SimplifiedPaymentDTO: Codable, Content {
    public let fromId: UUID
    public let fromName: String
    public let toId: UUID
    public let toName: String
    public let amount: Double
    public let formattedText: String

    public init(
        fromId: UUID,
        fromName: String,
        toId: UUID,
        toName: String,
        amount: Double,
        formattedText: String
    ) {
        self.fromId = fromId
        self.fromName = fromName
        self.toId = toId
        self.toName = toName
        self.amount = amount
        self.formattedText = formattedText
    }
}

/// Request body for optimizing multiple expenses into fewest transfers.
public struct SimplifyExpensesRequest: Content {
    public let participants: [ParticipantDTO]
    public let expenses: [ExpenseDTO]

    public init(participants: [ParticipantDTO], expenses: [ExpenseDTO]) {
        self.participants = participants
        self.expenses = expenses
    }
}

/// Response returned by the minimum-cash-flow algorithm with reduced transfers and plain text lines.
public struct SimplifyExpensesResponse: Content {
    public let transfers: [SimplifiedPaymentDTO]
    public let lines: [String]
    public let totalTransferred: Double
    public let originalExpenseCount: Int
    public let transferCount: Int

    public init(
        transfers: [SimplifiedPaymentDTO],
        lines: [String],
        totalTransferred: Double,
        originalExpenseCount: Int,
        transferCount: Int
    ) {
        self.transfers = transfers
        self.lines = lines
        self.totalTransferred = totalTransferred
        self.originalExpenseCount = originalExpenseCount
        self.transferCount = transferCount
    }
}

