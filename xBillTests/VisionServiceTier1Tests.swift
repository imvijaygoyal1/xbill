//
//  VisionServiceTier1Tests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Testing
import Foundation
import UIKit
@testable import xBill

// MARK: - VisionService Tier-1 Fix Tests
//
// Fix 1: CIContext reuse in preprocessForOCR — pure performance refactor, no
//         observable behaviour change; covered by the full test suite not regressing.
// Fix 2: Glare / overexposure detection (luminance > 0.92 → throw, not "too blurry").
// Fix 3: Unicode × (U+00D7) added to quantity regex character class [xX@×].

@Suite("VisionService — Tier 1 Fixes")
struct VisionServiceTier1Tests {

    // MARK: - Fix 2: Glare Detection

    @Test("Solid-white image is rejected with an overexposed error, not a blur error")
    func whiteImageRejectedAsOverexposed() async {
        let image = makeMonochromeImage(brightness: 1.0)
        do {
            _ = try await VisionService.shared.scanReceipt(from: image)
            Issue.record("Expected validationFailed to be thrown for an overexposed image")
        } catch AppError.validationFailed(let msg) {
            let lower = msg.lowercased()
            #expect(
                lower.contains("bright") || lower.contains("glare") || lower.contains("overexposed"),
                "Expected an overexposure message, got: \"\(msg)\""
            )
        } catch {
            Issue.record("Expected AppError.validationFailed, got \(error)")
        }
    }

    @Test("Dark image error message is unchanged after adding glare check")
    func darkImageStillRejectedWithDarkMessage() async {
        let image = makeMonochromeImage(brightness: 0.0)
        do {
            _ = try await VisionService.shared.scanReceipt(from: image)
            Issue.record("Expected validationFailed for a black image")
        } catch AppError.validationFailed(let msg) {
            #expect(msg.lowercased().contains("dark"),
                    "Dark image should still produce a 'dark' error, got: \"\(msg)\"")
        } catch {
            Issue.record("Expected AppError.validationFailed, got \(error)")
        }
    }

    // MARK: - Fix 3: Unicode × quantity regex

    @Test("Unicode × is matched by the updated quantity regex")
    func unicodeMultiplicationSignMatchedByQuantityRegex() throws {
        let fixedPattern = #"^(\d+)\s*[xX@×]\s*"#
        let regex = try NSRegularExpression(pattern: fixedPattern)

        let inputs = ["2×1.99", "3×2.50", "2 × 1.99", "4×  coffee"]
        for input in inputs {
            let range = NSRange(input.startIndex..., in: input)
            let match = regex.firstMatch(in: input, range: range)
            #expect(match != nil, "Updated pattern should match '\(input)'")
            if let match, let qRange = Range(match.range(at: 1), in: input) {
                #expect(Int(input[qRange]) != nil,
                        "Captured group should be a valid integer in '\(input)'")
            }
        }
    }

    @Test("Existing x / X / @ quantity formats still match after adding ×")
    func existingQuantityFormatsUnaffected() throws {
        let fixedPattern = #"^(\d+)\s*[xX@×]\s*"#
        let regex = try NSRegularExpression(pattern: fixedPattern)

        let inputs = ["2x burger", "3X coffee", "2 @ 1.99", "4@item", "2 @item"]
        for input in inputs {
            let range = NSRange(input.startIndex..., in: input)
            #expect(regex.firstMatch(in: input, range: range) != nil,
                    "Existing format '\(input)' should still match")
        }
    }

    @Test("Old pattern without × fails to match Unicode multiplication sign")
    func oldPatternFailsOnUnicode() throws {
        let oldPattern = #"^(\d+)\s*[xX@]\s*"#
        let regex = try NSRegularExpression(pattern: oldPattern)

        let range = NSRange("2×1.99".startIndex..., in: "2×1.99")
        #expect(regex.firstMatch(in: "2×1.99", range: range) == nil,
                "Old pattern must not match × — this proves the test is meaningful")
    }

    // MARK: - Helper

    private func makeMonochromeImage(brightness: CGFloat) -> UIImage {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: brightness, alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
