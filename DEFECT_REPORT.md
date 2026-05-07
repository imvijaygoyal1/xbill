# xBill — Senior Developer Defect Report
**Date:** 2026-05-06  
**Scope:** Full codebase audit — Services, ViewModels, Views, Models, Core, Edge Functions, SQL, Tests, Widget  
**Analyst:** Automated multi-agent review (5 parallel agents)  
**Status:** Report only — no fixes implemented

---

## Executive Summary

| Severity | Count |
|---|---|
| Critical | 20 |
| High | 45 |
| Medium | 62 |
| Low | 47 |
| Architectural | 4 |
| **Total** | **178** |

Critical findings include: race conditions on shared state (NotificationStore, CacheService), Swift model/DB schema mismatches that will crash at decode time (Expense.payerID, Group.createdBy), missing RLS UPDATE policy that silently blocks the entire edit-expense feature, recurring expense logic that incorrectly marks new instances as future recurring templates, and cross-user data leaks via stale AppState on sign-out.

---

## CRITICAL FINDINGS

### CRIT-01 — Model crash: `Expense.payerID` non-optional but DB column is nullable
**File:** `xBill/Models/Expense.swift:18` + `supabase/migrations/017_fix_user_delete_constraints.sql:17`  
Migration 017 ran `ALTER COLUMN paid_by DROP NOT NULL`. The Swift model declares `let payerID: UUID` (non-optional). Any group where the original payer deleted their account will crash at Codable decode with `DecodingError.valueNotFound`. Affects all expense fetches.

### CRIT-02 — Model crash: `BillGroup.createdBy` non-optional but DB column is nullable
**File:** `xBill/Models/Group.swift:17` + `supabase/migrations/017_fix_user_delete_constraints.sql:4-11`  
Same root cause as CRIT-01. Fetching any group whose creator deleted their account crashes the app.

### CRIT-03 — Missing RLS UPDATE policy on `expenses` — edit expense always fails
**File:** `supabase/migrations/001_initial_schema.sql:148-158`  
The initial schema defines SELECT, INSERT, DELETE policies but NO UPDATE policy on the `expenses` table. Every call to `ExpenseService.updateExpense` is silently rejected by Postgres for every user. The entire edit-expense UI flow is broken at the DB level.

### CRIT-04 — `AppState` stale nav targets not cleared on sign-out — cross-user data leak
**File:** `xBill/Core/AppState.swift:27-48`  
`AppState.shared` is a process-lifetime singleton. `pendingQuickAction`, `spotlightTarget`, `pendingNotificationTarget`, and `pendingAddFriendUserID` are never cleared on sign-out. A new user signing in on the same device immediately navigates to the previous user's group or opens Add Friend with the previous user's contact UUID.

### CRIT-05 — Race condition: `NotificationStore` concurrent read/mutate/write with no synchronisation
**File:** `xBill/Services/NotificationStore.swift:46-115`  
`NotificationStore` is `@unchecked Sendable` with no actor, lock, or serial queue. `merge`, `markRead`, `markAllRead`, `delete`, and `save` all follow the pattern: read from UserDefaults → mutate array → write back. Concurrent callers (ActivityService TaskGroup + ActivityViewModel) can each read the same stale array, mutate it, and the last writer silently wins — dropping read-state changes, re-showing dismissed items, or duplicating entries.

### CRIT-06 — Race condition: `CacheService` JSONEncoder/JSONDecoder shared across concurrent callers
**File:** `xBill/Services/CacheService.swift:31-41`  
`JSONEncoder` and `JSONDecoder` are not thread-safe. `CacheService` stores them as shared instance properties and declares `final class: Sendable` without any isolation mechanism. Concurrent `save`/`load` calls corrupt the encode/decode step.

### CRIT-07 — `GroupViewModel.computeBalances` serial N sequential `fetchSplits` blocking main actor
**File:** `xBill/ViewModels/GroupViewModel.swift:82-97`  
A `for expense in expenses` loop awaits `expenseService.fetchSplits` one-at-a-time. For a group with 50 expenses, this is 50 sequential network round-trips while blocking the MainActor between suspensions. Should be `withTaskGroup`.

### CRIT-08 — `GroupViewModel.recordSettlement` uses stale `splitsMap` — race condition
**File:** `xBill/ViewModels/GroupViewModel.swift:247-260`  
`splitsMap` is only refreshed when `load()` runs. If another device settles between the last load and this settlement, already-settled splits are included in `splitsToSettle`, causing duplicate `settleSplit` DB calls. If `computeBalances` partially failed (errors silently dropped), splits may be entirely missed from the settlement.

### CRIT-09 — `HomeViewModel.computeBalances` strong self-capture keeps VM alive indefinitely
**File:** `xBill/ViewModels/HomeViewModel.swift:174-213`  
`withTaskGroup` child tasks capture `self` (HomeViewModel) strongly. Each child makes 1 + 1 + N network requests per group. If the user navigates away, the structured concurrency scope keeps HomeViewModel alive and all fetched data in memory until every request finishes — potentially tens of seconds with no cancellation.

### CRIT-10 — `HomeViewModel.loadAll` never refreshes `archivedGroups`
**File:** `xBill/ViewModels/HomeViewModel.swift:64-84`  
`loadAll()` and `refresh()` only fetch active groups. `archivedGroups` is only refreshed by `loadArchivedGroups()` called from GroupListView's `.task`. Archiving a group from GroupDetailView leaves `archivedGroups` stale until the user explicitly visits GroupListView.

### CRIT-11 — `AddExpenseViewModel.save` fire-and-forget Task — unstructured, never cancelled
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:163-172`  
`Task { await expenseService.notifyExpenseAdded(...) }` creates an unstructured task with no cancellation handle. It continues running after view dismissal and has no error propagation path. Same pattern in GroupViewModel lines 270-282.

### CRIT-12 — `AddExpenseViewModel.save` race between `canSave` check and live-computed `amount`
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:128-135`  
`amount` is computed live from `amountText`. If `amountText` changes between the `canSave` guard and the `if isForeignCurrency` branch, `finalAmount` used for saving differs from the value `convertedAmount` was computed for. An expense is saved with mismatched local and converted amounts.

### CRIT-13 — Service `Sendable` conformances declared without actual isolation
**File:** Multiple — `CacheService.swift`, `ActivityService.swift`, `ExpenseService.swift`, `GroupService.swift`, `FriendService.swift`, `IOUService.swift`, `CommentService.swift`, `PaymentLinkService.swift`, `NotificationService.swift`  
All declare `final class: Sendable` without actor isolation or locks. Swift 6 strict concurrency will surface data races on any mutable stored state added in future. This is a systemic pattern flaw across the entire service layer.

### CRIT-14 — `SupabaseManager` singleton init race condition at launch
**File:** `xBill/Core/SupabaseClient.swift:18-37`  
Non-isolated `private init()` accesses `Bundle.main.infoDictionary`, constructs `SupabaseClient` (sets up auth state listeners), and `emitLocalSessionAsInitialSession: true` synchronously emits a session-change event from inside `init`, which re-entrantly accesses `KeychainManager.shared` before Keychain setup is complete.

