// MARK: - SubscriptionManager.swift

import Foundation
import SwiftUI
import StoreKit

/// StoreKit 2 and Backend Subscription Manager.
/// Manages native App Store transaction listening, backend tier verification, and feature gating.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers
    static let proMonthlyId = "com.zippy.app.pro.monthly"
    static let proAnnualId = "com.zippy.app.pro.annual"
    static let productIds = [proMonthlyId, proAnnualId]

    // MARK: - Published State
    @Published var isPro: Bool = false
    @Published var currentTier: SubscriptionTier = .free
    @Published var availableProducts: [Product] = []
    @Published var limits: SubscriptionLimits?
    @Published var isLoading: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var showPaywall: Bool = false
    @Published var showStoreKitSheet: Bool = false
    @Published var errorMessage: String?

    // MARK: - Device Identity
    var deviceId: String {
        if let saved = UserDefaults.standard.string(forKey: "zippy_device_id") {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: "zippy_device_id")
        return newId
    }

    private var transactionListenerTask: Task<Void, Never>?

    init() {
        // Start StoreKit 2 transaction updates listener
        transactionListenerTask = listenForTransactions()

        Task {
            await fetchProducts()
            await refreshBackendSubscriptionStatus()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - StoreKit 2 Transaction Listener
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await self?.handleVerifiedTransaction(transaction)
                    await transaction.finish()
                } catch {
                    print("[StoreKit] Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Product Fetching
    func fetchProducts() async {
        do {
            let products = try await Product.products(for: Self.productIds)
            self.availableProducts = products
        } catch {
            print("[StoreKit] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase Flow
    /// Triggers native StoreKit purchase flow for the Pro subscription.
    func purchasePro(product: Product? = nil) async {
        isPurchasing = true
        errorMessage = nil

        let targetProduct = product ?? availableProducts.first

        if let productToBuy = targetProduct {
            do {
                let result = try await productToBuy.purchase()

                switch result {
                case .success(let verification):
                    let transaction = try Self.checkVerified(verification)
                    await handleVerifiedTransaction(transaction)
                    await transaction.finish()
                    self.showPaywall = false
                    self.showStoreKitSheet = false

                case .userCancelled:
                    print("[StoreKit] User cancelled purchase")

                case .pending:
                    print("[StoreKit] Purchase pending authorization")

                @unknown default:
                    break
                }
            } catch {
                self.errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
        } else {
            // Development fallback / sandbox simulator upgrade
            await performDevProUpgrade()
        }

        isPurchasing = false
    }

    /// Development / Sandbox fallback that upgrades via the backend subscription service directly.
    func performDevProUpgrade() async {
        isLoading = true
        do {
            let status = try await SubscriptionService.upgradeTier(userId: deviceId, tier: "pro")
            self.isPro = status.isPro
            self.currentTier = status.tier
            self.limits = status.limits
            self.showPaywall = false
            self.showStoreKitSheet = false
        } catch {
            self.errorMessage = "Failed to activate Pro: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Handles a verified StoreKit 2 transaction by sending it to the backend subscription service.
    private func handleVerifiedTransaction(_ transaction: StoreKit.Transaction) async {
        do {
            let status = try await SubscriptionService.verifyStoreKitTransaction(
                userId: deviceId,
                productId: transaction.productID,
                originalTransactionId: String(transaction.originalID),
                transactionReceipt: nil,
                expiresAt: transaction.expirationDate
            )
            self.isPro = status.isPro
            self.currentTier = status.tier
            self.limits = status.limits
        } catch {
            print("[SubscriptionService] Failed to sync transaction with backend: \(error)")
            // Fallback: grant entitlement locally based on verified StoreKit transaction
            self.isPro = true
            self.currentTier = .pro
        }
    }

    /// Verifies transaction signature cryptographically via StoreKit 2.
    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Backend Status Sync
    /// Refreshes the subscription status and limits from the backend subscription service.
    func refreshBackendSubscriptionStatus() async {
        do {
            let status = try await SubscriptionService.fetchStatus(userId: deviceId)
            self.isPro = status.isPro
            self.currentTier = status.tier
            self.limits = status.limits
        } catch {
            print("[SubscriptionService] Status fetch error: \(error)")
        }
    }

    /// Restores previous StoreKit purchases and syncs with backend.
    func restorePurchases() async {
        isLoading = true
        do {
            try await AppStore.sync()
            for await result in StoreKit.Transaction.currentEntitlements {
                if let transaction = try? Self.checkVerified(result) {
                    await handleVerifiedTransaction(transaction)
                }
            }
            await refreshBackendSubscriptionStatus()
        } catch {
            self.errorMessage = "Failed to restore: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Triggers presentation of the minimalist paywall card.
    func presentPaywall() {
        self.showPaywall = true
    }
}
