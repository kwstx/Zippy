// MARK: - SubscriptionController.swift

import Vapor
import Fluent
import Foundation

/// Controller managing backend subscription queries, StoreKit verification, and feature gating.
struct SubscriptionController {

    /// Retrieves current subscription status and feature permissions.
    @Sendable
    func getStatus(req: Request) async throws -> SubscriptionStatusResponseDTO {
        let userId = req.headers.first(name: "X-User-Id")
            ?? req.headers.first(name: "X-Device-Id")
            ?? (try? req.query.get(String.self, at: "userId"))
            ?? "default_user"

        let record = try await SubscriptionService.getOrCreateSubscription(userId: userId, on: req.db)
        return SubscriptionService.makeStatusDTO(for: record)
    }

    /// Retrieves subscription status by explicit userId parameter.
    @Sendable
    func getStatusForUser(req: Request) async throws -> SubscriptionStatusResponseDTO {
        guard let userId = req.parameters.get("userId") else {
            throw Abort(.badRequest, reason: "Missing userId parameter.")
        }

        let record = try await SubscriptionService.getOrCreateSubscription(userId: userId, on: req.db)
        return SubscriptionService.makeStatusDTO(for: record)
    }

    /// Verifies a native StoreKit 2 transaction payload and upgrades user to Pro tier.
    @Sendable
    func verify(req: Request) async throws -> SubscriptionStatusResponseDTO {
        let payload = try req.content.decode(VerifySubscriptionRequest.self)
        let record = try await SubscriptionService.verifyAndActivateStoreKitTransaction(
            payload: payload,
            on: req.db,
            logger: req.logger
        )
        return SubscriptionService.makeStatusDTO(for: record)
    }

    /// Direct upgrade endpoint for testing, promotional access, or server-side tier management.
    @Sendable
    func upgrade(req: Request) async throws -> SubscriptionStatusResponseDTO {
        let payload = try req.content.decode(UpgradeSubscriptionRequest.self)
        let tierEnum = SubscriptionTier(rawValue: payload.tier.lowercased()) ?? .pro

        let record = try await SubscriptionService.setSubscriptionTier(
            userId: payload.userId,
            tier: tierEnum,
            productId: payload.productId,
            durationDays: payload.durationDays,
            on: req.db,
            logger: req.logger
        )
        return SubscriptionService.makeStatusDTO(for: record)
    }

    /// Checks if a specific feature is accessible under the user's current subscription tier.
    @Sendable
    func checkFeature(req: Request) async throws -> CheckFeatureAccessResponse {
        let payload = try req.content.decode(CheckFeatureAccessRequest.self)
        let record = try await SubscriptionService.getOrCreateSubscription(userId: payload.userId, on: req.db)
        let currentTier = SubscriptionTier(rawValue: record.tier) ?? .free

        let requiredTier: SubscriptionTier
        var isAllowed: Bool

        switch payload.feature.lowercased() {
        case "recurring_expenses", "recurring":
            requiredTier = .pro
            isAllowed = currentTier.canUseRecurringExpenses
        case "pdf_export", "export_pdf":
            requiredTier = .pro
            isAllowed = currentTier.canExportPDF
        case "automated_reminders", "reminders":
            requiredTier = .pro
            isAllowed = currentTier.canUseAutomatedReminders
        case "unlimited_groups", "groups":
            requiredTier = .pro
            isAllowed = currentTier.isPro
        default:
            requiredTier = .free
            isAllowed = true
        }

        return CheckFeatureAccessResponse(
            userId: payload.userId,
            feature: payload.feature,
            isAllowed: isAllowed,
            currentTier: currentTier,
            requiredTier: requiredTier
        )
    }
}
