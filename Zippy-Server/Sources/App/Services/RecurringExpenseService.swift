import Vapor
import Fluent
import Foundation

/// Engine that processes recurring expense templates and clones them into append-only ledger events.
public enum RecurringExpenseService {

    /// Scans all active recurring templates across groups or for a specific group,
    /// cloning any templates that are currently due into concrete `LedgerEvent` records.
    public static func processDueTemplates(
        db: Database,
        logger: Logger,
        client: Client? = nil,
        groupId: UUID? = nil,
        asOfDate: Date = Date()
    ) async throws -> [LedgerEvent] {
        var query = RecurringExpenseTemplate.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$nextDueDate <= asOfDate)

        if let groupId = groupId {
            query = query.filter(\.$groupId == groupId)
        }

        let dueTemplates = try await query.all()

        guard !dueTemplates.isEmpty else {
            return []
        }

        logger.info("[RECURRING-CRON] Found \(dueTemplates.count) recurring expense templates due for cloning.")

        var generatedEvents: [LedgerEvent] = []

        for template in dueTemplates {
            do {
                guard let group = try await PersistentGroup.find(template.groupId, on: db) else {
                    logger.warning("[RECURRING-CRON] Target group \(template.groupId) not found for template '\(template.title)'.")
                    continue
                }

                let groupCurrency = group.currency ?? "USD"
                let originalCurrency = template.currency

                // Calculate exchange rate and converted amount if currencies differ
                var exchangeRate: Double = 1.0
                var convertedAmount: Double = template.amount

                if originalCurrency.uppercased() != groupCurrency.uppercased() {
                    let rates = await ExchangeRateService.getRates(base: originalCurrency, client: client)
                    if let rate = rates[groupCurrency.uppercased()] {
                        exchangeRate = rate
                        convertedAmount = ((template.amount * rate * 100).rounded()) / 100
                    }
                }

                // Construct Split shares
                var splits: [LedgerSplitDTO] = []
                if !template.splits.isEmpty {
                    splits = template.splits
                } else if !template.splitMemberIds.isEmpty {
                    let splitCount = Double(template.splitMemberIds.count)
                    let perPersonAmount = ((template.amount / splitCount) * 100).rounded() / 100
                    let perPersonConverted = ((convertedAmount / splitCount) * 100).rounded() / 100

                    for memberId in template.splitMemberIds {
                        let memberName = group.members.first(where: { $0.id == memberId })?.name ?? "Member"
                        splits.append(LedgerSplitDTO(
                            memberId: memberId,
                            memberName: memberName,
                            amount: perPersonAmount,
                            currency: originalCurrency,
                            convertedAmount: perPersonConverted
                        ))
                    }
                } else if !group.members.isEmpty {
                    let splitCount = Double(group.members.count)
                    let perPersonAmount = ((template.amount / splitCount) * 100).rounded() / 100
                    let perPersonConverted = ((convertedAmount / splitCount) * 100).rounded() / 100

                    for member in group.members {
                        splits.append(LedgerSplitDTO(
                            memberId: member.id,
                            memberName: member.name,
                            amount: perPersonAmount,
                            currency: originalCurrency,
                            convertedAmount: perPersonConverted
                        ))
                    }
                }

                // Verify payer name from group roster if changed
                let payerName = group.members.first(where: { $0.id == template.payerId })?.name ?? template.payerName

                // Format recurring note
                let freqLabel = template.frequency.capitalized
                let recurringTag = "[Recurring: \(freqLabel)]"
                let fullNote: String
                if let customNote = template.note, !customNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fullNote = "\(recurringTag) \(customNote)"
                } else {
                    fullNote = recurringTag
                }

                // Create the cloned ledger event
                let clonedEvent = LedgerEvent(
                    groupId: template.groupId,
                    eventType: "expense",
                    title: template.title,
                    amount: template.amount,
                    currency: originalCurrency,
                    targetCurrency: groupCurrency,
                    exchangeRate: exchangeRate,
                    convertedAmount: convertedAmount,
                    payerId: template.payerId,
                    payerName: payerName,
                    splits: splits,
                    note: fullNote,
                    createdAt: template.nextDueDate <= asOfDate ? template.nextDueDate : asOfDate
                )

                try await clonedEvent.save(on: db)
                generatedEvents.append(clonedEvent)

                // Advance template state
                let previousDue = template.nextDueDate
                template.lastGeneratedAt = asOfDate
                template.occurrencesGenerated += 1
                template.nextDueDate = RecurringExpenseTemplate.computeNextDueDate(from: previousDue, frequency: template.frequency)

                // If nextDueDate is still past asOfDate (e.g. server catch-up), advance forward
                while template.nextDueDate <= asOfDate {
                    template.nextDueDate = RecurringExpenseTemplate.computeNextDueDate(from: template.nextDueDate, frequency: template.frequency)
                }

                try await template.save(on: db)

                logger.info("[RECURRING-CRON] Cloned recurring expense '\(template.title)' (\(template.amount) \(originalCurrency)) for group '\(group.name)' -> Next due: \(template.nextDueDate)")
            } catch {
                logger.error("[RECURRING-CRON] Failed to clone template ID \(template.id?.uuidString ?? "unknown"): \(error)")
            }
        }

        return generatedEvents
    }
}
