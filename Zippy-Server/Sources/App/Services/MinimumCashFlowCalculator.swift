import Foundation

/// Pure-Swift minimum-cash-flow optimization engine running inside the Vapor process.
/// Reduces complex multi-expense and pairwise debts into the minimal set of direct transfers (at most N-1 transfers).
public enum MinimumCashFlowCalculator {

    /// Represents an internal participant balance in integer cents for exact arithmetic.
    private struct ParticipantBalance {
        let id: UUID
        let name: String
        var netCents: Int64
    }

    /// Optimizes multiple expenses across participants into the fewest direct transfers.
    ///
    /// - Parameters:
    ///   - participants: All participants in the group.
    ///   - expenses: List of expenses, each specifying the payer, amount, and split shares.
    /// - Returns: Minimal list of transfers and formatted text lines.
    public static func simplifyExpenses(
        participants: [ParticipantDTO],
        expenses: [ExpenseDTO]
    ) -> SimplifyExpensesResponse {
        guard !participants.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No participants in group."],
                totalTransferred: 0,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        // 1. Calculate net balance in cents for each participant:
        //    netCents = (cents paid by person) - (cents owed by person)
        var netCentsByParticipant: [UUID: Int64] = [:]
        var participantNameLookup: [UUID: String] = [:]

        for p in participants {
            netCentsByParticipant[p.id] = 0
            participantNameLookup[p.id] = p.name
        }

        for expense in expenses {
            let totalExpenseCents = Int64((expense.amount * 100).rounded())
            guard totalExpenseCents > 0 else { continue }

            // Credit the payer
            netCentsByParticipant[expense.paidBy, default: 0] += totalExpenseCents

            // Debit the beneficiaries
            if let customSplits = expense.splits, !customSplits.isEmpty {
                // Custom split amounts
                var allocatedCents: Int64 = 0
                for split in customSplits {
                    let shareCents = Int64(((split.amount ?? 0) * 100).rounded())
                    netCentsByParticipant[split.participantId, default: 0] -= shareCents
                    allocatedCents += shareCents
                }
                // If any remainder exists, debit the first split participant
                let remainder = totalExpenseCents - allocatedCents
                if remainder != 0, let firstSplit = customSplits.first {
                    netCentsByParticipant[firstSplit.participantId, default: 0] -= remainder
                }
            } else if let splitParticipantIds = expense.splitWith, !splitParticipantIds.isEmpty {
                // Equal split among designated participants
                let count = Int64(splitParticipantIds.count)
                let baseShare = totalExpenseCents / count
                var remainder = totalExpenseCents % count

                for participantId in splitParticipantIds {
                    var share = baseShare
                    if remainder > 0 {
                        share += 1
                        remainder -= 1
                    }
                    netCentsByParticipant[participantId, default: 0] -= share
                }
            } else {
                // Equal split among all participants
                let count = Int64(participants.count)
                let baseShare = totalExpenseCents / count
                var remainder = totalExpenseCents % count

                for p in participants {
                    var share = baseShare
                    if remainder > 0 {
                        share += 1
                        remainder -= 1
                    }
                    netCentsByParticipant[p.id, default: 0] -= share
                }
            }
        }

        // 2. Build participant balance list
        var balances = participants.map { p in
            ParticipantBalance(
                id: p.id,
                name: p.name,
                netCents: netCentsByParticipant[p.id] ?? 0
            )
        }

        // 3. Run pure-Swift Minimum Cash Flow greedy algorithm
        let transfers = solveMinimumCashFlow(balances: &balances)

        // 4. Format black text lines for the frontend
        let lines: [String]
        if transfers.isEmpty {
            lines = ["All balances are settled. No transfers needed."]
        } else {
            lines = transfers.map { $0.formattedText }
        }

        let totalTransferred = transfers.reduce(0.0) { $0 + $1.amount }

        return SimplifyExpensesResponse(
            transfers: transfers,
            lines: lines,
            totalTransferred: round2(totalTransferred),
            originalExpenseCount: expenses.count,
            transferCount: transfers.count
        )
    }

    /// Optimizes existing split balances (e.g. from a receipt or session) into minimal transfers.
    ///
    /// - Parameters:
    ///   - balances: The list of per-person balances.
    ///   - hostParticipantId: The person who originally paid the receipt / bill.
    /// - Returns: Minimal list of transfers and formatted text lines.
    public static func simplifyBalances(
        balances: [PersonBalanceDTO],
        hostParticipantId: UUID? = nil
    ) -> SimplifyExpensesResponse {
        guard !balances.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No balances to simplify."],
                totalTransferred: 0,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        let totalBill = balances.reduce(0.0) { $0 + $1.total }
        let hostId = hostParticipantId ?? balances.first?.participantId ?? UUID()

        // Create a synthetic expense where the host paid the total bill and each person owes their total
        let participants = balances.map { ParticipantDTO(id: $0.participantId, name: $0.name) }
        let splits = balances.map { ExpenseSplitDTO(participantId: $0.participantId, amount: $0.total) }
        let expense = ExpenseDTO(
            id: UUID(),
            title: "Bill Split",
            amount: totalBill,
            paidBy: hostId,
            splitWith: nil,
            splits: splits
        )

        return simplifyExpenses(participants: participants, expenses: [expense])
    }

