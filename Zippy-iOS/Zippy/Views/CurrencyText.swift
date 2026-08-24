import SwiftUI

/// A specialized monetary display component adhering strictly to the monochrome design system.
/// Displays values as plain black text (or dynamic primary color for dark mode) with the currency code
/// in a lighter font weight, never introducing color (no green, red, or accents).
public struct CurrencyText: View {
    public let amount: Double
    public let currency: String
    public let showSign: Bool
    public let font: Font
    public let amountWeight: Font.Weight
    public let codeWeight: Font.Weight

    public init(
        _ amount: Double,
        currency: String = "USD",
        showSign: Bool = false,
        font: Font = .body,
        amountWeight: Font.Weight = .semibold,
        codeWeight: Font.Weight = .light
    ) {
        self.amount = amount
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.showSign = showSign
        self.font = font
        self.amountWeight = amountWeight
        self.codeWeight = codeWeight
    }

    private var formattedDigits: String {
        let absAmount = abs(amount)
        let formatted = String(format: "%.2f", absAmount)
        if showSign {
            if amount > 0.005 {
                return "+\(formatted)"
            } else if amount < -0.005 {
                return "-\(formatted)"
            } else {
                return formatted
            }
        } else {
            return formatted
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(formattedDigits)
                .font(font)
                .fontWeight(amountWeight)
                .foregroundColor(.primary)

            Text(currency.isEmpty ? "USD" : currency)
                .font(font == .title || font == .largeTitle ? .subheadline : .caption2)
                .fontWeight(codeWeight)
                .foregroundColor(.primary)
                .opacity(0.65)
        }
    }
}

extension CurrencyText {
    /// Formats a plain string representation of an amount and currency without color.
    public static func plainText(_ amount: Double, currency: String = "USD", showSign: Bool = false) -> String {
        let absAmount = abs(amount)
        let formatted = String(format: "%.2f", absAmount)
        let cur = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let curCode = cur.isEmpty ? "USD" : cur
        if showSign {
            if amount > 0.005 {
                return "+\(formatted) \(curCode)"
            } else if amount < -0.005 {
                return "-\(formatted) \(curCode)"
            } else {
                return "\(formatted) \(curCode)"
            }
        } else {
            return "\(formatted) \(curCode)"
        }
    }
}

#if DEBUG
struct CurrencyText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CurrencyText(124.50, currency: "USD", font: .largeTitle, amountWeight: .bold)
            CurrencyText(89.00, currency: "EUR", font: .title2)
            CurrencyText(-34.20, currency: "GBP", showSign: true, font: .body)
            CurrencyText(15000, currency: "JPY", font: .headline)
        }
        .padding()
        .preferredColorScheme(.light)
    }
}
#endif
