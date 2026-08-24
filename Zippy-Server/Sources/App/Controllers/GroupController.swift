import Vapor
import Fluent
import Foundation

struct GroupController {

    /// Lists all persistent groups with their calculated running balances.
    @Sendable
    func list(req: Request) async throws -> [GroupResponseDTO] {
        let groups = try await PersistentGroup.query(on: req.db)
            .sort(\.$createdAt, .desc)
            .all()

        var responses: [GroupResponseDTO] = []

        for group in groups {
            guard let groupId = group.id else { continue }
            let events = try await LedgerEvent.query(on: req.db)
                .filter(\.$groupId == groupId)
                .sort(\.$createdAt, .asc)
                .all()

            let state = GroupLedgerService.computeLedgerState(
                members: group.members,
                events: events
            )

            let lastActivity = events.last?.createdAt ?? group.updatedAt ?? group.createdAt

            responses.append(GroupResponseDTO(
                id: groupId,
                name: group.name,
                members: group.members,
                runningBalance: state.primaryRunningBalance,
                formattedBalance: GroupLedgerService.formatMonochromeBalance(state.primaryRunningBalance),
                memberCount: group.members.count,
                eventCount: events.count,
                lastActivity: lastActivity,
                createdAt: group.createdAt
            ))
        }

        return responses
    }

    /// Creates a new persistent group.
    @Sendable
    func create(req: Request) async throws -> GroupResponseDTO {
        let input = try req.content.decode(CreateGroupRequest.self)

        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Abort(.badRequest, reason: "Group name cannot be empty.")
        }

        // Ensure at least one member or assign default
        var members = input.members
        if members.isEmpty {
            members = [ParticipantDTO(id: UUID(), name: "Me")]
        }

        let newGroup = PersistentGroup(
            name: trimmedName,
            members: members
        )
        try await newGroup.save(on: req.db)

        guard let groupId = newGroup.id else {
            throw Abort(.internalServerError, reason: "Failed to persist group.")
        }

        req.logger.info("Created persistent group '\(newGroup.name)' with ID: \(groupId)")

