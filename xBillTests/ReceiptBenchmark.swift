//
//  ReceiptBenchmark.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Scores the real scan pipeline against a corpus of photographed receipts with hand-written
//  ground truth.
//
//  It was a measurement and **not** a gate: it asserted nothing, so accuracy could fall from 91%
//  to 50% and the suite would stay green. Twenty-two receipts scored on every run, protecting
//  nothing. It now asserts floors — see `Floor` below for what they are and how they were chosen.
//
//  It is gated on the **corpus being present**, not on an environment variable — env vars do not
//  reliably reach a test process through xcodebuild, and a gate that silently fails closed is
//  worse than no gate. `run-coverage.sh unit` passes `-skip-testing` so a normal unit run never
//  pays for a Vision pass over the whole corpus; `scripts/receipt-benchmark.sh` runs only this.
//
//  The corpus is git-ignored — real receipts carry card digits, loyalty numbers and addresses.
//  Absent corpus is reported, not failed: a fresh clone has no receipts and that is correct.
//

import Testing
import Foundation
import UIKit
@testable import xBill

// MARK: - Ground truth

private struct LabelItem: Decodable {
    let name: String
    let qty: Int
    let unitPrice: String
    /// Amounts are strings in the label files on purpose: a JSON number is a Double, and
    /// `Decimal(Double)` reproduces float error. Never relax this.
    var total: Decimal { (Decimal(string: unitPrice) ?? .zero) * Decimal(qty) }
}

private struct Label: Decodable {
    let image: String
    let merchant: String?
    let currency: String
    let items: [LabelItem]
    let subtotal: String?
    let tax: String?
    let tip: String?
    let total: String?
    let notes: [String]?

    var totalDecimal: Decimal? { total.flatMap { Decimal(string: $0) } }
    var taxDecimal:   Decimal? { tax.flatMap { Decimal(string: $0) } }
}

// MARK: - Scoring

private struct Score {
    let id: String
    /// Non-nil when the scan threw. A receipt the pipeline REFUSES is a failure of the pipeline,
    /// so it must occupy a row in the table — dropping it silently inflates every average.
    var failure: String? = nil
    let merchant: String
    let tier: String
    let confidence: Double
    let warning: String?

    let totalExpected: Decimal?
    let totalParsed: Decimal?
    var totalOK: Bool { totalExpected != nil && totalExpected == totalParsed }

    let taxExpected: Decimal?
    let taxParsed: Decimal?
    var taxOK: Bool { taxExpected == taxParsed }

    let itemsExpected: Int
    let itemsParsed: Int

    /// Fraction of ground-truth line amounts that appear among the parsed amounts, matched as a
    /// multiset so a duplicated price is not credited twice.
    let priceRecall: Double
    /// Fraction of ground-truth item names recognisably present in a parsed item name.
    let nameRecall: Double

    /// What the parser actually produced. A score says a receipt failed; only this says how, and
    /// without it every follow-up fix is a guess. Kept short — name and line total per item.
    let parsedItems: [String]
    let expectedItems: [String]
}

private func normalise(_ s: String) -> String {
    s.lowercased().filter { $0.isLetter || $0.isNumber }
}

private func score(id: String, label: Label, result: ScanResult) -> Score {
    // Price recall as a multiset intersection.
    var pool = result.receipt.items.map(\.totalPrice)
    var priceHits = 0
    for expected in label.items.map(\.total) {
        if let idx = pool.firstIndex(of: expected) {
            pool.remove(at: idx)
            priceHits += 1
        }
    }

    // Name recall: a parsed name counts if it contains the expected name or vice versa, after
    // stripping punctuation and case. Deliberately loose — we are measuring whether the name
    // survived at all, not whether it round-tripped exactly.
    let parsedNames = result.receipt.items.map { normalise($0.name) }.filter { !$0.isEmpty }
    var nameHits = 0
    for expected in label.items.map({ normalise($0.name) }) where !expected.isEmpty {
        if parsedNames.contains(where: { $0.contains(expected) || expected.contains($0) }) {
            nameHits += 1
        }
    }

    // A card slip itemises nothing. The correct parse produces no items, so recall is 1.0 when
    // the parser also produced none and 0.0 when it invented some — scoring it 0 either way
    // would punish the pipeline for being right.
    let n = Double(label.items.count)
    let emptyExpected = label.items.isEmpty
    let cleanEmpty = emptyExpected && result.receipt.items.isEmpty
    return Score(
        id: id,
        failure: nil,
        merchant: label.merchant ?? "—",
        tier: result.tier,
        confidence: result.confidence,
        warning: result.validationWarning,
        totalExpected: label.totalDecimal,
        totalParsed: result.receipt.total,
        taxExpected: label.taxDecimal,
        taxParsed: result.receipt.tax,
        itemsExpected: label.items.count,
        itemsParsed: result.receipt.items.count,
        priceRecall: emptyExpected ? (cleanEmpty ? 1 : 0) : Double(priceHits) / n,
        nameRecall:  emptyExpected ? (cleanEmpty ? 1 : 0) : Double(nameHits) / n,
        parsedItems: result.receipt.items.map { "\($0.name)=\($0.totalPrice)" },
        expectedItems: label.items.map { "\($0.name)=\($0.total)" }
    )
}

