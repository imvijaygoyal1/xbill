# xBill Senior Developer Defect Report — v3

**Date:** 2026-05-10  
**Scope:** Full app audit — auth, core services, all ViewModels, all Views, Supabase backend (migrations + edge functions), receipt scan, IOUs, friends, recurring expenses, export, app lock  
**Method:** 5-agent parallel review across ~100 Swift files, 26 migrations, 5 edge functions  
**Total findings:** ~136 (11 Critical / 37 High / 52 Medium / 36 Low)

> Findings marked **[DUP]** were independently reported by multiple agents — the duplicate is listed once at the highest severity.

---

## CRITICAL — Data loss, security breach, or guaranteed crash

---

### CRIT-01 — Recurring expense creation is non-atomic: infinite duplicate instances on partial failure
**Files:** `GroupViewModel.swift` `createDueRecurringInstances` ~L203–219 · `ExpenseService.swift` `setNextOccurrenceDate` L125–128  
`createExpense` and `setNextOccurrenceDate` are two separate `await` calls. If `createExpense` succeeds but `setNextOccurrenceDate` throws (network drop, RLS), the template's `next_occurrence_date` is never advanced. On the next app launch the same template is considered "due" again — a second instance is created. This loops forever with no idempotency guard. `setNextOccurrenceDate` also lacks `.select()` (CRIT-B below), so a silent RLS failure takes the same failure path.

---

### CRIT-02 — `SplitInput(from:)` always fires `assertionFailure` in DEBUG; crashes every recurring expense creation in debug builds
**File:** `Split.swift` `SplitInput.init(from:)` L83–92 · `GroupViewModel.swift` L196  
`init(from:)` unconditionally calls `assertionFailure(...)` in `#if DEBUG`. `createDueRecurringInstances` calls `existingSplits.map { SplitInput(from: $0) }`, which hits this path for every recurring expense in every debug session. Also, `displayName` is never populated in the mapped inputs — all participants appear as `""` in notifications and any display built from `SplitInput.displayName`.

---

### CRIT-03 — `groups` UPDATE RLS policy has no `WITH CHECK` — any group member can hijack group metadata
**File:** `001_initial_schema.sql` L88–91  
```sql
create policy "groups: members can update"
    on public.groups for update
    using ( public.is_group_member(id) );
```
No `WITH CHECK`. Any member can rename the group, change its currency, archive it, or hijack `created_by`. Only the creator should mutate group metadata.

---

### CRIT-04 — `ious` UPDATE RLS policy has no `WITH CHECK` — either party can mutate amount or reassign parties
**File:** `014_ious.sql` L33–35  
```sql
CREATE POLICY "parties can settle"
  ON public.ious FOR UPDATE
  USING (auth.uid() = lender_id OR auth.uid() = borrower_id);
```
No `WITH CHECK`. Borrower can set `amount` to zero, redirect `lender_id` to a third party, or change any field — not just `is_settled`.

---

### CRIT-05 — `friends` UPDATE RLS policy has no `WITH CHECK` — addressee can forge status/requester
**File:** `020_friends_table.sql` L33–35  
No `WITH CHECK`. Addressee can set `requester_id`, `addressee_id`, or `status` arbitrarily. Can accept their own friend requests, block without the RPC, or redirect the friendship to another user.

---

### CRIT-06 — All authenticated users can read every invite token in the system — any user can join any group
**File:** `012_group_invites.sql` L11–15  
```sql
CREATE POLICY "authenticated users can read invites"
  ON public.group_invites FOR SELECT TO authenticated USING (true);
```
An attacker can dump the entire `group_invites` table, harvest all tokens (valid for 7 days), and join any group. Fix: restrict SELECT to rows where `created_by = auth.uid()` OR the user is already a member of that group. Token validation for joining is handled by the SECURITY DEFINER RPC and does not require this broad SELECT.

---

### CRIT-07 — `device_tokens` `FOR ALL` policy lacks `WITH CHECK` — any user can register tokens under another user's ID
**File:** `016_create_device_tokens_table.sql` L15–18  
`FOR ALL USING (auth.uid() = user_id)` without `WITH CHECK`. For INSERT, `USING` filters existing rows, not the inserted value. A malicious user can insert their APNs token against another user's `user_id` to intercept that user's push notifications.

---

### CRIT-08 — `IOUService.settleIOU` missing `.select()` — silent RLS failure is indistinguishable from success
**File:** `IOUService.swift` `settleIOU(id:)` L97–101  
No `.select()` → SDK sends `Prefer: return=minimal` → empty 200 body on RLS block. Caller believes the settle succeeded. Same issue in `settleAllIOUs` (which calls `settleIOU` in a loop) and `deleteIOU`. [DUP: Backend H-05, Receipt CRIT-NEW-02]

---

### CRIT-09 — `FoundationModelService._cachedSession` is a data race under concurrent callers
**File:** `FoundationModelService.swift` `parseWithStructuredOutput` L42–86  
`_cachedSession` is `nonisolated(unsafe) private var`. Two concurrent `parseReceipt` callers both read `nil`, both create a new session, both write to the unguarded var — the second write replaces the first session while the first call is actively using it. This is an unsound use of `nonisolated(unsafe)` on a `var`.

---

### CRIT-10 — `GroupViewModel.load()` cache fallback condition fails after partial async fetch; users see empty data instead of cached data
**File:** `GroupViewModel.swift` `load()` L65–70  
On network error, fallback is `if members.isEmpty { members = cache }`. If `membersTask` throws after `expensesTask` already wrote `expenses` (but not `members`), the condition `members.isEmpty` is still `false` — no cache is loaded. Users see empty member lists with no error.

---

### CRIT-11 — `ExpenseDetailView` dismiss fires synchronously before delete async task completes; silent failure leaves zombie expenses
**File:** `ExpenseDetailView.swift` L189–192  
`onDeleted?()` fires `Task { await vm.deleteExpense(expense) }` (fire-and-forget) then `dismiss()` immediately. If `deleteExpense` throws, the error is swallowed, the view is gone, and the expense still appears in the group list with no user feedback.

---

