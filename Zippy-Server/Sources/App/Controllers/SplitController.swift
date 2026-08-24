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

    /// Converts a SplitSession model and receipt into SplitSessionResponse DTO with multi-currency data.
    private static func makeSplitSessionResponse(session: SplitSession, receipt: ExtractedReceipt?, req: Request) -> SplitSessionResponse {
        let token = session.shareToken ?? session.id!.uuidString
        let shareableURL = session.shareToken != nil
            ? Self.makeShortURL(for: token, req: req)
            : "/api/splits/\(session.id!.uuidString)"
        let method = session.splitMethod.flatMap(SplitMethod.init(rawValue:)) ?? .itemized
        let total = receipt?.total ?? session.balances.reduce(0.0) { $0 + $1.total }
        let currency = session.currency ?? receipt?.currency ?? "USD"
        let targetCurrency = session.targetCurrency ?? receipt?.targetCurrency ?? "USD"
        let exchangeRate = session.exchangeRate ?? receipt?.exchangeRate ?? 1.0
        let convertedTotal = receipt?.convertedTotal ?? ((total * exchangeRate * 100).rounded() / 100)

        return SplitSessionResponse(
            id: session.id!,
            receiptId: session.receiptId,
            participants: session.participants,
            splitMethod: method,
            assignments: session.assignments,
            percentageAllocations: session.percentageAllocations,
            shareAllocations: session.shareAllocations,
            exactAllocations: session.exactAllocations,
            balances: session.balances,
            receiptTotal: total,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: exchangeRate,
            convertedReceiptTotal: convertedTotal,
            category: session.category ?? receipt?.category,
            shareableURL: shareableURL,
            createdAt: session.createdAt
        )
    }

    /// Creates or updates a split session with server-computed balances, consulting live exchange rates.
    @Sendable
    func create(req: Request) async throws -> SplitSessionResponse {
        let input = try req.content.decode(CreateSplitRequest.self)

        // Load the receipt to get items, tax, tip
        guard let receipt = try await ExtractedReceipt.find(input.receiptId, on: req.db) else {
            throw Abort(.notFound, reason: "No receipt found with ID: \(input.receiptId)")
        }

        let selectedMethod = input.splitMethod ?? .itemized
        let assignments = input.assignments ?? [:]

        // Multi-currency: consult live rate service at calculation time
        let currency = input.currency ?? receipt.currency ?? "USD"
        let targetCurrency = input.targetCurrency ?? receipt.targetCurrency ?? "USD"
        let rate = await ExchangeRateService.getRate(from: currency, to: targetCurrency, client: req.client)

        // Compute authoritative balances across flexible methods with live exchange rate
        let balances = SplitCalculator.calculate(
            method: selectedMethod,
            items: receipt.items,
            receiptSubtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: rate,
            participants: input.participants,
            assignments: assignments,
            percentageAllocations: input.percentageAllocations,
            shareAllocations: input.shareAllocations,
            exactAllocations: input.exactAllocations
        )

        // Upsert: check for existing session for this receipt
        let categoryTag = input.category ?? receipt.category
        if input.category != nil && receipt.category != input.category {
            receipt.category = input.category
            try await receipt.update(on: req.db)
        }

        let session: SplitSession
        let token: String
        if let existing = try await SplitSession.query(on: req.db)
            .filter(\.$receiptId == input.receiptId)
            .first() {
            existing.participants = input.participants
            existing.splitMethod = selectedMethod.rawValue
            existing.assignments = assignments
            existing.percentageAllocations = input.percentageAllocations
            existing.shareAllocations = input.shareAllocations
            existing.exactAllocations = input.exactAllocations
            existing.balances = balances
            existing.currency = currency
            existing.targetCurrency = targetCurrency
            existing.exchangeRate = rate
            existing.category = categoryTag
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
                splitMethod: selectedMethod.rawValue,
                assignments: assignments,
                percentageAllocations: input.percentageAllocations,
                shareAllocations: input.shareAllocations,
                exactAllocations: input.exactAllocations,
                balances: balances,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: rate,
                shareToken: generatedToken,
                category: categoryTag
            )
            try await newSession.save(on: req.db)
            session = newSession
            token = generatedToken
        }

        req.logger.info("Split session \(session.id?.uuidString ?? "?") saved for receipt \(input.receiptId) [\(currency) -> \(targetCurrency) @ \(rate)] with method '\(selectedMethod.rawValue)' and token \(token)")

        return Self.makeSplitSessionResponse(session: session, receipt: receipt, req: req)
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

        let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db)
        return Self.makeSplitSessionResponse(session: session, receipt: receipt, req: req)
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
            let responseDTO = Self.makeSplitSessionResponse(session: session, receipt: receipt, req: req)
            return try await responseDTO.encodeResponse(for: req)
        }

        // Render lightweight black-and-white minimalist HTML page with monochrome lighter-weight currency display
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
        currency: String = "USD",
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
            let instructions = "Open Venmo to pay \(formattedAmount) \(currency). Settlement status will flip to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "paypal":
            let deepLink = "https://www.paypal.com/paypalme/zippysplit/\(formattedAmount)"
            let instructions = "Open PayPal to transfer \(formattedAmount) \(currency). Include reference \(reference) in note. Settlement flips to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "cash app", "cashapp", "cash_app":
            let deepLink = "https://cash.app/$zippysplit/\(formattedAmount)"
            let instructions = "Open Cash App to send \(formattedAmount) \(currency). Include note \(reference). Settlement flips to settled upon webhook or manual confirmation."
            return (deepLink, instructions)

        case "bank transfer", "bank_transfer", "ach", "wire":
            let instructions = """
            Direct Bank Transfer (ACH / Wire)
            Routing Number: 021000021
            Account Number: 9876543210
            Account Name: Zippy Split Host
            Currency: \(currency)
            Amount: \(formattedAmount)
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
            currency: balance.currency,
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
            currency: balance.currency,
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
            currency: balance.currency,
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
        let currency = session.currency ?? "USD"

        let participants = session.balances.map {
            SplitStatusResponse.ParticipantStatusDTO(
                id: $0.participantId,
                name: $0.name,
                total: $0.total,
                currency: $0.currency,
                convertedTotal: $0.convertedTotal,
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
            currency: currency,
            isFullySettled: isFullySettled,
            participants: participants
        )
    }

    /// Renders the minimalist pure white status screen displaying only participant names and a black checkmark or empty black circle.
    @Sendable
    func viewWhiteStatusScreen(req: Request) async throws -> Response {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db)
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"

        let html = GuestViewRenderer.renderWhiteStatusScreen(
            session: session,
            receipt: receipt,
            token: token,
            baseURL: baseURL
        )

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Optimizes multiple expenses into minimal direct transfers.
    @Sendable
    func simplifyExpenses(req: Request) async throws -> SimplifyExpensesResponse {
        let input = try req.content.decode(SimplifyExpensesRequest.self)
        let baseCurrency = input.baseCurrency ?? "USD"
        let response = MinimumCashFlowCalculator.simplifyExpenses(
            participants: input.participants,
            expenses: input.expenses,
            currency: baseCurrency
        )
        req.logger.info("Simplified \(input.expenses.count) expenses for \(input.participants.count) participants into \(response.transferCount) transfers")
        return response
    }

    /// Retrieves simplified payments for an existing split session.
    @Sendable
    func getSimplifiedPayments(req: Request) async throws -> Response {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing share token.")
        }

        guard let session = try await SplitSession.query(on: req.db)
            .filter(\.$shareToken == token)
            .first() else {
            throw Abort(.notFound, reason: "No split session found for token: \(token)")
        }

        let simplified = MinimumCashFlowCalculator.simplifyBalances(
            balances: session.balances,
            currency: session.currency ?? "USD"
        )

        let acceptHeader = req.headers.first(name: .accept) ?? ""
        let isJsonRequest = acceptHeader.contains("application/json") && !acceptHeader.contains("text/html")

        if isJsonRequest {
            return try await simplified.encodeResponse(for: req)
        }

        // Render minimalist white screen titled "Simplified payments" with reduced black text lines
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let html = GuestViewRenderer.renderSimplifiedPayments(
            lines: simplified.lines,
            title: "Simplified payments",
            backURL: "/s/\(token)",
            baseURL: baseURL
        )

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Standalone public endpoint rendering a minimalist white screen titled "Simplified payments".
    @Sendable
    func viewSimplifiedPaymentsStandalone(req: Request) async throws -> Response {
        let sampleLines = [
            "Alice pays Bob 24.50 USD",
            "Charlie pays Bob 18.00 USD",
            "David pays Alice 12.25 USD"
        ]

        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let html = GuestViewRenderer.renderSimplifiedPayments(
            lines: sampleLines,
            title: "Simplified payments",
            backURL: nil,
            baseURL: baseURL
        )

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }

    /// Updates the category for a split session (by session UUID or share token).
    @Sendable
    func updateCategory(req: Request) async throws -> SplitSessionResponse {
        let token = req.parameters.get("token")
        let sessionId = req.parameters.get("id", as: UUID.self)
        let input = try req.content.decode(UpdateCategoryRequest.self)

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
            throw Abort(.badRequest, reason: "Missing token or session ID.")
        }

        session.category = input.category
        try await session.update(on: req.db)

        if let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db) {
            receipt.category = input.category
            try await receipt.update(on: req.db)
        }

        req.logger.info("Updated category on split session \(session.id?.uuidString ?? "") to '\(input.category ?? "none")'")

        let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db)
        return Self.makeSplitSessionResponse(session: session, receipt: receipt, req: req)
    }

    /// Updates the split method and recalculates allocations & balances on the backend using live exchange rate.
    @Sendable
    func updateSplitMethod(req: Request) async throws -> SplitSessionResponse {
        let token = req.parameters.get("token")
        let sessionId = req.parameters.get("id", as: UUID.self)
        let input = try req.content.decode(UpdateSplitMethodRequest.self)

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
            throw Abort(.badRequest, reason: "Missing token or session ID.")
        }

        guard let receipt = try await ExtractedReceipt.find(session.receiptId, on: req.db) else {
            throw Abort(.notFound, reason: "Receipt not found for split session.")
        }

        if let participants = input.participants, !participants.isEmpty {
            session.participants = participants
        }
        if let assignments = input.assignments {
            session.assignments = assignments
        }
        if let percentageAllocations = input.percentageAllocations {
            session.percentageAllocations = percentageAllocations
        }
        if let shareAllocations = input.shareAllocations {
            session.shareAllocations = shareAllocations
        }
        if let exactAllocations = input.exactAllocations {
            session.exactAllocations = exactAllocations
        }
        session.splitMethod = input.splitMethod.rawValue

        // Consult live exchange rate
        let currency = input.currency ?? session.currency ?? receipt.currency ?? "USD"
        let targetCurrency = input.targetCurrency ?? session.targetCurrency ?? receipt.targetCurrency ?? "USD"
        let rate = await ExchangeRateService.getRate(from: currency, to: targetCurrency, client: req.client)

        session.currency = currency
        session.targetCurrency = targetCurrency
        session.exchangeRate = rate

        // Authoritative recalculation on the backend
        let balances = SplitCalculator.calculate(
            method: input.splitMethod,
            items: receipt.items,
            receiptSubtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: rate,
            participants: session.participants,
            assignments: session.assignments,
            percentageAllocations: session.percentageAllocations,
            shareAllocations: session.shareAllocations,
            exactAllocations: session.exactAllocations
        )
        session.balances = balances

        try await session.update(on: req.db)

        req.logger.info("Updated split method to '\(input.splitMethod.rawValue)' on session \(session.id?.uuidString ?? "")")

        return Self.makeSplitSessionResponse(session: session, receipt: receipt, req: req)
    }

    /// Returns past split sessions and receipts filtered by optional category tag, search query, and currency from PostgreSQL.
    @Sendable
    func getHistory(req: Request) async throws -> [HistoryItemDTO] {
        let query = try? req.query.decode(HistoryFilterQuery.self)
        let categoryFilter = query?.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let searchTerm = query?.search?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 1. Query PostgreSQL for SplitSessions with category filter if specified
        var sessionQuery = SplitSession.query(on: req.db)
        if let category = categoryFilter, !category.isEmpty, category != "all" {
            sessionQuery = sessionQuery.filter(\.$category == category)
        }
        let allSessions = try await sessionQuery.sort(\.$createdAt, .descending).all()

        // 2. Query PostgreSQL for ExtractedReceipts with category filter if specified
        var receiptDbQuery = ExtractedReceipt.query(on: req.db)
        if let category = categoryFilter, !category.isEmpty, category != "all" {
            receiptDbQuery = receiptDbQuery.filter(\.$category == category)
        }
        let allReceipts = try await receiptDbQuery.sort(\.$createdAt, .descending).all()

        let receiptMap = Dictionary(uniqueKeysWithValues: allReceipts.compactMap { r in
            r.id != nil ? (r.id!, r) : nil
        })

        var historyItems: [HistoryItemDTO] = []
        var processedReceiptIds = Set<UUID>()

        for session in allSessions {
            guard let sessionId = session.id else { continue }
            let receipt = receiptMap[session.receiptId]
            if let rId = receipt?.id {
                processedReceiptIds.insert(rId)
            }

            let effectiveCategory = session.category ?? receipt?.category
            let total = receipt?.total ?? session.balances.reduce(0.0) { $0 + $1.total }
            let currency = session.currency ?? receipt?.currency ?? "USD"
            let targetCurrency = session.targetCurrency ?? receipt?.targetCurrency ?? "USD"
            let exchangeRate = session.exchangeRate ?? receipt?.exchangeRate ?? 1.0
            let convertedTotal = receipt?.convertedTotal ?? ((total * exchangeRate * 100).rounded() / 100)
            let isSettled = !session.balances.isEmpty && session.balances.allSatisfy(\.isPaid)
            let token = session.shareToken ?? sessionId.uuidString
            let shareURL = Self.makeShortURL(for: token, req: req)
            let itemsSummary = receipt?.items.prefix(4).map(\.name)

            let title: String
            if let firstItem = receipt?.items.first?.name, !firstItem.isEmpty {
                title = firstItem + (receipt!.items.count > 1 ? " + \(receipt!.items.count - 1) more" : "")
            } else if !session.participants.isEmpty {
                title = "Split with " + session.participants.map(\.name).joined(separator: ", ")
            } else {
                title = "Split Receipt"
            }

            historyItems.append(HistoryItemDTO(
                id: sessionId,
                receiptId: session.receiptId,
                title: title,
                category: effectiveCategory,
                total: total,
                currency: currency,
                convertedTotal: convertedTotal,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                createdAt: session.createdAt,
                participantCount: session.participants.count,
                isSettled: isSettled,
                shareableURL: shareURL,
                itemsSummary: itemsSummary.map(Array.init)
            ))
        }

        // Include any standalone receipts that haven't been split yet
        for receipt in allReceipts {
            guard let rId = receipt.id, !processedReceiptIds.contains(rId) else { continue }
            let title = receipt.items.first?.name ?? "Receipt (\(receipt.referenceId.prefix(6)))"
            let itemsSummary = receipt.items.prefix(4).map(\.name)
            let currency = receipt.currency ?? "USD"
            let targetCurrency = receipt.targetCurrency ?? "USD"
            let exchangeRate = receipt.exchangeRate ?? 1.0
            let convertedTotal = receipt.convertedTotal ?? ((receipt.total * exchangeRate * 100).rounded() / 100)

            historyItems.append(HistoryItemDTO(
                id: rId,
                receiptId: rId,
                title: title,
                category: receipt.category,
                total: receipt.total,
                currency: currency,
                convertedTotal: convertedTotal,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                createdAt: receipt.createdAt,
                participantCount: 0,
                isSettled: false,
                shareableURL: nil,
                itemsSummary: Array(itemsSummary)
            ))
        }

        // Apply Category Filter in memory as fallback for joint records
        if let category = categoryFilter, !category.isEmpty, category != "all" {
            historyItems = historyItems.filter { item in
                guard let cat = item.category?.lowercased() else { return false }
                return cat == category || cat.contains(category)
            }
        }

        // Apply Keyword Search Filter across title, category, line items, currency, total
        if let search = searchTerm, !search.isEmpty {
            historyItems = historyItems.filter { item in
                let matchesTitle = item.title.lowercased().contains(search)
                let matchesCategory = item.category?.lowercased().contains(search) ?? false
                let matchesItems = item.itemsSummary?.contains { $0.lowercased().contains(search) } ?? false
                let matchesTotal = String(format: "%.2f", item.total).contains(search)
                let matchesCurrency = item.currency.lowercased().contains(search)
                return matchesTitle || matchesCategory || matchesItems || matchesTotal || matchesCurrency
            }
        }

        return historyItems
    }

    /// Exports filtered expense history as a streamed CSV or pure-Swift PDF document.
    @Sendable
    func exportHistory(req: Request) async throws -> Response {
        let items = try await getHistory(req: req)
        let query = try? req.query.decode(HistoryFilterQuery.self)
        let format = query?.format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "csv"
        let category = query?.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let search = query?.search?.trimmingCharacters(in: .whitespacesAndNewlines)

        req.logger.info("Exporting \(items.count) expense history item(s) as \(format.uppercased())")

        if format == "pdf" {
            return ExportStreamingService.streamPDF(
                items: items,
                categoryFilter: category,
                searchQuery: search,
                req: req
            )
        } else {
            return ExportStreamingService.streamCSV(
                items: items,
                req: req
            )
        }
    }
}