### CRIT-15 — `AuthViewModel.startListeningToAuthChanges` — calling it twice leaks the first loop
**File:** `xBill/ViewModels/AuthViewModel.swift:58-79`  
`for await ... in authStateChanges` loop has no cancellation handle. Calling it a second time (scene reconnect, app foreground) creates a second subscriber. Both loops call `loadCurrentUser()` concurrently on auth events, producing race conditions on `currentUser`.

### CRIT-16 — Recurring expense `createDueRecurringInstances` — new instance gets wrong `recurrence`/`nextDate`
**File:** `xBill/ViewModels/GroupViewModel.swift:166-208`  
The newly created recurring instance is given `recurrence: expense.recurrence` and `nextOccurrenceDate: newNextDate`. A concrete past-due occurrence should have `recurrence: .none` and `nextOccurrenceDate: nil`. As-is, it will trigger itself on the next run. The template's `clearNextOccurrenceDate` should instead advance to `newNextDate`, not clear it — otherwise the template never fires again.

### CRIT-17 — Vacuous archive-warning tests that never exercise production code
**File:** `xBillTests/GroupFlowTests.swift:274-286, 301-323`  
`testArchiveWarningShownWhenBalancesExist`, `testArchiveWarningHiddenWhenSettled`, `archiveWarningPluralSingular`, and `toolbarActionDependsOnArchivedState` construct plain Swift arrays or local closures in the test body and assert on those — never calling any production type. These tests would pass even if the corresponding production code was deleted.

### CRIT-18 — `ExpenseDetailView` swipe-to-delete comment: no confirmation, error silently swallowed, UI desynced on failure
**File:** `xBill/Views/Expenses/ExpenseDetailView.swift:138-146`  
`onDelete` fires without a confirmation dialog. `try? deleteComment` discards the error. On failure, the comment is still removed from the local `comments` array (line 143), leaving the UI permanently out of sync with the database.

### CRIT-19 — `GroupDetailView` swipe-to-delete expense: no confirmation dialog
**File:** `xBill/Views/Groups/GroupDetailView.swift:253-256`  
Cascade-deletes all splits. No `confirmationDialog`. The `ExpenseDetailView` delete path correctly uses a confirmation dialog; this path does not.

### CRIT-20 — `SettleUpView` / `FriendsView` settle actions fire immediately with no confirmation
**File:** `xBill/Views/Groups/SettleUpView.swift:70-79` / `xBill/Views/Friends/FriendsView.swift:398-402`  
Both "Mark Settled" and "Settle All" are irreversible financial actions that trigger push notifications. Neither has a confirmation dialog.

---

## HIGH FINDINGS

### H-01 — Missing RLS DELETE policy on `splits` — direct split deletion blocked
**File:** `supabase/migrations/001_initial_schema.sql:177-192`  
`splits` has SELECT, INSERT, UPDATE but no DELETE policy. Any direct `DELETE FROM splits` client call fails RLS. Cascade from expense ON DELETE CASCADE works server-side, but any future cleanup path will silently fail.

### H-02 — `profiles` RLS blocks group members from reading each other's display names
**File:** `supabase/migrations/001_initial_schema.sql:21-30`  
`own read` policy restricts SELECT to `auth.uid() = id`. Group members cannot read each other's profiles. Any `supabase.table("profiles").select().in("id", values: memberIDs)` returns zero rows. A "members of shared group can read each other's profiles" policy is missing.

### H-03 — `device_tokens` table missing UPDATE RLS policy — token refresh upserts fail
**File:** `supabase/migrations/016_create_device_tokens_table.sql:13-17`  
`FOR ALL` in Postgres/Supabase does not cover UPDATE (UPDATE requires its own `USING` clause). APNs token refresh upserts (`ON CONFLICT DO UPDATE`) fail RLS, accumulating stale tokens. Migration 019 adds a UNIQUE constraint but does not fix the missing UPDATE policy.

### H-04 — `notify-friend-request` leaks `fromUserID` (PII) in APNs payload
**File:** `supabase/functions/notify-friend-request/index.ts:97`  
A user's internal UUID is PII. It passes through Apple's servers in plaintext and is accessible via lock-screen notification extensions. The previous audit (L5) removed `expenseId`/`settlementId` for exactly this reason; `fromUserID` was not treated consistently.

### H-05 — Edge Function badge count = unsettled split count, not unread notification count; O(N) DB queries per send
**File:** `supabase/functions/notify-expense/index.ts:111,164-171` / `notify-comment/index.ts:126,179-186`  
Badge semantics are wrong: settling a split decrements the badge without a notification being read. For a group with 20 members on 2 devices each, one expense triggers 40 extra DB queries (one per device token). Fallback `count ?? 1` sets a phantom badge on DB error.

### H-06 — `IOUService.fetchUserByEmail` queries `profiles` directly — email enumeration
**File:** `xBill/Services/IOUService.swift:43-51`  
Issues a raw `.eq("email", value:)` against `profiles`, bypassing the `lookup_profiles_by_email` SECURITY DEFINER RPC that was added specifically to prevent this. Any authenticated user can enumerate the full profiles table one email at a time.

### H-07 — `GroupService.createGroup` non-atomic — creator not added as member if second request fails
**File:** `xBill/Services/GroupService.swift:97-104`  
Group row inserted, then `addMember` called in a separate round-trip. On crash or network drop between the two, the group exists in the DB but the creator is not a member. `fetchGroups` (member-ID-first lookup) will never surface this group — it is permanently invisible.

### H-08 — `ExchangeRateService` applies Double-precision rates to Decimal amounts
**File:** `xBill/Services/ExchangeRateService.swift:29-35,62`  
`rates: [String: Double]`. Converting `Double` → `Decimal` propagates binary floating-point error (e.g., 1.0823 → 1.082299999...) into what is supposed to be exact decimal arithmetic. All multi-currency balance calculations are systematically imprecise.

### H-09 — `ActivityService.fetchRecentActivity` silently swallows per-group errors
**File:** `xBill/Services/ActivityService.swift:25-33`  
`try? await self.items(for: group)` returns `[]` on failure. The caller sees a partial result with no error and no indication that entire groups are missing from the activity feed.

### H-10 — `AuthService.updateDeviceToken` non-atomic delete + insert — push notifications silently lost
**File:** `xBill/Services/AuthService.swift:136-142`  
Delete at line 139, insert at line 141, no transaction. On crash or network drop between the two steps the user has no device token and silently stops receiving push notifications.

### H-11 — `SplitCalculator.validateExact` reports signed (not absolute) "Remaining" value
**File:** `xBill/Services/SplitCalculator.swift:100-107`  
`absDiff` is named to imply absolute value but is actually `round(diff)`, which is still signed. When splits exceed total, the user sees "Remaining: -0.10" — misleading and incorrect.

