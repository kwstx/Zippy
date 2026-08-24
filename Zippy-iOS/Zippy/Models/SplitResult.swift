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

/// How much a single participant owes, broken down by component with multi-currency support.
struct PersonBalance: Identifiable, Codable, Equatable {
    var id: UUID { participantId }
    let participantId: UUID
    let name: String
    let itemsSubtotal: Double
    let taxShare: Double
    let tipShare: Double
    let total: Double
    var currency: String
    var convertedItemsSubtotal: Double?
    var convertedTaxShare: Double?
    var convertedTipShare: Double?
    var convertedTotal: Double?
    var targetCurrency: String?
    var exchangeRate: Double?
    var isPaid: Bool
    var paidAt: Date?
    var paymentMethod: String?
    var settlementStatus: SettlementStatus

    enum CodingKeys: String, CodingKey {
        case participantId, name, itemsSubtotal, taxShare, tipShare, total, currency
        case convertedItemsSubtotal, convertedTaxShare, convertedTipShare, convertedTotal
        case targetCurrency, exchangeRate, isPaid, paidAt, paymentMethod, settlementStatus
    }

    init(
        participantId: UUID,
        name: String,
        itemsSubtotal: Double,
        taxShare: Double,
        tipShare: Double,
        total: Double,
        currency: String = "USD",
        convertedItemsSubtotal: Double? = nil,
        convertedTaxShare: Double? = nil,
        convertedTipShare: Double? = nil,
        convertedTotal: Double? = nil,
        targetCurrency: String? = "USD",
        exchangeRate: Double? = 1.0,
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
        self.currency = currency
        let rate = exchangeRate ?? 1.0
        self.convertedItemsSubtotal = convertedItemsSubtotal ?? ((itemsSubtotal * rate * 100).rounded() / 100)
        self.convertedTaxShare = convertedTaxShare ?? ((taxShare * rate * 100).rounded() / 100)
        self.convertedTipShare = convertedTipShare ?? ((tipShare * rate * 100).rounded() / 100)
        self.convertedTotal = convertedTotal ?? ((total * rate * 100).rounded() / 100)
        self.targetCurrency = targetCurrency ?? "USD"
        self.exchangeRate = rate
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
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"

        let rate = try container.decodeIfPresent(Double.self, forKey: .exchangeRate) ?? 1.0
        exchangeRate = rate
        targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency) ?? "USD"
        convertedItemsSubtotal = try container.decodeIfPresent(Double.self, forKey: .convertedItemsSubtotal) ?? ((itemsSubtotal * rate * 100).rounded() / 100)
        convertedTaxShare = try container.decodeIfPresent(Double.self, forKey: .convertedTaxShare) ?? ((taxShare * rate * 100).rounded() / 100)
        convertedTipShare = try container.decodeIfPresent(Double.self, forKey: .convertedTipShare) ?? ((tipShare * rate * 100).rounded() / 100)
        convertedTotal = try container.decodeIfPresent(Double.self, forKey: .convertedTotal) ?? ((total * rate * 100).rounded() / 100)

        isPaid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
        paidAt = try container.decodeIfPresent(Date.self, forKey: .paidAt)
        paymentMethod = try container.decodeIfPresent(String.self, forKey: .paymentMethod)
        settlementStatus = try container.decodeIfPresent(SettlementStatus.self, forKey: .settlementStatus) ?? (isPaid ? .settled : .unpaid)
    }
}

/// The complete result of splitting a receipt among participants.
struct SplitResult: Codable, Equatable {
    let balances: [PersonBalance]
    /// Sum of only the items that have been assigned to at least one person.
    let assignedSubtotal: Double
    var currency: String = "USD"
    var convertedAssignedSubtotal: Double? = nil

    init(
        balances: [PersonBalance],
        assignedSubtotal: Double,
        currency: String = "USD",
        convertedAssignedSubtotal: Double? = nil
    ) {
        self.balances = balances
        self.assignedSubtotal = assignedSubtotal
        self.currency = currency
        self.convertedAssignedSubtotal = convertedAssignedSubtotal ?? assignedSubtotal
    }
}

/// A simplified payment transfer returned by the minimum-cash-flow algorithm.
struct SimplifiedPayment: Identifiable, Codable, Equatable {
    var id: String { "\(fromId)-\(toId)-\(amount)-\(currency)" }
    let fromId: UUID
    let fromName: String
    let toId: UUID
    let toName: String
    let amount: Double
    var currency: String
    var originalAmount: Double?
    var originalCurrency: String?
    var exchangeRate: Double?
    let formattedText: String

    init(
        fromId: UUID,
        fromName: String,
        toId: UUID,
        toName: String,
        amount: Double,
        currency: String = "USD",
        originalAmount: Double? = nil,
        originalCurrency: String? = nil,
        exchangeRate: Double? = 1.0,
        formattedText: String
    ) {
        self.fromId = fromId
        self.fromName = fromName
        self.toId = toId
        self.toName = toName
        self.amount = amount
        self.currency = currency
        self.originalAmount = originalAmount ?? amount
        self.originalCurrency = originalCurrency ?? currency
        self.exchangeRate = exchangeRate ?? 1.0
        self.formattedText = formattedText
    }
}
