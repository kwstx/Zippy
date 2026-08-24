import Vapor
import Fluent
import Foundation

struct SplitController {

    /// Generates a cryptographically random, URL-safe token.
    private static func generateSecureToken(byteCount: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            bytes[i] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Builds the short URL for a given share token.
    private static func makeShortURL(for token: String, req: Request) -> String {
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        return "\(baseURL)/s/\(token)"
    }

    /// Creates or updates a split session with server-computed balances.
    @Sendable
    func create(req: Request) async throws -> SplitSessionResponse {
        let input = try req.content.decode(CreateSplitRequest.self)

        // Load the receipt to get items, tax, tip
        guard let receipt = try await ExtractedReceipt.find(input.receiptId, on: req.db) else {
            throw Abort(.notFound, reason: "No receipt found with ID: \(input.receiptId)")
        }

        // Compute authoritative balances
        let balances = SplitCalculator.calculate(
            items: receipt.items,
            participants: input.participants,
            assignments: input.assignments,
            tax: receipt.tax,
            tip: receipt.tip
        )

        // Upsert: check for existing session for this receipt
        let session: SplitSession
        let token: String
        if let existing = try await SplitSession.query(on: req.db)
            .filter(\.$receiptId == input.receiptId)
            .first() {
            existing.participants = input.participants
            existing.assignments = input.assignments
            existing.balances = balances
            if existing.shareToken == nil {
                existing.shareToken = Self.generateSecureToken()
            }
            try await existing.update(on: req.db)
            session = existing
            token = existing.shareToken ?? Self.generateSecureToken()
        } else {
            let generatedToken = Self.generateSecureToken()
            let newSession = SplitSession(
                receiptId: input.receiptId,
                participants: input.participants,
                assignments: input.assignments,
                balances: balances,
                shareToken: generatedToken
            )
            try await newSession.save(on: req.db)
            session = newSession
            token = generatedToken
        }

        req.logger.info("Split session \(session.id?.uuidString ?? "?") saved for receipt \(input.receiptId) with token \(token)")

        return SplitSessionResponse(
            id: session.id!,
            receiptId: session.receiptId,
            participants: session.participants,
            balances: session.balances,
            receiptTotal: receipt.total,
            shareableURL: Self.makeShortURL(for: token, req: req),
            createdAt: session.createdAt
        )
    }

    /// Retrieves a previously saved split session by database ID.
    @Sendable
    func get(req: Request) async throws -> SplitSessionResponse {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid or missing split session ID.")
        }

        guard let session = try await SplitSession.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "No split session found with ID: \(id)")
        }

        // Load receipt for the total
        let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db)
        let token = session.shareToken ?? session.id!.uuidString
        let shareableURL = session.shareToken != nil
            ? Self.makeShortURL(for: token, req: req)
            : "/api/splits/\(session.id!.uuidString)"

        return SplitSessionResponse(
            id: session.id!,
            receiptId: session.receiptId,
            participants: session.participants,
            balances: session.balances,
            receiptTotal: receipt?.total ?? 0,
            shareableURL: shareableURL,
            createdAt: session.createdAt
        )
    }

    /// Retrieves a split session by token or renders the lightweight guest HTML page.
    @Sendable
    func getByToken(req: Request) async throws -> Response {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        guard let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db) else {
            throw Abort(.notFound, reason: "Receipt data missing for split session.")
        }

        let acceptHeader = req.headers.first(name: .accept) ?? ""
        let isJsonRequest = acceptHeader.contains("application/json") && !acceptHeader.contains("text/html")

        if isJsonRequest {
            let responseDTO = SplitSessionResponse(
                id: session.id!,
                receiptId: session.receiptId,
                participants: session.participants,
                balances: session.balances,
                receiptTotal: receipt.total,
                shareableURL: Self.makeShortURL(for: token, req: req),
                createdAt: session.createdAt
            )
            return try await responseDTO.encodeResponse(for: req)
        }

        // Render lightweight black-and-white minimalist Uber-aesthetic HTML page
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let html = GuestViewRenderer.render(
            session: session,
            receipt: receipt,
            token: token,
            baseURL: baseURL
        )

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Explicitly renders the guest HTML view.
    @Sendable
    func viewGuestHTML(req: Request) async throws -> Response {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        guard let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db) else {
            throw Abort(.notFound, reason: "Receipt data missing for split session.")
        }

        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let html = GuestViewRenderer.render(
            session: session,
            receipt: receipt,
            token: token,
            baseURL: baseURL
        )

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Builds deep links and instructions for external payment methods.
    private static func paymentDetails(
        method: String,
        amount: Double,
        participantName: String,
        token: String
    ) -> (deepLink: String?, instructions: String?) {
        let formattedAmount = String(format: "%.2f", amount)
        let reference = "ZIP-\(token.prefix(6).uppercased())"
        let note = "Zippy Bill Split - \(participantName) (\(reference))"
        let encodedNote = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? note

        switch method.lowercased() {
        case "venmo":
            let deepLink = "venmo://paycharge?txn=pay&amount=\(formattedAmount)&note=\(encodedNote)"
            let instructions = "Open Venmo to pay $\(formattedAmount). Settlement status will flip to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "paypal":
            let deepLink = "https://www.paypal.com/paypalme/zippysplit/\(formattedAmount)"
            let instructions = "Open PayPal to transfer $\(formattedAmount). Include reference \(reference) in note. Settlement flips to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "cash app", "cashapp", "cash_app":
            let deepLink = "https://cash.app/$zippysplit/\(formattedAmount)"
            let instructions = "Open Cash App to send $\(formattedAmount). Include note \(reference). Settlement flips to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "bank transfer", "bank_transfer", "ach", "wire":
            let instructions = """
            Direct Bank Transfer (ACH / Wire)
            Routing Number: 021000021
            Account Number: 9876543210
            Account Name: Zippy Split Host
            Reference Code: \(reference)
            Instructions: Include reference code in transfer memo. Settlement status flips upon bank webhook confirmation or manual confirmation.
            """
            return (nil, instructions)

        default:
            return (nil, "Payment method \(method) selected. Awaiting confirmation.")
        }
    }

    /// Records the chosen payment method and puts settlement status in pendingConfirmation.
    @Sendable
    func selectPaymentMethod(req: Request) async throws -> SelectPaymentMethodResponse {
        let token = req.parameters.get("token")
        let sessionId = req.parameters.get("id", as: UUID.self)
        let input = try req.content.decode(SelectPaymentMethodRequest.self)

        let session: SplitSession
        if let token = token {
            guard let found = try await SplitSession.query(on: req.db)
                .filter(\.$shareToken == token)
                .first() else {
                throw Abort(.notFound, reason: "No split session found for token: \(token)")
            }
            session = found
        } else if let sessionId = sessionId {
            guard let found = try await SplitSession.find(sessionId, on: req.db) else {
                throw Abort(.notFound, reason: "No split session found with ID: \(sessionId)")
            }
            session = found
        } else {
            throw Abort(.badRequest, reason: "Missing split token or session ID.")
        }

        guard let index = session.balances.firstIndex(where: { $0.participantId == input.participantId }) else {
            throw Abort(.notFound, reason: "Participant not found in this split session.")
        }

        var balance = session.balances[index]
        balance.paymentMethod = input.paymentMethod
        balance.settlementStatus = .pendingConfirmation
        balance.isPaid = false
        session.balances[index] = balance

        try await session.update(on: req.db)

        let tokenString = session.shareToken ?? session.id?.uuidString ?? "ZIPPY"
        let details = Self.paymentDetails(
            method: input.paymentMethod,
            amount: balance.total,
            participantName: balance.name,
            token: tokenString
        )

        req.logger.info("Recorded payment method \(input.paymentMethod) for \(balance.name), status pending confirmation")

        return SelectPaymentMethodResponse(
            success: true,
            participantId: balance.participantId,
            paymentMethod: input.paymentMethod,
            settlementStatus: .pendingConfirmation,
            deepLink: details.deepLink,
            instructions: details.instructions,
            message: "Payment method recorded. Awaiting webhook or manual confirmation."
        )
    }

    /// Manually confirms settlement to flip status from pendingConfirmation to settled.
    @Sendable
    func confirmSettlement(req: Request) async throws -> GuestPaymentResponse {
        let token = req.parameters.get("token")
        let sessionId = req.parameters.get("id", as: UUID.self)
        let input = try req.content.decode(ConfirmSettlementRequest.self)

        let session: SplitSession
        if let token = token {
            guard let found = try await SplitSession.query(on: req.db)
                .filter(\.$shareToken == token)
                .first() else {
                throw Abort(.notFound, reason: "No split session found for token: \(token)")
            }
            session = found
        } else if let sessionId = sessionId {
            guard let found = try await SplitSession.find(sessionId, on: req.db) else {
                throw Abort(.notFound, reason: "No split session found with ID: \(sessionId)")
            }
            session = found
        } else {
            throw Abort(.badRequest, reason: "Missing split token or session ID.")
        }

        guard let index = session.balances.firstIndex(where: { $0.participantId == input.participantId }) else {
            throw Abort(.notFound, reason: "Participant not found in this split session.")
        }

        var balance = session.balances[index]
        balance.isPaid = true
        balance.settlementStatus = .settled
        balance.paidAt = Date()
        if balance.paymentMethod == nil {
            balance.paymentMethod = "Manual Confirmation"
        }
        session.balances[index] = balance

        try await session.update(on: req.db)

        req.logger.info("Manual confirmation: \(balance.name) settlement confirmed (\(balance.paymentMethod ?? "Manual"))")

        return GuestPaymentResponse(
            success: true,
            participantId: balance.participantId,
            isPaid: true,
            settlementStatus: .settled,
            paidAt: balance.paidAt ?? Date(),
            totalPaid: balance.total,
            message: "Settlement confirmed for \(balance.name)"
        )
    }

    /// Webhook endpoint called by external payment providers to flip settlement status.
    @Sendable
    func handleWebhook(req: Request) async throws -> Response {
        let payload = try req.content.decode(PaymentWebhookPayload.self)

        var session: SplitSession?

        if let token = payload.shareToken {
            session = try await SplitSession.query(on: req.db)
                .filter(\.$shareToken == token)
                .first()
        } else if let sessionId = payload.sessionId {
            session = try await SplitSession.find(sessionId, on: req.db)
        } else if let participantId = payload.participantId {
            // Find any session containing this participant
            let allSessions = try await SplitSession.query(on: req.db).all()
            session = allSessions.first(where: { s in
                s.balances.contains(where: { $0.participantId == participantId })
            })
        }

        guard let splitSession = session else {
            throw Abort(.notFound, reason: "No split session matched webhook payload.")
        }

        guard let participantId = payload.participantId,
              let index = splitSession.balances.firstIndex(where: { $0.participantId == participantId }) else {
            throw Abort(.notFound, reason: "Participant not found in matching split session.")
        }

        var balance = splitSession.balances[index]
        balance.isPaid = true
        balance.settlementStatus = .settled
        balance.paidAt = Date()
        if let method = payload.paymentMethod {
            balance.paymentMethod = method
        }
        splitSession.balances[index] = balance

        try await splitSession.update(on: req.db)

        req.logger.info("Webhook processed: \(balance.name) settled via \(balance.paymentMethod ?? "Webhook")")

        struct WebhookAck: Content {
            let success: Bool
            let participantId: UUID
            let settlementStatus: SettlementStatus
            let message: String
        }

        let ack = WebhookAck(
            success: true,
            participantId: balance.participantId,
            settlementStatus: .settled,
            message: "Settlement status flipped to settled via webhook"
        )
        return try await ack.encodeResponse(for: req)
    }

    /// Handles unauthenticated guest payment / settlement.
    @Sendable
    func processGuestPayment(req: Request) async throws -> GuestPaymentResponse {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        let payment = try req.content.decode(GuestPaymentRequest.self)

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        guard let index = session.balances.firstIndex(where: { $0.participantId == payment.participantId }) else {
            throw Abort(.notFound, reason: "Participant not found in this split session.")
        }

        var balance = session.balances[index]
        balance.isPaid = true
        balance.settlementStatus = .settled
        balance.paidAt = Date()
        balance.paymentMethod = payment.paymentMethod
        session.balances[index] = balance

        try await session.update(on: req.db)

        req.logger.info("Guest payment recorded: \(balance.name) paid \(balance.total) via \(payment.paymentMethod)")

        return GuestPaymentResponse(
            success: true,
            participantId: balance.participantId,
            isPaid: true,
            settlementStatus: .settled,
            paidAt: balance.paidAt ?? Date(),
            totalPaid: balance.total,
            message: "Payment successfully recorded for \(balance.name)"
        )
    }

    /// Returns real-time status and payment progress for background polling.
    @Sendable
    func getStatus(req: Request) async throws -> SplitStatusResponse {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        let total = session.balances.reduce(0.0) { $0 + $1.total }
        let totalCollected = session.balances.filter(\.isPaid).reduce(0.0) { $0 + $1.total }
        let isFullySettled = !session.balances.isEmpty && session.balances.allSatisfy(\.isPaid)

        let participants = session.balances.map {
            SplitStatusResponse.ParticipantStatusDTO(
                id: $0.participantId,
                name: $0.name,
                total: $0.total,
                isPaid: $0.isPaid,
                settlementStatus: $0.settlementStatus,
                paidAt: $0.paidAt,
                paymentMethod: $0.paymentMethod
            )
        }

        return SplitStatusResponse(
            sessionId: session.id ?? UUID(),
            total: total,
            totalCollected: totalCollected,
            isFullySettled: isFullySettled,
            participants: participants
        )
    }
}