### H-12 — `SplitCalculator.splitEqually` percentage rounded to integer — percentages don't sum to 100
**File:** `xBill/Services/SplitCalculator.swift:38-39`  
`percentage` is rounded with no scale argument (rounds to nearest integer). A $10 three-way split produces percentages 33/33/33 = 99, not 100. In the percentage-split UI this creates a false validation error.

### H-13 — `SplitCalculator.minimizeTransactions` can infinite-loop on non-zero residual balances
**File:** `xBill/Services/SplitCalculator.swift:126-147`  
The while loop only advances `ci`/`di` when a balance reaches exactly `.zero`. If cross-group merges in HomeViewModel produce tiny residuals, neither index advances and the loop hangs the UI indefinitely.

### H-14 — `AddExpenseViewModel` state not reset between sheet presentations
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:44-53`  
`title`, `amountText`, `notes`, `splitInputs`, `convertedAmount`, `exchangeRate`, `isSaved`, `errorAlert` all retain values from the previous use. No `reset()` method exists. Re-opening the Add Expense sheet shows stale data.

### H-15 — `AddExpenseViewModel.convertedAmount` uses `.plain` rounding — systemic financial bias
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:118`  
`.plain` rounding truncates at .005 boundary. Financial applications should use `.bankers`. Split amounts may not sum to `finalAmount`, triggering false validation errors on foreign-currency exact-split expenses.

### H-16 — `GroupViewModel.deleteExpense` has no `isLoading` guard — concurrent deletes possible
**File:** `xBill/ViewModels/GroupViewModel.swift:212-222`  
Unlike `updateExpense` and `addMember`, `deleteExpense` does not set `isLoading = true`. Multiple rapid swipe-to-delete gestures can fire concurrently.

### H-17 — `GroupViewModel.archiveGroup` removes from active cache only — archived cache not updated
**File:** `xBill/ViewModels/GroupViewModel.swift:133-141`  
Archived group removed from active cache but not added to any archived-groups cache. Offline users won't see the newly archived group in the archived list until network is available.

### H-18 — `HomeViewModel` multiple async methods run concurrently without guards — TOCTOU on `groups`/`archivedGroups`
**File:** `xBill/ViewModels/HomeViewModel.swift:86,99,108,114`  
`refresh()`, `loadArchivedGroups()`, `unarchiveGroup()` can run concurrently. `unarchiveGroup` reads `groups`, suspends for network, then removes from `archivedGroups` — but `loadAll()` may have replaced both arrays in the meantime.

### H-19 — `HomeViewModel.createSampleData` swallows all errors — group created with no expenses, no feedback
**File:** `xBill/ViewModels/HomeViewModel.swift:133-162`  
All `try?` on `createExpense` calls. If all three fail, a group exists in the cache but is empty, with no error shown to the user.

### H-20 — `AuthViewModel.signUp` missing `AppError.isSilent` guard — cancellation errors shown as alerts
**File:** `xBill/ViewModels/AuthViewModel.swift:95-110`  
Every other auth action has `guard !AppError.isSilent(error)`. `signUp` does not, so a task-cancelled error shows a confusing alert.

### H-21 — `AuthViewModel.isEmailValid` trivially weak — accepts malformed emails
**File:** `xBill/ViewModels/AuthViewModel.swift:41-44`  
`email.contains("@") && email.contains(".")` passes `@.`, `a@b.`, `@example.com`. Same issue in `InviteMembersView.isValidEmail`.

### H-22 — `AuthViewModel.startListeningToAuthChanges` — `.userUpdated` skips `loadCurrentUser` if user already set
**File:** `xBill/ViewModels/AuthViewModel.swift:67-69`  
`if currentUser == nil { await loadCurrentUser() }` — `userUpdated` events (profile/password changes) never trigger a profile refresh. `currentUser` stays stale after the update.

### H-23 — `ProfileViewModel.saveProfile` — avatar uploaded before profile updated; orphaned image on failure
**File:** `xBill/ViewModels/ProfileViewModel.swift:86-104`  
`uploadAvatar` succeeds; `updateProfile` throws. The image is orphaned in Supabase Storage, the profile still references the old URL, and no cleanup occurs.

### H-24 — `ProfileViewModel.loadStats` silently swallows auth errors — shows misleading $0 stats
**File:** `xBill/ViewModels/ProfileViewModel.swift:53-82`  
Auth errors (expired JWT) are caught and silently ignored. The UI shows "0 groups, $0 paid" while the user's session is actually invalid. Auth errors should trigger re-authentication, not be swallowed.

### H-25 — `ProfileViewModel.signOut` clears `user` only — previous user's PII persists in VM
**File:** `xBill/ViewModels/ProfileViewModel.swift:108-115`  
`displayName`, `venmoHandle`, `paypalEmail`, stats fields all remain set after sign-out. If the VM is retained or re-used, the next user's Profile screen briefly shows the previous user's data.

### H-26 — `ActivityViewModel.load` non-atomic fetch then `unreadCount` read — stale badge TOCTOU
**File:** `xBill/ViewModels/ActivityViewModel.swift:23-33`  
`fetchRecentActivity` calls `NotificationStore.merge()` internally. Then `unreadCount = store.unreadCount()` is read separately. A concurrent `markRead` between the two yields a stale (too high) badge count.

### H-27 — `ActivityViewModel` surfaces `AppError.unauthenticated` as a raw error alert
**File:** `xBill/ViewModels/ActivityViewModel.swift:27`  
No `AppError.isSilent` check. "unauthenticated" is meaningless to end users; it should force sign-out, not display an alert.

### H-28 — `ReceiptViewModel.grandTotal` ignores user-edited `tipAmount` — always uses OCR tip
**File:** `xBill/ViewModels/ReceiptViewModel.swift:44-50`  
`var tip: Decimal { scannedReceipt?.tip ?? .zero }` reads from the scan result, not from the editable `tipAmount: String` field. User corrections to the tip never affect totals or splits.

### H-29 — `ReceiptViewModel.startManually` does not reset `confidence`, `parsingTier`, `errorAlert`, `isScanning`
**File:** `xBill/ViewModels/ReceiptViewModel.swift:141-156`  
If called after a failed scan, these fields retain scan metadata. The review UI shows confidence/tier badges on a manually-entered receipt.

### H-30 — `ReceiptViewModel.scan()` does not clear stale state before new scan — old results shown on error
**File:** `xBill/ViewModels/ReceiptViewModel.swift:68-86`  
On a "Scan Again" that throws, `scannedReceipt`, `items`, `merchantName`, `tipAmount`, `totalAmount` retain values from the previous successful scan. The user sees stale results paired with a new error message.

### H-31 — `HomeView` passes `UUID()` as `currentUserID` before `loadCurrentUser` completes
**File:** `xBill/Views/Main/HomeView.swift:186-190`  
`currentUserID: vm.currentUser?.id ?? UUID()`. If the user taps a group before the user loads, `GroupDetailView` uses a random UUID for all permission checks and balance calculations.

