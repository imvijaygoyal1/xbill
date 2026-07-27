# Payment Handle Experience + Unified Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an unusable Venmo/PayPal handle discoverable by its owner before anyone tries to pay, stop third-party payment failures reading as xBill failures, and unify device diagnostics into one categorised log per app.

**Architecture:** A single `PaymentHandleValidator` becomes the only source of truth for handle rules, consumed by both `ProfileView` (input) and `PaymentLinkService` (output), which today disagree. A "test your link" row lets the handle's owner verify it in one tap against the provider itself, rather than xBill scraping a third party. `GroupDetailView` shows the destination handle on the payment button, explains an absent one, and prompts to mark settled on return. `PaymentDiagnostics` becomes `AppDiagnostics`: one categorised, size-capped, DEBUG-only log per app.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, Swift Testing (`@Test`/`#expect`), XCTest for UI tests, XcodeGen, Supabase Postgres.

**Spec:** `docs/superpowers/specs/2026-07-26-payment-handles-and-diagnostics-design.md`

## Global Constraints

- **PayPal.Me handle rule:** 3–20 characters, ASCII letters and digits only. No `.`, `-`, `_`.
- **Venmo handle rule:** 5–30 characters, ASCII letters, digits, `-` and `_`. No `.`.
- A leading `@` is stripped before validation for both providers. Whitespace is trimmed.
- **The two charsets must not be merged.** `-`/`_` are legal for Venmo and illegal for PayPal.
- **Verified provider URLs** (do not change without re-verifying):
  - PayPal payment: `https://paypal.me/<handle>/<amount><CURRENCY>`
  - PayPal profile (test link, no amount): `https://paypal.me/<handle>`
  - Venmo payment: `venmo://paycharge?txn=pay&recipients=<handle>&amount=<amount>&note=<note>`
  - Venmo profile (test link): `https://venmo.com/u/<handle>` — returns 404 for a nonexistent handle
- **Seeded payment handles stay `NULL`.** Never seed a handle that is not a real profile.
- `AppDiagnostics` is `#if DEBUG` only — it records group names and amounts and must never ship.
- New Swift files require `xcodegen generate` before building.
- Test command:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:<target>`
- Commit messages end with: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

## File Structure

| File | Responsibility |
|---|---|
| `xBill/Services/PaymentHandleValidator.swift` (create) | Sole source of truth for handle rules and normalisation. Pure, no I/O. |
| `xBill/Services/PaymentLinkService.swift` (modify) | Builds payment + profile URLs. Delegates all validation to the validator. |
| `xBill/Views/Profile/ProfileView.swift` (modify) | Handle entry validation messages; "test your link" rows. |
| `xBill/Views/Groups/GroupDetailView.swift` (modify) | Handle on payment button; no-handle explanation; return prompt. |
| `supabase/seed_app_store_review_account.sql` (modify) | Amounts scaled ÷50. |
| `SETUP_REVIEW_ACCOUNT.md` (modify) | Documented balances kept in sync with the seed. |
| `xBill/Core/AppDiagnostics.swift` (rename from `PaymentDiagnostics.swift`) | Categorised, size-capped DEBUG log. |
| `xBillTests/PaymentHandleValidatorTests.swift` (create) | Validator rules, both providers. |
| `xBillTests/PaymentHandoffTests.swift` (modify) | Extended for profile links + validator agreement. |
| `xBillUITests/RegressionUITests.swift` (modify) | Settle-up surface + return prompt. |

---

### Task 1: `PaymentHandleValidator`

**Files:**
- Create: `xBill/Services/PaymentHandleValidator.swift`
- Test: `xBillTests/PaymentHandleValidatorTests.swift`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces:
  - `PaymentHandleValidator.Provider` — `enum { case venmo, paypal }`
  - `PaymentHandleValidator.Result` — `enum { case valid(String), invalid(reason: String), empty }`, `Equatable`
  - `static func validate(_ raw: String?, for provider: Provider) -> Result`
  - `static func normalized(_ raw: String?, for provider: Provider) -> String?`
  - `Provider.displayName: String`

- [ ] **Step 1: Write the failing tests**

Create `xBillTests/PaymentHandleValidatorTests.swift`:

```swift
//
//  PaymentHandleValidatorTests.swift
//  xBillTests
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//

import Foundation
import Testing
@testable import xBill

@Suite("Payment handle validation")
struct PaymentHandleValidatorTests {

    typealias Validator = PaymentHandleValidator

    // MARK: - Empty

    @Test("Nil, empty and whitespace-only input is empty, not invalid", arguments: [nil, "", "   ", "\n", "@"])
    func emptyInput(_ raw: String?) {
        #expect(Validator.validate(raw, for: .paypal) == .empty)
        #expect(Validator.validate(raw, for: .venmo) == .empty)
    }

    // MARK: - PayPal length bounds (3–20)

    @Test("PayPal rejects handles shorter than 3", arguments: ["a", "ab"])
    func paypalTooShort(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
    }

    @Test("PayPal accepts 3 and 20 character handles")
    func paypalLengthBounds() {
        #expect(Validator.validate("abc", for: .paypal) == .valid("abc"))
        let twenty = String(repeating: "a", count: 20)
        #expect(Validator.validate(twenty, for: .paypal) == .valid(twenty))
    }

    @Test("PayPal rejects handles longer than 20")
    func paypalTooLong() {
        let twentyOne = String(repeating: "a", count: 21)
        guard case .invalid = Validator.validate(twentyOne, for: .paypal) else {
            Issue.record("Expected a 21-character handle to be invalid for PayPal")
            return
        }
    }

