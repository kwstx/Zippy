// MARK: - SubscriptionDTOs.swift

import Vapor
import Foundation

/// Subscription tier enumeration defining feature privileges and limits.
enum SubscriptionTier: String, Codable, Sendable {
    case free
    case pro

    var isPro: Bool {
        self == .pro
    }

    /// Maximum active persistent groups allowed for the tier.
    var maxGroups: Int {
        switch self {
        case .free: return 2
        case .pro: return Int.max
        }
    }

    /// Maximum receipts scan / manual extractions allowed per month.
    var maxMonthlyReceipts: Int {
        switch self {
        case .free: return 5
        case .pro: return Int.max
        }
    }

    /// Whether recurring expense automation is enabled.
    var canUseRecurringExpenses: Bool {
        switch self {
        case .free: return false
        case .pro: return true
        }
    }

    /// Whether PDF reports and advanced multi-currency exports are allowed.
    var canExportPDF: Bool {
        switch self {
        case .free: return false
        case .pro: return true
        }
    }

    /// Whether automated silent debt reminders can be scheduled.
    var canUseAutomatedReminders: Bool {
        switch self {
        case .free: return false
        case .pro: return true
        }
    }
}

/// DTO summarizing the user's active limits and permissions.
struct SubscriptionLimitsDTO: Content, Sendable {
    let maxGroups: Int
    let maxMonthlyReceipts: Int
    let canUseRecurringExpenses: Bool
    let canExportPDF: Bool
    let canUseAutomatedReminders: Bool
}

/// DTO returned when querying subscription status from the backend.
struct SubscriptionStatusResponseDTO: Content, Sendable {
    let userId: String
    let tier: SubscriptionTier
    let isPro: Bool
    let isActive: Bool
    let productId: String?
    let originalTransactionId: String?
    let expiresAt: Date?
    let limits: SubscriptionLimitsDTO
    let message: String
}

/// Request payload for validating a StoreKit 2 transaction with the backend.
struct VerifySubscriptionRequest: Content, Sendable {
    let userId: String
    let productId: String
    let originalTransactionId: String
    let transactionReceipt: String?
    let expiresAt: Date?
}

/// Request payload to upgrade/manage user tier directly.
struct UpgradeSubscriptionRequest: Content, Sendable {
    let userId: String
    let tier: String
    let productId: String?
    let durationDays: Int?
}

/// Gated feature check request payload.
struct CheckFeatureAccessRequest: Content, Sendable {
    let userId: String
    let feature: String
}

/// Gated feature check response payload.
struct CheckFeatureAccessResponse: Content, Sendable {
    let userId: String
    let feature: String
    let isAllowed: Bool
    let currentTier: SubscriptionTier
    let requiredTier: SubscriptionTier
}
