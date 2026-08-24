// MARK: - SplitViewModel.swift

import SwiftUI
import Combine

/// Drives the split view with instant client-side recalculation on every change
/// and synchronization with the Vapor backend.
@MainActor
final class SplitViewModel: ObservableObject {
    let receipt: ExtractedReceiptResponse

    @Published var participants: [Participant] = []
    @Published var selectedSplitMethod: SplitMethod = .itemized

    // Allocations per split method
    @Published var assignments: [Int: Set<UUID>] = [:]
    @Published var percentageAllocations: [UUID: Double] = [:]
    @Published var shareAllocations: [UUID: Double] = [:]
    @Published var exactAllocations: [UUID: Double] = [:]

    @Published private(set) var splitResult: SplitResult?
    @Published var simplifiedPayments: [SimplifiedPayment] = []
    @Published var selectedCategory: ReceiptCategory?
    @Published var isFinalizing: Bool = false
    @Published var isSyncingWithBackend: Bool = false
    @Published var shareableURL: String?
    @Published var errorMessage: String?

    /// Indices of items that have no assignees (used for UI warnings in itemized mode).
    var unassignedItemIndices: [Int] {
        receipt.items.indices.filter { index in
            guard let assignees = assignments[index] else { return true }
            return assignees.isEmpty
        }
    }

    /// Sum of all percentage values assigned.
    var totalAssignedPercentage: Double {
        participants.reduce(0.0) { sum, p in
            sum + (percentageAllocations[p.id] ?? (participants.isEmpty ? 0 : 100.0 / Double(participants.count)))
        }
    }

    /// Sum of all share counts assigned.
    var totalAssignedShares: Double {
        participants.reduce(0.0) { sum, p in
            sum + (shareAllocations[p.id] ?? 1.0)
        }
    }

    /// Sum of all exact dollar amounts assigned.
    var totalAssignedExact: Double {
        participants.reduce(0.0) { sum, p in
            sum + (exactAllocations[p.id] ?? 0.0)
        }
    }

    /// Remaining balance to be allocated in exact split mode.
    var exactRemainingBalance: Double {
        receipt.total - totalAssignedExact
    }

    init(receipt: ExtractedReceiptResponse) {
        self.receipt = receipt
        self.selectedCategory = receipt.parsedCategory
    }

    // MARK: - Participant Management

    func addParticipant(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newParticipant = Participant(name: trimmed)
        participants.append(newParticipant)

        // Initialize default allocations for new participant
        initializeAllocationsForParticipant(newParticipant)

        recalculate()
        syncWithBackendIfActive()
    }

    func removeParticipant(id: UUID) {
        participants.removeAll { $0.id == id }

        // Clean up allocations referencing this participant
        for index in assignments.keys {
            assignments[index]?.remove(id)
        }
        percentageAllocations.removeValue(forKey: id)
        shareAllocations.removeValue(forKey: id)
        exactAllocations.removeValue(forKey: id)

        recalculate()
        syncWithBackendIfActive()
    }

    private func initializeAllocationsForParticipant(_ participant: Participant) {
        let count = Double(participants.count)
        if count > 0 {
            percentageAllocations[participant.id] = (100.0 / count)
            shareAllocations[participant.id] = 1.0
            exactAllocations[participant.id] = (receipt.total / count)
        }
    }

    // MARK: - Split Method Management

    func setSplitMethod(_ method: SplitMethod) {
        selectedSplitMethod = method

        // Ensure defaults are populated for the selected method
        ensureAllocationsInitialized()

        // Immediate client-side recalculation for snappy UI response
        recalculate()

        // Asynchronously sync the new method and allocations to backend
        syncWithBackendIfActive()
    }

    private func ensureAllocationsInitialized() {
        let count = Double(participants.count)
        guard count > 0 else { return }

        for p in participants {
            if percentageAllocations[p.id] == nil {
                percentageAllocations[p.id] = 100.0 / count
            }
            if shareAllocations[p.id] == nil {
                shareAllocations[p.id] = 1.0
            }
            if exactAllocations[p.id] == nil {
                exactAllocations[p.id] = receipt.total / count
            }
        }
    }

    // MARK: - Percentage Allocations

    func setPercentage(for participantId: UUID, percentage: Double) {
        percentageAllocations[participantId] = max(0, percentage)
        recalculate()
        syncWithBackendIfActive()
    }

    func adjustPercentage(for participantId: UUID, delta: Double) {
        let current = percentageAllocations[participantId] ?? (participants.isEmpty ? 0 : 100.0 / Double(participants.count))
        let next = max(0, min(100, current + delta))
        setPercentage(for: participantId, percentage: next)
    }

