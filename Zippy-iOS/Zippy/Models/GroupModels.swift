// MARK: - GroupModels.swift

import Foundation

/// Persistent group representing a shared expense pool with a member roster and running balance.
struct PersistentGroup: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var members: [Participant]
    var runningBalance: Double
    var formattedBalance: String
    var memberCount: Int
    var eventCount: Int
    var lastActivity: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, members, runningBalance, formattedBalance, memberCount, eventCount, lastActivity, createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        members: [Participant] = [],
        runningBalance: Double = 0.0,
        formattedBalance: String = "$0.00",
        memberCount: Int = 0,
        eventCount: Int = 0,
        lastActivity: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.runningBalance = runningBalance
        self.formattedBalance = formattedBalance
        self.memberCount = memberCount.max(members.count)
        self.eventCount = eventCount
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }
}

private extension Int {
    func max(_ other: Int) -> Int {
        Swift.max(self, other)
    }
}

/// Ledger event type discriminator.
enum LedgerEventType: String, Codable, Equatable {
    case expense = "expense"
    case settlement = "settlement"
}

/// A participant's share in a group expense.
struct LedgerSplit: Identifiable, Codable, Equatable {
    var id: UUID { memberId }
    let memberId: UUID
    let memberName: String
    let amount: Double
}

/// An immutable event in the group's append-only ledger event stream.
struct LedgerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let eventType: String
    let title: String
    let amount: Double
    let payerId: UUID
    let payerName: String
    let payeeId: UUID?
    let payeeName: String?
    let splits: [LedgerSplit]
    let runningBalanceAfter: Double?
    let receiptId: UUID?
    let note: String?
    let createdAt: Date?

    var isSettlement: Bool {
        eventType.lowercased() == "settlement"
    }

    var isExpense: Bool {
        eventType.lowercased() == "expense"
    }
}

/// Calculated net balance for a member in a group.
struct GroupMemberBalance: Identifiable, Codable, Equatable {
    var id: UUID { participantId }
    let participantId: UUID
    let name: String
    let netBalance: Double
    let formattedBalance: String
}

/// Full response when loading a group's history and append-only event stream from the backend,
/// including continuous debt simplification transfers.
struct GroupLedgerHistoryResponse: Codable {
    let group: PersistentGroup
    let events: [LedgerEvent]
    let memberBalances: [GroupMemberBalance]
    let currentBalances: [String: Double]?
    let simplifiedTransfers: [SimplifiedPayment]?
    let simplifiedLines: [String]?
    let totalTransferred: Double?
}

/// Payload to create a new persistent group.
struct CreateGroupPayload: Encodable {
    let name: String
    let members: [ParticipantPayload]

    struct ParticipantPayload: Encodable {
        let id: UUID
        let name: String
    }
}

/// Payload to append an expense to the backend ledger.
struct AddGroupExpensePayload: Encodable {
    let title: String
    let amount: Double
    let payerId: UUID
    let splitMemberIds: [UUID]?
    let splits: [LedgerSplitPayload]?
    let receiptId: UUID?
    let note: String?

    struct LedgerSplitPayload: Encodable {
        let memberId: UUID
        let memberName: String
        let amount: Double
    }
}

/// Payload to append a settlement to the backend ledger.
struct AddGroupSettlementPayload: Encodable {
    let payerId: UUID
    let payeeId: UUID
    let amount: Double
    let note: String?
}
