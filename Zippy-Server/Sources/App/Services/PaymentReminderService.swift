import Vapor
import Fluent
import Foundation

/// Core engine for scanning unsettled split sessions and group ledgers, tracking payment statuses,
/// and dispatching silent push notifications or reminder emails.
enum PaymentReminderService {

    /// Cooldown window in seconds before repeating a reminder to the same participant (default: 24 hours).
    static let defaultCooldownSeconds: TimeInterval = 24 * 3600

    /// Scans all unsettled SplitSessions and PersistentGroups in the database, evaluating cooldowns and pushing notifications/emails.
    static func scanAndDispatchReminders(
        db: Database,
        logger: Logger,
        cooldownSeconds: TimeInterval = defaultCooldownSeconds
    ) async throws -> ReminderScanReportDTO {
        let scanStartTime = Date()
        let cooldownCutoff = scanStartTime.addingTimeInterval(-cooldownSeconds)

        var totalSessionsScanned = 0
        var totalGroupsScanned = 0
        var totalUnsettledRecords = 0
        var silentNotificationsPushed = 0
        var emailsSent = 0
        var skippedDueToCooldown = 0

        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"

        // MARK: - 1. Scan Split Sessions
        let splitSessions = try await SplitSession.query(on: db).all()
        totalSessionsScanned = splitSessions.count

        for session in splitSessions {
            guard let sessionId = session.id else { continue }
            let token = session.shareToken ?? sessionId.uuidString
            let shareURL = "\(baseURL)/s/\(token)"

            for balance in session.balances {
                let isSettled = balance.isPaid || balance.settlementStatus == .settled
                guard !isSettled && balance.total > 0.01 else { continue }

                totalUnsettledRecords += 1

                // Check cooldown in PaymentReminderLog
                let recentLog = try await PaymentReminderLog.query(on: db)
                    .filter(\.$splitSessionId == sessionId)
                    .filter(\.$participantId == balance.participantId)
                    .filter(\.$createdAt >= cooldownCutoff)
                    .first()

                if recentLog != nil {
                    skippedDueToCooldown += 1
                    logger.debug("Skipping reminder for \(balance.name) in session \(sessionId) due to cooldown")
                    continue
                }

                // 1a. Dispatch Silent Push Notification
                let silentPayload = SilentPushNotificationPayload(
                    sessionId: sessionId,
                    sessionToken: token,
                    groupId: nil,
                    participantId: balance.participantId,
                    participantName: balance.name,
                    amountOwed: balance.total,
                    currency: balance.currency
                )

                let silentResult = await NotificationService.sendSilentNotification(
                    payload: silentPayload,
                    deviceToken: nil,
                    logger: logger
                )
                silentNotificationsPushed += 1

                // Log silent notification
                let silentLog = PaymentReminderLog(
                    splitSessionId: sessionId,
                    groupId: nil,
                    participantId: balance.participantId,
                    participantName: balance.name,
                    amount: balance.total,
                    currency: balance.currency,
                    channel: silentResult.channel,
                    recipientContact: "apns-silent",
                    status: silentResult.success ? "sent" : "failed",
                    notificationPayload: silentResult.payloadString
                )
                try await silentLog.save(on: db)

                // 1b. Dispatch Email Reminder if email address is configured / synthetic format
                let emailAddress = "\(balance.name.lowercased().filter { $0.isLetter || $0.isNumber })@example.com"
                let emailResult = await NotificationService.sendReminderEmail(
                    to: emailAddress,
                    participantName: balance.name,
                    amount: balance.total,
                    currency: balance.currency,
                    title: "Bill Split (\(token.prefix(6)))",
                    shareURL: shareURL,
                    logger: logger
                )
                emailsSent += 1

                let emailLog = PaymentReminderLog(
                    splitSessionId: sessionId,
                    groupId: nil,
                    participantId: balance.participantId,
                    participantName: balance.name,
                    amount: balance.total,
                    currency: balance.currency,
                    channel: emailResult.channel,
                    recipientContact: emailAddress,
                    status: emailResult.success ? "sent" : "failed",
                    notificationPayload: emailResult.payloadString
                )
                try await emailLog.save(on: db)
            }
        }

        // MARK: - 2. Scan Persistent Groups Ledger State
        let groups = try await PersistentGroup.query(on: db).all()
        totalGroupsScanned = groups.count

        for group in groups {
            guard let groupId = group.id else { continue }
            let groupCurrency = group.currency ?? "USD"

            let events = try await LedgerEvent.query(on: db)
                .filter(\.$groupId == groupId)
                .sort(\.$createdAt, .asc)
                .all()

            let state = GroupLedgerService.computeLedgerState(
                members: group.members,
                events: events,
                groupCurrency: groupCurrency
            )

            for member in state.memberBalancesDTO {
                // Negative net balance indicates member owes money to the group
                guard member.netBalance < -0.01 else { continue }

                let amountOwed = abs(member.netBalance)
                totalUnsettledRecords += 1

                // Check cooldown
                let recentLog = try await PaymentReminderLog.query(on: db)
                    .filter(\.$groupId == groupId)
                    .filter(\.$participantId == member.participantId)
                    .filter(\.$createdAt >= cooldownCutoff)
                    .first()

                if recentLog != nil {
                    skippedDueToCooldown += 1
                    continue
                }

                // Dispatch Silent Push
                let silentPayload = SilentPushNotificationPayload(
                    sessionId: nil,
                    sessionToken: nil,
                    groupId: groupId,
                    participantId: member.participantId,
                    participantName: member.name,
                    amountOwed: amountOwed,
                    currency: groupCurrency
                )

                let silentResult = await NotificationService.sendSilentNotification(
                    payload: silentPayload,
                    deviceToken: nil,
                    logger: logger
                )
                silentNotificationsPushed += 1

                let silentLog = PaymentReminderLog(
                    splitSessionId: nil,
                    groupId: groupId,
                    participantId: member.participantId,
                    participantName: member.name,
                    amount: amountOwed,
                    currency: groupCurrency,
                    channel: silentResult.channel,
                    recipientContact: "apns-silent",
                    status: silentResult.success ? "sent" : "failed",
                    notificationPayload: silentResult.payloadString
                )
                try await silentLog.save(on: db)

                // Dispatch Email
                let emailAddress = "\(member.name.lowercased().filter { $0.isLetter || $0.isNumber })@example.com"
                let emailResult = await NotificationService.sendReminderEmail(
                    to: emailAddress,
                    participantName: member.name,
                    amount: amountOwed,
                    currency: groupCurrency,
                    title: "Group '\(group.name)' Balance",
                    shareURL: "\(baseURL)/api/groups/\(groupId)/history",
                    logger: logger
                )
                emailsSent += 1

                let emailLog = PaymentReminderLog(
                    splitSessionId: nil,
                    groupId: groupId,
                    participantId: member.participantId,
                    participantName: member.name,
                    amount: amountOwed,
                    currency: groupCurrency,
                    channel: emailResult.channel,
                    recipientContact: emailAddress,
                    status: emailResult.success ? "sent" : "failed",
                    notificationPayload: emailResult.payloadString
                )
                try await emailLog.save(on: db)
            }
        }

        let message = "Scan completed: found \(totalUnsettledRecords) unsettled records across \(totalSessionsScanned) sessions and \(totalGroupsScanned) groups. Pushed \(silentNotificationsPushed) silent notifications and \(emailsSent) emails (skipped \(skippedDueToCooldown) on cooldown)."
        logger.info("[PAYMENT:REMINDERS] \(message)")

        return ReminderScanReportDTO(
            success: true,
            totalSessionsScanned: totalSessionsScanned,
            totalGroupsScanned: totalGroupsScanned,
            totalUnsettledRecords: totalUnsettledRecords,
            silentNotificationsPushed: silentNotificationsPushed,
            emailsSent: emailsSent,
            skippedDueToCooldown: skippedDueToCooldown,
            scannedAt: scanStartTime,
            message: message
        )
    }

