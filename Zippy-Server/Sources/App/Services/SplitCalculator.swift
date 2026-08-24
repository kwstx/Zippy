import Foundation

/// Authoritative server-side split calculator.
/// Produces identical results to the iOS client-side SplitCalculator across all 5 flexible split methods:
/// - Equal
/// - Itemized
/// - Percentage
/// - Shares
/// - Exact
enum SplitCalculator {

    /// Unified split calculation dispatching to the selected split method.
    static func calculate(
        method: SplitMethod = .itemized,
        items: [ReceiptItem],
        receiptSubtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        participants: [ParticipantDTO],
        assignments: [String: [UUID]]? = nil,
        percentageAllocations: [String: Double]? = nil,
        shareAllocations: [String: Double]? = nil,
        exactAllocations: [String: Double]? = nil
    ) -> [PersonBalanceDTO] {
        guard !participants.isEmpty else { return [] }

        let effectiveSubtotal = receiptSubtotal > 0 ? receiptSubtotal : items.reduce(0.0) { $0 + $1.price }
        let effectiveTotal = total > 0 ? total : (effectiveSubtotal + tax + tip)

        switch method {
        case .equal:
            return calculateEqual(
                participants: participants,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )

        case .itemized:
            return calculateItemized(
                items: items,
                participants: participants,
                assignments: assignments ?? [:],
                tax: tax,
                tip: tip
            )

        case .percentage:
            return calculatePercentage(
                participants: participants,
                percentages: percentageAllocations ?? [:],
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )

        case .shares:
            return calculateShares(
                participants: participants,
                shares: shareAllocations ?? [:],
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )

        case .exact:
            return calculateExact(
                participants: participants,
                exactAmounts: exactAllocations ?? [:],
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )
        }
    }

    /// Legacy convenience signature maintaining backwards compatibility.
    static func calculate(
        items: [ReceiptItem],
        participants: [ParticipantDTO],
        assignments: [String: [UUID]],
        tax: Double,
        tip: Double
    ) -> [PersonBalanceDTO] {
        let itemsSubtotal = items.reduce(0.0) { $0 + $1.price }
        return calculateItemized(
            items: items,
            participants: participants,
            assignments: assignments,
            tax: tax,
            tip: tip
        )
    }

    // MARK: - 1. Equal Split

    private static func calculateEqual(
        participants: [ParticipantDTO],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> [PersonBalanceDTO] {
        let count = Double(participants.count)
        guard count > 0 else { return [] }

        let perPersonSubtotal = round2(subtotal / count)
        let perPersonTax = round2(tax / count)
        let perPersonTip = round2(tip / count)
        let perPersonTotal = round2(perPersonSubtotal + perPersonTax + perPersonTip)

        var balances: [PersonBalanceDTO] = participants.map { p in
            PersonBalanceDTO(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: perPersonSubtotal,
                taxShare: perPersonTax,
                tipShare: perPersonTip,
                total: perPersonTotal
            )
        }

        // Remainder adjustment on total
        let expectedTotal = round2(subtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
        let remainder = round2(expectedTotal - actualTotal)
        if remainder != 0, !balances.isEmpty {
            let maxIdx = balances.indices.max(by: { balances[$0].total < balances[$1].total }) ?? 0
            let b = balances[maxIdx]
            balances[maxIdx] = PersonBalanceDTO(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: round2(b.total + remainder)
            )
        }

        return balances
    }

    // MARK: - 2. Itemized Split

    private static func calculateItemized(
        items: [ReceiptItem],
        participants: [ParticipantDTO],
        assignments: [String: [UUID]],
        tax: Double,
        tip: Double
    ) -> [PersonBalanceDTO] {
        guard !participants.isEmpty else { return [] }

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

        let groupSubtotal = personSubtotals.values.reduce(0, +)

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

        let expectedTotal = round2(groupSubtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
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

    // MARK: - 3. Percentage Split

    private static func calculatePercentage(
        participants: [ParticipantDTO],
        percentages: [String: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> [PersonBalanceDTO] {
        let count = Double(participants.count)
        guard count > 0 else { return [] }

        // Determine percentage per participant
        var userPercentages: [UUID: Double] = [:]
        var totalSpecifiedPct: Double = 0
        for p in participants {
            if let val = percentages[p.id.uuidString], val >= 0 {
                userPercentages[p.id] = val
                totalSpecifiedPct += val
            }
        }

        // If no percentages provided or sum is 0, default to equal division (100% / N)
        if totalSpecifiedPct <= 0 {
            for p in participants {
                userPercentages[p.id] = 100.0 / count
            }
            totalSpecifiedPct = 100.0
        }

        var balances: [PersonBalanceDTO] = participants.map { p in
            let pct = userPercentages[p.id] ?? (100.0 / count)
            let ratio = totalSpecifiedPct > 0 ? (pct / totalSpecifiedPct) : (1.0 / count)
            let pSubtotal = round2(ratio * subtotal)
            let pTax = round2(ratio * tax)
            let pTip = round2(ratio * tip)
            let pTotal = round2(pSubtotal + pTax + pTip)
            return PersonBalanceDTO(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: pTotal
            )
        }

        // Remainder adjustment
        let expectedTotal = round2(subtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
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

    // MARK: - 4. Shares Split

    private static func calculateShares(
        participants: [ParticipantDTO],
        shares: [String: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> [PersonBalanceDTO] {
        let count = Double(participants.count)
        guard count > 0 else { return [] }

        var userShares: [UUID: Double] = [:]
        var totalShares: Double = 0
        for p in participants {
            let shareVal = max(0, shares[p.id.uuidString] ?? 1.0)
            userShares[p.id] = shareVal
            totalShares += shareVal
        }

        if totalShares <= 0 {
            totalShares = count
            for p in participants {
                userShares[p.id] = 1.0
            }
        }

        var balances: [PersonBalanceDTO] = participants.map { p in
            let share = userShares[p.id] ?? 1.0
            let ratio = share / totalShares
            let pSubtotal = round2(ratio * subtotal)
            let pTax = round2(ratio * tax)
            let pTip = round2(ratio * tip)
            let pTotal = round2(pSubtotal + pTax + pTip)
            return PersonBalanceDTO(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: pTotal
            )
        }

        let expectedTotal = round2(subtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
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

    // MARK: - 5. Exact Split

    private static func calculateExact(
        participants: [ParticipantDTO],
        exactAmounts: [String: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> [PersonBalanceDTO] {
        let count = Double(participants.count)
        guard count > 0 else { return [] }

        let defaultPerPerson = count > 0 ? round2(total / count) : 0.0

        return participants.map { p in
            let pTotal = exactAmounts[p.id.uuidString] ?? defaultPerPerson
            let ratio = total > 0 ? (pTotal / total) : (1.0 / count)
            let pSubtotal = round2(pTotal * (total > 0 ? (subtotal / total) : 1.0))
            let pTax = round2(pTotal * (total > 0 ? (tax / total) : 0.0))
            let pTip = round2(pTotal - pSubtotal - pTax)
            return PersonBalanceDTO(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: round2(pTotal)
            )
        }
    }

    // MARK: - Helper

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
