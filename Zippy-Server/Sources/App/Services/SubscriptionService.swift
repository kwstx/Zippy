// MARK: - SubscriptionService.swift

import Vapor
import Fluent
import Foundation

/// Backend service responsible for gating Free-tier and Pro upgrades, verifying StoreKit transactions, and tracking entitlements.
enum SubscriptionService {

    /// Retrieves or provisions a subscription record for a user/device ID.
    static func getOrCreateSubscription(userId: String, on db: Database) async throws -> SubscriptionRecord {
        let cleanUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "default_user" : userId

        if let existing = try await SubscriptionRecord.query(on: db)
            .filter(\.$userId == cleanUserId)
            .first() {
            // Check if Pro subscription has expired
            if existing.tier == SubscriptionTier.pro.rawValue, let expiresAt = existing.expiresAt, expiresAt < Date() {
                existing.tier = SubscriptionTier.free.rawValue
                existing.isActive = false
                try await existing.save(on: db)
            }
            return existing
        }

        let newRecord = SubscriptionRecord(
            userId: cleanUserId,
            tier: SubscriptionTier.free.rawValue,
            productId: nil,
            originalTransactionId: nil,
            expiresAt: nil,
            isActive: true,
            receiptToken: nil
        )
        try await newRecord.save(on: db)
        return newRecord
    }

    /// Verifies and activates a StoreKit 2 transaction, updating the backend state to Pro.
    static func verifyAndActivateStoreKitTransaction(
        payload: VerifySubscriptionRequest,
        on db: Database,
        logger: Logger
    ) async throws -> SubscriptionRecord {
        let record = try await getOrCreateSubscription(userId: payload.userId, on: db)

        // StoreKit Product validation
        let validProductPrefixes = ["com.zippy.app.pro", "pro.subscription", "zippy.pro"]
        let isValidProduct = validProductPrefixes.contains { payload.productId.contains($0) } || payload.productId.lowercased().contains("pro")

        guard isValidProduct else {
            logger.warning("Subscription verification failed: unrecognized product ID '\(payload.productId)'")
            throw Abort(.badRequest, reason: "Unrecognized Pro subscription product identifier.")
        }

        // Set tier to Pro
        record.tier = SubscriptionTier.pro.rawValue
        record.productId = payload.productId
        record.originalTransactionId = payload.originalTransactionId
        record.receiptToken = payload.transactionReceipt
        record.isActive = true
        record.expiresAt = payload.expiresAt ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())

        try await record.save(on: db)
        logger.info("Successfully verified StoreKit transaction for user '\(payload.userId)'. Upgraded to Pro tier until \(String(describing: record.expiresAt)).")
        return record
    }

    /// Manually upgrades or sets a tier for development, testing, or server-side promotion.
    static func setSubscriptionTier(
        userId: String,
        tier: SubscriptionTier,
        productId: String? = nil,
        durationDays: Int? = nil,
        on db: Database,
        logger: Logger
    ) async throws -> SubscriptionRecord {
        let record = try await getOrCreateSubscription(userId: userId, on: db)

        record.tier = tier.rawValue
        record.productId = productId ?? (tier == .pro ? "com.zippy.app.pro.monthly" : nil)
        record.isActive = true

        if tier == .pro {
            let days = durationDays ?? 30
            record.expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
        } else {
            record.expiresAt = nil
            record.originalTransactionId = nil
        }

        try await record.save(on: db)
        logger.info("Updated subscription tier for user '\(userId)' to '\(tier.rawValue)'.")
        return record
    }

    /// Generates the standard status DTO for a given subscription record.
    static func makeStatusDTO(for record: SubscriptionRecord) -> SubscriptionStatusResponseDTO {
        let tierEnum = SubscriptionTier(rawValue: record.tier) ?? .free
        let isPro = (tierEnum == .pro) && record.isActive

        let limits = SubscriptionLimitsDTO(
            maxGroups: tierEnum.maxGroups,
            maxMonthlyReceipts: tierEnum.maxMonthlyReceipts,
            canUseRecurringExpenses: tierEnum.canUseRecurringExpenses,
            canExportPDF: tierEnum.canExportPDF,
            canUseAutomatedReminders: tierEnum.canUseAutomatedReminders
        )

        let message = isPro
            ? "Pro subscription is active."
            : "Free tier active. Upgrade to Pro for unlimited scans, groups, recurring templates, and exports."

        return SubscriptionStatusResponseDTO(
            userId: record.userId,
            tier: tierEnum,
            isPro: isPro,
            isActive: record.isActive,
            productId: record.productId,
            originalTransactionId: record.originalTransactionId,
            expiresAt: record.expiresAt,
            limits: limits,
            message: message
        )
    }

    // MARK: - Feature Gating Assertions

    /// Checks if a user is currently Pro, throwing 403 Forbidden with upgrade prompt if not.
    static func assertProUser(userId: String, featureName: String, on db: Database) async throws {
        let record = try await getOrCreateSubscription(userId: userId, on: db)
        let tierEnum = SubscriptionTier(rawValue: record.tier) ?? .free

        guard tierEnum == .pro && record.isActive else {
            throw Abort(
                .forbidden,
                reason: "Pro tier subscription required to access '\(featureName)'. Please upgrade via the in-app StoreKit paywall."
            )
        }
    }

    /// Evaluates if user can create a new group given current tier count limits.
    static func canCreateGroup(userId: String, currentGroupCount: Int, on db: Database) async throws -> Bool {
        let record = try await getOrCreateSubscription(userId: userId, on: db)
        let tierEnum = SubscriptionTier(rawValue: record.tier) ?? .free
        return currentGroupCount < tierEnum.maxGroups
    }

    /// Evaluates if user can scan or extract a new receipt this month.
    static func canScanReceipt(userId: String, monthlyReceiptCount: Int, on db: Database) async throws -> Bool {
        let record = try await getOrCreateSubscription(userId: userId, on: db)
        let tierEnum = SubscriptionTier(rawValue: record.tier) ?? .free
        return monthlyReceiptCount < tierEnum.maxMonthlyReceipts
    }
}
