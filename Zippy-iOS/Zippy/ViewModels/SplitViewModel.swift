// MARK: - SplitViewModel.swift

import SwiftUI
import Combine

/// Drives the split view with instant client-side recalculation on every change.
@MainActor
final class SplitViewModel: ObservableObject {
    let receipt: ExtractedReceiptResponse

    @Published var participants: [Participant] = []
    @Published var assignments: [Int: Set<UUID>] = [:]
    @Published private(set) var splitResult: SplitResult?
    @Published var isFinalizing: Bool = false
    @Published var shareableURL: String?
    @Published var errorMessage: String?

    /// Indices of items that have no assignees (used for UI warnings).
    var unassignedItemIndices: [Int] {
        receipt.items.indices.filter { index in
            guard let assignees = assignments[index] else { return true }
            return assignees.isEmpty
        }
    }

    init(receipt: ExtractedReceiptResponse) {
        self.receipt = receipt
    }

    // MARK: - Participant Management

    func addParticipant(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        participants.append(Participant(name: trimmed))
        recalculate()
    }

    func removeParticipant(id: UUID) {
        participants.removeAll { $0.id == id }
        // Clean up assignments referencing this participant
        for index in assignments.keys {
            assignments[index]?.remove(id)
        }
        recalculate()
    }

    // MARK: - Assignment Management

    func toggleAssignment(itemIndex: Int, participantId: UUID) {
        var current = assignments[itemIndex] ?? []
        if current.contains(participantId) {
            current.remove(participantId)
        } else {
            current.insert(participantId)
        }
        assignments[itemIndex] = current
        recalculate()
    }

    func assignAll(itemIndex: Int) {
        assignments[itemIndex] = Set(participants.map(\.id))
        recalculate()
    }

    func unassignAll(itemIndex: Int) {
        assignments[itemIndex] = []
        recalculate()
    }

    func isAssigned(itemIndex: Int, participantId: UUID) -> Bool {
        assignments[itemIndex]?.contains(participantId) ?? false
    }

    /// Returns the participants assigned to a given item index.
    func assignees(for itemIndex: Int) -> [Participant] {
        guard let ids = assignments[itemIndex] else { return [] }
        return participants.filter { ids.contains($0.id) }
    }

    // MARK: - Calculation

    func recalculate() {
        splitResult = SplitCalculator.calculate(
            items: receipt.items,
            participants: participants,
            assignments: assignments,
            tax: receipt.tax,
            tip: receipt.tip
        )
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
            // Convert assignments to [String: [UUID]] for JSON wire format
            var wireAssignments: [String: [UUID]] = [:]
            for (index, ids) in assignments {
                wireAssignments[String(index)] = Array(ids)
            }

            let response = try await ReceiptService.finalizeSplit(
                receiptId: receiptId,
                participants: participants,
                assignments: wireAssignments
            )

            // Update with authoritative server-computed balances
            self.splitResult = SplitResult(
                balances: response.appBalances,
                assignedSubtotal: splitResult?.assignedSubtotal ?? 0
            )
            self.shareableURL = response.shareableURL
        } catch {
            self.errorMessage = "Failed to save split: \(error.localizedDescription)"
        }

        isFinalizing = false
    }

    // MARK: - External Payment Methods

    func selectPaymentMethod(participantId: UUID, method: String) async -> SelectPaymentMethodResponse? {
        guard let token = shareableURL?.components(separatedBy: "/s/").last, !token.isEmpty else {
            // Update local balance state immediately if session is not yet finalized
            if let index = splitResult?.balances.firstIndex(where: { $0.participantId == participantId }) {
                var balances = splitResult!.balances
                balances[index].paymentMethod = method
                balances[index].settlementStatus = .pendingConfirmation
                splitResult = SplitResult(balances: balances, assignedSubtotal: splitResult?.assignedSubtotal ?? 0)
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
            // Update local state if session is not yet finalized
            if let index = splitResult?.balances.firstIndex(where: { $0.participantId == participantId }) {
                var balances = splitResult!.balances
                balances[index].isPaid = true
                balances[index].settlementStatus = .settled
                balances[index].paidAt = Date()
                splitResult = SplitResult(balances: balances, assignedSubtotal: splitResult?.assignedSubtotal ?? 0)
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
                assignedSubtotal: splitResult?.assignedSubtotal ?? 0
            )
        } catch {
            // Silently ignore background polling errors
        }
    }
}
