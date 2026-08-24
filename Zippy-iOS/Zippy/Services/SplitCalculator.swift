// MARK: - SplitCalculator.swift

import Foundation

/// Pure arithmetic engine that computes per-person balances across all flexible split methods.
/// Called synchronously on the main thread for instant UI updates.
/// Supports multi-currency calculations storing both original and converted amounts.
enum SplitCalculator {

    /// Computes per-person balances based on the active split method with multi-currency support.
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
        total: Double,
        currency: String = "USD",
        targetCurrency: String = "USD",
        exchangeRate: Double = 1.0
    ) -> SplitResult {
        guard !participants.isEmpty else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
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
                total: effectiveTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )

        case .itemized:
            return calculateItemized(
                items: items,
                participants: participants,
                assignments: assignments,
                tax: tax,
                tip: tip,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )

        case .percentage:
            return calculatePercentage(
                participants: participants,
                percentages: percentageAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )

        case .shares:
            return calculateShares(
                participants: participants,
                shares: shareAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )

        case .exact:
            return calculateExact(
                participants: participants,
                exactAmounts: exactAllocations,
                subtotal: effectiveSubtotal,
                tax: tax,
                tip: tip,
                total: effectiveTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
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
        return calculateItemized(
            items: items,
            participants: participants,
            assignments: assignments,
            tax: tax,
            tip: tip,
            currency: "USD",
            targetCurrency: "USD",
            exchangeRate: 1.0
        )
    }

    // MARK: - 1. Equal Split

    private static func calculateEqual(
        participants: [Participant],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        currency: String,
        targetCurrency: String,
        exchangeRate: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
        }

        let perPersonSubtotal = (subtotal / count * 100).rounded() / 100
        let perPersonTax = (tax / count * 100).rounded() / 100
        let perPersonTip = (tip / count * 100).rounded() / 100
        let perPersonTotal = (perPersonSubtotal + perPersonTax + perPersonTip * 100).rounded() / 100

        var balances = participants.map { p in
            PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: perPersonSubtotal,
                taxShare: perPersonTax,
                tipShare: perPersonTip,
                total: perPersonTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )
        }

        // Remainder adjustment
        let expectedTotal = ((subtotal + tax + tip) * 100).rounded() / 100
        let actualTotal = ((balances.reduce(0.0) { $0 + $1.total }) * 100).rounded() / 100
        let remainder = ((expectedTotal - actualTotal) * 100).rounded() / 100
        if remainder != 0, !balances.isEmpty {
            let maxIdx = balances.indices.max(by: { balances[$0].total < balances[$1].total }) ?? 0
            let b = balances[maxIdx]
            balances[maxIdx] = PersonBalance(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: ((b.total + remainder) * 100).rounded() / 100,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                isPaid: b.isPaid,
                paidAt: b.paidAt,
                paymentMethod: b.paymentMethod,
                settlementStatus: b.settlementStatus
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: subtotal, currency: currency)
    }

    // MARK: - 2. Itemized Split

    private static func calculateItemized(
        items: [ReceiptItem],
        participants: [Participant],
        assignments: [Int: Set<UUID>],
        tax: Double,
        tip: Double,
        currency: String,
        targetCurrency: String,
        exchangeRate: Double
    ) -> SplitResult {
        guard !participants.isEmpty else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
        }

        var personSubtotals: [UUID: Double] = [:]
        for participant in participants {
            personSubtotals[participant.id] = 0
        }

        var assignedIndices: Set<Int> = []

        for (index, item) in items.enumerated() {
            guard let assignees = assignments[index], !assignees.isEmpty else { continue }
            assignedIndices.insert(index)
            let share = item.price / Double(assignees.count)
            for participantId in assignees where personSubtotals[participantId] != nil {
                personSubtotals[participantId, default: 0] += share
            }
        }

        let assignedSubtotal = items.enumerated()
            .filter { assignedIndices.contains($0.offset) }
            .reduce(0.0) { $0 + $1.element.price }

        let groupSubtotal = personSubtotals.values.reduce(0, +)

        var balances: [PersonBalance] = participants.map { participant in
            let subtotal = personSubtotals[participant.id] ?? 0
            guard groupSubtotal > 0 else {
                return PersonBalance(
                    participantId: participant.id,
                    name: participant.name,
                    itemsSubtotal: 0,
                    taxShare: 0,
                    tipShare: 0,
                    total: 0,
                    currency: currency,
                    targetCurrency: targetCurrency,
                    exchangeRate: exchangeRate
                )
            }
            let ratio = subtotal / groupSubtotal
            let taxShare = (ratio * tax * 100).rounded() / 100
            let tipShare = (ratio * tip * 100).rounded() / 100
            let personTotal = ((subtotal + taxShare + tipShare) * 100).rounded() / 100
            return PersonBalance(
                participantId: participant.id,
                name: participant.name,
                itemsSubtotal: (subtotal * 100).rounded() / 100,
                taxShare: taxShare,
                tipShare: tipShare,
                total: personTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )
        }

        let expectedTotal = ((groupSubtotal + tax + tip) * 100).rounded() / 100
        let actualTotal = ((balances.reduce(0.0) { $0 + $1.total }) * 100).rounded() / 100
        let remainder = ((expectedTotal - actualTotal) * 100).rounded() / 100

        if remainder != 0,
           let maxIndex = balances.indices.max(by: { balances[$0].total < balances[$1].total }) {
            let b = balances[maxIndex]
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: ((b.total + remainder) * 100).rounded() / 100,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                isPaid: b.isPaid,
                paidAt: b.paidAt,
                paymentMethod: b.paymentMethod,
                settlementStatus: b.settlementStatus
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: assignedSubtotal, currency: currency)
    }

    // MARK: - 3. Percentage Split

    private static func calculatePercentage(
        participants: [Participant],
        percentages: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        currency: String,
        targetCurrency: String,
        exchangeRate: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
        }

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
            let pSubtotal = (ratio * subtotal * 100).rounded() / 100
            let pTax = (ratio * tax * 100).rounded() / 100
            let pTip = (ratio * tip * 100).rounded() / 100
            let pTotal = ((pSubtotal + pTax + pTip) * 100).rounded() / 100
            return PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: pTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )
        }

        let expectedTotal = ((subtotal + tax + tip) * 100).rounded() / 100
        let actualTotal = ((balances.reduce(0.0) { $0 + $1.total }) * 100).rounded() / 100
        let remainder = ((expectedTotal - actualTotal) * 100).rounded() / 100

        if remainder != 0,
           let maxIndex = balances.indices.max(by: { balances[$0].total < balances[$1].total }) {
            let b = balances[maxIndex]
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: ((b.total + remainder) * 100).rounded() / 100,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                isPaid: b.isPaid,
                paidAt: b.paidAt,
                paymentMethod: b.paymentMethod,
                settlementStatus: b.settlementStatus
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: subtotal, currency: currency)
    }

    // MARK: - 4. Shares Split

    private static func calculateShares(
        participants: [Participant],
        shares: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        currency: String,
        targetCurrency: String,
        exchangeRate: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
        }

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
            let pSubtotal = (ratio * subtotal * 100).rounded() / 100
            let pTax = (ratio * tax * 100).rounded() / 100
            let pTip = (ratio * tip * 100).rounded() / 100
            let pTotal = ((pSubtotal + pTax + pTip) * 100).rounded() / 100
            return PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: pTotal,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )
        }

        let expectedTotal = ((subtotal + tax + tip) * 100).rounded() / 100
        let actualTotal = ((balances.reduce(0.0) { $0 + $1.total }) * 100).rounded() / 100
        let remainder = ((expectedTotal - actualTotal) * 100).rounded() / 100

        if remainder != 0,
           let maxIndex = balances.indices.max(by: { balances[$0].total < balances[$1].total }) {
            let b = balances[maxIndex]
            balances[maxIndex] = PersonBalance(
                participantId: b.participantId,
                name: b.name,
                itemsSubtotal: b.itemsSubtotal,
                taxShare: b.taxShare,
                tipShare: b.tipShare,
                total: ((b.total + remainder) * 100).rounded() / 100,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate,
                isPaid: b.isPaid,
                paidAt: b.paidAt,
                paymentMethod: b.paymentMethod,
                settlementStatus: b.settlementStatus
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: subtotal, currency: currency)
    }

    // MARK: - 5. Exact Split

    private static func calculateExact(
        participants: [Participant],
        exactAmounts: [UUID: Double],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double,
        currency: String,
        targetCurrency: String,
        exchangeRate: Double
    ) -> SplitResult {
        let count = Double(participants.count)
        guard count > 0 else {
            return SplitResult(balances: [], assignedSubtotal: 0, currency: currency)
        }

        let defaultPerPerson = count > 0 ? ((total / count * 100).rounded() / 100) : 0.0

        let balances = participants.map { p in
            let pTotal = exactAmounts[p.id] ?? defaultPerPerson
            let pSubtotal = ((pTotal * (total > 0 ? (subtotal / total) : 1.0)) * 100).rounded() / 100
            let pTax = ((pTotal * (total > 0 ? (tax / total) : 0.0)) * 100).rounded() / 100
            let pTip = ((pTotal - pSubtotal - pTax) * 100).rounded() / 100
            return PersonBalance(
                participantId: p.id,
                name: p.name,
                itemsSubtotal: pSubtotal,
                taxShare: pTax,
                tipShare: pTip,
                total: (pTotal * 100).rounded() / 100,
                currency: currency,
                targetCurrency: targetCurrency,
                exchangeRate: exchangeRate
            )
        }

        return SplitResult(balances: balances, assignedSubtotal: subtotal, currency: currency)
    }
}