### H-32 — `MainTabView` passes `UUID()` as `currentUserID` to `FriendsView` before user loads
**File:** `xBill/Views/Main/MainTabView.swift:39`  
`FriendsView(currentUserID: homeVM.currentUser?.id ?? UUID(), ...)`. IOU ownership direction will be wrong for the entire session if the tab renders before `loadCurrentUser()` completes.

### H-33 — `ActivityView` double-load: `.task` and `.onAppear` both trigger loading on first appear
**File:** `xBill/Views/Main/ActivityView.swift:28-29`  
Both `.task { await vm.load() }` and `.onAppear { vm.refreshUnreadCount() }` fire. On every tab switch, `.onAppear` refreshes the count but `.task` does not re-fire — unread count refreshes but the item list does not.

### H-34 — `GroupDetailView` `.task` fires `createDueRecurringInstances` without completion check — partial DB writes on cancellation
**File:** `xBill/Views/Groups/GroupDetailView.swift:61-63`  
If the user navigates away mid-execution, the task is cancelled mid-write, potentially leaving some recurring instances created and others not. The function is called again on every view appearance with no guard for already-created instances.

### H-35 — Widget always shows `$` regardless of user's group currencies
**File:** `xBillWidget/xBillBalanceWidget.swift:73,81,84`  
All formatting uses `String(format: "$%.2f", ...)`. Non-USD users always see a dollar sign. `BalanceEntry` carries no currency code.

### H-36 — Widget timeline has a single entry; stale data shown indefinitely under iOS low-power
**File:** `xBillWidget/xBillBalanceWidget.swift:37-41`  
One entry, one `.after(refresh)` policy. No `.atEnd` fallback. Under low-power conditions where the host delays wakeup, the widget shows stale data with no visual indicator.

### H-37 — Widget shows "You owe $0.00" permanently if App Group not registered
**File:** `xBillWidget/xBillBalanceWidget.swift:43-49`  
`UserDefaults(suiteName:)` returns nil if the App Group is not registered; falls back to `.standard`; `double(forKey:)` returns 0.0. No error state, no "data unavailable" text, no last-refresh timestamp shown.

### H-38 — `GroupDetailView` dead `toolbar` property — duplicate of `groupMenu`, never applied
**File:** `xBill/Views/Groups/GroupDetailView.swift:395-447`  
`toolbar` and `groupMenu` contain identical menus. `toolbar` is never applied with `.toolbar { toolbar }`. Dead duplicated code that will diverge from `groupMenu` silently.

### H-39 — `AddExpenseView.applyReceiptSplits` uses `NSDecimalNumber.stringValue` which can produce scientific notation
**File:** `xBill/Views/Expenses/AddExpenseView.swift:357-362`  
`NSDecimalNumber(decimal: total).stringValue` returns `"5E-3"` for small values. `Decimal(string:)` in the ViewModel cannot parse scientific notation, silently setting the amount to zero.

### H-40 — `ContentView.onTrySampleData` uses a throwaway `HomeViewModel()` — sample data not reflected in live view
**File:** `xBill/Views/Main/ContentView.swift:36-38`  
A brand-new `HomeViewModel()` is constructed, `createSampleData` called on it, then discarded. The live `HomeViewModel` in `MainTabView` never knows about the data. User sees nothing after tapping "Try with sample data" until manual pull-to-refresh.

### H-41 — `VisionService.reconcile` force-unwraps `Decimal(string:)!` — crashes in European locales
**File:** `xBill/Services/VisionService.swift:533-534,545`  
`Decimal(string: "0.02")!` uses the current locale. In locales where `.` is a thousands separator, the parse returns nil and the force-unwrap crashes.

### H-42 — `PaymentLinkService` passes display name as Venmo/PayPal username — payment links broken for all users
**File:** `xBill/Services/PaymentLinkService.swift:23-24`  
`suggestion.toName` (e.g. "Alice Smith") is passed as the Venmo `recipients` / PayPal username. No mechanism exists to store actual payment usernames. The payment link feature is structurally broken.

### H-43 — `ExpenseDetailView` two `.task` modifiers race on same state without `id:` parameter
**File:** `xBill/Views/Expenses/ExpenseDetailView.swift:171-196`  
Splits fetch (line 171) and comments fetch (line 180) are plain `.task` with no `id:` — not cancellable on rapid navigate-away-and-back, and concurrent failures both write to `self.error`, the second silently discarding the first.

### H-44 — `ReceiptViewModel.asSplitInputs` silently excludes members rounded to zero amount
**File:** `xBill/ViewModels/ReceiptViewModel.swift:129-137`  
`isIncluded = input.amount > .zero`. A member assigned only low-cost items whose share rounds to $0.00 is excluded from the bill entirely, silently removing them from the expense.

### H-45 — Balance computation duplicated between `GroupViewModel` and `HomeViewModel` — can diverge
**File:** `xBill/ViewModels/GroupViewModel.swift:82` / `xBill/ViewModels/HomeViewModel.swift:215`  
Both independently fetch expenses and splits for the same groups and call `SplitCalculator.netBalances`. If either diverges in filtering logic (e.g., settled split handling), the Group Detail balance will differ from the Home screen balance for the same group.

---

## MEDIUM FINDINGS

### M-01 — `AddExpenseViewModel.recomputeSplits` silently no-ops on zero amount — UI shows stale split amounts
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:83-96`  
`guard total > .zero else { return }` returns without clearing `splitInputs[i].amount`. Clearing the amount field leaves the UI showing the last-computed split amounts.

### M-02 — `AddExpenseViewModel.canSave` does not check `splitValidationError` — invalid exact splits can be saved
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:68-74`  
`splitValidationError` is UI-only. The save path proceeds even when splits don't sum to total.

### M-03 — `AddExpenseViewModel` locale decimal parsing silently produces $0 on European keyboards
**File:** `xBill/ViewModels/AddExpenseViewModel.swift:57-59`  
`amountText.replacingOccurrences(of: ",", with: ".")` converts `1.234,56` (German) → `1.234.56`, which `Decimal(string:)` (C locale) fails to parse, returning `.zero`.

### M-04 — `GroupViewModel.refresh()` TOCTOU on `splitsMap` from concurrent `computeBalances` runs
**File:** `xBill/ViewModels/GroupViewModel.swift:79`  
Two concurrent `computeBalances` calls both build a fresh `var map` then assign `splitsMap = map`. The second assignment overwrites the first before `netBalances` has consumed the first result.

### M-05 — `GroupViewModel.recordSettlement` strong self in `withThrowingTaskGroup` — prevents deallocation during settlement
**File:** `xBill/ViewModels/GroupViewModel.swift:253-260`  
`[weak self]` should be used; lack of it can delay deallocation for the duration of the settlement network operation.

### M-06 — `HomeViewModel.unarchiveGroup` — group lost from both lists if `loadAll()` fails after server unarchive
**File:** `xBill/ViewModels/HomeViewModel.swift:108-119`  
`archivedGroups.removeAll` succeeds client-side before `loadAll()` is called. If `loadAll()` fails, the group is removed from archived and not present in active — it disappears from the UI despite existing on the server.