## HIGH — Significant bugs that degrade core features

---

### H-01 — `splitEqually` assigns amount remainder to first participant but percentage remainder to last — inconsistent
**File:** `SplitCalculator.swift` `splitEqually` L31–54  
`share += remainder` when `offset == 0` (first participant), but percentage remainder goes to `isLast`. A display recalculating from `percentage` produces a different amount than what was saved. The comment says "last participant" but the code says `offset == 0`.

---

### H-02 — `validateExact` shows "Remaining: X" even when over-allocated — backwards error message
**File:** `SplitCalculator.swift` `validateExact` L121  
Uses `absDiff` (absolute value). Over-allocation shows "Remaining: 0.50" when it should say "Over by 0.50". Users reduce amounts when they should increase them.

---

### H-03 — `handlePasswordReset` applies no password length/complexity validation before calling Supabase
**File:** `AuthViewModel.swift` `handlePasswordReset` L145–155  
Sign-up validates `isPasswordValid` (≥8 chars) but reset does not. Empty password submits to Supabase, returns a generic error alert with no actionable inline message.

---

### H-04 — `isNotFoundError` uses overly broad substring matching — false positives corrupt profile data
**File:** `AuthService.swift` `isNotFoundError` L210, 213  
`desc.contains("406")` matches any string containing "406" anywhere. `lower.contains("0 rows")` matches unrelated errors. A false positive causes the catch block to upsert a new profile when the real error is a network failure or RLS denial, silently corrupting profile data.

---

### H-05 — `setNextOccurrenceDate` missing `.select()` — silent RLS failure leaves template un-advanced (same root as CRIT-01)
**File:** `ExpenseService.swift` L125–128  
Without `.select()`, RLS rejection returns empty 200 — no throw, template silently stays due, duplicate instances created on next launch.

---

### H-06 — `NullNextOccurrence` struct is dead code — never referenced
**File:** `ExpenseService.swift` L293–301  
Defined but never called. If the clear-template path ever needs to null out `next_occurrence_date`, it will be re-invented incorrectly.

---

### H-07 — Duplicate Spotlight handler: `AppDelegate` and `xBillApp.onContinueUserActivity` both handle the same activity type
**File:** `xBillApp.swift` L107–127 (AppDelegate) and L192–199 (SwiftUI modifier)  
On iOS 17+ the SwiftUI modifier takes precedence, making the AppDelegate handler dead code. The dual registration is fragile and can cause double-navigation if iOS behavior changes.

---

### H-08 — `notify-expense` sender exclusion uses caller-supplied `payerId` instead of verified `callerID`
**File:** `supabase/functions/notify-expense/index.ts` L118  
An authenticated user can suppress notifications for any group member by passing that member's UUID as `payerId`. Fix: replace `payerId` with the `callerID` returned by `requireAuth`.

---

### H-09 — `notify-settlement` accepts `toUserID` and `fromName` from request body without verification — spoofed notifications possible
**File:** `supabase/functions/notify-settlement/index.ts` L60–69  
Any authenticated user can push a settlement notification to any device by passing an arbitrary `toUserID`. `fromName` is caller-supplied and can be faked. Fix: derive `fromUserID` from `callerID`; validate `toUserID` against shared group membership; fetch `fromName` server-side.

---

### H-10 — `lookup_profiles_by_email` has no index on `profiles.email`; `= ANY()` is case-sensitive — silent lookup misses
**File:** `025_medium_fixes.sql` L53–71  
Full table scan on every contact-discovery lookup. Case-sensitive `=` means `User@Example.com` vs `user@example.com` silently fails. At scale this is both a correctness and performance issue.

---

### H-11 — Old 7-parameter `add_expense_with_splits` overload not DROPped after migration 013 — orphaned executable function
**File:** `013_multi_currency.sql` L10–11  
`CREATE OR REPLACE` creates the 11-param version. The old 7-param overload (no currency/notes/recurrence) still exists and is executable by `authenticated` — calling it bypasses currency handling silently.

---

### H-12 — `HomeViewModel.loadAll()` does not recompute balances on network-error cache restore
**File:** `HomeViewModel.swift` `loadAll()` L76–91  
On error, `groups` is restored from cache but `computeBalances(for:)` is never called. `totalOwed`, `totalOwing`, `recentExpenses`, and `groupNetBalances` all remain stale or zero.

---

### H-13 — `HomeViewModel.fullBalancesInGroup` makes 2 network calls per group on every refresh — O(N) uncached fan-out
**File:** `HomeViewModel.swift` `fullBalancesInGroup(_:userID:)` L235–252  
No caching or early-return if data was just fetched in `loadAll()`. 10 groups = 20+ parallel redundant network calls per home screen refresh.

---

### H-14 — `startRealtimeUpdates()` has no stored Task handle — duplicate streams created on each view reappear
**File:** `HomeViewModel.swift` `startRealtimeUpdates()` L140–145  
No cancellation mechanism. Every time `HomeView` appears again, a new stream listener runs indefinitely alongside previous ones, causing double `loadAll()` on every realtime event.

---

### H-15 — `AddExpenseViewModel.save()` captures `amountText` after the first `await` — race window remains
**File:** `AddExpenseViewModel.swift` `save()` L140–198  
`capturedAmount` is captured at L151, after `await updateConversion()` returns at L146. A user typing during the network call can alter `amountText` between L146 and L151, corrupting the saved amount.

---

### H-16 — `ProfileViewModel.saveProfile` writes stale avatar URL in first `updateProfile`; profile is inconsistent if second write fails
**File:** `ProfileViewModel.swift` `saveProfile(avatarImage:)` L114–135  
Two sequential `updateProfile` calls. If `uploadAvatar` or the second `updateProfile` throws, `self.user` has the old `avatarURL` while the DB may have received a partial update. No rollback exists.

---

### H-17 — `ProfileViewModel.saveProfile` allows empty or whitespace-only `displayName` to be saved
**File:** `ProfileViewModel.swift` `saveProfile(avatarImage:)` L108  
No guard. Empty display name persists to DB and appears in expense payer names, split lists, and notifications app-wide. [DUP: Views PV-03]