    func resetPercentagesToEqual() {
        let count = Double(participants.count)
        guard count > 0 else { return }
        let equalPct = (100.0 / count * 10).rounded() / 10
        for p in participants {
            percentageAllocations[p.id] = equalPct
        }
        recalculate()
        syncWithBackendIfActive()
    }

    // MARK: - Shares Allocations

    func setShares(for participantId: UUID, shares: Double) {
        shareAllocations[participantId] = max(0.1, shares)
        recalculate()
        syncWithBackendIfActive()
    }

    func adjustShares(for participantId: UUID, delta: Double) {
        let current = shareAllocations[participantId] ?? 1.0
        let next = max(0.5, current + delta)
        setShares(for: participantId, shares: next)
    }

    func resetSharesToEqual() {
        for p in participants {
            shareAllocations[p.id] = 1.0
        }
        recalculate()
        syncWithBackendIfActive()
    }

    // MARK: - Exact Amount Allocations

    func setExactAmount(for participantId: UUID, amount: Double) {
        exactAllocations[participantId] = max(0, (amount * 100).rounded() / 100)
        recalculate()
        syncWithBackendIfActive()
    }

    func resetExactToEqual() {
        let count = Double(participants.count)
        guard count > 0 else { return }
        let equalAmount = (receipt.total / count * 100).rounded() / 100
        for p in participants {
            exactAllocations[p.id] = equalAmount
        }
        recalculate()
        syncWithBackendIfActive()
    }

    // MARK: - Assignment Management (Itemized)

    func toggleAssignment(itemIndex: Int, participantId: UUID) {
        var current = assignments[itemIndex] ?? []
        if current.contains(participantId) {
            current.remove(participantId)
        } else {
            current.insert(participantId)
        }
        assignments[itemIndex] = current
        recalculate()
        syncWithBackendIfActive()
    }

    func assignAll(itemIndex: Int) {
        assignments[itemIndex] = Set(participants.map(\.id))
        recalculate()
        syncWithBackendIfActive()
    }

    func unassignAll(itemIndex: Int) {
        assignments[itemIndex] = []
        recalculate()
        syncWithBackendIfActive()
    }

    func isAssigned(itemIndex: Int, participantId: UUID) -> Bool {
        assignments[itemIndex]?.contains(participantId) ?? false
    }

    /// Returns the participants assigned to a given item index.
    func assignees(for itemIndex: Int) -> [Participant] {
        guard let ids = assignments[itemIndex] else { return [] }
        return participants.filter { ids.contains($0.id) }
    }

    // MARK: - Instant Synchronous Calculation

    func recalculate() {
        let result = SplitCalculator.calculate(
            method: selectedSplitMethod,
            items: receipt.items,
            participants: participants,
            assignments: assignments,
            percentageAllocations: percentageAllocations,
            shareAllocations: shareAllocations,
            exactAllocations: exactAllocations,
            subtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total
        )
        splitResult = result
        simplifiedPayments = SplitCalculator.simplify(balances: result.balances)
    }

    /// Fetches authoritative simplified payments computed by the Vapor backend.
    func fetchSimplifiedPayments() async {
        guard let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty else {
            if let balances = splitResult?.balances {
                simplifiedPayments = SplitCalculator.simplify(balances: balances)
            }
            return
        }

        do {
            let response = try await ReceiptService.getSimplifiedPayments(token: token)
            simplifiedPayments = response.transfers
        } catch {
            if let balances = splitResult?.balances {
                simplifiedPayments = SplitCalculator.simplify(balances: balances)
            }
        }
    }

    // MARK: - Server Communication & Synchronization

    /// Wire format dictionaries for JSON payloads
    private var wireAssignments: [String: [UUID]] {
        var dict: [String: [UUID]] = [:]
        for (index, ids) in assignments {
            dict[String(index)] = Array(ids)
        }
        return dict
    }

    private var wirePercentages: [String: Double] {
        var dict: [String: Double] = [:]
        for (id, val) in percentageAllocations {
            dict[id.uuidString] = val
        }
        return dict
    }

    private var wireShares: [String: Double] {
        var dict: [String: Double] = [:]
        for (id, val) in shareAllocations {
            dict[id.uuidString] = val
        }
        return dict
    }

    private var wireExact: [String: Double] {
        var dict: [String: Double] = [:]
        for (id, val) in exactAllocations {
            dict[id.uuidString] = val
        }
        return dict
    }

