import Vapor
import Fluent
import Foundation

/// API Controller for managing payment status tracking, reminder scan jobs, and dispatch history.
struct ReminderController {

    /// Triggers an immediate scan of all unsettled records and dispatches silent push / email reminders.
    @Sendable
    func scan(req: Request) async throws -> ReminderScanReportDTO {
        let cooldownSeconds = (try? req.query.get(Double.self, at: "cooldown")) ?? PaymentReminderService.defaultCooldownSeconds
        return try await PaymentReminderService.scanAndDispatchReminders(
            db: req.db,
            logger: req.logger,
            cooldownSeconds: cooldownSeconds
        )
    }

    /// Returns the live status and metrics of the payment reminder scheduler.
    @Sendable
    func getStatus(req: Request) async throws -> ReminderSchedulerStatusDTO {
        return try await PaymentReminderService.getSchedulerStatus(app: req.application)
    }

    /// Lists past reminder dispatch logs.
    @Sendable
    func listLogs(req: Request) async throws -> [PaymentReminderLogDTO] {
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 50
        let logs = try await PaymentReminderLog.query(on: req.db)
            .sort(\.$createdAt, .desc)
            .range(0..<limit)
            .all()

        return logs.map(PaymentReminderLogDTO.init)
    }

    /// Triggers immediate reminders for a single split session token.
    @Sendable
    func triggerSessionReminders(req: Request) async throws -> ReminderScanReportDTO {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing session token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found with token: \(token)")
        }

        let sessionId = session.id ?? UUID()
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let shareURL = "\(baseURL)/s/\(token)"

        var silentCount = 0
        var emailCount = 0
        var unsettledCount = 0

        for balance in session.balances {
            let isSettled = balance.isPaid || balance.settlementStatus == .settled
            guard !isSettled && balance.total > 0.01 else { continue }
            unsettledCount += 1

            // 1. Silent Notification
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
                logger: req.logger
            )
            silentCount += 1

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
            try await silentLog.save(on: req.db)

            // 2. Email Reminder
            let emailAddress = "\(balance.name.lowercased().filter { $0.isLetter || $0.isNumber })@example.com"
            let emailResult = await NotificationService.sendReminderEmail(
                to: emailAddress,
                participantName: balance.name,
                amount: balance.total,
                currency: balance.currency,
                title: "Bill Split (\(token.prefix(6)))",
                shareURL: shareURL,
                logger: req.logger
            )
            emailCount += 1

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
            try await emailLog.save(on: req.db)
        }

        return ReminderScanReportDTO(
            success: true,
            totalSessionsScanned: 1,
            totalGroupsScanned: 0,
            totalUnsettledRecords: unsettledCount,
            silentNotificationsPushed: silentCount,
            emailsSent: emailCount,
            skippedDueToCooldown: 0,
            scannedAt: Date(),
            message: "Dispatched \(silentCount) silent notifications and \(emailCount) emails for session \(token)"
        )
    }
}