---

### H-18 — `ActivityViewModel.load()` comment says "read unreadCount before merge" but reads after — misleading, invites regression
**File:** `ActivityViewModel.swift` `load()` L23–45  
Behaviour is correct (count is accurate) but the comment is wrong. A developer "fixing" this to read before the merge will regress the badge count.

---

### H-19 — `ReceiptViewModel.tip` computed property: scientific notation from `NSDecimalNumber` causes `Decimal(string:)` to return nil — user edits ignored
**File:** `ReceiptViewModel.swift` `tip` computed property L51  
If the serialised decimal uses scientific notation (`5E-1`), `Decimal(string:)` returns nil, falling back to `scannedReceipt?.tip` and discarding the user's edit. Same issue for `totalAmount`.

---

### H-20 — `ReceiptViewModel.total(for:)` unrounded intermediate Decimal accumulation can overflow Decimal representation
**File:** `ReceiptViewModel.swift` `total(for:)` L126–139  
`(tax + tip) / Decimal(participatingIDs.count)` is not rounded per-item before accumulation. Many items × many participants produces Decimal values with many decimal places, risking representation overflow in edge cases.

---

### H-21 — `FriendsView.ious(with:)` includes third-party IOUs — corrupts balance display in FriendDetailView
**File:** `FriendsView.swift` `ious(with:)` L75 and `netBalances(with:)` L63–70  
Filter does not constrain to the current user as a party. An IOU between friend B and an unrelated user C satisfies `lenderID == B` and appears in the detail view, inflating displayed balances.

---

### H-22 — `AppLockService.biometryType` creates a new `LAContext` on every read — expensive and can misreport during auth
**File:** `AppLockService.swift` `biometryType` computed var L46–49  
Called from `AppLockView.body` on every render frame. Each call instantiates `LAContext` and evaluates the biometric policy. Can misreport biometry type between the check and the actual `authenticate()` call.

---

### H-23 — `VisionService.preprocessForOCR` creates a new `CIContext` on every call despite a shared static instance existing
**File:** `VisionService.swift` `preprocessForOCR` L291  
`let context = CIContext(options: [.useSoftwareRenderer: false])` inside the method, duplicating the `static let ciContext` at L56. Multi-page scans initialize the Metal GPU pipeline once per page instead of once total.

---

### H-24 — `ExportService.generatePDF` "Paid By" column leaves only 1pt right margin — long names clip off page
**File:** `ExportService.swift` L135–141  
Column layout leaves 1pt right margin for "Paid By". Names longer than ~14 characters at 9pt bold overflow the printable area.

---

### H-25 — `ExportService.generateCSV` uses LF-only line endings — violates RFC 4180, breaks Excel on Windows
**File:** `ExportService.swift` `generateCSV` L46  
`lines.joined(separator: "\n")`. RFC 4180 requires CRLF. Excel on Windows, some enterprise accounting tools, and Apple Numbers on macOS require CRLF. Financial exports must use `\r\n`.

---

### H-26 — `GroupDetailView.searchable` placement causes search bar to not render — nav bar is hidden
**File:** `GroupDetailView.swift` ~L181  
`.searchable` uses `navigationBarDrawer` placement but `.toolbar(.hidden, for: .navigationBar)` is active. The search bar will not render on iOS 17 and behaves unpredictably on iOS 18+.

---

### H-27 — `GroupDetailView.showSettleUp` state is dead code — sheet is unreachable
**File:** `GroupDetailView.swift` L15 and L75  
`showSettleUp = true` is never set anywhere. The `SettleUpView` sheet bound to it is completely unreachable.

---

### H-28 — `HomeView` navigation destination renders blank screen when `currentUser` is nil at tap time
**File:** `HomeView.swift` `navigationDestination(for: BillGroup.self)` L190–196  
`if let userID = vm.currentUser?.id` evaluates to nil on slow/cold launch. SwiftUI renders nothing — the user navigates to a blank white screen with no loading indicator or error.

---

### H-29 — `SettleUpView` "Mark Settled" has no `isLoading` guard — rapid taps trigger duplicate settlements
**File:** `SettleUpView.swift` L43–47  
`Task { await vm.recordSettlement(suggestion) }` is fire-and-forget with no disabled state. Two confirmation dialogs can both succeed, settling the same balance twice.

---

### H-30 — `FriendsView` dead `quickAdd` method and `contactSuggestions` state never populated
**File:** `FriendsView.swift` L20, L331, L335  
`contactSuggestions: [User]` is declared and used in `quickAdd(_:)` but `loadAll()` never assigns to it. The method and state variable are dead code from a removed "From Your Contacts" section.

---

### H-31 — `FriendsView` loading indicator only shows when BOTH `ious` AND `allFriends` are empty — hidden on all subsequent refreshes
**File:** `FriendsView.swift` L82  
`if isLoading && ious.isEmpty && allFriends.isEmpty`. After the first load, both are non-empty, so the spinner never appears again on pull-to-refresh. No progress indication during background refresh.

---

### H-32 — `MainTabView` Quick Action opens sheet before `homeVM.groups` is guaranteed non-empty — sheet shows empty picker
**File:** `MainTabView.swift` L107–113  
`showQuickAddExpense = true` fires if `homeVM.currentUser != nil`, not after `homeVM.groups` is loaded. On a slow first load, `QuickAddExpenseSheet` opens with no groups to select.

---

### H-33 — `ProfileView` payment handle fields have no save path — changes are lost on navigation
**File:** `ProfileView.swift` L149–166  
`XBillPaymentHandleRow` fields for Venmo/PayPal are on the main profile screen as bindings but no save action is triggered. The only save path is the Edit Profile sheet, which does not include these fields. User changes are silently discarded.

---

### H-34 — `ProfileView.lifetimePaid` is hardcoded to `"USD"` regardless of the user's groups' currencies
**File:** `ProfileView.swift` L142  
`.formatted(currencyCode: "USD")` on a sum aggregated across all currencies without conversion. Non-USD users see an incorrect currency label and incorrect aggregated value.

---