// MARK: - Report

private func report(_ scores: [Score]) -> String {
    func pad(_ s: String, _ w: Int) -> String {
        s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
    }
    func rpad(_ s: String, _ w: Int) -> String {
        s.count >= w ? String(s.prefix(w)) : String(repeating: " ", count: w - s.count) + s
    }
    func money(_ d: Decimal?) -> String { d.map { "\($0)" } ?? "nil" }
    func pct(_ d: Double) -> String { rpad("\(Int((d * 100).rounded()))%", 5) }

    var out = "RECEIPT SCAN BENCHMARK — \(ISO8601DateFormatter().string(from: Date()))\n"
    let rule = String(repeating: "─", count: 88)
    out += rule + "\n"
    out += pad("id", 4) + pad("merchant", 22) + pad("tier", 12)
         + pad("total", 12) + pad("tax", 10) + pad("items", 8)
         + pad("price", 6) + pad("name", 6) + "conf\n"
    out += rule + "\n"

    for s in scores {
        if let f = s.failure {
            out += pad(s.id, 4) + pad(s.merchant, 22) + "REFUSED  " + f + "\n"
            continue
        }
        out += pad(s.id, 4)
             + pad(s.merchant, 22)
             + pad(s.tier, 12)
             + pad(s.totalOK ? "✓" : "✗ " + money(s.totalParsed), 12)
             + pad(s.taxOK   ? "✓" : "✗ " + money(s.taxParsed),   10)
             + pad("\(s.itemsParsed)/\(s.itemsExpected)", 8)
             + pad(pct(s.priceRecall), 6)
             + pad(pct(s.nameRecall), 6)
             + String(format: "%.2f", s.confidence) + "\n"
    }

    out += rule + "\n"
    let n = Double(scores.count)
    let agg = Aggregate(scores)
    let totalsOK = agg.totalsOK
    let taxesOK  = agg.taxesOK
    let exact    = agg.itemCountExact
    let avgPrice = agg.priceRecall
    let avgName  = agg.nameRecall

    out += "TOTAL correct     \(totalsOK)/\(scores.count)   \(Int((Double(totalsOK)/n*100).rounded()))%\n"
    out += "TAX correct       \(taxesOK)/\(scores.count)   \(Int((Double(taxesOK)/n*100).rounded()))%\n"
    out += "Item count exact  \(exact)/\(scores.count)   \(Int((Double(exact)/n*100).rounded()))%\n"
    out += "Price recall      \(Int((avgPrice*100).rounded()))%   (ground-truth line amounts found)\n"
    out += "Name recall       \(Int((avgName*100).rounded()))%   (ground-truth item names surviving)\n"

    let scanned = scores.filter { $0.failure == nil }
    let refused = agg.refused
    if refused > 0 {
        out += "\nREFUSED           \(refused)/\(scores.count)   the pipeline threw and produced nothing\n"
    }
    let right = scanned.filter(\.totalOK).map(\.confidence)
    let wrong = scanned.filter { !$0.totalOK }.map(\.confidence)
    if !right.isEmpty && !wrong.isEmpty {
        let r = right.reduce(0,+)/Double(right.count)
        let w = wrong.reduce(0,+)/Double(wrong.count)
        out += String(format: "\nConfidence calibration  %.2f mean when TOTAL right, %.2f when wrong (gap %+.2f)\n", r, w, r - w)
        out += "  A gap at or below zero means the confidence shown to the user carries no\n"
        out += "  information — or, if negative, actively misleads.\n"
    }
    out += "\n" + rule + "\nPARSED vs EXPECTED\n" + rule + "\n"
    for s in scores where s.failure == nil {
        out += "\(s.id)  parsed  : " + (s.parsedItems.isEmpty ? "(none)" : s.parsedItems.joined(separator: " | ")) + "\n"
        out += "    expected: " + (s.expectedItems.isEmpty ? "(none)" : s.expectedItems.joined(separator: " | ")) + "\n"
    }
    return out
}

// MARK: - Aggregate

