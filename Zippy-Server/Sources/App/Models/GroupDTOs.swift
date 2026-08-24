import Vapor
import Foundation

/// A single participant's split share in an expense event.
public struct LedgerSplitDTO: Codable, Content {
    public let memberId: UUID
    public let memberName: String
    public let amount: Double
    public let currency: String
    public let convertedAmount: Double?

    public init(
        memberId: UUID,
        memberName: String,
        amount: Double,
        currency: String = "USD",
        convertedAmount: Double? = nil
    ) {
        self.memberId = memberId
        self.memberName = memberName
        self.amount = amount
        self.currency = currency
        self.convertedAmount = convertedAmount ?? amount
    }
}

/// Request to create a new persistent group.
public struct CreateGroupRequest: Content {
    public let name: String
    public let members: [ParticipantDTO]
    public let currency: String?
    public let ownerId: String?

    public init(
        name: String,
        members: [ParticipantDTO],
        currency: String? = "USD",
        ownerId: String? = nil
    ) {
        self.name = name
        self.members = members
        self.currency = currency ?? "USD"
        self.ownerId = ownerId
    }
}

/// Request to append an expense event to a group's append-only ledger.
public struct AddGroupExpenseRequest: Content {
    public let title: String
    public let amount: Double
    public let currency: String?
    public let targetCurrency: String?
    public let payerId: UUID
    /// Optional subset of member IDs splitting this expense equally.
    public let splitMemberIds: [UUID]?
    /// Or explicit custom split allocations.
    public let splits: [LedgerSplitDTO]?
    public let receiptId: UUID?
    public let note: String?

    public init(
        title: String,
        amount: Double,
        currency: String? = "USD",
        targetCurrency: String? = "USD",
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [LedgerSplitDTO]? = nil,
        receiptId: UUID? = nil,
        note: String? = nil
    ) {
        self.title = title
        self.amount = amount
        self.currency = currency ?? "USD"
        self.targetCurrency = targetCurrency ?? "USD"
        self.payerId = payerId
        self.splitMemberIds = splitMemberIds
        self.splits = splits
        self.receiptId = receiptId
        self.note = note
    }
}

/// Request to append a settlement payment event to a group's append-only ledger.
public struct AddGroupSettlementRequest: Content {
    public let payerId: UUID
    public let payeeId: UUID
    public let amount: Double
    public let currency: String?
    public let targetCurrency: String?
    public let note: String?

    public init(
        payerId: UUID,
        payeeId: UUID,
        amount: Double,
        currency: String? = "USD",
        targetCurrency: String? = "USD",
        note: String? = nil
    ) {
        self.payerId = payerId
        self.payeeId = payeeId
        self.amount = amount
        self.currency = currency ?? "USD"
        self.targetCurrency = targetCurrency ?? "USD"
        self.note = note
    }
}

/// Summary representation of a persistent group with running balance information.
public struct GroupResponseDTO: Content {
    public let id: UUID
    public let name: String
    public let members: [ParticipantDTO]
    public let runningBalance: Double
    public let formattedBalance: String
    public let currency: String
    public let memberCount: Int
    public let eventCount: Int
    public let ownerId: String?
    public let lastActivity: Date?
    public let createdAt: Date?

    public init(
        id: UUID,
        name: String,
        members: [ParticipantDTO],
        runningBalance: Double,
        formattedBalance: String,
        currency: String = "USD",
        memberCount: Int,
        eventCount: Int,
        ownerId: String? = nil,
        lastActivity: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.runningBalance = runningBalance
        self.formattedBalance = formattedBalance
        self.currency = currency
        self.memberCount = memberCount
        self.eventCount = eventCount
        self.ownerId = ownerId
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }
}

/// Calculated net balance for a specific group member.
public struct GroupMemberBalanceDTO: Content {
    public let participantId: UUID
    public let name: String
    public let netBalance: Double
    public let formattedBalance: String
    public let currency: String

    public init(
        participantId: UUID,
        name: String,
        netBalance: Double,
        formattedBalance: String,
        currency: String = "USD"
    ) {
        self.participantId = participantId
        self.name = name
        self.netBalance = netBalance
        self.formattedBalance = formattedBalance
        self.currency = currency
    }
}

/// A serialized ledger event returned to clients.
public struct LedgerEventResponseDTO: Content {
    public let id: UUID
    public let groupId: UUID
    public let eventType: String
    public let title: String
    public let amount: Double
    public let currency: String
    public let convertedAmount: Double?
    public let targetCurrency: String?
    public let exchangeRate: Double?
    public let payerId: UUID
    public let payerName: String
    public let payeeId: UUID?
    public let payeeName: String?
    public let splits: [LedgerSplitDTO]
    public let runningBalanceAfter: Double?
    public let receiptId: UUID?
    public let note: String?
    public let createdAt: Date?

    public init(
        id: UUID,
        groupId: UUID,
        eventType: String,
        title: String,
        amount: Double,
        currency: String = "USD",
        convertedAmount: Double? = nil,
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0,
        payerId: UUID,
        payerName: String,
        payeeId: UUID? = nil,
        payeeName: String? = nil,
        splits: [LedgerSplitDTO] = [],
        runningBalanceAfter: Double? = nil,
        receiptId: UUID? = nil,
        note: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.eventType = eventType
        self.title = title
        self.amount = amount
        self.currency = currency
        self.convertedAmount = convertedAmount ?? amount
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = exchangeRate ?? 1.0
        self.payerId = payerId
        self.payerName = payerName
        self.payeeId = payeeId
        self.payeeName = payeeName
        self.splits = splits
        self.runningBalanceAfter = runningBalanceAfter
        self.receiptId = receiptId
        self.note = note
        self.createdAt = createdAt
    }
}

/// Complete ledger event stream history and computed balances for a group,
/// including continuous debt simplification transfers.
public struct GroupLedgerHistoryResponseDTO: Content {
    public let group: GroupResponseDTO
    public let events: [LedgerEventResponseDTO]
    public let memberBalances: [GroupMemberBalanceDTO]
    public let currentBalances: [String: Double]
    public let currency: String
    public let simplifiedTransfers: [SimplifiedPaymentDTO]
    public let simplifiedLines: [String]
    public let totalTransferred: Double

    public init(
        group: GroupResponseDTO,
        events: [LedgerEventResponseDTO],
        memberBalances: [GroupMemberBalanceDTO],
        currentBalances: [String: Double],
        currency: String = "USD",
        simplifiedTransfers: [SimplifiedPaymentDTO] = [],
        simplifiedLines: [String] = [],
        totalTransferred: Double = 0.0
    ) {
        self.group = group
        self.events = events
        self.memberBalances = memberBalances
        self.currentBalances = currentBalances
        self.currency = currency
        self.simplifiedTransfers = simplifiedTransfers
        self.simplifiedLines = simplifiedLines
        self.totalTransferred = totalTransferred
    }
}
