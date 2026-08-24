import Foundation
import SwiftUI

/// Currency representation and conversion utilities for the iOS client.
public struct CurrencyItem: Identifiable, Hashable {
    public let code: String
    public let name: String
    public let symbol: String
    public var id: String { code }

    public init(code: String, name: String, symbol: String) {
        self.code = code.uppercased()
        self.name = name
        self.symbol = symbol
    }
}

public enum CurrencyRateService {
    /// Comprehensive list of standard ISO 4217 currency codes supported in Zippy.
    public static let supportedCurrencies: [String] = [
        "USD", "EUR", "GBP", "CAD", "JPY", "AUD", "CHF", "CNY",
        "INR", "MXN", "BRL", "SGD", "HKD", "NZD", "SEK", "NOK",
        "DKK", "KRW"
    ]

    /// Currency metadata catalog.
    public static let currencyItems: [CurrencyItem] = [
        CurrencyItem(code: "USD", name: "US Dollar", symbol: "$"),
        CurrencyItem(code: "EUR", name: "Euro", symbol: "€"),
        CurrencyItem(code: "GBP", name: "British Pound", symbol: "£"),
        CurrencyItem(code: "CAD", name: "Canadian Dollar", symbol: "$"),
        CurrencyItem(code: "JPY", name: "Japanese Yen", symbol: "¥"),
        CurrencyItem(code: "AUD", name: "Australian Dollar", symbol: "$"),
        CurrencyItem(code: "CHF", name: "Swiss Franc", symbol: "CHF"),
        CurrencyItem(code: "CNY", name: "Chinese Yuan", symbol: "¥"),
        CurrencyItem(code: "INR", name: "Indian Rupee", symbol: "₹"),
        CurrencyItem(code: "MXN", name: "Mexican Peso", symbol: "$"),
        CurrencyItem(code: "BRL", name: "Brazilian Real", symbol: "R$"),
        CurrencyItem(code: "SGD", name: "Singapore Dollar", symbol: "$"),
        CurrencyItem(code: "HKD", name: "Hong Kong Dollar", symbol: "$"),
        CurrencyItem(code: "NZD", name: "New Zealand Dollar", symbol: "$"),
        CurrencyItem(code: "SEK", name: "Swedish Krona", symbol: "kr"),
        CurrencyItem(code: "NOK", name: "Norwegian Krone", symbol: "kr"),
        CurrencyItem(code: "DKK", name: "Danish Krone", symbol: "kr"),
        CurrencyItem(code: "KRW", name: "South Korean Won", symbol: "₩")
    ]

    /// Default baseline rates relative to USD (1 USD = X).
    public static let fallbackRatesToUSD: [String: Double] = [
        "USD": 1.0,
        "EUR": 0.92,
        "GBP": 0.79,
        "CAD": 1.36,
        "JPY": 155.20,
        "AUD": 1.52,
        "CHF": 0.91,
        "CNY": 7.24,
        "INR": 83.40,
        "MXN": 16.80,
        "BRL": 5.15,
        "SGD": 1.35,
        "HKD": 7.82,
        "NZD": 1.66,
        "SEK": 10.75,
        "NOK": 10.85,
        "DKK": 6.88,
        "KRW": 1365.0
    ]

    /// Calculates conversion between source and target currency.
    public static func convert(
        amount: Double,
        from sourceCurrency: String,
        to targetCurrency: String,
        rates: [String: Double]? = nil
    ) -> (convertedAmount: Double, rate: Double) {
        let from = sourceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let to = targetCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if from == to {
            return (amount, 1.0)
        }

        let rateMatrix = rates ?? fallbackRatesToUSD
        let usdFrom = rateMatrix[from] ?? fallbackRatesToUSD[from] ?? 1.0
        let usdTo = rateMatrix[to] ?? fallbackRatesToUSD[to] ?? 1.0

        let rate: Double
        if usdFrom > 0 {
            rate = usdTo / usdFrom
        } else {
            rate = 1.0
        }

        let converted = (amount * rate * 100).rounded() / 100
        return (converted, rate)
    }

    /// Returns display symbol for a currency code.
    public static func symbol(for code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return currencyItems.first(where: { $0.code == normalized })?.symbol ?? normalized
    }

    /// Returns display name for a currency code.
    public static func name(for code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return currencyItems.first(where: { $0.code == normalized })?.name ?? normalized
    }
}
