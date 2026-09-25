//
//  LineCaptureAnalysis.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  SCAN-ML-01 step 3 — the diagnosis that decides whether step 4 needs a model.
//
//  The benchmark says *how much* the pipeline gets wrong. It cannot say *why*, and the difference
//  decides whether a trainable line classifier is worth building. A classifier chooses a label for
//  a line it can see. It cannot invent a line Vision never returned, and it cannot re-pair a price
//  with the right name when the geometry misfiled it.
//
//  So for every ground-truth item this asks one question of the raw OCR, before any parsing:
//
//      Is the NAME present in some line?  Is the PRICE present in some line?
//
//  and crosses that with whether the parser actually produced the item. The four buckets are:
//
//      NEITHER    — nothing was captured. Unreachable by any parser or model. Get a better photo.
//      NAME ONLY  — the price was never read. Same: the number does not exist to be classified.
//      PRICE ONLY — the name was never read.
//      BOTH       — the evidence was there. If the parser still missed it, that is OURS to fix,
//                   and only these rows are candidates a classifier could help with.
//
//  Writes a report next to the benchmark's. Prints nothing: stdout from the test process does not
//  reach xcodebuild, which is why the benchmark writes a file too.
//

import Testing
import Foundation
import UIKit
@testable import xBill

private struct CapItem: Decodable {
    let name: String
    let qty: Int
    let unitPrice: String
    var total: Decimal { (Decimal(string: unitPrice) ?? .zero) * Decimal(qty) }
}

private struct CapLabel: Decodable {
    let image: String
    let merchant: String?
    let items: [CapItem]
    let total: String?
    let tax: String?
}

private enum Capture: String {
    case both      = "BOTH"
    case nameOnly  = "NAME ONLY"
    case priceOnly = "PRICE ONLY"
    case neither   = "NEITHER"
}

@Suite("Line capture analysis (SCAN-ML-01 step 3)")
@MainActor
struct LineCaptureAnalysis {

    nonisolated static var corpusDir: URL {
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
            .deletingLastPathComponent().appendingPathComponent("ReceiptCorpus")
    }

    /// Opt-in. This re-OCRs all 22 images, which is ~90s on top of the benchmark's own pass, and
    /// it is a **diagnosis** rather than a gate — it asserts nothing about accuracy. Run it when
    /// the question is *why* the pipeline is wrong, not *how much*:
    ///
    ///     XBILL_CAPTURE_ANALYSIS=1 xcodebuild test -project xBill.xcodeproj -scheme xBill \
    ///       -destination "id=<sim>" -only-testing:xBillTests/LineCaptureAnalysis
    nonisolated static var corpusPresent: Bool {
        guard ProcessInfo.processInfo.environment["XBILL_CAPTURE_ANALYSIS"] != nil else { return false }
        return FileManager.default.fileExists(atPath: corpusDir.appendingPathComponent("images").path)
    }