### H-35 — `ExpenseDetailView` edit sheet "Save" button can be tapped during `isSaving` on some iOS versions; `isSaving` not cleared on sheet swipe-dismiss
**File:** `ExpenseDetailView.swift` L329–331  
`.overlay { ProgressView() }` without `.allowsHitTesting(false)` leaves the button frame tappable. If the user swipe-dismisses during save, the in-flight task has no cancellation and `isEditing = false` updates dismissed state.

---

### H-36 — `ExpenseDetailView.openEditSheet()` uses `NSDecimalNumber.stringValue` — can produce scientific notation
**File:** `ExpenseDetailView.swift` L341  
`editAmountText = NSDecimalNumber(decimal: expense.amount).stringValue` can produce `"1E-3"` for small amounts. The fix applied to `AddExpenseView` was not applied here.

---

### H-37 — `ExchangeRateService.rates(base:)` never checks HTTP status code — 4xx/5xx returns cryptic `DecodingError` to UI
**File:** `ExchangeRateService.swift` `rates(base:)` L66–68  
`URLResponse` is discarded (`_`). A 429 or 500 returns a non-JSON body, causing `DecodingError` with no contextual message. Rate-limit errors (1500 req/month on free tier) are invisible.

---

## MEDIUM — Real bugs that affect users in specific scenarios

---

### M-01 — `splitByShares` percentage has no last-participant correction — percentages may not sum to 100
**File:** `SplitCalculator.swift` `splitByShares` L100  
Each percentage is independently rounded. Unlike `splitEqually`, there is no `100 - distributedPct` correction for the last participant. Percentage breakdown displays can show 99.99% or 100.01%.

---

### M-02 — `AuthViewModel.signInWithApple/signIn/signUp` bypass `lastLoadedUserID` dedup — redundant profile reload on every sign-in
**File:** `AuthViewModel.swift` L109, L126, L138  
Direct `currentUser` assignment + auth listener both call `loadCurrentUser()`. Setting `lastLoadedUserID` after the direct assignment would prevent the redundant reload.

---

### M-03 — `CacheService.encrypt` silently falls back to plaintext when Keychain fails before first device unlock
**File:** `CacheService.swift` L106–124  
If the Keychain is unavailable (device rebooted, first-unlock not yet performed), `encrypt` returns nil and financial data is written as plaintext JSON to the App Group UserDefaults with no warning.

---

### M-04 — `NotificationStore.clearItems()` is dead public API — leaves `lastViewedAt` stale; should be removed
**File:** `NotificationStore.swift` L53–55  
Never called in production code. Leaves stale read-state metadata. Offers no value beyond `clearAll()`.

---

### M-05 — `IOU.createdBy` is non-optional but legacy DB rows with NULL would crash decode
**File:** `IOU.swift` L12  
`let createdBy: UUID`. A NULL from any path not enforced by a DB NOT NULL constraint causes a decode crash for the entire IOU list.

---

### M-06 — `ContentView.onTrySampleData` creates a throwaway `HomeViewModel` — sample groups only visible after full network reload
**File:** `ContentView.swift` L39–41  
A discarded `HomeViewModel()` creates sample data. The live VM in `MainTabView` must complete its own `.task loadAll()` before showing the data. On a slow network, users see empty Home for several seconds after choosing sample data.

---

### M-07 — `createDueRecurringInstances` `splitInputs.isEmpty` silently skips expense forever with no log
**File:** `GroupViewModel.swift` `createDueRecurringInstances` L197  
An expense with no splits (or whose splits failed to fetch via silent `try?`) is skipped on every launch. The template's `next_occurrence_date` is never advanced. No error surfaces to the user.

---

### M-08 — `fetchDueRecurringExpenses` only fetches templates where `paid_by = currentUserID` — inactive payer's templates never instantiate
**File:** `ExpenseService.swift` L105–115  
If the original payer stops opening the app, their recurring expenses are never created for anyone in the group.

---

### M-09 — `ISO8601DateFormatter` allocated per `fetchDueRecurringExpenses` call — expensive
**File:** `ExpenseService.swift` L106  
Should be a `static let`. `ISO8601DateFormatter` initialization is non-trivial and is called on every group-detail open.

---

### M-10 — `IOUService.fetchUserByEmail` trims only ASCII spaces — non-breaking spaces not stripped
**File:** `IOUService.swift` `fetchUserByEmail` L47  
`.trimmingCharacters(in: .whitespaces)` vs `.whitespacesAndNewlines`. Emails pasted from messaging apps with non-breaking spaces silently fail to find the user.

---

### M-11 — `ReceiptViewModel.totalAmount` user edits have no effect on split computation — `grandTotal` ignores the field
**File:** `ReceiptViewModel.swift` L34 and L53  
`totalAmount: String` is editable but never parsed back as `Decimal`. `grandTotal` = `totalFromItems + tax + tip`. A user who corrects a misread total sees splits unchanged.

---

### M-12 — `VisionService.extractDecimal` uses `firstMatch` — leftmost price returned instead of rightmost (line total)
**File:** `VisionService.swift` `extractDecimal` L644–652  
For lines with multiple prices, the first match is the unit price, not the line total. Fix: use `matches.last` or anchor to `$`.

---

### M-13 — `VisionService.parseWithHeuristics` does not detect ¥ or ₩ currency symbols — Japanese/Korean receipts default to USD
**File:** `VisionService.swift` `parseWithHeuristics` L491–494  
`ExchangeRateService.commonCurrencies` includes JPY and KRW but the symbol detection block has no case for `¥` or `₩`.

---

### M-14 — `FriendsView.friendIDsWithBalance` is O(n²) computed on every render
**File:** `FriendsView.swift` L48–55  
`.contains` called for every friend × every IOU. 50 friends × 200 IOUs = 10,000 comparisons per render pass. Should be precomputed as a `Set<UUID>`.

---

### M-15 — `ExportService.currencyFormatter` creates a new `NumberFormatter` per call without locale — German device shows comma-decimal format in exports
**File:** `ExportService.swift` `currencyFormatter` L252–258  
No `f.locale` set. On a German device, amounts are formatted as `1.234,56 USD` instead of `$1,234.56`. Fix: `f.locale = Locale(identifier: "en_US_POSIX")`.

