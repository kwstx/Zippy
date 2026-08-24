// MARK: - SplitResult.swift

import Foundation

/// The 5 flexible bill-splitting methods supported across the system.
enum SplitMethod: String, Codable, CaseIterable, Identifiable {
    case equal = "equal"
    case itemized = "itemized"
    case percentage = "percentage"
    case shares = "shares"
    case exact = "exact"

    var id: String { rawValue }

    /// Pure uppercase text label for the monochrome segmented control.
    var textLabel: String {
        switch self {
        case .equal: return "EQUAL"
        case .itemized: return "ITEMIZED"
        case .percentage: return "PERCENT"
        case .shares: return "SHARES"
        case .exact: return "EXACT"
        }
    }

    /// Short title / display name.
    var title: String {
        switch self {
        case .equal: return "Equal"
        case .itemized: return "Itemized"
        case .percentage: return "Percentage"
        case .shares: return "Shares"
        case .exact: return "Exact"
        }
    }

    /// Descriptive explanation of the splitting method.
    var description: String {
        switch self {
        case .equal: return "Split the entire bill evenly among all participants."
        case .itemized: return "Assign specific items to people with proportional tax & tip."
        case .percentage: return "Allocate custom percentages to each person."
        case .shares: return "Divide according to weighted share counts."
        case .exact: return "Assign exact dollar amounts to each participant."
        }
    }
}

/// Status of a participant's balance settlement.
enum SettlementStatus: String, Codable, Equatable {
    case unpaid = "unpaid"
    case pendingConfirmation = "pending_confirmation"
    case settled = "settled"
}

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
    var settlementStatus: SettlementStatus

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
}

/// The complete result of splitting a receipt among participants.
struct SplitResult: Codable, Equatable {
    let balances: [PersonBalance]
    /// Sum of only the items that have been assigned to at least one person.
    let assignedSubtotal: Double
}

/// A simplified payment transfer returned by the minimum-cash-flow algorithm.
struct SimplifiedPayment: Identifiable, Codable, Equatable {
    var id: String { "\(fromId)-\(toId)-\(amount)" }
    let fromId: UUID
    let fromName: String
    let toId: UUID
    let toName: String
    let amount: Double
    let formattedText: String
}

