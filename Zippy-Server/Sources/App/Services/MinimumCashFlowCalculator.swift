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
    public static func simplifyExpenses(
        participants: [ParticipantDTO],
        expenses: [ExpenseDTO],
        currency: String = "USD"
    ) -> SimplifyExpensesResponse {
        guard !participants.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No participants in group."],
                totalTransferred: 0,
                currency: currency,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        // 1. Calculate net balance in cents for each participant using convertedAmount or amount:
        var netCentsByParticipant: [UUID: Int64] = [:]
        var participantNameLookup: [UUID: String] = [:]

        for p in participants {
            netCentsByParticipant[p.id] = 0
            participantNameLookup[p.id] = p.name
        }

        for expense in expenses {
            let effectiveAmount = expense.convertedAmount ?? expense.amount
            let totalExpenseCents = Int64((effectiveAmount * 100).rounded())
            guard totalExpenseCents > 0 else { continue }

            // Credit the payer
            netCentsByParticipant[expense.paidBy, default: 0] += totalExpenseCents

            // Debit the beneficiaries
            if let customSplits = expense.splits, !customSplits.isEmpty {
                var allocatedCents: Int64 = 0
                for split in customSplits {
                    let splitAmt = split.convertedAmount ?? split.amount ?? 0
                    let shareCents = Int64((splitAmt * 100).rounded())
                    netCentsByParticipant[split.participantId, default: 0] -= shareCents
                    allocatedCents += shareCents
                }
                let remainder = totalExpenseCents - allocatedCents
                if remainder != 0, let firstSplit = customSplits.first {
                    netCentsByParticipant[firstSplit.participantId, default: 0] -= remainder
                }
            } else if let splitParticipantIds = expense.splitWith, !splitParticipantIds.isEmpty {
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

        var balances = participants.map { p in
            ParticipantBalance(
                id: p.id,
                name: p.name,
                netCents: netCentsByParticipant[p.id] ?? 0
            )
        }

        let transfers = solveMinimumCashFlow(balances: &balances, currency: currency)

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
            currency: currency,
            originalExpenseCount: expenses.count,
            transferCount: transfers.count
        )
    }

    /// Optimizes existing split balances into minimal transfers.
    public static func simplifyBalances(
        balances: [PersonBalanceDTO],
        hostParticipantId: UUID? = nil,
        currency: String = "USD"
    ) -> SimplifyExpensesResponse {
        guard !balances.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No balances to simplify."],
                totalTransferred: 0,
                currency: currency,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        let effectiveCurrency = balances.first?.targetCurrency ?? balances.first?.currency ?? currency
        let totalBill = balances.reduce(0.0) { $0 + ($1.convertedTotal ?? $1.total) }
        let hostId = hostParticipantId ?? balances.first?.participantId ?? UUID()

        let participants = balances.map { ParticipantDTO(id: $0.participantId, name: $0.name) }
        let splits = balances.map {
            ExpenseSplitDTO(
                participantId: $0.participantId,
                amount: $0.convertedTotal ?? $0.total,
                currency: effectiveCurrency,
                convertedAmount: $0.convertedTotal ?? $0.total
            )
        }
        let expense = ExpenseDTO(
            id: UUID(),
            title: "Bill Split",
            amount: totalBill,
            currency: effectiveCurrency,
            convertedAmount: totalBill,
            targetCurrency: effectiveCurrency,
            exchangeRate: 1.0,
            paidBy: hostId,
            splitWith: nil,
            splits: splits
        )

        return simplifyExpenses(participants: participants, expenses: [expense], currency: effectiveCurrency)
    }

    /// Optimizes continuous aggregate group net balances across many expenses and settlements
    /// into the fewest direct transfers.
    public static func simplifyGroupBalances(
        members: [ParticipantDTO],
        netBalances: [UUID: Double],
        currency: String = "USD"
    ) -> SimplifyExpensesResponse {
        guard !members.isEmpty else {
            return SimplifyExpensesResponse(
                transfers: [],
                lines: ["No members in group."],
                totalTransferred: 0,
                currency: currency,
                originalExpenseCount: 0,
                transferCount: 0
            )
        }

        var balances = members.map { member in
            let net = netBalances[member.id] ?? 0.0
            let cents = Int64((net * 100).rounded())
            return ParticipantBalance(
                id: member.id,
                name: member.name,
                netCents: cents
            )
        }

        let transfers = solveMinimumCashFlow(balances: &balances, currency: currency)

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
            currency: currency,
            originalExpenseCount: 0,
            transferCount: transfers.count
        )
    }

    // MARK: - Core Minimum Cash Flow Solver

    private static func solveMinimumCashFlow(
        balances: inout [ParticipantBalance],
        currency: String
    ) -> [SimplifiedPaymentDTO] {
        var transfers: [SimplifiedPaymentDTO] = []

        while true {
            guard let maxCreditorIndex = balances.indices.max(by: { balances[$0].netCents < balances[$1].netCents }),
                  balances[maxCreditorIndex].netCents > 0 else {
                break
            }

            guard let maxDebtorIndex = balances.indices.min(by: { balances[$0].netCents < balances[$1].netCents }),
                  balances[maxDebtorIndex].netCents < 0 else {
                break
            }

            let creditCents = balances[maxCreditorIndex].netCents
            let debtCents = -balances[maxDebtorIndex].netCents

            let settleCents = min(creditCents, debtCents)
            guard settleCents > 0 else { break }

            let debtor = balances[maxDebtorIndex]
            let creditor = balances[maxCreditorIndex]
            let transferAmount = Double(settleCents) / 100.0
            let formattedAmount = String(format: "%.2f", transferAmount)
            let lineText = "\(debtor.name) pays \(creditor.name) \(formattedAmount) \(currency)"

            let transfer = SimplifiedPaymentDTO(
                fromId: debtor.id,
                fromName: debtor.name,
                toId: creditor.id,
                toName: creditor.name,
                amount: transferAmount,
                currency: currency,
                originalAmount: transferAmount,
                originalCurrency: currency,
                exchangeRate: 1.0,
                formattedText: lineText
            )
            transfers.append(transfer)

            balances[maxDebtorIndex].netCents += settleCents
            balances[maxCreditorIndex].netCents -= settleCents
        }

        return transfers
    }

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
