//
//  ReceiptBenchmark.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Scores the real scan pipeline against a corpus of photographed receipts with hand-written
//  ground truth. This is a **measurement**, not a gate: it asserts nothing about accuracy,
//  because there is no threshold anyone has earned the right to assert yet.
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
    let totalsOK = scores.filter(\.totalOK).count
    let taxesOK  = scores.filter(\.taxOK).count
    let exact    = scores.filter { $0.itemsParsed == $0.itemsExpected }.count
    let avgPrice = scores.map(\.priceRecall).reduce(0, +) / n
    let avgName  = scores.map(\.nameRecall).reduce(0, +) / n

    out += "TOTAL correct     \(totalsOK)/\(scores.count)   \(Int((Double(totalsOK)/n*100).rounded()))%\n"
    out += "TAX correct       \(taxesOK)/\(scores.count)   \(Int((Double(taxesOK)/n*100).rounded()))%\n"
    out += "Item count exact  \(exact)/\(scores.count)   \(Int((Double(exact)/n*100).rounded()))%\n"
    out += "Price recall      \(Int((avgPrice*100).rounded()))%   (ground-truth line amounts found)\n"
    out += "Name recall       \(Int((avgName*100).rounded()))%   (ground-truth item names surviving)\n"

    let scanned = scores.filter { $0.failure == nil }
    let refused = scores.count - scanned.count
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

// MARK: - Suite

@Suite("Receipt scan benchmark")
@MainActor
struct ReceiptBenchmark {

    /// Repo-relative, derived from this file's own location so it needs no configuration.
    private var corpusDir: URL {
        if let override = ProcessInfo.processInfo.environment["XBILL_RECEIPT_CORPUS"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ReceiptCorpus")
    }

    @Test("Scores the shipped pipeline against the labelled corpus")
    func benchmark() async throws {
        let fm = FileManager.default
        let labelsDir = corpusDir.appendingPathComponent("labels")
        let imagesDir = corpusDir.appendingPathComponent("images")
        guard let labelFiles = try? fm.contentsOfDirectory(at: labelsDir, includingPropertiesForKeys: nil),
              !labelFiles.isEmpty else {
            print("\n[benchmark] No corpus at \(corpusDir.path) — nothing to measure.\n")
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

        let outDir = corpusDir.appendingPathComponent("reports")
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        try? text.write(to: outDir.appendingPathComponent("receipt-benchmark-\(stamp).txt"),
                        atomically: true, encoding: .utf8)
    }
}
