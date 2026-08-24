import Vapor
import Foundation

// MARK: - Agent Error Response
/// Standardized machine-readable error payload formatted specifically for autonomous agents and LLMs
public struct AgentErrorResponse: Content {
    public let error: String
    public let code: String
    public let status: Int
    public let details: [String]?
    public let remediationHint: String?
    public let documentationUrl: String

    public init(
        error: String,
        code: String,
        status: Int = 400,
        details: [String]? = nil,
        remediationHint: String? = nil,
        documentationUrl: String = "/api/v1/docs"
    ) {
        self.error = error
        self.code = code
        self.status = status
        self.details = details
        self.remediationHint = remediationHint
        self.documentationUrl = documentationUrl
    }
}

// MARK: - Agent Tool Definition Models (OpenAI / Gemini / Anthropic function-calling compatible)
public struct AgentToolDefinition: Content {
    public let name: String
    public let description: String
    public let parameters: AgentToolParameters

    public init(name: String, description: String, parameters: AgentToolParameters) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct AgentToolParameters: Content {
    public let type: String
    public let properties: [String: AgentPropertySchema]
    public let required: [String]

    public init(type: String = "object", properties: [String: AgentPropertySchema], required: [String]) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct AgentPropertySchema: Content {
    public let type: String
    public let description: String
    public let items: [String: String]?
    public let `enum`: [String]?

    public init(type: String, description: String, items: [String: String]? = nil, `enum`: [String]? = nil) {
        self.type = type
        self.description = description
        self.items = items
        self.enum = `enum`
    }
}

public struct AgentToolsManifestResponse: Content {
    public let version: String
    public let agentProtocolVersion: String
    public let description: String
    public let tools: [AgentToolDefinition]
}

// MARK: - Agent Unified Execution
public struct AgentExecuteRequest: Content {
    public let tool: String
    public let parameters: [String: String]
    public let agentId: String?
    public let idempotencyKey: String?
}

public struct AgentExecuteResponse: Content {
    public let success: Bool
    public let tool: String
    public let result: [String: String]
    public let summary: String
    public let timestamp: Date
}

// MARK: - Stateless Calculation DTOs for Agents
public struct AgentCalculateSplitRequest: Content {
    public let method: SplitMethod
    public let total: Double
    public let subtotal: Double?
    public let tax: Double?
    public let tip: Double?
    public let currency: String?
    public let targetCurrency: String?
    public let exchangeRate: Double?
    public let participants: [ParticipantDTO]
    public let items: [ReceiptItem]?
    public let assignments: [String: [UUID]]?
    public let percentageAllocations: [String: Double]?
    public let shareAllocations: [String: Double]?
    public let exactAllocations: [String: Double]?
}

public struct AgentCalculateSplitResponse: Content {
    public let method: SplitMethod
    public let currency: String
    public let targetCurrency: String
    public let exchangeRate: Double
    public let totalAmount: Double
    public let convertedTotalAmount: Double
    public let balances: [ParticipantBalanceDTO]
    public let isBalanced: Bool
    public let discrepancy: Double
}

// MARK: - Agent Debt Simplification DTOs
public struct AgentSimplifyDebtsRequest: Content {
    public let balances: [ParticipantBalanceDTO]
    public let currency: String?
}

public struct AgentSimplifyDebtsResponse: Content {
    public let currency: String
    public let originalTransactionsCount: Int
    public let simplifiedTransactionsCount: Int
    public let transactions: [SimplifiedPaymentDTO]
    public let netBalances: [String: Double]
}

// MARK: - Agent Receipt Parse DTOs
public struct AgentReceiptItemInput: Content {
    public let name: String
    public let price: Double
    public let quantity: Int?
    public let category: String?
}

public struct AgentParseReceiptRequest: Content {
    public let rawText: String?
    public let items: [AgentReceiptItemInput]?
    public let subtotal: Double?
    public let tax: Double?
    public let tip: Double?
    public let total: Double?
    public let currency: String?
    public let referenceId: String?
}

public struct AgentParseReceiptResponse: Content {
    public let receiptId: UUID
    public let referenceId: String?
    public let itemsCount: Int
    public let items: [ReceiptItem]
    public let subtotal: Double
    public let tax: Double
    public let tip: Double
    public let total: Double
    public let currency: String
    public let shareableURL: String?
}

// MARK: - Agent API Health & Capability DTO
public struct AgentHealthResponse: Content {
    public let status: String
    public let version: String
    public let environment: String
    public let documentation: String
    public let openapiSpec: String
    public let supportedSplitMethods: [String]
    public let supportedCurrencies: [String]
    public let agentToolsCount: Int
    public let serverTime: Date
}