    // MARK: - Venmo length bounds (5–30)

    @Test("Venmo rejects handles shorter than 5", arguments: ["a", "ab", "abc", "abcd"])
    func venmoTooShort(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    @Test("Venmo accepts 5 and 30 character handles")
    func venmoLengthBounds() {
        #expect(Validator.validate("abcde", for: .venmo) == .valid("abcde"))
        let thirty = String(repeating: "a", count: 30)
        #expect(Validator.validate(thirty, for: .venmo) == .valid(thirty))
    }

    @Test("Venmo rejects handles longer than 30")
    func venmoTooLong() {
        let thirtyOne = String(repeating: "a", count: 31)
        guard case .invalid = Validator.validate(thirtyOne, for: .venmo) else {
            Issue.record("Expected a 31-character handle to be invalid for Venmo")
            return
        }
    }

    // MARK: - Charsets differ per provider

    @Test("PayPal rejects separators and punctuation", arguments: ["ab.cd", "ab-cd", "ab_cd", "ab cd", "ab/cd", "ab@cd", "ab#cd"])
    func paypalRejectsNonAlphanumeric(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
    }

    @Test("Venmo accepts hyphen and underscore")
    func venmoAcceptsSeparators() {
        #expect(Validator.validate("my-handle", for: .venmo) == .valid("my-handle"))
        #expect(Validator.validate("my_handle", for: .venmo) == .valid("my_handle"))
    }

    @Test("Venmo rejects dot, space and slash", arguments: ["my.handle", "my handle", "my/handle"])
    func venmoRejectsOthers(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    @Test("Non-ASCII characters are rejected by both providers", arguments: ["handlé", "handle✓", "ハンドル"])
    func nonASCIIRejected(_ handle: String) {
        guard case .invalid = Validator.validate(handle, for: .paypal) else {
            Issue.record("Expected \(handle) to be invalid for PayPal")
            return
        }
        guard case .invalid = Validator.validate(handle, for: .venmo) else {
            Issue.record("Expected \(handle) to be invalid for Venmo")
            return
        }
    }

    /// The providers genuinely disagree; a shared charset would be wrong for one of them.
    @Test("A handle can be valid for one provider and invalid for the other")
    func providersDisagree() {
        #expect(Validator.validate("my_handle", for: .venmo) == .valid("my_handle"))
        guard case .invalid = Validator.validate("my_handle", for: .paypal) else {
            Issue.record("Expected my_handle to be invalid for PayPal")
            return
        }
        // "abc" is long enough for PayPal (3) but too short for Venmo (5).
        #expect(Validator.validate("abc", for: .paypal) == .valid("abc"))
        guard case .invalid = Validator.validate("abc", for: .venmo) else {
            Issue.record("Expected abc to be too short for Venmo")
            return
        }
    }

    // MARK: - Normalisation

    @Test("A leading @ is stripped and whitespace trimmed")
    func normalisation() {
        #expect(Validator.validate("  @realhandle  ", for: .paypal) == .valid("realhandle"))
        #expect(Validator.validate("@realhandle", for: .venmo) == .valid("realhandle"))
    }

    @Test("normalized returns the handle only when valid")
    func normalizedHelper() {
        #expect(Validator.normalized("@realhandle", for: .paypal) == "realhandle")
        #expect(Validator.normalized("ab", for: .paypal) == nil)
        #expect(Validator.normalized(nil, for: .venmo) == nil)
    }
}
```

- [ ] **Step 2: Regenerate the project and run the tests to verify they fail**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests/PaymentHandleValidatorTests 2>&1 | grep -E "error:|\*\* TEST"
```

Expected: build failure, `cannot find 'PaymentHandleValidator' in scope`.

- [ ] **Step 3: Write the implementation**

Create `xBill/Services/PaymentHandleValidator.swift`:

```swift
//
//  PaymentHandleValidator.swift
//  xBill
//
//  Copyright © 2026 Vijay Goyal. All rights reserved.
//
//  Single source of truth for Venmo / PayPal.Me handle rules.
//
//  Both ProfileView (input) and PaymentLinkService (output) validate through this
//  type. They previously carried three separate, disagreeing rule sets, so a handle
//  could pass entry and still fail to produce a link.
//
//  Rules are taken from the providers' own documentation, not inferred:
//    PayPal.Me — "between 3 and 20 characters", "only using letters and numbers"
//    Venmo     — "between 5 and 30 characters", "no special characters other than - and _"
//                https://help.venmo.com/cs/articles/check-or-edit-your-username-vhel208
//
//  The charsets must stay separate: - and _ are legal for Venmo and illegal for
//  PayPal. A dot is illegal for both.
//

import Foundation

enum PaymentHandleValidator {

    enum Provider: Equatable, Sendable {
        case venmo
        case paypal

        var displayName: String {
            switch self {
            case .venmo:  return "Venmo"
            case .paypal: return "PayPal"
            }
        }

        var minLength: Int {
            switch self {
            case .venmo:  return 5
            case .paypal: return 3
            }
        }

        var maxLength: Int {
            switch self {
            case .venmo:  return 30
            case .paypal: return 20
            }
        }

        /// Venmo permits `-` and `_`; PayPal.Me permits neither.
        var allowsSeparators: Bool { self == .venmo }

        var charsetMessage: String {
            switch self {
            case .venmo:  return "Venmo handles use letters, numbers, dashes and underscores."
            case .paypal: return "PayPal.Me handles use letters and numbers only."
            }
        }

        var lengthMessage: String {
            "\(displayName) handles are \(minLength)–\(maxLength) characters."
        }
    }

    enum Result: Equatable, Sendable {
        case valid(String)
        case invalid(reason: String)
        case empty
    }

    /// ASCII only — provider rules do not permit accented or non-Latin characters,
    /// and `CharacterSet.alphanumerics` would wrongly accept them.
    private static let asciiAlphanumerics = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    )

    static func validate(_ raw: String?, for provider: Provider) -> Result {
        var value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") { value.removeFirst() }
        guard !value.isEmpty else { return .empty }

        var allowed = asciiAlphanumerics
        if provider.allowsSeparators {
            allowed.formUnion(["-", "_"])
        }
        guard value.allSatisfy({ allowed.contains($0) }) else {
            return .invalid(reason: provider.charsetMessage)
        }
        guard value.count >= provider.minLength, value.count <= provider.maxLength else {
            return .invalid(reason: provider.lengthMessage)
        }
        return .valid(value)
    }

    /// The normalised handle when valid, otherwise nil. Use when a link is being built.
    static func normalized(_ raw: String?, for provider: Provider) -> String? {
        guard case .valid(let handle) = validate(raw, for: provider) else { return nil }
        return handle
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill && xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests/PaymentHandleValidatorTests 2>&1 | grep -E "failed on|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`, no `failed on` lines.

- [ ] **Step 5: Commit**

```bash
git add xBill/Services/PaymentHandleValidator.swift xBillTests/PaymentHandleValidatorTests.swift xBill.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
Add PaymentHandleValidator as the single source of handle rules

Rules are taken from each provider's own documentation: PayPal.Me is 3-20
ASCII alphanumerics, Venmo is 5-30 with hyphen and underscore also allowed.
The charsets must stay separate, since - and _ are legal for Venmo and
illegal for PayPal, and a dot is illegal for both.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `PaymentLinkService` delegates to the validator, and gains profile links

**Files:**
- Modify: `xBill/Services/PaymentLinkService.swift`
- Test: `xBillTests/PaymentHandoffTests.swift`

**Interfaces:**
- Consumes: `PaymentHandleValidator.normalized(_:for:)` from Task 1.
- Produces: `PaymentLinkService.shared.profileLink(handle:method:) -> URL?` — used by Task 3's test-your-link rows.

**Context:** `PaymentLinkService` currently validates in three places — `normalizedHandle` plus a second regex inside `paypalLink`. All of it is replaced by the validator. The existing 40 cases in `PaymentHandoffTests` must keep passing unmodified: they only use alphanumeric handles (`realhandle`, `@realhandle`) or clearly-unsafe ones (`bad handle`, `bad/handle`, …), all of which the new rules classify identically. That is the signal the swap was behaviour-preserving where it should be.

- [ ] **Step 1: Write the failing tests**

Append inside the `PaymentHandoffTests` struct in `xBillTests/PaymentHandoffTests.swift`, before the closing brace:

```swift
    // MARK: - Validator agreement

    @Test("PaymentLinkService accepts exactly what the validator accepts", arguments: [
        "ab",            // too short for both
        "abcd",          // valid PayPal, too short for Venmo
        "my_handle",     // valid Venmo, invalid PayPal
        "my.handle",     // invalid for both
        "realhandle"     // valid for both
    ])
    func serviceAgreesWithValidator(_ handle: String) {
        let sugg = suggestion()
        let paypalURL = PaymentLinkService.shared.paymentLink(
            for: sugg, recipient: recipient(paypal: handle), method: .paypal
        )
        let venmoURL = PaymentLinkService.shared.paymentLink(
            for: sugg, recipient: recipient(venmo: handle), method: .venmo
        )
        #expect((paypalURL != nil) == (PaymentHandleValidator.normalized(handle, for: .paypal) != nil))
        #expect((venmoURL != nil) == (PaymentHandleValidator.normalized(handle, for: .venmo) != nil))
    }

    // MARK: - Profile (test-your-link) URLs

    @Test("PayPal profile link omits the amount")
    func paypalProfileLink() throws {
        let url = try #require(PaymentLinkService.shared.profileLink(handle: "realhandle", method: .paypal))
        #expect(url.absoluteString == "https://paypal.me/realhandle")
    }

    @Test("Venmo profile link uses the verified /u/ path")
    func venmoProfileLink() throws {
        let url = try #require(PaymentLinkService.shared.profileLink(handle: "realhandle", method: .venmo))
        #expect(url.absoluteString == "https://venmo.com/u/realhandle")
    }

    @Test("Profile links reject handles the validator rejects", arguments: ["ab", "my handle", ""])
    func profileLinkRejectsInvalid(_ handle: String) {
        #expect(PaymentLinkService.shared.profileLink(handle: handle, method: .paypal) == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests/PaymentHandoffTests 2>&1 | grep -E "error:|\*\* TEST"
```

Expected: build failure, `value of type 'PaymentLinkService' has no member 'profileLink'`.

- [ ] **Step 3: Update `PaymentLinkService`**

In `xBill/Services/PaymentLinkService.swift`, replace the `paymentLink` switch and delete `normalizedHandle` entirely:

```swift
    func paymentLink(
        for suggestion: SettlementSuggestion,
        recipient: User,
        method: Settlement.PaymentMethod
    ) -> URL? {
        switch method {
        case .venmo:
            guard let username = PaymentHandleValidator.normalized(recipient.venmoHandle, for: .venmo) else { return nil }
            return venmoLink(to: username, amount: suggestion.amount, note: "xBill settlement")
        case .paypal:
            guard let username = PaymentHandleValidator.normalized(recipient.paypalHandle, for: .paypal) else { return nil }
            return paypalLink(to: username, amount: suggestion.amount, currency: suggestion.currency)
        case .upi:     return nil   // UPI links are user-specific; handled separately
        default:       return nil
        }
    }

    /// The provider's public profile page, with no amount. Used by "test your link"
    /// so the handle's owner can confirm it resolves without opening a payment screen.
    ///
    /// Verified 2026-07-26: `venmo.com/u/<handle>` returns 404 for a nonexistent handle,
    /// while `paypal.me/<handle>` returns 200 and renders PayPal's own error page.
    func profileLink(handle: String?, method: Settlement.PaymentMethod) -> URL? {
        switch method {
        case .venmo:
            guard let username = PaymentHandleValidator.normalized(handle, for: .venmo) else { return nil }
            return URL(string: "https://venmo.com/u/\(username)")
        case .paypal:
            guard let username = PaymentHandleValidator.normalized(handle, for: .paypal) else { return nil }
            return URL(string: "https://paypal.me/\(username)")
        default:
            return nil
        }
    }
```

Then remove the now-redundant regex guard at the top of `paypalLink`, so it reads:

```swift
    /// https://paypal.me/<username>/<amount><currency>
    private func paypalLink(to username: String, amount: Decimal, currency: String) -> URL? {
        URL(string: "https://paypal.me/\(username)/\(amount)\(currency)")
    }
```

- [ ] **Step 4: Run the full handoff suite to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests/PaymentHandoffTests 2>&1 | grep -E "failed on|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`. **All pre-existing cases must pass unmodified** — if any previously-passing case now fails, the validator changed behaviour it should not have. Investigate before proceeding.

- [ ] **Step 5: Commit**

```bash
git add xBill/Services/PaymentLinkService.swift xBillTests/PaymentHandoffTests.swift
git commit -m "$(cat <<'EOF'
Route PaymentLinkService through PaymentHandleValidator

Removes three disagreeing validation sites in favour of one. Adds
profileLink(handle:method:) for the test-your-link rows: paypal.me/<handle>
and venmo.com/u/<handle>, both without an amount so testing never opens a
payment screen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `ProfileView` — validator-backed messages and test-your-link rows

**Files:**
- Modify: `xBill/Views/Profile/ProfileView.swift` (validation vars at ~255–277; Payment Handles section at ~160–202)
- Modify: `xBill/ViewModels/ProfileViewModel.swift` (`normalizedPaymentHandle` at ~169)

**Interfaces:**
- Consumes: `PaymentHandleValidator` (Task 1), `PaymentLinkService.profileLink(handle:method:)` (Task 2).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the hand-rolled validation messages**

In `xBill/Views/Profile/ProfileView.swift`, replace both computed properties:

```swift
    private var venmoValidationMessage: String? {
        if case .invalid(let reason) = PaymentHandleValidator.validate(vm.venmoHandle, for: .venmo) {
            return reason
        }
        return nil
    }

    private var paypalValidationMessage: String? {
        if case .invalid(let reason) = PaymentHandleValidator.validate(vm.paypalHandle, for: .paypal) {
            return reason
        }
        return nil
    }
```

- [ ] **Step 2: Add the test-link rows**

Still in `ProfileView.swift`, add these helpers next to the validation properties:

```swift
    /// The saved handle's profile URL, shown only when the *stored* value is valid and
    /// there are no unsaved edits — so the row always tests what is actually saved.
    private func savedProfileLink(for method: Settlement.PaymentMethod) -> URL? {
        guard !hasUnsavedHandles else { return nil }
        let saved = method == .venmo ? vm.user?.venmoHandle : vm.user?.paypalHandle
        return PaymentLinkService.shared.profileLink(handle: saved, method: method)
    }

    @ViewBuilder
    private func testLinkRow(for method: Settlement.PaymentMethod) -> some View {
        if let url = savedProfileLink(for: method) {
            Link(destination: url) {
                XBillActionRow(
                    icon: "arrow.up.right.square",
                    title: "Test your \(method == .venmo ? "Venmo" : "PayPal") link",
                    subtitle: "Opens your public profile to confirm it works"
                )
            }
            .accessibilityIdentifier("xBill.profile.\(method == .venmo ? "venmo" : "paypal")TestLink")
        }
    }
```

Then insert `testLinkRow(for:)` after each handle field's `validationText(...)` call, inside the same `VStack`:

```swift
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        XBillPaymentHandleRow(
                            providerName: "Venmo",
                            systemImage: "dollarsign.circle.fill",
                            placeholder: "@venmo-handle",
                            text: $vm.venmoHandle
                        )
                        .accessibilityIdentifier("xBill.profile.venmoField")
                        validationText(venmoValidationMessage)
                        testLinkRow(for: .venmo)
                        }
```

and the same pattern for PayPal, using `testLinkRow(for: .paypal)`.

- [ ] **Step 3: Make the ViewModel normalise through the validator**

In `xBill/ViewModels/ProfileViewModel.swift`, replace the body of `saveProfile`'s handle normalisation (currently lines ~142–143) so an invalid handle is never persisted:

```swift
            let handle = PaymentHandleValidator.normalized(venmoHandle, for: .venmo)
            let paypal = PaymentHandleValidator.normalized(paypalHandle, for: .paypal)
```

Then delete the now-unused `normalizedPaymentHandle(_:)` static method (lines ~169–175).

- [ ] **Step 4: Build and confirm the app compiles**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the unit suite for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests 2>&1 | grep -E "failed on|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add xBill/Views/Profile/ProfileView.swift xBill/ViewModels/ProfileViewModel.swift
git commit -m "$(cat <<'EOF'
Validate payment handles on entry and add test-your-link rows

ProfileView and ProfileViewModel now validate through PaymentHandleValidator,
so a handle that cannot produce a link can no longer be saved. Once a valid
handle is stored, a row opens the provider's public profile page so the owner
can confirm it resolves in one tap, without opening a payment screen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Settle-up surface — handle on the button, explained empty state

**Files:**
- Modify: `xBill/Views/Groups/GroupDetailView.swift` (`settlementRow` at ~467–520)

**Interfaces:**
- Consumes: `PaymentHandleValidator` (Task 1), `PaymentLinkService.paymentLink(for:recipient:method:)`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace the payment button block**

In `settlementRow(_:)`, replace the `if let recipient = vm.members.first(...)` block with:

```swift
            if let recipient = vm.members.first(where: { $0.id == suggestion.toUserID }) {
                let venmoHandle  = PaymentHandleValidator.normalized(recipient.venmoHandle, for: .venmo)
                let paypalHandle = PaymentHandleValidator.normalized(recipient.paypalHandle, for: .paypal)

                if venmoHandle == nil && paypalHandle == nil {
                    // Previously this rendered nothing at all, so the absence of a payment
                    // button looked like a bug rather than missing recipient data.
                    Text("Ask \(suggestion.toName) to add a payment handle in their profile.")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("xBill.settleUp.noPaymentHandle.\(suggestion.id.uuidString)")
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        if let handle = venmoHandle,
                           let venmoURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .venmo) {
                            Button {
                                openPaymentURL(venmoURL, providerName: "Venmo", suggestion: suggestion)
                            } label: {
                                Label("Venmo · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.venmoButton.\(suggestion.id.uuidString)")
                        }
                        if let handle = paypalHandle,
                           let paypalURL = PaymentLinkService.shared.paymentLink(for: suggestion, recipient: recipient, method: .paypal) {
                            Button {
                                openPaymentURL(paypalURL, providerName: "PayPal", suggestion: suggestion)
                            } label: {
                                Label("PayPal · @\(handle)", systemImage: "link")
                                    .font(.appCaptionMedium)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("xBill.settleUp.paypalButton.\(suggestion.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
```

Note the `openPaymentURL` calls now pass `suggestion:` — that parameter is added in Task 5. Until Task 5 lands this will not compile, so **Tasks 4 and 5 are committed together**; complete Task 5's Step 1 before building.

- [ ] **Step 2: Proceed directly to Task 5**

Do not build or commit yet. Task 5 adds the `suggestion:` parameter these call sites now require.

---

### Task 5: Return prompt — "Did you complete this payment?"

**Files:**
- Modify: `xBill/Views/Groups/GroupDetailView.swift` (state at ~25–34; `scenePhase` handler at ~82; `openPaymentURL` at ~497)

**Interfaces:**
- Consumes: `vm.recordSettlement(_:)`, `AppLockService.shared.isLocked`.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the pending-handoff state and prompt**

In `GroupDetailView`, add near the other `@State` declarations (~line 31):

```swift
    /// A payment app was opened for this suggestion and we are waiting to ask whether it
    /// completed. View state, not model state — a handoff has no meaning once this screen
    /// is gone.
    private struct PendingHandoff: Equatable {
        let suggestion: SettlementSuggestion
        let providerName: String
    }
    @State private var pendingHandoff: PendingHandoff?
    @State private var handoffPrompt: PendingHandoff?
```

Update `openPaymentURL` to take the suggestion and record the handoff only when the URL was actually accepted:

```swift
    private func openPaymentURL(_ url: URL, providerName: String, suggestion: SettlementSuggestion) {
        AppDiagnostics.log(.payment, "openPaymentURL.request", [
            ("provider", providerName),
            ("scheme", url.scheme ?? "nil"),
            ("host", url.host() ?? "nil"),
            ("group", vm.group.name)
        ])
        openURL(url) { accepted in
            AppDiagnostics.log(.payment, "openPaymentURL.result", [
                ("provider", providerName),
                ("accepted", accepted)
            ])
            guard accepted else {
                paymentHandoffAlert = ErrorAlert(
                    title: "\(providerName) Not Available",
                    message: "Install \(providerName) or use another payment method, then mark the settlement when it is complete."
                )
                return
            }
            // Only arm the prompt when the payment app actually opened.
            pendingHandoff = PendingHandoff(suggestion: suggestion, providerName: providerName)
        }
    }
```

Extend the existing `scenePhase` handler to raise the prompt. Replace the handler body with:

```swift
            .onChange(of: scenePhase) { oldPhase, phase in
                AppDiagnostics.log(.lifecycle, "GroupDetailView.scenePhase", [
                    ("group", vm.group.name),
                    ("from", String(describing: oldPhase)),
                    ("to", String(describing: phase)),
                    ("pendingHandoff", pendingHandoff != nil),
                    ("isLocked", AppLockService.shared.isLocked)
                ])
                guard phase == .active else { return }
                Task { await vm.refresh(showError: false) }
                presentHandoffPromptIfReady()
            }
            .onChange(of: AppLockService.shared.isLocked) { _, locked in
                // App Lock is engaged on backgrounding, so returning from a payment app
                // lands here still locked. Presenting now would render the dialog behind
                // the lock overlay; defer until unlock.
                if !locked { presentHandoffPromptIfReady() }
            }
```

Add the helper alongside `openPaymentURL`:

```swift
    private func presentHandoffPromptIfReady() {
        guard let pending = pendingHandoff else { return }
        guard !AppLockService.shared.isLocked else { return }
        pendingHandoff = nil          // cleared so it can never re-ask on a later foreground
        handoffPrompt = pending
    }
```

Add the confirmation dialog next to the existing `.confirmationDialog` modifiers (after the settle confirmation at ~line 186):

```swift
            .confirmationDialog(
                "Did you complete this payment?",
                isPresented: Binding(
                    get: { handoffPrompt != nil },
                    set: { if !$0 { handoffPrompt = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Mark as Settled") {
                    guard let prompt = handoffPrompt else { return }
                    handoffPrompt = nil
                    Task { await vm.recordSettlement(prompt.suggestion) }
                }
                Button("Not yet", role: .cancel) { handoffPrompt = nil }
            } message: {
                if let prompt = handoffPrompt {
                    Text("xBill can't confirm payments made in \(prompt.providerName). Only mark this settled if the payment went through.")
                }
            }
```

- [ ] **Step 2: Build**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`. If `AppDiagnostics` is unresolved, Task 7 has not run yet — temporarily use `PaymentDiagnostics.log("openPaymentURL.request", [...])` (dropping the category argument) and restore the categorised calls in Task 7.

- [ ] **Step 3: Add the UI regression tests**

In `xBillUITests/RegressionUITests.swift`, add a new test after `testPaymentReturnSurvivesAppReactivationRegression`:

```swift
    func testSettleUpExplainsMissingPaymentHandleRegression() throws {
        try signInIfNeeded()

        let groupName = uniqueName(prefix: "NoHandle")
        try createGroup(named: groupName)
        try openGroup(named: groupName)
        try addExpense(title: "Handle expense \(uniqueSuffix())", amount: "10.00")
        try openGroupTab("Settle Up")

        // A brand-new group's members have no payment handles, so the settle-up surface
        // must explain the absent button rather than rendering nothing.
        let explanation = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.noPaymentHandle.")
        ).firstMatch
        let paymentButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "xBill.settleUp.paypalButton.")
        ).firstMatch

        if explanation.waitForExistence(timeout: 5) {
            XCTAssertFalse(paymentButton.exists, "A payment button must not appear when no handle exists.")
        } else {
            XCTAssertFalse(
                paymentButton.exists,
                "With no handle saved, neither a payment button nor an explanation appeared."
            )
        }

        try openGroupTab("Expenses")
        try archiveCurrentGroup()
    }
```

- [ ] **Step 4: Run the UI regression tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillUITests/RegressionUITests/testSettleUpExplainsMissingPaymentHandleRegression \
  -only-testing:xBillUITests/RegressionUITests/testPaymentReturnSurvivesAppReactivationRegression 2>&1 | grep -E "failed|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit Tasks 4 and 5 together**

```bash
git add xBill/Views/Groups/GroupDetailView.swift xBillUITests/RegressionUITests.swift
git commit -m "$(cat <<'EOF'
Show payment destination, explain missing handles, prompt on return

The settle-up button now reads "PayPal / @handle" so a payer can spot a wrong
destination before leaving the app, and a recipient with no usable handle gets
an explanation instead of a silently absent button.

Returning from a payment app now asks whether the payment completed, defaulting
to unmarked. Three guards: it arms only when openURL reports the app actually
opened, it clears after one answer so it cannot re-ask on later foregrounds,
and it defers past App Lock, which would otherwise render the dialog behind
the lock overlay on every return.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Scale seeded amounts ÷50

**Files:**
- Modify: `supabase/seed_app_store_review_account.sql` (expenses ~297–301, splits ~316–330, IOU ~337)
- Modify: `SETUP_REVIEW_ACCOUNT.md` (split table ~182, balances ~272–274, ~291)

**Interfaces:** none — data and documentation only.

**Why:** once a real handle is entered on the demo account, tapping PayPal opens a genuine payment screen for the settlement amount. At `$95.00` a stray tap sends real money. Every value divides by 50 to an exact 2-decimal result, so splits still sum to their expense totals and no `is_settled` flag changes.

- [ ] **Step 1: Scale the expenses**

In `supabase/seed_app_store_review_account.sql`, replace the five expense amounts:

| Title | From | To |
|---|---|---|
| Flights to Tokyo | `180.00` | `3.60` |
| Hotel - Night 1 | `90.00` | `1.80` |
| Sushi dinner | `120.00` | `2.40` |
| Day trip to Nikko | `60.00` | `1.20` |
| Convenience store run | `45.00` | `0.90` |

- [ ] **Step 2: Scale the splits**

Replace the 15 split amounts, preserving every `is_settled` flag and `settled_at` value:

| Expense | From (reviewer / alice / bob) | To |
|---|---|---|
| 0001 Flights | `60.00 / 60.00 / 60.00` | `1.20 / 1.20 / 1.20` |
| 0002 Hotel | `30.00 / 30.00 / 30.00` | `0.60 / 0.60 / 0.60` |
| 0003 Sushi | `50.00 / 40.00 / 30.00` | `1.00 / 0.80 / 0.60` |
| 0004 Nikko | `20.00 / 20.00 / 20.00` | `0.40 / 0.40 / 0.40` |
| 0005 Store | `15.00 / 15.00 / 15.00` | `0.30 / 0.30 / 0.30` |

- [ ] **Step 3: Scale the IOU**

Change the IOU amount from `25.00` to `0.50`.

- [ ] **Step 4: Update the documented balances**

In `SETUP_REVIEW_ACCOUNT.md`:
- The split table entry showing `50.00` becomes `1.00`.
- The balances block becomes:

```
  Owed to you:  ~$4.40   (Alice + Bob owe across 3 expenses reviewer paid)
  You owe:      ~$1.00   (reviewer owes Alice $0.60 + Bob $0.40)
  Net:          ~+$3.40
```

- The prose "Positive net balance (owed $220, owes $50)" becomes "(owed $4.40, owes $1.00)".

- [ ] **Step 5: Apply the seed and verify the arithmetic**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
supabase db query --file supabase/seed_app_store_review_account.sql --linked

supabase db query --linked "
select e.title, e.amount as expense_total, sum(s.amount) as split_total
from public.expenses e join public.splits s on s.expense_id = e.id
where e.group_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
group by e.id, e.title, e.amount order by e.title;"
```

Expected: `expense_total` equals `split_total` on every row. Also confirm handles are still absent:

```bash
supabase db query --linked "select count(*) as with_handles from public.profiles \
  where venmo_handle is not null or paypal_handle is not null or paypal_email is not null;"
```

Expected: `0`.

- [ ] **Step 6: Commit**

```bash
git add supabase/seed_app_store_review_account.sql SETUP_REVIEW_ACCOUNT.md
git commit -m "$(cat <<'EOF'
Scale seeded review amounts by 50 so on-device testing is safe

Entering a real payment handle makes the settle-up button open a genuine
payment screen for the settlement amount. At $95.00 a stray tap during
testing sends real money; the settlement is now $1.90.

Every expense, split and the IOU divide by 50 to an exact 2-decimal value, so
splits still sum to their totals and no settled flag changes. Tokyo Trip keeps
5 expenses, 15 splits, 3 members, 2 comments and 1 IOU. Chose 50 over 100 to
stay above a possible but unverified $1 PayPal.Me minimum, rather than let
"minimum" reintroduce a broken link. SETUP_REVIEW_ACCOUNT.md balances updated
to match.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `PaymentDiagnostics` → `AppDiagnostics`

**Files:**
- Rename: `xBill/Core/PaymentDiagnostics.swift` → `xBill/Core/AppDiagnostics.swift`
- Modify call sites: `xBill/Core/Extensions.swift`, `xBill/ViewModels/HomeViewModel.swift`, `xBill/ViewModels/GroupViewModel.swift`, `xBill/Views/Groups/GroupDetailView.swift`, `xBill/Views/Main/MainTabView.swift`, `xBill/Views/Main/ContentView.swift`
- Modify: `diagnostics/README.md`

**Interfaces:**
- Produces: `AppDiagnostics.log(_ category: Category, _ event: String, _ fields: [(String, Any)])`, `AppDiagnostics.describe(_:) -> String`, `AppDiagnostics.logPath: String`.

- [ ] **Step 1: Create the renamed type**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
git mv xBill/Core/PaymentDiagnostics.swift xBill/Core/AppDiagnostics.swift
```

Rewrite the type in `xBill/Core/AppDiagnostics.swift`, keeping the existing three-sink structure and adding a category plus rotation:

```swift
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

    static func log(_ category: Category, _ event: String, _ fields: [(String, Any)] = []) {
        let rendered = fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
        let line = "[\(timestampFormatter.string(from: Date()))] [\(category.rawValue)] \(event)"
            + (rendered.isEmpty ? "" : " " + rendered)

        logger.log("\(line, privacy: .public)")
        print("XBILLDIAG \(line)")
        append(line)
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "swiftType=\(type(of: error))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "localized=\(nsError.localizedDescription)"
        ]
        if let appError = error as? AppError { parts.append("appError=\(appError)") }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)#\(underlying.code):\(underlying.localizedDescription)")
        }
        return "{" + parts.joined(separator: " | ") + "}"
    }

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
        let kept = lines.suffix(lines.count / 2).joined(separator: "\n")
        let header = "===== ROTATED \(timestampFormatter.string(from: Date())) =====\n"
        try? (header + kept + "\n").data(using: .utf8)?.write(to: url)
    }

    #else

    static func log(_ category: Category, _ event: String, _ fields: [(String, Any)] = []) {}
    static func describe(_ error: Error) -> String { "" }
    static var logPath: String { "unavailable" }

    #endif
}
```

- [ ] **Step 2: Update every call site with a category**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
grep -rn "PaymentDiagnostics" --include="*.swift" xBill/
```

Replace each occurrence, choosing the category by concern:

| Call site | Category |
|---|---|
| `Extensions.swift` alert chokepoint | `.lifecycle` |
| `HomeViewModel` load/balance events | `.balance` |
| `GroupViewModel` load/balance events | `.balance` |
| `GroupDetailView` payment events | `.payment` |
| `GroupDetailView` / `ContentView` scenePhase | `.lifecycle` |
| `MainTabView.didBecomeActive` | `.lifecycle` |

Example transformation:

```swift
// before
PaymentDiagnostics.log("HomeViewModel.loadAll.enter", [("connected", NetworkMonitor.shared.isConnected)])
// after
AppDiagnostics.log(.balance, "HomeViewModel.loadAll.enter", [("connected", NetworkMonitor.shared.isConnected)])
```

- [ ] **Step 3: Verify no references remain and build**

```bash
grep -rn "PaymentDiagnostics" --include="*.swift" xBill/ || echo "clean"
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | grep -E "error:|BUILD"
```

Expected: `clean`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the diagnostics compile out of Release**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project xBill.xcodeproj -scheme xBill -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Update the diagnostics README**

In `diagnostics/README.md`, change the log filename from `payment-diagnostics.log` to `xbill-diagnostics.log` in the retrieval commands, and add above the file table:

```markdown
## Index of investigations

| Date | Investigation | Artifacts |
|------|---------------|-----------|
| 2026-07-26 | PayPal settle-up handoff — fabricated seed handles | `2026-07-27-paypal-handoff/` |

Append a row here at the end of each investigation. Raw device logs live in the
dated folder; this table is the entry point.
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Generalise PaymentDiagnostics into AppDiagnostics

The logger was named after a single investigation, so the next agent debugging
something unrelated would have started a second file. It now writes one
categorised log per app at Documents/xbill-diagnostics.log, tagged .payment,
.auth, .balance, .lifecycle or .sync.

Adds a 2 MB cap that keeps the newest half on overflow, so an append-only file
on a device cannot grow without bound. Still DEBUG-only, since it records group
names and amounts; verified to compile out of Release.

diagnostics/README.md gains an index table as the entry point for future
investigations.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Full verification and documentation

**Files:**
- Modify: `CLAUDE.md`, `AUDIT_REPORT.md`

- [ ] **Step 1: Run the full unit suite**

```bash
cd /Users/vijaygoyal/MyiOSApp/xBill
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillTests 2>&1 | grep -E "failed on|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Run the full UI regression suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project xBill.xcodeproj -scheme xBill \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:xBillUITests/RegressionUITests 2>&1 | grep -E "failed|error:|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Install on the physical device**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme xBill -destination 'id=00008140-000135EE3432801C' \
  -configuration Debug -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"

xcrun devicectl device install app --device 00008140-000135EE3432801C \
  ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphoneos/xBill.app
```

- [ ] **Step 4: Manual device verification**

Ask the user to perform these and report results — they cannot be automated:

1. Profile → Payment Handles → enter a real PayPal handle → Save.
   - Expected: no validation error; a "Test your PayPal link" row appears.
2. Tap "Test your PayPal link".
   - Expected: opens a real PayPal.Me profile page, **no** payment screen, **no** "Something went wrong".
3. Enter an invalid handle such as `ab` or `my.handle`.
   - Expected: an inline validation message; Save is disabled.
4. Tokyo Trip → Settle Up.
   - Expected: the button reads `PayPal · @<handle>` and the settlement is **$1.90**, not $95.00.
5. Tap PayPal, return to xBill without paying, unlock with Face ID.
   - Expected: "Did you complete this payment?" appears **after** unlock, not behind the lock overlay. Choose "Not yet".
6. Confirm the settlement is still listed as unsettled.

- [ ] **Step 5: Pull the device log and confirm**

```bash
xcrun devicectl device copy from --device 00008140-000135EE3432801C \
  --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill \
  --source Documents/xbill-diagnostics.log --destination ./verify.log

grep -c "alert.presented" verify.log      # expect 0
grep "\[payment\]" verify.log             # handoff request/result with accepted=true
```

- [ ] **Step 6: Update documentation and commit**

Add a `## Recent Fix Log — <date>` entry to `CLAUDE.md` covering: the shared validator and both sourced provider rules, test-your-link, the settle-up surface changes, the return prompt and its three guards, the ÷50 seed scaling, and `AppDiagnostics`. Add matching rows to `AUDIT_REPORT.md`.

```bash
git add CLAUDE.md AUDIT_REPORT.md
git commit -m "$(cat <<'EOF'
Document payment handle experience and unified diagnostics

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| §1 `PaymentHandleValidator` | Task 1, adopted in Tasks 2 and 3 |
| §2 Test-your-link | Task 2 (`profileLink`), Task 3 (UI rows) |
| §3 Settle-up surface | Task 4 |
| §4 Return prompt | Task 5 |
| §5 Seeded amounts ÷50 | Task 6 |
| §6 Unified diagnostics | Task 7 |
| Testing section | Tasks 1, 2, 5 (UI), 8 (full suites + manual) |
| Risks | Task 6 Step 5 verifies split arithmetic and handle absence; Task 7 Step 4 verifies Release strip |

**Type consistency**

- `PaymentHandleValidator.validate/normalized` signatures identical in Tasks 1, 2, 3, 4.
- `profileLink(handle:method:)` defined in Task 2, consumed in Task 3.
- `openPaymentURL(_:providerName:suggestion:)` — the `suggestion:` parameter is added in Task 5 but its call sites appear in Task 4, which is why Tasks 4 and 5 build and commit together. Flagged explicitly in Task 4 Step 2 and Task 5 Step 2.
- `AppDiagnostics.log(_:_:_:)` gains a leading `Category` in Task 7; Task 5 writes categorised calls and carries a fallback note in case Task 7 has not run.
- `Settlement.PaymentMethod` is the existing enum used throughout; `PaymentHandleValidator.Provider` is separate and deliberately not merged with it — one describes settlement methods including cash and bank transfer, the other only handle-bearing providers.