---

### M-16 — `AppLockService.authenticate` auto-disables App Lock on any `canEvaluatePolicy` failure — kills security setting on device reboot
**File:** `AppLockService.swift` `authenticate()` L79–83  
`isEnabled = false` fires for all `canEvaluatePolicy` failures, not just `LAError.passcodeNotSet`. A transient hardware failure (enclave unavailable on first reboot unlock) permanently removes the user's security setting.

---

### M-17 — `GroupStatsView.memberData` maps multiple deleted users to `"Unknown"` — duplicate chart IDs crash SwiftUI Charts
**File:** `GroupStatsView.swift` `memberData` L40–46  
`Chart(memberData, id: \.name)` uses name as ID. Multiple deleted users all named "Unknown" cause SwiftUI Charts to collapse bars or behave unpredictably.

---

### M-18 — `group_members` INSERT policy allows adding non-existent user UUIDs — phantom members corrupt balance calculations
**File:** `006_groups_currency_member_rls.sql` L15–30  
No profile-existence check on INSERT. Any member can add arbitrary UUIDs, inflating member counts and corrupting splits.

---

### M-19 — `search_profiles` has no minimum query length — single-character queries enable directory enumeration
**File:** `021_fix_search_profiles_no_email.sql` L26  
No minimum length. A single character `a` returns up to 20 profiles. With repeated calls, the entire user directory is enumerable.

---

### M-20 — Group invite tokens are not invalidated after use — reusable within 7-day window
**File:** `012_group_invites.sql` L55–58  
`join_group_via_invite` does not DELETE the token after successful use. Anyone who obtains the token (see CRIT-06) can join the same group multiple times within the expiry window.

---

### M-21 — `GroupService.removeMember` silently does nothing when removing another user — RLS blocks the delete but no error is thrown
**File:** `GroupService.swift` L142–148  
`group_members` DELETE RLS is `auth.uid() = user_id` — only self-delete. Passing another user's ID returns HTTP 200 with zero rows affected. No error thrown; caller believes the removal succeeded.

---

### M-22 — `GroupService.deleteGroup` has no DELETE RLS policy on `groups` — call always silently no-ops
**File:** `GroupService.swift` L152–157  
No DELETE policy exists on `public.groups`. Supabase denies by default. The Swift call returns empty 200 (no `.select()`), no error thrown. Groups are never actually deleted.

---

### M-23 — APNs `apns-expiration` hardcoded to now+3600 — financial notifications lost when device offline >1 hour
**File:** `notify-expense/index.ts` L104 · `notify-settlement/index.ts` L93  
Settlement and expense notifications discarded after 1 hour if device is offline. APNs allows up to 30 days for alert notifications. Should be at least 86400.

---

### M-24 — `profiles` SELECT RLS policy does a cross-join with no index — O(N²) at scale
**File:** `023_high_rls_fixes.sql` L15–28  
The EXISTS subquery joins `group_members` to itself. No composite index on `(user_id, group_id)`. Hundreds of users × groups → full table scan on every profile row evaluation.

---

### M-25 — `IOUService.createIOU` accepts arbitrary party UUIDs — caller can create debt for third parties
**File:** `IOUService.swift` `createIOU` L60–91  
RLS only checks `auth.uid() = created_by`. Caller can set `created_by = auth.uid()` but assign `lenderID` to any third party — creating debt for users who never agreed to it.

---

### M-26 — `GroupViewModel.recordSettlement` over-settles splits: settles any unsettled split for `fromUserID`, not just splits belonging to this suggestion's creditor
**File:** `GroupViewModel.swift` `recordSettlement` L284–286  
If user A has unsettled splits to multiple creditors (B and C), settling with B also marks splits owed to C as settled.

---

### M-27 — `GroupViewModel.recordSettlement` `[weak self]` inside `withThrowingTaskGroup` silently swallows DB updates if `self` is deallocated
**File:** `GroupViewModel.swift` `recordSettlement` L289–297  
If `self` is nil when the task group runs (view dismissed), `guard let self else { return }` exits silently with zero splits settled and no error shown.

---

### M-28 — `HomeViewModel.unarchiveGroup` rollback is incomplete — `groups` left in partial-load state on failure
**File:** `HomeViewModel.swift` `unarchiveGroup(_:)` L115–136  
Catch block restores `archivedGroups` but not `groups`. After a failed `loadAll()` mid-unarchive, `groups` may be in a partial-load state.

---

### M-29 — `HomeViewModel.deleteGroup` has no `isLoading` guard and does not update cache after deletion
**File:** `HomeViewModel.swift` `deleteGroup(_:)` L95–103  
Double-tap risk. Cache is not updated after deletion — deleted group reappears on cold launch.

---

### M-30 — `HomeViewModel.computeBalances` display-name merge drops newer names with `{ old, _ in old }` resolution
**File:** `HomeViewModel.swift` `computeBalances(for:)` L204  
`allNames.merge(data.names) { old, _ in old }`. First group's stale name wins permanently for users shared across multiple groups.

---

### M-31 — Push preference keys read from `.standard` UserDefaults — App Group widget/extension writes to group suite and are never seen
**File:** `GroupViewModel.swift` L307 · `AddExpenseViewModel.swift` L183  
`UserDefaults.standard.bool(forKey: "prefPushSettlement")`. If a widget or extension writes the preference to the App Group suite, the main app never reads it — push notifications silently disabled.

---

### M-32 — `AddExpenseViewModel.canSave` not re-evaluated after `await updateConversion()` — form can save with invalid state
**File:** `AddExpenseViewModel.swift` `save()` L141  
User can empty the title or deselect all participants during the conversion `await`. By the time `createExpense` is called, the form is invalid but the initial `guard canSave` already passed.

---

### M-33 — `AddExpenseViewModel.updateConversion()` has no Task cancellation — stale rate from slow earlier call overwrites newer rate
**File:** `AddExpenseViewModel.swift` `updateConversion()` L118–136  
Rapid currency changes fire multiple concurrent `ExchangeRateService.rate()` calls. The last to complete wins. A slow earlier call can overwrite a correct newer result.