/// The numbers the report prints and the gate asserts, computed **once**.
///
/// They were separate expressions in two places for about ten minutes, which is exactly how a
/// gate comes to assert something the report does not show.
private struct Aggregate {
    let count: Int
    let totalsOK: Int
    let taxesOK: Int
    let itemCountExact: Int
    let priceRecall: Double
    let nameRecall: Double
    let refused: Int

    init(_ scores: [Score]) {
        let n = Double(scores.count)
        count          = scores.count
        totalsOK       = scores.filter(\.totalOK).count
        taxesOK        = scores.filter(\.taxOK).count
        itemCountExact = scores.filter { $0.itemsParsed == $0.itemsExpected }.count
        priceRecall    = n == 0 ? 0 : scores.map(\.priceRecall).reduce(0, +) / n
        nameRecall     = n == 0 ? 0 : scores.map(\.nameRecall).reduce(0, +) / n
        refused        = scores.filter { $0.failure != nil }.count
    }
}

/// Accuracy floors the suite fails below.
///
/// ## The pipeline is NOT deterministic — this is the single most important thing here
///
/// Nine runs of the **same corpus against the same code**, 2026-09-11/12:
///
/// | metric | values | spread |
/// |---|---|---|
/// | TOTAL correct | 18, 19, 20, 20, 20, 19, 18, 19, 18 | **18–20 of 22 (82–91%)** |
/// | TAX correct | 19, then 20 × 8 | 19–20 |
/// | Item count exact | 15, 14, 14, 14, 15, 14, 14, 14, 15 | 14–15 |
/// | Price recall | 86, 84, 86, 86, 86, 86, 86, 87, 88 | 84–88% |
/// | Name recall | 78, 76, 77, 77, 77, 76, 78, 77, 83 | **76–83%** |
///
/// The ninth run widened name recall by five points on its own, which is the honest reason these
/// are stated as ranges and re-checked rather than fixed after one pass.
///
/// The cause is Tier 1: `VisionService` routes to Apple Foundation Models when available, and a
/// language model does not return the same answer twice. Four receipts (01, 03, 04, 13) take that
/// path on the simulator.
///
/// **So there is no single accuracy figure.** Quoting "91% totals" from one report — which is what
/// happened before these eight runs existed — reports the best sample as though it were the value.
/// It is 82–91%.
///
/// ## What that does to the floors
///
/// They sit **one below the observed minimum of eight runs**, not below a single measurement.
/// A floor at the minimum fires on noise, and a gate that fires on noise gets deleted — the first
/// draft had totals at 19 and would have failed two of these eight runs.
///
/// The cost is bluntness: with totals ranging 18–20 naturally, this can only catch a regression of
/// about **two receipts or more**. A single-receipt regression is invisible. The fix is not a
/// tighter floor — it is to make the benchmark deterministic by forcing the heuristic tier
/// (`fm.isAvailable`, `VisionService.swift:144`) and reporting Tier 1 separately. That is worth
/// doing before any model work, because a model cannot be evaluated against a moving baseline.
///
/// Raise the floors when an improvement lands, or the improvement is unprotected.
///
/// Deliberately NOT gated: **confidence calibration**. Its "wrong" side is the mean over the two
/// or three receipts whose total is wrong, and which receipts those are changes between runs.
private enum Floor {
    static let totalsOK       = 17      // of 22 — observed 18–20 across 9 runs
    static let taxesOK        = 18      // of 22 — observed 19–20
    static let itemCountExact = 13      // of 22 — observed 14–15
    static let priceRecall    = 0.80    // observed 0.84–0.88
    static let nameRecall     = 0.72    // observed 0.76–0.83
    /// The pipeline throwing on a real receipt is never acceptable, and has never happened, so
    /// this one is absolute rather than a floor with slack.
    static let maxRefused     = 0
}

// MARK: - Suite

@Suite("Receipt scan benchmark")
@MainActor
struct ReceiptBenchmark {

