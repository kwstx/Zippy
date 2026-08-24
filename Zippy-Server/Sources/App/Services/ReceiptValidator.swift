import Foundation

/// Result of validating a receipt on the server.
public struct ReceiptValidationReport: Codable, Sendable {
    public let isValid: Bool
    public let isMathConsistent: Bool
    public let computedSubtotal: Double
    public let computedTotal: Double
    public let subtotalDiscrepancy: Double
    public let totalDiscrepancy: Double
    public let warnings: [String]
    public let errors: [String]

    public init(
        isValid: Bool,
        isMathConsistent: Bool,
        computedSubtotal: Double,
        computedTotal: Double,
        subtotalDiscrepancy: Double,
        totalDiscrepancy: Double,
        warnings: [String],
        errors: [String]
    ) {
        self.isValid = isValid
        self.isMathConsistent = isMathConsistent
        self.computedSubtotal = computedSubtotal
        self.computedTotal = computedTotal
        self.subtotalDiscrepancy = subtotalDiscrepancy
        self.totalDiscrepancy = totalDiscrepancy
        self.warnings = warnings
        self.errors = errors
    }
}

/// Pure-Swift validator for receipt line items, subtotals, taxes, tips, and totals.
public enum ReceiptValidator {

    private static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Validates receipt line items and financial totals.
    ///
    /// - Parameters:
    ///   - items: The list of receipt items (name, price, quantity).
    ///   - subtotal: The stated subtotal amount.
    ///   - tax: The stated tax amount.
    ///   - tip: The stated tip amount.
    ///   - total: The stated grand total amount.
    /// - Returns: A `ReceiptValidationReport` detailing errors, warnings, and computed sums.
    public static func validate(
        items: [ReceiptItem],
        subtotal: Double,
        tax: Double,
        tip: Double,
        total: Double
    ) -> ReceiptValidationReport {
        var errors: [String] = []
        var warnings: [String] = []

        // 1. Line item checks
        if items.isEmpty {
            warnings.append("Receipt has no line items.")
        }

        var computedItemSubtotal: Double = 0.0

        for (index, item) in items.enumerated() {
            let itemNum = index + 1
            let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                warnings.append("Item #\(itemNum) has an empty name.")
            }

            if item.price < 0 {
                errors.append("Item #\(itemNum) (\(trimmedName.isEmpty ? "Unnamed" : trimmedName)) has negative price $\(String(format: "%.2f", item.price)).")
            }

            if item.quantity <= 0 {
                warnings.append("Item #\(itemNum) (\(trimmedName.isEmpty ? "Unnamed" : trimmedName)) has invalid quantity \(item.quantity). Defaulted to 1.")
            }

            let effectiveQty = max(1, item.quantity)
            let lineTotal = round2(item.price * Double(effectiveQty))
            computedItemSubtotal = round2(computedItemSubtotal + lineTotal)
        }

        // 2. Tax & Tip checks
        if tax < 0 {
            errors.append("Tax cannot be negative ($\(String(format: "%.2f", tax))).")
        }
        if tip < 0 {
            errors.append("Tip cannot be negative ($\(String(format: "%.2f", tip))).")
        }

        let effectiveTax = max(0, tax)
        let effectiveTip = max(0, tip)

        // 3. Subtotal consistency check
        let roundedStatedSubtotal = round2(subtotal)
        let subtotalDiff = round2(abs(roundedStatedSubtotal - computedItemSubtotal))
        if !items.isEmpty && subtotalDiff > 0.05 {
            warnings.append(
                "Stated subtotal ($\(String(format: "%.2f", roundedStatedSubtotal))) differs from item sum ($\(String(format: "%.2f", computedItemSubtotal))) by $\(String(format: "%.2f", subtotalDiff))."
            )
        }

        // 4. Grand Total consistency check
        let baseForTotal = roundedStatedSubtotal > 0 ? roundedStatedSubtotal : computedItemSubtotal
        let computedGrandTotal = round2(baseForTotal + effectiveTax + effectiveTip)
        let roundedStatedTotal = round2(total)
        let totalDiff = round2(abs(roundedStatedTotal - computedGrandTotal))

        if roundedStatedTotal > 0 && totalDiff > 0.05 {
            warnings.append(
                "Stated total ($\(String(format: "%.2f", roundedStatedTotal))) differs from sum ($\(String(format: "%.2f", computedGrandTotal))) by $\(String(format: "%.2f", totalDiff))."
            )
        }

        let isMathConsistent = (subtotalDiff <= 0.05) && (totalDiff <= 0.05)
        let isValid = errors.isEmpty

        return ReceiptValidationReport(
            isValid: isValid,
            isMathConsistent: isMathConsistent,
            computedSubtotal: computedItemSubtotal,
            computedTotal: computedGrandTotal,
            subtotalDiscrepancy: subtotalDiff,
            totalDiscrepancy: totalDiff,
            warnings: warnings,
            errors: errors
        )
    }
}
