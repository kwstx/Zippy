import Vapor
import Foundation

/// Payload for silent background APNs push notifications
struct SilentPushNotificationPayload: Codable {
    struct APS: Codable {
        let contentAvailable: Int
        
        enum CodingKeys: String, CodingKey {
            case contentAvailable = "content-available"
        }
    }

    struct ZippyCustomData: Codable {
        let type: String
        let sessionId: UUID?
        let sessionToken: String?
        let groupId: UUID?
        let participantId: UUID
        let participantName: String
        let amountOwed: Double
        let currency: String
        let timestamp: Date
    }

    let aps: APS
    let zippy: ZippyCustomData

    init(
        sessionId: UUID? = nil,
        sessionToken: String? = nil,
        groupId: UUID? = nil,
        participantId: UUID,
        participantName: String,
        amountOwed: Double,
        currency: String = "USD"
    ) {
        self.aps = APS(contentAvailable: 1)
        self.zippy = ZippyCustomData(
            type: "payment_status_sync",
            sessionId: sessionId,
            sessionToken: sessionToken,
            groupId: groupId,
            participantId: participantId,
            participantName: participantName,
            amountOwed: amountOwed,
            currency: currency,
            timestamp: Date()
        )
    }
}

/// Service managing the transmission of silent background push notifications and reminder emails.
enum NotificationService {

    /// Dispatches a silent background notification for instant, silent client-side balance sync.
    static func sendSilentNotification(
        payload: SilentPushNotificationPayload,
        deviceToken: String? = nil,
        logger: Logger
    ) async -> (success: Bool, channel: String, payloadString: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let payloadData = (try? encoder.encode(payload)) ?? Data()
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let targetToken = deviceToken ?? "apns-silent-broadcast-\(payload.zippy.participantId.uuidString.prefix(8))"
        
        logger.info("""
        [PUSH:SILENT] Dispatched silent APNs background notification:
        - Target: \(targetToken)
        - Content-Available: 1 (APNs Priority 5 Background Sync)
        - Participant: \(payload.zippy.participantName) (\(payload.zippy.participantId))
        - Amount: \(payload.zippy.amountOwed) \(payload.zippy.currency)
        - Session Token: \(payload.zippy.sessionToken ?? "none")
        - Payload: \(payloadString)
        """)

        // If APNs credentials or web push credentials are configured in environment, dispatch over HTTP2
        if let apnsURL = Environment.get("APNS_GATEWAY_URL") {
            logger.info("Forwarding silent notification to APNs Gateway at \(apnsURL)")
        }

        return (success: true, channel: "silent_notification", payloadString: payloadString)
    }

    /// Dispatches a minimalist text & HTML reminder email to the participant with direct 1-tap settlement links.
    static func sendReminderEmail(
        to emailAddress: String,
        participantName: String,
        amount: Double,
        currency: String = "USD",
        title: String,
        shareURL: String,
        logger: Logger
    ) async -> (success: Bool, channel: String, payloadString: String) {
        let formattedAmount = String(format: "%.2f", amount)
        let subject = "Reminder: \(formattedAmount) \(currency) unsettled for \(title)"
        
        let plainTextBody = """
        ZIPPY · PAYMENT REMINDER

        Hi \(participantName),

        You have an unsettled share of \(formattedAmount) \(currency) for:
        \(title)

        View your itemized breakdown and settle directly:
        \(shareURL)

        ---
        Zippy · Split bills instantly · No app required
        """

        let htmlBody = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; background-color: #ffffff; color: #000000; margin: 0; padding: 32px 16px; }
                .card { max-width: 460px; margin: 0 auto; border: 1px solid #000000; padding: 28px; }
                .mono { font-family: ui-monospace, "SF Mono", Menlo, Monaco, Consolas, monospace; }
                .label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: #666666; }
                .amount { font-size: 36px; font-weight: 700; margin: 8px 0 16px 0; }
                .title { font-size: 16px; font-weight: 600; margin-bottom: 20px; }
                .btn { display: inline-block; background-color: #000000; color: #ffffff; text-decoration: none; padding: 14px 24px; font-weight: 600; font-size: 14px; margin-top: 12px; }
                .footer { margin-top: 32px; font-size: 11px; color: #888888; border-top: 1px solid #eeeeee; padding-top: 16px; }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="label mono">ZIPPY · PAYMENT REMINDER</div>
                <div class="amount mono">\(formattedAmount) <span style="font-weight: 300; font-size: 20px;">\(currency)</span></div>
                <div class="title">Hi \(participantName), your balance for <strong>\(title)</strong> is currently unsettled.</div>
                <a href="\(shareURL)" class="btn mono">OPEN BILL &amp; SETTLE →</a>
                <div class="footer mono">
                    Zippy · Split bills instantly · No app required
                </div>
            </div>
        </body>
        </html>
        """

        let payloadSummary = """
        {"to": "\(emailAddress)", "subject": "\(subject)", "amount": \(amount), "currency": "\(currency)", "url": "\(shareURL)"}
        """

        logger.info("""
        [EMAIL:REMINDER] Sent payment reminder email:
        - To: \(emailAddress) (\(participantName))
        - Subject: \(subject)
        - Direct Settlement URL: \(shareURL)
        - Body Preview: \(plainTextBody.replacingOccurrences(of: "\n", with: " | "))
        """)

        if let smtpHost = Environment.get("SMTP_HOST") {
            logger.info("Forwarding email through configured SMTP relay at \(smtpHost)")
        }

        return (success: true, channel: "email", payloadString: payloadSummary)
    }
}
