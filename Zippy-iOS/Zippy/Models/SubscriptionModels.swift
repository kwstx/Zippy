// MARK: - SubscriptionModels.swift

import Foundation

/// Subscription tier enumeration on iOS.
enum SubscriptionTier: String, Codable, Sendable {
    case free
    case pro

    var isPro: Bool {
        self == .pro
    }
}

/// Limits and feature gates provided by the backend subscription service.
struct SubscriptionLimits: Codable, Sendable {
    let maxGroups: Int
    let maxMonthlyReceipts: Int
    let canUseRecurringExpenses: Bool
    let canExportPDF: Bool
    let canUseAutomatedReminders: Bool
}

/// Active subscription status returned by the backend.
struct SubscriptionStatus: Codable, Sendable {
    let userId: String
    let tier: SubscriptionTier
    let isPro: Bool
    let isActive: Bool
    let productId: String?
    let originalTransactionId: String?
    let expiresAt: Date?
    let limits: SubscriptionLimits
    let message: String
}
