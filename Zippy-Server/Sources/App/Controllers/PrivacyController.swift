import Vapor
import Fluent
import Foundation

/// Controller handling privacy and data controls and deletion endpoints.
/// Every handler reads user identity from `X-User-Id` / `X-Device-Id` headers
/// (matching the pattern used by `SubscriptionController` and `GroupController`).
struct PrivacyController {

    // MARK: - DTOs

    /// Privacy and data control toggle preferences.
    struct PrivacyControlsDTO: Content {
        var storeReceiptImages: Bool
        var retainReceiptHistory: Bool
        var retainSplitSessions: Bool
        var retainGroupLedgers: Bool
        var allowAutomatedReminders: Bool
        var telemetryAndAnalytics: Bool
    }

    /// Request payload for patching privacy controls.
    struct PatchPrivacyControlsRequest: Content {
        var storeReceiptImages: Bool?
        var retainReceiptHistory: Bool?
        var retainSplitSessions: Bool?
        var retainGroupLedgers: Bool?
        var allowAutomatedReminders: Bool?
        var telemetryAndAnalytics: Bool?
    }

    /// Returned by every privacy deletion and patch endpoint.
    struct PrivacyActionResponse: Content {
        let success: Bool
        let controls: PrivacyControlsDTO?
        let deletedCounts: [String: Int]
        let message: String
    }

    // In-memory / persistent control state key
    struct PrivacyStorageKey: StorageKey {
        typealias Value = [String: PrivacyControlsDTO]
    }

    private func getControls(for userId: String, on app: Application) -> PrivacyControlsDTO {
        let state = app.storage[PrivacyStorageKey.self] ?? [:]
        return state[userId] ?? PrivacyControlsDTO(
            storeReceiptImages: true,
            retainReceiptHistory: true,
            retainSplitSessions: true,
            retainGroupLedgers: true,
            allowAutomatedReminders: true,
            telemetryAndAnalytics: false
        )
    }

    private func saveControls(_ controls: PrivacyControlsDTO, for userId: String, on app: Application) {
        var state = app.storage[PrivacyStorageKey.self] ?? [:]
        state[userId] = controls
        app.storage[PrivacyStorageKey.self] = state
    }

    // MARK: - GET Controls

    @Sendable
    func getControls(req: Request) async throws -> PrivacyControlsDTO {
        let userId = req.headers.first(name: "X-User-Id")
            ?? req.headers.first(name: "X-Device-Id")
            ?? "default_user"
        return getControls(for: userId, on: req.application)
    }

    // MARK: - PATCH Controls

    /// Authenticated PATCH that updates privacy toggles and immediately permanently purges associated
    /// object-storage files and records if toggled off.
    @Sendable
    func patchControls(req: Request) async throws -> PrivacyActionResponse {
        let userId = req.headers.first(name: "X-User-Id")
            ?? req.headers.first(name: "X-Device-Id")
            ?? "default_user"

        let input = try req.content.decode(PatchPrivacyControlsRequest.self)
        var current = getControls(for: userId, on: req.application)
        var deletedCounts: [String: Int] = [:]
        var actionsTaken: [String] = []

        // 1. If storeReceiptImages toggled to false, permanently purge object-storage images
        if let storeImages = input.storeReceiptImages {
            current.storeReceiptImages = storeImages
            if !storeImages {
                let purged = try await purgeReceiptImagesFromStorage(on: req)
                deletedCounts["purgedImageFiles"] = purged
                actionsTaken.append("purged \(purged) object-storage receipt image files")
            }
        }

        // 2. If retainReceiptHistory toggled to false, purge all receipts + image files
        if let retainReceipts = input.retainReceiptHistory {
            current.retainReceiptHistory = retainReceipts
            if !retainReceipts {
                let receiptResult = try await deleteReceiptsInternal(on: req)
                for (k, v) in receiptResult { deletedCounts[k] = v }
                actionsTaken.append("purged receipt history")
            }
        }

        // 3. If retainSplitSessions toggled to false, purge splits
        if let retainSplits = input.retainSplitSessions {
            current.retainSplitSessions = retainSplits
            if !retainSplits {
                let splitCount = try await deleteSplitsInternal(on: req)
                deletedCounts["splits"] = splitCount
                actionsTaken.append("purged split sessions")
            }
        }

        // 4. If retainGroupLedgers toggled to false, purge groups & ledger
        if let retainGroups = input.retainGroupLedgers {
            current.retainGroupLedgers = retainGroups
            if !retainGroups {
                let groupResult = try await deleteGroupsInternal(on: req)
                for (k, v) in groupResult { deletedCounts[k] = v }
                actionsTaken.append("purged group ledgers")
            }
        }

        // 5. If allowAutomatedReminders toggled to false, purge reminder logs
        if let allowReminders = input.allowAutomatedReminders {
            current.allowAutomatedReminders = allowReminders
            if !allowReminders {
                let remCount = try await deleteRemindersInternal(on: req)
                deletedCounts["reminderLogs"] = remCount
                actionsTaken.append("purged reminder logs")
            }
        }

        if let analytics = input.telemetryAndAnalytics {
            current.telemetryAndAnalytics = analytics
        }

        saveControls(current, for: userId, on: req.application)

        let msg = actionsTaken.isEmpty
            ? "Privacy controls updated."
            : "Privacy controls updated; permanently " + actionsTaken.joined(separator: ", ") + "."

        req.logger.info("Privacy PATCH for user \(userId): \(msg)")

        return PrivacyActionResponse(
            success: true,
            controls: current,
            deletedCounts: deletedCounts,
            message: msg
        )
    }

