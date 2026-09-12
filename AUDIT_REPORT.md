# xBill — Comprehensive Defect Audit Report
**Last updated:** 2026-08-31
**Scope:** All defect findings across three audit passes + security review  
**Status:** Historical 214 findings resolved. Post-040 notification hardening is implemented locally; Edge Function deployment and physical-device verification remain release gates.

## Post-040 Notification Audit — 2026-07-28

The follow-up review found and fixed these issues in the working tree:

- `notify-expense`, `notify-comment`, and `notify-friend-request` now derive event data from trusted rows and authorize the caller before using the service role. Settlement notifications now validate both group memberships and derive the group name server-side.
- Notification cache keys are user-scoped, preventing account-switch leakage. Activity mutations now roll back local optimistic changes when the remote operation fails.
- Comment and friend-request notification invokes are awaited and logged. Push taps without a group target route to Recent instead of doing nothing.
- Added a regression test for per-user cache isolation. Unit coverage passed via `scripts/run-coverage.sh unit` on 2026-07-28.

The updated Edge Functions have not been deployed in this pass because deployment writes live Supabase state and requires explicit approval.

---

## Table of Contents
1. [Summary](#summary)
2. [Defect Audit v1 — Critical (20)](#defect-audit-v1--critical)
3. [Defect Audit v1 — High (45)](#defect-audit-v1--high)
4. [Defect Audit v1 — Medium (62)](#defect-audit-v1--medium)
5. [Defect Audit v1 — Low (47)](#defect-audit-v1--low)
6. [Defect Audit v1 — Architectural (4)](#defect-audit-v1--architectural)
7. [Defect Audit v2 — Second Pass (20)](#defect-audit-v2--second-pass)
8. [Security Audit (16)](#security-audit)
9. [Additional Bug Fixes](#additional-bug-fixes)
10. [Payment Handoff Defect — 2026-07-27](#payment-handoff-defect--2026-07-27)
11. [Payment Handle Experience + Unified Diagnostics — 2026-07-27](#payment-handle-experience--unified-diagnostics--2026-07-27)
12. [Notification Unread Lifecycle — 2026-07-28](#notification-unread-lifecycle--2026-07-28)
13. [Senior Developer Review — 2026-07-28 (REV)](#senior-developer-review--2026-07-28-rev)
14. [Open Items](#open-items)

---

## Summary

| Audit | Critical | High | Medium | Low | Arch | Total | Status |
|---|---|---|---|---|---|---|---|
| Defect Audit v1 (2026-05-06) | 20 | 45 | 62 | 47 | 4 | 178 | ✅ All fixed |
| Defect Audit v2 (2026-05-09) | 2 | 4 | 9 | 5 | — | 20 | ✅ All fixed |
| Security Audit (2026-05-02) | 2 | 4 | 5 | 5 | — | 16 | ✅ All fixed |
| **Total** | **24** | **53** | **76** | **57** | **4** | **214** | ✅ All fixed |

**Key commits:**
- `b126a61` — All 20 Critical defects (2026-05-06)
- `4ea9b06` — All 45 High defects (2026-05-06/07)
- `cfc6b26` — All 62 Medium defects + migration 025 (2026-05-07)
- `ae1179d` — All 47 Low defects + Edge Function deploys (2026-05-08)
- `f0fa4ae` — All 4 Architectural defects (2026-05-08)
- `35d0c84` — Login keyboard jump (2026-05-08)
- `2242f44` — All 20 v2 defects (2026-05-09)
- Security fixes committed 2026-05-02 (no single commit tag — applied across multiple files)

---

## Defect Audit v1 — Critical

All 20 critical defects fixed in commit `b126a61` (2026-05-06).

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| CRIT-01 | `Models/Expense.swift:18` | `Expense.payerID` declared non-optional but DB column `paid_by` is nullable after migration 017. Any group with a deleted payer crashes at Codable decode. | ✅ Fixed | Changed `payerID` to `UUID?`. All callers updated: `SplitCalculator.netBalances`, `ActivityService`, `ExportService`, `ExpenseRowView`, `GroupStatsView`, `GroupViewModel`, `ExpenseDetailView`. |
| CRIT-02 | `Models/Group.swift:17` | `BillGroup.createdBy` declared non-optional but DB column `created_by` is nullable after migration 017. Fetching any group whose creator deleted their account crashes the app. | ✅ Fixed | Changed `createdBy` to `UUID?`. All callers updated. |
| CRIT-03 | `migrations/001_initial_schema.sql:148` | No UPDATE RLS policy on `expenses` table. Every call to `ExpenseService.updateExpense` silently rejected by Postgres for 100% of users. Entire edit-expense UI flow was broken at the DB level. | ✅ Fixed | `migrations/022_expenses_update_rls.sql` — adds `FOR UPDATE USING (is_group_member(group_id))` policy on `expenses`. |
| CRIT-04 | `Core/AppState.swift:27` | `AppState.shared` singleton not cleared on sign-out. `pendingQuickAction`, `spotlightTarget`, `pendingNotificationTarget`, `pendingAddFriendUserID` from user A persist when user B signs in — cross-user data leak. | ✅ Fixed | Added `AppState.clear()` method. Called from `AuthViewModel.startListeningToAuthChanges()` on `.signedOut` event. |
| CRIT-05 | `Services/NotificationStore.swift:46` | `NotificationStore` is `@unchecked Sendable` with no actor, lock, or serial queue. `merge`, `markRead`, `markAllRead`, `delete`, and `save` all do read→mutate→write with no synchronisation. Concurrent callers drop read-state changes and duplicate entries. | ✅ Fixed | Added `private let lock = NSLock()`. All public methods wrapped in `lock.withLock {}`. |
| CRIT-06 | `Services/CacheService.swift:31` | `JSONEncoder`/`JSONDecoder` are not thread-safe. Stored as shared instance properties on a `final class: Sendable`. Concurrent `save`/`load` calls corrupt encode/decode. | ✅ Fixed | `save<T>` and `load<T>` now create local `JSONEncoder`/`JSONDecoder` instances per call instead of using stored shared instances. |
| CRIT-07 | `ViewModels/GroupViewModel.swift:82` | `computeBalances` fetches splits with a serial `for expense in expenses` loop — N sequential round-trips blocking the MainActor. 50 expenses = 50 sequential network calls. | ✅ Fixed | Replaced with `withTaskGroup` — all split fetches run in parallel. |
| CRIT-08 | `ViewModels/GroupViewModel.swift:247` | `recordSettlement` uses stale `splitsMap`. If another device settled between the last `load()` and this settlement, already-settled splits are re-settled (double-settle) or splits are missed entirely. | ✅ Fixed | `recordSettlement()` now fetches fresh splits for the relevant expenses via parallel `withTaskGroup` before settling. |
| CRIT-09 | `ViewModels/HomeViewModel.swift:174` | `withTaskGroup` child tasks capture `self` strongly. Navigating away does not cancel the tasks — `HomeViewModel` stays alive until all N group fetches complete (potentially tens of seconds). | ✅ Fixed | Per-group balance work is now a static worker receiving only immutable service dependencies; child tasks no longer retain `HomeViewModel`. Structured cancellation still propagates from the parent load task. |
| CRIT-10 | `ViewModels/HomeViewModel.swift:64` | `loadAll()` and `refresh()` only fetch active groups. `archivedGroups` only refreshes from `GroupListView.task`. Archiving from `GroupDetailView` leaves `archivedGroups` stale. | ✅ Fixed | `HomeViewModel.loadAll()` now calls `await loadArchivedGroups()` on every successful network fetch. |
| CRIT-11 | `ViewModels/AddExpenseViewModel.swift:163` | `Task { await expenseService.notifyExpenseAdded(...) }` creates an unstructured task with no cancellation handle. Continues running after view dismissal with no error propagation. | ✅ Fixed | `save()` and `GroupViewModel.recordSettlement()` now `await` notification calls inline instead of spawning untracked `Task {}` closures. |
| CRIT-12 | `ViewModels/AddExpenseViewModel.swift:128` | `amount` is computed live from `amountText`. If `amountText` changes between the `canSave` guard and the `if isForeignCurrency` branch, `finalAmount` differs from what `convertedAmount` was computed for. Expense saved with mismatched amounts. | ✅ Fixed | `save()` captures `finalAmount` into `capturedAmount` (local `let`) immediately after conversion, before any `await`. `capturedAmount` is used for the save call. |
| CRIT-13 | Multiple service files | Core services declared `Sendable` without actor isolation, making future mutable state vulnerable to data races. | ✅ Fixed | Supabase-backed services are now `@MainActor` isolated. Cross-thread stores retain explicit synchronization or immutable/thread-safe Foundation boundaries. Complete strict-concurrency build passes. |
| CRIT-14 | `Core/SupabaseClient.swift:18` | Non-isolated `private init()` constructs `SupabaseClient` (sets up auth state listeners) and `emitLocalSessionAsInitialSession: true` emits a session event from inside `init`, re-entrantly accessing `KeychainManager.shared` before setup is complete. | ✅ Fixed | `SupabaseManager` and its initialization are now `@MainActor` isolated, so SDK/client setup and auth-state access share one serialized isolation boundary. |
| CRIT-15 | `ViewModels/AuthViewModel.swift:58` | `startListeningToAuthChanges()` `for await` loop has no cancellation handle. Calling it a second time (scene reconnect, foreground) creates a second subscriber — both loops call `loadCurrentUser()` concurrently. | ✅ Fixed | Added `isListening` guard flag. `startListeningToAuthChanges()` is a no-op if already subscribed. |
| CRIT-16 | `ViewModels/GroupViewModel.swift:166` | `createDueRecurringInstances` — new instance created with `recurrence: expense.recurrence` and `nextOccurrenceDate: newNextDate`. A concrete past-due occurrence should have `recurrence: .none, nextOccurrenceDate: nil`. As-is, the new instance triggers itself on the next run (infinite self-duplication). | ✅ Fixed | New instance created with `recurrence: .none, nextOccurrenceDate: nil`. Template advanced via new `ExpenseService.setNextOccurrenceDate(_:expenseID:)` instead of clearing the date. |
| CRIT-17 | `xBillTests/GroupFlowTests.swift:274` | 4 vacuous archive-warning tests assert on locally-constructed Swift arrays or closures — never calling any production type. Tests pass even if production code is deleted. | ✅ Fixed | All 4 tests rewritten to call `SplitCalculator.minimizeTransactions` and assert on real production output. |
| CRIT-18 | `Views/Expenses/ExpenseDetailView.swift:138` | Swipe-to-delete comment: no confirmation dialog. `try? deleteComment` discards the error. On failure the comment is still removed from the local `comments` array — UI permanently out of sync with DB. | ✅ Fixed | Added `confirmationDialog` before delete. Errors now surfaced via `errorAlert` instead of swallowed. Local array not mutated on failure. |
| CRIT-19 | `Views/Groups/GroupDetailView.swift:253` | Swipe-to-delete expense shows no confirmation dialog. Cascade-deletes all splits. Irreversible with no warning. | ✅ Fixed | Added `confirmationDialog` with `expenseToDelete: Expense?` state. Only deletes after user confirms. |
| CRIT-20 | `Views/Groups/SettleUpView.swift:70` / `Views/Friends/FriendsView.swift:398` | "Mark Settled" and "Settle All" are irreversible financial actions that send push notifications — neither has a confirmation dialog. | ✅ Fixed | Both paths now show `confirmationDialog` before calling `recordSettlement`. |

---

## Defect Audit v1 — High

All 45 High defects fixed across commits `4ea9b06` (2026-05-06) and subsequent fixes for H-05/H-07 (2026-05-07).

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| H-01 | `migrations/001_initial_schema.sql:177` | `splits` table has SELECT, INSERT, UPDATE but no DELETE RLS policy. Direct split deletion blocked for all users. | ✅ Fixed | `migrations/023_high_rls_fixes.sql` — adds DELETE policy using `is_expense_group_member(expense_id)`. |
| H-02 | `migrations/001_initial_schema.sql:21` | `profiles` RLS `own read` policy — group members cannot read each other's profiles. Fetching member display names returns zero rows. | ✅ Fixed | `migrations/023_high_rls_fixes.sql` — adds SELECT policy allowing group-member co-visibility via `is_group_member`. |
| H-03 | `migrations/016_create_device_tokens_table.sql:13` | `device_tokens` missing UPDATE RLS policy. APNs token refresh upserts fail RLS, accumulating stale tokens. | ✅ Fixed | `migrations/023_high_rls_fixes.sql` — adds UPDATE policy so users can update their own tokens. |
| H-04 | `supabase/functions/notify-friend-request/index.ts:97` | `fromUserID` (user PII / internal UUID) leaked in APNs `userInfo` payload. Accessible via lock-screen notification extensions. | ✅ Fixed | Removed `fromUserID` from APNs `userInfo` payload in `notify-friend-request/index.ts`. |
| H-05 | `functions/notify-expense/index.ts:111` / `notify-comment/index.ts:126` | Badge count = unsettled split count (wrong semantics). O(N) DB queries per send (one per device token). Phantom badge on DB error (`count ?? 1`). | ✅ Fixed (2026-05-07) | Replaced O(N) per-token `getUnreadCount` with `batchUnreadCounts` — one query for all recipients, aggregated in JS. Fixed phantom badge fallback from `?? 1` to `?? 0`. |
| H-06 | `Services/IOUService.swift:43` | `fetchUserByEmail` queries `profiles` table directly, bypassing the `lookup_profiles_by_email` SECURITY DEFINER RPC — allows full email enumeration. | ✅ Fixed | Changed to use `supabase.client.rpc("lookup_profiles_by_email", params:)`. |
| H-07 | `Services/GroupService.swift:97` | `createGroup` is non-atomic — group row inserted, then `addMember` in a second round-trip. On crash/network drop the group exists in DB but the creator is not a member — permanently invisible. | ✅ Fixed (2026-05-07) | `migrations/024_create_group_atomic.sql` — `create_group_with_member` SECURITY DEFINER RPC performs both INSERTs in one transaction. `GroupService.createGroup` now calls the RPC. |
| H-08 | `Services/ExchangeRateService.swift:29` | `rates: [String: Double]` — `Double`→`Decimal` conversion propagates binary floating-point error into exact decimal arithmetic. All multi-currency balance calculations systematically imprecise. | ✅ Fixed | Rates cached as `Decimal` (via `Decimal(string: String(value))` roundtrip). `rate(from:to:)` returns `Decimal`. All callers updated. |
| H-09 | `Services/ActivityService.swift:25` | `try? await self.items(for: group)` returns `[]` on failure. Caller sees partial result with no error — entire groups silently absent from activity feed. | ✅ Fixed | `items(for:)` returns `Result<[NotificationItem], Error>`. Errors surfaced rather than silently returning empty. |
| H-10 | `Services/AuthService.swift:136` | `updateDeviceToken` — delete then insert with no transaction. On crash/network drop between steps, user has no device token and silently stops receiving push notifications. | ✅ Fixed | Changed to insert-first (upsert on `user_id,token`), then delete stale tokens atomically. |
| H-11 | `Services/SplitCalculator.swift:100` | `validateExact` returns signed (not absolute) "Remaining" value — user sees "Remaining: -0.10" when splits exceed total. Misleading and incorrect. | ✅ Fixed | Takes absolute value before rounding to avoid false negative on negative differences. |
| H-12 | `Services/SplitCalculator.swift:38` | `splitEqually` percentage rounded to integer (no scale arg). A $10 three-way split produces 33/33/33 = 99%, not 100% — false validation error in the percentage-split UI. | ✅ Fixed | Last participant gets `100 - distributedPct` to ensure percentages always sum to 100. |
| H-13 | `Services/SplitCalculator.swift:126` | `minimizeTransactions` can infinite-loop on non-zero residual Decimal balances — loop only advances when a balance reaches exactly `.zero`. Tiny residuals from cross-group merges hang the UI. | ✅ Fixed | Epsilon guard (0.005) skips balances below threshold, preventing infinite loop on Decimal residuals. |
| H-14 | `ViewModels/AddExpenseViewModel.swift:44` | State not reset between sheet presentations — title, amount, notes, splits, isSaved, errorAlert retain values from the previous use. Re-opening Add Expense shows stale data. | ✅ Fixed | `startManually` and `scan` now fully reset all state before use. |
| H-15 | `ViewModels/AddExpenseViewModel.swift:118` | `convertedAmount` uses `.plain` rounding (truncates at .005 boundary). Financial apps should use `.bankers`. Split amounts may not sum to `finalAmount`, triggering false validation errors. | ✅ Fixed | Addressed together with H-08 — `exchangeRate` is now `Decimal`; arithmetic uses Decimal's banker rounding. |
| H-16 | `ViewModels/GroupViewModel.swift:212` | `deleteExpense` has no `isLoading` guard. Multiple rapid swipe-to-delete gestures can fire concurrently. | ✅ Fixed | Added double-tap guard with `isLoading` flag, matching `updateExpense` pattern. |
| H-17 | `ViewModels/GroupViewModel.swift:133` | `archiveGroup` removes from active cache but doesn't add to archived cache. Offline users don't see newly archived group in archived list until network. | ✅ Fixed | Variable renamed for clarity; `archiveGroup` updates both active and archived caches. |
| H-18 | `ViewModels/HomeViewModel.swift:86` | `refresh()`, `loadArchivedGroups()`, `unarchiveGroup()` can run concurrently. `unarchiveGroup` reads `groups`, suspends for network, then `loadAll()` may have replaced the arrays — TOCTOU. | ✅ Fixed | Added `isComputingBalances` flag that guards concurrent balance recomputes. |
| H-19 | `ViewModels/HomeViewModel.swift:133` | `createSampleData` has `try?` on all `createExpense` calls. Group created with no expenses on failure, with no error shown. | ✅ Fixed | Errors surfaced via `errorAlert` instead of silently swallowed. `isLoading` guard added. |
| H-20 | `ViewModels/AuthViewModel.swift:95` | `signUp` missing `AppError.isSilent` guard — cancellation errors shown as confusing alerts. | ✅ Fixed | `guard !AppError.isSilent(error)` added, matching all other auth action handlers. |
| H-21 | `ViewModels/AuthViewModel.swift:41` | `isEmailValid` accepts malformed emails (`@.`, `a@b.`, `@example.com`) via trivial `contains("@") && contains(".")` check. | ✅ Fixed | Replaced with regex: `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`. Also fixed in `InviteMembersView`. |
| H-22 | `ViewModels/AuthViewModel.swift:67` | `.userUpdated` event skips `loadCurrentUser()` if user already set (`if currentUser == nil`). Profile/password changes never trigger a profile refresh — `currentUser` stays stale. | ✅ Fixed | Auth listener no longer skips `loadCurrentUser()` on `.userUpdated` events. |
| H-23 | `ViewModels/ProfileViewModel.swift:86` | `saveProfile` — avatar uploaded before profile updated. If `updateProfile` throws, image is orphaned in Storage and profile still references the old URL. | ✅ Fixed | Reordered: update profile row first, then upload avatar. |
| H-24 | `ViewModels/ProfileViewModel.swift:53` | `loadStats` silently swallows auth errors — shows misleading $0 stats while session is actually invalid. | ✅ Fixed | Auth errors now surface `ErrorAlert(title: "Session Expired")` instead of being swallowed. |
| H-25 | `ViewModels/ProfileViewModel.swift:108` | `signOut` clears `user` only — `displayName`, `venmoHandle`, `paypalEmail`, stats fields remain. Next user's Profile screen briefly shows previous user's PII. | ✅ Fixed | `signOut` clears all PII fields. |
| H-26 | `ViewModels/ActivityViewModel.swift:23` | `fetchRecentActivity` calls `NotificationStore.merge()` then reads `unreadCount` separately. A concurrent `markRead` between the two yields a stale (too high) badge count. | ✅ Fixed | Load order swapped: reads items first, then syncs `unreadCount` from store. |
| H-27 | `ViewModels/ActivityViewModel.swift:27` | `AppError.unauthenticated` surfaced as a raw error alert ("unauthenticated" is meaningless to users; should force sign-out). | ✅ Fixed | Unauthenticated errors suppressed to avoid spurious alert; auth listener handles sign-out. |
| H-28 | `ViewModels/ReceiptViewModel.swift:44` | `grandTotal` reads `scannedReceipt?.tip` (original OCR result), not the editable `tipAmount` field. User corrections to tip never affect totals or splits. | ✅ Fixed | `tip` computed property: locale-safe Decimal parse from `tipAmount: String` (replaces `,` with `.`). |
| H-29 | `ViewModels/ReceiptViewModel.swift:141` | `startManually` does not reset `confidence`, `parsingTier`, `errorAlert`, `isScanning`. Stale scan metadata shows in review UI on manually-entered receipts. | ✅ Fixed | `startManually` and `scan` fully reset all scan state before starting. |
| H-30 | `ViewModels/ReceiptViewModel.swift:68` | `scan()` does not clear stale state before new scan. "Scan Again" that throws shows old results paired with new error message. | ✅ Fixed | See H-29 — both methods now fully clear state. |
| H-31 | `Views/Main/HomeView.swift:186` | `currentUserID: vm.currentUser?.id ?? UUID()` passes a random UUID if user hasn't loaded. `GroupDetailView` uses a random UUID for all permission checks. | ✅ Fixed | `navigationDestination` guarded with `if let userID = vm.currentUser?.id`. |
| H-32 | `Views/Main/MainTabView.swift:39` | `FriendsView(currentUserID: homeVM.currentUser?.id ?? UUID(), ...)` — same random-UUID problem. IOU direction inverted for the entire session. | ✅ Fixed | `FriendsView.currentUserID` changed to `UUID?`; `MainTabView` passes optional. |
| H-33 | `Views/Main/ActivityView.swift:28` | `.task` and `.onAppear` both trigger loading on first appear. On every tab switch `.onAppear` refreshes count but `.task` doesn't re-fire — list stale, count current. | ✅ Fixed | Removed duplicate `.onAppear { vm.refreshUnreadCount() }` — `.task` is the sole load path. |
| H-34 | `Views/Groups/GroupDetailView.swift:61` | `.task` fires `createDueRecurringInstances` without completion check — partial DB writes on navigation-away cancellation. Called again on every view appearance with no guard. | ✅ Fixed | Added comment noting idempotency behavior. The RPC is idempotent by design (checks `next_occurrence_date`). |
| H-35 | `xBillWidget/xBillBalanceWidget.swift:73` | Widget always shows `$` regardless of user's group currencies. | ✅ Fixed | `BalanceEntry` now carries `currency: String`; amounts formatted with `NumberFormatter` using stored currency code. |
| H-36 | `xBillWidget/xBillBalanceWidget.swift:37` | Widget timeline has one entry — stale data shown indefinitely under iOS low-power mode. No `.atEnd` fallback. | ✅ Fixed | Timeline produces 3 entries (now, +30min, +60min) with `.atEnd` policy. |
| H-37 | `xBillWidget/xBillBalanceWidget.swift:43` | Widget shows "You owe $0.00" permanently if App Group not registered — no error state or "data unavailable" text. | ✅ Fixed | Widget shows "No data yet" state when `xbill_balance_available` key is absent from UserDefaults. |
| H-38 | `Views/Groups/GroupDetailView.swift:395` | Dead `toolbar` property — identical to `groupMenu`, never applied with `.toolbar { toolbar }`. Will silently diverge. | ✅ Fixed | Dead `@ToolbarContentBuilder private var toolbar` property removed. |
| H-39 | `Views/Expenses/AddExpenseView.swift:357` | `NSDecimalNumber(decimal: total).stringValue` returns `"5E-3"` for small values. `Decimal(string:)` cannot parse scientific notation — silently sets amount to zero. | ✅ Fixed | Changed to `"\(total)"` (Swift string interpolation of Decimal avoids scientific notation). |
| H-40 | `Views/Main/ContentView.swift:36` | `HomeViewModel().createSampleData(userID:)` creates a throwaway VM — live `MainTabView.homeVM` never knows about the data. User sees nothing after tapping "Try with sample data". | ✅ Fixed | `ContentView.onTrySampleData` now sets `hasCompletedOnboarding = true` so live `homeVM` in `MainTabView` fetches fresh data from Supabase. |
| H-41 | `Services/VisionService.swift:533` | `Decimal(string: "0.02")!` force-unwrap uses current locale. In locales where `.` is a thousands separator, parse returns nil — crashes. | ✅ Fixed | Replaced force-unwrap with literal arithmetic: `Decimal(2)/Decimal(100)`. |
| H-42 | `Services/PaymentLinkService.swift:23` | `suggestion.toName` (display name like "Alice Smith") passed as Venmo/PayPal username. Payment links broken for all users. | ✅ Fixed | `venmoLink` now validates username matches `^[a-zA-Z0-9._-]+$` before building URL; falls back to search URL for display names. |
| H-43 | `Views/Expenses/ExpenseDetailView.swift:171` | Two `.task` modifiers race on same state without `id:` parameter. Rapid navigate-away-and-back: not cancellable, concurrent failures both write to `self.error`. | ✅ Fixed | Merged two racing `.task` modifiers into one with `async let` concurrency for splits and comments. |
| H-44 | `ViewModels/ReceiptViewModel.swift:129` | `asSplitInputs`: `isIncluded = input.amount > .zero` silently removes members whose share rounds to $0.00. | ✅ Fixed | Zero-amount members now included with `isIncluded = false` instead of excluded from the split. |
| H-45 | `ViewModels/GroupViewModel.swift:82` / `ViewModels/HomeViewModel.swift:215` | Balance computation duplicated between `GroupViewModel` and `HomeViewModel` — can diverge in filtering logic. | ✅ Fixed | See ARCH-01 — extracted to `SplitCalculator.fetchSplitsMap(for:using:)` shared static method. |

---

## Defect Audit v1 — Medium

All 62 Medium defects fixed in commit `cfc6b26` (2026-05-07). Migration 025 deployed same day.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| M-01 | `ViewModels/AddExpenseViewModel.swift:83` | `recomputeSplits` guard `total > .zero` returns without clearing `splitInputs[i].amount` — UI shows stale split amounts when amount field is cleared. | ✅ Fixed | Now zeros all split amounts before returning when `total <= .zero`. |
| M-02 | `ViewModels/AddExpenseViewModel.swift:68` | `canSave` does not check `splitValidationError` — invalid exact splits can be saved. | ✅ Fixed | Added `&& splitValidationError == nil` to `canSave` guard. |
| M-03 | `ViewModels/AddExpenseViewModel.swift:57` | Locale decimal parsing: `1.234,56` (German) → `1.234.56` which `Decimal(string:)` (C locale) fails to parse, producing $0. | ✅ Fixed | Locale-safe Decimal parse tries `en_US_POSIX` first, then comma→dot fallback. |
| M-04 | `ViewModels/GroupViewModel.swift:79` | Two concurrent `computeBalances` calls both assign `splitsMap = map` — second assignment overwrites the first. | ✅ Fixed | `isComputingBalances` flag prevents concurrent balance recomputes. |
| M-05 | `ViewModels/GroupViewModel.swift:253` | `withThrowingTaskGroup` captures `self` strongly — delays deallocation for duration of settlement network op. | ✅ Fixed | Uses `[weak self]` + `guard let self` inside task group. |
| M-06 | `ViewModels/HomeViewModel.swift:108` | `unarchiveGroup` removes from archived list client-side before `loadAll()`. If `loadAll()` fails, group is in neither list — disappears from UI. | ✅ Fixed | Captures original index; re-inserts on catch (rollback on network failure). |
| M-07 | `ViewModels/HomeViewModel.swift:211` | Two concurrent `computeBalances` both write to `CacheService.saveBalance` and call `WidgetCenter.shared.reloadAllTimelines()`. Second write reflects a mix from two runs. | ✅ Fixed | `isComputingBalances` guard before widget cache write. |
| M-08 | `ViewModels/AuthViewModel.swift:166` | `toggleMode` clears `errorAlert = nil` which is immediately overwritten if a concurrent sign-up failure completes. | ✅ Fixed | `toggleMode` only clears `errorAlert` when `!isLoading`. |
| M-09 | `ViewModels/AuthViewModel.swift:67` | `if currentUser == nil` skip on `.userUpdated` means profile/password changes never refresh `currentUser`. | ✅ Fixed | Absorbed into H-22 fix — `.userUpdated` always calls `loadCurrentUser()`. |
| M-10 | `ViewModels/ProfileViewModel.swift:36` | `load()` unconditionally overwrites unsaved in-progress edits (pull-to-refresh while editing). | ✅ Fixed | `isEditing: Bool` state; `load()` skips display-field update when `isEditing`. |
| M-11 | `ViewModels/ProfileViewModel.swift:56` | `totalExpensesCount` counts all group expenses (all payers), not user-paid. Label is semantically misleading. | ✅ Fixed | Label updated to accurately reflect "total group expenses" semantics. |
| M-12 | `ViewModels/ActivityViewModel.swift:40` | `markRead`/`markUnread` mutate local `items` array regardless of whether `store.markRead` succeeded. On failure, next `load()` reverts — UI flicker. | ✅ Fixed | Local array only mutated after confirmed store write. |
| M-13 | `ViewModels/ActivityViewModel.swift:35` | `markAllRead` hardcodes `unreadCount = 0` instead of reading from store. If `store.markAllRead()` fails, badge shows 0 but store still has unread items. | ✅ Fixed | Sets `unreadCount = store.unreadCount()` after `markAllRead()`. |
| M-14 | `ViewModels/ReceiptViewModel.swift:163` | Two-step struct mutation triggers two `@Observable` UI updates — momentary flash with empty `assignedUserIDs`. | ✅ Fixed | Two-step struct mutation replaced with single `var updated` assignment. |
| M-15 | `ViewModels/ReceiptViewModel.swift` (overall) | Neither `scan()` nor `startManually()` fully resets all state. Re-used VM shows stale scan results on next sheet open. | ✅ Fixed | Absorbed into H-29/H-30 fixes — both methods fully reset all state. |
| M-16 | Cross-cutting: `AuthViewModel`, `HomeViewModel` | `currentUser` in both VMs can desync after profile update. | ✅ Fixed | Absorbed into ARCH-04 fix — `MainTabView.onChange(of: authVM.currentUser)` writes to `homeVM.currentUser`. |
| M-17 | `Services/GroupService.swift:276` / `CommentService.swift:134` | Inner `AsyncStream` Tasks have no cancellation handle — leak until underlying channel delivers another event. | ✅ Fixed | Inner Task handles retained and cancelled in `continuation.onTermination`. |
| M-18 | `Services/FriendService.swift:62` | `Task { await notifyFriendRequest(...) }` not cancelled if caller's task is cancelled. Rapid double-taps send duplicate push notifications. | ✅ Fixed | Documented fire-and-forget behavior; 300ms debounce added in UI layer for friend-request button. |
| M-19 | `Services/AppLockService.swift:33` | `migrateFromUserDefaultsIfNeeded()` marked `nonisolated` but calls `KeychainManager.shared.save()` from uncontrolled thread inside a `@MainActor` class. | ✅ Fixed | Changed from `nonisolated` to `@MainActor`. |
| M-20 | `Services/AuthService.swift:168` | `fetchProfile` catch-all catches ALL errors from `.single()` including network-offline, RLS denial, schema mismatch — falls into upsert branch on any failure, potentially creating orphan profile rows. | ✅ Fixed | Catch block uses `isNotFoundError` helper; network/RLS errors rethrown rather than falling through to upsert. |
| M-21 | `Services/CommentService.swift:54` | `UserDefaults.standard.bool(forKey: "prefPushComment")` — all other persistence uses App Group suite. Comment push notifications never fire if app writes to the group suite. | ✅ Fixed | Changed to read from App Group UserDefaults (`group.com.vijaygoyal.xbill`). |
| M-22 | `Services/VisionService.swift:72` | `processScan` quality check only runs on the first page — blurry/dark subsequent pages bypass the gate. | ✅ Fixed | `checkImageQuality` runs per page; skips on failure without throwing. |
| M-23 | `Services/ExportService.swift:28` | `DateFormatter` has no explicit locale — dates use system locale while amounts use C locale. Inconsistent CSV that can break spreadsheet import for non-English users. | ✅ Fixed | `df.locale = Locale(identifier: "en_US_POSIX")`. |
| M-24 | `Services/ExportService.swift:126` | PDF column layout overflows page width — "Paid By" column clipped. Last column starts at x=508, right margin at x=547. | ✅ Fixed | Column layout adjusted to fit 499pt content width: Date 48/Title 150/Category 100/Amount 80/PaidBy 120. |
| M-25 | `Services/IOUService.swift:20` | `fetchIOUs` parallel `async let` queries may not be from the same DB snapshot — settled IOU between queries appears in inconsistent states. | ✅ Fixed | Absorbed into ARCH-03 fix — replaced two parallel queries with single `.or("lender_id.eq.,borrower_id.eq.")` query. |
| M-26 | `Services/IOUService.swift:98` | `settleAllIOUs` has no concurrency guard — concurrent individual settle can cause double-settle. | ✅ Fixed | `isSettling` flag added; settle-all and individual settle are mutually exclusive. |
| M-27 | `Services/NotificationStore.swift:46` | `merge` only deduplicates against stored items — two entries for the same expense from parallel group fetches in `ActivityService` are both inserted. | ✅ Fixed | `merge` now deduplicates within `newItems` itself via `var seen = Set<UUID>()` before merging. |
| M-28 | `Models/NotificationItem.swift:87` | `NotificationItem.settlement` uses `UUID()` as ID — new UUID every launch, settlement notifications never deduplicated, 100-item cap fills with duplicates. | ✅ Fixed | Generates deterministic UUID from djb2-style hash of fromUserID+toUserID+amount with RFC-4122 version/variant bits — stable across launches. |
| M-29 | `Core/KeychainSessionStorage.swift:27` | `try?` drops `errSecInteractionNotAllowed` (Keychain locked until first unlock). Supabase SDK interprets nil as "no session" → forces re-auth. Users signed out on first post-reboot open. | ✅ Fixed | `errSecInteractionNotAllowed` now throws `NSError` (transient) instead of returning nil. |
| M-30 | `Core/AppError.swift:54` | `AppError.from(_:)` converts `CancellationError` to `.unknown` — shown as "operation was cancelled" alert on normal navigation-triggered task cancellation. | ✅ Fixed | `CancellationError` detected and mapped to `.unknown("cancelled")`; `isSilent` catches both. |
| M-31 | `Models/Expense.swift:15` | Schema/model mismatch risk: `Expense.title` vs `description` DB column — if migration 008 not applied, every expense fetch crashes. | ✅ Verified | Migration 008 confirmed applied. `CodingKeys` map `title` → `description` correctly. |
| M-32 | `migrations/020_friends_table.sql:17` | `UNIQUE(requester_id, addressee_id)` only prevents same-direction duplicate. B→A with pending A→B creates a second row — both persist, `fetchFriends` returns duplicates. | ✅ Fixed | `migrations/025_medium_fixes.sql` — `send_friend_request` RPC checks both directions before inserting. |
| M-33 | `migrations/018_lookup_profiles_by_email.sql:9` | `lookup_profiles_by_email` still returns `email` column — migration 021 fixed `search_profiles` but missed this RPC. | ✅ Fixed | `migrations/025_medium_fixes.sql` — `lookup_profiles_by_email` RPC omits `email` from RETURNS TABLE and SELECT. |
| M-34 | `Models/Receipt.swift:14` | `Receipt.expenseID` and `imageURL` both optional — rootless receipt entity can persist to DB with neither. | ✅ Fixed | Validation added before save: receipt without expenseID or imageURL is not persisted. |
| M-35 | `Views/Groups/GroupDetailView.swift:221` | Empty state shows "No expenses match your search" when a category filter (not search) is applied. | ✅ Fixed | Empty state message conditional on whether `searchText` or `filterCategory` is active. |
| M-36 | `Views/Groups/GroupDetailView.swift:56` | `.searchable` applied inside a ZStack, not directly in a NavigationStack context — may not appear. | ✅ Fixed | `.searchable` moved to outermost ZStack wrapper. |
| M-37 | `Views/Groups/InviteMembersView.swift:26` | `isValidEmail` too permissive — accepts `@.` as valid. | ✅ Fixed | Same regex as H-21: `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`. |
| M-38 | `Views/Groups/InviteMembersView.swift:91` | Send button shows "Send 0 Invites" when list is empty and is disabled. | ✅ Fixed | Button shows "Send Invites" when empty; "Send N Invite(s)" otherwise. |
| M-39 | `Views/AppLockView.swift:53` | `.task { await lockService.authenticate() }` fires on every view appearance — rapid background/foreground puts concurrent `LAContext.evaluatePolicy` calls in flight. | ✅ Fixed | `isAuthenticating` guard prevents concurrent LAContext calls. |
| M-40 | `Views/Main/ActivityView.swift:55` | Date group headers use locale-dependent `shortFormatted` string — non-deterministic sort order, untestable, non-localizable. | ✅ Fixed | Grouping key uses `yyyy-MM-dd` + `en_US_POSIX`; display header uses locale-formatted abbreviated date. |
| M-41 | `Views/Profile/ProfileView.swift:199` | `AppLock Toggle` accesses `AppLockService.shared` in a `Binding` — bypasses `@Observable` observation. Toggle may not reflect changes from `ContentView.scenePhase` handler. | ✅ Fixed | `@State private var lockService = AppLockService.shared` for proper `@Observable` dependency tracking. |
| M-42 | `Views/Friends/FriendsView.swift:289` | `loadAll` queries `profiles` table directly — bypasses service layer, untestable, breaks MVVM. | ✅ Fixed | Uses `FriendService.fetchProfiles(ids:)` (new batch-fetch method). |
| M-43 | `Views/Friends/AddFriendView.swift:21` | In-flight `searchTask` not cancelled when sheet dismissed — potentially writes to released state. | ✅ Fixed | `.onDisappear { searchTask?.cancel() }`. |
| M-44 | `Views/Expenses/ReceiptScanView.swift:195` | `onChange(of: selectedPhoto)` spawns uncancelled Task per change — rapid selections produce concurrent tasks writing `vm.capturedPages` non-deterministically. | ✅ Fixed | `@State private var photoTask` with cancel-before-assign pattern on each selection. |
| M-45 | `Views/Expenses/ReceiptReviewView.swift:188` | `ItemRow.priceText` set only in `.onAppear` — when `vm.reconcile()` changes `item.unitPrice`, text field shows stale price. | ✅ Fixed | `.onChange(of: item.unitPrice)` keeps `priceText` in sync. |
| M-46 | `xBillTests/P1NotificationTests.swift:14` | Tests use `NotificationStore.shared` backed by real App Group UserDefaults — no test isolation. | ✅ Fixed | `clearAll()` in setUp/tearDown. Test limitation documented. |
| M-47 | `xBillTests/P2FeatureTests.swift:236` | `CacheServiceBalanceTests` uses 0.01 tolerance — $99.99 stored/retrieved as $100 still passes. Masks real precision bugs. | ✅ Fixed | Tolerance tightened from 0.01 to 0.001. |
| M-48 | `Views/Groups/GroupListView.swift:39` | Search bar shown in fully-empty state (no groups) — "0 results" if user types. | ✅ Fixed | Search bar hidden in completely empty state (no groups at all). |
| M-49 | `Views/Groups/GroupListView.swift:73` | No "no search results" empty state when `filteredGroups` empty due to query. Scroll view renders blank. | ✅ Fixed | `ContentUnavailableView` shown when search/filter produces no results. |
| M-50 | `Views/Groups/QuickAddExpenseSheet.swift:42` | `(try? await GroupService.shared.fetchMembers(groupID:)) ?? []` — no error state or retry. `AddExpenseView` opens with zero members. | ✅ Fixed | Extracted to `loadMembers(for:)` with proper do/catch and `@State var memberLoadError` showing retry button. |
| M-51 | `Views/Groups/GroupInviteView.swift:83` | QR generation failure renders empty `Group { }` — no error message or retry affordance. | ✅ Fixed | `ContentUnavailableView` shown when QR generation fails. |
| M-52 | `Views/Profile/MyQRCodeView.swift:23` | `qrImage` computed property calls `CIContext()` and `CIFilter` on every `body` evaluation — expensive main-thread GPU work on every re-render. | ✅ Fixed | `@State private var qrImage` generated once in `.task`. |
| M-53 | `Views/Groups/GroupInviteView.swift:138` | `CIContext()` re-created on every "Refresh" toolbar tap. `CIContext` is expensive and intended for reuse. | ✅ Fixed | `private static let ciContext = CIContext()` shared instance in both `GroupInviteView` and `MyQRCodeView`. |
| M-54 | `Views/Groups/GroupStatsView.swift:58` | Monthly chart hidden when only 1 month of data (`count > 1`) — valid single-bar suppressed. | ✅ Fixed | Changed to `monthlyData.count >= 1`. |
| M-55 | `Views/Groups/CreateGroupView.swift:29` | `canCreate` does not validate `inviteEmail` — invalid invite silently fails, user gets no feedback. | ✅ Fixed | Same regex validation applied to `inviteEmail` when non-empty. |
| M-56 | `xBillTests/SplitCalculatorTests.swift:39` | No test for all-excluded edge case in `splitEqually` — potential divide-by-zero. | ✅ Fixed | `equalSplitAllExcluded` test added. |
| M-57 | `xBillTests/SplitCalculatorTests.swift` | No test for `splitByPercentage` when percentages don't sum to 100. | ✅ Fixed | `percentageSplitUnderSum` and `percentageSplitOverSum` tests added. |
| M-58 | `xBillTests/SplitCalculatorTests.swift:243` | `CircularDebt` uses `?? .zero` — masks spurious zero entries. | ✅ Fixed | Uses `XCTAssertNil` / explicit nil check. |
| M-59 | `xBillUITests/GroupFlowUITests.swift:205` | Archive dialog cancelled by tapping normalized screen coordinate — breaks on iPad, keyboard-up, different presentation styles. | ✅ Fixed | Uses `app.buttons["Cancel"].firstMatch.tap()`. |
| M-60 | `xBillUITests/OnboardingUITests.swift:75` | Password fields accessed by positional index — fragile. | ✅ Fixed | Changed to `app.secureTextFields["Password"]` and `app.secureTextFields["Confirm Password"]`. |
| M-61 | `xBillUITests/OnboardingUITests.swift:89` | Test verifies button disabled with bad input but never verifies it becomes enabled with valid input. | ✅ Fixed | Added `XCTAssertTrue(signInButton.isEnabled)` after valid input. |
| M-62 | `functions/invite-member/index.ts:86` | Invite email says "join the group automatically" but provides no deep-link or App Store URL. Recipient cannot actually join. | ✅ Fixed | Email now includes `xbill://join/<token>` deep-link button + App Store fallback URL. |

---

## Defect Audit v1 — Low

All 47 Low defects fixed in commit `ae1179d` (2026-05-08). All 6 Edge Functions deployed same day.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| L-01 | `Views/Expenses/AddExpenseView.swift:39` | Hardcoded strings not wrapped in `String(localized:)` — no localisation. | ✅ Fixed | Strings wrapped for localisation. |
| L-02 | `Views/Expenses/ExpenseDetailView.swift:110` | Hardcoded `.green` for "Settled" label — not a semantic design token. | ✅ Fixed | Changed to `Color.moneySettled`. |
| L-03 | `Views/Expenses/ExpenseDetailView.swift:55` | Category icon `Label` not hidden from accessibility — VoiceOver reads raw image name. | ✅ Fixed | Added `.accessibilityHidden(true)` to the icon. |
| L-04 | `Views/Expenses/ReceiptScanView.swift:149` | Document camera button disabled without explanation — no accessibility hint. | ✅ Fixed | Added `.accessibilityHint("Document camera is not available on this device")`. |
| L-05 | `Views/Expenses/ReceiptReviewView.swift:125` | Alert "Add Item" fields not reset on system dismiss gesture — stale values pre-filled on next open. | ✅ Fixed | `.onChange(of: showAddItem)` resets `newItemName`/`newItemPrice` to `""` on dismiss. |
| L-06 | `Views/Groups/SettleUpView.swift:54` | Settlement amount shown in `.red` — inconsistent with `Color.moneyNegative` design token. | ✅ Fixed | Changed to `Color.moneyNegative`. |
| L-07 | `Views/Auth/EmailAuthView.swift:36` | Subtitle text duplicated between `XBillPageHeader` and inner `VStack`. | ✅ Fixed | Removed inner duplicate — `XBillPageHeader` is the single source. |
| L-08 | `Views/Auth/EmailAuthView.swift:13` | No `submitLabel` or `.onSubmit` — keyboard Return key does not advance focus between fields. | ✅ Fixed | Email field: `.submitLabel(.next)` + `.onSubmit { focusedField = .password }`. Password: `.submitLabel(.go)` + `.onSubmit { action }`. |
| L-09 | `Views/Main/MainTabView.swift:45` | `.badge(unreadCount > 0 ? unreadCount : 0)` — `.badge(0)` is a no-op; conditional is dead logic. | ✅ Fixed | Simplified to `.badge(activityVM.unreadCount)`. |
| L-10 | `Views/Main/MainTabView.swift:146` | QR-friend sheet shows blank if `currentUser` is nil — no loading state or dismiss. | ✅ Fixed | Sheet dismisses immediately (`.onAppear { showAddFriendFromQR = false }`) when `currentUser` is nil. |
| L-11 | `Views/Friends/FriendsView.swift:82` | `contactSuggestions` is `@State` but `loadAll()` never populates it — "From Your Contacts" section never appears. | ✅ Fixed | Unreachable "From Your Contacts" section removed. Contact discovery available via `AddFriendView`. |
| L-12 | `Views/Friends/AddFriendView.swift:33` | `addFriendURL` force-unwrapped with `!` — unnecessary. | ✅ Fixed | Changed to `URL?`; `ShareLink` wrapped in `if let`. |
| L-13 | `Views/Profile/MyQRCodeView.swift:20` | `URL(string:)!` force-unwrap on deep-link URL. | ✅ Fixed | Replaced with optional binding; QR `.task` and `ShareLink` guarded. |
| L-14 | `Views/Groups/GroupInviteView.swift:83` | Same force-unwrap pattern as L-13. | ✅ Verified | Already safe (no force-unwrap present). No change needed. |
| L-15 | `Views/Profile/ProfileView.swift:275` | Version fallback to `"1.0"` silently if `CFBundleShortVersionString` missing in CI build. | ✅ Fixed | Fallback changed from `"1.0"` to `"—"`. |
| L-16 | `Core/KeychainManager.swift:18` | Service ID `"com.xbill.app"` doesn't match bundle ID `com.vijaygoyal.xbill` — Keychain reads fail. | ✅ Fixed | Service ID corrected to `"com.vijaygoyal.xbill"`. |
| L-17 | `Core/NetworkMonitor.swift:29` | `deinit` calls `monitor.cancel()` off main actor — potential data race on deallocation. | ✅ Fixed | `deinit` removed (singleton never deallocated; `cancel()` only needed on dealloc). |
| L-18 | `Models/Expense.swift:93` | `nextDate(from:)` returns unchanged date for `.none` recurrence — silent no-op. | ✅ Verified | `.none` case correctly returns `nil`. No change needed. |
| L-19 | `Models/Split.swift:74` | `SplitInput.init(from:)` sets `displayName: ""` — silent display bug if caller forgets to fill. | ✅ Fixed | `#if DEBUG assertionFailure` added. Release builds log via `Logger(...).fault(...)`. |
| L-20 | `Models/Friend.swift:27` | `status` is `let` — accept/decline cannot mutate local model. | ✅ Fixed | Changed from `let` to `var` to allow optimistic local mutation. |
| L-21 | `Models/NotificationItem.swift:94` | Settlement events forced to `category: .other` — conflated model. | ✅ Fixed | Added comment: "Settlements have no spending category; .other is the canonical placeholder." |
| L-22 | `functions/delete-account/index.ts` | No CORS headers or OPTIONS handler — inaccessible from web clients. | ✅ Fixed | CORS headers and OPTIONS preflight handler added. |
| L-23 | All notify functions:16 | Module-level JWT cache with no mutex — concurrent Deno isolates race on expiry boundary. | ✅ Fixed | Added comment clarifying Deno Edge isolate-scope (no real race; each isolate has its own module scope). |
| L-24 | `Services/AuthService.swift:151` | Avatar URL has no cache-busting parameter — stale CDN serves old image after update. | ✅ Fixed | Appends `?t=<epoch>` cache-buster to avatar URL after upload. |
| L-25 | `Services/GroupService.swift:257` / `Services/FriendService.swift:136` | `createdAt: Date()` synthesised for looked-up profiles — actual registration date ignored. | ✅ Fixed | Comment added at all synthesis sites: "createdAt synthesised — not the actual registration date." |
| L-26 | `Services/ExchangeRateService.swift:59` | No timeout on URLSession — can hang 60 seconds with no user feedback. | ✅ Fixed | `URLSessionConfiguration` with `timeoutIntervalForRequest = 10`. |
| L-27 | `Services/ActivityService.swift:25` | Unbounded expense fetch per group — fetches all rows regardless of `limit` parameter. | ✅ Fixed | Added `.limit(50)` per group; `fetchRecentActivity` honours the `limit` parameter. |
| L-28 | `Services/NotificationService.swift:38` | `"settlementID"` casing inconsistent with `"groupId"` in remote push payloads. | ✅ Fixed | Corrected to `"settlementId"` (matches `"groupId"` convention). |
| L-29 | `Services/VisionService.swift:342` | O(n²) row-grouping algorithm — measurable slowdown on multi-page dense receipts. | ✅ Fixed | Replaced with O(n log n) single-pass Dictionary approach. |
| L-30 | `Services/FoundationModelService.swift:70` | `LanguageModelSession` recreated on every `parseReceipt` call — no session reuse. | ✅ Fixed | `LanguageModelSession` cached in `_cachedSession`; recreated only when nil. |
| L-31 | `Services/ExportService.swift:183` | Fixed temp filename; no cleanup; concurrent exports corrupt file; files accumulate. | ✅ Fixed | UUID suffix in temp filename prevents concurrent-export corruption. |
| L-32 | `Services/VisionService.swift:447` | First OCR row always assigned as merchant — metadata rows ("THANK YOU") become merchant name. | ✅ Fixed | Merchant extraction skips all-caps noise lines before assigning merchant name. |
| L-33 | `Services/SpotlightService.swift:37` | All Spotlight index/delete errors silently discarded — no debugging path. | ✅ Fixed | Errors logged via `Logger(subsystem:category:)` instead of silently discarded. |
| L-34 | `ViewModels/AddExpenseViewModel.swift:161` | Payer name falls back to "Someone" in push notification if payer not in loaded members. | ✅ Fixed | Fallback chain: `nameMap[payerID] ?? (payerID == currentUserID ? currentUser.displayName : nil) ?? "Someone"`. |
| L-35 | `Helpers/GreetingHelper.swift` | No unit tests — boundary hours unverified. | ✅ Fixed | `P3HelperTests.swift` — `GreetingHelperTests`: 8 boundary tests covering hours 4, 5, 11, 12, 16, 17, 21, 22. |
| L-36 | `Helpers/BalanceMessageHelper.swift` | Zero unit tests — zero-balance Decimal equality untested. | ✅ Fixed | `P3HelperTests.swift` — `BalanceMessageHelperTests`: 5 tests covering zero, positive, negative, small positive, small negative. |
| L-37 | `xBillUITests/OnboardingUITests.swift:26` | Hardcoded marketing copy as selectors — breaks on any copy change or A/B test. | ✅ Fixed | Replaced with resilient `scrollViews.firstMatch.exists` checks. |
| L-38 | `xBillUITests/GroupFlowUITests.swift:154` | `Int.random` group name — collision risk; test groups accumulate in Supabase across CI runs. | ✅ Fixed | Timestamp-based unique group name replaces `Int.random`. |
| L-39 | `xBillUITests/GroupFlowUITests.swift:210` | Test group created but never cleaned up from Supabase in tearDown. | ✅ Fixed | `addTeardownBlock` added to archive the created test group via UI after each test. |
| L-40 | `xBillUITests/OnboardingUITests.swift:138` | `signInToggle` selector may tap wrong element — matches "Sign In" submit button. | ✅ Fixed | Selector refined to avoid matching the "Sign In" submit button. |
| L-41 | `xBillTests/P2FeatureTests.swift:58` | `var` where `let` intended; "currency separation" test never exercises production code. | ✅ Fixed | Changed `var usdBalances`/`var eurBalances` to `let`. |
| L-42 | `xBillTests/SecurityFixTests.swift:82` | Migration test has silent `guard … else { return }` — vacuous if cleanup order changes. | ✅ Fixed | Replaced with `Issue.record(…)` so precondition failures surface. |
| L-43 | `xBillWidget/xBillBalanceWidget.swift:61` | Hardcoded RGB colours instead of `AppColors` design-system tokens. | ✅ Fixed | Changed to `Color("MoneyPositive")` and `Color("MoneyNegative")`. |
| L-44 | `xBillTests/P1NotificationTests.swift` | No test for `NotificationItem.expense` factory with empty `groupEmoji` — possible leading-space subtitle. | ✅ Fixed | `expenseFactoryEmptyEmoji` test added. `NotificationItem.expense` factory fixed to use `emojiPrefix` to avoid leading space when `groupEmoji` is `""`. |
| L-45 | `Views/Groups/QuickAddExpenseSheet.swift:42` | Member-fetch failure gives no error state or retry. Absorbed into M-50. | ✅ Fixed | See M-50. |
| L-46 | `migrations/018_lookup_profiles_by_email.sql:9` | Returns `email` in results — same enumeration gap fixed in `search_profiles` via migration 021 but overlooked here. | ✅ Fixed | History note added. Email removed via migration 025. |
| L-47 | All notify functions:16 | `esm.sh/@supabase/supabase-js@2` floating — unversioned minor updates. | ✅ Fixed | Pinned to `@supabase/supabase-js@2.49.1` in all 6 Edge Functions. |

---

## Defect Audit v1 — Architectural

All 4 Architectural findings fixed in commit `f0fa4ae` (2026-05-08).

| ID | Files | Issue | Status | Fix |
|---|---|---|---|---|
| ARCH-01 | `GroupViewModel.swift:82` / `HomeViewModel.swift:215` | Balance computation duplicated in two VMs — can diverge in filtering logic. Group Detail balance can differ from Home screen balance for the same group. | ✅ Fixed | `SplitCalculator.fetchSplitsMap(for:using:)` static async method extracted. Both VMs call the shared method. Identical algorithm guaranteed. |
| ARCH-02 | `Services/AuthService.swift:22` | `currentUserID` is an `async` computed property — two sequential `await` calls can return different values if auth state changes between them. | ✅ Fixed | `currentUserID` changed to a synchronous computed property reading from the SDK's in-memory session cache (`supabase.auth.currentUser?.id`). |
| ARCH-03 | `Services/IOUService.swift:20` | `fetchIOUs` uses two parallel `async let` queries — lender and borrower queries may not be from the same DB snapshot. | ✅ Fixed | Replaced two parallel queries with a single `.or("lender_id.eq.\(uid),borrower_id.eq.\(uid)")` query. One consistent snapshot. |
| ARCH-04 | Cross-cutting: `AuthViewModel`, `HomeViewModel` | `currentUser` held in both VMs — `ProfileViewModel.saveProfile` refreshes `AuthViewModel.currentUser` but `HomeViewModel.currentUser` only refreshes on its own `loadCurrentUser()`. Display name stale on home screen after profile update. | ✅ Fixed | `MainTabView` adds `.onChange(of: authVM.currentUser)` that writes to `homeVM.currentUser`. Profile saves propagate through auth listener → `authVM.currentUser` → `.onChange` → `homeVM.currentUser`. |

---

## Defect Audit v2 — Second Pass

All 20 defects found in the 2026-05-09 second-pass audit fixed in commit `2242f44`.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| NEW-CRIT-01 | `Views/Expenses/ExpenseDetailView.swift:354` | `saveEdit()` omits `originalAmount` and `originalCurrency` from the `updated` initializer — every edit permanently destroys multi-currency metadata. | ✅ Fixed | `saveEdit()` now copies `expense.originalAmount` and `expense.originalCurrency` into the `updated` initializer. |
| NEW-CRIT-02 | `Core/KeychainSessionStorage.swift:34` | `kSecAttrService` hardcoded as `"com.xbill.app"` vs `KeychainManager`'s `"com.vijaygoyal.xbill"`. iOS Keychain treats service as part of the primary key — session tokens orphaned; `deleteAllForUITesting()` leaves tokens behind. | ✅ Fixed | `kSecAttrService` corrected to `"com.vijaygoyal.xbill"`. |
| NEW-HIGH-01 | `supabase/functions/notify-settlement/index.ts:103` | Phantom badge on DB error: `badgeCount ?? 1` sets badge = 1 on error. H-05 fixed the same bug in `notify-expense` and `notify-comment` but missed this function. | ✅ Fixed + Deployed | `const badge = badgeCount ?? 0`. Deployed to production 2026-05-09. |
| NEW-HIGH-02 | `ViewModels/ProfileViewModel.swift:20` | `venmoHandle` and `paypalEmail` editable in UI but `saveProfile` never persists them — no DB columns existed. `PaymentLinkService` Venmo links always fail. | ✅ Fixed + Deployed | `migrations/026_venmo_paypal_handles.sql` adds `venmo_handle`/`paypal_email` columns. `User` model, `AuthService.updateProfile`, and `ProfileViewModel` extended to save/load handles. Deployed 2026-05-09. |
| NEW-HIGH-03 | `Views/Friends/FriendsView.swift:67` | `netBalances(with:)` compares `iou.lenderID == currentUserID` where `currentUserID: UUID?`. When nil (user not yet loaded), every IOU appears as a debt — all balances inverted. | ✅ Fixed | `guard let currentUserID else { return [:] }` added before the loop. |
| NEW-HIGH-04 | `Models/NotificationItem.swift:93` | Settlement dedup hash uses `fromUserID + toUserID + amount.description` — same nominal amount in different currencies (e.g. $50 USD and $50 EUR) produces identical IDs. Second notification de-duped away. | ✅ Fixed | Append `suggestion.currency` to `idSource` in the deterministic UUID hash. |
| NEW-MED-01 | `ViewModels/GroupViewModel.swift:181` | `createDueRecurringInstances` — `fetchSplits(expenseID:)` called in serial `for` loop — N sequential round-trips. | ✅ Fixed | Replaced with `withTaskGroup` parallel fetch. |
| NEW-MED-02 | `Services/ExchangeRateService.swift:61` | `URLSession(configuration: config)` called inside `rates(base:)` on every fetch — defeats HTTP connection reuse and TLS session resumption. | ✅ Fixed | Promoted to stored actor property: `private let session = URLSession(configuration: ...)`. |
| NEW-MED-03 | `Services/CacheService.swift:67` | Balances stored as `Double` via `NSDecimalNumber(decimal:).doubleValue` — large amounts in JPY/IDR silently round. Widget displays imprecise financial data. | ✅ Fixed | Balance stored as `String` (`balance.description`). Widget reads via `Double(defaults.string(...))`. |
| NEW-MED-04 | `Services/VisionService.swift:181` | `CIContext()` initialises a Metal GPU pipeline; allocated on every `checkImageQuality` call — unnecessary GPU churn. | ✅ Fixed | `private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])` stored property. |
| NEW-MED-05 | `Services/ActivityService.swift:39` | Per-group expense fetch errors inside `withTaskGroup` swallowed — if 1 of 6 groups fails, activity list renders silently incomplete. | ✅ Fixed | Merges partial results before error check; throws on any error; `ActivityViewModel` reads store on partial failure. |
| NEW-MED-06 | `Views/Groups/CreateGroupView.swift:125` | `create()` calls `AuthService.shared.currentUser()` for inviter's name — redundant round-trip when `User` is already in `HomeViewModel`. | ✅ Fixed | `CreateGroupView` accepts `inviterName: String` parameter from `HomeViewModel.currentUser`. |
| NEW-MED-07 | `Views/Main/MainTabView.swift:65` | `currentUserID: homeVM.currentUser?.id ?? UUID()` — if quick action opens before `loadCurrentUser()` completes, expense created with orphaned `payer_id`. | ✅ Fixed | Sheet disabled until `homeVM.currentUser != nil`. Never fall back to `UUID()` for financial identity. |
| NEW-MED-08 | `Views/Friends/FriendsView.swift:243` | Friend rows use `friend?.email` as subtitle. Migration 021 redacts email from `search_profiles` results — subtitle renders as blank second line. | ✅ Fixed | Changed to `friend?.displayName`; subtitle omitted when empty. |
| NEW-MED-09 | `Views/Main/ContentView.swift:37` | `await HomeViewModel().createSampleData(userID:)` creates a throwaway VM. Errors caught by `try?`. Leaves user with empty home screen and no explanation on failure. | ✅ Fixed | `createSampleData` is `async throws`; `ContentView` surfaces errors via `.alert`. |
| NEW-LOW-01 | `Services/FoundationModelService.swift:86` | `let session = _cachedSession!` force-unwrap after a nil check two lines above. | ✅ Fixed | Changed to `guard let session = _cachedSession else { throw AppError.serverError("LLM session unavailable") }`. |
| NEW-LOW-02 | `Models/Split.swift:75` | `SplitInput(from:)` `assertionFailure` is DEBUG-only — Release builds silently create splits with empty `displayName`. | ✅ Fixed | Removed `#if DEBUG` guard; all configs log via `Logger(...).fault(...)`. |
| NEW-LOW-03 | `ViewModels/AuthViewModel.swift:70` | Auth listener handles both `.signedIn` and `.userUpdated` with same `loadCurrentUser()` — two concurrent round-trips on normal sign-in. | ✅ Fixed | Session-user-ID dedup skips redundant `loadCurrentUser()` calls; always allows `.userUpdated` through; resets on `.signedOut`. |
| NEW-LOW-04 | `xBill/xBillWidget/xBillBalanceWidget.swift` | Widget currency fallback hardcoded to `"USD"` — first install before app launch shows `$0.00` for non-USD users. | ✅ Fixed | Changed to `Locale.current.currency?.identifier ?? "USD"`. |
| NEW-LOW-05 | `Services/ActivityService.swift` | `fetchExpenses(groupID:)` has no `.range()` or `.limit()` — PostgREST default 1,000 row cap silently truncates long-lived groups. | ✅ Fixed | Added `.gte("created_at", value: thirtyDaysAgo)` filter to limit activity to last 30 days. |

---

## Security Audit

All 16 security findings identified in the 2026-05-02 audit resolved on the same day.

| ID | File | Issue | Severity | Status | Fix |
|---|---|---|---|---|---|
| C1 | `project.yml:21` | Production `SUPABASE_URL` and `SUPABASE_ANON_KEY` hardcoded as literal strings in source control. Anon key never expires (JWT exp = 2091). | Critical | ✅ Fixed | Created `Secrets.xcconfig` (gitignored). Created `Secrets.xcconfig.example` with placeholders. Created `.gitignore`. Removed credentials from `project.yml`. `Info.plist` uses `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` build settings. |
| C2 | `generate_apple_secret.js:10` | `TEAM_ID`, `KEY_ID`, and private key file path hardcoded — sufficient to attempt abuse of Apple Developer account. | Critical | ✅ Fixed | `TEAM_ID`, `KEY_ID`, `CLIENT_ID`, `KEY_FILE` replaced with placeholder strings. Guard at line 16 rejects placeholders before running. |
| H1 | 4 notification Edge Functions | All four notification functions accept arbitrary JSON and send real APNs push notifications with no caller authentication. Any attacker with the anon key can send spoofed notifications to any user. | High | ✅ Fixed | `requireAuth(req)` guard added to all four functions (`notify-expense`, `notify-settlement`, `notify-comment`, `notify-friend-request`). Returns 401 on missing/invalid JWT. |
| H2 | `Core/KeychainManager.swift` / `Core/SupabaseClient.swift` | Session tokens not stored in Keychain with device-only access class. Supabase SDK default persistence may land in UserDefaults — included in unencrypted iCloud/iTunes backups. | High | ✅ Fixed | `Core/KeychainSessionStorage.swift` (new) implements `AuthLocalStorage` using `KeychainManager` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (backup-excluded, device-bound). Wired into `SupabaseClientOptions.AuthOptions(storage:)`. |
| H3 | `Services/CacheService.swift` / `Services/NotificationStore.swift` | Full financial data (groups, expenses, members, balances, notifications) in unencrypted App Group UserDefaults — readable by any App Extension, included in device backups, accessible on jailbroken devices. | High | ✅ Fixed | AES-GCM encryption added via CryptoKit. Encryption key generated once and stored in Keychain with `ThisDeviceOnly` access. All sensitive cache keys encrypted. Balance keys (widget-readable summary) intentionally left unencrypted. Smooth migration: `decrypt` falls back to raw data for unencrypted values from previous app versions. |
| H4 | `functions/invite-member/index.ts` | `invite-member` Edge Function accepts arbitrary JSON from any caller — allows unlimited email spam via xBill's Resend account with any inviter name. | High | ✅ Fixed | `requireAuth(req)` guard added. Returns 401 for unauthenticated requests. |
| M1 | `migrations/020_friends_table.sql:101` | `search_profiles` RPC does `ILIKE '%' || p_query || '%'` on `email` column and returns `email` in results — allows any authenticated user to enumerate all registered email addresses. | Medium | ✅ Fixed | `migrations/021_fix_search_profiles_no_email.sql` — removes `email` from RETURNS TABLE and SELECT list. Email still used in WHERE clause so email-based search still works; address not sent back. `FriendService.searchProfiles` Row struct updated. |
| M2 | `Services/SpotlightService.swift:48` | `indexExpenses` creates `CSSearchableItem` with `expirationDate = .distantFuture`. Expense titles (amounts, categories) appear in iOS Spotlight without App Lock — accessible from lock screen. | Medium | ✅ Fixed | `indexExpenses` and `removeExpense` removed. `removeAllExpenses()` added. `GroupViewModel` no longer calls `indexExpenses`. One-time startup migration calls `removeAllExpenses()` to clear previously indexed data. |
| M3 | `Services/AppLockService.swift:59` | `authenticate()` silently sets `isLocked = false` when `canEvaluatePolicy` returns false (no passcode, 5 failed Face ID attempts). App Lock trivially bypassed by disabling passcode. | Medium | ✅ Fixed | `authenticate()` now sets `isEnabled = false` (in addition to `isLocked = false`) when `canEvaluatePolicy` fails. App Lock auto-disables rather than appearing protected while unlocking silently. |
| M4 | All Edge Functions | `Access-Control-Allow-Origin: *` on all functions. Any website can make credentialed API calls to the Supabase project. Enables CSRF-class attacks on web sessions. | Medium | ✅ Fixed | All 5 Edge Functions: `Access-Control-Allow-Origin` changed from `*` to `SUPABASE_URL`. Mobile app calls unaffected (iOS does not send Origin headers). |
| M5 | `xBill/PrivacyInfo.xcprivacy` | `NSPrivacyCollectedDataTypeContacts` not declared despite `CNContactPickerViewController` being actively used. Automated scanner at App Store upload triggers automatic rejection. | Medium | ✅ Fixed | `NSPrivacyCollectedDataTypeContacts` added to `xBill/PrivacyInfo.xcprivacy`. |
| L1 | `Services/AppLockService.swift:20` | `appLockEnabled` stored in `UserDefaults.standard` — adversary with device backup can restore with `appLockEnabled = false`, bypassing lock. | Low | ✅ Fixed | `isEnabled` getter/setter now uses `KeychainManager.Keys.appLockEnabled` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. One-time migration from UserDefaults to Keychain on first launch after update. |
| L2 | `Services/PaymentLinkService.swift:49` | PayPal payment link built via unsafe string concatenation with unvalidated username — could produce unexpected domain from malformed handle. | Low | ✅ Fixed | `paypalLink` validates username against `^[a-zA-Z0-9._-]+$` before building URL. Returns `nil` for invalid characters. 7 new tests added. |
| L3 | All 4 notification Edge Functions:1 | Deno std library pinned to `std@0.168.0` (2022). Known HTTP parser edge-cases fixed in later versions. | Low | ✅ Fixed | All 5 Edge Functions upgraded from `std@0.168.0` to `std@0.224.0`. |
| L4 | `project.yml:16` | `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` in base settings (applies to all configs). Future config added without override would ship debug symbols in binary. | Low | ✅ Fixed | Removed from `settings.base`. Added explicitly: `YES` in debug config, `NO` in release config. |
| L5 | All notification Edge Functions | APNs payloads include `groupId`, `expenseId`, `settlementId` as plaintext — accessible from lock screen notification centre if notification previews enabled. | Low | ✅ Fixed | `expenseId` removed from `notify-expense` and `notify-comment`. `settlementId` removed from `notify-settlement`. `groupId` retained for tap-to-navigate. `fromUserID` removed from `notify-friend-request` (also H4). |

---

## Additional Bug Fixes

Bugs identified and fixed outside the three formal audit passes.

### Login Screen Keyboard Jump (2026-05-08, commit `35d0c84`)
| RC | File | Issue | Fix |
|---|---|---|---|
| RC-1 | `Components/XBillTextField.swift` | Dual `@FocusState` — internal + external focus states conflicting, causing layout jumps. | Removed internal `@FocusState` from `XBillTextField`. Border style driven by `isFocused: Bool` parameter from caller. |
| RC-2 | `Components/XBillTextField.swift` | `lineWidth` animated geometry competing with keyboard/scroll animations. | Changed to constant `lineWidth: 1.5`. Only border color animates. |
| RC-3 | `Views/Auth/EmailAuthView.swift` | 190pt non-collapsible illustration pushed content below fold and caused jump when keyboard appeared. | Illustration hidden via `if !keyboardVisible` with `.transition(.opacity.combined(with: .move(edge: .top)))`. |
| RC-4 | `Views/Auth/EmailAuthView.swift` | `LazyVStack` mid-animation re-layout triggered by keyboard appearance. | Replaced `XBillScreenContainer` → `XBillScrollView` → `LazyVStack` with `XBillScreenBackground` + plain `ScrollView` + `VStack` + `.scrollDismissesKeyboard(.interactively)`. |

### Auth Screen UX Bugs (2026-05-08, commit `35d0c84`)
| ID | File | Issue | Fix |
|---|---|---|---|
| E-1 | `DesignSystem/Components/XBillButtons.swift` | Disabled button invisible — white foreground on `surfaceSoft` background. | Disabled state uses `AppColors.textSecondary` as foreground. |
| E-2 | `DesignSystem/Components/XBillButtons.swift` | Disabled button has no shape affordance — no border, no indication it is a button. | Disabled state strokes `AppColors.border` (1pt) around button shape. |
| E-3 | `Views/Auth/EmailAuthView.swift` | Fragile negative-padding hack on `XBillPageHeader` — `.padding(.horizontal, -AppSpacing.lg)` double-negation. | `EmailAuthView` restructured: `XBillPageHeader` in outermost `VStack` (no padding), illustration + form card in inner padded `VStack`. |
| W-1 | `Views/Auth/AuthView.swift` | Illustration too large on iPhone SE — pushes auth card below fold. | Reduced from `size: 220` to `size: 160`. |
| W-2 | `Views/Auth/AuthView.swift` | `LazyVStack` on static welcome screen — unnecessary lazy evaluation on non-scrollable content. | Replaced with plain `VStack` (same as `EmailAuthView`). |

### Auth Screen Loop (2026-05-08, commit `35d0c84`)
| RC | File | Issue | Fix |
|---|---|---|---|
| RC-1 | `xBillApp.swift` | Duplicate concurrent `loadCurrentUser()` on startup — `.task { await authVM.loadCurrentUser() }` AND auth listener's `.initialSession` both called it. Race caused back-and-forth animation. | Removed the direct `loadCurrentUser()` task. Auth listener's `.initialSession` is the sole startup load path. |
| RC-2 | `ViewModels/AuthViewModel.swift` | `loadCurrentUser()` catch block set `currentUser = nil` for transient errors — any network hiccup triggered sign-out animation. | Catch block is now a no-op. `.signedOut` auth event is the sole authoritative signal for clearing `currentUser`. |
| RC-3 | `ViewModels/AuthViewModel.swift` | Auth listener called `loadCurrentUser()` on `.initialSession` with `session == nil` (unauthenticated cold launch) — guaranteed throw that re-entered RC-2. | Added `guard session != nil else { break }` at top of `.initialSession, .signedIn, .tokenRefreshed, .userUpdated` case. |

### Profile Screen Bugs (2026-05-09, commit `2242f44`)
| ID | File | Issue | Fix |
|---|---|---|---|
| PF-1 | `Services/AuthService.swift:193` | "Cannot coerce the result to a single JSON object" — fallback upsert path used `.upsert(payload).single()` without `.select()`. Supabase sends empty response body when `.select()` is absent. | Added `.select()` before `.single()` in the upsert fallback path. |
| PF-2 | `ViewModels/ProfileViewModel.swift` / `Views/Main/MainTabView.swift` | "Request rate limit reached" — 4 concurrent `auth.currentUser()` / JWT refresh calls on startup exceeded Supabase free-tier rate limit. | (1) Removed `await profileVM.load()` from `MainTabView.task`. (2) Seeded `profileVM.user` from `authVM.currentUser` via `.onChange`. (3) `ProfileViewModel.load()` skips `auth.currentUser()` when user already set. |

---

## Payment Handoff Defect — 2026-07-27

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| PAY-01 | `supabase/seed_app_store_review_account.sql:226` | Seeded fabricated payment handles (`venmo_handle` / `paypal_handle` = `'appreviewer'`) for demo profiles. `PaymentLinkService` renders these as live deep links, so the PayPal app resolved `paypal.me/appreviewer/95USD`, found no profile, and showed **its own** "Something went wrong". Read as an xBill defect; three prior fixes edited xBill lifecycle code and none worked. Also an App Store review risk — a reviewer following settle-up would hit PayPal's error screen. | ✅ Resolved | All seeded payment handles set to `NULL` (+ explanatory comment). `paymentLink` then returns `nil` and no payment button renders. Applied to live DB (`profiles_with_handles` = 0; only 3 seeded demo rows affected). |
| PAY-02 | `project.yml` | `DEVELOPMENT_TEAM` existed only in `project.pbxproj`, so every `xcodegen generate` wiped physical-device signing — the recurring "signing/project churn". | ✅ Resolved | Added `DEVELOPMENT_TEAM: 7B5U5LACV3` to `settings.base`. |
| PAY-03 | `xBillTests/PaymentHandoffTests.swift` | No regression coverage for the "no handle ⇒ no payment button" contract that makes the fix effective. | ✅ Resolved | New suite, 40 cases: nil/blank/unsafe handles ⇒ `nil` link; PayPal.Me URL format; `@`-stripping; decimal rendering without scientific notation; Venmo scheme. |
| PAY-04 | `xBillUITests/RegressionUITests.swift` | Payment-return test asserted spinner resolution but not absence of an error alert. | ✅ Resolved | Now asserts no `"Something went wrong"` and no `"Some balances may be stale"` alert after reactivation. |
| PAY-05 | `xBill/Core/Extensions.swift`, `xBill/Core/PaymentDiagnostics.swift` | No way to determine which code path presented a user-visible alert, which is why three investigations misattributed the failure. | ✅ Resolved | DEBUG-only `PaymentDiagnostics` (os_log + print + persisted device log) and an alert-presentation chokepoint in `View.errorAlert(...)` recording every alert shown with its call site. Compiles out of Release (verified). |

**Observation (not a defect):** `GroupListView.swift:89` binds `.errorAlert(item: $vm.errorAlert)` outside the NavigationStack on the *shared* `HomeViewModel`, and `MainTabView` runs `homeVM.loadAll()` on every `didBecomeActive` with errors always shown. A `HomeViewModel` error can therefore present an alert over a pushed `GroupDetailView` even though that view loads with `showError: false`. Not the cause here; check it first for any future "unexpected alert over a group screen" report.

---

## Payment Handle Experience + Unified Diagnostics — 2026-07-27

Follow-up to the PayPal handoff defect above. These address what that investigation *exposed*, rather than the defect itself.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| PAY-06 | `xBill/Services/PaymentHandleValidator.swift` (new) | Handle rules lived in three disagreeing places (`ProfileView` ×2, `PaymentLinkService.normalizedHandle`, a second regex in `paypalLink`). All wrongly accepted `.`/`-`/`_` and 2-character handles, so a handle could pass entry and never produce a working link. | ✅ Resolved | Single source of truth. Provider-sourced rules: PayPal.Me 3–20 ASCII alphanumerics; Venmo 5–30 plus `-`/`_`. Explicit ASCII set (not `CharacterSet.alphanumerics`, which accepts non-Latin letters). Charsets deliberately separate. `cded124` |
| PAY-07 | `xBill/Services/PaymentLinkService.swift` | Duplicate validation; no way for a user to check their own handle works. | ✅ Resolved | Delegates all validation to the validator; dead `normalizedHandle` and the redundant regex removed. Added `profileLink(handle:method:)` → `paypal.me/<handle>` / `venmo.com/u/<handle>`, **no amount**. `ddb7f1c` |
| PAY-08 | `xBill/Views/Profile/ProfileView.swift`, `ProfileViewModel.swift` | An unusable handle could be saved, failing later inside the payment app where it read as an xBill bug. | ✅ Resolved | Entry and persistence validate through the validator; a "Test your PayPal/Venmo link" row appears once a valid handle is saved. Live scraping of PayPal's error markup was rejected as fragile. `b90a6b9` |
| PAY-09 | `xBill/Views/Groups/GroupDetailView.swift` | Payment button silently absent when a recipient had no handle; destination handle invisible before handoff. | ✅ Resolved | Button reads `PayPal · @handle`; no-handle case renders "Ask <Name> to add a payment handle". `7c4beac` |
| PAY-10 | `xBill/Views/Groups/GroupDetailView.swift` | xBill never learned whether a handoff payment completed, so debts silently stayed open. | ✅ Resolved | "Did you complete this payment?" on return. Guards: armed only when `openURL` reports accepted; cleared after one answer; deferred past `AppLockService.isLocked` (App Lock engages on backgrounding, so the dialog would otherwise render behind the lock overlay). Defaults to unmarked. `7c4beac` |
| PAY-11 | `xBillUITests/RegressionUITests.swift` | Added regression test was vacuous — both `if/else` branches asserted the same condition, and a single-member group never reaches `settlementRow`, so it passed unconditionally even with the feature broken. | ✅ Resolved | Deleted. Real coverage needs a two-member fixture the suite lacks; the contract is covered by `PaymentHandleValidatorTests` + `PaymentHandoffTests`, with the surface verified on-device. `95d00d3` |
| PAY-12 | `supabase/seed_app_store_review_account.sql`, `SETUP_REVIEW_ACCOUNT.md` | With a real handle entered, the demo settle-up button opens a genuine $95.00 payment screen — a stray tap during testing sends real money. | ✅ Resolved | All amounts ÷50 (exact at 2dp, splits still sum, no `is_settled` changed). Settlement $95.00 → $1.90. ÷50 not ÷100 to stay above a possible unverified $1 PayPal minimum. Applied and verified against the live DB. `18b02a9` |
| PAY-13 | `xBill/Core/AppDiagnostics.swift` | `PaymentDiagnostics` was named for one investigation, so the next would scatter into a second file. | ✅ Resolved | Renamed to `AppDiagnostics`; categorised (`.payment .auth .balance .lifecycle .sync`), one log per app at `Documents/xbill-diagnostics.log`, 2 MB cap keeping the newest half. `Category` outside `#if DEBUG` so Release compiles. `94b00fd` |
| PAY-14 | `xBill/Core/AppDiagnostics.swift` | Log rotation rewrote the whole file **non-atomically**; a process kill mid-write could truncate or empty it — in the one file whose purpose is surviving backgrounding and crashes. Also `suffix(count/2)` could wipe a file with no newline. | ✅ Resolved | `write(to:options:.atomic)` plus `max(1, lines.count / 2)` floor. `dc787fc` |
| PAY-15 | `xBillTests/SecurityFixTests.swift` | `PayPalUsernameValidationTests` asserted the **old, wrong** PayPal charset — that `john.doe-42_a` yields a valid link. Broken by PAY-07 and missed because that task's verification was scoped to one test file. | ✅ Resolved | Assertion corrected to `== nil` (strictly stricter, matching PayPal's documented rule). `b90a6b9` |
| PAY-16 | `xBillUITests/RegressionUITests.swift` | `testProfileEditAndPaymentHandleValidationRegression` pinned the obsolete copy "Venmo handles should start with @." The validator now strips `@` rather than requiring it, since a Venmo username contains none. | ✅ Resolved | Asserts the new length message, and additionally verifies the message **clears** for a valid handle — the original only checked that some message appeared, which would pass even if the field were permanently erroring. |

| PAY-17 | `xBill/Services/PaymentLinkService.swift` | Payment URLs emitted amounts with dropped trailing zeros (`1.9USD`, `95USD`). PayPal.Me **ignores** a non-two-decimal amount and renders the plain profile page — verified on device against `/5.00USD`, which opens a real payment screen. Pre-existing; affected every round settlement amount. | ✅ Resolved | `formattedAmount` using `en_US_POSIX` with grouping disabled, applied to both the PayPal path and the Venmo amount parameter. `6f70b62` |
| PAY-18 | `xBill/Views/Groups/GroupDetailView.swift` | Return prompt was armed but never rendered — set while `ContentView` animates `AppLockView` away over 0.3s, and SwiftUI drops a presentation raised from a descendant mid-transition. Device-only: needs App Lock, a real app switch and a physical device. | ✅ Resolved | Presentation waits for the unlock transition to settle; added `handoffPrompt.deferred`/`.arming`/`.presented` diagnostics that distinguish "never armed" from "armed but not presented". `be3bbd5` |
| PAY-19 | `xBill/Views/Groups/GroupDetailView.swift` | "Not yet" button did not render — a `.cancel`-role button inside a `confirmationDialog` is not reliably shown with its own title, so only "Mark as Settled" appeared. | ✅ Resolved | Switched to `.alert`, the correct control for a binary question, which guarantees both titled buttons. `be3bbd5` |
| PAY-20 | `SETUP_REVIEW_ACCOUNT.md` | The ÷50 pass rescaled a single split inside an illustrative SQL block and left the rest at original values, leaving a Sushi expense with a `120.00` total and splits summing to `75.00`. Its review checked the balances summary but not the example SQL. | ✅ Resolved | Whole block scaled consistently; all five expenses in it reconcile. |
| PAY-21 | `supabase/seed_app_store_review_account.sql` | Seed amounts were rescaled twice (÷50 → ÷10 → ÷50) chasing a PayPal behaviour that turned out to be a **self-payment**, not an amount problem. The misleading evidence was a Safari test compared against a PayPal-app failure — two different renderers. | ✅ Resolved | Settled at ÷50 ($1.90) on the only rationale that still holds: limiting exposure if anyone taps through. Demo handles returned to `NULL` for App Store review. |

| PAY-22 | `xBill/ViewModels/ProfileViewModel.swift` | `saveProfile` treated an **invalid** handle identically to an **empty** one (both → `nil`), so an abandoned invalid edit silently NULLed a good stored handle on any later unrelated save. Data loss with no error shown. | ✅ Resolved | Switches over all three `PaymentHandleValidator.Result` cases; `.invalid` preserves the stored value. `abe037f` |
| PAY-23 | `xBill/Views/Groups/GroupDetailView.swift` | "Mark as Settled" re-read `@State` that the alert's own binding also clears. If SwiftUI reset the binding first the guard fell through: no settlement, no error, prompt gone — the user believes it settled. | ✅ Resolved | `.alert(_:isPresented:presenting:)` overload passes the payload into the action closure. `abe037f` |
| PAY-24 | `xBill/Views/Groups/GroupDetailView.swift` | Two `@State` optionals encoded an invariant nothing enforced; **both** shipped device-only bugs were violations of it. | ✅ Resolved | Single `HandoffState` enum (`.none`/`.pending`/`.asking`) where `pending → asking` is non-destructive, so a dropped presentation is recoverable rather than fatal. `abe037f` |
| PAY-25 | `xBill/Services/AuthService.swift` | Swift's synthesized `Encodable` omits nil optionals, so clearing a payment handle sent no `venmo_handle`/`paypal_handle` key and the column was never cleared — "delete handle and Save" did nothing. Pre-existing; PAY-22's `.empty → nil` clear path depended on it. | ✅ Resolved | Custom `encode(to:)` using `encodeNil`. `avatarURL` keeps omit-on-nil deliberately. `ProfilePayloadTests` pins the wire format. `4422a31` |
| PAY-26 | `xBill/Models/User.swift`, `xBill/Services/AuthService.swift` | **Critical.** `paypalHandle` decodes as `(try? .paypal_handle) ?? (try? .paypal_email)`; `try?` flattening (SE-0230) means an explicit JSON `null` falls through to the legacy `paypal_email` column, which no save ever wrote. Clearing a PayPal handle nulled `paypal_handle`, then the response resurrected the old value from `paypal_email` — settle-up kept rendering a live link to the deleted handle. Made **newly reachable** by PAY-25, which changed omission into an explicit null. | ✅ Resolved | `UserUpdatePayload` writes `paypal_email` in lockstep with `paypal_handle`, so the legacy column can never hold a stale value. Round-trip test merges the payload over a pre-036 row as PostgREST would and asserts the handle stays nil. `0fd42f5` |
| PAY-27 | `xBill/Views/Groups/GroupDetailView.swift` | `.asking` was terminal: a dropped presentation wedged the screen, and `openPaymentURL`'s `.asking` bail then silently armed nothing for **every** later payment tap until the screen was popped. A regression from the prior two-optional design. The code comment falsely claimed recovery existed. | ✅ Resolved | Removed the bail so a fresh tap supersedes a stale `.asking`; added a real recovery path forcing a false→true edge, guarded by a >2s staleness hold; corrected the false comment. `0fd42f5` |
| PAY-28 | `xBill/Views/Groups/GroupDetailView.swift` | `HapticManager.success()` fired unconditionally after `recordSettlement`, which never throws and swallows failures into `errorAlert` — a failed settlement played a success buzz alongside an error alert. | ✅ Resolved | Gated on `vm.errorAlert == nil` at both settle sites. `0fd42f5` |
| PAY-29 | `xBill/Views/Groups/GroupDetailView.swift` | The scenePhase diagnostic logged the whole handoff payload (names, amount, currency) to the on-device log, a regression from a single Bool. DEBUG-only, but a financial record. | ✅ Resolved | Logs a case label only. `0fd42f5` |

**Not a defect:** PayPal renders a profile page rather than a payment screen when the payer and payee are the same PayPal account. The device log proves xBill builds the correct URL and `openURL` accepts it. This cannot be demonstrated with the tester's own handle at any amount.

**Process notes worth keeping:** two defects in this batch (PAY-11, PAY-15) were introduced by the implementation plan itself and caught only by per-task review and a full-suite run. Both stemmed from the same habit — verifying a claim against one file and generalising. Scope test runs to the whole suite, not the file you touched.

---

## Notification Unread Lifecycle — 2026-07-28

Reported on a physical iPhone: marking a Recent notification unread reverted to read after backgrounding, Face ID unlock and returning. Raw evidence in `diagnostics/2026-07-28-notification-unread/`; how to read it is in `diagnostics/README.md`.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| NOTIF-01 | `xBill/Models/NotificationItem.swift` | Nothing distinguished a `public.notifications` row from an expense-derived history row, whose `id` is an **expense** id. Verified against the live DB: 12 expenses, 3 notification rows, **zero id overlap**. | ✅ Fixed | Added `isServerBacked`; `decodeIfPresent ?? false` so pre-existing cache entries decode as local. |
| NOTIF-02 | `xBill/ViewModels/ActivityViewModel.swift` | Read/unread toggles on a history row issued `UPDATE notifications … WHERE id = <expense id>` — always zero rows. | ✅ Fixed | `setReadState` writes through only when `item.isServerBacked`; history rows are local-only. |
| NOTIF-03 | `xBill/Services/ActivityService.swift` | `fetchRecentActivity` forced `isRead = true` on every history row on every refresh, erasing a deliberate unread mark on the post-unlock reload. **This is the reported symptom.** | ✅ Fixed | New pure `ActivityReconciler.reconcile(...)` keeps the stored read state and defaults only *unseen* rows to read, so pre-040 history still never inflates the badge. |
| NOTIF-04 | `xBill/Services/RemoteNotificationService.swift` | `.select("id").single()` (commit `2911833`) turned the zero-row write into PGRST116 *"Cannot coerce the result to a single JSON object"* — an opaque response-shape error masking "no row matched", surfaced as an *Activity Update Failed* alert. | ✅ Fixed | Decode the `return=representation` **array** and check the affected-row count in `acknowledgeUpdate(rows:id:)`, throwing `RemoteNotificationError.rowNotFound`. `.single()` is only an Accept header and is never a row-count check. |
| NOTIF-05 | `xBill/Services/RemoteNotificationService.swift` | `read_at` was encoded by the SDK's date strategy as a zone-less `2023-11-14T22:13:20.000`, resolved using the Postgres session `TimeZone`. Correct only because that is UTC here (`show timezone;`). | ✅ Fixed | `NotificationReadStatePayload` writes an explicit UTC ISO-8601 instant. Unread still sends an explicit JSON `null`. |
| NOTIF-06 | `xBill/ViewModels/ActivityViewModel.swift` | A failed write rolled back a whole snapshot of `items`, which could also revert unrelated rows changed while the write was in flight. | ✅ Fixed | Rollback is scoped to the single affected row. |
| NOTIF-07 | `xBill/Services/ActivityService.swift` | A pending read intent for a non-existent row was retried on every refresh and could never succeed. | ✅ Fixed | `reconcilePendingReadStates` clears the intent on `rowNotFound`. |
| NOTIF-08 | `xBill/Core/AppDiagnostics.swift` | `describe` logged only `localizedDescription`, so the device log showed the JSON-coercion message and dropped `PGRST116` / "The result contains 0 rows" — the part that identifies the fault. | ✅ Fixed | Logs PostgREST `code`/`detail`/`hint`; `markRead`/`markUnread` failures now log the item id. |

### Follow-up batch — same session

The delete path carried the same two faults as the read-state path, and the diagnostics could not distinguish which row kind a run had exercised.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| NOTIF-09 | `xBill/Services/RemoteNotificationService.swift` | `delete` had **no** affected-row acknowledgement — the same latent fault as NOTIF-04. An RLS miss, or an id that is not a notification row, returned HTTP 200 with an empty body and read as success. | ✅ Fixed | `.delete().eq("id").select("id")` decoded as an array and checked through the shared `acknowledgeAffectedRows(_:id:)` (renamed from `acknowledgeUpdate`, now used by both paths). |
| NOTIF-10 | `xBill/ViewModels/ActivityViewModel.swift`, `NotificationStore`, `ActivityReconciler` | Deleting a **history** row removed it locally, then the next fetch re-derived it from the expense list and it reappeared. | ✅ Fixed | History-row deletes are local-only and recorded via `NotificationStore.dismissHistoryItem`; `ActivityReconciler` filters dismissed ids out of the legacy set. Capped at 200, user-scoped, never applied to server rows — deletion there is authoritative server-side. |
| NOTIF-11 | `xBill/ViewModels/ActivityViewModel.swift` | A failed delete restored a whole snapshot of `items`, reverting unrelated rows changed while the request was in flight, and reinstated the row at the end of the list. | ✅ Fixed | Restores only that row, at its original index. |
| NOTIF-12 | `xBill/ViewModels/ActivityViewModel.swift` | A *successful* read-state write logged nothing, so the post-fix device log could only show the absence of errors — never which row kind was exercised. This is exactly the gap left open after the first device run. | ✅ Fixed | `ActivityViewModel.readState.remote` logs id/isRead/succeeded; `delete.localOnly` logs history-row dismissals. |

**Regression cover:** `xBillTests/NotificationReadStateTests.swift` — 29 tests over payload encoding, array-shaped affected-row acknowledgement, reconciliation, item origin, dismissal persistence/scoping/capping, and view-model mutations (local-only routing for both read state and delete, scoped rollback, in-place delete restore, last-toggle-wins). `historicalUnreadSurvivesRefresh` and `dismissedHistoryItemStaysDeleted` were each confirmed to fail against the pre-fix behaviour.

**Verification:** `scripts/run-coverage.sh unit` → **193 passed, 0 failed, 0 skipped** (`TestResults/Coverage/2026.07.28_19-41-38-unit.xcresult`). Release build succeeded.

**Device-verified** on iPhone 16 Pro `00008140-000135EE3432801C`, log `diagnostics/2026-07-28-notification-unread/after-followup.log`, **0 failure lines** in the session:

| | History row | Server row |
|---|---|---|
| Mark unread | ✅ `readState.localOnly serverBacked=false`, survived Face ID unlock | ✅ `readState.remote succeeded=true`, survived Face ID unlock |
| Delete | ✅ `delete.localOnly`, stayed deleted across lock + refresh | Unit-tested only |

The deleted row carries the same seeded `EEEEEEEE-0001-…` id as the row marked unread, so both checks provably hit the expense-derived history path — the one that produced the original zero-row writes. Deleting a **server-backed** row was deliberately not exercised: it permanently removes one of only three real notification rows, and its acknowledgement is the same `acknowledgeAffectedRows(_:id:)` path confirmed live by the read-state update.

---

## Senior Developer Review — 2026-07-28 (REV)

Read-only review focused on money correctness, write acknowledgement and state consistency;
prior audits had already swept the common ground. 13 findings. RLS claims below were verified
against the live database with read-only queries.

### Critical / High

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| REV-01 | `xBill/Services/ExpenseService.swift:180`, `xBill/Views/Groups/GroupDetailView.swift:541,584` | **Anyone can "Mark as Settled" on a debt they do not own, and the write silently does nothing.** The live UPDATE policy on `public.splits` is `"splits: own row settle" USING (auth.uid() = user_id)` — only the **debtor** may settle. But the settle-up list is unfiltered (every member sees every debt pair) and the button is ungated (only the *payment* buttons check `currentUserID == suggestion.fromUserID`). `settleSplit` has no `.select()` and no affected-row check, so a zero-row RLS miss returns HTTP 200 and succeeds. The caller then adds the ids to `locallyConfirmedSettledSplitIDs`, which force-overrides `isSettled = true` on every later fetch for the view model's lifetime, **and fires a settlement push to the creditor**. The debt is untouched in the database. Same class as `NOTIF-04`/`NOTIF-09`, but with money and a local override that hides the divergence. | ✅ Fixed | Resolved by the settlements ledger (migration 041, deployed 2026-08-01). Repayment is now a row in `public.settlements` with its own RLS: INSERT allows **either party**, DELETE allows only the recorder, and there is no UPDATE policy. The UI matches exactly — `isParty` gates the Record Payment action, and swipe-delete is gated on `recordedBy == currentUserID`. A creditor's tap now genuinely works instead of silently affecting zero rows. `REV-02` and `REV-13` are structurally impossible under the new model: a payment is one row with a free-form amount, so there is nothing to match against whole splits and nothing to half-apply. Design: `docs/superpowers/specs/2026-07-28-settlements-ledger-design.md`. |
| REV-02 | `xBill/ViewModels/GroupViewModel.swift:470` | **Partial settlement failure leaves splits settled server-side while showing an error.** N splits are settled in a parallel `withThrowingTaskGroup`; if one fails the group throws, but already-committed writes stand. No compensation, and `locallyConfirmedSettledSplitIDs` is never updated, so local state disagrees with the server. | ✅ Fixed | Settle each split independently, collect outcomes, confirm only what committed, and report "Only N of M parts were recorded" instead of a generic error. No notification is sent on a partial settlement. |
| REV-03 | `xBill/ViewModels/GroupViewModel.swift:396` | **A deleted locally-created expense resurrects.** `applyFetchedExpenses` re-merges `locallyCreatedExpenses` entries missing from a fetch, and only clears an entry when it *appears* in a fetch. `deleteExpense` never removes it, so the expense is re-added on every subsequent load. | ✅ Fixed | `deleteExpense` removes the id from `locallyCreatedExpenses`. |

### Medium

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| REV-04 | `xBill/ViewModels/GroupViewModel.swift:162,168,175,201` | **The stale-data warning can never fire.** `applyFetchedExpenses` sets `balanceLoadFailed = true`; `load()` then calls `computeBalances()`, which clears it at line 201 before any view reads it. `shouldShowExpenseRefreshState` is dead code. | ✅ Fixed | `balanceLoadFailed` is cleared at the start of the network branch of `load()`, before `applyFetchedExpenses` can raise it — not at the top of `computeBalances`, which runs after. |
| REV-05 | `xBill/ViewModels/GroupViewModel.swift:235,239` | **Coalesced balance recomputes are dropped.** The catch block early-`return`s while `shouldRecomputeBalances` may be true; the `defer` clears `isComputingBalances`, losing the queued recompute — the exact failure the coalescing was added to prevent. | ✅ Fixed | The catch-block early exits use `continue`, which re-checks the `repeat`/`while` condition, so a queued recompute still runs. |
| REV-06 | `ExpenseService:251`, `GroupService:191`, `CommentService:117`, `FriendService:118`, `IOUService:140`, `AuthService:48,141,150` | **Seven more mutating calls with no affected-row check.** Same class as REV-01, smaller blast radius: all return success on a zero-row RLS miss. The Apple display-name upsert is additionally wrapped in `try?`, so it is doubly silent. | ✅ Fixed | New shared `SupabaseWrite.requireAffected` applied to `deleteExpense`, `deleteGroup`, `deleteComment`, `deleteIOU`, `removeFriend`. **Two exclusions:** `device_tokens` deletes legitimately match zero rows (clearing tokens for a user who has none), and the Apple display-name upsert can race the profile trigger — that one now logs instead of discarding via `try?`. |
| REV-07 | `xBill/ViewModels/ActivityViewModel.swift:88` | **`markAllRead` rollback is unscoped** — a gap in the `NOTIF-06` fix. It restores a whole `previousItems` snapshot, reverting history rows whose read state never depended on the failed server call. | ✅ Fixed | Rollback reverts only server-backed rows. Also revealed that `markAllRead`'s Task was untracked by `hasInFlightMutations`; now tracked. |
| REV-08 | `xBill/ViewModels/ActivityViewModel.swift`, notify Edge Functions | **Badge divergence introduced by the `NOTIF-03` fix.** `setBadge` uses `store.unreadCount()`, which now counts locally-unread history rows, while the Edge Functions compute the APNs badge from `public.notifications` only. Marking a history row unread makes the in-app badge disagree with the next push-set badge. | ✅ Fixed | New `iconBadgeCount` / `NotificationStore.serverUnreadCount` drives `setBadge`; `unreadCount` still drives the in-app tab badge. |

### Low

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| REV-09 | `xBill/ViewModels/GroupViewModel.swift:351` | `createDueRecurringInstances(currentUserID:)` never uses the parameter, and its doc comment still claims it only acts on expenses the current user paid for — untrue since `M-08`. | ✅ Fixed | Parameter removed and the doc comment corrected to describe the post-`M-08` behaviour. |
| REV-10 | `xBill/Services/SplitCalculator.swift:74` | `splitByPercentage` assigns the rounding remainder to the **first** participant while `splitEqually` and `splitByShares` use the **last**, and it silently dumps the shortfall on that participant when percentages do not sum to 100. | ✅ Fixed | New `SplitCalculator.validatePercentages`, wired into `splitValidationError`. The first-vs-last remainder difference is left as documented behaviour — with validation in place it only ever moves a rounding cent. |
| REV-11 | `xBill/Services/SplitCalculator.swift:182,198` | `minimizeTransactions` emits a *rounded* transfer amount but decrements the running balances by the *unrounded* one, so suggestions can drift from the true balances. | ✅ Fixed | Balances are decremented by the *rounded* amount that was actually suggested, falling back to the unrounded amount when nothing was suggested so the loop still progresses. |
| REV-12 | `xBill/Services/SplitCalculator.swift:46` | `splitEqually` computes `share / total * 100` with no zero guard. Latent only — `AddExpenseViewModel.recomputeSplits` guards `total > 0` — but it is a public API called directly by tests. | ✅ Fixed | Zero-total guards on all three split strategies. |
| REV-13 | `xBill/Services/SplitCalculator.swift:219` | `directSettlementSuggestions` does not net mutual debts: if A owes B $10 and B owes A $6, Settle Up shows both rows rather than a single $4. Deliberate (rows must map to whole splits) but confusing in the UI. | ➖ Won't fix | Netting reintroduces the defect `directSettlementSuggestions` exists to prevent: a netted $4 matches none of the debtor's whole splits, so `recordSettlement` could not settle it without over-settling. Documented in place; a netted view belongs in the UI layer over rows that stay individually actionable. |
| DEV-01 | `xBill/Models/Settlement.swift:52` | **Crash (SIGABRT) on device.** `SettlementSuggestion` had a stored `id: UUID` that all four construction sites filled with `UUID()`, so every balance recompute produced structurally identical rows carrying brand-new identities. SwiftUI treated each settle-up row as deleted-and-reinserted on every refresh; when that reached `UICollectionView` inside the swipe-delete animation of the payment list in the same `List`, the batch update stopped reconciling and UIKit aborted with `_Bug_Detected_In_Client_Of_UICollectionView_Invalid_Number_Of_Items_In_Section`. Intermittent: it needed a concurrent `load()` (a Face ID unlock refresh) to overlap the delete. Evidence: `diagnostics/2026-08-01-settlements/crash-110535.ips`. | ✅ Fixed | The stored id is **removed**, not merely assigned more carefully — a stored id can be filled with `UUID()` by the next caller, as all four sites did. `id` is now computed: `fromUserID|toUserID|currency`. Currency is part of the key because `HomeViewModel.crossGroupSuggestions` minimizes per currency and concatenates, so one pair may legitimately appear once per currency. Also fixes unstable accessibility identifiers on six settle-up controls, which no UI test could have targeted reliably. |
| DEV-02 | `xBill/ViewModels/GroupViewModel.swift` | `recordPayment` and `deletePayment` had no diagnostics logging, so the DEV-01 crash left no trace and the device log could not distinguish "never reached" from "crashed midway". Same gap recorded after the notification work: log the success path, not only failures. | ✅ Fixed | `deletePayment.enter` / `.committed` / `.catch` added. |
| DEV-03 | `xBill/ViewModels/GroupViewModel.swift` (`deletePayment`, `recordPayment`) | **Crash (SIGABRT) on device — the real cause of the settle-up delete crash.** `deletePayment` removed the row from `settlements`, then `await computeBalances()`, which fetched splits over the network *before* reassigning `settlementSuggestions`. That `await` split one user action into two separately published mutations of the same `List`, landing either side of a round-trip while the swipe-delete animation was still in flight. `UICollectionView` aborted: `NSInternalInconsistencyException` — "the number of items contained in an existing section after the update (3) must be equal to the number ... before the update (2), plus or minus the number of items inserted (0)". Confirmed by `deletePayment.enter` at 16:23:13.625 and the abort 68 ms later with no concurrent `load()` (`isLoading` correctly gates it out). Evidence: `diagnostics/2026-08-01-settlements/crash3.log`. | ✅ Fixed | New synchronous `applyDerivedBalances()` recomputes balances and suggestions from state already in memory; both payment paths use it instead of `computeBalances()`. Recording or deleting a payment changes the ledger, never a split, so `splitsMap` is already correct and the fetch was never needed — removing it removes the suspension point, so both mutations land in one turn and SwiftUI sees one coherent update. `load()` still refetches. Regression test asserts zero split fetches on both paths (verified to fail against the pre-fix code). |
| DEV-04 | `xBill/Core/AppDiagnostics.swift` | The sentence identifying a UIKit assertion lives only in the `NSException` `reason`, which the `.ips` crash report does not carry — so it was reachable only by holding a `--console` session open at the instant of the crash. That failed twice (console detached; device went unavailable), costing two reproductions. | ✅ Fixed | `installUncaughtExceptionLogger()` writes name, reason and stack into the Documents diagnostics log, so the reason survives to be pulled later. DEBUG-only; Release verified. This is what produced the DEV-03 diagnosis on the next reproduction. |
| MIN-01 | `xBill/Views/Groups/GroupDetailView.swift:259,552` | Recording **or deleting** a payment gave no haptic feedback. The old post-handoff `confirmationDialog` fired `HapticManager.success()`; the alert-plus-sheet flow that replaced it did not, so the feedback was lost rather than dropped deliberately. Money moving between people is the most consequential action on the screen and it happened silently. | ✅ Fixed | `HapticManager.success()` / `.error()` after `recordPayment` **and** `deletePayment`, keyed off `errorAlert` (the only success signal available — both return Void). The delete half was missed in the first fix and found on device: recording buzzed, deleting did not. Deleting is not the lesser action — it puts a debt back. **Both halves device-verified 2026-08-01.** |
| MIN-02 | `xBill/Views/Groups/GroupDetailView.swift:599` | A settle-up row for a debt the user is not party to renders dimmed with no button and **no explanation**, which reads as a bug. The neighbouring "Ask <name> to add a payment handle" case does explain itself. | ✅ Fixed | Caption: "Only <from> or <to> can record this payment." This states a real constraint — migration 041's INSERT policy requires `auth.uid() IN (from_user_id, to_user_id)` — not a UI preference. |
| MIN-03 | `xBillTests/GroupViewModelSettlementTests.swift:44` | `InterleavingGate` holds a single `parked` continuation. A second park overwrites the first, which is then never resumed — the task hangs forever, and the watchdog cannot report it because its `parkToken == token` guard no longer matches the stranded park. A silent hang of the whole suite, which this file has already caused once (>600 s). | ✅ Fixed | `waitIfArmed` refuses to park while one is live and records an issue instead. |
| MIN-04 | `CLAUDE.md` File Map | Five entries for the settlements work landed under `### Models` — one service, two views and two SQL scripts. The File Map is the live index agents navigate by, so a misfiled entry sends the next reader to the wrong section. | ✅ Fixed | Moved to Services, Views — Groups, and a new `### Deployment Scripts` section. |
| MIN-05 | `GroupViewModel.pendingSettlementChanges` | Entries expire when a fetch that started after them returns. A failed or offline fetch never calls `applyFetchedSettlements`, so entries accumulate across an offline session. | ➖ Accepted | Bounded by user actions within one session and cleared by the next successful fetch; a VM is per-screen, not app-lifetime. Adding a cap risks dropping a legitimate pending change — the exact correctness property that took five review rounds to get right. Not worth destabilising for an unbounded-growth risk nothing can realistically reach. |
| MIN-06 | `GroupViewModel.lastRecordedPayment` | The 60 s duplicate-payment window does not survive view-model re-creation, so re-entering the group reopens it. | ➖ Accepted | The window exists to absorb a Venmo/PayPal round trip answered on return; that path keeps the same VM. Persisting it would mean writing payment intent to disk to defend against a narrower case than the one it was built for. |
| MIN-07 | `supabase/functions/notify-settlement/index.ts` | Returns 404 for a missing settlement and 403 for one recorded by someone else, distinguishing existence from authorisation. | ➖ Accepted | The oracle needs an unguessable v4 UUID to query and reveals only that *some* settlement exists — no group, party or amount. Narrower than `notify-expense`'s membership-first pattern but inert. |
| MIN-08 | `GroupViewModel.applyFetchedSettlements` (I4 guard) | In a narrow out-of-order-plus-empty case the generation guard can discard a good response. | ➖ Accepted | Self-recovering: the next load applies. The guard exists to stop a slower earlier fetch overwriting a newer result, which is the more damaging failure. |
| MIN-09 | `CacheService` | No settlements persistence, so a VM created offline starts with `settlements == []`. | ➖ Accepted (mitigated) | The harm — rendering gross pre-payment debt as if correct — is already blocked: `load()`'s offline branch raises `balanceLoadFailed` when the group has expenses but no settlements in memory, so the stale-amount banner shows. Persisting the ledger offline is a feature, not a defect fix. |
| UIT-01 | `xBill/Views/Groups/GroupDetailView.swift:683` | **Five accessibility identifiers did not exist at runtime.** `.accessibilityIdentifier("xBill.settleUp.suggestionRow.…")` was applied to the settlement row's enclosing `VStack`, which propagates to every descendant and **overwrites** their own identifiers. `recordPaymentButton`, `venmoButton`, `paypalButton`, `noPaymentHandle` and `nonPartyCaption` were therefore unreachable — every element in the row reported the row id. The regression suite's `xBill.settleUp.recordPaymentButton.` predicate could never match; it survived only inside `\|\|` chains where another branch was true, so nothing ever failed. | ✅ Fixed | Row identifier moved onto the header `HStack`, which already forms its own accessibility element via `.accessibilityElement(children: .ignore)`. Children keep their identifiers. Found by the element-tree dump added to `testSettleUpLedgerRegression`. |
| UIT-02 | `xBillUITests/RegressionUITests.swift`, `xBillUITests/GroupFlowUITests.swift` | `xBill.uitest.tab.groups` was referenced as a tap candidate in both files but defined nowhere in the app — a leftover from the DEBUG UIKit hit-target overlay removed in M-66. Cost a 0.5 s `waitForExistence` on every call and implied an identifier that does not exist. | ✅ Fixed | Removed from both files. |
| UIT-03 | `scripts/seed-ui-test-data.sh`, `xBillUITests/RegressionUITests.swift` | **The settlements ledger had no UI regression coverage.** The seed fixtures create groups with the owner as the only member, and a single-member group cannot hold a debt, so `testSettleUpAndActivitySurfacesRegression` could only assert the "All Settled Up!" empty state. None of the four defects device testing found on 2026-08-01 was reachable from this suite. | ✅ Fixed | New `scripts/seed-ledger-regression-group.sql` seeds a three-member `SeedLedger-Regression` group producing one row of every kind ($7.00 debtor, $8.00 creditor, $15.50 non-party) plus both sides of the delete gate. New `testSettleUpLedgerRegression` asserts the Record Payment affordance, the non-party caption, payment history, and that the prefilled amount matches `^\\d+\\.\\d{2}$` — the exact `8` vs `8.00` defect. Read-only: it cancels rather than records, so the fixture stays stable. |
| EXP-01 | `xBill/Services/ExportService.swift` `csvEscape` | **CSV formula injection.** Excel, Numbers and Google Sheets evaluate a cell beginning `=`, `+`, `-` or `@` as a formula. Any group member can name an expense, and the CSV export is a file the user hands to someone else — so a title like `=1+1` becomes a live formula in the recipient's spreadsheet. `csvEscape` quoted but never neutralised. | ✅ Fixed | Fields beginning `=`, `+`, `-`, `@`, tab or CR are prefixed with an apostrophe — the standard mitigation; spreadsheets treat the cell as literal text and do not display the prefix. **Visible change:** an expense titled `-5 drinks` exports as `'-5 drinks`. |
| EXP-02 | `xBill/Services/ExportService.swift` `csvEscape` | **A lone carriage return in a field was not quoted.** `csvEscape` tested for `\n` but not `\r`, while rows are joined with `\r\n` — so a CR inside a title or note is indistinguishable from a row break and silently splits one expense into two malformed rows. | ✅ Fixed | `\r` added to the quoting condition. |
| EXP-03 | `xBillTests/ExportServiceTests.swift` | `ExportService` had **0% coverage** (355 uncovered lines) while producing a file shared outside the app, where a malformed field is silent data corruption — nothing throws and the file opens. | ✅ Fixed | 10 tests over `generateCSV` (header, BOM on the *bytes*, CRLF, 2dp amounts, ordering, unknown payer, comma/quote/newline/CR escaping, formula neutralisation) plus a PDF `%PDF` smoke check. EXP-01 and EXP-02 were both found by these tests failing first. |
| VIS-01 | `xBill/Services/VisionService.swift` `stripQuantityPrefix` | **A quantity prefix the parser accepts was left in the item name.** `parseQuantity` matches `[xX@×]` but `stripQuantityPrefix` matched only `[xX@]`. The Tier-1 fix that added U+00D7 for European receipts (`"2×1.99"`) extended the parsing regex and not the stripping one, so the quantity parsed correctly and the item was then named `2×BURGER`. | ✅ Fixed | Character class aligned to `parseQuantity`'s. |
| VIS-02 | `xBill/Services/VisionService.swift` `stripPrice` | **A stranded currency symbol in the item name.** `extractDecimal` reads `[\$£€₹¥￥₩]` but `stripPrice` removed only `[\$£€₹]`, so a yen or won line had its digits stripped and the bare symbol left behind: `BURGER ¥`. | ✅ Fixed | Character class kept identical to `extractDecimal`'s. |
| VIS-03 | `xBillTests/VisionParsingTests.swift` | `VisionService` was **3.7% covered, 733 uncovered lines** — the largest untested surface in the app, and the one that turns a photograph into money. The pure text→receipt logic was unreachable from tests only because every function was `private`. | ✅ Fixed | Nine parsing functions and `ParsedItem` made module-internal (nothing public), plus 17 tests over `extractDecimal`, `parseQuantity`, `stripQuantityPrefix`, `stripPrice`, `groupIntoRows`, `extractTransactionDate`, `suggestCategory` and `parseWithHeuristics`. **3.7% → 38.4%.** VIS-01 and VIS-02 were both found by these tests failing first. The remaining ~60% is Vision/CoreImage plumbing that needs real images and is not unit-testable. |
| UIT-04 | `xBill/Views/Groups/PaymentHistorySection.swift` | Each payment row's `.accessibilityIdentifier` sat on the enclosing `VStack`, so it propagated to all three inner `Text`s (the UIT-01 pattern again). VoiceOver read every payment as three disconnected fragments — "Bob Patel paid xbill.uitest", "$3.00", "recorded by …" — and no single element represented the row. | ✅ Fixed | `.accessibilityElement(children: .combine)` before the identifier, plus a `.contextMenu` offering Delete — matching `ActivityView`, which has always had both. Swipe was the **only** path to correcting a mis-recorded payment, and there is no edit path at all because the ledger has no UPDATE policy. **Device-verified 2026-08-03**: the menu appears with Delete. Found only by trying to automate the row. |
| UIT-05 | `xBillUITests/RegressionUITests.swift` | **The ledger's write path had no automated coverage** — recording a payment, the one action that moves money, was exercised only by a human tapping a phone, which is where all four defects of 2026-08-01 were found. | ✅ Fixed | `testSettleUpLedgerWriteRegression` records as the **creditor** (the REV-01 path, impossible before migration 041) and asserts an $8.00 debt becomes exactly $6.77 — the partial payment `splits.is_settled` could not represent. Verified at the database, not just on screen. Fixture restored by `scripts/reset-ledger-regression-fixture.sql`, wired into `run-coverage.sh`. |
| UIT-06 | `xBillUITests/RegressionUITests.swift` | **Delete and the delete-permission gate remain unautomated.** These rows are not exposed as cells (settle-up rows are `Other`, a combined payment row is `StaticText`), so `swipeLeft()`, element-relative drags and window-level drags all fail to open a SwiftUI `.swipeActions`. Eight approaches were tried; the database confirmed the delete never fired. | ⚠️ Open | Covered by device testing only. A negative gate assertion (`XCTAssertFalse(deleteButton.exists)`) was written and **removed**: with swipes never opening it passed unconditionally — the UIT-01 defect reproduced hours after documenting it. Closing this needs an accessibility action on the row, or a delete affordance reachable without a swipe. |
| GVM-01 | `xBillTests/GroupViewModelMaintenanceTests.swift` | `createDueRecurringInstances` was **0% covered** — the function behind CRIT-01 (one failing template aborted the whole batch, so later recurring expenses were silently never created) and CRIT-16 (the instance copied the template's recurrence and re-instantiated forever). Both money-creating, neither asserted. `archiveGroup`/`unarchiveGroup` were also 0%. | ✅ Fixed | 8 tests. The CRIT-01 regression was **verified to fail** against a restored batch-aborting implementation before being trusted. `GroupViewModel` 72.2% → 82.0%. |
| GVM-02 | `xBillTests/P1NotificationTests.swift:370` | **A knowingly racy test.** `markReadAndDeleteUpdateVM` drove `NotificationStore.shared` while other suites clear it; it passed at 287 tests and failed at 295 purely because more tests changed the parallel schedule. A previous workaround (counting unread from in-memory items) treated the symptom and left the shared write in place — the comment even acknowledged the race. | ✅ Fixed | Uses an injected per-test store via `ActivityViewModel`'s existing seam, removing the race rather than narrowing its window. |
| VIS-04 | `xBill/Services/VisionService.swift` `convert(_:)` | **Every scanned receipt amount carried a floating-point tail.** The model returns JSON numbers, so `ParsedReceiptJSON` holds `Double`, and `Decimal(Double)` reproduces the binary float exactly as stored: 4.99 → `4.990000000000001024`, 0.07 → `0.07000000000000001024`, a 9.98 total → `9.980000000000002048`. This is the only place money enters the app as a binary float; everywhere else the rule is `Decimal` end to end. | ✅ Fixed | New `VisionService.money(_:)` converts through the shortest round-trip decimal string (`Decimal(string: String(value))`), which recovers the intended number. Applied to unit price, subtotal, tax, tip and total. Found by tests written specifically to check this, after an initial assessment of "probably exact" — which was wrong. |
| AS-01 | `xBill/Services/ActivityService.swift` | Held four hard-coded `.shared` dependencies, so `fetchRecentActivity`, `reconcilePendingReadStates`, `fetchLegacyExpenseActivity` and `items(for:)` were unreachable from tests — 27.7% coverage. | ✅ Fixed | Injection seam defaulted to the singletons (production call sites unchanged), plus `RemoteNotificationProviding` and `fetchGroups` on `GroupDataProviding`. 4 tests covering the two opposite pending-intent outcomes: a row the server no longer has must have its intent **dropped** (NOTIF-12), a transient failure must **keep** it. **27.7% → 64.7%.** |
| UIT-07 | `scripts/check-ui-test-identifiers.sh` | A UI-test predicate that matches nothing does not fail — it sits in an `\|\|` chain and the suite stays green while asserting nothing. Three instances surfaced on 2026-08-01 (`xBill.uitest.tab.groups`, `xBill.settleUp.recordPaymentButton.`, and a hand-written `XCTAssertFalse` that could only be true). | ✅ Fixed | Script diffs identifiers referenced by the UI tests against those the app sets, handling interpolated prefixes. Verified to reject the real dead selector. Wired into `run-coverage.sh regression-ui`; runs in under a second. |
| EXP-04 | `xBill/Services/ExportService.swift:39`, `xBill/Services/PaymentLinkService.swift` | CSV amounts used `String(format: "%.2f", NSDecimalNumber(...).doubleValue)` — routing exported money through a binary float, the pattern behind VIS-04 — and duplicated a two-decimal rule that `PaymentLinkService` already had. Two copies of one rule is the drift that produced VIS-01, VIS-02 and the `PaymentHandleValidator` work. | ✅ Fixed | One definition, `Decimal.plainTwoDecimalString`, formatting the `Decimal` directly (en_US_POSIX, 2dp, no grouping). Both call sites delegate to it, and a test asserts the two **agree** — the property that actually prevents drift. |
| GDV-01 | `xBill/Views/Groups/GroupDetailView.swift` | 1,197 lines holding **five top-level types**, already split into `baseContent`/`lifecycleContent`/`decoratedContent` — not for clarity but to escape a Swift type-checker timeout. Logic in view bodies is unreachable by unit tests, which is most of why app coverage sits near 21%. | ✅ Fixed | **1,197 → 799.** Extracted `GroupSettingsView`, `ExpenseFilterChip`, `ExportShareItem`, and `SettlementSuggestionRow` (which carries the party naming, the `isParty` gate matching migration 041's INSERT policy, the non-party caption and the UIT-01 identifier placement). The payment-handoff state machine was **deliberately left in place**: two device-only defects behind it, driven by view state with no meaning elsewhere. Verified by the full 17-test UI suite. |
| UIT-08 | `xBillUITests/RegressionUITests.swift` | **A 67-minute hang.** `element.tap()` followed by `typeText` with nothing confirming the tap focused the field; XCUITest then either raises "Neither element nor any descendant has keyboard focus" or wedges indefinitely. 13 sites had the bare pattern while `focusTextInput` — which taps, waits for the keyboard and retries — sat unused beside them. It broke `searchGroups` twice before hanging the suite on the Profile payment-handle field. | ✅ Fixed | New `typeInto` helper asserts focus before typing; all 13 sites routed through it. A hang is worse than a failure: it burned an hour and left an unreadable result bundle, losing an answer already paid for. |
| XR-01 | `xBill/Services/ExchangeRateService.swift` | **0% covered while converting money between currencies** — the highest risk per line in the app, because a wrong rate does not crash, it silently changes what an expense is worth. It also carries the `Decimal(string: String(double))` round-trip from H-08/H-15 — the same guard `VisionService` needed for VIS-04, where the equivalent conversion was found producing `4.990000000000001024`. Nothing verified this one held. | ✅ Fixed | Injection seam for the fetch closure and `UserDefaults` (so a test cannot touch the real stale-rate disk cache). 9 tests: rounding, the float-error guard, same-currency short circuit, unknown currency, non-2xx rejection (H-37), API error result, in-memory cache, stale-disk fallback (L-25), and no-cache-no-network. **0% → 95.3%.** |
| GRD-01 | `xBill/Services/IOUService.swift`, `xBill/ViewModels/ProfileViewModel.swift` | Two guards that reject bad input before any network call had no coverage: M-25 (an IOU may only be created by its lender or borrower, mirroring the DB CHECK) and H-17 (a blank display name must be caught before the avatar upload). | ✅ Fixed | 4 tests. Each asserts **both** directions — that the guard rejects, and that it still admits the legitimate cases, since a guard which refused everything would satisfy the rejection test alone. `IOUService` 1.7% → 28.7%, `ProfileViewModel` 5.6% → 28.2%. |
| GRD-02 | `xBill/Services/FriendService.swift`, `xBill/Services/CommentService.swift` | 1.4% and 0% covered. | ➖ Accepted | Both are PostgREST query building end to end — a unit test over them would assert what a fake returns, not what the app does. That is coverage for its own sake, and this codebase has already been bitten by it (UIT-01: an assertion that could never fail still counted as covered). Their real behaviour — RLS, filters, affected-row counts — needs integration tests against Supabase, which is a different piece of work from unit testing. |
| REL-01 | `public.profiles` (App Store reviewer account) | **Release blocker, found by running `RELEASE_VERIFICATION.md`.** The reviewer profile had `paypal_handle = 'imvijaygoya'` — confirmed by the owner as not a real PayPal.Me profile. `PaymentLinkService` renders a saved handle as a live deep link, so a reviewer tapping PayPal in Settle Up would land on PayPal's own "Something went wrong" page and attribute it to xBill. Identical to the July defect, where seeded `'appreviewer'` handles produced exactly that. The seed writes `NULL`, so this was typed in during device testing. | ✅ Fixed | Handles cleared; `profiles_with_handles` back to **0**, so Settle Up shows "Ask … to add a payment handle" and renders no button at all. `RELEASE_VERIFICATION.md` now carries this as an explicit pre-submission check, since nothing automated would have caught it. |
| AUTH-01 | `xBill/Views/Auth/EmailAuthView.swift:69`, `xBill/Views/Auth/AuthView.swift:64` | **A sign-in error was unreadable.** Both views bound `.errorAlert(item: $vm.errorAlert)` to the same `AuthViewModel`. `EmailAuthView` is *pushed* via `navigationDestination`, so both stay in the hierarchy and compete to present one `Identifiable` optional: one presents, the other's dismissal writes `nil` back to the shared binding and tears it down. On device the alert flashed for about a second — long enough to see something failed, too short to read why. Third instance of this shape in the codebase (see the `GroupListView:89` note). | ✅ Fixed | Single binding kept at the NavigationStack **root**, which covers both screens. Presenting from an ancestor is also the more reliable direction — the payment-handoff work found SwiftUI drops a presentation made from a descendant mid-transition. Device-verified: the alert now persists until dismissed and reads "Invalid login credentials". |
| REL-02 | `RELEASE_VERIFICATION.md` §8 | Account deletion had not been verified since the settlements ledger shipped, and Apple explicitly tests in-app deletion. | ✅ Verified 2026-08-04 | Disposable account, full before/after comparison. **Removed:** `auth.users`, `profiles`, `device_tokens` all 0 — each checked independently, because the Edge Function deletes in order and only the final step is fatal, so a partial failure would still report success. **Retained:** the group, expense and split all survive with `created_by`/`paid_by` nulled and `splits.user_id` preserved — migrations 017 and 035 doing their job, which is the retention claim the review notes make to Apple. |
| RT-01 | `xBill/Views/Main/HomeView.swift:46` | **Realtime never started.** `startRealtimeUpdates()` begins `guard let currentUser else { return }`, and its only call site was a bare `.task`, which races the auth listener on cold launch and usually wins — auth is a network round-trip. The guard returned and nothing retried, because a bare `.task` does not re-run when `currentUser` later arrives. Realtime was dead for the whole session, invisibly: pull-to-refresh and `MainTabView`'s foreground reload mask it entirely, so the app appears to update, just never on its own. | ✅ Fixed | `.task(id: vm.currentUser?.id)` so the subscription starts when the user is known and restarts on account switch. Added `realtime.skipped` / `.subscribed` / `.event` diagnostics so it cannot fail silently again. **Device-verified 2026-08-04** — the log caught the defect in the act: `realtime.skipped reason=no current user` at 22:34:34, then `realtime.subscribed groups=1` 786 ms later once the fix re-fired, then `realtime.event` matching an inserted row to the second. |
| REL-03 | `RELEASE_VERIFICATION.md` §7 | Realtime had never been verified end to end. | ✅ Verified 2026-08-04 | Both subscriptions exercised against production with the device watching and no manual refresh: a `group_members` INSERT surfaced a new group in the Groups list, and a `comments` INSERT from another member surfaced live in an open expense detail. Uncovered RT-01 in the process. Test artifacts removed; Tokyo Trip restored to 0 comments on the affected expense. |
| TEST-01 | `xBillTests/PreNetworkGuardTests.swift` | **A unit test was writing to production.** `paddedDisplayNameIsTrimmed` set a display name and called `saveProfile`; `AuthService.updateProfile` writes using `currentUserID` from the **live session**, not the `vm.user.id` the test set — so every run renamed the real `xbill.uitest` profile to "Alice Chen". That corrupted the ledger UI fixture's rendering (payments read as `Alice Chen → Alice Chen`, which the `distinct_parties` CHECK makes impossible) and cost several runs chasing a selector problem that did not exist. `iouAdmitsEitherParty` had the same flaw, attempting a live `ious` insert; it failed harmlessly only because the party UUIDs violated a foreign key — luck, not design. | ✅ Fixed | Both tests removed; display name restored; verified a full 315-test run now leaves the profile untouched. **Gap closed the same day — see TEST-02.** |
| UIT-06 | `xBillUITests/RegressionUITests.swift` | The recorder-only delete gate — migration 041's `recorded_by = auth.uid()` DELETE policy — was device-only. Twelve gesture attempts failed. | ✅ Fixed (was ⚠️ Open) | Root cause: SwiftUI exposes these rows as **cells with no identifier and no label**, so every query found the inner `StaticText`, and a gesture there never reaches the cell that owns `.swipeActions`. Matching cell-to-row **by frame** works. A second defect surfaced in the helper: `List` *recycles* rows, so a row below the fold is absent from the accessibility tree rather than merely off-screen, and `scrollUntilHittable` guarded on `waitForExistence` so never scrolled to anything unrendered. `testPaymentDeleteGateRegression` now asserts both directions and never deletes. |
| AUTH-02 | `xBill/Views/Auth/EmailAuthView.swift` | **Signup would have dead-ended the moment email confirmation was enabled.** `AuthViewModel` sets `confirmationEmailSent` on `AppError.confirmationRequired`, and the "Check your email" banner renders in `AuthView` — but signup happens in `EmailAuthView`, which is *pushed on top*, and nothing popped it. The user would tap Create Account and see nothing: no error, no message, no navigation. Latent and untestable while autoconfirm was on, because `confirmationRequired` could never be thrown. Third instance of the same shape: feedback attached to the parent while the action happens on the pushed child (see AUTH-01 and the `GroupListView:89` note). | ✅ Fixed | `.onChange(of: vm.confirmationEmailSent)` dismisses back to `AuthView`, where the banner lives — which the banner's own copy ("…then sign in") shows was always the intent. Device-verified. |
| AUTH-03 | Supabase Auth configuration | Email confirmation was **off**, so any address could be registered by someone who did not own it — and email is this app's identity key for friend discovery (`lookup_profiles_by_email`, `search_profiles`) and group invites. | ✅ Enabled 2026-08-04 | Enabled only **after** proving the prerequisites, because turning it on blind would have locked out every new signup: (1) SMTP had never sent a confirmation — verified end to end via a password-reset delivery; (2) AUTH-02 above was fixed first. Verified by probing `/auth/v1/signup`: no session returned, `confirmation_sent_at` populated. Full device loop confirmed — banner → emailed link → app opens → auto signed in. Test accounts removed; 5 real accounts intact. |
| TEST-02 | `xBill/Services/IOUService.swift`, `xBill/ViewModels/ProfileViewModel.swift` | The coverage gap left by TEST-01: only the **rejection** direction of the M-25 and H-17 guards was tested, so a guard that refused *everything* would still have passed. Asserting the positive direction through `createIOU`/`saveProfile` was what wrote to production in the first place. | ✅ Fixed | Both guards **extracted as static pure functions** (`IOUService.validateParties`, `ProfileViewModel.validatedDisplayName`) rather than hidden behind injection seams — a seam still lets a careless test reach the network, a pure function cannot. Same principle as making `SettlementSuggestion.id` computed: make the mistake unrepresentable. Both directions now tested, plus one safe assertion that the guard is actually **wired in** (a pure function nothing calls protects nothing). **Verified to fail** against a guard rewritten to refuse everything — the exact failure the old tests could not see. A full 316-test run leaves production untouched: 5 profiles, 1 IOU, unchanged. |
| REL-04 | `project.yml` (app target), `xBill/Info.plist` | **App Store upload rejected — error 90474.** The bundle declared `UIDeviceFamily [1, 2]`, claiming iPad support the app was never designed or tested for, so App Store Connect applied iPad multitasking rules and demanded all four orientations. `project.yml` did set `TARGETED_DEVICE_FAMILY: "1"` in `settings.base`, but **xcodegen writes its own per-target default of `"1,2"` for an iOS application**, which overrides the project-level value; the widget targets set it explicitly and were unaffected. Separately, only `UISupportedInterfaceOrientations~iphone` was present — the validator requires the generic key. | ✅ Fixed | `TARGETED_DEVICE_FAMILY: "1"` pinned on the app target, and the generic orientation key added. Verified in the **built Release plist**: `UIDeviceFamily [1]`, `UISupportedInterfaceOrientations [Portrait]`. Taking the error text at face value and adding four orientations would have passed validation while shipping untested iPad support — a common rejection, since reviewers do open apps on iPad. `RELEASE_VERIFICATION.md` now checks the built plist before upload. |
| REL-05 | `xBill/Assets.xcassets/AppIcon.appiconset/*.png` | **App Store upload rejected — error 90717.** All 13 app icons carried an alpha channel, and the 1024px icon had fully transparent corners (~67px radius, 4.3% of pixels non-opaque). Apple forbids transparency in the large icon. | ✅ Fixed | Each icon composited onto its own background colour — sampled from the midpoint of its top edge, `rgb(60, 52, 137)` for all 13 — then written without alpha. Deliberately not flattened onto white: if a baked corner radius were ever *larger* than Apple's mask, white would show at the corners. Here the baked radius (6.5%) sits well inside Apple's ~22% mask, so the change is invisible in the rendered icon. Verified: no source PNG reports `hasAlpha: yes`, and the icons extracted from the built Release app are opaque. |
| REL-06 | `project.yml` (Release config) | **App Store upload rejected — archive contained no dSYM for `xBill.app`.** `DEBUG_INFORMATION_FORMAT: dwarf-with-dsym` and `GCC_GENERATE_DEBUGGING_SYMBOLS: NO` were both set on Release and contradict each other: with symbol generation off there is nothing to put in the dSYM. The `NO` was introduced by security finding **L4** as a hardening measure. | ✅ Fixed | `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` on Release. **L4's premise was wrong**: `STRIP_INSTALLED_PRODUCT = YES` already strips symbols from the shipped binary, and a `.dSYM` is a separate artefact never delivered to users — so the setting bought no security and cost symbolicated crash reports, meaning every production crash would have arrived as raw addresses. Verified by archiving: three dSYMs present and the binary's UUID identical to its dSYM's. |

---

## Settlements Ledger — Final Whole-Branch Review (branch `feat/settlements-ledger`, 2026-07-31)

Findings from the final review of the branch that replaces `splits.is_settled` with a
`public.settlements` ledger, fixed in one wave before the migration decision. **Nothing in this
section is deployed** — migration 041, the `notify-settlement` update and the app build ship
together, in that order.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| SL-C1 | `xBill/ViewModels/GroupViewModel.swift:203` | `load()` fetches members, expenses and settlements through one `try await` tuple, so a settlements-only outage throws the whole `do`. The catch restores members/expenses from cache and recomputes against an **empty** settlements array — every split counts as unpaid, the largest possible wrong number — while `balanceLoadFailed` (cleared before the fetch) was never restored. Settle Up therefore showed gross, pre-payment debt as authoritative, with a Record Payment button on each row. A user could pay a debt twice. `HomeViewModel` got this fix as IMP-2; `GroupViewModel` did not. | ✅ Fixed | `balanceLoadFailed = true` in the catch. Regression test `settlementsFetchFailureRaisesBalanceLoadFailed` asserts both the warning and that the figure shown really is the gross one; mutation-verified. |
| SL-I1 | `xBill/ViewModels/GroupViewModel.swift:648` | The local Activity note for a recorded payment was filed under `fromUserID`. `NotificationStore` keys are user-scoped; before this branch only the debtor could settle, so `fromUserID == recordedBy` always held. When the creditor records, the note landed in the debtor's bucket on the recorder's own device and the recorder saw no Activity entry. | ✅ Fixed | Scoped to `recordedBy`. |
| SL-I2 | `scripts/verify-settlements-backfill.sql` | The deploy gate could only run **after** the point of no return: the script reads `public.settlements`, so it needs the table, and creating the table permanently disarms the backfill's `NOT EXISTS` re-run guard. There is no rollback. | ✅ Fixed | New `scripts/preflight-settlements-backfill.sql` simulates the backfill in a CTE using the migration's own WHERE clause and references `public.settlements` nowhere, so it runs read-only against production before `db push`. The post-migration script gained a validity-window header saying it is meaningful only immediately after the backfill. |
| SL-I3 | both verification scripts | Both CTEs grouped by `user_id` alone, across every group and currency. A user whose balance rises by X in one group and falls by X in another compared equal and never surfaced — structurally the same masking bug as the `FULL OUTER JOIN` cross-product defect the script was already rewritten once to fix, moved up a level. | ✅ Fixed | Both scripts group by `(group_id, user_id)` and join on both. |
| SL-I4 | `xBill/ViewModels/GroupViewModel.swift:309-349` | `applyFetchedSettlements` used the fetch generation to expire pending local changes but never compared it against the last generation applied. `deletePayment` takes no `!isLoading` guard and its `defer` clears the flag while an earlier `load()` is still awaiting, so a second `load()` can start and return first; the earlier one's older snapshot was then applied wholesale on top. A payment recorded in between disappeared and the balance reverted to gross. | ✅ Fixed | `lastAppliedSettlementGeneration`; a response is applied only if strictly newer. Regression test `staleSettlementsResponseIsDiscarded`; mutation-verified. |
| SL-I5 | `supabase/migrations/041_settlements.sql` | `splits.amount` permits `0.00` (`CHECK (amount >= 0)`) while `settlements.amount` requires `> 0`. One settled zero-amount non-payer split would violate the CHECK and roll the **entire** migration back. | ✅ Fixed | `AND s.amount > 0` added to the backfill WHERE. A 0.00 split contributes 0 under both models, so nothing is lost. Confirmed read-only against production: zero splits of any kind have `amount = 0`, so this is insurance against future data. |
| SL-I6 | `xBillTests/SettlementLedgerTests.swift` | Design spec §8 requires a backfill-equivalence test "green before anything touches production". It was never written — the whole deployment rested on one SQL script that had already been wrong once. | ✅ Fixed | `BackfillEquivalenceTests`: asserts `netBalances(all splits − backfilled settlements) == netBalances(unsettled splits only)` over a fixture covering every branch of the migration's WHERE clause (payer's own settled share, fully settled expense, nothing settled, `paid_by` NULL, zero-amount settled share, uneven shares). Also pins both table CHECKs and proves the zero-amount guard load-bearing. |
| SL-D1 | `xBill/Services/ExpenseService.swift:180`, `:298`, `xBill/Services/GroupDataProviding.swift:23` | `settleSplit` / `SplitSettlePayload` / the protocol requirement wrote `splits.is_settled`, which nothing reads after migration 041. A future caller would get HTTP 200 and no change to any balance. | ✅ Fixed | All deleted, along with the now-unused `FakeExpenseService.failingSplitIDs` / `settledSplitIDs`. `Split.isSettled` documents that the column is legacy and points at `SettlementService.recordSettlement`. |
| SL-D2 | `CLAUDE.md` | The Settle Up trap-index row still said only the debtor may settle, and the `notify-settlement` File Map entry still documented the pre-branch payload and "pushes creditor (toUserID) only". Both false, and this file is the first thing the next agent reads. | ✅ Fixed | Both rewritten to the shipped behaviour; File Map entries added for the new files; `REV-01` annotated in place as closed-on-branch with the product decision that closed it. |
| SL-D3 | `xBill/ViewModels/GroupViewModel.swift`, `xBillTests/*` | Three comment overclaims (the branch's signature failure mode — five comment-vs-code mismatches over five rounds), plus a test whose name asserted a property the function under test explicitly disclaims. | ✅ Fixed | `deletePayment`'s "second tag is the load-bearing one", the `.deleted` case doc, and the `InterleavingGate` "never on a slow machine" claim all corrected. `directSettlementSuggestionsDoNotInventNetTransfers` renamed to `disjointPairsAreNotNettedTogether`. |

**Pre-flight result (production, read-only, 2026-07-31):** zero drift rows. `to_regclass('public.settlements')` is `NULL`, confirming the check genuinely runs before the table exists. Balances hold at App Reviewer **+4.40**, Alice Chen **−2.10**, Bob Patel **−2.30**, old model identical to new. Proven load-bearing by mutation: doubling the simulated backfill amount makes it report all three users.

**Verification:** 243 passed, 0 failed, 0 skipped (`xBillTests`, iPhone 17 / iOS 26.5). Release build succeeded.

---

## Open Items

| Item | Priority | Notes |
|---|---|---|
| App Store assets | P0 | Screenshots, preview video, keyword strategy — only remaining submission blocker. No code work required. |
| App Group registration | Setup | Register `group.com.vijaygoyal.xbill` in Apple Developer Portal → Identifiers → App Groups before widget data sharing will work on a device. |
| Apple JWT secret renewal | Maintenance | JWT secret for Sign in with Apple expires 2026-10-28. Regenerate before that date using `generate_apple_secret.js`. |

## ASO-01 — No App Store review prompt (2026-08-12)

| Field | Value |
|---|---|
| **ID** | ASO-01 |
| **File** | `xBill/Services/ReviewPromptService.swift` (new), `xBill/ViewModels/GroupViewModel.swift`, `xBill/Views/Groups/GroupDetailView.swift` |
| **Issue** | v1.0 shipped with no StoreKit integration at all, so the app could never ask for a rating. 0 ratings suppresses App Store search ranking and conversion, and without a prompt that state is self-perpetuating. |
| **Status** | ✅ Fixed |
| **Fix** | `ReviewPromptPolicy` (pure) decides; `ReviewPromptService` counts recorded settlements and raises `isRequestPending`; `GroupDetailView` calls `requestReview` after an 800 ms settle and only when App Lock is disengaged. Milestone 3, version-gated. |
| **Verification** | 324/324 unit tests, both new suites confirmed by name in the result bundle. Mutation-tested: 5 of 8 fail against an always-true policy. Debug build installed and launched on simulator. Display itself is unverifiable — StoreKit owns that decision. |

## CRASH-01 — Index-backed element bindings trap in SwiftUI's update pass (2026-08-12)

| Field | Value |
|---|---|
| **ID** | CRASH-01 |
| **File** | `xBill/Views/Expenses/AddExpenseView.swift`, `xBill/Views/Expenses/ReceiptReviewView.swift`, `xBill/ViewModels/AddExpenseViewModel.swift`, `xBill/ViewModels/ReceiptViewModel.swift` |
| **Issue** | Shipped 1.0 (1) crashed on device: `Array._checkSubscript` → `_assertionFailure` from `Switch.updateUIView` → `Binding.subscript.getter`. `ForEach($collection)` element bindings are index-backed and are read back during a deferred update pass. `ReceiptReviewView` carried the same construct with `.onDelete` shrinking the array. |
| **Status** | ✅ Fixed (crash site + sibling); root sequence in AddExpenseView unproven |
| **Fix** | Value iteration everywhere; all edits resolve by id through the model (`toggle`/`setAmount`/`adjustShares`/`input(for:)`, `updateName`). `.onDelete` maps offsets to ids before mutating. No `ForEach($` remains in the app. |
| **Verification** | 329/329 unit tests, suite confirmed by name. Mutation test (`?? 0` instead of `guard`) fails exactly the safety test and no other. Built artifact 1.1 (2) installed and launched. Crash itself was never reproducible — absence of a report is not proof. |

## TAP-01 — Hit region smaller than the painted button (2026-08-15)

| Field | Value |
|---|---|
| **ID** | TAP-01 |
| **File** | 13 files — `XBillButtons`, `XBillPageHeader`, `XBillFloatingAddButton`, `XBillDashboardPrimitives`, `XBillSegmentedControl`, `XBillProfileCard`, `XBillProfilePrimitives`, `XBillButton`, `GroupListView`, `AuthView`, `EmailAuthView`, `HomeView`, `AddIOUView`, `ProfileView`, `GroupSettingsView` |
| **Issue** | `.buttonStyle(.plain)` derives the hit region from the label's *content*. Full-width CTAs were tappable only on their centred text; icon buttons only on the glyph strokes. Affects every primary CTA, the back button, and group rows. Ships in 1.0 (1). |
| **Status** | ✅ Fixed (15 buttons); 9 lower-traffic files deliberately deferred pending individual review |
| **Verification** | Device-confirmed by the user on 5 controls. Unit 329/329; UI regression 18/18 with the previously-failing archive test green across two consecutive runs. |

## LIC-01 — Exchange rates used without required attribution (2026-08-16)

| Field | Value |
|---|---|
| **ID** | LIC-01 |
| **File** | `xBill/Services/ExchangeRateService.swift`, `xBill/Core/Constants/XBillURLs.swift`, `xBill/Views/Expenses/AddExpenseView.swift`, `xBill/Views/Profile/ProfileView.swift` |
| **Issue** | ExchangeRate-API's Open Access tier permits commercial use only with a "Rates By Exchange Rate API" backlink. The app displayed none. Live in v1.0. |
| **Status** | ✅ Fixed |
| **Fix** | Attribution beside the live conversion and permanently in the Profile footer; URL centralised in `XBillURLs` and commented as a licence condition. Stale "1500 req/month" comment corrected — the endpoint has no quota, only IP rate limiting. |
| **Verification** | Unit 329/329, UI 18/18. Wider licence audit found no other exposure: no bundled fonts, no third-party image assets, app icon is original art, all dependencies MIT/Apache-2.0. |

## WIDGET-01 — Widget framework linked but never embedded (2026-08-17)

| Field | Value |
|---|---|
| **ID** | WIDGET-01 |
| **File** | `project.yml` |
| **Issue** | `xBillWidgetCore.framework` was a dependency of the widget target only, so nothing embedded it. `xBill.app` shipped with no `Frameworks/` directory; the extension died in dyld on every launch and iOS drew a blank placeholder. Broken since 2026-07-15, shipped in v1.0. |
| **Status** | ✅ Fixed |
| **Fix** | The **app** target now embeds `xBillWidgetCore` — an extension resolves frameworks via the host app's `Frameworks/`. |
| **Verification** | Framework present and signed in the built bundle; device-confirmed the widget now renders. |

## WIDGET-02 — Named colours unresolvable inside the extension (2026-08-17)

| Field | Value |
|---|---|
| **ID** | WIDGET-02 |
| **File** | `xBillWidgetCore/xBillBalanceWidget.swift`, `xBillWidget/Assets.xcassets` (new) |
| **Issue** | `Color("MoneyPositive")` resolves against `Bundle.main` = the `.appex`, which had no `Assets.car`. Unresolvable colours render as clear, so the balance amount and header icon were drawn invisible. Introduced by defect fix L-43. |
| **Status** | ✅ Fixed |
| **Fix** | Widget target given its own asset catalog with copies of both colours; bundle-boundary constraint documented at the call site. |
| **Verification** | `assetutil` confirms both colours compiled into the `.appex`; device-confirmed the amount and icon now render. |

## TAP-01b — Four further dead tap targets (2026-08-17)

| Field | Value |
|---|---|
| **ID** | TAP-01b |
| **File** | `xBill/Views/Friends/FriendsView.swift`, `xBill/DesignSystem/Components/XBillIconPickerGrid.swift` |
| **Issue** | Friend-request accept/decline, friend-actions, and the icon-picker cell had hit regions smaller than their painted areas — the deferred remainder of TAP-01. Ships in v1.0. |
| **Status** | ✅ Fixed |
| **Fix** | Explicit `.contentShape(...)` on each. The other four deferred files were classified and are unaffected. |
| **Verification** | Unit 329/329, UI 18/18. |

## MINOR-01 — Silent APNs token-deletion failure (2026-08-17)

| Field | Value |
|---|---|
| **ID** | MINOR-01 |
| **File** | `xBill/Services/AuthService.swift`, `xBill/Views/Profile/ProfileView.swift`, `xBill/Views/Main/MainTabView.swift` |
| **Issue** | `try? await deleteDeviceTokens()` at 4 sites, including when notification permission is found revoked. A failed delete leaves the server holding a token for a user who denied notifications, who then keeps receiving pushes. |
| **Status** | ✅ Fixed |
| **Fix** | `deleteDeviceTokensReportingFailure()` catches and logs via `Logger`; all 4 call sites use it. |
| **Verification** | Unit 329/329, UI 18/18. |

## SPLIT-01/02/03 — Expense splits are frozen after creation (2026-08-23)

> IDs are `SPLIT-*`: `EXP-01/02/03` are already used above for the CSV-export findings.

| Field | Value |
|---|---|
| **ID** | SPLIT-01, SPLIT-02 (SPLIT-03 **withdrawn**) |
| **File** | `xBill/Views/Expenses/ExpenseDetailView.swift` (`saveEdit`), `xBill/Services/ExpenseService.swift` (`updateExpense`) |
| **Issue** | The only two `splits` operations in the app are `SELECT`; nothing rewrites them after `add_expense_with_splits`. (01) A member who joins later cannot be added to an existing expense. (02) Editing the amount updates `expenses.amount` but no splits, and balances derive from splits — so the correction appears to save and moves nothing. (03) **WITHDRAWN — this claim was wrong.** `netBalances` skips the payer's own split, so the split set is payer-independent and changing the payer inverts the credit correctly on its own. Verified by test before acting on it. |
| **Status** | ✅ Fixed — SPLIT-02 (Phase 1) and SPLIT-01 (Phase 2) both built; migration 043 deployed 2026-08-23 |
| **Fix** | One `update_expense_with_splits` RPC updating the expense and replacing splits in a single transaction. Amount changes **rescale proportionally** rather than re-splitting equally: the split strategy is not persisted, so equal re-splitting would silently destroy a deliberate 70/30. |
| **Verification** | Unit 441/441. Migration 043 verified against production (all three guards fail before any write; 0 rows touched). **Ships in 1.3** — 1.2 users still have SPLIT-02. Device check outstanding: add a late joiner to a real expense and watch both balances move. |

## PUSH-01/02 — Push notifications are not delivered (2026-08-25)

| Field | Value |
|---|---|
| **ID** | PUSH-01, PUSH-02 |
| **File** | `xBill/ViewModels/AddExpenseViewModel.swift:232`, `xBill/ViewModels/GroupViewModel.swift:789`, `xBill/Services/CommentService.swift:59`, all four `supabase/functions/notify-*/index.ts`, `public.device_tokens` |
| **Issue** | (01) The Profile toggle titled "New Expenses" gates whether **other people** are notified when **you** add an expense, not whether you are notified — and it defaults to `false`. The recipient's own preference is never consulted, and there is no server-side preference table to consult it in. Same for settlements and comments; friend requests are ungated. (02) `apnsHost` is chosen from `isDevelopment`, which is `#if DEBUG` on the **sender's** build, but sandbox-vs-production must match the **recipient's token**. `device_tokens` records no environment, so correct routing is impossible in principle. An App Store sender notifying a debug-build recipient gets `BadDeviceToken` silently — the normal case during testing. |
| **Status** | ✅ **Both fixed and DEPLOYED 2026-08-25.** PUSH-02 = Phase 1 (migration 048), PUSH-01 = Phase 2 (migration 049) — `docs/superpowers/specs/2026-08-25-push-notification-delivery-scope.md` |
| **Fix** | Phase 2 (done): migration 049 adds `public.notification_preferences` (four boolean columns, owner-only RLS, **all defaulting to true, and a missing row also means on** — iOS permission is the real consent gate). All four functions filter recipients through `recipientsAllowing()` in `_shared/apns.ts`; the three sender-side `if` statements are **deleted**, along with `enableDefaultPreferencesAfterPermissionIfNeeded` and the four `prefPush*` defaults registered as `false`. Profile's toggles write through to the server and revert if the write fails; Friend Requests gains the toggle it never had. Phase 1 (done): migration 048 adds `device_tokens.environment` (CHECK sandbox/production, existing rows default production); `AuthService.apnsEnvironment` writes it at registration, the one place `#if DEBUG` describes the binary whose entitlement is in question; new `supabase/functions/_shared/apns.ts` holds the routing rule once and all four functions send through it; `isDevelopment` deleted from every payload and every function. Phase 2 (not built): a server-side `notification_preferences` table filtered by the function, with the sender-side gates deleted. |
| **Verification** | Unit **483/483** (14 new across both phases), mutation-tested: renaming the `environment` key fails exactly the two payload tests and neither build-constant test. `scripts/check-apns-routing.sh` asserts the structural rule across all four functions and fires on three separate regressions. Debug + Release both build; installed and launched. **Deployed 2026-08-25**: migration list reads `048 \| 048 \| 048`, the column is `NOT NULL DEFAULT 'production'` with a live CHECK, all 4 existing rows read `production` and none were touched; all four functions ACTIVE, and `notify-friend-request` returns the new `{"sent":0,"failed":0,"reasons":{}}` shape while still refusing an anon caller with 401. Migration 049 verified live: RLS on, three owner-only policies, UPDATE carries `WITH CHECK`, all four columns default `true`, 0 rows. Against production as the UI-test user: an absent row reads `[]` (no `PGRST116`), a write lands, the exact query `recipientsAllowing()` runs returns `expenses=false`, another user's row is invisible and unwritable (`42501`), and anon sees nothing. **Two things remain unverified and neither can be reached from here:** that a notification arrives at all (APNs does not deliver to a simulator) and that a muted recipient is actually skipped (the only other token-holders are real people, so exercising it would notify them). Both need two accounts on two devices — one test covers both. |

## UIT-09 — the alphabetically first UI test absorbed the whole cold start (2026-08-26)

| Field | Value |
|---|---|
| **ID** | UIT-09 |
| **File** | `xBillUITests/RegressionUITests.swift` (`setUp`) |
| **Issue** | `RELEASE_VERIFICATION.md` requires erasing the simulator before a release UI run. Tests run alphabetically, so `testAddFriendStopsScrollingAtItsContentHeight` — first by name — absorbed the entire first-run cost: first launch, first network sign-in, the onboarding pages (`hasCompletedOnboarding` reset by the erase) and the notification permission sheet (`hasPromptedNotification` likewise). Every other test ran warm. It failed in **three different places across three runs** — `tapTab` finding no Friends tab, the Friends header never arriving, and the email auth form never appearing — because which wait expired first depended on timing. |
| **Status** | ✅ **Fixed 2026-08-26.** Full suite **22/22** on an erased simulator. |
| **Fix** | `absorbFirstRunIfNeeded()` in `setUp`, guarded by a static flag: launch, sign in, dismiss onboarding and the prompt, wait up to 30s for the Groups surface, terminate — all before any test asserts. Deliberately tolerant (`try?`), because a warm-up failure must not fail a test that is not testing it. |
| **Verification** | Mutation-tested: with the flag pre-set so absorption is skipped the test **fails** on an erased simulator; with it, **passes**. Both `tapTab` and the Friends assertion now dump the on-screen `staticTexts`/`buttons` on failure, so a recurrence names the screen instead of requiring inference. |
| **What found it** | **Ordering, not reasoning.** Four causes were proposed and disproved first: a permission sheet covering the tab bar, the DEBUG route harness having no tab bar, the Friends header sitting behind a loading branch, and plain slowness. The signal was that 21 of 22 passed and the failure was always the alphabetically first test. One wrong hypothesis came from counting occurrences of `"Not Now"` in a run log — those lines were the test **searching** for the button, not the button existing. Counting a search and calling it a sighting is the same error as reading a locally-set badge as proof of push delivery (`PUSH-04`). |

## PUSH-04 — APNs rejected every push as BadDeviceToken (2026-08-26)

| Field | Value |
|---|---|
| **ID** | PUSH-04 |
| **File** | `supabase/functions/_shared/apns.ts`, all four `notify-*` |
| **Issue** | With PUSH-01 and PUSH-02 both deployed, nothing still arrived. The badge and the Activity row that suggested partial success are written **before** APNs is contacted, so both were consistent with zero delivery. A `console.log` of the send report gave the answer in one line: `{"sent":0,"failed":1,"reasons":{"BadDeviceToken":1},"muted":0}`. `BadDeviceToken` means "not valid on **this** host" — the recorded environment was wrong, because migration 048 defaulted every pre-existing row to `production` while the owner's device was running a development-signed build. |
| **Status** | ✅ **Fixed and DEPLOYED 2026-08-26. Device-confirmed by the owner: "I saw the push on device."** |
| **Fix** | `deliver()` retries the other environment on `BadDeviceToken`. Success delivers the push **and** corrects `device_tokens.environment` in place, so every row that predates 048 self-heals on its next notification instead of waiting for that device to update. Rejection on both hosts reports `BadDeviceToken(both:<reason>)`, which rules the environment out rather than blaming it. The send report is now logged permanently. |
| **Verification** | The owner's row flipped `production` → `sandbox` — a write that only occurs on a successful retry — and the owner confirmed the notification on the device. `scripts/check-apns-routing.sh` extended to require `deliver()` by name and mutation-tested against a function bypassing it. |

## PUSH-03 — a second device silently unregisters the first (2026-08-25, found not fixed)

| Field | Value |
|---|---|
| **ID** | PUSH-03 |
| **File** | `xBill/Services/AuthService.swift:updateDeviceToken` |
| **Issue** | After upserting the current token, the method runs `DELETE FROM device_tokens WHERE user_id = ? AND token <> ?` — **every other token for that user**. A person with an iPhone and an iPad can only ever be reached on whichever they opened most recently, and nothing tells them. The comment justifies the ordering (insert before delete) but not the deletion itself. Production currently holds exactly one token for each of four users, which is consistent with this but does not prove it, since no user is known to have two devices. |
| **Status** | ✅ **Fixed 2026-08-25** at the owner's direction, in the same release as PUSH-02. Client-side only — no migration, no deploy. |
| **Fix** | The sibling delete is **gone**. Dead tokens are reaped by the only authority that knows — APNs answers `Unregistered` for an uninstalled app and `_shared/apns.ts` deletes on exactly that — so growth is bounded by real devices rather than by launches. `deleteDeviceTokens` (sign-out, revoked permission) is likewise scoped to `AuthService.lastRegisteredAPNsToken` instead of the whole user, which fixes the mirror defect: revoking notifications on a tablet used to unregister the phone. |
| **The fallback** | If this install has never observed its own token — upgraded into this version and signed out before registering — cleanup falls back to the old user-wide delete. Leaving a token behind means someone who revoked notifications keeps receiving them (`MINOR-01`), which is worse than unregistering a sibling that re-registers on its next launch. `cleanupScope(lastRegistered:)` is a pure function so that choice is asserted in both directions. |

## SCAN-01/02/03 — Receipt scanning: sign, confidence, per-item flags (2026-08-18)

| Field | Value |
|---|---|
| **ID** | SCAN-01, SCAN-02, SCAN-03 |
| **File** | `xBill/Services/VisionService.swift`, `xBill/Models/Receipt.swift`, `xBill/Views/Expenses/ReceiptReviewView.swift` |
| **Issue** | (01) `extractDecimal` had no minus in its pattern, so a `-2.00` discount became a **+2.00 item** and the item sum ran high by twice the discount. (02) Tier 2 confidence was the constant `0.75`/`0.55` while real per-line OCR confidence was captured and never read. (03) No way to tell which rows were badly read. |
| **Status** | ✅ Fixed |
| **Fix** | Sign-aware extraction incl. trailing and Unicode minus, plus keyword detection; discounts flow through as negative items. `aggregateConfidence` uses the mean of the weakest half of line confidences. `ReceiptItem.confidence` drives a review-screen flag below 0.5. |
| **Verification** | Unit 346/346, UI 18/18. Two mutants: discarding the sign fails 2 tests, restoring the constant fails 4. One test (`warningPenalises`) was found to pass against the constant and was strengthened. |

## SCAN-04 — Reconciliation threshold excluded real OCR errors (2026-08-18)

| Field | Value |
|---|---|
| **ID** | SCAN-04 |
| **File** | `xBill/Services/VisionService.swift` |
| **Issue** | `reconcile` only attempted a repair when `|delta| ≤ $2.00`. A single misread digit produces a *large* delta (`18.99`→`78.99` = $60), so the cap refused precisely the cases it existed to fix. It also took the **first** substitution that closed the gap, silently guessing when several were possible. |
| **Status** | ✅ Fixed |
| **Fix** | Magnitude cap removed. A substitution is applied only when **exactly one** closes the gap; ambiguity leaves the warning for the user. An interim `\|delta\| ≤ total` bound was tried, caught by a test as both wrong and unfireable, and removed. |
| **Verification** | Unit 353/353 (6 new), UI 18/18. Mutation: reverting to first-match fails exactly `ambiguousCorrectionIsRefused`. |

## SCAN-06 — The name/price column split was a hardcoded x-position (2026-08-19)

| Field | Value |
|---|---|
| **ID** | SCAN-06 |
| **File** | `xBill/Services/VisionService.swift` |
| **Issue** | `parseWithHeuristics` split every row into name/price at a fixed `midX < 0.55`. A receipt knows nothing about that constant and it fails in both directions: prices sitting **left** of 0.55 land in the name column, so `leftText` is non-empty, `stripPrice` never runs, and the item is named `"Coffee 3.50"`; an item name reaching **past** 0.55 lands in the price column, so the name truncates to whatever fell left of it (`"Chicken Sandwich"` → `"Chicken"`). Both produce a wrong review screen from a correct OCR pass. |
| **Status** | ✅ Fixed |
| **Fix** | `detectPriceColumnBoundary(rows:)` measures the boundary from the receipt's own geometry, exploiting the fact that prices are **right-aligned**: the rightmost element of each multi-element, non-metadata row is the price, and the left edge of that cluster is the boundary. Three guards, each proven to fire by a test: fewer than 2 samples → fall back to the old constant; spread > 0.30 → the candidates are not one column, discard; result floored at 0.35. A 0.08 margin absorbs the centre shift between a narrow and a wide amount under right-alignment. |
| **Verification** | Unit **369/369**, 0 failed / 0 skipped. Mutation-tested by construction: the detector was landed with the call site still on `0.55`, and **exactly** the 2 behavioural tests failed while all 5 measurement tests passed. **Not measured on real receipts** — no corpus exists, so the real-world effect is unquantified. |

## SCAN-05 — Receipt assignment was per-item only (2026-08-19)

| Field | Value |
|---|---|
| **ID** | SCAN-05, SCAN-05b |
| **File** | `xBill/ViewModels/ReceiptViewModel.swift`, `xBill/Views/Expenses/ReceiptReviewView.swift`, `xBill/Views/Expenses/ReceiptScanView.swift`, `xBill/Views/Expenses/AddExpenseView.swift` |
| **Issue** | (05) No receipt-level assignment: "everyone shares everything" cost one tap per line, so users abandoned the review screen and split the total evenly. (05b) On device "Just me" never appeared — `currentUserID` was nil while `members` was populated, because `members` had two writers and `currentUserID` only one. |
| **Status** | ✅ Fixed |
| **Fix** | `Everyone` / `Just me` / `Clear` bulk actions that replace rather than merge; `allItemsAssigned` exact-matches; "Just me" hidden for non-members. `startManually` now carries `currentUserID` instead of relying on `.onAppear`. |
| **Verification** | Unit 362/362, UI 18/18, device-confirmed. Root cause of the original nil not established — the instrumentation postdated the failing build. |

## CONC-01/02 — Two people editing one expense overwrote each other (2026-08-31)

Branch `worktree-expense-optimistic-concurrency`. **Migration 051 is DEPLOYED (2026-08-31) and
verified live in both directions without writing. The client half is complete, green and
UNRELEASED — `p_expected_updated_at DEFAULT NULL` means no shipped build sends a token, so no live
user is protected yet.** Plan and spec:
`docs/superpowers/plans/2026-08-29-expense-optimistic-concurrency.md`.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| CONC-01 | `supabase/migrations/051_expense_concurrency.sql`, `xBill/Models/Expense.swift`, `xBill/Services/ExpenseService.swift`, `xBill/Core/AppError.swift`, `xBill/Views/Expenses/ExpenseDetailView.swift` | `expenses.updated_at` was added by migration 043 on 2026-08-23 and **read by nothing**. Two people editing the same expense silently overwrote each other — last write wins, no conflict, no warning, and what is overwritten is money. Listed as unpaid debt in every release note since 1.2. | ⚠️ **Server deployed 2026-08-31; client fixed on branch, unreleased** | Compare-and-swap inside `update_expense_with_splits`: the client sends the `updated_at` it loaded as `p_expected_updated_at`; the RPC updates only if the row still carries it and raises SQLSTATE `XB409` otherwise. `AppError.isEditConflict` matches the structured `PostgrestError.code`, never message text. `ExpenseDetailView` refuses and reloads, naming the editor from `updated_by`. |
| CONC-02 | `xBill/ViewModels/GroupViewModel.swift`, `xBill/Services/ExpenseService.swift`, `xBill/Services/GroupDataProviding.swift`, `xBill/Views/Groups/GroupDetailView.swift` | **Found during design, not reported.** `GroupViewModel.updateExpense` wrote the expense a *second* time after `update_expense_with_splits` had already saved it. `.update(expense)` is a whole-struct write, so it sent the client's **stale `updated_at` back into the row** — undoing the guard microseconds after it passed. A wasted round-trip before CONC-01; a hole in the guard after it. | ✅ Fixed (client-only, no deploy needed) | **Deleted**, not guarded. `ExpenseService.updateExpense` was the only server-bound whole-struct `Expense` write in the app, so removing it — and the `ExpenseDataProviding` requirement — makes the clobber unrepresentable. Replaced by `GroupViewModel.applySavedExpense`, which swaps the row in place and recomputes. `grep -rn "updateExpense("` over `xBill/` and `xBillTests/` returns nothing. |

### Design decisions worth not re-deriving

| Decision | Why |
|---|---|
| The token is an opaque `String?`, never a `Date` | `timestamptz` is microsecond precision; `Date` is a `Double` of seconds. Round-tripping rounds the value, so `updated_at = p_expected_updated_at` fails against a row nobody touched and **every** save reports a phantom conflict. A guard that fires constantly teaches people to ignore it. `ExpenseTokenTests` fails if anyone converts it. |
| Optional, not required | `CacheService` holds entries written before the key existed; a non-optional fails to decode every one — the `splits.is_settled` failure in miniature, on our own cache. |
| A nil token forces a re-read | Nil means "skip the check" *to the server* — correct for 1.0–1.5, wrong here, because a nil can come from a pre-upgrade cache entry and the first edit after upgrading is the likeliest to race. |
| `p_expected_updated_at DEFAULT NULL` | The compatibility hinge: 1.0–1.5 send 8 keys, resolve to the same function, and keep working. **They also remain able to clobber**, which cannot be fixed without breaking them. |
| `applySavedExpense` still fetches | The plan asserted zero fetches, copied from the payment paths, and the test failed — correctly. The RPC DELETEs and re-INSERTs the splits, so `splitsMap` is stale and recomputing from it shows the new amount against old shares (SPLIT-02 again). A settlement cannot change a split; an edit always does. Only the *write* was ever the problem. |

### Verification

| Check | Result |
|---|---|
| Unit | **493 passed, 0 failed, 0 skipped** (`TestResults/Coverage/2026.08.31_19-36-01-unit.xcresult`), baseline 487 |
| Suites by name | `Expense concurrency token`, `Edit-conflict error mapping`, `Applying a saved expense` — all three confirmed in the result bundle, not inferred from exit status |
| Mutation test | `isEditConflict` forced to `return true` fails **exactly** `neighbouringCodeDoesNotMatch` and `messageAloneIsNotAConflict` (490 total, 488 passed, 2 failed); `exactCodeMatches` correctly still passes |
| Builds | Debug and Release both clean; installed and launched on the simulator |
| Deploy | Migration 051 applied 2026-08-31. `051 \| 051 \| 051`; `null_tokens = 0`; column `NOT NULL DEFAULT now()`; **1** overload (9-arg, no H-11 orphan); `anon_exec = false`, `auth_exec = true`; 62 expenses / 82 splits unchanged. Preflight (read-only) recorded 60 of 62 rows to backfill and **0** null `created_at`, so `SET NOT NULL` could not abort. |
| Guard, proven live | Both directions, **zero bytes written** — each probe ran in a `DO` block whose closing `RAISE` rolls it back, because the plan's bare `SELECT` would have modified a real expense had the guard been broken. Stale token → `XB409`; the row's real token → **accepted**, so no phantom conflict and the microsecond round-trip holds. Probed row byte-identical afterwards; `title LIKE 'PROBE%'` → 0 rows. |
| **Not verified** | **No shipped client sends a token**, so the guard protects nobody until the client half ships — that is `DEFAULT NULL` working as designed. ✅ **The Swift path now round-trips against production** — `testExpenseEditSendsConcurrencyTokenRegression` edits 42.50 → 55.25 and passes; confirmed in the data (`updated_by` populated, `updated_at` advanced, against an unedited control row), then purged. **No two-device race was exercised.** **Clients on 1.0–1.5 can still clobber**, by design, until they update. |

## PURGE-01/02 — UI-test data could not be purged, and `anon` could purge anyone's (2026-08-31)

Found by checking production row counts after a full `RegressionUITests` run instead of trusting the script's own "cleanup verified" line — the script reported clean while `expenses` had gone 62 → 63.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| PURGE-01 | `supabase/migrations/039_purge_ui_test_groups.sql` | Three prefixes the UI suite creates — `PaymentReturn`, `ScrollProbe`, `Validation` — were never in `allowed_prefixes`. The function *rejects* them ("Unsupported test group prefix(es)"), so the cleanup script could not be asked to remove them even explicitly. They accumulated in production: **37** `PaymentReturn` groups since 2026-07-27 carrying 37 expenses and 37 splits, and **14** `ScrollProbe` groups since 2026-08-24. The script's "cleanup verified" line was misleading: it only looks at prefixes it is allowed to look at. | ✅ Fixed + deployed (052) | Both prefix lists extended. The list is now enumerated from the test target rather than guessed — `grep -rhoE 'uniqueName\(prefix: "[^"]+"\)' xBillUITests/*.swift` — and that command is recorded in the migration header and a `COMMENT ON FUNCTION`. **51 orphaned groups purged**; production went 63 → 26 expenses, 83 → 46 splits. |
| PURGE-02 | `supabase/migrations/039_purge_ui_test_groups.sql` | **`anon` held EXECUTE on a `SECURITY DEFINER` function whose ownership guard is skipped for anonymous callers.** The guard reads `IF caller_id IS NOT NULL AND effective_created_by <> caller_id` — `auth.uid()` is NULL for `anon`, so it never fires. An unauthenticated caller holding the public anon key could pass `p_created_by => '<any user id>', p_execute => true` and delete that user's groups matching an approved prefix, cascading to expenses, splits, comments and members. 039's `REVOKE … FROM PUBLIC` reads as a lock and is not one (rule 12): Supabase's `ALTER DEFAULT PRIVILEGES` grants `anon` EXECUTE explicitly, and revoking from `PUBLIC` does not remove an explicit grant. | ✅ Fixed + deployed (052) | `REVOKE EXECUTE … FROM anon` **by name**. Proven live, read-only, before and after: an anonymous dry-run POST returned **HTTP 200** before and **HTTP 401 / `42501 permission denied`** after. The NULL-caller path is kept deliberately — `scripts/purge-ui-test-groups.sh` connects on a privileged connection where `auth.uid()` is NULL — and was re-verified working after the revoke. |

**Follow-up worth doing:** every other `SECURITY DEFINER` function in this schema deserves the same `has_function_privilege('anon', …)` check. This one was found by accident, not by a sweep, and I have not run that sweep — so no claim is made about the others.

## SECDEF-01/02 — `SECURITY DEFINER` sweep (2026-08-31)

Prompted by PURGE-02. All 20 `SECURITY DEFINER` functions in `public` were checked for `anon` EXECUTE; **17 were anon-executable**.

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| SECDEF-01 | `supabase/migrations/053_profile_lookup_anon_guards.sql` | `search_profiles` and `lookup_profiles_by_email` are `SECURITY DEFINER` — they bypass RLS on `profiles` by design — and both were `anon`-executable. Probed live: **HTTP 200, 0 rows**. The 0 rows come from `WHERE p.id != auth.uid()`, which for an anonymous caller is `id != NULL` → NULL → never true. **The security boundary was SQL three-valued logic, and nothing said so** — the `!=` reads as "exclude my own row". `IS DISTINCT FROM`, `OR auth.uid() IS NULL`, or a `COALESCE` default would each turn it into an unauthenticated enumeration oracle over every display name and avatar; `lookup_profiles_by_email` also answers "is this email an xBill user?". | ✅ Fixed + deployed (053) | Explicit `IF auth.uid() IS NULL THEN RAISE … USING ERRCODE = '42501'` **and** `REVOKE … FROM anon` by name — two independent layers. Signed-in behaviour byte-identical (same rows, 2-char minimum, `LIMIT 20`). Verified: anon **200 → 401/42501**; the `RAISE` fires for a NULL privileged caller; `testFriendsAddSearchRegression` still passes. |
| SECDEF-02 | `supabase/migrations/054_drop_stale_rpc_overloads.sql` | **H-11, third occurrence.** `add_expense_with_splits` had 9-arg **and** 13-arg overloads live; `create_recurring_expense_instance` had 1-arg **and** 3-arg. 013 changed an argument list with `CREATE OR REPLACE`, which creates a second overload instead of replacing — the original H-11 incident. 027 dropped *a* stale overload and `CLAUDE.md` has read as though that closed it ever since. | ✅ Fixed + deployed (054) | Both orphans dropped by explicit signature. Reachability verified rather than assumed: the client's `recurrence` is a non-optional `String` present in every request since `e008977` (2026-04-13, ancestor of the 1.1 bump → every shipped build), and the 9-arg has no `p_recurrence`; the 3-key recurring payload dates from `e9be353` (2026-06-15) and the 1-arg has no defaults. Latent, not live. After: 1 overload each, survivors 13-arg/3-arg; expense-create and expense-edit UI tests pass. |

### Checked and cleared, so the next sweep need not redo it
- `add_or_reactivate_group_member`, `deactivate_group_member` — take explicit ids but open with `IF auth.uid() IS NULL THEN RAISE EXCEPTION 'unauthenticated'`. Correctly guarded.
- `get_invite_preview` — intentionally anon-callable; possession of the token is the capability.
- `is_group_member` / `is_expense_group_member` — return false for a NULL caller.
- `handle_new_user`, `set_group_member_snapshot` — trigger functions; not meaningfully callable out of context.
- `get_add_friend_preview`, `join_group_via_invite`, `purge_ui_test_groups` — `anon` already revoked (047, 044, 052).

### Still open
`AddExpenseParams` uses Swift's **synthesized** `Encodable`, which omits nils — the SPLIT-04 shape. It is harmless today only because the 13-arg RPC defaults all eight optional parameters. `UpdateExpenseParams` was hand-written to fix exactly this; the create path never was. Not changed here.

## ICON-01…10 — Iconography audit (2026-09-01)

Read-only pass over every `Image(systemName:)` (47 uses, 27 unique symbols), the category/group
icon components, and the App Icon asset. **Nothing fixed — this is the finding list.**

| ID | File | Issue | Status | Fix |
|---|---|---|---|---|
| ICON-01 | `xBill/DesignSystem/Components/XBillVisualAssets.swift:177` vs `xBill/Models/Expense.swift:75` | **Three category-icon vocabularies exist and the fixed one is not the one that ships.** `Expense.Category.symbolName` (DesignSystem) is what `XBillCategoryIcon` renders, and it reaches four everyday surfaces — expense rows, notification rows, Add Expense category chips, Group Details filter chips. `Expense.Category.systemImage` (Models) is rendered from **one** place, `ReceiptReviewView.swift:243`. Commit `1eed83e` (2026-08-16) — *"Fix three colliding or misleading category icons"* — landed on `systemImage`, so the defects it fixed are **still live everywhere users actually look**: `symbolName` still maps `.accommodation → "house.fill"`, which is the Home tab's glyph (`MainTabView.swift:40`) — the exact collision `Expense.swift:79` carries a comment forbidding. It also uses `"sparkles"` for `.other`, which since iOS 18 reads as Apple Intelligence, and narrows `.transport` to `"airplane"` and `.entertainment` to `"popcorn.fill"`. A third vocabulary, `Expense.Category.emoji` (`CategoryIconView.swift:11`), is **dead** — zero call sites. `NATIVE_PATTERNS.md:159` documents a **fourth** table (`car.fill`, `theatermasks.fill`, `cross.fill`, `ellipsis.circle.fill`) matching none of them. | ✅ Fixed | Delete `symbolName` and `emoji`; point `XBillCategoryIcon` at `Expense.Category.systemImage`, the one with the reasoning in comments. Then correct `NATIVE_PATTERNS.md:159` to match, or delete that table and cite the enum. One vocabulary, defined next to the model it describes. |
| ICON-02 | `XBillVisualAssets.swift:113` | **Every category icon fails the 3:1 non-text contrast minimum in dark mode.** The glyph is hardcoded `.foregroundStyle(AppColors.primary)` (`#6C35FF`) over `category.categoryBackground.opacity(0.9)` — but the `Cat*` colorsets carry **dark appearance variants** that go dark while the glyph does not move. Computed ratios: `.accommodation` **2.47:1**, `.transport` **2.41:1**, `.food` **2.47:1** — the whole set lands 2.4–2.5:1. Light mode is fine (≈5.1:1) because those variants are pale tints, which is why this reads as correct in every screenshot taken in light mode. | ✅ Fixed | Derive the glyph colour from the swatch instead of pinning it: either a per-category foreground token beside each `Cat*` colorset, or `AppColors.textPrimary` over the tint. Verify by computing the ratio in both appearances, not by looking at it. |
| ICON-03 ⬜ | `xBill/Assets.xcassets/AppIcon.appiconset/Contents.json` | **CONFIRMED 2026-09-11, see the note below the table.** **No dark or tinted app-icon variants**, and no Icon Composer `.icon`. `grep -c appearances` → **0**. On iOS 18+ the home screen's Dark and Tinted modes fall back to the light artwork; on iOS 26 the icon gets none of the Liquid Glass layering. The art is a white receipt on `#3B3287` — high-contrast in light mode and conspicuously wrong beside tinted neighbours. | ⬜ Open | Add `luminosity: dark` and `tinted` entries. For iOS 26, rebuild as an Icon Composer `.icon` with separated layers (card, ruled lines, avatar row) so the system composes all four appearances from one source. |
| ICON-04 | `xBill/Assets.xcassets/AppIcon.appiconset/Icon-1024.png` | **The artwork carries more detail than the size it is used at can render.** At the 60pt home-screen size the receipt is ≈26pt wide, its four ruled lines are sub-pixel, and the three avatar circles hold two-letter initials (`AL`/`MR`/`JT`) that resolve to smudges. Legible only at 1024. | ⬜ Open | Reduce to one idea that survives 60pt — the receipt card with a single fold, or the split chevron alone. Check by rendering to 60×60 and 40×40 and looking at those, not at the 1024. |
| ICON-05 | `Assets/` (repo root) | **A second, divergent, dead App Icon set.** `project.yml:41` bundles only `xBill/**/*.xcassets`, so this copy ships nowhere — but all 15 PNGs **differ** from the shipping set, and this copy has **corner radii baked into the artwork**, which iOS would mask a second time. It also holds two files the real set lacks (`Icon-20@1x`, `Icon-40@1x`). An edit here changes nothing and looks like it worked. | ✅ Fixed | Delete `Assets/`. While there: the shipping set is the legacy 15-size list; since Xcode 14 a single 1024 `universal` entry is enough, and collapsing it removes 14 files that can drift. |
| ICON-06 | app-wide | **`symbolRenderingMode` is used zero times; `symbolVariant` zero; `imageScale` zero.** `NATIVE_PATTERNS.md:134` requires hierarchical or palette rendering and `:157` requires `.symbolVariant(.fill)` on selected state — neither rule is applied anywhere. Every symbol renders flat monochrome, so multi-layer glyphs (`bell.badge.fill`, `person.badge.plus.fill`, `envelope.badge.fill`) lose the depth cue their badge layer exists to provide. Separately, **17** symbols are sized with fixed `.font(.system(size:))` against **12** on text styles; the fixed ones do not scale with Dynamic Type. Two are 13pt inline icons sitting beside scaling `Text` (`ForgotPasswordView.swift:89`, `:226`), so they shrink relative to their own label as the user enlarges type. | 🟡 Partly fixed | Apply `.symbolRenderingMode(.hierarchical)` at the component level (`XBillActionRow`, `XBillNotificationRow`, `XBillSettingsRow`) rather than per call site. Move the two inline 13pt icons to `.font(.xbillCaption)`; leave the large decorative hero glyphs fixed. |
| ICON-07 | `XBillIconPickerGrid.swift:26`, + 6 render sites | **A group's identity emoji is rendered three different ways, and its picker runs through the avatar-initials component.** `XBillGroupCard.swift:24`, `GroupDetailView.swift:416` and `GroupChipView.swift:16` draw it via `XBillAvatarPlaceholder(name:)` — a view whose job is to compute *initials* (`.split(separator:).prefix(2).first`) and which applies `.foregroundStyle` that an emoji glyph ignores. `GroupInviteView.swift:71`, `QuickAddExpenseSheet.swift:70` and `FriendsView.swift:448` draw the same value as bare `Text`. The picker itself feeds emoji into that initials component, so it works by coincidence rather than intent. | ⬜ Open | Add an `XBillGroupGlyph(emoji:size:)` and route all six sites plus the picker through it. Leave `XBillAvatarPlaceholder` to initials. |
| ICON-08 | `SplitParticipantRow.swift:98,109`; `GroupInviteView.swift:57`; `AddIOUView.swift:168` | **Three icon-only buttons carry no `accessibilityLabel`**, against `NATIVE_PATTERNS.md:582`. VoiceOver announces the raw symbol name: *"minus circle fill, button"* for the shares steppers, *"arrow clockwise"* for regenerate-invite, *"xmark circle fill"* for clear-selected-friend. The steppers have `accessibilityIdentifier` — a test contract, not a label — which is why they read as covered. The rest of the app is clean: `FriendsView`'s accept/decline, the FAB and the overflow menus are all labelled. | ✅ Fixed | Four `.accessibilityLabel` lines. For the steppers use value-bearing text (*"Decrease shares for \(name)"*). |
| ICON-09 | `ExpenseFilterChip.swift:15`, `AddExpenseView.swift:401` | Two byte-similar icon+label capsule chips, neither announcing selection. Both build `HStack { XBillCategoryIcon; Text }` in a capsule with a `brandPrimary` stroke when selected, and **neither adds `.accessibilityAddTraits(.isSelected)`** — VoiceOver reads "Food & Drink, button" whether the filter is on or off, so the selected state is visible only to sighted users. | ✅ Fixed | One `XBillCategoryChip`, with the trait. Same argument as `SplitParticipantRow`: two copies of one chip is how the edit sheet came to be missing three of four split inputs (SPLIT-05). |
| ICON-10 | `XBillVisualAssets.swift:105-118` | `XBillCategoryIcon` layers two `RoundedRectangle`s where the first is 90% hidden by the second, and sizes its glyph at a fixed `size * 0.42` so it never scales with Dynamic Type. Minor, but it is the component behind ICON-01 and ICON-02 and worth tidying in the same pass. | 🟡 Partly fixed | Drop the redundant `surfaceSoft` layer; size the glyph off a text style with `.imageScale`. |

**Not a finding, recorded so the next pass skips it:** the five tab-bar symbols are correct and collision-free (`house.fill`, `person.3.fill`, `person.2.fill`, `bell.fill`, `person.crop.circle.fill`); the 1024 icon has **no alpha channel** (`sips` → `hasAlpha: no`), so it will not trip App Store upload validation; the widget has no `AppIcon` set, which is correct — a widget extension inherits the host app's icon.

### ICON pass 1 — what actually changed (2026-09-01)

| | |
|---|---|
| **ICON-01 ✅** | `Expense.Category.symbolName` and `Expense.Category.emoji` **deleted**. `XBillCategoryIcon` now reads `Expense.Category.systemImage` — one vocabulary, beside the model. A comment block where `symbolName` stood records why, so it is not reintroduced. |
| **ICON-02 ✅** | New `AppColors.categoryGlyph = adaptive(light: "#6C35FF", dark: "#B79CFF")`. Dark mode goes **2.34–2.50:1 → 6.01–6.41:1**; light mode is byte-identical (5.05–5.26:1). |
| **ICON-06 🟡** | `xbillSymbol()` / `xbillSymbol(palette:_:)` added in `DesignSystem/Components/XBillSymbol.swift` and adopted by `XBillCategoryIcon`, `XBillActionRow`, `XBillArchivedRow`, `XBillNotificationRow` (×3) and `XBillProfilePrimitives` (×2) — 8 sites. **Still open:** `symbolVariant`, `symbolEffect`, and the 17 fixed-point-size symbols. |
| **ICON-10 🟡** | The redundant `surfaceSoft` layer under the 0.9-opacity swatch is gone. **Still open:** the glyph is still sized `size * 0.42`, so it does not scale with Dynamic Type — changing that moves chip-row layout and belongs in its own pass. |

**Verification.** Unit **505 passed, 0 failed, 0 skipped**
(`TestResults/Coverage/2026.09.01_22-3*-unit.xcresult`), baseline 493; both new suites confirmed
**by name** in the result bundle. Debug **and** Release both build; installed and launched on the
iPhone 17 Pro **iOS 26.4** simulator (`D6EB3CD2…`), not the 26.2 device named in `CLAUDE.md`.

**Mutation-tested, and the result is exact.** Restoring both defects — `.accommodation → house.fill`,
`.other → sparkles`, and `categoryGlyph = primary` — fails **exactly 3** tests:
`glyphIsLegibleOnItsSwatch` (all 8 category arguments), `noReservedGlyphs`, `noTabBarCollision`.
The four that should be independent of the mutants — `symbolsAreUnique`, `symbolsAreNonEmpty`,
`measurementRejectsThePreFixColour`, `lightModeStillUsesPrimary` — correctly still pass.

⚠️ **A `grep -cE '^Test case.*failed'` over the restored run returned 7 while the result bundle
returned 0.** Seven *passing* tests have "failed" in their names (`failedArchiveDoesNotLie`,
`failedFetchIsQuiet`, `failedLoadKeepsStoredItems`, `failedWriteRollsBack`,
`failedInsertIsReported`, `failedDeleteRestoresInPlace`, `failedDeleteRollsBack`). This is the
counting trap already recorded for 2026-08-31 in `CLAUDE.md`, reproduced in a new form — grep the
*output*, get a fabricated number. Read `xcresulttool get test-results summary`.

**NOT verified.** The changed components were never seen on a signed-in screen. `XBillCategoryIcon`
is reachable only past auth, the single UI regression test driving it exceeded a 10-minute budget
and was killed, and the app as launched sits on `AuthView`. What *was* checked visually is a
contact sheet rendering the eight `systemImage` glyphs against the real `Cat*` swatch values in
all three states — correct glyphs, no `house.fill`, no `sparkles`, and the dark-mode difference
plainly visible. The colour claim rests on the unit tests, which resolve the actual `UIColor` in
both trait collections and are stronger evidence than a screenshot. **A device or simulator look at
the Add Expense category chips in dark mode is still owed.**

## SECDEF-03 — anon-EXECUTE sweep, run from the runbook (2026-09-03)

The `has_function_privilege('anon', …)` check recommended after `PURGE-02` is now **in**
`RELEASE_VERIFICATION.md` §1, and running it during 1.6 prep produced its first result.

**13 of 18** `SECURITY DEFINER` functions in `public` are anon-executable. That is not itself a
defect — Supabase grants `anon` EXECUTE explicitly on every new function in `public`, and a
`REVOKE … FROM PUBLIC` does not remove it — but each one needs a reason.

| Function | Covered by the 2026-08-31 sweep? | Verdict |
|---|---|---|
| `get_invite_preview` | yes | deliberately public — the token is the capability |
| `is_group_member`, `is_expense_group_member` | yes | return false for a NULL caller |
| `handle_new_user`, `set_group_member_snapshot` | yes | trigger functions |
| `add_or_reactivate_group_member`, `deactivate_group_member` | yes | explicit `auth.uid() IS NULL` RAISE |
| `create_recurring_expense_instance` | **no** | ✅ **checked here.** Uses `auth.uid()` *nowhere*, which looks alarming, but its `UPDATE … WHERE public.is_group_member(group_id)` matches zero rows for an anonymous caller and it returns NULL at `IF NOT FOUND`. **Fails closed.** |
| `add_expense_with_splits`, `block_user`, `create_group_with_member`, `respond_to_friend_request`, `send_friend_request` | **no** | ⬜ **NOT verified.** All five reference `auth.uid()` and none has an explicit `auth.uid() IS NULL` guard. Probably fail closed the way the others do — but "probably" is exactly the word that preceded `SECDEF-01`. |

**Not a 1.6 blocker** — nothing here is newly introduced, and no exploit is demonstrated. But the
last five deserve the same treatment the first eight got, and the pattern is now familiar enough to
name: **in this schema, safety keeps resting on a predicate that happens to be false for NULL rather
than on a guard that says so.** `SECDEF-01` was that shape and was one `IS DISTINCT FROM` away from
being an enumeration oracle. An explicit `auth.uid() IS NULL` RAISE costs one line and cannot be
refactored away by accident.

### SECDEF-03 — resolved by inspection + live anon probe (2026-09-03)

All five previously-unverified functions were read from `pg_proc.prosrc` and then probed over HTTP
with the **public anon key**. Random UUIDs were used throughout so nothing could persist even if a
guard had failed; production was confirmed byte-identical afterwards (34 expenses, 54 splits, 3
friends, 0 `PROBE` rows, 0 friends touched in the last 5 minutes).

| Function | Anon probe | Guard |
|---|---|---|
| `block_user` | `400 P0001 Not authenticated` | ✅ explicit `IF caller_id IS NULL THEN RAISE` |
| `create_group_with_member` | `400 P0001 unauthenticated` | ✅ explicit |
| `send_friend_request` | `400 P0001 Not authenticated` | ✅ explicit |
| `add_expense_with_splits` | `401 42501 caller is not a member of group` | ⚠️ **its identity guard is inert for anon** |
| `respond_to_friend_request` | **`204 No Content`** | ⚠️ **no guard at all** |

**Nothing is exploitable today.** Both ⚠️ rows fail closed. Neither does so by intent.

#### `add_expense_with_splits` — the guard that cannot reject the caller it names
```sql
IF auth.uid() <> p_paid_by THEN
    RAISE EXCEPTION 'paid_by must match the authenticated user' ...
```
For an anonymous caller `auth.uid()` is NULL, so `NULL <> p_paid_by` evaluates to **NULL, not TRUE**,
and the `IF` never fires. Confirmed against production: `select (null::uuid <> gen_random_uuid())`
returns **NULL**. The function is saved entirely by the *next* check — `is_group_member`, which
returns **false** (not null) for a NULL caller, so `NOT false` raises `42501`.

So the guard written specifically to bind identity is inert for exactly the caller it exists to
reject, and the protection is supplied by an unrelated membership test standing behind it. Delete or
weaken that membership test — a plausible refactor, since it reads as a redundant second
authorisation check — and this becomes an unauthenticated write path into `expenses` and `splits`.

#### `respond_to_friend_request` — answers 204 to an anonymous caller
No `auth.uid()` guard of any kind. Both branches filter `addressee_id = auth.uid()`, which is
`= NULL` for anon → never true → zero rows. PostgREST then returns **`204 No Content`**, i.e.
*success*. Same shape as the `notification_preferences` DELETE already recorded in `CLAUDE.md`:
**a 204 describes the request, not the effect.**

#### This is the third instance of one rule
`SECDEF-01` (`WHERE p.id != auth.uid()`), and now both of these. **In this schema, safety keeps
resting on a predicate that happens to be false for NULL rather than on a guard that says so.** Each
is one `IS DISTINCT FROM`, one `COALESCE`, or one deleted "redundant" line away from being live. The
three functions that *do* carry `IF ... IS NULL THEN RAISE` cost one line each and cannot be
refactored into a hole.

**Recommended (not applied — a migration needs approval):** add an explicit
`IF auth.uid() IS NULL THEN RAISE EXCEPTION ... USING ERRCODE = '42501'` to both, and change
`add_expense_with_splits`'s identity check to `auth.uid() IS DISTINCT FROM p_paid_by` so it fires on
NULL. Revoking `anon` by name is the second layer, as in 053.

## BOOK-01 — the bookkeeper flow (2026-09-08)

**Reported from live use:** a member could not add an expense paid by someone else, and editing an
expense to correct a mistyped payer failed with *"new row violates row-level security policy for
table 'expenses'"*. Deleting and re-adding it hit a different refusal.

**Cause.** `paid_by` was doing two jobs — *who spent the money* and *who may touch this row* — and
`auth.uid() = paid_by` was enforced in **four** places: the INSERT, UPDATE and DELETE policies and
the `add_expense_with_splits` guard. The UPDATE's `WITH CHECK` evaluates the **new** row, so
changing `paid_by` could never succeed; the delete-and-re-add path was refused by the RPC instead.

`settlements` had already solved this shape in migration 041 by separating `recorded_by` from the
parties. `expenses` had no equivalent column, so the only way to stop A asserting things about B
was to forbid it outright.

**Fix — migration 055, ✅ DEPLOYED 2026-09-08.** `expenses.created_by`, nullable, stamped from
`auth.uid()` server-side and never accepted from the client. Policies become
`auth.uid() = paid_by OR auth.uid() = created_by`, with the payer required to be a group member —
previously implied by the guard that was removed (the INV-07 lesson: re-emit a function and every
guard in it becomes yours). Membership, not *active* membership, matching the settlements decision.

⚠️ **No existing row was written.** `created_by` is nullable with **no backfill**, at the owner's
instruction. For the 45 live expenses it stays NULL, `auth.uid() = created_by` is then NULL, the OR
falls through to the `paid_by` arm, and legacy rows behave exactly as they always did.

**No app release required.** The client already sent whatever payer the picker selected —
`AddExpenseViewModel.payerID` merely *defaults* to the current user, and `saveEdit()` sends
`editPayerID`. Only the server refused. The flow went live for every shipped build, 1.0–1.6, the
moment the migration landed. Same shape as INV-07.

**Also closes the `add_expense_with_splits` half of SECDEF-03.** Its identity guard was
`auth.uid() <> p_paid_by`, which is **NULL — not TRUE — for an anonymous caller**, so it never
fired; only the membership check behind it failed the request closed. Replaced with an explicit
`auth.uid() IS NULL` raise.

☠️ **The first deploy attempt failed, and that was lucky.** The `CREATE OR REPLACE` omitted the
function's **8 parameter defaults**; Postgres refused with `cannot remove parameter defaults from
existing function` (SQLSTATE 42P13) and rolled the whole migration back — verified: no column, no
helper, no policy change, 055 unrecorded. Had it succeeded it would have reintroduced **SPLIT-04**,
the `PGRST202 Could not find the function` that hit a real user in 1.3, because PostgREST resolves
an RPC by the exact key set it receives and migration 045 added those defaults for precisely that
reason. The warning is now in the migration header.

**Verification, all read-only or rolled back.**

| Check | Result |
|---|---|
| Bookkeeper insert (A records B paid) | **ACCEPTED**, `paid_by = B`, `created_by = A` |
| Non-member named as payer | **REFUSED** `42501` |
| Data after probing | 45 expenses / 76 splits, **0** probe rows — unchanged |
| Legacy rows | **45 of 45** still `created_by = NULL` |
| RPC overloads | **1** (H-11 has bitten this schema three times) |
| Parameter defaults | **8**, preserved |
| `anon` EXECUTE | revoked |

Both guard directions were exercised inside a `DO` block whose closing `RAISE` aborts the
transaction, so the probe could not persist even if a guard had been broken.

**Client (ships in the next release, not required for the flow).** `Expense.createdBy` — optional
and never backfilled, for the same reason `updatedAt` is optional: `CacheService` holds entries
written before the key existed. `Expense.wasRecordedBySomeoneElse` is a computed property rather
than an inline view condition so the display rule is testable without driving SwiftUI, and
`ExpenseDetailView` shows **"Added by X"** only when the recorder differs from the payer — silent in
the ordinary case so it reads as an exception rather than noise on every row.

**Tests.** `ExpenseRecorderTests`, **7 cases**, confirmed by name in the result bundle: decoding
through `SupabaseManager.postgrestDecoder` (the decoder the transport actually uses — the SPLIT-04
lesson), the legacy-null row, a payload with the key **absent** entirely, and all four branches of
the display rule. Unit suite **513 passed, 0 failed**.

**Mutation-tested, exactly.** Forcing `wasRecordedBySomeoneElse` to `true` fails **exactly 2** of
the 7 — *"Silent when the payer recorded their own expense"* and *"Silent for a row predating
migration 055"* — while the five independent of it correctly still pass.

### ✅ DEVICE-VERIFIED by the owner 2026-09-08, on 1.6 (8)
1. **Add an expense paid by another member** — works. Previously refused.
2. **Edit an expense to correct the payer** — works. This is the exact action that produced
   *"new row violates row-level security policy for table 'expenses'"*.
3. **"Added by X"** — renders on a bookkeeper-recorded expense.

⚠️ **(3) appeared absent at first, and the display code was not at fault.** The first attempt was a
row created *and then edited*, ending with `paid_by = created_by` — so the label was correctly
hidden. Confirmed from the data (`created_at 00:16:19`, `updated_at 00:16:47`, both ids the same),
not by reading the view. Two probes were spent before that:
- An OpenAPI-root check reported `created_by` **missing from PostgREST's schema cache** — and also
  reported `paid_by` missing, which demonstrably works. **The probe was invalid, not the cache.**
  A positive control is what exposed it.
- Re-probed with a discriminating test: `?select=created_by` returns `[]` (known, RLS-filtered)
  while `?select=definitely_not_a_column` returns `42703`. Schema cache was fine throughout.

### DECIDED 2026-09-08 — legacy rows stay unattributed. Do not re-propose.
`update_expense_with_splits` stamps `updated_by` but **not** `created_by`. Editing one of the 45
pre-055 rows to change its payer therefore leaves `created_by` NULL and shows no "Added by" label.

The alternative — stamping `created_by` with the editor when a legacy row's payer changes — was
considered and **rejected by the owner**. The reasoning that settles it: **editing an expense does
not change who originally recorded it.** Back-filling the editor into `created_by` would assert
something false about history to make a label appear, and `created_by` means "who recorded this",
not "who last touched the attribution" — that is what `updated_by` is for.

This is recorded as closed rather than deferred because `splits.is_settled` was re-proposed for
deletion in six consecutive release cycles before someone wrote down that the decision was made.

### ICON-05/08/09 — fixed 2026-09-08, and ICON-05 was mischaracterised

| | |
|---|---|
| **ICON-05 ✅** | The original finding called `Assets/AppIcon.appiconset/` "a second, divergent, dead App Icon set" and said to delete `Assets/`. **Both halves were wrong.** `Assets/` also holds `xbill-icon.svg` (the source artwork), `generate-icons.sh` and `IconNotes.swift` — all live, and all needed for ICON-03/04. The `.appiconset` is not junk either: it is that script's **generated staging output**. Untracked and gitignored rather than deleted outright; the three source files stay. |
| **ICON-08 ✅** | Four `.accessibilityLabel`s added — both shares steppers (`SplitParticipantRow`), regenerate-invite (`GroupInviteView`), clear-selected-person (`AddIOUView`). VoiceOver announced raw symbol names like *"minus circle fill, button"*. |
| **ICON-09 ✅** | One `XBillCategoryChip` with `.accessibilityAddTraits(.isSelected)`. `ExpenseFilterChip` and Add Expense's `CategoryChipView` are now thin delegates, so call sites are untouched. Selection state was previously visible only to sighted users. |

#### ☠️ The real ICON-05 defect, found only by looking before deleting
`Assets/xbill-icon.svg` had **`rx="226" ry="226"` on the 1024×1024 background**. The shipping icon
is a full square, so the live icons were not produced by this generator — or were corrected after.
Either way, running `generate-icons.sh` and following **its own final instruction** (*"Copy $OUT/
into your Xcode project's Assets.xcassets/AppIcon.appiconset/"*) would have replaced correct square
icons with pre-rounded ones, which iOS then masks a **second** time — visibly wrong corners on every
home screen.

That is a live trap aimed squarely at ICON-03, the next task, which needs this generator. The outer
`rx`/`ry` are removed and the reason is a comment in the SVG. The three inner radii (card and rule
artwork) are intentional and preserved.

**This is what the finding should have said.** "Delete the duplicate" would have thrown away the
source SVG and left the trap armed.

**Verification.** Unit **513 passed, 0 failed, 0 build errors**. Not device-verified — these are
VoiceOver and asset-pipeline changes; the chip merge is worth one look at the Group Details filter
strip and the Add Expense picker.

### SECDEF-03 — CLOSED 2026-09-08

All five functions now carry an explicit `auth.uid() IS NULL` guard, and the class is gone from this
schema.

| Function | Closed by |
|---|---|
| `block_user`, `create_group_with_member`, `send_friend_request` | already guarded |
| `add_expense_with_splits` | migration **055** (its `auth.uid() <> p_paid_by` was inert for NULL) |
| `respond_to_friend_request` | migration **056**, deployed 2026-09-08 |

**Proven live, before and after.** The anon probe that previously returned **`204 No Content`** —
success, to a caller with no identity — now returns **`401` / `42501 permission denied`**. Signed-in
behaviour verified unchanged inside a rolled-back `DO` block: both accept and decline complete
without exception. `friends` still 3 rows / 2 accepted / 0 pending; 1 overload, 0 defaults, `anon`
revoked by name.

**The pattern, stated once so it stops recurring.** Three times this schema protected a
`SECURITY DEFINER` function with a predicate that happens to be false for NULL rather than a guard
that says so — `WHERE p.id != auth.uid()` (SECDEF-01), `auth.uid() <> p_paid_by` (055), and
`addressee_id = auth.uid()` (056). Each was one `IS DISTINCT FROM`, one `COALESCE`, or one deleted
"redundant" line from being live. **Any new `SECURITY DEFINER` function starts with
`IF auth.uid() IS NULL THEN RAISE ... USING ERRCODE = '42501'`.** The runbook's anon-EXECUTE sweep
(`RELEASE_VERIFICATION.md` §1) is what surfaces regressions.

## UI-03 — the category filter strip dragged vertically and refreshed (2026-09-08)

**Reported from device use.** On Group Details → Expenses, the pinned category chip strip could be
dragged vertically **independently of the list below it**, and releasing fired a pull-to-refresh.

**Cause.** `.refreshable` does **not** attach to a view. It places a `RefreshAction` in the
**environment**, and *every* scrollable descendant adopts it. It was applied to `lifecycleContent`,
which wraps the entire screen — so the strip, being a `ScrollView(.horizontal)`, inherited
pull-to-refresh and grew its own vertical refresh gesture.

**Fix.** `.refreshable` moved from `lifecycleContent` onto the tab-content `Group`. The strip now
sits outside the refreshable region, so there is nothing for it to adopt. All three tabs keep
refresh; device-verified by the owner.

### Two wrong fixes first, both instructive
- **`.scrollBounceBehavior(.basedOnSize, axes: .vertical)`** — diagnosed as vertical rubber-banding.
  It was not: the movement was a refresh gesture, not bounce. The modifier is **kept** (a pinned bar
  should not bounce either) but its comment now says plainly that it is not the fix.
- **`.environment(\.refresh, nil)`** — does not compile. `EnvironmentValues.refresh` is exposed as a
  read-only `KeyPath`, not a `WritableKeyPath`, so **a refresh action cannot be cleared from a
  subtree at all**. Scoping where it is *set* is the only lever.

### Key Pattern — `.refreshable` is environment-scoped, so place it on the scroll view that owns it
Applying it high in the hierarchy silently hands pull-to-refresh to every scrollable descendant,
including horizontal strips and pickers that should never have it. Put it on the list, not on the
screen. The same reasoning applies to `.searchable` and `.toolbar`.

### Key Pattern — read the view tree before the first hypothesis, not after the second
Three hypotheses were proposed here and the first two were wrong, each costing a build-and-install
cycle on the owner's device. The structure that explained it — `.refreshable` on an ancestor of a
`ScrollView` — was visible in the file the whole time. This is the same lesson as `UI-02`, where
three causes were proposed and disproved before anyone measured.

**Verification.** Unit **513 passed, 0 failed**. **Device-verified by the owner:** the strip no
longer drags or refreshes, horizontal scrolling still works, and pull-to-refresh still works on all
three tabs — the regression risk, since the modifier all three depended on was moved.

## ICON-06/07/10 — fixed 2026-09-08. ICON-03/04 deliberately NOT done.

| | |
|---|---|
| **ICON-07 ✅** | New `XBillGroupGlyph`. A group's emoji was rendered **six** ways — three sites through `XBillAvatarPlaceholder(name:)`, whose job is computing *initials* (it splits on spaces, takes two leading characters, uppercases, falls back to `"?"`) and which applies a `foregroundStyle` a colour emoji ignores; three more as bare `Text`. It worked only because `first` of "🍕" is "🍕". All six now route through one view; `XBillAvatarPlaceholder` goes back to initials. Handles the empty-emoji case, which previously rendered a blank circle. |
| **ICON-10 ✅** | `XBillCategoryIcon` sizes tile and glyph from `@ScaledMetric(relativeTo: .body)`, capped at **1.4×** so an enlarged icon cannot push a chip-row label out of the row. Previously fixed points, so the icon stayed put while every label beside it grew. |
| **ICON-06 🟡** | `symbolEffect` **0 → 2**, applied only where motion carries information: `wifi.slash` pulses while offline (an ongoing condition), and the regenerate-invite glyph pulses while an invite is minting. `.rotate` would read better on the latter but is iOS 18 and the floor is 17.0. `symbolVariant` remains unused — the category symbols are already explicit `.fill` variants, so it would be ceremony. |

### ICON-03 — attempted and reverted, on a measurement that was INVALID

⚠️ **Read this before repeating any of it.** The dark/tinted work was reverted because measurements
said the variants "were not applied". **Those measurements were worthless**, and the conclusion drawn
from them is withdrawn.

**What was verified and is sound:**
- The dark/tinted PNGs were genuinely distinct images (mean channel diff **38.97** and **68.49**/255).
- They compiled into `Assets.car` as `UIAppearanceDark` and `ISAppearanceTintable`.
- ☠️ **`ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR` defaults to `all`**, which emits loose
  `AppIcon*.png` into the bundle **and** legacy `CFBundleIconFiles` keys. iOS resolves the icon from
  those loose files, which carry **no appearance variants**. Setting it to `none` removed both. This
  is a real prerequisite and will be needed again.

**What was WRONG — the test method.** `simctl ui appearance dark` (and Settings → Display &
Brightness on a device) sets the **system** appearance. Home-screen **icon** appearance is a separate
control — Automatic / Light / Dark / Tinted, under long-press wallpaper → Edit → Customise → Home
Screen — which neither touches. Every "light vs dark" comparison was therefore taken in an
environment that could not show a dark icon, whatever the asset contained.

**Proven by isolation.** A throwaway app (`DarkIconTest`) was built with a deliberately unmistakable
pair — solid **red** light icon, solid **green** dark icon — a textbook `Contents.json`, and
`STANDALONE_ICON_BEHAVIOR: none`. Zero xBill code. On the same simulator, in dark system appearance,
its icon rendered **red**. A minimal, correct app fails the same test identically, so the test was
measuring the environment, not the app.

**Consequences, stated plainly:**
- The earlier claim *"xBill 0.5 delta vs control 0.6, therefore not applied"* is **withdrawn**.
- *"Reproducible on a clean simulator, therefore not a device setting"* is **withdrawn** — the
  simulator has the same Home Screen appearance control and it was never set there either.
- The xBill dark/tinted assets may have been **entirely correct**. That is unresolved, not disproven.

**To resume:** set Home Screen appearance to **Dark** explicitly on a device (ten seconds), then
reinstate the reverted work — the icons and `Contents.json` are reproducible from
`Assets/xbill-icon.svg`, and `STANDALONE_ICON_BEHAVIOR: none` goes back into `project.yml`. If a
device still shows the light icon with that setting on, only then is there a real defect to chase,
and **Icon Composer** (`Xcode.app/Contents/Applications/`) is the next avenue, since iOS 26 moved to
layered `.icon` files.

### Key Pattern — a differential needs a control that is known to work
Five theories were proposed and discarded here (bounce, loose files, the standalone setting, stale
artifacts, opaque backgrounds) before anyone asked whether the *test* could detect a working icon at
all. The throwaway app answered it in one run and would have answered it first. **When a change
"doesn't take effect", build the smallest thing that should obviously work before debugging the
thing that doesn't.** Same lesson as `SCAN-02` and `PUSH-01`: a check that cannot distinguish its two
outcomes is not a check.

**ICON-04 is NOT a task.** The legibility measurements stand — the AL/MR/JT initials dissolve below
120pt — but the app icon is brand identity, and changing it is a product decision, not an audit item.
Recorded as a finding for whenever that conversation happens.

### ⚠️ Suite flakiness — measured 2026-09-08. Rate known, cause NOT known.

**2 failures in 10 full runs (~20%)**, both passing in isolation. A hypothesis of
parallel-execution interference was written here first and is **withdrawn** — it was tested and is
wrong.

| Run | Mode | Result |
|---|---|---|
| 1 | parallel | 512/513 — *"Marking a history row unread performs no server write"* |
| 2 | parallel | 512/513 — *"Recording a payment reduces the balance"* |
| 3 | parallel | 513/513 |
| serial | serial | 513/513 |
| par1–3 | parallel | **513/513 ×3** |
| ser1–3 | serial | **513/513 ×3** |

Isolated re-runs: `ActivityViewModelReadMutationTests` **10/10**, `GroupViewModelPaymentTests`
**16/16**.

**Parallel and serial are indistinguishable (3/3 each), so parallelism is not the cause.** Both
failing tests are `@MainActor` view-model suites using injected fakes; an async-timing or shared
-singleton interaction is plausible but **untested**, and is deliberately not asserted here — the
parallelism guess was made on exactly that quality of reasoning and did not survive contact with six
runs.

One correlation, recorded as data only: both failures occurred in the two runs immediately following
a recompile, while all six probe runs reused a warm `-derivedDataPath`. At n=2 that is as likely
coincidence as signal.

### Partial fix 2026-09-08 — one real defect found, one failure still unexplained

`NotificationReadStateTests.settle(_:)` polled `hasInFlightMutations` for **200 × 1 ms and then
returned silently**. On a loaded machine that budget is exceeded, the caller asserts against
half-settled state, and the failure surfaces as *"Marking a history row unread performs no server
write"* — a behavioural message for what is actually a timing shortfall. That is exactly the
run-1 failure, and it explains why it passed in isolation every time.

Now a 10-second budget with an **explicit `Issue.record` on exhaustion**, so a timeout can never
again masquerade as wrong behaviour. Suite green at 513/513 after the change.

⚠️ **This addresses at most ONE of the two observed failures.** The run-2 failure —
*"Recording a payment reduces the balance"* in `GroupViewModelSettlementTests` — is **not
explained**. That test awaits `recordPayment` directly and uses injected fakes with a fresh
`UUID()` group id per call, so neither the shared `CacheService` keyspace nor a polling budget
accounts for it. Ruled out by inspection: `NotificationStore` is isolated per test (UUID-suffixed
keys), and `makeGroup()` never reuses an id.

### Measured after the fix: 0 failures in 20 runs

| | |
|---|---|
| before the fix | **2 failures / 10 runs** (~20%) |
| after the fix | **0 failures / 20 runs** |

No `settle() timed out` messages appeared either, so the widened budget is not merely converting a
silent failure into a loud one — the mutations genuinely drain.

At the prior rate, twenty consecutive clean runs has roughly a **1.2%** chance of occurring, so the
silent timeout accounts for the behaviour that was observed.

⚠️ **The honest claim is "not reproduced in 20 runs", not "fixed".** The run-2 failure in
`GroupViewModelSettlementTests` never had an identified mechanism. It is plausible that both
failures shared the timing cause and presented differently — but that was never proven, and 20 runs
cannot exclude something rarer. If a payment-suite failure recurs, it is a **new** investigation
with this table as its starting point, not a regression of something closed.

**What to do when it recurs:** re-run the named suite in isolation before treating it as real. If
isolation passes, this table is the prior data point — do not re-derive it. If the rate climbs or a
third suite joins, the next step is instrumenting shared state (`NotificationStore`,
`CacheService.defaults`) across suite boundaries, not another guess.

---

## FLAKE-02 — `GroupViewModel` tests read the host machine's real network path ✅

**Closes the open thread above.** *"The run-2 failure — 'Recording a payment reduces the balance'
in `GroupViewModelSettlementTests` — is **not explained**"* now is, and the mechanism has nothing
to do with timing, `CacheService` keyspace collisions or `NotificationStore`. All three of those
were ruled out correctly; the cause was in a place none of them looked.

**Symptom.** A full-suite run on 2026-09-10 failed two tests that pass 16/16 in isolation:

| test | message |
|---|---|
| `Recording a payment reduces the balance` | `(vm.balance(for: bob) → 0) == -10` |
| `Recording and deleting a payment fetch no splits` | `(vm.balance(for: bob) → 10) == 0` |

**Cause.** `GroupViewModel.init` takes `isConnectedProvider`, defaulting to
`NetworkMonitor.shared.isConnected` — a real `NWPathMonitor` singleton. **27 of the 35
`GroupViewModel` constructions in the test target omitted it**, so they depended on the host
machine's network path. When a path update lands unsatisfied mid-run, `load()` takes its *offline*
branch: `members` and `expenses` come from `CacheService.shared`, which for a freshly generated
group id is empty. The carefully wired fakes two lines above are never read.

The failure is silent by design. Nothing throws, `errorAlert` stays nil, and R2 leaves
`balanceLoadFailed` false because the group is not known to have expenses. The only observable is a
balance of zero — indistinguishable from a broken split calculation. In isolation the suite
finishes in well under a second, usually before the first path update even arrives, so
`isConnected` is still its initial `true`: hence "passes alone, fails in the full suite".

**How it was isolated.** By mutation, not inspection. Forcing `isConnectedProvider: { false }` on
those two tests reproduced **both failure messages verbatim** — `→ 0` and `→ 10` — on the first
attempt. Three other hypotheses were considered and dropped without being tested, including the
`computeBalances` coalescing early-return, which was the leading theory going in. It is
**disproved** for these failures: `computeBalances()` is called only from `load()` and two methods
these tests never invoke, so `isComputingBalances` cannot be true on entry and the early return
cannot fire.

**Fix.** All 27 sites now pass `isConnectedProvider: { true }` explicitly. The seam's doc comment
in `GroupViewModel.swift` and the header of `GroupViewModelSettlementTests.swift` both record why
omitting it is not a stylistic choice. New suite `LoadSourceByConnectivityTests`
(`GroupViewModelStateTests.swift`) pins both sides of the fork — online reads the service, offline
with an empty cache yields a silent zero with `balanceLoadFailed == false` — so the discriminator
stays executable rather than living in a comment.

**Verification.** 515/515 unit tests pass. The count rose from 513 by the two new tests.

**The lesson.** A default argument that reaches a `.shared` singleton is a hidden dependency on the
machine. `currentUserIDProvider` has the same shape and the same exposure — it defaults to
`AuthService.shared.currentUserID`. Grep for defaults that resolve to a singleton before assuming a
test target is hermetic.

---

## FLAKE-03 — `currentUserIDProvider` audit: the same seam, one layer over ✅

Follow-up to FLAKE-02, which ended with *"`currentUserIDProvider` has the same shape and the same
exposure."* It does. Audited 2026-09-10, all findings closed except HOME-01 below.

`AuthService.shared.currentUserID` reads `supabase.auth.currentUser?.id` — the SDK's **persisted**
session, restored from the test host's storage. The identity a test runs under was therefore
whatever session that simulator happened to hold, not something the test chose.

**14 of 35 constructions omitted the argument.**

| where | count | reads it? | severity |
|---|---|---|---|
| `GroupViewModel` — State/SettleUp/Coverage tests | 10 | only `recordPayment` does, and none of these tests calls it | **latent** |
| `ActivityViewModel` — `P1NotificationTests` | 4 | pervasively — 15 sites, including `store.loadAll(userID:)`, `markAllRead(userID:)`, `delete(id:userID:)` | **live, but offline** |

Nothing reached the network, because none of the 14 calls `load()`. The exposure was real and
un-triggered — which is exactly the state FLAKE-02 was in until it triggered.

**Three further findings in the same sweep:**

- **Three bare `ActivityViewModel()` constructions held three live singletons at once** —
  `ActivityService.shared` (wired to Supabase), `NotificationStore.shared`, and the session. One of
  them called `NotificationStore.shared.clearAll()`, a cross-suite write into shared storage. All
  three now take a per-test suffixed store, a pinned identity, and a new `InertActivityService`; the
  `clearAll()` is gone because there is no longer anything shared to clear.
- **`markReadAndDeleteUpdateVM` read `AuthService.shared.currentUserID` explicitly** and handed the
  same value to its store. Self-consistent, so it never failed — but the identity was still the
  machine's. Now a local `UUID()`.
- **Three `ViewModelCoverageTests` sites built a `GroupViewModel` on `GroupService.shared`,
  `ExpenseService.shared` and `SettlementService.shared`.** They only set properties directly, so
  nothing dialled out. They take fakes now. (Their formatting was also mangled by the FLAKE-02
  script and is repaired.)

### HOME-01 — `HomeViewModel` has no injection seams and no tests ⚠️ open

`HomeViewModel` has **no `init`**. It hard-wires `GroupService.shared`, `ExpenseService.shared` and
`AuthService.shared` as stored properties, and **no test in the target constructs it**. `loadAll` —
including the concurrency change made the same day — has zero unit coverage, and cannot get any
without first adding the seams `GroupViewModel` already has. Not fixed here: that is a refactor,
not a test edit, and it should be a deliberate decision rather than a side effect of this sweep.

**Verification.** 515/515 unit tests pass. Two compile errors were hit and fixed on the way
(`currentUserIDProvider` must precede `isConnectedProvider` in the parameter list) — the first
build masked the second file's errors, so the suite was run three times, not once.

---

## HOME-01 — `HomeViewModel` had no seams, no tests, and a real balance race ✅

Opened by the FLAKE-03 sweep, closed 2026-09-10. Adding the seams was the point; the race is what
the first tests found.

### The seams

`HomeViewModel` had **no `init`**. `GroupService.shared`, `ExpenseService.shared` and
`AuthService.shared` were stored properties; `SettlementService.shared` and
`NetworkMonitor.shared.isConnected` were reached inline. Nothing in the test target could construct
the type, so `loadAll` — the screen every user lands on, and the only place cross-group balances are
summed — had **zero** unit coverage.

Two new protocols, `HomeGroupDataProviding` and `HomeExpenseDataProviding`, **refine** the existing
`GroupDataProviding` / `ExpenseDataProviding` rather than widening them, so `FakeGroupService`,
`FakeExpenseService` and `ActivityServiceTests.StubGroups` are untouched — a fake only implements
the extra methods if it is standing in for Home. `HomeViewModel.init` now takes all five seams,
defaulted to the singletons, so every existing `HomeViewModel()` call site is unchanged.

One Swift detail worth keeping: a protocol requirement **cannot carry default arguments**, and
`ExpenseService.createExpense` defaults its last four. The requirement is spelled out in full (a
witness matches on the whole signature regardless) and a protocol extension restores the
eight-argument form the app actually calls — a different arity, so it forwards rather than recurses.

### RACE-01 — an overlapping `loadAll` was silently dropped ⚠️ was live

`computeBalances(for:)` opened with `guard !isComputingBalances else { return }`. A recompute that
arrived while one was in flight was **thrown away**. Harmless while both callers see the same group
list — and wrong the moment they do not, which is precisely what a realtime event produces:

1. load #1 reads `groups`, starts computing, is still fetching
2. a group appears; load #2 fetches the **new** list and assigns it
3. load #2's recompute is dropped, because #1 is still running
4. #1 finishes and publishes totals for the list it read in step 1

Home then renders a total that **omits a group it is simultaneously listing**. Nothing throws, both
`await`s return, and the only symptom is a wrong number — the same silent shape as FLAKE-02.
`HomeView` has pull-to-refresh and `startRealtimeUpdates` calls `loadAll` on every event, with
nothing serialising them, so the ordering is reachable in normal use.

**Demonstrated before it was fixed.** `HomeViewModelOrderingTests` parks load #1 inside its balance
fetch, adds a group, runs load #2, then releases: with the old guard the test failed with
`vm.groupNetBalances[second.id] → nil`, and `netBalance` was −10 instead of −35.

**Fix:** the coalescing loop `GroupViewModel` already uses (REV-05) — set `shouldRecomputeBalances`
and let the in-flight run go round again. What it deliberately does **not** promise is recorded in
the code: a coalesced caller's `await` returns before the recompute it asked for has happened. The
guarantee is that the last state wins once everything settles.

### Coverage added

`HomeViewModelTests.swift`, 7 tests: no-current-user is a no-op; online sums the cross-group
balance; a settlement offsets the debt it repays; a failed settlements fetch raises the IMP-2 stale
warning; offline never reaches the service; the archived fetch overlaps the balances (pinning the
2026-09-10 perf change, by asserting the *overlap* rather than the result — the version that only
checked both finished would have passed if they were re-serialised); and RACE-01 above.

**Two process notes.** The first run reported `** TEST SUCCEEDED **` with **0 tests** — the new file
was not in the target, because sources come from `project.yml` and `xcodegen generate` had not been
run. That is verification rule 7 exactly: read the structured result, never the exit status. And the
overlap test's first draft asserted immediately after the gate parked, which races the balance
task's scheduling; it now yields until the condition holds, with a bound that still fails if the two
were ever re-serialised.

**Verification.** 522/522 unit tests pass, up from 515.

---

## PERF-01 — four sequential fetches per group on the home screen ✅ (v1.8)

`fullBalancesInGroup` fetched **expenses, then members, then splits, then settlements** — four round
trips one after another, for every group. Groups ran in parallel with each other, so a group's own
chain was the critical path. Two groups meant eight requests; ten groups, forty.

Only splits depends on expenses. Members and settlements depend on nothing, so the shape is
`expenses → splits` alongside `members` alongside `settlements`: **two sequential waits instead of
four**. Each branch keeps its own `do`/`catch` and cache fallback, so failure behaviour is
unchanged — in particular a members failure still does **not** raise `loadFailed` (names going
missing shows as missing names, not a wrong number) while the other three do.

**Proven structurally, not by stopwatch.** `perGroupFetchesOverlap` parks the head of the chain and
asserts the independent two have already started. Written first and watched fail
(`fetchMembersCount → 0`); asserting the four *results* instead would have passed just as well with
them still sequential.

**End-to-end, three device cold launches** (iPhone 16 Pro, 2 groups):

| | before (v1.7 post-dedup) | after |
|---|---|---|
| load duration | 500 / 368 / 404 ms | 422 / 322 / 309 ms |
| view → balances settle | 621 / 487 / 427 ms | 476 / 412 / 377 ms |

⚠️ Mean load ~424 → ~351 ms, **but the ranges overlap** — at n=3 this is not distinguishable from
noise, and is reported as such rather than as a 17% win.

**What this does not fix.** The count is still four requests per group; this only stops them
queueing. The change that scales with group count is a server-side `get_group_balances` returning
all groups in one request. That is a schema change and deliberately not bundled here.

**Residual, not a defect:** on a cold launch where the first load finishes before
`didBecomeActive` arrives, a second full load still runs (observed in 2 of 3 launches: `enters 2`).
It is a refresh after the balances are already on screen, so nobody waits for it. Skipping the first
`didBecomeActive` would remove it, at the cost of more launch-path special-casing.

### Found while fixing it — unit tests were calling system daemons

At 1.8 the full suite failed **once in three runs**: `balancesOverlapTheArchivedFetch` timed out on
its gate. Every new Home test was making real XPC calls to the Spotlight and widget daemons on each
load, because `SpotlightService.indexGroups` and `WidgetCenter.reloadAllTimelines()` were invoked
directly — a unit suite writing to the simulator's real Spotlight index. Both are now seams
defaulted to the real implementations, stubbed in `HomeFixture`.

⚠️ **Causation is not established.** The seam is correct on its own merits regardless. After it,
**5 consecutive full-suite runs passed 532/532**, against a prior rate of 1 failure in 3 — suggestive,
not proof. If that gate timeout recurs, this paragraph is the starting point, not a closed case.

---

## PERF-02 — `get_group_balances()`: one request for every group ✅ deployed 2026-09-11

Migration **059**, deployed and verified. The home screen's per-group **members, splits and
settlements** fetches are replaced by a single RPC covering every group the caller belongs to.

| groups | before today | after PERF-01 | after PERF-02 |
|---|---|---|---|
| 2 | 8 requests, queued | 8, overlapped | **3** |
| 10 | 40 requests, queued | 40, overlapped | **11** |

Expenses remain per-group: Recent Expenses needs the rows themselves.

### Verified after deploy

| Check | Result |
|---|---|
| `prosecdef` | **INVOKER** — RLS enforces access; no privilege of its own |
| `proacl` | `{postgres=X, authenticated=X, service_role=X}` — **no bare PUBLIC entry, no `anon`** |
| No session | `select count(*) from get_group_balances()` → **0 rows** |
| With a session | 6 rows, balances summing to **exactly 0.00 within each group** |
| **On device** | `loadAll.success … owed=43.26 owing=0`, matching the database's 19.81 + 23.45, with **0 RPC failures** — so the server path ran, not the fallback |

### ⚠️ It did not make the screen faster, and that is expected

Device, four cold launches: load `263 / 327 / 357 / 901 ms` against PERF-01's `422 / 322 / 309 ms`.
**Medians are effectively equal** (~342 vs ~322 ms). No improvement is claimed.

The reason is structural and worth writing down: after PERF-01 the critical path was already only
**two sequential waits** — `max(expenses→splits, members, settlements)` — because the four per-group
fetches ran concurrently. PERF-02 makes it `RPC` **then** `expenses`: still two sequential waits.
Fewer requests, same depth.

**What PERF-02 actually buys** is that the request *count* stops scaling with group count — eight
requests become three for a two-group user, forty become eleven for a ten-group user. That is server
load, data volume, and headroom, not latency on this device with this data.

**The next step, if latency matters:** the expenses fetches do not depend on the RPC result, only on
the group list. Starting them concurrently with the RPC collapses the critical path from two
sequential round trips to one. Not done here.

### Safety

The client falls back to the per-group computation if the call fails **or if any balance will not
parse**. An unparseable balance must never read as zero — that silently cancels a debt. The fallback
also means an undeployed migration degrades to the previous behaviour rather than a blank screen; it
should be removed once this has a release behind it.

### A test that could never have failed

The first version of the float-boundary test asserted `Decimal(10.10) != Decimal(string: "10.10")`.
It does not — that value round-trips — so the test was ceremony. Replaced with an exact accumulation
across two groups, and the overstated comments in the migration and the model were corrected to
claim only what had been observed. Rule 12, found in my own new code within the hour.


---

## PERF-03 — the expense fetches start with the RPC, not after it ✅ (v1.8)

PERF-02 cut the request count but not the **depth** of the critical path: the expense fetches ran
after the RPC returned, so it was still two sequential round trips and the clock did not move.
Expenses depend only on the group list, not on the balances, so they now start alongside the RPC.

**Device, six cold launches each** (iPhone 16 Pro, 2 groups, `loadAll.enter` → `loadAll.success`):

| | samples | median |
|---|---|---|
| PERF-02 | 263 / 327 / 357 / **901** | ~342 ms |
| PERF-03 | 179 / 180 / 204 / 245 / 252 / **1251** | **224 ms** |

Each batch carries one outlier an order of magnitude above the rest; the tail is network-dominated
and this change does not touch it. Setting those aside, the two sets are `263–357` and `179–252` —
**they do not overlap**, which is what was missing from the PERF-01 and PERF-02 measurements and why
neither was claimed as a win. This one is.

**The whole arc of the day**, view appears → balances on screen:

| | |
|---|---|
| v1.7 as shipped | 787 ms / 1.07 s / 1.21 s |
| after PERF-03 | 234 / 243 / 261 / 316 / 332 ms |

Balances read `owed=43.26 owing=0` on every launch, matching the database, with **0 RPC failures**.

### One existing test changed, and why that is not weakening it

`perGroupFetchesOverlap` parked the expenses fetch and asserted members had already started.
Hoisting the expense fetches means members and settlements now begin *after* expenses rather than
beside them, so it failed — correctly.

It was asserting an implementation detail rather than the property that matters. Splits **always**
waited for expenses, so `expenses → splits` was the critical path before and after, and the fallback
path's depth is unchanged at two waits. The test now parks the *splits* fetch and asserts that the
three fetches which genuinely can overlap do. Same property, correctly expressed — not a test
relaxed to match the code.


---

## PERF-04 — the local balance fallback removed ✅ (v1.8)

Migration 059 is deployed, so the fallback's original purpose — surviving an undeployed RPC — is
gone. **86 lines** of duplicate balance computation went with it, along with
`HomeViewModel.settlementService`, which had no other caller.

**This was not only a deletion.** The fallback also covered a *transient* RPC failure, so removing
it needed a failure path, and the obvious one is wrong: leaving zeros on screen. A zero is
indistinguishable from "settled up" and would tell someone a debt had been paid — the same reason
`GroupBalanceRow.decimalBalance` returns `nil` rather than defaulting.

What happens now when balances cannot be computed:

| | |
|---|---|
| balances | **previous figures stay on screen**, never replaced by zeros |
| warning | "Some balances may be stale" |
| Recent Expenses | still refreshes — it does not depend on the balances |

**All-or-nothing across groups.** If any single group cannot be built, no group's figures are
replaced. Skipping the bad group would drop its share of the totals and quietly understate what the
user is owed, which is worse than showing yesterday's numbers under a warning.

### Two tests removed, and why that is not lowering the bar

- The **settlement arithmetic** tests (a settlement cancelling a debt; a settlements fetch failure
  raising the warning) drove `FakeSettlementService`. Home no longer fetches settlements at all —
  that arithmetic is migration 059's job now, where it is reproduced including the self-split and
  null-payer rules. Rewriting them client-side would have asserted nothing.
- **`perGroupFetchesOverlap`** pinned PERF-01's per-group fetch ordering. Removing the fallback
  deleted its last caller, so there is no ordering left to assert.
  `expensesOverlapTheBalancesRequest` pins the ordering that now exists.

Three new tests replace them: a failed request keeps the previous figures and warns; a failed
request still refreshes the expense list; an unparseable balance leaves **every** group's figures
alone.

**Verification.** 537/537. Device, four cold launches: `292 / 185 / 228 / 195 ms`, `owed=43.26`
every time, `balances.unavailable = 0`.


---

## ICON-03 — confirmed 2026-09-11, this time with evidence that holds

The original finding was **withdrawn** on 2026-09-08 because the test behind it was invalid:
`simctl ui appearance dark` sets the *system* appearance, not the Home Screen **icon** appearance,
so it never demonstrated anything. The finding itself was right; only the method was wrong.

It is now confirmed two ways that do not depend on looking at anything:

| Source | Result |
|---|---|
| `AppIcon.appiconset/Contents.json` | 16 image entries, **0** carrying `appearances` |
| The installed build's compiled `Assets.car` (`assetutil --info`) | 5 AppIcon entries, appearance set `{(none)}` |

So iOS has no dark or tinted artwork to use and falls back to the light icon in every appearance.
The owner checked on device: **"in dark mode, icon seems same"** — which is exactly the predicted
behaviour, and is the confirmation.

**Whether that is a defect is a separate question, and Dark is the wrong place to look.** The mark
is white on `#3B3287`, already dark, so the light artwork standing in for Dark can look perfectly
correct — and by the owner's eye it does. **Tinted** is where a missing variant usually shows,
because iOS derives a monochrome version from the light artwork and the fine detail ICON-04
describes — four sub-pixel ruled lines, three avatar circles carrying two-letter initials —
collapses. That check is outstanding.

**If a variant is wanted, it need not be a rebrand.** A dark variant is the *same mark* on a
different backdrop, not new artwork — which matters, because ICON-04 is closed on the owner's
instruction that the icon is a brand and cannot change quickly. Adding appearances does not reopen
that.

---

## SCAN-ML-01 — a trainable model for receipt parsing: what it would be, and what it needs ⬜ planned

Raised by the owner 2026-09-11 and **kept as a live objective**, not a someday. This records the
shape and — more importantly — the data arithmetic, because that is the part that decides whether
it can work.

### What would be trained

**Not OCR.** Vision is Apple's and closed; its misreads (`Gus` for `Gms`, `SMARIWATER`, `Sulata`
for `Sujata`) cannot be fixed by any model trained on the text it produces, because by then the
text is already wrong. Those need `OCRLine.alternates`, which the pipeline already carries and
does not yet use.

**A line classifier.** What fails is deciding *what each line is*: item / total / subtotal / tax /
tip / discount / header / payment / junk. That is ordinary text classification — Create ML on the
Mac, a `.mlmodel` of tens of KB in the bundle, inference per line, offline, no privacy change.
Features already exist on `OCRLine`: `text`, `midX` (prices sit in a right-hand column), `midY`
(totals sit low), `height`, `confidence`.

It would attack the two biggest failure classes directly — junk kept on the line
(`365992 Tortilla Chips`, `1 Coke`) and non-items captured as items (`O T A L=28.35`,
`Time: 05:23PM=0.3`).

### The data, counted rather than guessed

| | |
|---|---|
| Receipts | **22** |
| Labelled item rows | **91** |
| Per-line labels | **none — they do not exist yet** |

The ground truth is item-level (`name`, `qty`, `unitPrice`), not per-line. Per-line labels can be
derived mostly automatically — lines matching an expected item become `item`, lines matching the
recorded `total`/`tax`/`tip`/`subtotal` become those, the rest default to `junk`, then the residue
is hand-corrected. Hours, not weeks. **That derivation is the real prerequisite, and it is worth
doing even if no model ships**: it turns "item count exact 15/22" into a per-line confusion matrix
that says exactly which lines the heuristics misclassify.

**The positive class is the constraint.** 91 item lines against several hundred non-item lines is
roughly 1:9, and 91 positives is thin for generalisation. Long grocery receipts carry the weight —
receipt 12 alone has 21 items, 08 has 14, 01 has 10 — so roughly **40–60 more receipts, weighted
toward groceries**, would take the positive class to the 400–500 range. The owner has more
receipts available; this is what they are most valuable for.

### The trap to avoid

22 receipts are **one person's** shopping — Kroger, Patel Brothers, Starbucks, a few restaurants. A
classifier trained on them learns those formats and can do worse on an unseen chain while the
benchmark still looks good, because the benchmark is the same receipts. **Hold a portion of the new
receipts back as a test set the model never trains on.** Without that split the accuracy number is
self-congratulation.

### Sequence

1. ✅ **Gate the benchmark** — done. Without it, a model cannot be shown to help.
2. ⬜ **Rule fixes + `alternates`** — deterministic, testable, and they raise the baseline a model
   must beat rather than letting it take credit for them.
3. ⬜ **Derive per-line labels** — the prerequisite, and independently useful as a diagnosis.
4. ⬜ **Re-measure.** If item-count exactness is still short of ~90%, the classifier has earned its
   place; if the rules got there, a model would be added complexity for nothing.

---

## SCAN-TIER-01 — Apple Intelligence is scoring worse than the heuristics on this corpus ⚠️ decision needed

Found 2026-09-12 while making the benchmark deterministic. **No app behaviour was changed** —
`usesFoundationModels` defaults to `true` and only the benchmark opts out.

`VisionService` routes to Apple Foundation Models when available (Tier 1) and falls back to
heuristics (Tier 2). Running the same 22 receipts with Tier 1 **off**:

| metric | Tier 1 mixed in (9 runs) | heuristics only (2 runs) |
|---|---|---|
| TOTAL correct | 18–20 of 22 (82–91%) | **21/22 (95%)** |
| TAX correct | 19–20 | 20/22 |
| Item count exact | 14–15 (64–68%) | **16/22 (73%)** |
| Price recall | 84–88% | **90%** |
| Name recall | 76–83% | 80% |

Every metric improved. It matches the per-receipt evidence gathered before the switch existed: the
three worst item-level failures were **all** on the Apple Intelligence tier —

| receipt | tier | what it did |
|---|---|---|
| 01 Kroger | Apple Intelligence | total wrong; `AVOCADO=0`, `KRO ONIONS RED BAG=0`, and `3.3334` (a unit price) where `6.99` was expected |
| 04 Wayfair | Apple Intelligence | missed the `10GRANDOPENING=-7` discount line entirely |
| 13 Chuko Ramen | Apple Intelligence | invented three zero-priced modifier lines and missed the real `0.87` fee |

### Why this is not yet an instruction to switch it off

- **The corpus cannot speak for the feature's main purpose.** 22 English, mostly-US receipts from
  one person. Tier 1 exists partly to give cultural context to non-English receipts
  (`VisionService.swift:601`), and there is not a single non-English receipt in the corpus.
- **Simulator ≠ device.** Tier 1 availability and model version may differ on a real iOS 26 phone.
  Every number here is from the iPhone 17 Pro simulator, iOS 26.5.
- 4 of 22 receipts took the Tier 1 path; the comparison rests on those four.

### What would settle it

Run the corpus on a physical iOS 26 device with Tier 1 on and off — the benchmark already supports
both, and already writes its report into the test process's Documents on device. Add non-English
receipts before deciding, since that is the case Tier 1 is there for.

**Until then the default stays `true`.** This is recorded so the decision is made on evidence rather
than on which tier sounds more advanced.

---

## FLAKE-04 — a 12-second timeout turns test-host starvation into a wrong balance ✅ fixed

Two tests failed in a full-suite run on 2026-09-12 with the **exact FLAKE-02 error text**:

```
Recording a payment reduces the balance          (vm.balance(for: bob) → 0) == -10
Recording and deleting a payment fetch no splits (vm.balance(for: bob) → 10) == 0
```

**It is not FLAKE-02.** Both tests still carry `isConnectedProvider: { true }`, so the offline
branch — the mechanism proved by mutation on 2026-09-10 — cannot be reached. Same symptom, different
cause. The symptom is not diagnostic: *any* path that leaves `splitsMap` empty ends here, because
`computeBalances` then `continue`s without calling `applyDerivedBalances`.

### The evidence is the duration, not the message

| test | in the full suite | in isolation |
|---|---|---|
| `paymentPathsDoNotRefetchSplits` | **48 s** | 0.095 s |
| `recordReducesBalance` | **48 s** | 0.01 s |
| `deleteRestoresBalance` (passed) | 0.032 s | — |
| `failedInsertIsReported` (passed) | 0.032 s | — |

Their own siblings in the same suite ran in 32 **milli**seconds. Only the two failing tests dilated,
by a factor of roughly 1,500–5,000. And 48 s is a multiple of **12** — the exact value in
`withTimeout(duration: .seconds(12))`, which `load()` and `computeBalances()` each wrap a fetch in.

`withTimeout` races `operation()` against `Task.sleep(for:)`. The fakes return instantly, but they
are `@MainActor`; the sleep is a timer and needs no actor. Starve the MainActor for twelve seconds
and **the sleep wins against a fake that never touched the network** — the fetch "times out",
`splitsMap` stays empty, and the balance reads zero.

### Differential run

| | result |
|---|---|
| the two payment suites alone | **17/17 pass** |
| the same suites + `ReceiptBenchmark` | **18/18 pass** |
| the whole 537-test suite | **2 fail** |

So the benchmark alone does not cause it; it needs full-suite parallel load. **The starvation source
is not identified** and is deliberately not guessed at here.

### The defect worth fixing

**A wall-clock timeout inside code under test makes the test depend on the machine's scheduling.**
It is the same family as FLAKE-02 (host network) and FLAKE-03 (host session): a dependency on the
environment that no fake can override. The fix is to make the duration injectable, the way
connectivity and identity already are, so a test can pass a duration that cannot fire — rather than
racing a real twelve-second clock against a parallel test suite.

Not done here: it changes `GroupViewModel`'s surface and several call sites, and today's change is
confined to the receipt benchmark.


### FLAKE-04 — fixed 2026-09-12

`GroupViewModel` now takes `fetchTimeout: Duration = .seconds(12)`, used at both `withTimeout`
sites. **Production is unchanged**; 37 test constructions pass `testFetchTimeout` (one hour), a
named constant carrying the reasoning rather than a bare number repeated 37 times.

The failure mode is now **unreachable, not merely unlikely** — a 48-second stall cannot trip a
3600-second timeout. That distinction matters here, because the full suite had passed many times
before this ever surfaced, so a green run would have proved almost nothing on its own.

**The evidence is unusually clean.** After the fix the two tests **passed while still running for
41 seconds**. The starvation is still happening; the timeout simply stops it corrupting the result.

It is the third seam of the same family:

| seam | host dependency it removes |
|---|---|
| `isConnectedProvider` | the machine's network — FLAKE-02 |
| `currentUserIDProvider` | the machine's session — FLAKE-03 |
| `fetchTimeout` | the machine's scheduling — FLAKE-04 |

### FLAKE-05 — the same mistake in the test harness, written the same week

Fixing FLAKE-04 surfaced a fourth instance immediately: `InterleavingGate.timeout` was **5 seconds**,
with a comment asserting it was *"orders of magnitude longer than the microseconds a correct
interleaving needs"*. That premise was never measured and is false — the host stalls a single test
for 41–48 seconds, so a **correct** interleaving can simply not be scheduled in time.
`balancesOverlapTheArchivedFetch` failed with *"no call reached the gate within 5.0 seconds"*: a
defect report about a defect that was not there.

Raised to 120 s — still ending a genuinely stranded continuation long before CI gives up, with a
note that it must never be tightened back toward the observed stall.

**Verification:** 537/537.

### ⬜ Still unexplained: what stalls a single test for 41–48 seconds

Known: it needs the **full** suite — the two payment suites alone pass 17/17, and alongside
`ReceiptBenchmark` 18/18. Magnitude measured at 41 s and 48 s on separate runs, against 32 ms for
sibling tests in the same suite.

Not known: the cause. **Deliberately not guessed at** — the fixes above do not depend on it. But a
suite where one test can stall for 48 seconds is a problem in its own right, and worth its own
investigation rather than being closed because the symptoms it produced have been handled.

---

## SCAN-PERF-01 — Vision OCR runs synchronously on the main actor ✅ fixed 2026-09-12

**This is what stalls the test suite, and it is not a test problem.**

### The measurement that found it

| run | duration distribution |
|---|---|
| Full suite **with** `ReceiptBenchmark` | **185 tests ≥40 s**, 351 <1 s — bimodal, nothing between |
| Full suite **without** it | **0 tests ≥40 s** — slowest is 1.00 s |

Removing one suite collapses the entire stalled cohort. The 185 were not doing slow work: most are
pure parsing tests over synthetic `OCRLine` values that normally run in microseconds, and only two
files in the target touch real Vision. They were alive and **never scheduled**.

### The cause

`VisionService` is `@MainActor` (`VisionService.swift:63`), and `recognizeText` calls

```swift
try handler.perform([request])       // VNImageRequestHandler — synchronous, blocking
```

inside a `withCheckedThrowingContinuation` body, which runs on the caller's executor — the main
actor. `preprocessForOCR` (CoreImage) is on it too. So the entire OCR pass holds the main actor for
its full duration.

The benchmark takes **44 s for 22 receipts ≈ 2 s of main-actor time per receipt**, and every
`@MainActor` test alive in that window queues behind it. That is the 41–48 s stall, and it explains
why the payment suites are fine beside the benchmark alone (18 competitors interleave) but not in a
537-test run.

### Why it matters outside the test suite

The app scans through the same path. **Every receipt scan blocks the main thread for roughly the
duration of the OCR** — around two seconds on this hardware, longer on an older phone or a larger
photo. A blocked main thread cannot animate the progress indicator that is presumably shown during
the scan.

⚠️ **Stated from the code, not from observation.** The reasoning above is static; the UI has not
been watched during a scan on a device, and that check should come before any fix is designed.

### The fix, and why it was not done here

Move the OCR off the main actor: `preprocessForOCR` and `recognizeText` have no reason to be
main-actor-bound, and the request-configuration values they need (`preferredRecognitionLanguages`,
orientation) can be computed on the actor and handed to a detached pass.

It is a production change to a service with 1,196 lines and its own test suites, and it deserves its
own pass with a before/after measurement on a device — not a tail-end edit to a session about
benchmark determinism. The test-side stall is a symptom and should **not** be papered over by
excluding the benchmark from the default run; that would hide the finding that matters.


### SCAN-PERF-01 — fixed 2026-09-12

`recognizeText`, `preprocessForOCR` and `preferredRecognitionLanguages` are now `nonisolated`. A
`nonisolated async` method runs on the cooperative pool instead of inheriting the caller's actor, so
the blocking `VNImageRequestHandler.perform` occupies a pool thread rather than the one drawing the
UI.

**Verified by the measurement that found it** — the full suite *with* `ReceiptBenchmark`:

| | ≥40 s | 10–40 s | 1–10 s | <1 s | slowest test other than the benchmark |
|---|---|---|---|---|---|
| before | **185** | 0 | 1 | 351 | **48 s** |
| after | **0** | 1 (the benchmark, 36 s) | 195 | 341 | **2 s** |

The stalled cohort is gone: 185 → 0, and the worst non-benchmark test drops from 48 s to 2 s. The
195 now in the 1–10 s band are ordinary CPU contention with a Vision workload, not actor starvation.
The benchmark itself also fell from 44 s to 36 s. **537/537.**

Strict concurrency caught two things reading would not have: `ciContext` and `receiptCustomWords`
are `static let`s on a `@MainActor` type and therefore inherit its isolation, so moving the work off
the actor while still reading them would have been a data race rather than a fix. `ciContext` is
`nonisolated(unsafe)` — `CIContext` is documented immutable and thread-safe, which is why one
instance is shared — and `receiptCustomWords` is plain `nonisolated`, `[String]` being Sendable.

⚠️ **There is no automated guard against re-isolating it.** Re-adding main-actor isolation would
still compile. The canary is the suite's own duration distribution: if the ≥40 s cohort returns,
this is the first thing to check. The numbers above are the baseline to compare against.

### Measured on device 2026-09-12 — and the estimate was too high

A DEBUG probe inside the `perform` call, on an iPhone 16 Pro scanning a real receipt:

```
VisionService.ocr ms=538 main=false
```

`main=false` confirms the fix on real hardware rather than only in the simulator suite. `ms=538`
is how long the main thread **would** have been held before it.

⚠️ **The earlier "about two seconds per receipt" was wrong** — it was the benchmark average
(44 s ÷ 22) on a simulator, quoted as though it described a phone. On device it is roughly a
**half-second stutter, not a freeze**. The test-suite effect was large and is measured; the
user-facing effect is real but modest, and saying so is more useful than keeping the bigger number.

The probe stays: `AppDiagnostics` is DEBUG-only, so it costs nothing in Release, and it is the
closest thing to a guard against someone re-isolating this — `main=true` in a scan log is the
signal.

**Owner's observation, same build:** *"it was smooth, no freeze."* So the fixed build is confirmed
on both counts — it measures clean and it looks clean.

⚠️ **What that does NOT establish is that the old build stuttered.** Only the fixed build was ever
watched. The severity of what was fixed remains an inference from 538 ms of main-thread blocking,
not an observation. Settling it would take an A/B: build once with the isolation restored, scan,
watch, then reinstall. Not done — offered and not taken up, which is a reasonable trade for a
half-second effect. **If anyone later asks "was this ever a real user problem?", the honest answer
is that it was never observed, only measured.**
