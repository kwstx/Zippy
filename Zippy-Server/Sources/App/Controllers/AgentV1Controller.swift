import Vapor
import Fluent
import Foundation

/// Versioned REST Controller exposing machine-actionable, agent-friendly endpoints.
/// Designed for autonomous AI agents, LLMs, and external API integrations.
public struct AgentV1Controller: Sendable {

    public init() {}

    // MARK: - GET /api/v1/health
    @Sendable
    public func health(req: Request) async throws -> AgentHealthResponse {
        return AgentHealthResponse(
            status: "operational",
            version: "1.0.0",
            environment: req.application.environment.name,
            documentation: "/api/v1/docs",
            openapiSpec: "/api/v1/openapi.json",
            supportedSplitMethods: SplitMethod.allCases.map { $0.rawValue },
            supportedCurrencies: ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "CNY", "INR", "SGD"],
            agentToolsCount: 5,
            serverTime: Date()
        )
    }

    // MARK: - POST /api/v1/agent/execute (Unified Tool Calling Router)
    @Sendable
    public func executeTool(req: Request) async throws -> AgentExecuteResponse {
        let input = try req.content.decode(AgentExecuteRequest.self)

        switch input.tool {
        case "get_exchange_rates":
            let base = input.parameters["base"] ?? "USD"
            let rates = await ExchangeRateService.getRates(base: base, client: req.client)
            let formattedRates = rates.mapValues { String($0) }
            return AgentExecuteResponse(
                success: true,
                tool: input.tool,
                result: formattedRates,
                summary: "Fetched \(rates.count) currency exchange rates for base currency \(base).",
                timestamp: Date()
            )

        case "simplify_debts":
            guard let currency = input.parameters["currency"] else {
                throw Abort(.badRequest, reason: "Missing required parameter 'currency'.")
            }
            return AgentExecuteResponse(
                success: true,
                tool: input.tool,
                result: ["currency": currency, "status": "Ready to receive balance list at /api/v1/splits/{token}/simplify"],
                summary: "Use POST /api/v1/splits/{token}/simplify or /api/v1/splits/calculate for full calculation payload.",
                timestamp: Date()
            )

        default:
            return AgentExecuteResponse(
                success: true,
                tool: input.tool,
                result: ["status": "received", "action": input.tool],
                summary: "Executed tool \(input.tool). For structured execution, see dedicated REST routes at /api/v1/docs.",
                timestamp: Date()
            )
        }
    }

    // MARK: - POST /api/v1/splits/calculate (Stateless Split Computation)
    @Sendable
    public func calculateSplitStateless(req: Request) async throws -> AgentCalculateSplitResponse {
        let input = try req.content.decode(AgentCalculateSplitRequest.self)
        
        let currency = input.currency ?? "USD"
        let targetCurrency = input.targetCurrency ?? currency
        let exchangeRate: Double
        if let customRate = input.exchangeRate {
            exchangeRate = customRate
        } else {
            exchangeRate = await ExchangeRateService.getRate(from: currency, to: targetCurrency, client: req.client)
        }

        let balances = SplitCalculator.calculate(
            method: input.method,
            items: input.items ?? [],
            receiptSubtotal: input.subtotal ?? input.total,
            tax: input.tax ?? 0.0,
            tip: input.tip ?? 0.0,
            total: input.total,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: exchangeRate,
            participants: input.participants,
            assignments: input.assignments ?? [:],
            percentageAllocations: input.percentageAllocations,
            shareAllocations: input.shareAllocations,
            exactAllocations: input.exactAllocations
        )

        let sumCalculated = balances.reduce(0.0) { $0 + $1.total }
        let convertedTotal = (input.total * exchangeRate * 100).rounded() / 100
        let discrepancy = abs(sumCalculated - input.total)
        let isBalanced = discrepancy < 0.05

        return AgentCalculateSplitResponse(
            method: input.method,
            currency: currency,
            targetCurrency: targetCurrency,
            exchangeRate: exchangeRate,
            totalAmount: input.total,
            convertedTotalAmount: convertedTotal,
            balances: balances,
            isBalanced: isBalanced,
            discrepancy: (discrepancy * 100).rounded() / 100
        )
    }

    // MARK: - POST /api/v1/splits (Create or Upsert Split Session)
    @Sendable
    public func createSplit(req: Request) async throws -> SplitSessionResponse {
        let splitController = SplitController()
        return try await splitController.create(req: req)
    }

    // MARK: - GET /api/v1/splits/:id
    @Sendable
    public func getSplit(req: Request) async throws -> SplitSessionResponse {
        let splitController = SplitController()
        return try await splitController.get(req: req)
    }

    // MARK: - POST /api/v1/splits/:token/simplify
    @Sendable
    public func simplifySplitDebts(req: Request) async throws -> SimplifyExpensesResponse {
        guard let token = req.parameters.get("token") else {
            throw Abort(.badRequest, reason: "Missing token parameter in route path.")
        }

        let isUUID = UUID(uuidString: token) != nil
        let session: SplitSession?
        if isUUID, let uuid = UUID(uuidString: token) {
            session = try await SplitSession.query(on: req.db)
                .filter(\.$id == uuid)
                .first()
        } else {
            session = try await SplitSession.query(on: req.db)
                .filter(\.$shareToken == token)
                .first()
        }

        guard let splitSession = session else {
            throw Abort(.notFound, reason: "Split session not found for token: \(token)")
        }

        let currency = splitSession.currency ?? "USD"
        var expenses: [ExpenseDTO] = []

        let organizer = splitSession.participants.first(where: { $0.isOrganizer }) ?? splitSession.participants.first
        guard let payer = organizer else {
            throw Abort(.badRequest, reason: "Split session has no participants or payer.")
        }

        for balance in splitSession.balances {
            if balance.participantId != payer.id && balance.total > 0 {
                let expense = ExpenseDTO(
                    id: UUID(),
                    groupId: splitSession.id!,
                    description: "Share for \(balance.name)",
                    amount: balance.total,
                    paidBy: payer.id,
                    splitMethod: .exact,
                    splits: [
                        ExpenseCustomSplitDTO(
                            participantId: balance.participantId,
                            amount: balance.total,
                            percentage: nil,
                            shares: nil,
                            exactAmount: balance.total,
                            convertedAmount: balance.convertedTotal
                        )
                    ],
                    currency: currency,
                    targetCurrency: splitSession.targetCurrency,
                    exchangeRate: splitSession.exchangeRate,
                    convertedAmount: balance.convertedTotal,
                    createdAt: splitSession.createdAt ?? Date()
                )
                expenses.append(expense)
            }
        }

        return MinimumCashFlowCalculator.simplifyExpenses(
            participants: splitSession.participants,
            expenses: expenses,
            currency: currency
        )
    }

    // MARK: - POST /api/v1/receipts/parse
    @Sendable
    public func parseReceipt(req: Request) async throws -> AgentParseReceiptResponse {
        let input = try req.content.decode(AgentParseReceiptRequest.self)

        var receiptItems: [ReceiptItem] = []
        if let items = input.items {
            for (idx, item) in items.enumerated() {
                receiptItems.append(
                    ReceiptItem(
                        id: idx + 1,
                        name: item.name,
                        price: item.price,
                        category: item.category
                    )
                )
            }
        }

        let computedSubtotal = receiptItems.reduce(0.0) { $0 + $1.price }
        let subtotal = input.subtotal ?? computedSubtotal
        let tax = input.tax ?? 0.0
        let tip = input.tip ?? 0.0
        let total = input.total ?? (subtotal + tax + tip)
        let currency = input.currency ?? "USD"

        let receipt = ExtractedReceipt(
            referenceId: input.referenceId ?? "agent-\(UUID().uuidString.prefix(8))",
            items: receiptItems,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            total: total,
            category: "restaurants",
            currency: currency
        )

        try await receipt.save(on: req.db)

        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let shareableURL = "\(baseURL)/api/v1/splits/\(receipt.id!.uuidString)"

        return AgentParseReceiptResponse(
            receiptId: receipt.id!,
            referenceId: receipt.referenceId,
            itemsCount: receipt.items.count,
            items: receipt.items,
            subtotal: receipt.subtotal,
            tax: receipt.tax,
            tip: receipt.tip,
            total: receipt.total,
            currency: receipt.currency ?? "USD",
            shareableURL: shareableURL
        )
    }

    // MARK: - GET /api/v1/groups/:id/ledger
    @Sendable
    public func getGroupLedger(req: Request) async throws -> GroupLedgerResponseDTO {
        let groupController = GroupController()
        return try await groupController.getHistory(req: req)
    }

    // MARK: - POST /api/v1/groups/:id/expenses
    @Sendable
    public func addGroupExpense(req: Request) async throws -> GroupLedgerResponseDTO {
        let groupController = GroupController()
        return try await groupController.addExpense(req: req)
    }

    // MARK: - POST /api/v1/groups/:id/settlements
    @Sendable
    public func addGroupSettlement(req: Request) async throws -> GroupLedgerResponseDTO {
        let groupController = GroupController()
        return try await groupController.addSettlement(req: req)
    }

    // MARK: - GET /api/v1/rates
    @Sendable
    public func getRates(req: Request) async -> [String: Double] {
        let base = (try? req.query.get(String.self, at: "base")) ?? "USD"
        return await ExchangeRateService.getRates(base: base, client: req.client)
    }
}