    // MARK: - Delete Handlers

    /// Permanently deletes all extracted receipts and their on-disk image files.
    @Sendable
    func deleteReceipts(req: Request) async throws -> PrivacyActionResponse {
        let counts = try await deleteReceiptsInternal(on: req)
        let rCount = counts["receipts"] ?? 0
        let fCount = counts["files"] ?? 0
        return PrivacyActionResponse(
            success: true,
            controls: nil,
            deletedCounts: counts,
            message: "Permanently deleted \(rCount) receipt(s) and \(fCount) image file(s)."
        )
    }

    /// Permanently deletes all split sessions.
    @Sendable
    func deleteSplits(req: Request) async throws -> PrivacyActionResponse {
        let count = try await deleteSplitsInternal(on: req)
        return PrivacyActionResponse(
            success: true,
            controls: nil,
            deletedCounts: ["splits": count],
            message: "Permanently deleted \(count) split session(s)."
        )
    }

    /// Permanently deletes all groups, cascading ledger events and recurring templates.
    @Sendable
    func deleteGroups(req: Request) async throws -> PrivacyActionResponse {
        let counts = try await deleteGroupsInternal(on: req)
        let gCount = counts["groups"] ?? 0
        let eCount = counts["ledgerEvents"] ?? 0
        return PrivacyActionResponse(
            success: true,
            controls: nil,
            deletedCounts: counts,
            message: "Permanently deleted \(gCount) group(s), \(eCount) ledger event(s)."
        )
    }

    /// Permanently deletes all payment reminder logs.
    @Sendable
    func deleteReminders(req: Request) async throws -> PrivacyActionResponse {
        let count = try await deleteRemindersInternal(on: req)
        return PrivacyActionResponse(
            success: true,
            controls: nil,
            deletedCounts: ["reminderLogs": count],
            message: "Permanently deleted \(count) reminder log(s)."
        )
    }

