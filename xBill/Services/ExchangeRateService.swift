//
//  ExchangeRateService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation

// MARK: - ExchangeRateService
// Uses open.er-api.com (no API key, 1500 req/month free tier).
// Caches rates for 1 hour per base currency to avoid hammering the API.

actor ExchangeRateService {
    static let shared = ExchangeRateService()
    private init() {}

    private struct CacheEntry {
        let rates: [String: Double]
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    // MARK: - Public API

    /// Converts `amount` from `fromCurrency` to `toCurrency`.
    func convert(amount: Decimal, from fromCurrency: String, to toCurrency: String) async throws -> Decimal {
        guard fromCurrency != toCurrency else { return amount }
        let rates = try await rates(base: fromCurrency)
        guard let rate = rates[toCurrency] else {
            throw AppError.unknown("No exchange rate for \(toCurrency)")
        }
        return (amount * Decimal(rate)).rounded(scale: 2)
    }

    /// Returns the rate from `base` to `target`.
    func rate(from base: String, to target: String) async throws -> Double {
        guard base != target else { return 1.0 }
        let rates = try await rates(base: base)
        guard let rate = rates[target] else {
            throw AppError.unknown("No exchange rate for \(target)")
        }
        return rate
    }

    // MARK: - Fetch

    private func rates(base: String) async throws -> [String: Double] {
        let key = base.uppercased()
        if let cached = cache[key],
           Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.rates
        }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(key)") else {
            throw AppError.unknown("Invalid exchange rate URL")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response  = try JSONDecoder().decode(ERAPIResponse.self, from: data)
        guard response.result == "success" else {
            throw AppError.unknown("Exchange rate API error")
        }
        cache[key] = CacheEntry(rates: response.rates, fetchedAt: Date())
        return response.rates
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
        NSDecimalRound(&result, &copy, scale, .plain)
        return result
    }
}
