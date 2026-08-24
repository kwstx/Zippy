import Vapor
import Foundation

/// Controller that serves OpenAPI 3.1.0 specifications and LLM Agent Tool Manifests.
public struct OpenAPIController: Sendable {

    public init() {}

    // MARK: - OpenAPI JSON Spec
    @Sendable
    public func getSpecJSON(req: Request) async throws -> Response {
        let spec = Self.generateOpenAPISpec(req: req)
        let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        return response
    }

    // MARK: - OpenAPI YAML Spec
    @Sendable
    public func getSpecYAML(req: Request) async throws -> Response {
        let yaml = Self.generateOpenAPIYAML(req: req)
        let response = Response(status: .ok, body: .init(string: yaml))
        response.headers.contentType = .init(type: "text", subType: "yaml")
        return response
    }

    // MARK: - Interactive Swagger UI / API Documentation
    @Sendable
    public func getDocsHTML(req: Request) async throws -> Response {
        let html = Self.generateDocsHTML(req: req)
        let response = Response(status: .ok, body: .init(string: html))
        response.headers.contentType = .html
        return response
    }

    // MARK: - AI Plugin Manifest
    @Sendable
    public func getAIManifest(req: Request) async throws -> Response {
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        let manifest: [String: Any] = [
            "schema_version": "v1",
            "name_for_human": "Zippy Expense & Bill Splitting",
            "name_for_model": "zippy_agent_api",
            "description_for_human": "Agent-friendly bill splitting, debt simplification, and group expense tracking.",
            "description_for_model": "Autonomous agent API for parsing receipts, calculating flexible multi-currency splits, simplifying debts (Minimum Cash Flow), and managing persistent group ledgers.",
            "auth": [
                "type": "none"
            ],
            "api": [
                "type": "openapi",
                "url": "\(baseURL)/api/v1/openapi.json"
            ],
            "logo_url": "\(baseURL)/logo.png",
            "contact_email": "api@zippy.app",
            "legal_info_url": "\(baseURL)/privacy"
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.contentType = .json
        return response
    }

    // MARK: - LLM Agent Tool Manifest
    @Sendable
    public func getAgentTools(req: Request) async throws -> AgentToolsManifestResponse {
        return AgentToolsManifestResponse(
            version: "1.0.0",
            agentProtocolVersion: "1.0",
            description: "Zippy Autonomous Agent Tools for expense allocation, debt simplification, and ledger management.",
            tools: [
                AgentToolDefinition(
                    name: "calculate_split",
                    description: "Statelessly calculates split balances among participants across equal, itemized, percentage, shares, or exact allocation methods with real-time multi-currency exchange rates.",
                    parameters: AgentToolParameters(
                        properties: [
                            "method": AgentPropertySchema(
                                type: "string",
                                description: "Split strategy to apply",
                                enum: ["equal", "itemized", "percentage", "shares", "exact"]
                            ),
                            "total": AgentPropertySchema(
                                type: "number",
                                description: "Total receipt amount"
                            ),
                            "currency": AgentPropertySchema(
                                type: "string",
                                description: "Source currency 3-letter ISO code (e.g., USD, EUR, GBP)"
                            ),
                            "targetCurrency": AgentPropertySchema(
                                type: "string",
                                description: "Target currency 3-letter ISO code for settlement"
                            ),
                            "participants": AgentPropertySchema(
                                type: "array",
                                description: "List of participant objects with name, optional email/phone and isOrganizer flag"
                            )
                        ],
                        required: ["method", "total", "participants"]
                    )
                ),
                AgentToolDefinition(
                    name: "simplify_debts",
                    description: "Calculates the minimum cash flow transfers to settle all group or split balances with the absolute minimum number of payments.",
                    parameters: AgentToolParameters(
                        properties: [
                            "balances": AgentPropertySchema(
                                type: "array",
                                description: "Array of participant balance objects containing participantId, name, and total amount owed/paid"
                            ),
                            "currency": AgentPropertySchema(
                                type: "string",
                                description: "Currency code for the transfer calculations"
                            )
                        ],
                        required: ["balances"]
                    )
                ),
                AgentToolDefinition(
                    name: "parse_receipt_items",
                    description: "Ingests structured or raw receipt text into validated line items with tax, tip, and subtotal reconciliation.",
                    parameters: AgentToolParameters(
                        properties: [
                            "items": AgentPropertySchema(
                                type: "array",
                                description: "Array of items with name, price, and optional quantity/category"
                            ),
                            "subtotal": AgentPropertySchema(type: "number", description: "Receipt subtotal before tax and tip"),
                            "tax": AgentPropertySchema(type: "number", description: "Tax amount"),
                            "tip": AgentPropertySchema(type: "number", description: "Tip amount"),
                            "total": AgentPropertySchema(type: "number", description: "Receipt total amount"),
                            "currency": AgentPropertySchema(type: "string", description: "3-letter currency code")
                        ],
                        required: ["items", "total"]
                    )
                ),
                AgentToolDefinition(
                    name: "record_group_expense",
                    description: "Records an automated expense event into a persistent group ledger with automatic split calculation.",
                    parameters: AgentToolParameters(
                        properties: [
                            "groupId": AgentPropertySchema(type: "string", description: "UUID of the persistent group"),
                            "payerId": AgentPropertySchema(type: "string", description: "UUID of the paying participant"),
                            "amount": AgentPropertySchema(type: "number", description: "Expense amount"),
                            "description": AgentPropertySchema(type: "string", description: "Description or merchant name"),
                            "category": AgentPropertySchema(type: "string", description: "Expense category (e.g. restaurants, trips, everyday)"),
                            "splitMethod": AgentPropertySchema(type: "string", description: "Split method", enum: ["equal", "itemized", "percentage", "shares", "exact"])
                        ],
                        required: ["groupId", "payerId", "amount", "description"]
                    )
                ),
                AgentToolDefinition(
                    name: "get_exchange_rates",
                    description: "Fetches live foreign exchange rates against a base currency.",
                    parameters: AgentToolParameters(
                        properties: [
                            "base": AgentPropertySchema(type: "string", description: "Base 3-letter currency code (defaults to USD)")
                        ],
                        required: []
                    )
                )
            ]
        )
    }

    // MARK: - Internal OpenAPI 3.1.0 Dictionary Generator
    private static func generateOpenAPISpec(req: Request) -> [String: Any] {
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"

        return [
            "openapi": "3.1.0",
            "info": [
                "title": "Zippy Public Agent API",
                "version": "1.0.0",
                "description": "Versioned REST routes documented with OpenAPI for external integrations and autonomous AI agents. The native iOS client retains a dedicated human interface and does not consume these public agent routes.",
                "contact": [
                    "name": "Zippy API Support",
                    "email": "api@zippy.app"
                ],
                "license": [
                    "name": "MIT"
                ]
            ],
            "servers": [
                [
                    "url": "\(baseURL)/api/v1",
                    "description": "Production Version 1 Gateway"
                ]
            ],
            "paths": [
                "/health": [
                    "get": [
                        "summary": "Agent Capability Matrix & Health Status",
                        "operationId": "getAgentHealth",
                        "tags": ["System"],
                        "responses": [
                            "200": [
                                "description": "System health and supported features",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentHealthResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/agent/tools": [
                    "get": [
                        "summary": "Retrieve LLM Agent Tool Manifest",
                        "operationId": "getAgentTools",
                        "tags": ["Agent"],
                        "description": "Returns JSON-schema formatted function definitions compatible with OpenAI, Gemini, and Anthropic function calling.",
                        "responses": [
                            "200": [
                                "description": "Agent tool definitions",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentToolsManifestResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/agent/execute": [
                    "post": [
                        "summary": "Execute Unified Agent Tool",
                        "operationId": "executeAgentTool",
                        "tags": ["Agent"],
                        "requestBody": [
                            "required": true,
                            "content": [
                                "application/json": [
                                    "schema": ["$ref": "#/components/schemas/AgentExecuteRequest"]
                                ]
                            ]
                        ],
                        "responses": [
                            "200": [
                                "description": "Tool execution result",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentExecuteResponse"]
                                    ]
                                ]
                            ],
                            "400": [
                                "description": "Agent validation error",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentErrorResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/splits/calculate": [
                    "post": [
                        "summary": "Stateless Split Calculation Engine",
                        "operationId": "calculateSplitStateless",
                        "tags": ["Splits"],
                        "description": "Calculates authoritative participant balances across equal, itemized, percent, shares, and exact splits with currency conversion.",
                        "requestBody": [
                            "required": true,
                            "content": [
                                "application/json": [
                                    "schema": ["$ref": "#/components/schemas/AgentCalculateSplitRequest"]
                                ]
                            ]
                        ],
                        "responses": [
                            "200": [
                                "description": "Calculated participant balances",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentCalculateSplitResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/splits/{token}/simplify": [
                    "post": [
                        "summary": "Simplify Group Debts (Minimum Cash Flow)",
                        "operationId": "simplifyDebts",
                        "tags": ["Splits"],
                        "parameters": [
                            [
                                "name": "token",
                                "in": "path",
                                "required": true,
                                "schema": ["type": "string"],
                                "description": "Split session share token or UUID"
                            ]
                        ],
                        "responses": [
                            "200": [
                                "description": "Optimal minimal cash flow transactions",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentSimplifyDebtsResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/receipts/parse": [
                    "post": [
                        "summary": "Parse & Validate Receipt Line Items",
                        "operationId": "parseReceipt",
                        "tags": ["Receipts"],
                        "requestBody": [
                            "required": true,
                            "content": [
                                "application/json": [
                                    "schema": ["$ref": "#/components/schemas/AgentParseReceiptRequest"]
                                ]
                            ]
                        ],
                        "responses": [
                            "200": [
                                "description": "Created receipt entity with validation",
                                "content": [
                                    "application/json": [
                                        "schema": ["$ref": "#/components/schemas/AgentParseReceiptResponse"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "/rates": [
                    "get": [
                        "summary": "Get Live Currency Exchange Rates",
                        "operationId": "getRates",
                        "tags": ["Currencies"],
                        "parameters": [
                            [
                                "name": "base",
                                "in": "query",
                                "required": false,
                                "schema": ["type": "string", "default": "USD"],
                                "description": "Base 3-letter currency code"
                            ]
                        ],
                        "responses": [
                            "200": [
                                "description": "Dictionary of currency exchange rates",
                                "content": [
                                    "application/json": [
                                        "schema": [
                                            "type": "object",
                                            "additionalProperties": ["type": "number"]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ],
            "components": [
                "schemas": [
                    "AgentHealthResponse": [
                        "type": "object",
                        "properties": [
                            "status": ["type": "string"],
                            "version": ["type": "string"],
                            "environment": ["type": "string"],
                            "documentation": ["type": "string"],
                            "openapiSpec": ["type": "string"],
                            "supportedSplitMethods": ["type": "array", "items": ["type": "string"]],
                            "supportedCurrencies": ["type": "array", "items": ["type": "string"]],
                            "agentToolsCount": ["type": "integer"],
                            "serverTime": ["type": "string", "format": "date-time"]
                        ],
                        "required": ["status", "version", "supportedSplitMethods"]
                    ],
                    "AgentErrorResponse": [
                        "type": "object",
                        "properties": [
                            "error": ["type": "string"],
                            "code": ["type": "string"],
                            "status": ["type": "integer"],
                            "details": ["type": "array", "items": ["type": "string"]],
                            "remediationHint": ["type": "string"],
                            "documentationUrl": ["type": "string"]
                        ],
                        "required": ["error", "code", "status", "documentationUrl"]
                    ],
                    "AgentExecuteRequest": [
                        "type": "object",
                        "properties": [
                            "tool": ["type": "string"],
                            "parameters": ["type": "object", "additionalProperties": ["type": "string"]],
                            "agentId": ["type": "string"],
                            "idempotencyKey": ["type": "string"]
                        ],
                        "required": ["tool", "parameters"]
                    ],
                    "AgentExecuteResponse": [
                        "type": "object",
                        "properties": [
                            "success": ["type": "boolean"],
                            "tool": ["type": "string"],
                            "result": ["type": "object", "additionalProperties": ["type": "string"]],
                            "summary": ["type": "string"],
                            "timestamp": ["type": "string", "format": "date-time"]
                        ],
                        "required": ["success", "tool", "summary"]
                    ],
                    "AgentCalculateSplitRequest": [
                        "type": "object",
                        "properties": [
                            "method": ["type": "string", "enum": ["equal", "itemized", "percentage", "shares", "exact"]],
                            "total": ["type": "number"],
                            "subtotal": ["type": "number"],
                            "tax": ["type": "number"],
                            "tip": ["type": "number"],
                            "currency": ["type": "string"],
                            "targetCurrency": ["type": "string"],
                            "exchangeRate": ["type": "number"],
                            "participants": ["type": "array", "items": ["type": "object"]]
                        ],
                        "required": ["method", "total", "participants"]
                    ],
                    "AgentCalculateSplitResponse": [
                        "type": "object",
                        "properties": [
                            "method": ["type": "string"],
                            "currency": ["type": "string"],
                            "targetCurrency": ["type": "string"],
                            "exchangeRate": ["type": "number"],
                            "totalAmount": ["type": "number"],
                            "convertedTotalAmount": ["type": "number"],
                            "balances": ["type": "array", "items": ["type": "object"]],
                            "isBalanced": ["type": "boolean"],
                            "discrepancy": ["type": "number"]
                        ],
                        "required": ["method", "currency", "totalAmount", "balances", "isBalanced"]
                    ],
                    "AgentSimplifyDebtsResponse": [
                        "type": "object",
                        "properties": [
                            "currency": ["type": "string"],
                            "originalTransactionsCount": ["type": "integer"],
                            "simplifiedTransactionsCount": ["type": "integer"],
                            "transactions": ["type": "array", "items": ["type": "object"]],
                            "netBalances": ["type": "object", "additionalProperties": ["type": "number"]]
                        ],
                        "required": ["currency", "transactions"]
                    ],
                    "AgentParseReceiptRequest": [
                        "type": "object",
                        "properties": [
                            "rawText": ["type": "string"],
                            "items": ["type": "array", "items": ["type": "object"]],
                            "subtotal": ["type": "number"],
                            "tax": ["type": "number"],
                            "tip": ["type": "number"],
                            "total": ["type": "number"],
                            "currency": ["type": "string"],
                            "referenceId": ["type": "string"]
                        ]
                    ],
                    "AgentParseReceiptResponse": [
                        "type": "object",
                        "properties": [
                            "receiptId": ["type": "string", "format": "uuid"],
                            "itemsCount": ["type": "integer"],
                            "subtotal": ["type": "number"],
                            "tax": ["type": "number"],
                            "tip": ["type": "number"],
                            "total": ["type": "number"],
                            "currency": ["type": "string"],
                            "shareableURL": ["type": "string"]
                        ],
                        "required": ["receiptId", "itemsCount", "total", "currency"]
                    ]
                ],
                "securitySchemes": [
                    "ApiKeyAuth": [
                        "type": "apiKey",
                        "in": "header",
                        "name": "X-API-Key"
                    ],
                    "AgentIdAuth": [
                        "type": "apiKey",
                        "in": "header",
                        "name": "X-Agent-ID"
                    ],
                    "BearerAuth": [
                        "type": "http",
                        "scheme": "bearer"
                    ]
                ]
            ]
        ]
    }

    // MARK: - OpenAPI YAML Generator
    private static func generateOpenAPIYAML(req: Request) -> String {
        let baseURL = Environment.get("BASE_URL") ?? "http://localhost:8080"
        return """
        openapi: 3.1.0
        info:
          title: Zippy Public Agent API
          version: 1.0.0
          description: Versioned REST routes documented with OpenAPI for external integrations and autonomous AI agents.
        servers:
          - url: \(baseURL)/api/v1
            description: Production Version 1 Gateway
        paths:
          /health:
            get:
              summary: Agent Capability Matrix & Health Status
              operationId: getAgentHealth
              responses:
                '200':
                  description: System health and supported features
          /agent/tools:
            get:
              summary: Retrieve LLM Agent Tool Manifest
              operationId: getAgentTools
              responses:
                '200':
                  description: Agent tool definitions
          /splits/calculate:
            post:
              summary: Stateless Split Calculation Engine
              operationId: calculateSplitStateless
              responses:
                '200':
                  description: Calculated participant balances
          /rates:
            get:
              summary: Get Live Currency Exchange Rates
              operationId: getRates
              responses:
                '200':
                  description: Dictionary of currency exchange rates
        """
    }

    // MARK: - Monochromatic Swagger UI Documentation Renderer
    private static func generateDocsHTML(req: Request) -> String {
        let baseURL = Environment.get("BASE_URL") ?? ""
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Zippy API & Agent Reference</title>
          <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui.css" />
          <style>
            body {
              margin: 0;
              padding: 0;
              background-color: #000000;
              color: #ffffff;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            }
            .header-bar {
              padding: 24px 32px;
              background: #111111;
              border-bottom: 1px solid #222222;
              display: flex;
              justify-content: space-between;
              align-items: center;
            }
            .header-title {
              font-size: 20px;
              font-weight: 700;
              letter-spacing: -0.5px;
              color: #ffffff;
              margin: 0;
            }
            .header-badge {
              background: #ffffff;
              color: #000000;
              font-size: 11px;
              font-weight: 700;
              padding: 4px 10px;
              border-radius: 9999px;
              text-transform: uppercase;
              letter-spacing: 0.5px;
            }
            .notice-card {
              max-width: 1200px;
              margin: 20px auto 0 auto;
              padding: 16px 24px;
              background: #161616;
              border: 1px solid #333333;
              border-radius: 8px;
              font-size: 13px;
              line-height: 1.5;
              color: #cccccc;
            }
            .notice-card strong {
              color: #ffffff;
            }
            .swagger-ui {
              max-width: 1200px;
              margin: 0 auto;
              padding: 20px;
              filter: invert(0.9) hue-rotate(180deg);
            }
            .swagger-ui .topbar { display: none; }
          </style>
        </head>
        <body>
          <div class="header-bar">
            <h1 class="header-title">ZIPPY // AGENT & VERSIONED REST API</h1>
            <span class="header-badge">OpenAPI 3.1.0 • v1</span>
          </div>

          <div class="notice-card">
            <strong>Architecture Boundary:</strong> This public OpenAPI specification documents the <code>/api/v1</code> endpoints designed for autonomous AI agents, LLMs, and external services. The native Swift iOS client retains its own dedicated human-facing endpoints to keep its black-and-white minimalist interface purely focused on human interaction.
          </div>

          <div id="swagger-ui"></div>

          <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"></script>
          <script src="https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js"></script>
          <script>
            window.onload = function() {
              window.ui = SwaggerUIBundle({
                url: "\(baseURL)/api/v1/openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                  SwaggerUIBundle.presets.apis,
                  SwaggerUIStandalonePreset
                ],
                plugins: [
                  SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "BaseLayout"
              });
            };
          </script>
        </body>
        </html>
        """
    }
}