    /// Optimizes continuous aggregate group net balances across many expenses and settlements
    /// into the fewest direct transfers using the same pure-Swift graph optimization algorithm.
    ///
    /// - Parameters:
    ///   - members: All members in the persistent group.
    ///   - netBalances: Authoritative net balance for each member UUID (+ for owed, - for owes).
    /// - Returns: Minimal set of transfers (at most N-1) and formatted text lines.
    public static func simplifyGroupBalances(
        members: [ParticipantDTO],
        netBalances: [UUID: Double]
    ) -> SimplifyExpensesResponse {
        guard !members.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No members in group."],
                totalTransferred: 0,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        // Build participant balance list with integer cents
        var balances = members.map { member in
            let net = netBalances[member.id] ?? 0.0
            let cents = Int64((net * 100).rounded())
            return ParticipantBalance(
                id: member.id,
                name: member.name,
                netCents: cents
            )
        }

        // Run pure-Swift Minimum Cash Flow greedy algorithm
        let transfers = solveMinimumCashFlow(balances: &balances)

        let lines: [String]
        if transfers.isEmpty {
            lines = ["All balances are settled. No transfers needed."]
        } else {
            lines = transfers.map { $0.formattedText }
        }

        let totalTransferred = transfers.reduce(0.0) { $0 + $1.amount }

        return SimplifyExpensesResponse(
            transfers: transfers,
            lines: lines,
            totalTransferred: round2(totalTransferred),
            originalExpenseCount: 0,
            transferCount: transfers.count
        )
    }

    /// Optimizes member balances into minimal transfers.
    ///
    /// - Parameter memberBalances: Calculated group member balance DTOs.
    /// - Returns: Minimal set of transfers and formatted text lines.
    public static func simplifyMemberBalances(
        memberBalances: [GroupMemberBalanceDTO]
    ) -> SimplifyExpensesResponse {
        guard !memberBalances.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No member balances to simplify."],
                totalTransferred: 0,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        var balances = memberBalances.map { member in
            let cents = Int64((member.netBalance * 100).rounded())
            return ParticipantBalance(
                id: member.participantId,
                name: member.name,
                netCents: cents
            )
        }

        let transfers = solveMinimumCashFlow(balances: &balances)

        let lines: [String]
        if transfers.isEmpty {
            lines = ["All balances are settled. No transfers needed."]
        } else {
            lines = transfers.map { $0.formattedText }
        }

        let totalTransferred = transfers.reduce(0.0) { $0 + $1.amount }

        return SimplifyExpensesResponse(
            transfers: transfers,
            lines: lines,
            totalTransferred: round2(totalTransferred),
            originalExpenseCount: 0,
            transferCount: transfers.count
        )
    }

    // MARK: - Core Minimum Cash Flow Solver

    /// Iterative greedy minimum-cash-flow optimization algorithm.
    /// Runs in O(N log N) or O(N) steps where N is participant count.
    /// At each step:
    ///   - Finds max debtor (person with min net balance < 0).
    ///   - Finds max creditor (person with max net balance > 0).
    ///   - Transfers min(|debt|, credit).
    ///   - Updates net balances until all net balances are 0.
    private static func solveMinimumCashFlow(
        balances: inout [ParticipantBalance]
    ) -> [SimplifiedPaymentDTO] {
        var transfers: [SimplifiedPaymentDTO] = []

        while true {
            // Find index of maximum creditor (largest positive net balance)
            guard let maxCreditorIndex = balances.indices.max(by: { balances[$0].netCents < balances[$1].netCents }),
                  balances[maxCreditorIndex].netCents > 0 else {
                break
            }

            // Find index of maximum debtor (most negative net balance)
            guard let maxDebtorIndex = balances.indices.min(by: { balances[$0].netCents < balances[$1].netCents }),
                  balances[maxDebtorIndex].netCents < 0 else {
                break
            }

            let creditCents = balances[maxCreditorIndex].netCents
            let debtCents = -balances[maxDebtorIndex].netCents

            // Settle minimum of what debtor owes and creditor is owed
            let settleCents = min(creditCents, debtCents)
            guard settleCents > 0 else { break }

            let debtor = balances[maxDebtorIndex]
            let creditor = balances[maxCreditorIndex]
            let transferAmount = Double(settleCents) / 100.0
            let formattedAmount = String(format: "$%.2f", transferAmount)
            let lineText = "\(debtor.name) pays \(creditor.name) \(formattedAmount)"

            let transfer = SimplifiedPaymentDTO(
                fromId: debtor.id,
                fromName: debtor.name,
                toId: creditor.id,
                toName: creditor.name,
                amount: transferAmount,
                formattedText: lineText
            )
            transfers.append(transfer)

            // Update balances
            balances[maxDebtorIndex].netCents += settleCents
            balances[maxCreditorIndex].netCents -= settleCents
        }

        return transfers
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