### M-07 — `HomeViewModel` widget cache write races with concurrent `computeBalances`
**File:** `xBill/ViewModels/HomeViewModel.swift:211`  
Two concurrent `computeBalances` calls both write `CacheService.shared.saveBalance` and call `WidgetCenter.shared.reloadAllTimelines()`. The second write reflects a mix from two runs.

### M-08 — `AuthViewModel.toggleMode` error clear races with in-flight network response
**File:** `xBill/ViewModels/AuthViewModel.swift:166-172`  
`errorAlert = nil` in `toggleMode` is immediately overwritten if a concurrent sign-up failure completes in the same event loop turn. No `isLoading` guard on this clear.

### M-09 — `AuthViewModel` stale `currentUser` after `.userUpdated` event
**File:** `xBill/ViewModels/AuthViewModel.swift:67-69`  
`if currentUser == nil { await loadCurrentUser() }` — on `.userUpdated`, `currentUser` is already set so the profile is not refreshed. Profile changes don't propagate to the VM.

### M-10 — `ProfileViewModel.load()` unconditionally overwrites unsaved in-progress edits
**File:** `xBill/ViewModels/ProfileViewModel.swift:36-49`  
A background `load()` (pull-to-refresh) silently discards any in-progress `displayName` edits.

### M-11 — `ProfileViewModel.loadStats` miscounts expenses — counts all group expenses, not user-paid
**File:** `xBill/ViewModels/ProfileViewModel.swift:56-75`  
`totalExpensesCount` is "total expenses in all groups" (all payers). `lifetimePaid` correctly filters by `payerID == userID`. The label is semantically misleading.

### M-12 — `ActivityViewModel.markRead`/`markUnread` local items and store can diverge on write failure
**File:** `xBill/ViewModels/ActivityViewModel.swift:40-49`  
Local `items` array is mutated regardless of whether `store.markRead` succeeded. On next `load()`, items will revert to unread, causing UI flicker.

### M-13 — `ActivityViewModel.markAllRead` hardcodes `unreadCount = 0` instead of reading from store
**File:** `xBill/ViewModels/ActivityViewModel.swift:35-37`  
If `store.markAllRead()` silently fails, the badge shows 0 but the store still has unread items; next `load()` re-shows the badge.

### M-14 — `ReceiptViewModel.scan()` two-step struct mutation — brief UI flash with empty `assignedUserIDs`
**File:** `xBill/ViewModels/ReceiptViewModel.swift:163-166`  
Replacing an item in the array then setting `assignedUserIDs` in two steps may trigger two `@Observable` UI updates — a momentary flash where assigned users appear empty.

### M-15 — `ReceiptViewModel` shared instance re-use shows stale scan on next sheet open
**File:** `xBill/ViewModels/ReceiptViewModel.swift` (overall)  
Neither `scan()` nor `startManually()` fully resets all state. If the VM is re-used on the next sheet presentation, stale scan results appear before the user scans.

### M-16 — `currentUser` held in both `AuthViewModel` and `HomeViewModel` — profile updates desync them
**File:** Cross-cutting: `AuthViewModel`, `HomeViewModel`  
`ProfileViewModel.saveProfile` updates `AuthViewModel.currentUser` but `HomeViewModel.currentUser` is only refreshed on its own `loadCurrentUser()`. Display name can be stale on the home screen after a profile update.

### M-17 — `GroupService.groupChanges` / `CommentService.commentChanges` — inner AsyncStream Tasks not cancelled
**File:** `xBill/Services/GroupService.swift:276-287` / `xBill/Services/CommentService.swift:134`  
Unretained `Task` handles spawned inside `AsyncStream` initializer cannot be cancelled when the stream terminates. They leak until the underlying channel delivers one more event.

### M-18 — `FriendService.sendFriendRequest` fires unstructured notification Task — duplicate notifications on rapid taps
**File:** `xBill/Services/FriendService.swift:62-63`  
`Task { await notifyFriendRequest(...) }` is not cancelled if the caller's task is cancelled. Rapid double-taps send duplicate push notifications.

### M-19 — `AppLockService.migrateFromUserDefaultsIfNeeded` — nonisolated function accesses Keychain from uncontrolled thread
**File:** `xBill/Services/AppLockService.swift:33-40`  
Called from `@MainActor init()` but marked `nonisolated`. Calls `KeychainManager.shared.save()` from an uncontrolled thread inside a `@MainActor` class.

### M-20 — `AuthService.fetchProfile` catch-all creates orphan profiles on network errors
**File:** `xBill/Services/AuthService.swift:168-188`  
Catches ALL errors from `.single()`, including network-offline, RLS denial, schema mismatch. Falls into the upsert branch on any failure, potentially creating a new profile row instead of surfacing the real error.

### M-21 — `CommentService.addComment` reads push preference from `UserDefaults.standard`, not App Group suite
**File:** `xBill/Services/CommentService.swift:54`  
`UserDefaults.standard.bool(forKey: "prefPushComment")` — all other persistence uses the App Group suite. If the app writes preferences to the group suite, comment push notifications never fire.

### M-22 — `VisionService.processScan` quality check only runs on the first page in multi-page mode
**File:** `xBill/Services/VisionService.swift:72-78`  
Blurry or dark subsequent pages bypass the quality gate and silently produce garbage OCR results mixed into the final output.

### M-23 — `ExportService.generateCSV` — no locale on DateFormatter; inconsistent locale in output
**File:** `xBill/Services/ExportService.swift:28-36`  
Amounts use C locale (`.`), dates use system locale. A French user's CSV has locale-formatted dates and C-locale numbers — an inconsistency that can break spreadsheet import.

### M-24 — `ExportService.generatePDF` column layout overflows page width — "Paid By" column clipped
**File:** `xBill/Services/ExportService.swift:126-131`  
Last column starts at x=508, right margin is at 547 (595-48). "Paid By" text is clipped in generated PDFs.

### M-25 — `IOUService.fetchIOUs` parallel queries — non-snapshot-consistent IOU list
**File:** `xBill/Services/IOUService.swift:20-39`  
Lender and borrower queries run as `async let` but may not represent the same DB snapshot. An IOU settled between the two returns as settled in one and unsettled in the other; after deduplication the winner is non-deterministic.

### M-26 — `IOUService.settleAllIOUs` — no concurrency guard; concurrent individual settle causes double-settle
**File:** `xBill/Services/IOUService.swift:98-110`  
Fetches IOUs then settles in a `ThrowingTaskGroup`. If the user taps individual Settle simultaneously, both see `isSettled = false` and both issue UPDATE.

### M-27 — `NotificationStore.merge` does not deduplicate within `newItems` itself
**File:** `xBill/Services/NotificationStore.swift:46-51`  
`existingIDs` only deduplicates against stored items. Two entries for the same expense from parallel group fetches in `ActivityService` are both inserted.

### M-28 — `NotificationItem.settlement` uses `UUID()` as its ID — settlement notifications never deduplicated
**File:** `xBill/Models/NotificationItem.swift:87`  
`SettlementSuggestion.id` is `UUID()` computed locally. Every app launch generates new UUIDs; `NotificationStore.merge` never deduplicates settlement notifications, filling the 100-item cap with duplicates.

