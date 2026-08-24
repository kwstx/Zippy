// MARK: - GroupModels.swift

import Foundation

/// Persistent group representing a shared expense pool with a member roster and running balance.
struct PersistentGroup: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var members: [Participant]
    var runningBalance: Double
    var formattedBalance: String
    var currency: String
    var memberCount: Int
    var eventCount: Int
    var lastActivity: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, members, runningBalance, formattedBalance, currency, memberCount, eventCount, lastActivity, createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        members: [Participant] = [],
        runningBalance: Double = 0.0,
        formattedBalance: String = "0.00 USD",
        currency: String = "USD",
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
        self.currency = currency
        self.memberCount = memberCount.max(members.count)
        self.eventCount = eventCount
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        members = try container.decode([Participant].self, forKey: .members)
        runningBalance = try container.decode(Double.self, forKey: .runningBalance)
        formattedBalance = try container.decode(String.self, forKey: .formattedBalance)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        let count = try container.decode(Int.self, forKey: .memberCount)
        memberCount = count.max(members.count)
        eventCount = try container.decode(Int.self, forKey: .eventCount)
        lastActivity = try container.decodeIfPresent(Date.self, forKey: .lastActivity)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
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
    var currency: String
    var convertedAmount: Double?

    init(
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

/// An immutable event in the group's append-only ledger event stream.
struct LedgerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let eventType: String
    let title: String
    let amount: Double
    var currency: String?
    var convertedAmount: Double?
    var targetCurrency: String?
    var exchangeRate: Double?
    let payerId: UUID
    let payerName: String
    let payeeId: UUID?
    let payeeName: String?
    let splits: [LedgerSplit]
    let runningBalanceAfter: Double?
    let receiptId: UUID?
    let note: String?
    let createdAt: Date?

    var effectiveCurrency: String {
        currency ?? "USD"
    }

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
    var currency: String = "USD"

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantId = try container.decode(UUID.self, forKey: .participantId)
        name = try container.decode(String.self, forKey: .name)
        netBalance = try container.decode(Double.self, forKey: .netBalance)
        formattedBalance = try container.decode(String.self, forKey: .formattedBalance)
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
    }

    enum CodingKeys: String, CodingKey {
        case participantId, name, netBalance, formattedBalance, currency
    }
}

/// Full response when loading a group's history and append-only event stream from the backend,
/// including continuous debt simplification transfers.
struct GroupLedgerHistoryResponse: Codable {
    let group: PersistentGroup
    let events: [LedgerEvent]
    let memberBalances: [GroupMemberBalance]
    let currentBalances: [String: Double]?
    let currency: String?
    let simplifiedTransfers: [SimplifiedPayment]?
    let simplifiedLines: [String]?
    let totalTransferred: Double?
}

/// Payload to create a new persistent group.
struct CreateGroupPayload: Encodable {
    let name: String
    let members: [ParticipantPayload]
    let currency: String?

    struct ParticipantPayload: Encodable {
        let id: UUID
        let name: String
    }
}

/// Payload to append an expense to the backend ledger.
struct AddGroupExpensePayload: Encodable {
    let title: String
    let amount: Double
    let currency: String?
    let targetCurrency: String?
    let payerId: UUID
    let splitMemberIds: [UUID]?
    let splits: [LedgerSplitPayload]?
    let receiptId: UUID?
    let note: String?

    struct LedgerSplitPayload: Encodable {
        let memberId: UUID
        let memberName: String
        let amount: Double
        let currency: String?
    }
}

/// Payload to append a settlement to the backend ledger.
struct AddGroupSettlementPayload: Encodable {
    let payerId: UUID
    let payeeId: UUID
    let amount: Double
    let currency: String?
    let targetCurrency: String?
    let note: String?
}
