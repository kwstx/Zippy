// MARK: - GroupLedgerViewModel.swift

import Foundation
import SwiftUI

@MainActor
final class GroupLedgerViewModel: ObservableObject {
    let groupId: UUID

    @Published var group: PersistentGroup?
    @Published var events: [LedgerEvent] = []
    @Published var memberBalances: [GroupMemberBalance] = []
    @Published var isLoading: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil

    init(groupId: UUID, initialGroup: PersistentGroup? = nil) {
        self.groupId = groupId
        self.group = initialGroup
    }

    func loadHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await GroupService.fetchGroupHistory(groupId: groupId)
                self.group = response.group
                self.events = response.events
                self.memberBalances = response.memberBalances
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to load ledger history: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    func addExpense(
        title: String,
        amount: Double,
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        note: String? = nil
    ) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await GroupService.addExpense(
                groupId: groupId,
                title: title,
                amount: amount,
                payerId: payerId,
                splitMemberIds: splitMemberIds,
                note: note
            )
            // Reload full ledger stream to update balances and snapshots
            let response = try await GroupService.fetchGroupHistory(groupId: groupId)
            self.group = response.group
            self.events = response.events
            self.memberBalances = response.memberBalances
            self.isSubmitting = false
            return true
        } catch {
            self.errorMessage = "Failed to record expense: \(error.localizedDescription)"
            self.isSubmitting = false
            return false
        }
    }

    func addSettlement(
        payerId: UUID,
        payeeId: UUID,
        amount: Double,
        note: String? = nil
    ) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        do {
            _ = try await GroupService.addSettlement(
                groupId: groupId,
                payerId: payerId,
                payeeId: payeeId,
                amount: amount,
                note: note
            )
            // Reload full ledger stream to update balances and snapshots
            let response = try await GroupService.fetchGroupHistory(groupId: groupId)
            self.group = response.group
            self.events = response.events
            self.memberBalances = response.memberBalances
            self.isSubmitting = false
            return true
        } catch {
            self.errorMessage = "Failed to record settlement: \(error.localizedDescription)"
            self.isSubmitting = false
            return false
        }
    }
}