    /// Computes summary statistics of currently unsettled records.
    static func getSchedulerStatus(app: Application) async throws -> ReminderSchedulerStatusDTO {
        let lastLog = try await PaymentReminderLog.query(on: app.db)
            .sort(\.$createdAt, .desc)
            .first()

        let totalLogs = try await PaymentReminderLog.query(on: app.db).count()

        let interval = Environment.get("REMINDER_SCAN_INTERVAL_SECONDS").flatMap(Int.init) ?? 3600
        let lastScanTime = lastLog?.createdAt
        let nextScan = lastScanTime?.addingTimeInterval(TimeInterval(interval))

        // Calculate count of currently unsettled participants across all sessions
        let sessions = try await SplitSession.query(on: app.db).all()
        var activeUnsettledCount = 0
        for session in sessions {
            for balance in session.balances {
                if !balance.isPaid && balance.settlementStatus != .settled && balance.total > 0.01 {
                    activeUnsettledCount += 1
                }
            }
        }

        return ReminderSchedulerStatusDTO(
            isRunning: true,
            scanIntervalSeconds: interval,
            lastScanTime: lastScanTime,
            totalLogsRecorded: totalLogs,
            activeUnsettledParticipantsCount: activeUnsettledCount,
            nextScheduledScanEstimate: nextScan
        )
    }
}
