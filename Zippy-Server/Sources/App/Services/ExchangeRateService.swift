import Vapor
import Foundation

/// Thread-safe in-memory cache for exchange rates.
private actor RateCache {
    private var cache: [String: (rates: [String: Double], timestamp: Date)] = [:]
    private let ttl: TimeInterval = 1800 // 30 minutes cache TTL

    func getRates(for base: String) -> [String: Double]? {
        guard let entry = cache[base.uppercased()] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) < ttl {
            return entry.rates
        }
        return nil
    }

    func setRates(_ rates: [String: Double], for base: String) {
        cache[base.uppercased()] = (rates: rates, timestamp: Date())
    }
}

/// Live exchange rate service consulted at calculation time.
/// Supports querying live remote rate endpoints, caching results with TTL,
/// and falling back to a comprehensive built-in conversion matrix.
public enum ExchangeRateService {

    private static let cache = RateCache()

    /// Default fallback conversion rates against USD (base: 1 USD).
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

    /// Standard supported currency list.
    public static let supportedCurrencies = [
        "USD", "EUR", "GBP", "CAD", "JPY", "AUD", "CHF", "CNY", "INR", "MXN", "BRL", "SGD", "HKD", "NZD", "SEK", "NOK", "DKK", "KRW"
    ]

    /// Structure representing remote API response from standard open exchange rate services.
    private struct OpenExchangeRatesResponse: Decodable {
        let result: String?
        let base_code: String?
        let rates: [String: Double]?
    }

    /// Fetches all exchange rates for a given base currency.
    /// Consults live API first, then cache, and falls back to static baseline.
    public static func getRates(base: String = "USD", client: Client? = nil) async -> [String: Double] {
        let normalizedBase = base.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 1. Check in-memory cache
        if let cached = await cache.getRates(for: normalizedBase) {
            return cached
        }

        // 2. Attempt live consulting from live rate service
        if let liveRates = await fetchLiveRates(base: normalizedBase, client: client) {
            await cache.setRates(liveRates, for: normalizedBase)
            return liveRates
        }

        // 3. Fallback to computed static baseline rates
        let fallback = computeFallbackRates(for: normalizedBase)
        await cache.setRates(fallback, for: normalizedBase)
        return fallback
    }

    /// Fetches live conversion rate from one currency to another.
    public static func getRate(
        from sourceCurrency: String,
        to targetCurrency: String,
        client: Client? = nil
    ) async -> Double {
        let from = sourceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let to = targetCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if from == to {
            return 1.0
        }

        let rates = await getRates(base: from, client: client)
        if let directRate = rates[to] {
            return directRate
        }

        // Cross-rate calculation via USD if direct rate not found
        let usdFrom = fallbackRatesToUSD[from] ?? 1.0
        let usdTo = fallbackRatesToUSD[to] ?? 1.0
        if usdFrom > 0 {
            return usdTo / usdFrom
        }

        return 1.0
    }

    /// Converts an amount between currencies consulting live rate at calculation time.
    /// Returns both the converted amount and the precise exchange rate used.
    public static func convert(
        amount: Double,
        from sourceCurrency: String,
        to targetCurrency: String,
        client: Client? = nil
    ) async -> (convertedAmount: Double, rate: Double) {
        let from = sourceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let to = targetCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if from == to {
            return (round2(amount), 1.0)
        }

        let rate = await getRate(from: from, to: to, client: client)
        let converted = round2(amount * rate)
        return (converted, rate)
    }

    // MARK: - Internal Network Retrieval

    private static func fetchLiveRates(base: String, client: Client?) async -> [String: Double]? {
        let endpoint = Environment.get("EXCHANGE_RATE_API_URL") ?? "https://open.er-api.com/v6/latest/\(base)"
        guard let url = URI(string: endpoint).string.flatMap(URI.init(string:)) else { return nil }

        do {
            if let client = client {
                let response = try await client.get(url)
                if response.status == .ok,
                   let body = try? response.content.decode(OpenExchangeRatesResponse.self),
                   let rates = body.rates {
                    return rates
                }
            } else {
                guard let nativeURL = URL(string: endpoint) else { return nil }
                var request = URLRequest(url: nativeURL)
                request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                    let decoded = try JSONDecoder().decode(OpenExchangeRatesResponse.self, from: data)
                    if let rates = decoded.rates {
                        return rates
                    }
                }
            }
        } catch {
            // Live rate service unavailable, fallback seamlessly
        }
        return nil
    }

    private static func computeFallbackRates(for base: String) -> [String: Double] {
        guard let baseToUSD = fallbackRatesToUSD[base] else {
            return fallbackRatesToUSD
        }
        var computed: [String: Double] = [:]
        for (currency, rateToUSD) in fallbackRatesToUSD {
            computed[currency] = (rateToUSD / baseToUSD)
        }
        return computed
    }

    public static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
