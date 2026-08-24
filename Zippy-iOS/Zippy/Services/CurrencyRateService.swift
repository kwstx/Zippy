import Foundation
import SwiftUI

/// Currency representation and conversion utilities for the iOS client.
public struct CurrencyItem: Identifiable, Hashable {
    public let code: String
    public let name: String
    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code.uppercased()
        self.name = name
    }
}

public enum CurrencyRateService {
    /// Comprehensive list of standard ISO 4217 currencies supported in Zippy.
    public static let supportedCurrencies: [CurrencyItem] = [
        CurrencyItem(code: "USD", name: "US Dollar"),
        CurrencyItem(code: "EUR", name: "Euro"),
        CurrencyItem(code: "GBP", name: "British Pound"),
        CurrencyItem(code: "CAD", name: "Canadian Dollar"),
        CurrencyItem(code: "JPY", name: "Japanese Yen"),
        CurrencyItem(code: "AUD", name: "Australian Dollar"),
        CurrencyItem(code: "CHF", name: "Swiss Franc"),
        CurrencyItem(code: "CNY", name: "Chinese Yuan"),
        CurrencyItem(code: "INR", name: "Indian Rupee"),
        CurrencyItem(code: "MXN", name: "Mexican Peso"),
        CurrencyItem(code: "BRL", name: "Brazilian Real"),
        CurrencyItem(code: "SGD", name: "Singapore Dollar"),
        CurrencyItem(code: "HKD", name: "Hong Kong Dollar"),
        CurrencyItem(code: "NZD", name: "New Zealand Dollar"),
        CurrencyItem(code: "SEK", name: "Swedish Krona"),
        CurrencyItem(code: "NOK", name: "Norwegian Krone"),
        CurrencyItem(code: "DKK", name: "Danish Krone"),
        CurrencyItem(code: "KRW", name: "South Korean Won")
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

    /// Returns display name for a currency code.
    public static func name(for code: String) -> String {
        let normalized = code.uppercased()
        return supportedCurrencies.first(where: { $0.code == normalized })?.name ?? normalized
    }
}