### M-29 — `KeychainSessionStorage.retrieve` silently converts Keychain errors to nil — unexpected sign-out after reboot
**File:** `xBill/Core/KeychainSessionStorage.swift:27-32`  
`try?` drops `errSecInteractionNotAllowed` (Keychain locked until first unlock). The Supabase SDK interprets nil as "no session" and forces re-authentication. Users signed out on first post-reboot open.

### M-30 — `AppError.from(_:)` converts `CancellationError` to `.unknown` — cancellation shown as alert
**File:** `xBill/Core/AppError.swift:54-57`  
Any ViewModel that calls `AppError.from(error)` without first checking `AppError.isSilent(error)` shows a confusing "The operation was cancelled" alert on navigation-triggered task cancellation.

### M-31 — Schema/model mismatch risk: `Expense.title` vs `description` DB column
**File:** `xBill/Models/Expense.swift:15` / `supabase/migrations/001_initial_schema.sql:121`  
Migration 001 creates `description text`. The Swift model has `var title: String` with no CodingKey. If migration 008 (`expenses_align_schema.sql`) was not applied, every expense SELECT crashes at decode and every INSERT fails with a column-not-found error. Must verify migration was applied.

### M-32 — `send_friend_request` RPC — reverse request creates a second row; duplicate friendships
**File:** `supabase/migrations/020_friends_table.sql:17,55`  
`UNIQUE (requester_id, addressee_id)` and `ON CONFLICT DO NOTHING` only handle the same-direction pair. If A→B is pending and B also sends to A, a second B→A row is inserted. Both rows persist; `fetchFriends` returns duplicates, and accepting one leaves the other dangling as "pending" forever.

### M-33 — `lookup_profiles_by_email` still returns `email` in results — same enumeration gap as search_profiles
**File:** `supabase/migrations/018_lookup_profiles_by_email.sql:9-10,19-20`  
Migration 021 fixed `search_profiles` to omit email. `lookup_profiles_by_email` still returns `email text`, allowing any authenticated user to confirm email registrations via contact list lookup.

### M-34 — `Receipt.expenseID` and `imageURL` both optional — rootless receipt entity can persist to DB
**File:** `xBill/Models/Receipt.swift:14-15`  
A Receipt can exist with neither a linked expense nor a stored image. Downstream display logic expecting one of these may render a blank unidentifiable receipt row.

### M-35 — `GroupDetailView` filter empty state shows "No expenses match your search" when a category filter (not search) is applied
**File:** `xBill/Views/Groups/GroupDetailView.swift:221-222`  
The empty state message is hardcoded to the search case. No filter-specific empty message exists.

### M-36 — `GroupDetailView` `.searchable` applied inside a ZStack, not directly in a NavigationStack context — may not appear
**File:** `xBill/Views/Groups/GroupDetailView.swift:56-57`  
`.searchable(placement: .navigationBarDrawer)` requires a NavigationStack context. Applied to a `Group` inside a `ZStack` in a pushed view is fragile and can result in the search bar not appearing.

### M-37 — `InviteMembersView` email validation too permissive — accepts `@.` as valid
**File:** `xBill/Views/Groups/InviteMembersView.swift:26-28`  
`emailInput.contains("@") && emailInput.contains(".")` passes `@.`, `a@b.`, `@example.com`.

### M-38 — `InviteMembersView` send button shows "Send 0 Invites" when list is empty
**File:** `xBill/Views/Groups/InviteMembersView.swift:91`  
Button reads "Send 0 Invites" and is disabled when `pendingInvites` is empty. Should be hidden or show a neutral label.

### M-39 — `AppLockService.authenticate` in `.task` — no re-entrancy guard; concurrent LAContext calls on rapid lock/unlock
**File:** `xBill/Views/AppLockView.swift:53`  
`.task { await lockService.authenticate() }` fires on every view appearance. Rapid backgrounding/foregrounding can put multiple concurrent `LAContext.evaluatePolicy` calls in flight.

### M-40 — `ActivityView` grouping key uses locale-dependent `shortFormatted` string — non-deterministic sort order
**File:** `xBill/Views/Main/ActivityView.swift:55-65`  
Date group headers are locale-dependent strings (e.g., "5/6/26" vs "06.05.26"). Sort comparison falls back to `Date` comparison (correct) but header strings vary by region, making them untestable and non-localizable.

### M-41 — `ProfileView.AppLock Toggle` accesses `AppLockService.shared` in a `Binding` — bypasses `@Observable` observation
**File:** `xBill/Views/Profile/ProfileView.swift:199-215`  
The `Binding` reads `AppLockService.shared` directly. ProfileView's body does not declare a dependency on `lockService`, so changes from `ContentView`'s `scenePhase` handler may not update the Toggle.

### M-42 — `FriendsView.loadAll` queries `profiles` table directly — bypasses service layer, untestable
**File:** `xBill/Views/Friends/FriendsView.swift:289-323`  
Direct `SupabaseManager.shared.table("profiles")` in a view. Breaks MVVM separation, not covered by any service-level test.

### M-43 — `AddFriendView` — in-flight `searchTask` not cancelled when sheet dismissed and VM destroyed
**File:** `xBill/Views/Friends/AddFriendView.swift:21`  
`@State private var searchTask: Task<Void, Never>?` — on VM deallocation the task is abandoned without cancellation, potentially writing to released state.

### M-44 — `ReceiptScanView` multiple rapid photo selections can interleave — non-deterministic `capturedPages`
**File:** `xBill/Views/Expenses/ReceiptScanView.swift:195-208`  
`onChange(of: selectedPhoto)` spawns an uncancelled `Task` per change. Rapid selections produce concurrent tasks writing to `vm.capturedPages` non-deterministically.

### M-45 — `ReceiptReviewView.ItemRow.priceText` not updated when `item.unitPrice` changes externally
**File:** `xBill/Views/Expenses/ReceiptReviewView.swift:188-213`  
`priceText` is set only in `.onAppear`. When `vm.reconcile()` or `vm.updateQuantity()` changes `item.unitPrice`, the text field shows the stale original price while the model is updated.

### M-46 — `NotificationStore` tests share real App Group `UserDefaults` — no test isolation
**File:** `xBillTests/P1NotificationTests.swift:14-155`  
Tests use `NotificationStore.shared` backed by the real App Group suite. On a device where the group is unregistered, they silently fall back to `.standard` — a different backing store than production. Test cleanup relies on `clearAll()` working correctly.

### M-47 — `CacheServiceBalanceTests` uses 0.01 tolerance on financial data — masks real precision bugs
**File:** `xBillTests/P2FeatureTests.swift:236-238`  
A $100 balance stored/retrieved as $99.99 still passes. Tolerance should be tightened or storage fixed to use `Decimal`/`String`.

### M-48 — `GroupListView` shows search bar in the fully-empty state (no groups at all)
**File:** `xBill/Views/Groups/GroupListView.swift:39-51`  
A search bar over an empty list serves no purpose and shows "0 results" if the user types.

