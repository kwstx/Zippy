// MARK: - GroupLedgerViewModel.swift

import Foundation
import SwiftUI

@MainActor
final class GroupLedgerViewModel: ObservableObject {
    let groupId: UUID

    @Published var group: PersistentGroup?
    @Published var events: [LedgerEvent] = []
    @Published var memberBalances: [GroupMemberBalance] = []
    @Published var simplifiedTransfers: [SimplifiedPayment] = []
    @Published var simplifiedLines: [String] = []
    @Published var totalTransferred: Double = 0.0
    @Published var recurringTemplates: [RecurringExpenseTemplate] = []
    @Published var isLoading: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil

    var groupCurrency: String {
        group?.currency ?? "USD"
    }

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
                if let transfers = response.simplifiedTransfers {
                    self.simplifiedTransfers = transfers
                }
                if let lines = response.simplifiedLines {
                    self.simplifiedLines = lines
                } else if let transfers = response.simplifiedTransfers {
                    self.simplifiedLines = transfers.isEmpty
                        ? ["All balances are settled. No transfers needed."]
                        : transfers.map { $0.formattedText }
                }
                self.totalTransferred = response.totalTransferred ?? 0.0
                self.isLoading = false
            } catch {
                self.errorMessage = "Failed to load ledger history: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    /// Fetches the latest simplified payments calculated by the server's graph algorithm.
    func fetchSimplifiedPayments() async {
        do {
            let response = try await GroupService.fetchSimplifiedPayments(groupId: groupId)
            self.simplifiedTransfers = response.transfers
            self.simplifiedLines = response.lines
            self.totalTransferred = response.totalTransferred
        } catch {
            // Silently fallback if history is already loaded
        }
    }

    func addExpense(
        title: String,
        amount: Double,
        currency: String? = nil,
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        splits: [AddGroupExpensePayload.LedgerSplitPayload]? = nil,
        note: String? = nil
    ) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        let targetCur = groupCurrency
        let expCurrency = currency ?? targetCur

        do {
            _ = try await GroupService.addExpense(
                groupId: groupId,
                title: title,
                amount: amount,
                currency: expCurrency,
                targetCurrency: targetCur,
                payerId: payerId,
                splitMemberIds: splitMemberIds,
                splits: splits,
                note: note
            )
            // Reload full ledger stream to update balances, snapshots, and simplified transfers
            let response = try await GroupService.fetchGroupHistory(groupId: groupId)
            self.group = response.group
            self.events = response.events
            self.memberBalances = response.memberBalances
            if let transfers = response.simplifiedTransfers {
                self.simplifiedTransfers = transfers
            }
            if let lines = response.simplifiedLines {
                self.simplifiedLines = lines
            } else if let transfers = response.simplifiedTransfers {
                self.simplifiedLines = transfers.isEmpty
                    ? ["All balances are settled. No transfers needed."]
                    : transfers.map { $0.formattedText }
            }
            self.totalTransferred = response.totalTransferred ?? 0.0
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
        currency: String? = nil,
        note: String? = nil
    ) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        let targetCur = groupCurrency
        let setCurrency = currency ?? targetCur

        do {
            _ = try await GroupService.addSettlement(
                groupId: groupId,
                payerId: payerId,
                payeeId: payeeId,
                amount: amount,
                currency: setCurrency,
                targetCurrency: targetCur,
                note: note
            )
            // Reload full ledger stream to update balances, snapshots, and simplified transfers
            let response = try await GroupService.fetchGroupHistory(groupId: groupId)
            self.group = response.group
            self.events = response.events
            self.memberBalances = response.memberBalances
            if let transfers = response.simplifiedTransfers {
                self.simplifiedTransfers = transfers
            }
            if let lines = response.simplifiedLines {
                self.simplifiedLines = lines
            } else if let transfers = response.simplifiedTransfers {
                self.simplifiedLines = transfers.isEmpty
                    ? ["All balances are settled. No transfers needed."]
                    : transfers.map { $0.formattedText }
            }
            self.totalTransferred = response.totalTransferred ?? 0.0
            self.isSubmitting = false
            return true
        } catch {
            self.errorMessage = "Failed to record settlement: \(error.localizedDescription)"
            self.isSubmitting = false
            return false
        }
    }

    // MARK: - Recurring Expenses

    /// Loads all recurring expense templates configured for this group.
    func loadRecurringTemplates() {
        Task {
            do {
                let templates = try await GroupService.fetchRecurringExpenses(groupId: groupId)
                self.recurringTemplates = templates
            } catch {
                // Silently keep current templates or update message
            }
        }
    }

    /// Stores a new recurring expense template on the backend.
    func addRecurringExpense(
        title: String,
        amount: Double,
        currency: String? = nil,
        payerId: UUID,
        splitMemberIds: [UUID]? = nil,
        frequency: RecurringFrequency = .monthly,
        note: String? = nil,
        startDate: Date? = nil
    ) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        let targetCur = groupCurrency
        let expCurrency = currency ?? targetCur

        do {
            _ = try await GroupService.createRecurringExpense(
                groupId: groupId,
                title: title,
                amount: amount,
                currency: expCurrency,
                payerId: payerId,
                splitMemberIds: splitMemberIds,
                frequency: frequency,
                note: note,
                startDate: startDate
            )

            // Refresh templates and reload history (in case an immediate occurrence was cloned)
            loadRecurringTemplates()
            loadHistory()

            self.isSubmitting = false
            return true
        } catch {
            self.errorMessage = "Failed to create recurring template: \(error.localizedDescription)"
            self.isSubmitting = false
            return false
        }
    }

    /// Toggles active state of a recurring template.
    func toggleRecurringExpense(templateId: UUID) async {
        do {
            let updated = try await GroupService.toggleRecurringExpense(groupId: groupId, templateId: templateId)
            if let index = recurringTemplates.firstIndex(where: { $0.id == templateId }) {
                recurringTemplates[index] = updated
            }
        } catch {
            self.errorMessage = "Failed to toggle recurring template: \(error.localizedDescription)"
        }
    }

    /// Deletes a recurring expense template.
    func deleteRecurringExpense(templateId: UUID) async {
        do {
            try await GroupService.deleteRecurringExpense(groupId: groupId, templateId: templateId)
            recurringTemplates.removeAll { $0.id == templateId }
        } catch {
            self.errorMessage = "Failed to delete recurring template: \(error.localizedDescription)"
        }
    }

    /// Triggers immediate cron-like cloning evaluation on the backend.
    func processRecurringCronJob() async -> Int {
        do {
            let response = try await GroupService.processRecurringExpenses(groupId: groupId)
            loadRecurringTemplates()
            loadHistory()
            return response.generatedEventsCount
        } catch {
            self.errorMessage = "Failed to run cron job: \(error.localizedDescription)"
            return 0
        }
    }
}
