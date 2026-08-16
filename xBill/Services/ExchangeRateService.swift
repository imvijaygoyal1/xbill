//
//  ExchangeRateService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import OSLog

// MARK: - ExchangeRateService
// Uses open.er-api.com Open Access (no API key). There is **no monthly quota** — the earlier
// "1500 req/month" note was wrong; access is IP rate-limited, answering HTTP 429 with a ~20 minute
// cooldown. The 1-hour cache below sits comfortably inside that.
//
// Commercial use is permitted **only with attribution**: the app must link back with the words
// "Rates By Exchange Rate API". See `XBillURLs.exchangeRateAttribution`; it is rendered in
// AddExpenseView's conversion preview and permanently in the Profile footer.
// Caches rates for 1 hour per base currency to avoid hammering the API.

actor ExchangeRateService {
    static let shared = ExchangeRateService()

    /// Injection seam, defaulted to the real network and `UserDefaults.standard`.
    ///
    /// This service was **0% covered** while converting money between currencies — the highest
    /// risk per line in the app, because a wrong rate silently changes what an expense is worth
    /// and nothing crashes. It also carries the `Decimal(string: String(double))` round-trip from
    /// H-08/H-15, the same guard added to `VisionService` for VIS-04; nothing verified it held.
    ///
    /// `defaults` is injectable too, so a test cannot collide with the real disk cache — the
    /// stale-rate fallback below reads and writes it.
    init(
        fetch: (@Sendable (URL) async throws -> (Data, URLResponse))? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.injectedFetch = fetch
        self.defaults = defaults
    }

    private let injectedFetch: (@Sendable (URL) async throws -> (Data, URLResponse))?
    private let defaults: UserDefaults

    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        if let injectedFetch { return try await injectedFetch(url) }
        return try await session.data(from: url)
    }
    private let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "ExchangeRates")

    private struct CacheEntry {
        // Rates stored as Decimal (converted via String roundtrip to avoid
        // binary floating-point contamination from the JSON Double representation).
        let rates: [String: Decimal]
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 hour
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Converts `amount` from `fromCurrency` to `toCurrency`.
    func convert(amount: Decimal, from fromCurrency: String, to toCurrency: String) async throws -> Decimal {
        guard fromCurrency != toCurrency else { return amount }
        let rates = try await rates(base: fromCurrency)
        guard let rate = rates[toCurrency] else {
            throw AppError.unknown("No exchange rate for \(toCurrency)")
        }
        return (amount * rate).rounded(scale: 2)
    }

    /// Returns the rate from `base` to `target` as a Decimal.
    func rate(from base: String, to target: String) async throws -> Decimal {
        guard base != target else { return 1 }
        let rates = try await rates(base: base)
        guard let rate = rates[target] else {
            throw AppError.unknown("No exchange rate for \(target)")
        }
        return rate
    }

    // MARK: - Fetch

    private func rates(base: String) async throws -> [String: Decimal] {
        let key = base.uppercased()
        if let cached = cache[key],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.rates
        }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(key)") else {
            throw AppError.unknown("Invalid exchange rate URL")
        }
        do {
            let (data, response) = try await fetch(url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AppError.unknown("Exchange rate unavailable (HTTP \(http.statusCode)). Try again later.")
            }
            let decoded = try JSONDecoder().decode(ERAPIResponse.self, from: data)
            guard decoded.result == "success" else {
                throw AppError.unknown("Exchange rate API returned an error response.")
            }
            let decimalRates = decoded.rates.mapValues { Decimal(string: String($0)) ?? Decimal($0) }
            cache[key] = CacheEntry(rates: decimalRates, fetchedAt: Date())
            persistRates(decimalRates, base: key)
            return decimalRates
        } catch {
            // Network or decode failure — fall back to stale disk cache before rethrowing.
            if let stale = cachedRates(base: key) {
                logger.warning("Using stale disk-cached rates for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Populate in-memory cache so subsequent calls in this session are fast.
                cache[key] = CacheEntry(rates: stale, fetchedAt: .distantPast)
                return stale
            }
            throw error
        }
    }

    // MARK: - Disk persistence (UserDefaults)

    /// Persists a rate dictionary for `base` to UserDefaults so it survives app restarts.
    private func persistRates(_ rates: [String: Decimal], base: String) {
        guard let data = try? JSONEncoder().encode(rates) else { return }
        defaults.set(data, forKey: "er_cache_\(base)")
    }

    /// Returns a previously persisted rate dictionary for `base`, or nil if absent / undecodable.
    private func cachedRates(base: String) -> [String: Decimal]? {
        guard let data = defaults.data(forKey: "er_cache_\(base)"),
              let dict = try? JSONDecoder().decode([String: Decimal].self, from: data)
        else { return nil }
        return dict
    }
}

// MARK: - Response

private struct ERAPIResponse: Decodable {
    let result: String
    let rates: [String: Double]
}

// MARK: - Common currencies

extension ExchangeRateService {
    static let commonCurrencies: [String] = [
        "USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF",
        "CNY", "INR", "MXN", "BRL", "KRW", "SGD", "HKD",
        "NOK", "SEK", "DKK", "NZD", "ZAR", "AED"
    ]
}

// MARK: - Decimal helper

private extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var result = Decimal()
        var copy = self
        NSDecimalRound(&result, &copy, scale, .bankers)
        return result
    }
}
