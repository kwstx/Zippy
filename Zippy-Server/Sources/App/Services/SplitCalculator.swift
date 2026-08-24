import Foundation

/// Authoritative server-side split calculator.
/// Produces identical results to the iOS client-side SplitCalculator.
enum SplitCalculator {

    /// Computes per-person balances from item assignments.
    ///
    /// - Parameters:
    ///   - items: The receipt's line items.
    ///   - participants: All participants in the split.
    ///   - assignments: Item index (string key) → array of participant UUIDs.
    ///   - tax: Receipt tax amount.
    ///   - tip: Receipt tip amount.
    /// - Returns: Array of per-person balance breakdowns.
    static func calculate(
        items: [ReceiptItem],
        participants: [ParticipantDTO],
        assignments: [String: [UUID]],
        tax: Double,
        tip: Double
    ) -> [PersonBalanceDTO] {
        guard !participants.isEmpty else { return [] }

        // 1. Accumulate each person's share of assigned items
        var personSubtotals: [UUID: Double] = [:]
        for participant in participants {
            personSubtotals[participant.id] = 0
        }

        for (index, item) in items.enumerated() {
            let key = String(index)
            guard let assignees = assignments[key], !assignees.isEmpty else { continue }
            let share = item.price / Double(assignees.count)
            for participantId in assignees where personSubtotals[participantId] != nil {
                personSubtotals[participantId, default: 0] += share
            }
        }

        // 2. Group subtotal
        let groupSubtotal = personSubtotals.values.reduce(0, +)

        // 3. Build per-person balances
        var balances: [PersonBalanceDTO] = participants.map { participant in
            let subtotal = personSubtotals[participant.id] ?? 0
            guard groupSubtotal > 0 else {
                return PersonBalanceDTO(
                    participantId: participant.id, name: participant.name,
                    itemsSubtotal: 0, taxShare: 0, tipShare: 0, total: 0
                )
            }
            let ratio = subtotal / groupSubtotal
            let taxShare = round2(ratio * tax)
            let tipShare = round2(ratio * tip)
            let personTotal = round2(subtotal + taxShare + tipShare)
            return PersonBalanceDTO(
                participantId: participant.id, name: participant.name,
                itemsSubtotal: round2(subtotal), taxShare: taxShare,
                tipShare: tipShare, total: personTotal
            )
        }

        // 4. Remainder adjustment
        let expectedTotal = round2(groupSubtotal + tax + tip)
        let actualTotal = balances.reduce(0) { $0 + $1.total }
        let remainder = round2(expectedTotal - actualTotal)
        if remainder != 0,
           let maxIndex = balances.indices.max(by: { balances[$0].total < balances[$1].total }) {
            let b = balances[maxIndex]
            balances[maxIndex] = PersonBalanceDTO(
                participantId: b.participantId, name: b.name,
                itemsSubtotal: b.itemsSubtotal, taxShare: b.taxShare,
                tipShare: b.tipShare, total: round2(b.total + remainder)
            )
        }

        return balances
    }

    // MARK: - Private

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
