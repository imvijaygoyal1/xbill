//
//  ExportService.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import PDFKit
import UIKit

// MARK: - ExportService
// Must be @MainActor because PDF generation uses UIKit drawing APIs.

@MainActor
final class ExportService {
    static let shared = ExportService()
    private init() {}

    // MARK: - CSV

    /// Returns UTF-8 CSV data for all expenses in a group.
    func generateCSV(
        group: BillGroup,
        expenses: [Expense],
        memberNames: [UUID: String]
    ) -> Data {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        // M-23: fix locale so dates are always formatted as ISO-8601 regardless of the
        // device locale (e.g. Persian calendar in Iran would otherwise change digit glyphs).
        df.locale = Locale(identifier: "en_US_POSIX")

        var lines = ["Date,Title,Category,Amount,Currency,Paid By,Notes,Recurrence"]
        for expense in expenses.sorted(by: { $0.createdAt < $1.createdAt }) {
            let date      = df.string(from: expense.createdAt)
            let title     = csvEscape(expense.title)
            let category  = expense.category.displayName
            let amount    = String(format: "%.2f", NSDecimalNumber(decimal: expense.amount).doubleValue)
            let currency  = expense.currency
            let paidBy    = csvEscape(expense.payerID.flatMap { memberNames[$0] } ?? "Unknown")
            let notes     = csvEscape(expense.notes ?? "")
            let recur     = expense.recurrence == .none ? "" : expense.recurrence.shortLabel
            lines.append("\(date),\(title),\(category),\(amount),\(currency),\(paidBy),\(notes),\(recur)")
        }
        return lines.joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    // MARK: - PDF

    /// Returns PDF data for a group expense report.
    func generatePDF(
        group: BillGroup,
        expenses: [Expense],
        memberNames: [UUID: String],
        balances: [UUID: Decimal]
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 portrait
        let margin:   CGFloat = 48
        let contentW: CGFloat = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()

            var y: CGFloat = margin

            // ── Header ──
            y = drawText(
                "\(group.emoji) \(group.name)",
                at: CGPoint(x: margin, y: y),
                font: .boldSystemFont(ofSize: 22),
                maxWidth: contentW
            ) + 6

            let df = DateFormatter(); df.dateStyle = .medium
            y = drawText(
                "Expense Report · Generated \(df.string(from: Date()))",
                at: CGPoint(x: margin, y: y),
                font: .systemFont(ofSize: 11),
                color: .secondaryLabel,
                maxWidth: contentW
            ) + 4

            y = drawHRule(at: y, margin: margin, width: pageRect.width) + 14

            // ── Summary ──
            let totalAmount = expenses.reduce(Decimal.zero) { $0 + $1.amount }
            let fmt = currencyFormatter(code: group.currency)
            let totalStr = fmt.string(from: totalAmount as NSDecimalNumber) ?? "\(totalAmount)"

            y = drawSectionTitle("Summary", at: CGPoint(x: margin, y: y)) + 8

            y = drawText(
                "Total expenses: \(expenses.count)   Total amount: \(totalStr)",
                at: CGPoint(x: margin, y: y),
                font: .systemFont(ofSize: 12),
                maxWidth: contentW
            ) + 12

            // ── Balances ──
            y = drawSectionTitle("Balances", at: CGPoint(x: margin, y: y)) + 8

            for (userID, balance) in balances.sorted(by: { abs($0.value) > abs($1.value) }) {
                let name = memberNames[userID] ?? "Unknown"
                let direction: String
                if balance > 0 {
                    direction = "is owed \(fmt.string(from: balance as NSDecimalNumber) ?? "")"
                } else if balance < 0 {
                    direction = "owes \(fmt.string(from: (-balance) as NSDecimalNumber) ?? "")"
                } else {
                    direction = "is settled"
                }
                y = drawText(
                    "• \(name): \(direction)",
                    at: CGPoint(x: margin + 8, y: y),
                    font: .systemFont(ofSize: 12),
                    maxWidth: contentW - 8
                ) + 4
            }
            y += 8

            y = drawHRule(at: y, margin: margin, width: pageRect.width) + 14

            // ── Expense Table ──
            y = drawSectionTitle("Expenses", at: CGPoint(x: margin, y: y)) + 10

            // Column x positions (content width = 499pt; right edge = margin + 499 = 547).
            // M-24: shrink Date and Category to give "Paid By" enough room to avoid clipping.
            //   Date:     48 ..  96  (48pt)
            //   Title:    96 .. 246  (150pt)
            //   Category: 246 .. 346 (100pt)
            //   Amount:   346 .. 426 (80pt)
            //   Paid By:  426 .. 546 (120pt) — was starting at 508, now 426 with 120pt width
            let cols: [(header: String, x: CGFloat, maxW: CGFloat)] = [
                ("Date",     margin,       48),
                ("Title",    margin +  48, 150),
                ("Category", margin + 198, 100),
                ("Amount",   margin + 298,  80),
                ("Paid By",  margin + 378, 120)
            ]

            // Header row
            for col in cols {
                drawText(col.header, at: CGPoint(x: col.x, y: y), font: .boldSystemFont(ofSize: 9),
                         color: .secondaryLabel, maxWidth: col.maxW)
            }
            y += 14

            drawHRule(at: y - 2, margin: margin, width: pageRect.width, alpha: 0.4)
            y += 4

            // Rows
            df.dateFormat = "MMM d, yyyy"
            var alternate = false

            for expense in expenses.sorted(by: { $0.createdAt < $1.createdAt }) {
                if y > pageRect.height - 60 {
                    ctx.beginPage()
                    y = margin
                }

                if alternate {
                    let rowRect = CGRect(x: margin, y: y - 2,
                                        width: pageRect.width - margin * 2, height: 16)
                    UIColor.systemGray6.setFill()
                    UIBezierPath(roundedRect: rowRect, cornerRadius: 2).fill()
                }
                alternate.toggle()

                let amtStr  = fmt.string(from: expense.amount as NSDecimalNumber) ?? "\(expense.amount)"
                let paidBy  = expense.payerID.flatMap { memberNames[$0] } ?? "Unknown"
                let values  = [
                    df.string(from: expense.createdAt),
                    expense.title + (expense.recurrence != .none ? " ↻" : ""),
                    expense.category.displayName,
                    amtStr,
                    paidBy
                ]
                for (col, val) in zip(cols, values) {
                    drawText(val, at: CGPoint(x: col.x, y: y),
                             font: .systemFont(ofSize: 9),
                             maxWidth: col.maxW - 6)
                }
                y += 16
            }
        }
    }

