// MARK: - PaymentStatusViewModel.swift

import SwiftUI
import Combine

/// Drives the pure white payment status screen with real-time status tracking,
/// background polling, and silent notification handling.
@MainActor
final class PaymentStatusViewModel: ObservableObject {
    @Published var participants: [ParticipantStatus] = []
    @Published var isFullySettled: Bool = false
    @Published var totalCollected: Double = 0.0
    @Published var totalDue: Double = 0.0
    @Published var currency: String = "USD"
    @Published var isLoading: Bool = false
    @Published var isTriggeringReminders: Bool = false
    @Published var reminderStatusMessage: String?
    @Published var errorMessage: String?

    let token: String?
    let sessionId: UUID?

    struct ParticipantStatus: Identifiable, Equatable {
        let id: UUID
        let name: String
        let total: Double
        let currency: String
        var isPaid: Bool
        var settlementStatus: SettlementStatus

        var isSettled: Bool {
            isPaid || settlementStatus == .settled
        }
    }

    init(token: String? = nil, sessionId: UUID? = nil, initialBalances: [PersonBalance] = []) {
        self.token = token
        self.sessionId = sessionId

        if !initialBalances.isEmpty {
            self.participants = initialBalances.map { b in
                ParticipantStatus(
                    id: b.participantId,
                    name: b.name,
                    total: b.total,
                    currency: b.currency,
                    isPaid: b.isPaid,
                    settlementStatus: b.settlementStatus
                )
            }
            self.currency = initialBalances.first?.currency ?? "USD"
            self.totalDue = initialBalances.reduce(0.0) { $0 + $1.total }
            self.totalCollected = initialBalances.filter { $0.isPaid || $0.settlementStatus == .settled }.reduce(0.0) { $0 + $1.total }
            self.isFullySettled = !initialBalances.isEmpty && initialBalances.allSatisfy { $0.isPaid || $0.settlementStatus == .settled }
        }
    }

    /// Fetches the latest live payment status from the backend.
    func refreshStatus() async {
        guard let token = token, !token.isEmpty else { return }

        do {
            let status = try await ReceiptService.fetchSplitStatus(token: token)
            self.participants = status.participants.map { p in
                ParticipantStatus(
                    id: p.id,
                    name: p.name,
                    total: p.total,
                    currency: p.currency,
                    isPaid: p.isPaid,
                    settlementStatus: p.settlementStatus
                )
            }
            self.totalDue = status.total
            self.totalCollected = status.totalCollected
            self.currency = status.currency
            self.isFullySettled = status.isFullySettled
        } catch {
            // Silently retain local state on polling drop
        }
    }

    /// Triggers an immediate backend reminder scan and silent notification / email dispatch.
    func triggerReminders() async {
        isTriggeringReminders = true
        reminderStatusMessage = nil
        errorMessage = nil

        do {
            let report: ReminderScanReport
            if let token = token, !token.isEmpty {
                report = try await ReceiptService.triggerSessionReminders(token: token)
            } else {
                report = try await ReceiptService.triggerReminderScan()
            }

            self.reminderStatusMessage = "Reminders sent: \(report.silentNotificationsPushed) silent push, \(report.emailsSent) emails."
            await refreshStatus()
        } catch {
            self.errorMessage = "Failed to dispatch reminders: \(error.localizedDescription)"
        }

        isTriggeringReminders = false
    }

    /// Handles incoming silent push notifications delivered to the app.
    func handleSilentPush(participantId: UUID, isSettled: Bool) {
        if let index = participants.firstIndex(where: { $0.id == participantId }) {
            participants[index].isPaid = isSettled
            participants[index].settlementStatus = isSettled ? .settled : .unpaid
            self.isFullySettled = !participants.isEmpty && participants.allSatisfy(\.isSettled)
        }
    }
}
