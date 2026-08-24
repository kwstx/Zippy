import Vapor

/// Middleware designed specifically for machine clients and autonomous AI agents.
/// Captures agent metadata (`X-Agent-ID`, `X-API-Key`, `User-Agent`) and provides
/// structured, machine-actionable errors if authentication or validation fails.
public struct AgentAuthMiddleware: AsyncMiddleware {
    
    public init() {}

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Extract Agent identity if provided
        let agentId = request.headers.first(name: "X-Agent-ID") ?? "autonomous-agent"
        let apiKey = request.headers.first(name: "X-API-Key") ?? request.headers.bearerAuthorization?.token
        
        // Log agent interaction with versioned API
        request.logger.info("Agent v1 request received", metadata: [
            "agent_id": .string(agentId),
            "endpoint": .string(request.url.path),
            "method": .string(request.method.rawValue),
            "has_api_key": .string(apiKey != nil ? "true" : "false")
        ])
        
        do {
            let response = try await next.respond(to: request)
            // Attach agent protocol response headers
            response.headers.replaceOrAdd(name: "X-Zippy-Agent-Protocol-Version", value: "1.0")
            response.headers.replaceOrAdd(name: "X-Zippy-API-Version", value: "v1")
            return response
        } catch let abort as AbortError {
            let agentError = AgentErrorResponse(
                error: abort.reason,
                code: "HTTP_\(abort.status.code)",
                status: Int(abort.status.code),
                details: nil,
                remediationHint: Self.suggestRemediation(status: abort.status, reason: abort.reason)
            )
            
            let res = Response(status: abort.status)
            try res.content.encode(agentError, as: .json)
            res.headers.replaceOrAdd(name: "X-Zippy-Agent-Protocol-Version", value: "1.0")
            return res
        } catch {
            request.logger.error("Agent unhandled error: \(error)")
            let agentError = AgentErrorResponse(
                error: "Internal agent processing error: \(error.localizedDescription)",
                code: "INTERNAL_SERVER_ERROR",
                status: 500,
                details: nil,
                remediationHint: "Check request payload formatting against the OpenAPI schema at /api/v1/openapi.json"
            )
            let res = Response(status: .internalServerError)
            try res.content.encode(agentError, as: .json)
            res.headers.replaceOrAdd(name: "X-Zippy-Agent-Protocol-Version", value: "1.0")
            return res
        }
    }

    private static func suggestRemediation(status: HTTPStatus, reason: String) -> String {
        switch status {
        case .badRequest:
            return "Verify that all required fields are present and conform to types described in /api/v1/openapi.json."
        case .notFound:
            return "Ensure the requested resource UUID or shareToken exists and is accessible."
        case .unauthorized, .forbidden:
            return "Provide a valid X-API-Key or Authorization Bearer header."
        case .unprocessableEntity:
            return "Payload validation failed. Check item totals, participant IDs, or percentage allocation sum (must equal 100%)."
        default:
            return "Refer to API documentation at /api/v1/docs or retrieve the tool manifest at /api/v1/agent/tools."
        }
    }
}