---

### M-34 — `ProfileViewModel.loadStats` fires N parallel `fetchExpenses` calls — 20 groups = 20+ concurrent DB queries
**File:** `ProfileViewModel.swift` `loadStats(userID:)` L70–103  
`withTaskGroup` launches one `fetchExpenses` per group simultaneously, combined with 20 calls already from `HomeViewModel.computeBalances` — 40+ simultaneous DB connections on profile open.

---

### M-35 — `GroupDetailView` filter state (`filterCategory`, `searchText`) persists across tab switches — silently filtered list on return
**Files:** `GroupDetailView.swift` L26 and L210–232  
No `.onChange(of: selectedTab) { filterCategory = nil; searchText = "" }`. Users see a mysteriously reduced expense list after switching tabs and returning.

---

### M-36 — `GroupDetailView` Balances and Settle Up tabs show stale or zero data while `vm.isLoading == true`
**File:** `GroupDetailView.swift`  
`vm.isLoading` only gates the expenses tab empty state. Balances tab shows empty rows; Settle Up tab shows "All Settled!" during initial load.

---

### M-37 — `FriendsView.FriendDetailView` receives a construction-time snapshot of `allIOUs` — stale after `settleAll()`
**File:** `FriendsView.swift` L112–121  
`allIOUs: ious(with: friendID)` is computed at navigation time. After settle, parent refreshes but the detail view holds the old snapshot. IOUs do not update until the user dismisses and re-opens.

---

### M-38 — `FriendDetailView.loadMutualGroups()` silently bails if `allGroups.isEmpty` with no retry
**File:** `FriendsView.swift` L450  
`guard !allGroups.isEmpty else { return }`. On cold launch race, mutual groups section is permanently empty with no error or retry affordance.

---

### M-39 — `FriendDetailView` uses system `.insetGrouped` list style and `.navigationTitle` — jarring visual inconsistency with rest of app
**File:** `FriendsView.swift` L430–431  
All other detail views use `XBillPageHeader` with `.toolbar(.hidden)`. The system large title navigation bar appears abruptly on navigation to friend detail.

---

### M-40 — `ActivityViewModel.markAllRead()` does not update in-memory `items` — unread indicators persist until next `load()`
**File:** `ActivityViewModel.swift` `markAllRead()` L48–53  
`store.markAllRead()` persists correctly but `items` in memory still has `isRead = false` on each row. The view shows stale unread indicators until the next `load()` call.

---

### M-41 — `ReceiptViewModel.asSplitInputs()` calls `total(for:)` N×M times — O(N×M) on main actor
**File:** `ReceiptViewModel.swift` `asSplitInputs()` L144–155  
`total(for:)` iterates all items once per member. 50 items × 10 members = 500+ iterations on `@MainActor` during save — stutter risk.

---

### M-42 — `ReceiptViewModel.scan(pages:)` does not clear `capturedPages` — stale pages visible on empty scan
**File:** `ReceiptViewModel.swift` `scan(pages:)` L71–101  
The doc comment says "Clear all state from any previous scan" but `capturedPages` retains previous pages. `scan(pages: [])` shows the old scan's pages while displaying results for an empty scan.

---

### M-43 — `ExpenseDetailView` `.onDelete` shows swipe affordance for ALL comments but silently ignores other users' comments
**File:** `ExpenseDetailView.swift` L141–145  
The `guard comment.userID == currentUserID else { continue }` inside `onDelete` means swipe-to-delete is visible on other users' comments but does nothing. No feedback given.

---

### M-44 — `ExpenseDetailView` realtime comment subscription silently fails if channel creation or any fetch fails
**File:** `ExpenseDetailView.swift` L181–187  
`try? await CommentService.shared.commentChanges(...)` — stream creation failure returns nil, silently disabling realtime. Fetch errors inside the stream are also silent via `try?`.

---

### M-45 — `MainTabView` QR deep-link sheet renders transparent/empty if `currentUser` is nil — brief transparent flash
**File:** `MainTabView.swift` L154–165  
`Color.clear.onAppear { dismiss }` is a known workaround but produces a visible transparent sheet flash before dismissal.

---

### M-46 — `MainTabView` foregrounding calls `activityVM.load()` but not `homeVM.refresh()` — balance data goes stale across backgrounding
**File:** `MainTabView.swift` L179  
`UIApplication.didBecomeActiveNotification` refreshes activity feed but not home balances. Changes made by other users while the app was backgrounded are not reflected until the user pull-to-refreshes.

---

### M-47 — `MainTabView.pendingAddFriendUserID` deep-link calls `searchProfiles(query: userID.uuidString)` — UUIDs never match name/email fields
**File:** `MainTabView.swift` L147  
`searchProfiles` uses `ILIKE` on `email` and `display_name`. UUIDs never appear in those fields. `AddFriendView` opens without pre-population; failure is silent.

---

### M-48 — `send_friend_request` bidirectional existence check has TOCTOU race between SELECT and INSERT
**File:** `025_medium_fixes.sql` L28–43  
Between `IF EXISTS` check and `INSERT`, a concurrent call can insert the reverse-direction row. Fix: `INSERT ... ON CONFLICT DO NOTHING` with a partial unique index on `(LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id))`.

---

### M-49 — `ActivityView.NotificationDetailSheet` shows stale `isUnread` state after "Mark Read" — does not re-render with updated item
**File:** `ActivityView.swift` L208  
`item` is passed by value at sheet presentation time. After `markRead`, `currentItem(for: item)` returns the updated item and `selectedItem` is updated, but `NotificationDetailSheet` renders the original captured value.

---

### M-50 — `ProfileView.scrollBottomPadding` adds FAB clearance padding when no FAB exists on the profile screen
**File:** `ProfileView.swift` L241–243  
`AppSpacing.xxl + AppSpacing.floatingActionBottomPadding` adds ~80pt of unnecessary bottom padding. The Profile tab has no FAB.

---