    private func syncWithBackendIfActive() {
        let token = shareableURL?.components(separatedBy: "/s/").last
        guard (token != nil && !token!.isEmpty) || receipt.id != nil else { return }

        Task {
            isSyncingWithBackend = true
            do {
                let response: SplitSessionResponse
                if let token = token, !token.isEmpty {
                    response = try await ReceiptService.updateSplitMethod(
                        token: token,
                        method: selectedSplitMethod,
                        participants: participants,
                        assignments: wireAssignments,
                        percentageAllocations: wirePercentages,
                        shareAllocations: wireShares,
                        exactAllocations: wireExact
                    )
                } else if let receiptId = receipt.id {
                    response = try await ReceiptService.finalizeSplit(
                        receiptId: receiptId,
                        participants: participants,
                        splitMethod: selectedSplitMethod,
                        assignments: wireAssignments,
                        percentageAllocations: wirePercentages,
                        shareAllocations: wireShares,
                        exactAllocations: wireExact,
                        category: selectedCategory?.rawValue
                    )
                } else {
                    return
                }

                // In-place refresh of monochrome totals
                self.splitResult = SplitResult(
                    balances: response.appBalances,
                    assignedSubtotal: splitResult?.assignedSubtotal ?? receipt.subtotal
                )
                if response.shareableURL != nil {
                    self.shareableURL = response.shareableURL
                }
            } catch {
                // Silently fallback to local calculation on transient connection drops
            }
            isSyncingWithBackend = false
        }
    }

    // MARK: - Server Finalization

    func finalize() async {
        guard let receiptId = receipt.id else {
            errorMessage = "Receipt has no server ID."
            return
        }

        isFinalizing = true
        errorMessage = nil

        do {
            let response = try await ReceiptService.finalizeSplit(
                receiptId: receiptId,
                participants: participants,
                splitMethod: selectedSplitMethod,
                assignments: wireAssignments,
                percentageAllocations: wirePercentages,
                shareAllocations: wireShares,
                exactAllocations: wireExact,
                category: selectedCategory?.rawValue
            )

            // Update with authoritative server-computed balances
            self.splitResult = SplitResult(
                balances: response.appBalances,
                assignedSubtotal: splitResult?.assignedSubtotal ?? receipt.subtotal
            )
            self.shareableURL = response.shareableURL
            if let cat = response.category {
                self.selectedCategory = ReceiptCategory(flexibleString: cat)
            }
        } catch {
            self.errorMessage = "Failed to save split: \(error.localizedDescription)"
        }

        isFinalizing = false
    }

    // MARK: - Category Management

    func updateCategory(_ category: ReceiptCategory?) {
        self.selectedCategory = category

        if let receiptId = receipt.id {
            Task {
                try? await ReceiptService.updateReceiptCategory(receiptId: receiptId, category: category?.rawValue)
            }
        }

        if let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty {
            Task {
                try? await ReceiptService.updateSplitCategory(token: token, category: category?.rawValue)
            }
        }
    }

    // MARK: - External Payment Methods

    func selectPaymentMethod(participantId: UUID, method: String) async -> SelectPaymentMethodResponse? {
        guard let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty else {
            if let index = splitResult?.balances.firstIndex(where: { $0.participantId == participantId }) {
                var balances = splitResult!.balances
                balances[index].paymentMethod = method
                balances[index].settlementStatus = .pendingConfirmation
                splitResult = SplitResult(balances: balances, assignedSubtotal: splitResult?.assignedSubtotal ?? receipt.subtotal)
            }
            return nil
        }

        do {
            let response = try await ReceiptService.selectPaymentMethod(
                token: token,
                participantId: participantId,
                method: method
            )
            await refreshStatus()
            return response
        } catch {
            self.errorMessage = "Failed to select payment method: \(error.localizedDescription)"
            return nil
        }
    }

    func confirmSettlement(participantId: UUID) async {
        guard let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty else {
            if let index = splitResult?.balances.firstIndex(where: { $0.participantId == participantId }) {
                var balances = splitResult!.balances
                balances[index].isPaid = true
                balances[index].settlementStatus = .settled
                balances[index].paidAt = Date()
                splitResult = SplitResult(balances: balances, assignedSubtotal: splitResult?.assignedSubtotal ?? receipt.subtotal)
            }
            return
        }

        do {
            try await ReceiptService.confirmSettlement(token: token, participantId: participantId)
            await refreshStatus()
        } catch {
            self.errorMessage = "Failed to confirm settlement: \(error.localizedDescription)"
        }
    }

    // MARK: - Status Polling

    func refreshStatus() async {
        guard let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty else { return }
        do {
            let response = try await ReceiptService.getSplitByToken(token: token)
            self.splitResult = SplitResult(
                balances: response.appBalances,
                assignedSubtotal: splitResult?.assignedSubtotal ?? receipt.subtotal
            )
        } catch {
            // Silently ignore background polling errors
        }
    }
}
