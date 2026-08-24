import Vapor
import Foundation

/// A single participant's split share in an expense event.
public struct LedgerSplitDTO: Codable, Content {
    public let memberId: UUID
    public let memberName: String
    public let amount: Double

    public init(memberId: UUID, memberName: String, amount: Double) {
        self.memberId = memberId
        self.memberName = memberName
        self.amount = amount
    }
}

/// Request to create a new persistent group.
public struct CreateGroupRequest: Content {
    public let name: String
    public let members: [ParticipantDTO]

    public init(name: String, members: [ParticipantDTO]) {
        self.name = name
        self.members = members
    }
}

/// Request to append an expense event to a group's append-only ledger.
public struct AddGroupExpenseRequest: Content {
    public let title: String
    public let amount: Double
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
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [LedgerSplitDTO]? = nil,
        receiptId: UUID? = nil,
        note: String? = nil
    ) {
        self.title = title
        self.amount = amount
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
    public let note: String?

    public init(
        payerId: UUID,
        payeeId: UUID,
        amount: Double,
        note: String? = nil
    ) {
        self.payerId = payerId
        self.payeeId = payeeId
        self.amount = amount
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
    public let memberCount: Int
    public let eventCount: Int
    public let lastActivity: Date?
    public let createdAt: Date?

    public init(
        id: UUID,
        name: String,
        members: [ParticipantDTO],
        runningBalance: Double,
        formattedBalance: String,
        memberCount: Int,
        eventCount: Int,
        lastActivity: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.runningBalance = runningBalance
        self.formattedBalance = formattedBalance
        self.memberCount = memberCount
        self.eventCount = eventCount
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

    public init(
        participantId: UUID,
        name: String,
        netBalance: Double,
        formattedBalance: String
    ) {
        self.participantId = participantId
        self.name = name
        self.netBalance = netBalance
        self.formattedBalance = formattedBalance
    }
}

/// A serialized ledger event returned to clients.
public struct LedgerEventResponseDTO: Content {
    public let id: UUID
    public let groupId: UUID
    public let eventType: String
    public let title: String
    public let amount: Double
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

/// Complete ledger event stream history and computed balances for a group.
public struct GroupLedgerHistoryResponseDTO: Content {
    public let group: GroupResponseDTO
    public let events: [LedgerEventResponseDTO]
    public let memberBalances: [GroupMemberBalanceDTO]
    public let currentBalances: [String: Double]

    public init(
        group: GroupResponseDTO,
        events: [LedgerEventResponseDTO],
        memberBalances: [GroupMemberBalanceDTO],
        currentBalances: [String: Double]
    ) {
        self.group = group
        self.events = events
        self.memberBalances = memberBalances
        self.currentBalances = currentBalances
    }
}