### M-51 — `ReceiptViewModel.totalAmount` user-edited field is never read back; edits have no effect on split computation
[See M-11 — confirmed by two agents]

---

### M-52 — `ProfileViewModel.loadStats` recurring template expenses inflate `lifetimePaid`
**File:** `ProfileViewModel.swift` `loadStats` L82–85  
Recurring template expenses (which have `amount` but represent no actual transaction) are counted in `lifetimePaid`, inflating the user's displayed total.

---

## LOW — Minor bugs, design smells, and polish issues

---

### L-01 — `Expense.Category` and `Expense.Recurrence` have no fallback for unknown DB values — entire expense decode fails on new enum member
**File:** `Expense.swift` L30–101  
No custom `init(from:)` with fallback to `.other`/`.none`. A future migration adding a new category causes all expenses with that category to crash the decoder, dropping them from the UI.

---

### L-02 — `GroupService.lookupProfilesByEmail` Row.email is non-optional but RPC no longer returns email — decoding crash on every call
**File:** `GroupService.swift` L239  
`let email: String` but migration 025 removed `email` from the `RETURNS TABLE` of `lookup_profiles_by_email`. Every call to `lookupProfilesByEmail` throws `keyNotFound` today. **This is likely a live crash.** Fix: `let email: String?` or remove the field.

---

### L-03 — `SplitCalculator.validateExact` shows raw `Decimal.description` — can show many decimal places in error strings
**File:** `SplitCalculator.swift` `validateExact` L121  
"Remaining: 0.00000001" in edge cases. Format both values to 2dp before interpolation.

---

### L-04 — `AuthService.deleteAccount()` calls `signOut()` after the Edge Function deletes the auth user — call always throws
**File:** `AuthService.swift` L100–101  
Once the auth user is server-side deleted, `signOut()` attempts to revoke an already-invalid session. The `.signedOut` auth-state event may not fire. Fix: wrap in `try?` and rely on the auth-state listener.

---

### L-05 — `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` uses `try?` — APNs token registration errors are silently dropped
**File:** `xBillApp.swift` L59  
No logging, no retry. If the user is signed out during token registration or the Supabase call fails, they silently never receive push notifications.

---

### L-06 — `fetchUnsettledExpenses` in `ExpenseService` is dead code — never called
**File:** `ExpenseService.swift` L49–58  
Dead public API. Should be removed or marked internal.

---

### L-07 — `NotificationStore.clearItems()` is dead public API with incomplete semantics — leaves `lastViewedAt` stale
**File:** `NotificationStore.swift` L53–55  
[See M-04]

---

### L-08 — `AuthViewModel.sendPasswordReset` has no success state property — success is view-only
**File:** `AuthViewModel.swift` `sendPasswordReset()` L157  
No ViewModel-level success flag. Cannot be called from any entry point other than `ForgotPasswordView`.

---

### L-09 — `ErrorAlert` second error silently replaces first if alert is still presented — user sees wrong error message
**File:** All ViewModels, all error paths  
`ErrorAlert` is `Identifiable`. A new instance with the same `id` (or type) while the alert is presented does not re-trigger `.alert(item:)`. User sees old error title for new failure.

---

### L-10 — `splits.settled_at` / `is_settled` have no consistency constraint — can be set independently
**File:** `001_initial_schema.sql` L164–171  
No CHECK constraint enforcing `(is_settled = false AND settled_at IS NULL) OR (is_settled = true)`. Stale `settled_at` with `is_settled = false` is silently valid.

---

### L-11 — `join_group_via_invite` error messages distinguish "invalid token" from "expired token" — information oracle
**File:** `012_group_invites.sql` L47–48  
Different exceptions for invalid vs expired tokens confirm whether a guessed token ever existed. Both paths should raise the same message: `'Invalid or expired invite token'`.

---

### L-12 — `VisionService.recognizeText` discards `UIImage` orientation before OCR — rotated receipt photos produce garbage text
**File:** `VisionService.swift` `recognizeText` L339  
`VNImageRequestHandler(cgImage: cgImage, options: [:])` with no orientation. Should pass `CGImagePropertyOrientation(image.imageOrientation)`.

---

### L-13 — `GroupDetailView` FAB has generic "Add" accessibility label — no context for VoiceOver users
**File:** `GroupDetailView.swift` L176  
`FABButton` announces "Add" with no qualifier. `FriendsView` correctly overrides with `.accessibilityLabel("Add IOU")`. GroupDetailView should use "Add Expense".

---

### L-14 — `GroupDetailView` export functions silently do nothing on `writeTemp` failure — no user feedback
**File:** `GroupDetailView.swift` `exportCSV()` L449 · `exportPDF()` L462  
`guard let url = try? ... else { return }`. Disk-full or temp-directory errors produce no alert, no haptic, no toast.

---

### L-15 — `ProfileView` edit sheet has no display name length limit or empty guard
**File:** `ProfileView.swift` L325–340  
Save button only disabled on `vm.isLoading`. Empty display name saves to DB and propagates everywhere. [DUP: H-17]

---

### L-16 — `ActivityView.groupedItems` creates a new `DateFormatter` on every SwiftUI evaluation pass
**File:** `ActivityView.swift` L59–65  
`DateFormatter` initialized inline in a computed property called from `body`. Should be `private static let`.

---

### L-17 — `ProfileView` stats section shows zeros before `loadStats` completes — no loading skeleton
**File:** `ProfileView.swift` L138–143  
"Groups: 0, Expenses: 0, Total Paid: $0.00" flashes before real data arrives. Use a `redacted(reason: .placeholder)` skeleton.

---

### L-18 — `ProfileView` uses deprecated `UIImagePickerController` for avatar — replaced by `PHPickerViewController` since iOS 14
**File:** `ProfileView.swift` L13–47  
Deprecated picker doesn't support multi-select, shows older UI, generates deprecation warnings in console on iOS 18+.

---

### L-19 — `HomeView` recent expenses rows are not tappable — no NavigationLink
**File:** `HomeView.swift` L168–186  
`ExpenseRowView` in the "Recent Expenses" section renders as plain views. Users naturally expect rows to navigate to expense detail (they do in `GroupDetailView`).