### M-49 — `GroupListView` has no "no search results" empty state
**File:** `xBill/Views/Groups/GroupListView.swift:73-116`  
When `filteredGroups` and `filteredArchivedGroups` are both empty due to a query, the scroll view renders blank with no `ContentUnavailableView`.

### M-50 — `QuickAddExpenseSheet` silently falls back to empty members list on network failure
**File:** `xBill/Views/Groups/QuickAddExpenseSheet.swift:42`  
`(try? await GroupService.shared.fetchMembers(groupID:)) ?? []` — no error state, no retry. `AddExpenseView` opens with zero members; user cannot assign splits.

### M-51 — `GroupInviteView.qrCodeView` silently renders nothing if QR generation fails
**File:** `xBill/Views/Groups/GroupInviteView.swift:83-101`  
Returns an empty `Group { }` with no error message or retry affordance if `invite.inviteURL` is nil or `generateQRCode` returns nil.

### M-52 — `MyQRCodeView` generates QR synchronously on main thread on every `body` evaluation
**File:** `xBill/Views/Profile/MyQRCodeView.swift:23,70-79`  
`var qrImage: UIImage?` is a computed property called from `body`. `CIContext()` allocation and `CIFilter` are CPU-intensive main-thread work on every re-render. Should be cached in `@State` computed once in `.task`.

### M-53 — `GroupInviteView.generateQRCode` re-creates `CIContext()` on every call
**File:** `xBill/Views/Groups/GroupInviteView.swift:138-148`  
`CIContext` is expensive to allocate and is intended to be shared/reused. Recreated on every tap of the "Refresh" toolbar button.

### M-54 — `GroupStatsView` monthly chart hidden when only 1 month of data — valid single-bar suppressed
**File:** `xBill/Views/Groups/GroupStatsView.swift:58-59`  
`if monthlyData.count > 1` hides the chart for a group with all expenses in one month. `>= 1` is correct.

### M-55 — `CreateGroupView.canCreate` does not validate `inviteEmail` — invalid invite silently fails
**File:** `xBill/Views/Groups/CreateGroupView.swift:29`  
Group is created even with an invalid `inviteEmail`. The invite call is `try?`-ignored; the user gets no feedback that the invite failed.

### M-56 — `SplitCalculatorTests` — `equalSplitExcluded` has no test for all-excluded edge case
**File:** `xBillTests/SplitCalculatorTests.swift:39-51`  
No test where all participants are excluded from equal split. This is a potential divide-by-zero or NaN in `SplitCalculator.splitEqually`.

### M-57 — `SplitCalculatorTests` — no test for `splitByPercentage` when percentages don't sum to 100
**File:** `xBillTests/SplitCalculatorTests.swift` (coverage gap)  
All percentage tests use inputs summing to exactly 100. Under-sum and over-sum are untested; the rounding-remainder absorption produces incorrect amounts in those cases.

### M-58 — `SplitCalculatorTests.CircularDebt` assertion uses `?? .zero` fallback — masks spurious zero entries
**File:** `xBillTests/SplitCalculatorTests.swift:243-253`  
`?? .zero` means a bug that inserts a non-nil `Decimal(0)` entry would still pass. Assertion should be `XCTAssertNil` or explicitly check for nil/zero.

### M-59 — `GroupFlowUITests` cancels archive dialog by tapping a normalized screen coordinate — breaks on different device sizes
**File:** `xBillUITests/GroupFlowUITests.swift:205`  
`app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()` — breaks on iPad, with keyboard up, or with different presentation styles. Should use `app.buttons["Cancel"].firstMatch`.

### M-60 — `OnboardingUITests` accesses password fields by positional index — fragile
**File:** `xBillUITests/OnboardingUITests.swift:75-81`  
`passwordFields[0]` and `passwordFields[1]` by raw index. Any added or reordered field silently fills the wrong field; the test continues to pass.

### M-61 — `OnboardingUITests.testSignInValidatesEmail` never verifies button becomes enabled with valid input
**File:** `xBillUITests/OnboardingUITests.swift:89-108`  
Test verifies button is disabled with bad input but never verifies it becomes enabled with good input. Cannot catch a regression where the button stays permanently disabled.

### M-62 — `invite-member` Edge Function — invite email has no join link or App Store URL — recipient cannot join
**File:** `supabase/functions/invite-member/index.ts:86-99`  
Email says "join the group automatically" but provides no deep-link, no App Store link, no join token. Recipients have no way to join the specific group; the claim of automatic join is false.

---

## LOW FINDINGS (selected highlights)