    @Test("classify every ground-truth item by what the OCR captured",
          .enabled(if: LineCaptureAnalysis.corpusPresent))
    func analyse() async throws {
        let service   = VisionService.shared
        let fm        = FileManager.default
        let dir       = Self.corpusDir
        let labelsDir = dir.appendingPathComponent("labels")
        let imagesDir = dir.appendingPathComponent("images")
        let files     = (try? fm.contentsOfDirectory(at: labelsDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        var out = "LINE CAPTURE ANALYSIS — \(ISO8601DateFormatter().string(from: Date()))\n"
        out += String(repeating: "─", count: 96) + "\n"
        out += "For each ground-truth item: was its NAME in the raw OCR? its PRICE? and did we parse it?\n"
        out += "Only BOTH rows are ours to fix. NEITHER / NAME ONLY / PRICE ONLY are capture limits —\n"
        out += "no parser and no classifier can label a line that was never returned.\n"
        out += String(repeating: "─", count: 96) + "\n"
        out += "id  merchant              items  BOTH  NAMEONLY  PRICEONLY  NEITHER   parsed  missed-with-evidence\n"

        var totals: [Capture: Int] = [:]
        var grandItems = 0, grandParsed = 0, grandMissedWithEvidence = 0
        var falsePositives = 0
        var detail = "\n" + String(repeating: "─", count: 96) + "\nMISSED ROWS THAT HAD THE EVIDENCE (these are ours)\n"
        detail += String(repeating: "─", count: 96) + "\n"
        var capDetail = "\n" + String(repeating: "─", count: 96) + "\nNOT CAPTURED BY OCR AT ALL (no parser or model can reach these)\n"
        var fpDetail = "\n" + String(repeating: "─", count: 96) + "\nPARSED ROWS MATCHING NO TRUTH NAME\n"
        fpDetail += String(repeating: "─", count: 96) + "\n"
        capDetail += String(repeating: "─", count: 96) + "\n"

        for file in files {
            guard let label = try? JSONDecoder().decode(CapLabel.self, from: Data(contentsOf: file))
            else { continue }
            let id = file.deletingPathExtension().lastPathComponent
            let imageURL = imagesDir.appendingPathComponent(label.image)
            guard let image = UIImage(contentsOfFile: imageURL.path) else { continue }

            // Raw OCR, plus the fragment merge, because a split price IS captured — just in halves.
            let lines  = (try? await service.recognizeText(in: image)) ?? []
            let merged = service.mergeSplitPrices(lines)
            let texts  = merged.map(\.text)
            let amountsInOCR: [Decimal] = merged.compactMap { service.extractDecimal(from: $0.text) }

            let parsed = try? await service.scanReceipt(from: image, usesFoundationModels: false)
            let parsedItems = parsed?.receipt.items ?? []

            // The parser's own name cleanup, so "was the name captured" asks the same question
            // the parser does rather than a stricter one.
            func cleanedName(_ t: String) -> String {
                service.stripCatalogCode(
                    from: service.stripQuantityPrefix(from: service.stripPrice(from: t)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var counts: [Capture: Int] = [:]
            var parsedHits = 0, missedWithEvidence = 0
            var priceBudget = amountsInOCR

            for item in label.items {
                // NAME present: any OCR line within the benchmark's match threshold, tested BOTH
                // raw and after the same cleanup the parser applies.
                //
                // ⚠️ The first version tested raw text only and was wrong. ALDI's lines read
                // `365992 Tortilla Chips` against a truth of `Tortilla Chips` — 0.68 similarity,
                // so every one of its 9 items was scored "name never captured" while the parser
                // was in fact getting all 9 right. The report then claimed 64 rows parsed out of
                // 56 captured, which is impossible and is what exposed it.
                //
                // The lesson is the same one receipt 12 taught: an instrument that does not apply
                // the same transformation as the thing it measures is measuring something else.
                let nameSeen = texts.contains {
                    nameSimilarity($0, item.name) >= nameMatchThreshold
                        || nameSimilarity(cleanedName($0), item.name) >= nameMatchThreshold
                }
                // PRICE present: consume from a budget so two items at the same price need two
                // sightings — otherwise one `2.49` would vouch for every 2.49 on the receipt.
                var priceSeen = false
                if let idx = priceBudget.firstIndex(of: item.total) {
                    priceBudget.remove(at: idx); priceSeen = true
                }
                let cap: Capture = nameSeen && priceSeen ? .both
                                 : nameSeen ? .nameOnly
                                 : priceSeen ? .priceOnly : .neither
                counts[cap, default: 0] += 1
                totals[cap, default: 0] += 1

                let didParse = parsedItems.contains {
                    nameSimilarity($0.name, item.name) >= nameMatchThreshold && $0.totalPrice == item.total
                }
                if didParse { parsedHits += 1 }
                if !didParse && cap == .both {
                    missedWithEvidence += 1
                    detail += "\(id)  \(item.name) = \(item.total)\n"
                }
                if !didParse && cap != .both {
                    capDetail += "\(id)  [\(cap.rawValue)] \(item.name) = \(item.total)\n"
                }
            }

            // Parsed rows matching no ground-truth name. NOT all of these are inventions — a real
            // item whose name OCR'd badly lands here too — so the figure is an upper bound on
            // spurious rows, and is labelled as such in the report.
            for p in parsedItems where !label.items.contains(where: {
                nameSimilarity(p.name, $0.name) >= nameMatchThreshold
            }) {
                falsePositives += 1
                // Flag the ones that are a *classification* error — a non-item row sold as an
                // item — separately from a real item whose name simply read badly. This is the
                // half of the failure space a line classifier would actually address.
                let truthTotal = label.total.flatMap { Decimal(string: $0) }
                let truthTax   = label.tax.flatMap { Decimal(string: $0) }
                let looksLikeTotal = (truthTotal.map { p.totalPrice == $0 } ?? false)
                    || (truthTax.map { p.totalPrice == $0 } ?? false)
                let note = looksLikeTotal ? "  <- amount equals the receipt's TOTAL or TAX" : ""
                fpDetail += "\(id)  \(p.name) = \(p.totalPrice)\(note)\n"
            }

            grandItems += label.items.count
            grandParsed += parsedHits
            grandMissedWithEvidence += missedWithEvidence

            func pad(_ s: String, _ n: Int) -> String {
                s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count)
            }
            out += pad(id, 4) + pad(label.merchant ?? "—", 22)
                 + pad("\(label.items.count)", 7)
                 + pad("\(counts[.both] ?? 0)", 6)
                 + pad("\(counts[.nameOnly] ?? 0)", 10)
                 + pad("\(counts[.priceOnly] ?? 0)", 11)
                 + pad("\(counts[.neither] ?? 0)", 10)
                 + pad("\(parsedHits)", 8)
                 + "\(missedWithEvidence)\n"
        }

        let both = totals[.both] ?? 0
        out += String(repeating: "─", count: 96) + "\n"
        out += "TOTAL ground-truth item rows          \(grandItems)\n"
        out += "  captured BOTH name and price        \(both)\n"
        out += "  name only (price never read)        \(totals[.nameOnly] ?? 0)\n"
        out += "  price only (name never read)        \(totals[.priceOnly] ?? 0)\n"
        out += "  neither                             \(totals[.neither] ?? 0)\n"
        out += "parsed correctly (name AND price)     \(grandParsed)\n"
        out += "MISSED DESPITE FULL EVIDENCE          \(grandMissedWithEvidence)   <- the only rows a parser or model can win back\n"
        out += "parsed rows matching no truth name    \(falsePositives)   <- UPPER BOUND on spurious rows;\n"
        out += "                                                 a real item with a badly-read name lands here too\n"
        let ceiling = grandItems == 0 ? 0 : Double(both) / Double(grandItems) * 100
        out += String(format: "\nCEILING FOR ANY PARSER OR MODEL: %.0f%% (%d of %d rows have both halves captured)\n",
                      ceiling, both, grandItems)
        out += detail + capDetail + fpDetail

        let reports = dir.appendingPathComponent("reports")
        try? fm.createDirectory(at: reports, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? out.write(to: reports.appendingPathComponent("line-capture-\(stamp).txt"),
                       atomically: true, encoding: .utf8)
        #expect(grandItems > 0, "no ground-truth items were read")
    }
}