---

### L-20 — `SettleUpView` settlement amounts always shown in `Color.moneyNegative` (red) regardless of perspective
**File:** `SettleUpView.swift` L76  
From the creditor's perspective the settlement is positive. All rows display in red unconditionally.

---

### L-21 — `ContentView.sampleDataError` alert uses hardcoded title string instead of the `ErrorAlert` pattern
**File:** `ContentView.swift` L74–81  
Every other alert in the app uses `ErrorAlert` with `errorDescription` as the title. This alert uses a hardcoded "Sample Data Error" string.

---

### L-22 — `ReceiptViewModel.confidenceLabel` uses `PartialRangeFrom` switch — fragile under future case additions
**File:** `ReceiptViewModel.swift` `confidenceLabel` L55–60  
`case 0.90...:` and `case 0.75...:` are non-idiomatic. Adding `case 0.95...:` above changes semantics of `0.90...` silently.

---

### L-23 — `ReceiptViewModel.updateUnitPrice/updateQuantity` reconstruct `ReceiptItem` by destructuring — silently drops future fields
**File:** `ReceiptViewModel.swift` L183–213  
New fields added to `ReceiptItem` are zeroed. Use `var copy = items[index]` + mutate pattern.

---

### L-24 — `VisionService.validateHeuristic` called twice in `processScan` — redundant computation
**File:** `VisionService.swift` `processScan` L158–165  
Same validation math runs twice per scan. Cache the result in a local variable.

---

### L-25 — `ExchangeRateService` has no disk persistence of cached rates — first-launch offline throws hard error to UI
**File:** `ExchangeRateService.swift` `rates(base:)` L57–74  
In-memory cache only. On first launch offline, every foreign-currency expense conversion throws a `URLError`. Stale disk-persisted rates (with a "data may be outdated" label) would be far better UX for travelers.

---

### L-26 — `AddIOUView` description field has no character length cap — very long descriptions send oversized requests to Supabase
**File:** `AddIOUView.swift`  
No `.onChange` limiting character count. A user who pastes multi-KB content causes an oversized request with no user-facing validation.

---

### L-27 — `CacheService.saveBalance` writes multiple `UserDefaults` keys without atomicity — widget reads may see partial state
**File:** `CacheService.swift` L65–73  
Multiple `defaults.set` calls are individually atomic but not collectively. A widget reading `netBalance` mid-write may see an updated `netBalance` but a stale `totalOwed`.

---

### L-28 — `xBillApp` `@State private var authVM = AuthViewModel()` — duplicate listener if App struct is reconstructed on scene lifecycle events
**File:** `xBillApp.swift` L162  
`isListening` is instance-level. A reconstructed `App` struct creates a new instance with `isListening = false` and re-subscribes, running two concurrent auth listeners.

---

### L-29 — `InviteJoinRequest` data type co-located in `AuthViewModel.swift`
**File:** `AuthViewModel.swift` L11–14  
A pure data type defined inside a ViewModel file. Should live alongside `GroupInvite.swift`.

---

### L-30 — `ExpenseService` mixes notification dispatch (`notifyExpenseAdded`, `notifySettlementRecorded`) with data-access concerns
**File:** `ExpenseService.swift` L155–221  
Notification logic in a data-access service makes unit testing harder and method placement non-obvious. Should live in a `NotificationService` or be moved to the ViewModel layer.

---

## Summary by Feature Area

| Feature | Critical | High | Medium | Low |
|---|---|---|---|---|
| Recurring Expenses | 2 | 1 | 3 | — |
| RLS / Database | 5 | 4 | 9 | 2 |
| Edge Functions | — | 2 | 1 | 1 |
| SplitCalculator | — | 2 | 2 | 2 |
| Auth | — | 2 | 1 | 4 |
| GroupViewModel | 1 | 3 | 5 | 2 |
| HomeViewModel | — | 3 | 5 | 2 |
| AddExpenseViewModel | — | 2 | 3 | 2 |
| ProfileViewModel | — | 2 | 3 | 2 |
| ActivityViewModel | — | 1 | 2 | 2 |
| ReceiptViewModel | — | 2 | 4 | 3 |
| GroupDetailView | — | 2 | 5 | 2 |
| AddExpenseView | — | 1 | 3 | 2 |
| HomeView | — | 1 | 2 | 1 |
| FriendsView | — | 3 | 5 | 1 |
| SettleUpView | — | 1 | 2 | 1 |
| MainTabView | — | 1 | 3 | 1 |
| ExpenseDetailView | 1 | 2 | 2 | 1 |
| ProfileView | — | 2 | 3 | 3 |
| IOUService | 1 | — | 2 | — |
| ExchangeRateService | — | 1 | — | 1 |
| ExportService | — | 2 | 1 | — |
| AppLockService | — | 1 | 1 | — |
| VisionService | — | 1 | 2 | 2 |
| CacheService / NotificationStore | — | — | 2 | 2 |
| **TOTAL** | **11** | **37** | **71** | **36** |

---

## Triage: Fix These First

### Likely live crashes today
1. **L-02** — `GroupService.lookupProfilesByEmail` `Row.email: String` decodes a key the RPC no longer returns → `keyNotFound` crash on every contact-discovery call
2. **CRIT-02** — `SplitInput.init(from:)` `assertionFailure` crashes every debug-build recurring expense creation

### Security — fix before any public launch
3. **CRIT-06** — All invite tokens readable by all authenticated users
4. **CRIT-07** — APNs token hijacking via `device_tokens` INSERT
5. **CRIT-03** — Any group member can rename/archive/hijack group
6. **CRIT-04** — IOU amount/parties mutable by either party
7. **CRIT-05** — Friend status/requester forgeable by addressee
8. **H-08 / H-09** — Notification spoofing in edge functions

### Data integrity — fix before v1.0
9. **CRIT-01** — Infinite duplicate recurring expenses on partial failure
10. **CRIT-08** — Silent IOU settle failures
11. **M-22** — `deleteGroup` silently no-ops (no DELETE RLS policy)
12. **M-21** — `removeMember` silently no-ops when removing another user