    // MARK: - Temp file helpers

    /// Writes `data` to a uniquely named temp file, preventing concurrent exports from
    /// overwriting each other and stale files from accumulating with the same name.
    /// The UUID suffix is inserted before the file extension: "name_<uuid8>.ext".
    func writeTemp(data: Data, filename: String) throws -> URL {
        let suffix = UUID().uuidString.prefix(8)
        let uniqueName: String
        if let dotRange = filename.range(of: ".", options: .backwards) {
            let base = String(filename[filename.startIndex ..< dotRange.lowerBound])
            let ext  = String(filename[dotRange.lowerBound...])
            uniqueName = "\(base)_\(suffix)\(ext)"
        } else {
            uniqueName = "\(filename)_\(suffix)"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName)
        try data.write(to: url)
        return url
    }

    // MARK: - Private drawing helpers

    @discardableResult
    private func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor = .label,
        maxWidth: CGFloat
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let boundingRect = text.boundingRect(
            with: CGSize(width: maxWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil
        )
        text.draw(in: CGRect(origin: point, size: boundingRect.size), withAttributes: attrs)
        return point.y + boundingRect.height
    }

    @discardableResult
    private func drawSectionTitle(_ title: String, at point: CGPoint) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.secondaryLabel,
            .kern: 0.8
        ]
        title.uppercased().draw(at: point, withAttributes: attrs)
        return point.y + 14
    }

    @discardableResult
    private func drawHRule(at y: CGFloat, margin: CGFloat, width: CGFloat, alpha: CGFloat = 1) -> CGFloat {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: width - margin, y: y))
        UIColor.separator.withAlphaComponent(alpha).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        return y + 1
    }

    private func currencyFormatter(code: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n")
            ? "\"\(escaped)\""
            : escaped
    }
}
