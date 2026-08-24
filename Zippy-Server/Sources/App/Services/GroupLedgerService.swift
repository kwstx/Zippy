import Foundation

/// Pure logic calculation service for replaying append-only ledger event streams
/// and maintaining running balances across persistent groups.
public enum GroupLedgerService {

    /// Structure representing a calculated snapshot of member balances at a point in the event stream.
    public struct LedgerSnapshot {
        public var memberBalances: [UUID: Double]
        public var totalVolume: Double
    }

    /// Formats a balance as a clean single monochrome figure.
    /// Examples: "+$42.50", "-$15.00", "$0.00"
    public static func formatMonochromeBalance(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if abs(rounded) < 0.005 {
            return "$0.00"
        } else if rounded > 0 {
            return String(format: "+$%.2f", rounded)
        } else {
            return String(format: "-$%.2f", abs(rounded))
        }
    }

    /// Replays the append-only event stream in strict chronological order and calculates
    /// the authoritative running balances for all members and event snapshots.
    public static func computeLedgerState(
        members: [ParticipantDTO],
        events: [LedgerEvent]
    ) -> (
        currentBalances: [UUID: Double],
        memberBalancesDTO: [GroupMemberBalanceDTO],
        eventResponses: [LedgerEventResponseDTO],
        primaryRunningBalance: Double
    ) {
        // Initialize all member balances to zero
        var runningBalances: [UUID: Double] = [:]
        for member in members {
            runningBalances[member.id] = 0.0
        }

        // Sort events chronologically (strict append-only order)
        let sortedEvents = events.sorted { (a, b) -> Bool in
            let dateA = a.createdAt ?? Date.distantPast
            let dateB = b.createdAt ?? Date.distantPast
            if dateA == dateB {
                return (a.id?.uuidString ?? "") < (b.id?.uuidString ?? "")
            }
            return dateA < dateB
        }

        var eventResponses: [LedgerEventResponseDTO] = []

        for event in sortedEvents {
            let eventType = event.eventType.lowercased()

            if eventType == "expense" {
                let payerId = event.payerId
                let totalAmount = event.amount

                // Record allocations
                var totalAllocated = 0.0
                for split in event.splits {
                    let memberId = split.memberId
                    let splitAmount = split.amount
                    totalAllocated += splitAmount

                    // Each member's net balance decreases by what they owe
                    let current = runningBalances[memberId] ?? 0.0
                    runningBalances[memberId] = current - splitAmount
                }

                // If splits didn't cover the full amount or splits were empty, distribute remaining
                let remaining = totalAmount - totalAllocated
                if remaining > 0.001 && !members.isEmpty {
                    let share = remaining / Double(members.count)
                    for member in members {
                        let current = runningBalances[member.id] ?? 0.0
                        runningBalances[member.id] = current - share
                    }
                }

                // Payer's net balance increases by total amount paid
                let currentPayerBalance = runningBalances[payerId] ?? 0.0
                runningBalances[payerId] = currentPayerBalance + totalAmount

            } else if eventType == "settlement" {
                let payerId = event.payerId
                let amount = event.amount

                // Payer gave money to settle debt -> their balance increases (+amount)
                let currentPayer = runningBalances[payerId] ?? 0.0
                runningBalances[payerId] = currentPayer + amount

                // Payee received money -> their balance decreases (-amount)
                if let payeeId = event.payeeId {
                    let currentPayee = runningBalances[payeeId] ?? 0.0
                    runningBalances[payeeId] = currentPayee - amount
                }
            }

            // Snapshot the primary running balance after this event
            // (Perspective of the first member in the roster, or overall payer)
            let snapshotBalance: Double
            if let primaryMember = members.first {
                snapshotBalance = runningBalances[primaryMember.id] ?? 0.0
            } else {
                snapshotBalance = runningBalances[event.payerId] ?? 0.0
            }

            let responseDTO = LedgerEventResponseDTO(
                id: event.id ?? UUID(),
                groupId: event.groupId,
                eventType: event.eventType,
                title: event.title,
                amount: event.amount,
                payerId: event.payerId,
                payerName: event.payerName,
                payeeId: event.payeeId,
                payeeName: event.payeeName,
                splits: event.splits,
                runningBalanceAfter: snapshotBalance,
                receiptId: event.receiptId,
                note: event.note,
                createdAt: event.createdAt
            )
            eventResponses.append(responseDTO)
        }

        // Build member balances DTO
        var memberDTOs: [GroupMemberBalanceDTO] = []
        for member in members {
            let balance = runningBalances[member.id] ?? 0.0
            memberDTOs.append(GroupMemberBalanceDTO(
                participantId: member.id,
                name: member.name,
                netBalance: balance,
                formattedBalance: formatMonochromeBalance(balance)
            ))
        }

        // Primary running balance figure for the group summary row
        let primaryBalance: Double
        if let primaryMember = members.first {
            primaryBalance = runningBalances[primaryMember.id] ?? 0.0
        } else {
            // Aggregate net positive balance or zero
            primaryBalance = memberDTOs.first?.netBalance ?? 0.0
        }

        return (
            currentBalances: runningBalances,
            memberBalancesDTO: memberDTOs,
            eventResponses: eventResponses,
            primaryRunningBalance: primaryBalance
        )
    }
}
