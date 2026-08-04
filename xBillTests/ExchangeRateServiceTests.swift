//
//  ExchangeRateServiceTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  `ExchangeRateService` was 0% covered while converting money between currencies — the highest
//  risk per line in the app. A wrong rate does not crash; it silently changes what an expense is
//  worth, and the user has no way to tell.
//
//  It also carries the `Decimal(string: String(double))` round-trip from H-08/H-15 — the same
//  guard added to `VisionService` for VIS-04, where the equivalent conversion was found to be
//  producing `4.990000000000001024`. Nothing verified this one held.
//

import Testing
import Foundation
@testable import xBill

@Suite("ExchangeRateService")
struct ExchangeRateServiceTests {

    /// A private suite name so a test never reads or writes the real stale-rate disk cache.
    /// Returns the *name*, not the instance: handing one `UserDefaults` object to two actors is a
    /// send violation under strict concurrency, so each call site builds its own.
    private func makeSuite() -> String { "er.tests.\(UUID().uuidString)" }

    private func response(_ url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private func successBody(_ rates: String) -> Data {
        Data(#"{"result":"success","rates":{\#(rates)}}"#.utf8)
    }

    // MARK: - Conversion

    @Test("Converting applies the rate and rounds to two places")
    func convertsAndRounds() async throws {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { url in (self.successBody(#""EUR":0.9"#), self.response(url)) },
            defaults: UserDefaults(suiteName: suite)!)

        let converted = try await service.convert(amount: Decimal(string: "10.00")!, from: "USD", to: "EUR")
        #expect(converted == Decimal(string: "9.00"))
    }

    /// The H-08/H-15 guard: the JSON rate is a `Double`, and `Decimal(Double)` reproduces the
    /// binary float's error — that is precisely how scanned receipts ended up with
    /// `4.990000000000001024` (VIS-04). Converting through the decimal string keeps it exact.
    @Test("A rate does not inherit binary floating-point error")
    func rateSurvivesTheJSONBoundary() async throws {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { url in (self.successBody(#""EUR":0.07"#), self.response(url)) },
            defaults: UserDefaults(suiteName: suite)!)

        let rate = try await service.rate(from: "USD", to: "EUR")
        #expect(rate == Decimal(string: "0.07"),
                "Rate became \(rate); Decimal(Double) would give 0.07000000000000001024.")
    }

    @Test("Converting to the same currency is a no-op and makes no request")
    func sameCurrencyShortCircuits() async throws {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { _ in Issue.record("No network call should be made."); throw AppError.networkUnavailable },
            defaults: UserDefaults(suiteName: suite)!)

        let amount = Decimal(string: "12.34")!
        #expect(try await service.convert(amount: amount, from: "USD", to: "USD") == amount)
        #expect(try await service.rate(from: "USD", to: "USD") == 1)
    }

    @Test("An unknown target currency is an error, not a silent zero")
    func unknownCurrencyThrows() async {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { url in (self.successBody(#""EUR":0.9"#), self.response(url)) },
            defaults: UserDefaults(suiteName: suite)!)

        await #expect(throws: (any Error).self) {
            _ = try await service.convert(amount: 10, from: "USD", to: "XYZ")
        }
    }

    // MARK: - Failure handling

    /// H-37: a non-2xx response must be rejected before decoding, or an error page decodes into
    /// nonsense rates.
    @Test("A non-2xx response is rejected")
    func httpErrorRejected() async {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { url in (self.successBody(#""EUR":0.9"#), self.response(url, status: 500)) },
            defaults: UserDefaults(suiteName: suite)!)

        await #expect(throws: (any Error).self) {
            _ = try await service.rate(from: "USD", to: "EUR")
        }
    }

    @Test("A body whose result is not success is rejected")
    func apiErrorResultRejected() async {
        let suite = makeSuite()
        let service = ExchangeRateService(
            fetch: { url in (Data(#"{"result":"error","rates":{}}"#.utf8), self.response(url)) },
            defaults: UserDefaults(suiteName: suite)!)

        await #expect(throws: (any Error).self) {
            _ = try await service.rate(from: "USD", to: "EUR")
        }
    }

    // MARK: - Caching

    @Test("A second conversion in the same session makes no second request")
    func inMemoryCacheAvoidsRefetch() async throws {
        let suite = makeSuite()
        let calls = Counter()
        let service = ExchangeRateService(
            fetch: { url in
                await calls.increment()
                return (self.successBody(#""EUR":0.9"#), self.response(url))
            },
            defaults: UserDefaults(suiteName: suite)!)

        _ = try await service.rate(from: "USD", to: "EUR")
        _ = try await service.rate(from: "USD", to: "EUR")
        #expect(await calls.value == 1, "Rates are cached for an hour; a refetch wastes a request.")
    }

    /// L-25: rates persist to disk so a conversion still works offline. Without the fallback the
    /// user simply cannot record a foreign-currency expense on a plane.
    @Test("A failed fetch falls back to previously persisted rates")
    func staleDiskCacheIsUsedOnFailure() async throws {
        let suite = makeSuite()

        // First service populates the disk cache.
        let warm = ExchangeRateService(
            fetch: { url in (self.successBody(#""EUR":0.9"#), self.response(url)) },
            defaults: UserDefaults(suiteName: suite)!)
        _ = try await warm.rate(from: "USD", to: "EUR")

        // A fresh instance with no memory cache and a dead network must still answer.
        let offline = ExchangeRateService(
            fetch: { _ in throw AppError.networkUnavailable },
            defaults: UserDefaults(suiteName: suite)!)
        let rate = try await offline.rate(from: "USD", to: "EUR")
        #expect(rate == Decimal(string: "0.9"))
    }

    @Test("With no network and no persisted rates, the error surfaces")
    func noCacheNoNetworkThrows() async {
        let suite = makeSuite()
        let service = ExchangeRateService(fetch: { _ in throw AppError.networkUnavailable },
                                          defaults: UserDefaults(suiteName: suite)!)
        await #expect(throws: (any Error).self) {
            _ = try await service.rate(from: "USD", to: "EUR")
        }
    }
}

/// Counts calls from a `@Sendable` closure without tripping strict concurrency.
actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
