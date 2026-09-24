//
//  BenchmarkMetricTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Tests for the *measuring instrument*, not the thing it measures.
//
//  These exist because the benchmark's name metric was blind for its whole life and nobody
//  noticed: it matched a parsed name against a ground-truth name with a two-way substring test,
//  so `365992 Tortilla Chips` "contained" `Tortilla Chips` and scored as a hit with the till's
//  SKU still attached. SCAN-RULE-02 then stripped that junk from 11 of 11 such names across 8
//  receipts and the reported figure did not move at all — 0.804 before, 0.804 after.
//
//  A metric that cannot see the defect it is meant to judge is worse than no metric, because it
//  is trusted. SCAN-ML-01 step 4 uses this number to decide whether a trainable line classifier
//  is worth building, so it has to be right.
//

import Testing
import Foundation
@testable import xBill

@Suite("Receipt benchmark metric")
struct BenchmarkMetricTests {

    // MARK: - The regression that started this

    /// The exact pair that fooled the old metric. If this ever passes as a match again, the
    /// benchmark has gone blind and every name figure it reports is meaningless.
    @Test("A till SKU glued to a correct name is not a match")
    func skuPrefixIsNotAMatch() {
        let s = nameSimilarity("365992 Tortilla Chips", "Tortilla Chips")
        #expect(s < nameMatchThreshold,
                "similarity \(s) — the old substring metric scored this a full hit")
    }

    /// The other shapes SCAN-RULE-02 fixed, and one the parser still gets wrong. All must read as
    /// misses, otherwise cleaning them up would again be invisible.
    @Test("Junk attached to a name is a miss, whichever end it is on")
    func attachedJunkIsAMiss() {
        let cases = [
            ("THERMACARE 195882990040", "THERMACARE"),        // trailing UPC
            ("1158 ORG ARUGULA",        "ORG ARUGULA"),       // leading PLU
            ("BFR PINEAPPLE COCO 6. 99 F", "BFR PINEAPPLE COCO"), // the price, still in the name
            ("WT BANANAS",              "BANANAS"),           // weight marker
        ]
        for (parsed, truth) in cases {
            #expect(nameSimilarity(parsed, truth) < nameMatchThreshold,
                    "\(parsed) vs \(truth) scored \(nameSimilarity(parsed, truth))")
        }
    }

    // MARK: - ...without becoming so strict it is useless

    /// Real OCR noise from the corpus. These are unambiguously the same item and must still count,
    /// or the metric would punish the parser for Vision's misreads and never reach a usable score.
    @Test("Character-level OCR noise still counts as recovered")
    func ocrNoiseStillMatches() {
        let cases = [
            ("DEEP DRY GARLIC CHUTNEY 150Gas", "DEEP DRY GARLIC CHUTNEY 150Gms"),
            ("DEEP RED CHORI 2IBS",            "DEEP RED CHORI 2LBS"),
            ("NEEM OIL 200MI",                 "NEEM OIL 200ML"),
            ("SEL VALUR PAPDI FLAT /LB",       "SCL VALOR PAPDI FLAT /LB"),
        ]
        for (parsed, truth) in cases {
            #expect(nameSimilarity(parsed, truth) >= nameMatchThreshold,
                    "\(parsed) vs \(truth) scored \(nameSimilarity(parsed, truth))")
        }
    }

    @Test("An exact name, ignoring case and punctuation, is a perfect match")
    func exactMatchIsOne() {
        #expect(nameSimilarity("Tortilla Chips", "TORTILLA CHIPS!") == 1.0)
        #expect(nameSimilarity("", "") == 1.0)
    }

    @Test("Unrelated names do not match")
    func unrelatedNamesDoNotMatch() {
        #expect(nameSimilarity("AVOCADO", "SOURDOUGH BREAD") < 0.4)
    }

    // MARK: - editDistance itself, so the threshold rests on something checked

    @Test("Edit distance agrees with known values")
    func editDistanceIsCorrect() {
        #expect(editDistance(Array("kitten"), Array("sitting")) == 3)
        #expect(editDistance(Array("flaw"), Array("lawn")) == 2)
        #expect(editDistance(Array(""), Array("abc")) == 3)
        #expect(editDistance(Array("same"), Array("same")) == 0)
    }

    /// Length-relative, deliberately: the same two wrong characters matter more in a short name.
    @Test("Similarity is relative to the longer name")
    func similarityIsLengthRelative() {
        let short = nameSimilarity("ab", "cb")                         // 1 of 2 wrong
        let long  = nameSimilarity("abcdefghij", "cbcdefghij")         // 1 of 10 wrong
        #expect(short < long)
    }
}
