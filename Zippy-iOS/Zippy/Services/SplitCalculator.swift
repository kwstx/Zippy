// MARK: - SplitCalculator.swift

import Foundation

/// Pure arithmetic engine that computes per-person balances across all flexible split methods.
/// Called synchronously on the main thread for instant UI updates.
enum SplitCalculator {

    /// Computes per-person balances based on the active split method.
    static func calculate(
        method: SplitMethod = .itemized,
        items: [ReceiptItem],
        participants: [Participant],
        assignments: [Int: Set<UUID>] = [:],
        percentageAllocations: [UUID: Double] = [:],
        shareAllocations: [UUID: Double] = [:],
        exactAllocations: [UUID: Double] = [:],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> SplitResult {
        guard !participants.isEmpty else {
            return SplitResult(balances: [], assignedSubtotal: 0)
        }

        let effectiveSubtotal = subtotal > 0 ? subtotal : items.reduce(0.0) { $0 + $1.price }
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
                assignments: assignments,
                tax: tax,
                tip: tip
            )

        case .percentage:
            return calculatePercentage(
                participants: participants,
                percentages: percentageAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )

        case .shares:
            return calculateShares(
                participants: participants,
                shares: shareAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )

        case .exact:
            return calculateExact(
                participants: participants,
                exactAmounts: exactAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal
            )
        }
    }

    /// Legacy overload for itemized calculations.
    static func calculate(
        items: [ReceiptItem],
        participants: [Participant],
        assignments: [Int: Set<UUID>],
        tax: Double,
        tip: Double
    ) -> SplitResult {
        let subtotal = items.reduce(0.0) { $0 + $1.price }
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
        participants: [Participant],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else { return SplitResult(balances: [], assignedSubtotal: 0) }

        let perPersonSubtotal = round2(subtotal / count)
        let perPersonTax = round2(tax / count)
        let perPersonTip = round2(tip / count)
        let perPersonTotal = round2(perPersonSubtotal + perPersonTax + perPersonTip)

        var balances: [PersonBalance] = participants.map { p in
            PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: perPersonSubtotal,
                taxShare: perPersonTax,
                tipShare: perPersonTip,
                total: perPersonTotal
            )
        }

        let expectedTotal = round2(subtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
        let remainder = round2(expectedTotal - actualTotal)
        if remainder != 0, !balances.isEmpty {
            let maxIdx = balances.indices.max(by: { balances[$0].total < balances[$1].total }) ?? 0
            let b = balances[maxIdx]
            balances[maxIdx] = PersonBalance(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: round2(b.total + remainder)
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: round2(subtotal))
    }

    // MARK: - 2. Itemized Split

    private static func calculateItemized(
        items: [ReceiptItem],
        participants: [Participant],
        assignments: [Int: Set<UUID>],
        tax: Double,
        tip: Double
    ) -> SplitResult {
        guard !participants.isEmpty else {
            return SplitResult(balances: [], assignedSubtotal: 0)
        }

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

        let groupSubtotal = personSubtotals.values.reduce(0, +)

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

        let expectedTotal = round2(groupSubtotal + tax + tip)
        let actualTotal = balances.reduce(0.0) { $0 + $1.total }
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

    // MARK: - 3. Percentage Split

    private static func calculatePercentage(
        participants: [Participant],
        percentages: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else { return SplitResult(balances: [], assignedSubtotal: 0) }

        var userPercentages: [UUID: Double] = [:]
        var totalSpecifiedPct: Double = 0
        for p in participants {
            if let val = percentages[p.id], val >= 0 {
                userPercentages[p.id] = val
                totalSpecifiedPct += val
            }
        }

        if totalSpecifiedPct <= 0 {
            for p in participants {
                userPercentages[p.id] = 100.0 / count
            }
            totalSpecifiedPct = 100.0
        }

        var balances: [PersonBalance] = participants.map { p in
            let pct = userPercentages[p.id] ?? (100.0 / count)
            let ratio = totalSpecifiedPct > 0 ? (pct / totalSpecifiedPct) : (1.0 / count)
            let pSubtotal = round2(ratio * subtotal)
            let pTax = round2(ratio * tax)
            let pTip = round2(ratio * tip)
            let pTotal = round2(pSubtotal + pTax + pTip)
            return PersonBalance(
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
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId, name: b.name,
                itemsSubtotal: b.itemsSubtotal, taxShare: b.taxShare,
                tipShare: b.tipShare, total: round2(b.total + remainder)
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: round2(subtotal))
    }

    // MARK: - 4. Shares Split

    private static func calculateShares(
        participants: [Participant],
        shares: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else { return SplitResult(balances: [], assignedSubtotal: 0) }

        var userShares: [UUID: Double] = [:]
        var totalShares: Double = 0
        for p in participants {
            let shareVal = max(0, shares[p.id] ?? 1.0)
            userShares[p.id] = shareVal
            totalShares += shareVal
        }

        if totalShares <= 0 {
            totalShares = count
            for p in participants {
                userShares[p.id] = 1.0
            }
        }

        var balances: [PersonBalance] = participants.map { p in
            let share = userShares[p.id] ?? 1.0
            let ratio = share / totalShares
            let pSubtotal = round2(ratio * subtotal)
            let pTax = round2(ratio * tax)
            let pTip = round2(ratio * tip)
            let pTotal = round2(pSubtotal + pTax + pTip)
            return PersonBalance(
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
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId, name: b.name,
                itemsSubtotal: b.itemsSubtotal, taxShare: b.taxShare,
                tipShare: b.tipShare, total: round2(b.total + remainder)
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: round2(subtotal))
    }

    // MARK: - 5. Exact Split

    private static func calculateExact(
        participants: [Participant],
        exactAmounts: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else { return SplitResult(balances: [], assignedSubtotal: 0) }

        let defaultPerPerson = count > 0 ? round2(total / count) : 0.0

        let balances: [PersonBalance] = participants.map { p in
            let pTotal = exactAmounts[p.id] ?? defaultPerPerson
            let ratio = total > 0 ? (pTotal / total) : (1.0 / count)
            let pSubtotal = round2(pTotal * (total > 0 ? (subtotal / total) : 1.0))
            let pTax = round2(pTotal * (total > 0 ? (tax / total) : 0.0))
            let pTip = round2(pTotal - pSubtotal - pTax)
            return PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: round2(pTotal)
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: round2(subtotal))
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
