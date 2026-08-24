import Vapor
import Fluent
import Foundation

struct SplitController {

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
        if let existing = try await SplitSession.query(on: req.db)
            .filter(\.$receiptId == input.receiptId)
            .first() {
            existing.participants = input.participants
            existing.assignments = input.assignments
            existing.balances = balances
            try await existing.update(on: req.db)
            session = existing
        } else {
            let newSession = SplitSession(
                receiptId: input.receiptId,
                participants: input.participants,
                assignments: input.assignments,
                balances: balances
            )
            try await newSession.save(on: req.db)
            session = newSession
        }

        req.logger.info("Split session \(session.id?.uuidString ?? "?") saved for receipt \(input.receiptId)")

        return SplitSessionResponse(
            id: session.id!,
            receiptId: session.receiptId,
            participants: session.participants,
            balances: session.balances,
            receiptTotal: receipt.total,
            shareableURL: "/api/splits/\(session.id!.uuidString)",
            createdAt: session.createdAt
        )
    }

    /// Retrieves a previously saved split session (shareable link endpoint).
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

        return SplitSessionResponse(
            id: session.id!,
            receiptId: session.receiptId,
            participants: session.participants,
            balances: session.balances,
            receiptTotal: receipt?.total ?? 0,
            shareableURL: "/api/splits/\(session.id!.uuidString)",
            createdAt: session.createdAt
        )
    }
}