    /// Nuclear option: deletes all receipts, object-storage images, splits, groups, reminders, and subscription records.
    @Sendable
    func deleteAllData(req: Request) async throws -> PrivacyActionResponse {
        let userId = req.headers.first(name: "X-User-Id")
            ?? req.headers.first(name: "X-Device-Id")
            ?? "default_user"

        var allCounts: [String: Int] = [:]

        // 1. Receipts + object storage images
        let rCounts = try await deleteReceiptsInternal(on: req)
        for (k, v) in rCounts { allCounts[k] = v }

        // 2. Splits
        let sCount = try await deleteSplitsInternal(on: req)
        allCounts["splits"] = sCount

        // 3. Groups (cascading)
        let gCounts = try await deleteGroupsInternal(on: req)
        for (k, v) in gCounts { allCounts[k] = v }

        // 4. Reminders
        let remCount = try await deleteRemindersInternal(on: req)
        allCounts["reminderLogs"] = remCount

        // 5. Subscription records
        let subCount = try await SubscriptionRecord.query(on: req.db).count()
        try await SubscriptionRecord.query(on: req.db).delete()
        allCounts["subscriptionRecords"] = subCount

        // 6. Reset privacy controls
        saveControls(
            PrivacyControlsDTO(
                storeReceiptImages: false,
                retainReceiptHistory: false,
                retainSplitSessions: false,
                retainGroupLedgers: false,
                allowAutomatedReminders: false,
                telemetryAndAnalytics: false
            ),
            for: userId,
            on: req.application
        )

        let totalDeleted = allCounts.values.reduce(0, +)
        req.logger.info("Privacy: FULL ACCOUNT WIPE completed for \(userId). \(totalDeleted) total records deleted.")

        return PrivacyActionResponse(
            success: true,
            controls: getControls(for: userId, on: req.application),
            deletedCounts: allCounts,
            message: "Full account wipe complete. All database records and object-storage files have been permanently removed."
        )
    }

    // MARK: - Internal Helpers

    private func purgeReceiptImagesFromStorage(on req: Request) async throws -> Int {
        let storageDir = req.application.storage[ReceiptStorageKey.self] ?? "./Storage/Receipts/"
        let fm = FileManager.default
        var filesDeleted = 0

        let receipts = try await ExtractedReceipt.query(on: req.db).all()
        for receipt in receipts {
            let filePath = URL(fileURLWithPath: storageDir)
                .appendingPathComponent("\(receipt.referenceId).jpg").path
            if fm.fileExists(atPath: filePath) {
                try? fm.removeItem(atPath: filePath)
                filesDeleted += 1
            }
        }

        // Also sweep directory for any orphaned receipt files
        if let files = try? fm.contentsOfDirectory(atPath: storageDir) {
            for file in files where file.hasSuffix(".jpg") || file.hasSuffix(".png") || file.hasSuffix(".jpeg") {
                let p = URL(fileURLWithPath: storageDir).appendingPathComponent(file).path
                try? fm.removeItem(atPath: p)
                filesDeleted += 1
            }
        }

        return filesDeleted
    }

    private func deleteReceiptsInternal(on req: Request) async throws -> [String: Int] {
        let receipts = try await ExtractedReceipt.query(on: req.db).all()
        let count = receipts.count
        let filesDeleted = try await purgeReceiptImagesFromStorage(on: req)
        try await ExtractedReceipt.query(on: req.db).delete()
        return ["receipts": count, "files": filesDeleted]
    }

    private func deleteSplitsInternal(on req: Request) async throws -> Int {
        let count = try await SplitSession.query(on: req.db).count()
        try await SplitSession.query(on: req.db).delete()
        return count
    }

    private func deleteGroupsInternal(on req: Request) async throws -> [String: Int] {
        let groups = try await PersistentGroup.query(on: req.db).all()
        let groupCount = groups.count
        var eventsDeleted = 0
        var templatesDeleted = 0

        for group in groups {
            guard let groupId = group.id else { continue }
            let eventCount = try await LedgerEvent.query(on: req.db).filter(\.$groupId == groupId).count()
            try await LedgerEvent.query(on: req.db).filter(\.$groupId == groupId).delete()
            eventsDeleted += eventCount

            let templateCount = try await RecurringExpenseTemplate.query(on: req.db).filter(\.$groupId == groupId).count()
            try await RecurringExpenseTemplate.query(on: req.db).filter(\.$groupId == groupId).delete()
            templatesDeleted += templateCount
        }

        try await PersistentGroup.query(on: req.db).delete()
        return [
            "groups": groupCount,
            "ledgerEvents": eventsDeleted,
            "recurringTemplates": templatesDeleted
        ]
    }

    private func deleteRemindersInternal(on req: Request) async throws -> Int {
        let count = try await PaymentReminderLog.query(on: req.db).count()
        try await PaymentReminderLog.query(on: req.db).delete()
        return count
    }
}
