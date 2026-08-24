// MARK: - SplitCalculator.swift

import Foundation

/// Pure arithmetic engine that computes per-person balances from item assignments.
/// Called synchronously on the main thread for instant UI updates.
enum SplitCalculator {

    /// Computes how much each participant owes based on their assigned items.
    ///
    /// - Parameters:
    ///   - items: The receipt line items.
    ///   - participants: All people splitting the bill.
    ///   - assignments: Mapping of item index → set of participant IDs assigned to that item.
    ///   - tax: The receipt's tax amount.
    ///   - tip: The receipt's tip amount.
    /// - Returns: A `SplitResult` with per-person balances that sum correctly.
    static func calculate(
        items: [ReceiptItem],
        participants: [Participant],
        assignments: [Int: Set<UUID>],
        tax: Double,
        tip: Double
    ) -> SplitResult {
        guard !participants.isEmpty else {
            return SplitResult(balances: [], assignedSubtotal: 0)
        }

        // 1. Accumulate each person's share of assigned items
        var personSubtotals: [UUID: Double] = [:]
        for participant in participants {
            personSubtotals[participant.id] = 0
        }

        for (index, item) in items.enumerated() {
            guard let assignees = assignments[index], !assignees.isEmpty else { continue }
            let share = item.price / Double(assignees.count)
            for participantId in assignees where personSubtotals[participantId] != nil {
                personSubtotals[participantId, default: 0] += share
            }
        }

        // 2. Group subtotal = sum of all assigned item shares
        let groupSubtotal = personSubtotals.values.reduce(0, +)

        // 3. Build per-person balances with proportional tax & tip
        var balances: [PersonBalance] = participants.map { participant in
            let subtotal = personSubtotals[participant.id] ?? 0
            guard groupSubtotal > 0 else {
                return PersonBalance(
                    participantId: participant.id, name: participant.name,
                    itemsSubtotal: 0, taxShare: 0, tipShare: 0, total: 0
                )
            }
            let ratio = subtotal / groupSubtotal
            let taxShare = round2(ratio * tax)
            let tipShare = round2(ratio * tip)
            let personTotal = round2(subtotal + taxShare + tipShare)
            return PersonBalance(
                participantId: participant.id, name: participant.name,
                itemsSubtotal: round2(subtotal), taxShare: taxShare,
                tipShare: tipShare, total: personTotal
            )
        }

        // 4. Remainder adjustment — absorb rounding error into the largest balance
        let expectedTotal = round2(groupSubtotal + tax + tip)
        let actualTotal = balances.reduce(0) { $0 + $1.total }
        let remainder = round2(expectedTotal - actualTotal)
        if remainder != 0,
           let maxIndex = balances.indices.max(by: { balances[$0].total < balances[$1].total }) {
            let b = balances[maxIndex]
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId, name: b.name,
                itemsSubtotal: b.itemsSubtotal, taxShare: b.taxShare,
                tipShare: b.tipShare, total: round2(b.total + remainder)
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: round2(groupSubtotal))
    }

    /// Optimizes balances into the fewest direct transfers using the minimum-cash-flow algorithm.
    static func simplify(balances: [PersonBalance], hostId: UUID? = nil) -> [SimplifiedPayment] {
        guard !balances.isEmpty else { return [] }

        struct NetParticipant {
            let id: UUID
            let name: String
            var netCents: Int64
        }

        let host = hostId ?? balances.first?.participantId ?? UUID()
        let totalBillCents = Int64((balances.reduce(0.0) { $0 + $1.total } * 100).rounded())

        var netMap: [UUID: Int64] = [:]
        for b in balances {
            let owedCents = Int64((b.total * 100).rounded())
            netMap[b.participantId, default: 0] -= owedCents
        }
        netMap[host, default: 0] += totalBillCents

        var participants = balances.map { b in
            NetParticipant(id: b.participantId, name: b.name, netCents: netMap[b.participantId] ?? 0)
        }

        var transfers: [SimplifiedPayment] = []

        while true {
            guard let maxCreditorIdx = participants.indices.max(by: { participants[$0].netCents < participants[$1].netCents }),
                  participants[maxCreditorIdx].netCents > 0 else {
                break
            }

            guard let maxDebtorIdx = participants.indices.min(by: { participants[$0].netCents < participants[$1].netCents }),
                  participants[maxDebtorIdx].netCents < 0 else {
                break
            }

            let credit = participants[maxCreditorIdx].netCents
            let debt = -participants[maxDebtorIdx].netCents
            let settle = min(credit, debt)
            guard settle > 0 else { break }

            let debtor = participants[maxDebtorIdx]
            let creditor = participants[maxCreditorIdx]
            let amount = Double(settle) / 100.0
            let formattedAmount = String(format: "$%.2f", amount)
            let line = "\(debtor.name) pays \(creditor.name) \(formattedAmount)"

            transfers.append(SimplifiedPayment(
                fromId: debtor.id,
                fromName: debtor.name,
                toId: creditor.id,
                toName: creditor.name,
                amount: amount,
                formattedText: line
            ))

            participants[maxDebtorIdx].netCents += settle
            participants[maxCreditorIdx].netCents -= settle
        }

        return transfers
    }

    // MARK: - Private

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

