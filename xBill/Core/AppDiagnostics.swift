//
//  AppDiagnostics.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  General-purpose DEBUG-only on-device diagnostic logger. Originally added
//  under a payment-specific name while investigating the Venmo/PayPal
//  payment-return defect (see diagnostics/2026-07-27-paypal-handoff/), then
//  generalised into one categorised log per app so future investigations do
//  not scatter across multiple ad-hoc loggers. DEBUG-only: the whole
//  implementation compiles out of Release builds.
//
//  Three sinks so evidence survives regardless of tooling:
//    1. os_log        — visible in Console.app
//    2. print         — captured by `devicectl device process launch --console`
//    3. Documents log — pulled with `devicectl device copy from`
//

import Foundation
import Supabase
import OSLog

enum AppDiagnostics {

    enum Category: String, Sendable {
        case payment, auth, balance, lifecycle, sync
    }

    #if DEBUG

    private static let logger = Logger(subsystem: "com.vijaygoyal.xbill", category: "AppDiagnostics")
    private static let lock = NSLock()
    private static let maxBytes = 2 * 1024 * 1024   // 2 MB

    nonisolated(unsafe) private static var didStartSession = false

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("xbill-diagnostics.log")
    }

    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Logs a single structured diagnostic event.
    /// - Parameters:
    ///   - category: Which subsystem this event belongs to, e.g. `.balance`.
    ///   - event: Stable event name, e.g. `"HomeViewModel.loadAll.catch"`.
    ///   - fields: Ordered key/value context. Order is preserved for readability.
    static func log(_ category: Category, _ event: String, _ fields: [(String, Any)] = []) {
        let rendered = fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        let line = "[\(timestampFormatter.string(from: Date()))] [\(category.rawValue)] \(event)"
            + (rendered.isEmpty ? "" : " " + rendered)

        logger.log("\(line, privacy: .public)")
        print("XBILLDIAG \(line)")
        append(line)
    }

    /// Fully describes an error, including NSError domain/code and any underlying error.
    /// `localizedDescription` alone hides the distinction between, for example,
    /// NSURLErrorCancelled (-999) and NSURLErrorNetworkConnectionLost (-1005).
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "swiftType=\(type(of: error))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "localized=\(nsError.localizedDescription)"
        ]
        if let appError = error as? AppError { parts.append("appError=\(appError)") }
        // PostgREST puts the actionable part in `code`/`detail`, not in the localized
        // message. PGRST116 with "The result contains 0 rows" reads as a JSON coercion
        // fault through `localizedDescription` alone, which cost a full debugging cycle.
        if let pgError = error as? PostgrestError {
            parts.append("pgCode=\(pgError.code ?? "-")")
            parts.append("pgDetail=\(pgError.detail ?? "-")")
            parts.append("pgHint=\(pgError.hint ?? "-")")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)#\(underlying.code):\(underlying.localizedDescription)")
        }
        return "{" + parts.joined(separator: " | ") + "}"
    }

    /// Absolute path of the on-device log, for retrieval instructions.
    static var logPath: String { fileURL?.path ?? "unavailable" }

    private static func append(_ line: String) {
        guard let url = fileURL, let data = (line + "\n").data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }

        if !didStartSession {
            didStartSession = true
            let header = "\n===== SESSION START \(timestampFormatter.string(from: Date())) =====\n"
            if let headerData = header.data(using: .utf8) { write(headerData, to: url) }
        }
        write(data, to: url)
        rotateIfNeeded(url)
    }

    private static func write(_ data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Keeps the newest half once the log passes the cap, so an append-only file on a
    /// device cannot grow without bound.
    private static func rotateIfNeeded(_ url: URL) {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes else { return }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(max(1, lines.count / 2)).joined(separator: "\n")
        let header = "===== ROTATED \(timestampFormatter.string(from: Date())) =====\n"
        try? (header + kept + "\n").data(using: .utf8)?.write(to: url, options: .atomic)
    }

    #else

    static func log(_ category: Category, _ event: String, _ fields: [(String, Any)] = []) {}
    static func describe(_ error: Error) -> String { "" }
    static var logPath: String { "unavailable" }

    #endif
}