| ID | File | Line(s) | Issue |
|---|---|---|---|
| L-01 | `AddExpenseView.swift` | 39-43 | Hardcoded strings not wrapped in `String(localized:)` — no localisation |
| L-02 | `ExpenseDetailView.swift` | 110-114 | Hardcoded `.green` for "Settled" — not a semantic design token |
| L-03 | `ExpenseDetailView.swift` | 55-57 | `Label` category icon not hidden from accessibility — VoiceOver reads image name |
| L-04 | `ReceiptScanView.swift` | 149 | Document camera button disabled without explanation — no accessibility hint |
| L-05 | `ReceiptReviewView.swift` | 125-135 | Alert "Add Item" fields not reset on system dismiss gesture — stale values pre-filled on next open |
| L-06 | `SettleUpView.swift` | 54-56 | Settlement amount shown in `.red` — inconsistent with `Color.moneyNegative` design token |
| L-07 | `EmailAuthView.swift` | 36-42 | Subtitle text duplicated between `XBillPageHeader` and inner `VStack` |
| L-08 | `EmailAuthView.swift` | 13 | No `submitLabel` or `.onSubmit` — keyboard Return key does not advance focus between fields |
| L-09 | `MainTabView.swift` | 45 | `badge(unreadCount > 0 ? unreadCount : 0)` — `.badge(0)` is a no-op; conditional is dead logic |
| L-10 | `MainTabView.swift` | 146-151 | `showAddFriendFromQR` sheet shows blank if `currentUser` is nil — no loading state or dismiss button |
| L-11 | `FriendsView.swift` | 82-84 | `contactSuggestions` is `@State` but `loadAll()` never populates it — "From Your Contacts" section never appears |
| L-12 | `AddFriendView.swift` | 33-35 | `addFriendURL` force-unwrapped with `!` — unnecessary; should use optional check |
| L-13 | `MyQRCodeView.swift` | 20 | `URL(string:)!` force-unwrap on deep-link URL |
| L-14 | `GroupInviteView.swift` | 83-101 | Same force-unwrap pattern as L-13 |
| L-15 | `ProfileView.swift` | 275 | Version falls back to "1.0" silently if `CFBundleShortVersionString` missing in CI build |
| L-16 | `KeychainManager.swift` | 18 | Service ID `"com.xbill.app"` doesn't match bundle ID `com.vijaygoyal.xbill` |
| L-17 | `NetworkMonitor.swift` | 29-30 | `deinit` calls `monitor.cancel()` off main actor — potential data race on deallocation |
| L-18 | `Expense.swift` | 93-101 | `nextDate(from:)` returns unchanged date for `.none` recurrence — silent no-op, misleads callers |
| L-19 | `Split.swift` | 74-83 | `SplitInput.init(from: Split)` sets `displayName: ""` — silent display bug if caller forgets to fill |
| L-20 | `Friend.swift` | 27 | `status` is `let` — accept/decline cannot mutate local model; full refetch required, unenforced |
| L-21 | `NotificationItem.swift` | 94 | Settlement events forced to `category: .other` — conflated model; future event types will need same workaround |
| L-22 | `delete-account/index.ts` | all | No CORS headers or OPTIONS handler — inaccessible from web clients |
| L-23 | `notify-expense/index.ts` et al. | 16-24 | Module-level JWT cache with no mutex — concurrent Deno isolates race on expiry boundary |
| L-24 | `AuthService.swift` | 151 | Avatar URL has no cache-busting parameter — stale CDN serves old image after update |
| L-25 | `GroupService.swift` / `FriendService.swift` | 257, 136, 162 | `createdAt: Date()` synthesised for looked-up profiles — actual registration date ignored |
| L-26 | `ExchangeRateService.swift` | 59 | No timeout on URLSession — can hang 60 seconds with no user feedback |
| L-27 | `ActivityService.swift` | 25-39 | Unbounded expense fetch per group — fetches all rows regardless of `limit` parameter |
| L-28 | `NotificationService.swift` | 38 | `"settlementID"` casing inconsistent with `"groupId"` in remote push payloads |
| L-29 | `VisionService.swift` | 342-359 | O(n²) row-grouping algorithm — measurable slowdown on multi-page dense receipts |
| L-30 | `FoundationModelService.swift` | 70 | `LanguageModelSession` recreated on every `parseReceipt` call — no session reuse |
| L-31 | `ExportService.swift` | 183-187 | Fixed temp filename; no cleanup; concurrent exports corrupt file; files accumulate |
| L-32 | `VisionService.swift` | 447-449 | First OCR row always assigned as merchant — metadata rows ("THANK YOU") become merchant name |
| L-33 | `SpotlightService.swift` | 37,43,54 | All Spotlight index/delete errors silently discarded — no debugging path |
| L-34 | `AddExpenseViewModel.swift` | 161 | Payer name falls back to "Someone" in push notification if payer not in loaded members |
| L-35 | `GreetingHelper.swift` | all | No unit tests — boundary hours (midnight, 5 AM, noon, 5 PM, 10 PM) unverified |
| L-36 | `BalanceMessageHelper.swift` | all | Zero unit tests — zero-balance Decimal equality untested |
| L-37 | `OnboardingUITests.swift` | 26-28 | Hardcoded marketing copy as selectors — breaks on any copy change or A/B test |
| L-38 | `GroupFlowUITests.swift` | 154 | `Int.random` group name — collision risk; test groups accumulate in Supabase across CI runs |
| L-39 | `GroupFlowUITests.swift` | 210-247 | UI test group created but never cleaned up from Supabase in tearDown |
| L-40 | `OnboardingUITests.swift` | 138-140 | `signInToggle` selector matches "Sign In" submit button — may tap wrong element |
| L-41 | `P2FeatureTests.swift` | 58-60 | `var` where `let` intended; "currency separation" test never exercises production code |
| L-42 | `SecurityFixTests.swift` | 82-83 | Migration test has silent `guard … else { return }` — vacuous if cleanup order changes |
| L-43 | `xBillBalanceWidget.swift` | 61,76-85 | Hardcoded RGB colours instead of `AppColors` design-system tokens |
| L-44 | `P1NotificationTests.swift` | all | No test for `NotificationItem.expense` factory with empty `groupEmoji` — possible leading-space subtitle |
| L-45 | `QuickAddExpenseSheet.swift` | 42 | Member-fetch failure gives no error state or retry — `AddExpenseView` opens with zero members |
| L-46 | `018_lookup_profiles_by_email.sql` | 9-10,19-20 | Returns `email` in results; same enumeration gap fixed in `search_profiles` via migration 021 but overlooked here |
| L-47 | `notify-expense/index.ts` et al. | 16-24 | Deno `std@0.224.0` upgraded (correct), but `esm.sh/@supabase/supabase-js@2` floating — unversioned minor updates |

---

## ARCHITECTURAL CONCERNS

### ARCH-01 — Balance computation duplicated between GroupViewModel and HomeViewModel — divergence risk
**Files:** `GroupViewModel.swift:82` / `HomeViewModel.swift:215`  
Both independently fetch expenses and splits for the same groups and invoke `SplitCalculator.netBalances`. Balance shown on Group Detail can differ from the Home screen for the same group.

### ARCH-02 — `AuthService.currentUserID` computed async property — back-to-back awaits can return different values
**File:** `xBill/Services/AuthService.swift:22-26`  
Two sequential `await currentUserID` calls can return different values if auth state changes between them. Any caller that calls it twice (check + use) may see inconsistent results.

### ARCH-03 — `IOUService.fetchIOUs` parallel queries — non-snapshot-consistent IOU list
**File:** `xBill/Services/IOUService.swift:20-39`  
Lender and borrower `async let` queries may not represent the same DB snapshot. A settled IOU between queries appears settled in one result and unsettled in the other.

### ARCH-04 — `currentUser` held in both `AuthViewModel` and `HomeViewModel` — profile updates desync them
**File:** Cross-cutting  
`ProfileViewModel.saveProfile` refreshes `AuthViewModel.currentUser` but `HomeViewModel.currentUser` is only refreshed by its own `loadCurrentUser()`. Display name can be stale on the home screen after a profile update.

---

## TOP PRIORITIES (recommended fix order)

| # | Finding | Why urgent |
|---|---|---|
| 1 | CRIT-01, CRIT-02 | App crashes on decode for any group/expense with a deleted creator or payer |
| 2 | CRIT-03 | Edit expense is silently broken for 100% of users at the DB level |
| 3 | CRIT-04 | Cross-user data leak — stale nav targets after sign-out |
| 4 | CRIT-05, CRIT-06 | Race conditions on shared mutable state — data loss in prod |
| 5 | CRIT-16 | Recurring expenses generate infinite self-triggering instances |
| 6 | H-01, H-02, H-03 | Additional RLS gaps — split deletion blocked, profile reads blocked, token refresh blocked |
| 7 | CRIT-07 | GroupViewModel blocks main actor with 50 serial network requests |
| 8 | H-07 | Group creation leaves creator-less orphan groups on network failure |
| 9 | CRIT-19, CRIT-20 | Destructive financial actions (delete expense, settle) with no confirmation |
| 10 | H-42 | Payment links structurally broken — display name ≠ username |
| 11 | H-28 | Receipt tip edits ignored in totals — core receipt flow is incorrect |
| 12 | M-31 | Verify migration 008 applied — if not, all expense fetch/insert fails |
