import Vapor
import Fluent
import Foundation

struct RecurringExpenseController {

    /// Lists all recurring expense templates for a persistent group.
    @Sendable
    func list(req: Request) async throws -> [RecurringExpenseResponseDTO] {
        guard let groupId = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        let templates = try await RecurringExpenseTemplate.query(on: req.db)
            .filter(\.$groupId == groupId)
            .sort(\.$createdAt, .desc)
            .all()

        return templates.map { template in
            RecurringExpenseResponseDTO(
                id: template.id ?? UUID(),
                groupId: template.groupId,
                title: template.title,
                amount: template.amount,
                currency: template.currency,
                payerId: template.payerId,
                payerName: template.payerName,
                splitMemberIds: template.splitMemberIds,
                splits: template.splits,
                frequency: template.frequency,
                note: template.note,
                isActive: template.isActive,
                nextDueDate: template.nextDueDate,
                lastGeneratedAt: template.lastGeneratedAt,
                occurrencesGenerated: template.occurrencesGenerated,
                createdAt: template.createdAt
            )
        }
    }

    /// Stores a new recurring expense template for a group.
    @Sendable
    func create(req: Request) async throws -> RecurringExpenseResponseDTO {
        guard let groupId = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(groupId, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        let input = try req.content.decode(CreateRecurringExpenseRequest.self)

        let trimmedTitle = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw Abort(.badRequest, reason: "Expense title cannot be empty.")
        }

        guard input.amount > 0 else {
            throw Abort(.badRequest, reason: "Expense amount must be greater than 0.")
        }

        // Determine payer name
        guard let payer = group.members.first(where: { $0.id == input.payerId }) else {
            throw Abort(.badRequest, reason: "Payer is not a member of this group.")
        }

        let baseCurrency = input.currency ?? group.currency ?? "USD"
        let splitMemberIds = input.splitMemberIds ?? group.members.map { $0.id }
        let startDate = input.startDate ?? Date()

        let template = RecurringExpenseTemplate(
            groupId: groupId,
            title: trimmedTitle,
            amount: input.amount,
            currency: baseCurrency,
            payerId: input.payerId,
            payerName: payer.name,
            splitMemberIds: splitMemberIds,
            splits: input.splits ?? [],
            frequency: input.frequency,
            note: input.note,
            isActive: true,
            nextDueDate: startDate,
            lastGeneratedAt: nil,
            occurrencesGenerated: 0
        )

        try await template.save(on: req.db)

        req.logger.info("Created recurring expense template '\(template.title)' (\(template.frequency)) for group \(group.name)")

        // If the start date is now or in the past, process due templates immediately so it reflects right away
        if template.nextDueDate <= Date() {
            _ = try? await RecurringExpenseService.processDueTemplates(
                db: req.db,
                logger: req.logger,
                client: req.client,
                groupId: groupId
            )
        }

        return RecurringExpenseResponseDTO(
            id: template.id ?? UUID(),
            groupId: template.groupId,
            title: template.title,
            amount: template.amount,
            currency: template.currency,
            payerId: template.payerId,
            payerName: template.payerName,
            splitMemberIds: template.splitMemberIds,
            splits: template.splits,
            frequency: template.frequency,
            note: template.note,
            isActive: template.isActive,
            nextDueDate: template.nextDueDate,
            lastGeneratedAt: template.lastGeneratedAt,
            occurrencesGenerated: template.occurrencesGenerated,
            createdAt: template.createdAt
        )
    }

    /// Deletes a recurring expense template.
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let templateId = req.parameters.get("templateId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid template ID.")
        }

        guard let template = try await RecurringExpenseTemplate.find(templateId, on: req.db) else {
            throw Abort(.notFound, reason: "Recurring expense template not found.")
        }

        try await template.delete(on: req.db)
        req.logger.info("Deleted recurring expense template \(templateId)")
        return .noContent
    }

    /// Toggles active state of a recurring template.
    @Sendable
    func toggleActive(req: Request) async throws -> RecurringExpenseResponseDTO {
        guard let templateId = req.parameters.get("templateId", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid template ID.")
        }

        guard let template = try await RecurringExpenseTemplate.find(templateId, on: req.db) else {
            throw Abort(.notFound, reason: "Recurring expense template not found.")
        }

        template.isActive.toggle()
        try await template.save(on: req.db)

        return RecurringExpenseResponseDTO(
            id: template.id ?? UUID(),
            groupId: template.groupId,
            title: template.title,
            amount: template.amount,
            currency: template.currency,
            payerId: template.payerId,
            payerName: template.payerName,
            splitMemberIds: template.splitMemberIds,
            splits: template.splits,
            frequency: template.frequency,
            note: template.note,
            isActive: template.isActive,
            nextDueDate: template.nextDueDate,
            lastGeneratedAt: template.lastGeneratedAt,
            occurrencesGenerated: template.occurrencesGenerated,
            createdAt: template.createdAt
        )
    }

    /// Triggers the cron-like processor on demand for a group or all groups.
    @Sendable
    func processDue(req: Request) async throws -> ProcessRecurringExpensesResultDTO {
        let groupId = req.parameters.get("id", as: UUID.self)

        let generated = try await RecurringExpenseService.processDueTemplates(
            db: req.db,
            logger: req.logger,
            client: req.client,
            groupId: groupId
        )

        let eventDTOs = generated.compactMap { event -> LedgerEventResponseDTO? in
            guard let eventId = event.id else { return nil }
            return LedgerEventResponseDTO(
                id: eventId,
                groupId: event.groupId,
                eventType: event.eventType,
                title: event.title,
                amount: event.amount,
                currency: event.currency ?? "USD",
                convertedAmount: event.convertedAmount,
                targetCurrency: event.targetCurrency,
                exchangeRate: event.exchangeRate,
                payerId: event.payerId,
                payerName: event.payerName,
                payeeId: event.payeeId,
                payeeName: event.payeeName,
                splits: event.splits,
                runningBalanceAfter: nil,
                receiptId: event.receiptId,
                note: event.note,
                createdAt: event.createdAt
            )
        }

        return ProcessRecurringExpensesResultDTO(
            processedCount: generated.count,
            generatedEventsCount: generated.count,
            generatedEvents: eventDTOs
        )
    }
}