        return GroupResponseDTO(
            id: groupId,
            name: newGroup.name,
            members: newGroup.members,
            runningBalance: 0.0,
            formattedBalance: "$0.00",
            memberCount: newGroup.members.count,
            eventCount: 0,
            lastActivity: newGroup.createdAt,
            createdAt: newGroup.createdAt
        )
    }

    /// Retrieves a single group summary.
    @Sendable
    func get(req: Request) async throws -> GroupResponseDTO {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        let events = try await LedgerEvent.query(on: req.db)
            .filter(\.$groupId == id)
            .sort(\.$createdAt, .asc)
            .all()

        let state = GroupLedgerService.computeLedgerState(
            members: group.members,
            events: events
        )

        let lastActivity = events.last?.createdAt ?? group.updatedAt ?? group.createdAt

        return GroupResponseDTO(
            id: id,
            name: group.name,
            members: group.members,
            runningBalance: state.primaryRunningBalance,
            formattedBalance: GroupLedgerService.formatMonochromeBalance(state.primaryRunningBalance),
            memberCount: group.members.count,
            eventCount: events.count,
            lastActivity: lastActivity,
            createdAt: group.createdAt
        )
    }

    /// Loads the complete append-only event stream history and member running balances.
    @Sendable
    func getHistory(req: Request) async throws -> GroupLedgerHistoryResponseDTO {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        let events = try await LedgerEvent.query(on: req.db)
            .filter(\.$groupId == id)
            .sort(\.$createdAt, .asc)
            .all()

        let state = GroupLedgerService.computeLedgerState(
            members: group.members,
            events: events
        )

        let groupDTO = GroupResponseDTO(
            id: id,
            name: group.name,
            members: group.members,
            runningBalance: state.primaryRunningBalance,
            formattedBalance: GroupLedgerService.formatMonochromeBalance(state.primaryRunningBalance),
            memberCount: group.members.count,
            eventCount: events.count,
            lastActivity: events.last?.createdAt ?? group.updatedAt ?? group.createdAt,
            createdAt: group.createdAt
        )

        // Convert currentBalances map with String keys for JSON compatibility
        var currentBalancesStringMap: [String: Double] = [:]
        for (key, val) in state.currentBalances {
            currentBalancesStringMap[key.uuidString] = val
        }

        // Return events in reverse chronological order for immediate timeline display
        let sortedHistoryEvents = state.eventResponses.reversed()

        return GroupLedgerHistoryResponseDTO(
            group: groupDTO,
            events: Array(sortedHistoryEvents),
            memberBalances: state.memberBalancesDTO,
            currentBalances: currentBalancesStringMap
        )
    }

    /// Appends a new expense event to the group's ledger stream.
    @Sendable
    func addExpense(req: Request) async throws -> LedgerEventResponseDTO {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        let input = try req.content.decode(AddGroupExpenseRequest.self)

        guard input.amount > 0 else {
            throw Abort(.badRequest, reason: "Expense amount must be greater than zero.")
        }

        let payer = group.members.first(where: { $0.id == input.payerId })
        let payerName = payer?.name ?? "Unknown"

        // Calculate splits
        var finalSplits: [LedgerSplitDTO] = []
        if let explicitSplits = input.splits, !explicitSplits.isEmpty {
            finalSplits = explicitSplits
        } else if let splitMemberIds = input.splitMemberIds, !splitMemberIds.isEmpty {
            let splitCount = Double(splitMemberIds.count)
            let perPersonShare = (input.amount / splitCount * 100).rounded() / 100
            for memberId in splitMemberIds {
                let memberName = group.members.first(where: { $0.id == memberId })?.name ?? "Member"
                finalSplits.append(LedgerSplitDTO(memberId: memberId, memberName: memberName, amount: perPersonShare))
            }
        } else {
            // Default split equally among all members
            let splitCount = max(1.0, Double(group.members.count))
            let perPersonShare = (input.amount / splitCount * 100).rounded() / 100
            for member in group.members {
                finalSplits.append(LedgerSplitDTO(memberId: member.id, memberName: member.name, amount: perPersonShare))
            }
        }

        let event = LedgerEvent(
            groupId: id,
            eventType: "expense",
            title: input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Group Expense" : input.title,
            amount: input.amount,
            payerId: input.payerId,
            payerName: payerName,
            splits: finalSplits,
            receiptId: input.receiptId,
            note: input.note
        )

        try await event.save(on: req.db)
        req.logger.info("Appended expense event '\(event.title)' (\(event.amount)) to group \(id)")

        // Recompute ledger state for authoritative running balance snapshot
        let allEvents = try await LedgerEvent.query(on: req.db)
            .filter(\.$groupId == id)
            .sort(\.$createdAt, .asc)
            .all()

        let state = GroupLedgerService.computeLedgerState(members: group.members, events: allEvents)
        let lastResponse = state.eventResponses.first(where: { $0.id == event.id })

        return lastResponse ?? LedgerEventResponseDTO(
            id: event.id ?? UUID(),
            groupId: id,
            eventType: "expense",
            title: event.title,
            amount: event.amount,
            payerId: event.payerId,
            payerName: event.payerName,
            splits: event.splits,
            runningBalanceAfter: state.primaryRunningBalance,
            receiptId: event.receiptId,
            note: event.note,
            createdAt: event.createdAt
        )
    }

    /// Appends a settlement payment event to the group's ledger stream.
    @Sendable
    func addSettlement(req: Request) async throws -> LedgerEventResponseDTO {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        let input = try req.content.decode(AddGroupSettlementRequest.self)

        guard input.amount > 0 else {
            throw Abort(.badRequest, reason: "Settlement amount must be greater than zero.")
        }

        let payerName = group.members.first(where: { $0.id == input.payerId })?.name ?? "Payer"
        let payeeName = group.members.first(where: { $0.id == input.payeeId })?.name ?? "Payee"

        let title = "Settlement: \(payerName) paid \(payeeName)"

        let event = LedgerEvent(
            groupId: id,
            eventType: "settlement",
            title: title,
            amount: input.amount,
            payerId: input.payerId,
            payerName: payerName,
            payeeId: input.payeeId,
            payeeName: payeeName,
            splits: [],
            note: input.note
        )

        try await event.save(on: req.db)
        req.logger.info("Appended settlement event '\(event.title)' (\(event.amount)) to group \(id)")

        // Recompute ledger state
        let allEvents = try await LedgerEvent.query(on: req.db)
            .filter(\.$groupId == id)
            .sort(\.$createdAt, .asc)
            .all()

        let state = GroupLedgerService.computeLedgerState(members: group.members, events: allEvents)
        let lastResponse = state.eventResponses.first(where: { $0.id == event.id })

        return lastResponse ?? LedgerEventResponseDTO(
            id: event.id ?? UUID(),
            groupId: id,
            eventType: "settlement",
            title: event.title,
            amount: event.amount,
            payerId: event.payerId,
            payerName: event.payerName,
            payeeId: event.payeeId,
            payeeName: event.payeeName,
            splits: [],
            runningBalanceAfter: state.primaryRunningBalance,
            note: event.note,
            createdAt: event.createdAt
        )
    }

    /// Deletes a group and cascades its ledger events.
    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let id = req.parameters.get("id", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid group ID.")
        }

        guard let group = try await PersistentGroup.find(id, on: req.db) else {
            throw Abort(.notFound, reason: "Group not found.")
        }

        try await group.delete(on: req.db)
        return .noContent
    }
}
