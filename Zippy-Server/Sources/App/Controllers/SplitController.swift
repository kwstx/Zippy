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
        balance.paidAt = Date()
        balance.paymentMethod = payment.paymentMethod
        session.balances[index] = balance

        try await session.update(on: req.db)

        req.logger.info("Guest payment recorded: \(balance.name) paid \(balance.total) via \(payment.paymentMethod)")

        return GuestPaymentResponse(
            success: true,
            participantId: balance.participantId,
            isPaid: true,
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
