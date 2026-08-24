import Vapor
import Fluent
import Foundation

/// Persistent audit and cooldown log for payment reminders dispatched via silent notifications or emails.
final class PaymentReminderLog: Model, Content, @unchecked Sendable {
    static let schema = "payment_reminder_logs"

    @ID(key: .id)
    var id: UUID?

    /// Optional reference to SplitSession UUID
    @OptionalField(key: "split_session_id")
    var splitSessionId: UUID?

    /// Optional reference to PersistentGroup UUID
    @OptionalField(key: "group_id")
    var groupId: UUID?

    /// Target participant ID
    @Field(key: "participant_id")
    var participantId: UUID

    /// Participant name for reference
    @Field(key: "participant_name")
    var participantName: String

    /// Outstanding amount owed at reminder time
    @Field(key: "amount")
    var amount: Double

    /// Currency of the balance
    @Field(key: "currency")
    var currency: String

    /// Channel used: "silent_notification", "email", "apns"
    @Field(key: "channel")
    var channel: String

    /// Destination email or push token (if available)
    @OptionalField(key: "recipient_contact")
    var recipientContact: String?

    /// Status of the dispatch: "sent", "skipped_cooldown", "failed"
    @Field(key: "status")
    var status: String

    /// Detailed JSON payload / metadata associated with the reminder
    @OptionalField(key: "notification_payload")
    var notificationPayload: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        splitSessionId: UUID? = nil,
        groupId: UUID? = nil,
        participantId: UUID,
        participantName: String,
        amount: Double,
        currency: String = "USD",
        channel: String,
        recipientContact: String? = nil,
        status: String = "sent",
        notificationPayload: String? = nil
    ) {
        self.id = id
        self.splitSessionId = splitSessionId
        self.groupId = groupId
        self.participantId = participantId
        self.participantName = participantName
        self.amount = amount
        self.currency = currency
        self.channel = channel
        self.recipientContact = recipientContact
        self.status = status
        self.notificationPayload = notificationPayload
    }
}

/// DTO for returning reminder logs via API
struct PaymentReminderLogDTO: Content {
    let id: UUID
    let splitSessionId: UUID?
    let groupId: UUID?
    let participantId: UUID
    let participantName: String
    let amount: Double
    let currency: String
    let channel: String
    let recipientContact: String?
    let status: String
    let notificationPayload: String?
    let createdAt: Date?

    init(model: PaymentReminderLog) {
        self.id = model.id ?? UUID()
        self.splitSessionId = model.splitSessionId
        self.groupId = model.groupId
        self.participantId = model.participantId
        self.participantName = model.participantName
        self.amount = model.amount
        self.currency = model.currency
        self.channel = model.channel
        self.recipientContact = model.recipientContact
        self.status = model.status
        self.notificationPayload = model.notificationPayload
        self.createdAt = model.createdAt
    }
}

/// DTO for reminder scan response and scheduler status
struct ReminderScanReportDTO: Content {
    let success: Bool
    let totalSessionsScanned: Int
    let totalGroupsScanned: Int
    let totalUnsettledRecords: Int
    let silentNotificationsPushed: Int
    let emailsSent: Int
    let skippedDueToCooldown: Int
    let scannedAt: Date
    let message: String
}

struct ReminderSchedulerStatusDTO: Content {
    let isRunning: Bool
    let scanIntervalSeconds: Int
    let lastScanTime: Date?
    let totalLogsRecorded: Int
    let activeUnsettledParticipantsCount: Int
    let nextScheduledScanEstimate: Date?
}
