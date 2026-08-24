// MARK: - PrivacySettingsViewModel.swift

import Foundation
import SwiftUI

/// View model powering the Privacy & Data settings screen.
/// Manages plain text toggles with PATCH sync and permanent purging of object-storage files,
/// as well as the destructive "Delete all data" action.
@MainActor
final class PrivacySettingsViewModel: ObservableObject {

    // MARK: - Published Toggle States

    @Published var storeReceiptImages: Bool = true
    @Published var retainReceiptHistory: Bool = true
    @Published var retainSplitSessions: Bool = true
    @Published var retainGroupLedgers: Bool = true
    @Published var allowAutomatedReminders: Bool = true
    @Published var telemetryAndAnalytics: Bool = false

    // MARK: - Operational State

    @Published var isLoading: Bool = false
    @Published var isProcessing: Bool = false
    @Published var statusMessage: String? = nil
    @Published var statusIsError: Bool = false

    // MARK: - Confirmation States

    @Published var showDeleteAllConfirmation: Bool = false
    @Published var showToggleOffConfirmation: Bool = false
    @Published var pendingToggleTarget: ToggleKey? = nil

    enum ToggleKey: String {
        case storeReceiptImages = "Store receipt image files"
        case retainReceiptHistory = "Retain receipt history"
        case retainSplitSessions = "Retain split sessions"
        case retainGroupLedgers = "Retain group ledgers"
        case allowAutomatedReminders = "Automated reminders"
        case telemetryAndAnalytics = "Telemetry & analytics"

        var warningMessage: String {
            switch self {
            case .storeReceiptImages:
                return "Disabling this will immediately and permanently delete all stored receipt image files from object storage. Extracted text will remain. Continue?"
            case .retainReceiptHistory:
                return "Disabling this will immediately and permanently delete all receipts and their stored image files. Continue?"
            case .retainSplitSessions:
                return "Disabling this will immediately and permanently delete all split sessions. Continue?"
            case .retainGroupLedgers:
                return "Disabling this will immediately and permanently delete all persistent groups and ledger events. Continue?"
            case .allowAutomatedReminders:
                return "Disabling this will delete reminder logs and prevent automatic notifications. Continue?"
            case .telemetryAndAnalytics:
                return "Disable anonymous usage telemetry?"
            }
        }
    }

    // MARK: - Init & Load

    init() {
        Task {
            await loadControls()
        }
    }

    func loadControls() async {
        isLoading = true
        do {
            let controls = try await PrivacyService.fetchControls()
            self.storeReceiptImages = controls.storeReceiptImages
            self.retainReceiptHistory = controls.retainReceiptHistory
            self.retainSplitSessions = controls.retainSplitSessions
            self.retainGroupLedgers = controls.retainGroupLedgers
            self.allowAutomatedReminders = controls.allowAutomatedReminders
            self.telemetryAndAnalytics = controls.telemetryAndAnalytics
        } catch {
            print("[PrivacySettingsViewModel] Failed to load controls: \(error)")
        }
        isLoading = false
    }

    // MARK: - Toggle Action Handling

    func handleToggleChange(for key: ToggleKey, newValue: Bool) {
        // If turning OFF a destructive data storage toggle, confirm first
        if !newValue && (key == .storeReceiptImages || key == .retainReceiptHistory || key == .retainSplitSessions || key == .retainGroupLedgers) {
            // Revert state temporarily until confirmed
            revertToggle(for: key, to: true)
            pendingToggleTarget = key
            showToggleOffConfirmation = true
            return
        }

        // Apply immediately
        applyToggle(for: key, value: newValue)
        Task {
            await syncToggleToBackend(for: key, value: newValue)
        }
    }

    func confirmToggleOff() {
        guard let key = pendingToggleTarget else { return }
        pendingToggleTarget = nil
        applyToggle(for: key, value: false)

        Task {
            await syncToggleToBackend(for: key, value: false)
        }
    }

    func cancelToggleOff() {
        guard let key = pendingToggleTarget else { return }
        pendingToggleTarget = nil
        revertToggle(for: key, to: true)
    }

    private func applyToggle(for key: ToggleKey, value: Bool) {
        switch key {
        case .storeReceiptImages: self.storeReceiptImages = value
        case .retainReceiptHistory: self.retainReceiptHistory = value
        case .retainSplitSessions: self.retainSplitSessions = value
        case .retainGroupLedgers: self.retainGroupLedgers = value
        case .allowAutomatedReminders: self.allowAutomatedReminders = value
        case .telemetryAndAnalytics: self.telemetryAndAnalytics = value
        }
    }

    private func revertToggle(for key: ToggleKey, to value: Bool) {
        applyToggle(for: key, value: value)
    }

    private func syncToggleToBackend(for key: ToggleKey, value: Bool) async {
        isProcessing = true
        statusMessage = nil
        statusIsError = false

        var payload = PrivacyService.PatchPrivacyControlsPayload()
        switch key {
        case .storeReceiptImages: payload.storeReceiptImages = value
        case .retainReceiptHistory: payload.retainReceiptHistory = value
        case .retainSplitSessions: payload.retainSplitSessions = value
        case .retainGroupLedgers: payload.retainGroupLedgers = value
        case .allowAutomatedReminders: payload.allowAutomatedReminders = value
        case .telemetryAndAnalytics: payload.telemetryAndAnalytics = value
        }

        do {
            let response = try await PrivacyService.patchControls(payload)
            statusMessage = response.message
            statusIsError = false
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
            statusIsError = true
            // Revert local state on error
            revertToggle(for: key, to: !value)
        }

        isProcessing = false
    }

    // MARK: - Delete All Data

    func requestDeleteAllData() {
        showDeleteAllConfirmation = true
    }

    func confirmDeleteAllData() {
        Task {
            await executeDeleteAll()
        }
    }

    private func executeDeleteAll() async {
        isProcessing = true
        statusMessage = nil
        statusIsError = false

        do {
            let response = try await PrivacyService.deleteAllData()
            statusMessage = response.message
            statusIsError = false

            // Reflect in UI toggles
            self.storeReceiptImages = false
            self.retainReceiptHistory = false
            self.retainSplitSessions = false
            self.retainGroupLedgers = false
            self.allowAutomatedReminders = false
            self.telemetryAndAnalytics = false
        } catch {
            statusMessage = "Delete all failed: \(error.localizedDescription)"
            statusIsError = true
        }

        isProcessing = false
    }
}