    /// Bundle first, then the source tree.
    ///
    /// `#filePath` points into the developer's checkout, which exists on a simulator run and
    /// **does not exist on a physical device** — the sandbox cannot see the Mac's filesystem. The
    /// corpus is copied into the test bundle by a build phase so the same suite runs in both
    /// places.
    ///
    /// ⚠️ This used to say *"Tier 1 (Apple Intelligence) only exists on device: every number this
    /// benchmark has produced describes Tier 2 heuristics alone."* **That is no longer true.** The
    /// 2026-09-11 simulator reports (iPhone 17 Pro, iOS 26.5) show receipts 01, 03, 04 and 13
    /// parsed by the `Apple Intelligence` tier, so the simulator now runs Tier 1 and the numbers
    /// below are a mix of both. Check the `tier` column before attributing a result to either.
    nonisolated private static var corpusDir: URL {
        if let override = ProcessInfo.processInfo.environment["XBILL_RECEIPT_CORPUS"] {
            return URL(fileURLWithPath: override)
        }
        final class Marker {}
        if let bundled = Bundle(for: Marker.self).resourceURL?
            .appendingPathComponent("ReceiptCorpus"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("labels").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ReceiptCorpus")
    }

    /// Whether there is anything to score.
    ///
    /// This drives `.enabled(if:)` rather than an early `return`, so a machine without the corpus
    /// reports the test as **skipped**. A fresh clone has no receipts and that is correct — but
    /// "no corpus" must never be indistinguishable from "22 receipts, all good". That is the exact
    /// false green this file produced once before: *"no corpus" in 0.024s, and passed.*
    nonisolated static var corpusIsPresent: Bool {
        let labels = corpusDir.appendingPathComponent("labels")
        let files = try? FileManager.default.contentsOfDirectory(at: labels, includingPropertiesForKeys: nil)
        return !(files?.filter { $0.pathExtension == "json" }.isEmpty ?? true)
    }

    @Test("Scores the shipped pipeline against the labelled corpus",
          .enabled(if: ReceiptBenchmark.corpusIsPresent))
    func benchmark() async throws {
        let fm = FileManager.default
        let corpusDir = Self.corpusDir
        let labelsDir = corpusDir.appendingPathComponent("labels")
        let imagesDir = corpusDir.appendingPathComponent("images")
        guard let labelFiles = try? fm.contentsOfDirectory(at: labelsDir, includingPropertiesForKeys: nil),
              !labelFiles.isEmpty else {
            // The trait said the corpus was there, so it going missing mid-run is a real fault.
            Issue.record("Corpus vanished between the enablement check and the run: \(corpusDir.path)")
            return
        }

        var scores: [Score] = []
        for file in labelFiles.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
            let id = file.deletingPathExtension().lastPathComponent
            let label = try JSONDecoder().decode(Label.self, from: Data(contentsOf: file))
            guard label.notes?.first != "TODO: not yet labelled" else { continue }

            let imageURL = imagesDir.appendingPathComponent(label.image)
            guard let image = UIImage(contentsOfFile: imageURL.path) else {
                print("[benchmark] \(id): could not load \(imageURL.path)")
                continue
            }
            do {
                let result = try await VisionService.shared.scanReceipt(from: image)
                scores.append(score(id: id, label: label, result: result))
            } catch {
                scores.append(Score(
                    id: id, failure: error.localizedDescription,
                    merchant: label.merchant ?? "—", tier: "—", confidence: 0, warning: nil,
                    totalExpected: label.totalDecimal, totalParsed: nil,
                    taxExpected: label.taxDecimal, taxParsed: nil,
                    itemsExpected: label.items.count, itemsParsed: 0,
                    priceRecall: 0, nameRecall: 0, parsedItems: [], expectedItems: []))
            }
        }

        guard !scores.isEmpty else {
            print("[benchmark] No receipts scored.")
            return
        }

        let text = report(scores)
        print("\n" + text)

        var outDir = corpusDir.appendingPathComponent("reports")
        if !fm.isWritableFile(atPath: corpusDir.path) {
            // Device run: the bundle is read-only. Write into the test process's own Documents so
            // the report can be pulled off afterwards.
            outDir = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(
                .documentDirectory, .userDomainMask, true)[0]).appendingPathComponent("reports")
        }
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        try? text.write(to: outDir.appendingPathComponent("receipt-benchmark-\(stamp).txt"),
                        atomically: true, encoding: .utf8)

        // The gate. Asserted after the report is printed and written, so a failing run still
        // leaves the full per-receipt evidence behind rather than only a threshold message.
        let agg = Aggregate(scores)
        #expect(agg.refused <= Floor.maxRefused,
                "the pipeline threw on \(agg.refused) of \(agg.count) real receipts")
        #expect(agg.totalsOK >= Floor.totalsOK,
                "TOTAL correct \(agg.totalsOK)/\(agg.count), floor \(Floor.totalsOK)")
        #expect(agg.taxesOK >= Floor.taxesOK,
                "TAX correct \(agg.taxesOK)/\(agg.count), floor \(Floor.taxesOK)")
        #expect(agg.itemCountExact >= Floor.itemCountExact,
                "item count exact \(agg.itemCountExact)/\(agg.count), floor \(Floor.itemCountExact)")
        #expect(agg.priceRecall >= Floor.priceRecall,
                Comment(rawValue: String(format: "price recall %.2f, floor %.2f",
                                         agg.priceRecall, Floor.priceRecall)))
        #expect(agg.nameRecall >= Floor.nameRecall,
                Comment(rawValue: String(format: "name recall %.2f, floor %.2f",
                                         agg.nameRecall, Floor.nameRecall)))
    }
}
