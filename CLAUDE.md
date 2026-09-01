# xBill — Claude Code Context

## Start here

**This file is the index, not the whole story.** It is large; do not read it end to end. Use
the document map to find the one file that owns your question, and the trap index to find out
what will bite you before you touch code.

**Reading order for a cold start**

1. **Trap index** below — check whether your area has a known trap. If it does, read the
   linked doc *first*. Every entry there cost at least one wasted debugging cycle.
2. **File Map** in this file — locate the code. It is the live index and is kept current;
   the dated fix logs are period records and may describe superseded behaviour.
3. **`AUDIT_REPORT.md`** — search it for the files you are about to change. If a defect ID
   already covers your symptom, read the fix before re-deriving it.
4. **`ARCHITECTURE.md`** — only if you need the wider design.

### Document map — who owns what

Each fact lives in exactly one place. Put new content where it belongs; do not restate it
elsewhere, and do not create a parallel doc.

| File | Owns | Do **not** put here |
|---|---|---|
| `CLAUDE.md` (this file) | Index: File Map, Key Patterns, trap index, dated fix logs | Per-defect detail — that is `AUDIT_REPORT.md` |
| `AUDIT_REPORT.md` | **Single source for findings.** Every defect: ID, file, issue, status, fix, verification | Log-reading instructions |
| `diagnostics/README.md` | **The only README under `diagnostics/`.** Index of investigations, which log is which, how to read it | Findings — link to the audit ID instead |
| `diagnostics/<date>-<slug>/` | Raw evidence only: logs, captures, verification output | A README — a `PreToolUse` hook blocks it |
| `HANDOFF_PAYMENT_HANDLES.md` | Third-party provider behaviour (Venmo/PayPal rules, URL shapes) | xBill defect detail |
| `NATIVE_PATTERNS.md` / `DESIGN.md` | SwiftUI conventions / the clay design system | Anything not about UI convention |
| `RELEASE_VERIFICATION.md` | Pre-submission runbook | Day-to-day verification |

### Before you touch these — known traps

Each row is a behaviour that already caused a real defect. Append a row when an investigation
turns one up; do not add a new prose block.

| Area | Trap | Read first |
|---|---|---|
| `PaymentHandleValidator`, `PaymentLinkService`, Settle Up, payment-return prompt, reviewer seed | Five non-obvious third-party/language behaviours: a fabricated handle is a **live deep link**; PayPal.Me ignores a non-two-decimal amount; PayPal will not render a self-payment; Swift's synthesized `Encodable` omits nil; `try?` flattening makes an explicit JSON null fall through to a fallback key | `HANDOFF_PAYMENT_HANDLES.md` |
| `ActivityView`, `ActivityViewModel`, `ActivityService`, `NotificationStore`, `RemoteNotificationService`, `NotificationItem` | An Activity row is **not** necessarily a `public.notifications` row — expense-derived history carries an *expense* id, so a write matches zero rows. And `.single()` is an Accept header, **not** an affected-row check: a zero-row match surfaces as *"Cannot coerce the result to a single JSON object"* | `AUDIT_REPORT.md` → `NOTIF-01`…`NOTIF-12` |
| Any screen binding `.errorAlert` | **Bind an `Identifiable` alert in exactly one place per view-model instance.** Two views binding the same optional compete: one presents, the other's dismissal writes `nil` back and tears it down — the alert flashes for ~1s and cannot be read. Bind at the NavigationStack **root**, which covers pushed children; presenting from a descendant is also unreliable mid-transition | `AUDIT_REPORT.md` → `AUTH-01`, and the `GroupListView:89` note below |
| Any `@Observable` ViewModel | Never construct one inline in a `navigationDestination` / `sheet` closure — SwiftUI rebuilds it on every parent re-render, wiping loaded state, and `.task` will not re-fire | *Key Pattern — Own ViewModels in @State, never inline in a view builder* |
| Any Supabase `insert`/`update`/`delete` | Without `.select()` the SDK sends `Prefer: return=minimal` and decoding fails. Never use `.single()` to check affected rows — go through `SupabaseWrite.requireAffected` | *Supabase Insert/Update — Always Chain .select()* |
| Any `Identifiable` model built per-refresh (`SettlementSuggestion`) | A stored `id` filled with `UUID()` gives structurally identical rows new identities on every recompute. SwiftUI rebuilds every row; inside an in-flight `List` animation `UICollectionView` aborts with "Invalid number of items in section". Derive identity from content instead of storing it | `AUDIT_REPORT.md` → `DEV-01` |
| Editing an expense (`ExpenseDetailView`, `ExpenseService`, `GroupViewModel`) | **`expenses.updated_at` is an optimistic-concurrency token, not a timestamp to display or parse.** It is an opaque `String?` on purpose — `timestamptz` is microsecond precision and `Date` is a `Double`, so decoding and re-encoding rounds it and *every* save reports a phantom conflict. Never "tidy" it into a `Date`. There is **no whole-struct `Expense` write** any more: `updateExpense` was deleted because `.update(expense)` sends the stale token back and undoes the guard. Every edit goes through `update_expense_with_splits`, which raises SQLSTATE **`XB409`** on conflict — match it with `AppError.isEditConflict`, never on message text. A nil token means "skip the check" **to the server**, so the client re-reads rather than sending one. Migration 051 is ✅ **deployed** (2026-08-31), but `p_expected_updated_at DEFAULT NULL` means **no shipped client sends a token yet** — the guard protects nobody until the client half ships, and 1.0–1.5 can still clobber forever | the 2026-08-31 fix log below, `supabase/migrations/051_expense_concurrency.sql`, `docs/superpowers/plans/2026-08-29-expense-optimistic-concurrency.md` |
| Settle Up / `settlements` | **Either party may record a payment** — the debtor *or* the creditor. Balances are every split minus every settlement. **`splits.is_settled` STAYS IN THE SCHEMA PERMANENTLY — decided 2026-08-29. Do not propose dropping it again.** No logic branches on it, and as of 2026-08-28 `Split` no longer *decodes* it either. "Read by nothing" was true of the logic and false of the decoding: clients on 1.0–1.5 decode it non-optionally, so a `DROP` throws `keyNotFound` on every split and kills expenses and balances outright. **There is no force-update mechanism in this app**, so that population never provably empties — the risk has no bounded tail, and the prize is one boolean on a small table. The client change already captured the whole benefit by making a write unrepresentable. `settlements` RLS: INSERT requires `recorded_by = auth.uid()` **and** `auth.uid() IN (from_user_id, to_user_id)`; DELETE requires `recorded_by = auth.uid()`; there is **no UPDATE policy** — a correction is delete-then-record | `supabase/migrations/041_settlements.sql`, `docs/superpowers/specs/2026-07-28-settlements-ledger-design.md` |

### When you finish a piece of work

In this order, every time:

1. **Verify before claiming.** `scripts/run-coverage.sh unit`, and a Release build if you
   touched anything `#if DEBUG`. Report the actual numbers.
2. **Never claim device/lifecycle behaviour from a green suite.** App Lock, Face ID, real app
   switches and push are not reachable from tests. Build, install on the physical device, have
   the user reproduce, then pull and read the log. Every serious defect in this project was
   found that way, with both suites green throughout.
3. **Update this file** — File Map for new/changed files, Key Patterns for new invariants, a
   dated fix-log entry. Annotate superseded entries in place; do not rewrite history.
4. **Update `AUDIT_REPORT.md`** — one row per defect: ID, file, issue, status, fix.
5. **Investigation evidence** → a new `diagnostics/<date>-<slug>/` folder holding logs only,
   plus one appended row in `diagnostics/README.md`. **Never add a second README.**
6. **Commit and push**, then record anything non-obvious and cross-session in memory.

**If a previous agent broke one of these conventions, consolidate rather than extend.** Two
documents describing one defect will drift, and the next reader may act on the stale one.

### Enforcement — this is not only advisory

`.claude/settings.json` (committed) carries two hooks, so the conventions above do not depend
on an agent choosing to read this file:

| Hook | Effect |
|---|---|
| `SessionStart` | Injects the six core rules into context at the start of every session. |
| `PreToolUse` on `Write` | **Blocks** creating a second README under `diagnostics/`, with the reason and where to put the content instead. |

`AGENTS.md` points non-Claude tools (Codex and similar) at this section. It is a pointer, not
a copy — a second copy would drift.

Review or disable the hooks with `/hooks`. If you change `.claude/settings.json` mid-session,
the watcher may not pick it up until `/hooks` is opened once or the session restarts.

### Standing build rules

- After every code change: run `xcodegen generate` if Swift files were added, build for the
  simulator, install on `DA97985A-F7CC-44F6-8281-9DD24C22B978`, launch once, and report the
  result.
- Before writing any SwiftUI view, read `NATIVE_PATTERNS.md`. `DESIGN.md` overrides native
  defaults only where explicitly documented; keep Apple behaviour for navigation, sheets,
  accessibility, inputs and data-flow safety.
- Never deploy migrations or modify live Supabase data without explicit approval. Read-only
  queries for diagnosis are fine and are often the fastest way to confirm a hypothesis.

## Release status — v1.5 (7) APPROVED 2026-08-27

**The release that makes push notifications work.** Delivery was device-confirmed before
submission, not after — the server halves went live during diagnosis, so this ships the client
side that makes the *first* attempt correct rather than the retry.

| Contents | |
|---|---|
| `PUSH-02` | the app records which APNs environment its token belongs to |
| `PUSH-01` | notification toggles finally mean **"notify me"**, honoured server-side; the three sender-side gates deleted; new **Friend Requests** toggle |
| `PUSH-03` | a second device no longer silently unregisters the first; sign-out unregisters only that device |
| `UIT-09` | the UI suite survives an erased simulator |

| Check | Result |
|---|---|
| Unit | **483 passed**, 0 failed, 0 skipped |
| UI regression | **22/22** on an erased simulator — first clean full run since the scroll probes were added |
| Widget | ✅ |
| Release build | clean |
| Backend | handles NULL `0` · migrations local = remote through **049** · six web endpoints + AASA + Apple's CDN all 200 |
| Archive | `1.5 (7)`, `UIDeviceFamily [1]`, region `en`, encryption `false`, 3 dSYMs, widget framework + `.appex` with `Assets.car`, Siri `nlu/` compiled |
| DEBUG-only symbols absent from Release | `scrollContentHeight` 0 · `ReceiptCorpus` 0 · `xbill-diagnostics` 0 |
| **Exported IPA** | **`aps-environment: production`**, distribution profile, `associated-domains` present |
| Privacy manifest | **9** collected types — `OtherDataTypes` added for the server-stored notification preferences (linked, App Functionality, not tracking); widget manifest present in the `.appex` |
| Privacy policy | corrected and **deployed**: the published page said preferences were *local*, which `PUSH-01` made untrue. All six endpoints 200, AASA still `application/json` |

### ⚠️ New runbook check: read `aps-environment` from the EXPORT, never the archive
A plain `xcodebuild archive` signs with the **development** profile, which **overrides** the
`production` value in `xBill.entitlements`. The 1.5 archive reports `development` and that is
**not** a defect — only the App Store export re-signs. Verified `production` on the exported IPA.

This is worth a command per release: a build shipped with `development` hands every App Store user
a **sandbox** token, which the notify functions would post to the production host and get
`BadDeviceToken` — silently, for everyone. That is `PUSH-02`/`PUSH-04` reproduced at the worst
possible scale, and nothing else in the pipeline would catch it.

### Approved 2026-08-27, first pass — including the privacy-manifest change
Six releases, six first-pass approvals. The added `OtherDataTypes` declaration and the corrected
privacy policy went through without a query.

### Now unblocked by approval
- ~~**`splits.is_settled`**~~ — **CLOSED 2026-08-29: the column stays, permanently.** It appeared on
  this list for six consecutive releases as unpaid debt. It is not debt; see the 2026-08-28/29
  entries below. Removed from the list so it stops resurfacing.
- **`expenses.updated_at`** — added in migration 043 and still unread, so two people editing one
  expense silently overwrite each other.
  ⚠️ **Superseded 2026-08-31.** Migration 051 is **deployed**: `updated_at` is `NOT NULL DEFAULT
  now()`, and `update_expense_with_splits` compares it and raises `XB409`. The client half is built
  on branch `worktree-expense-optimistic-concurrency` and **not yet released** — so the sentence
  above still describes what a live user experiences, because no shipped build sends a token. See
  the 2026-08-31 fix log.
- Any further migration or Edge Function work.

## Recent Fix Log — 2026-08-31 — expense edits stop overwriting each other

**Branch `worktree-expense-optimistic-concurrency`. Client half complete and green; migration 051
✅ DEPLOYED 2026-08-31 and verified against production without writing. The client half ships in
the next release — until then the guard protects nothing, because no shipped build sends a token.**

### The defect
`expenses.updated_at` was added by migration 043 on 2026-08-23 and **nothing ever read it**. Two
people editing the same expense therefore silently overwrote each other — last write wins, no
conflict, no warning, and the thing being overwritten is money. It has been listed as unpaid debt
under "Now unblocked by approval" in every release note since 1.2.

The guard is a compare-and-swap inside the existing `update_expense_with_splits`: the client sends
the `updated_at` it loaded as `p_expected_updated_at`, and the RPC updates only if the row still
carries it, raising SQLSTATE **`XB409`** otherwise.

### The second write was found during design, and deleted
`GroupViewModel.updateExpense` wrote the row a **second** time after the RPC had already saved it —
`.update(expense)` on the whole struct, which sends the client's **stale `updated_at` straight back
into the row**, undoing the guard microseconds after it passed. A wasted round-trip before this
change; a hole in the guard after it.

It is **deleted**, not guarded: `ExpenseService.updateExpense` was the only server-bound
whole-struct `Expense` write in the app, so removing it makes the clobber *unrepresentable* rather
than discouraged by a comment. `ExpenseDataProviding` lost the requirement too, so there is no
write method left to call. Same treatment as `settleSplit` and `fetchInvite`. Its replacement,
`GroupViewModel.applySavedExpense`, swaps the row in place and recomputes.

### The token is a `String`, and must stay one
`timestamptz` is **microsecond** precision; Swift's `Date` is a `Double` of seconds. Decoding to a
`Date` and re-encoding **rounds** the value, so `updated_at = p_expected_updated_at` would fail
against a row nobody had touched and *every save would report a phantom conflict*. A guard that
fires constantly is worse than no guard: it teaches people to ignore it. `Expense.updatedAt` is an
opaque `String?` — never parsed, never reformatted — and `ExpenseTokenTests` fails if anyone
"tidies" it into a `Date`.

Optional because `CacheService` holds entries written before the key existed. A non-optional would
fail to decode every one of them — the `splits.is_settled` failure in miniature, on our own cache.

### A nil token forces a re-read rather than "no check"
On the server a nil `p_expected_updated_at` means *skip the check*. That is correct for clients on
1.0–1.5 and **wrong for this client**, because a nil can also come from a pre-upgrade cache entry —
and the first edit after upgrading, right when the app has just reopened, is exactly the one most
likely to race. `ExpenseDetailView.currentToken()` re-fetches instead.

### `DEFAULT NULL` is the compatibility hinge — and old clients can still clobber
`p_expected_updated_at timestamptz DEFAULT NULL` is what keeps 1.0–1.5 working: they send 8 keys,
resolve to the same function, receive NULL, and skip the check. **They therefore remain able to
overwrite silently, and will until they update.** That cannot be fixed without breaking them, and
this app has no force-update mechanism.

### Key Pattern — a fetch is not a write, and only the write was the problem
The plan for `applySavedExpense` asserted **zero fetches**, copied from the payment paths where a
fetch is pure cost and its suspension crashed `UICollectionView` (DEV-03). The test failed, and it
was right to: `update_expense_with_splits` **DELETEs and re-INSERTs the splits**, so `splitsMap` is
stale the instant an edit lands, and recomputing from it shows the new amount against the old
shares — SPLIT-02 returning. A settlement cannot change a split; an edit always does. The read is
kept, with the reasoning recorded on the test so nobody optimises it away. What had to die was the
second *write*.

### Key Pattern — `grep -c '^Test case'` is not a test count
Three runs were reported as 533/535/539 from `grep -c` over piped `xcodebuild` output. The real
figures were 487/490/493. Parallel test clones interleave on one stream, so lines are duplicated
and occasionally truncated mid-word (one run logged `est case '...'`, losing the `T`). That made a
plan-vs-actual comparison look wrong and prompted a false claim that the plan's expected totals
were stale — they were exact. **Read counts from the result bundle**:
`xcrun xcresulttool get test-results summary --path <bundle>.xcresult`.

### Verification
Unit **493 passed, 0 failed, 0 skipped** (`TestResults/Coverage/2026.08.31_19-36-01-unit.xcresult`),
baseline 487. All three new suites confirmed **by name** in the bundle — `Expense concurrency
token`, `Edit-conflict error mapping`, `Applying a saved expense` — not inferred from exit status.
Debug and Release both build; installed and launched on the simulator.

`AppError.isEditConflict` was mutation-tested: forced to `return true` it fails **exactly**
`neighbouringCodeDoesNotMatch` and `messageAloneIsNotAConflict` (490 total, 488 passed, 2 failed),
leaving `exactCodeMatches` correctly passing. A matcher that cannot reject is not a matcher.

### ✅ Migration 051 DEPLOYED 2026-08-31

Preflight first, all read-only: 051 was the **only** pending migration (local = remote through
050); **60 of 62** expense rows had a null `updated_at` (the plan's "roughly 46" was written on
08-29 and the table had grown); **0** rows had a null `created_at`, so the backfill could not leave
a NULL and `SET NOT NULL` could not abort; and exactly **1** overload existed, with the 8-argument
signature the `DROP` names.

| Check | Result |
|---|---|
| `migration list --linked` | `051 \| 051 \| 051` |
| `null_tokens` | **0** |
| Column | `is_nullable = NO`, `column_default = now()` |
| Overloads | **1**, and it is the 9-argument signature — no orphaned 8-arg function (H-11 avoided) |
| Grants | `anon_exec = false`, `auth_exec = true` |
| Data | 62 expenses / 82 splits, unchanged |

**Both directions of the guard were proven against production without writing a byte.** Each probe
ran inside a `DO` block whose final `RAISE` aborts the transaction, so anything the call did was
rolled back — the plan's bare `SELECT` would have modified a real expense if the guard had been
broken, which is precisely the case a probe exists to detect:

- stale token (`1999-01-01`) → **`sqlstate=XB409`**, "This expense was changed by someone else"
- the row's **real** token → **accepted**, no phantom conflict — the microsecond round-trip works

Afterwards the probed row was byte-identical (title `Test`, amount `5.00`, same `updated_at`,
`updated_by` still null, 1 split) and `title LIKE 'PROBE%'` matched **0** rows.

### ✅ The client path round-trips against production — verified 2026-08-31

`testExpenseEditSendsConcurrencyTokenRegression` (new, in `RegressionUITests`) drives the real
thing: sign in → create a disposable `Regression-` group → add an expense at 42.50 → open it → Edit
→ 55.25 → Save. It passed, and it is the check that would have caught the ordering hazard, because
a client sending 9 keys to an unmigrated database resolves to no function and dies with `PGRST202`
— which no unit test can see, since PostgREST resolves an RPC by the exact key set it receives.

**Confirmed in the data, not on screen**, and an earlier run that failed before reaching the edit
left a natural control:

| Expense | amount | `updated_at` vs `created_at` | `updated_by` |
|---|---|---|---|
| edited | **55.25** | **advanced** (00:14:15 vs 00:13:44) | **`6180290a…`** |
| never edited | 42.50 | identical | `null` |

`updated_by` **only exists as of 051**, so a populated value is direct proof the new 9-argument
function ran rather than some fallback. Both disposable groups were then purged
(`scripts/purge-ui-test-groups.sh --execute`); production is back to 62 expenses / 82 splits with
`null_tokens = 0`.

Three accessibility identifiers were added to reach it — `xBill.expenseDetail.actions`,
`xBill.expenseDetail.editButton`, `xBill.editExpense.amountField`,
`xBill.editExpense.saveButton`. They are a contract with the suite; do not rename them.

⚠️ **Two traps cost a run each here.** A bare `xcodebuild` **omits the UI-test credentials** and
fails with "Set XBILL_TEST_EMAIL…", which reads like a crash because the summary says
*"Executed 0 tests… Restarting after unexpected exit"* — export them from
`xBillUITests/UITestCredentials.plist` or go through `scripts/run-coverage.sh`. And the expense
overflow menu had **no accessibility label at all**, unlike `GroupDetailView`'s "Group actions".

### NOT verified — read this before believing the feature works
- **No *shipped* client sends a token, so live users are not protected yet.** The server accepts
  `p_expected_updated_at` and every build in the wild omits it — the `DEFAULT NULL` compatibility
  hinge doing its job. Protection begins when this branch ships.
- **No two-device race was exercised.** The mechanism is proven; the race is not. It needs two
  accounts editing one expense.
- **Clients on 1.0–1.5 can still clobber**, by design, and will until they update.

## Recent Fix Log — 2026-08-28 — `Split` stops decoding `is_settled`, and the build that never ran

### "Read by nothing" was true of the logic and false of the decoding
Six release notes in this file recorded `splits.is_settled` as safe to drop because nothing reads
it. `netBalances` genuinely ignores it — but `Split.isSettled` was a **non-optional `Bool` with a
synthesised `Decodable`**, and splits are fetched with `select=*`. Dropping the column would have
omitted the key, thrown `keyNotFound` on **every split**, and broken expenses and balances for
every client on 1.0–1.5, including the build approved the day before.

**A column you never branch on is still a column you parse.** The fix is not to drop the column but
to stop the model decoding it: Swift's decoder ignores unknown keys, so `Split` now reads rows with
or without `is_settled`, which is what makes an eventual `DROP` safe. It also makes writing to the
flag unrepresentable rather than discouraged by a comment.

`flagIsIgnored` was deleted with it — it set `split.isSettled` and asserted balances ignored the
flag. With the property gone that guarantee is structural, so the suite is **482**, not 483.

### The branch sat unverified for a day because of the sandbox, not the toolchain
The change was committed on 2026-08-27 with a `*** THIS HAS NEVER BEEN COMPILED ***` banner: every
build that day wedged before compiling a single file. The variable that had never been tested was
the **agent shell's sandbox** — the same cause already recorded in this file for 2026-07-15. Re-run
with the sandbox disabled, it compiled in about two minutes and produced real errors.

**When a build fails before producing compile output, run one differential — same command, one
variable changed — before naming any cause.**

### What the green build then caught
Exactly what the parked commit predicted: the `BackfillEquivalenceTests` rework was half-finished.
The fixture dictionary was annotated `[UUID: [Split]]` while holding `[Row]` values, and
`netBalances` was handed `Row`s directly. A `splitsOnly` adapter had been written for precisely
this and left **unwired** — dead code in the parked commit, which is why nothing referenced it.

### Checked, because `Split` is `Codable` in both directions
Removing the keys stops `is_settled` being **sent** on insert as well as read. Safe:
`001_initial_schema.sql:169` declares `is_settled boolean not null default false`, so an INSERT
omitting it gets `false` and the `splits_settled_consistency` CHECK still holds. Every remaining
`isSettled` reference in app code belongs to `IOU`, a different model with its own live column.

### ~~Sequence to actually drop the column~~ — the column is NOT being dropped (2026-08-29)
The plan was merge → ship → wait for adoption → `DROP COLUMN`. **Step 3 has no end.** Every client
on 1.0–1.5 decodes `is_settled` non-optionally, and this app has **no force-update or
minimum-version mechanism** — verified by grep, nothing of the kind exists. So there is no date on
which the drop becomes safe, only a date on which you decide the remaining clients don't matter,
and the failure mode is total: `keyNotFound` on every split, expenses and balances dead.

Against that: the column is one boolean on a table recorded at ~82 rows. **The client change
already captured the entire benefit** — a write to the flag is now unrepresentable rather than
discouraged. The `DROP` adds no simplification, no speed, nothing.

**Decision: `splits.is_settled` stays in the schema permanently.** Not deferred — closed. If
someone reopens it, the gate is a *measured* one (a client-version column written at device-token
registration, DROP conditional on observed adoption), which is real work for a payoff of one
boolean, and is itself the argument for leaving it alone.

**Verification:** unit **482 passed, 0 failed, 0 skipped**
(`TestResults/Coverage/2026.08.28_07-04-22-unit.xcresult`); the `Backfill equivalence` suite
confirmed present **by name** with all 3 cases passing, not inferred from exit status.
**Not verified:** nothing on a device, and no migration run — the column is deliberately untouched.

### Privacy drift caught at submission, not by a tool
`PUSH-01` moved notification preferences from `UserDefaults` to `public.notification_preferences`,
and **two documents kept saying they were local** — `APPSTORE_PRIVACY_RECONCILIATION.md` and the
**published** privacy policy, which told users their notification choices never left the phone.
Nothing flags this: the manifest scanner checks required-reason APIs, not whether prose matches
behaviour. **When a change moves data across the device boundary, the privacy copy is part of the
change**, not a follow-up.

`PrivacyInfo.xcprivacy` now declares `OtherDataTypes`. A per-user setting transmitted off-device
and stored persistently meets Apple's definition of collected data, and this project has already
been blocked once by a manifest gap (`M5`, missing Contacts) — under-declaring is the expensive
direction.

### ⚠️ `_prefPushExpense` is still in the Release binary and is NOT the old key
`strings` finds `_prefPushExpense`: that is SwiftUI's `@State` backing storage for `ProfileView`'s
local toggle variable, which kept its name. The **UserDefaults keys** it is named after are gone —
`prefPushExpense`, `prefPushSettlement`, `prefPushComment` and `prefPushConfiguredAfterPermission`
each match **0** times as exact strings. Grep for the exact key, not a substring, or this reads as
a failed removal.

### What still needs a device once this is live
1. **The mute path** — turn off "New Expenses", confirm no push arrives **and** the Activity row
   still does. Only meaningful now that delivery works.
2. **Two devices, one account** (`PUSH-03`) — both should receive.
3. **First-attempt routing** — after this build registers, `device_tokens.environment` should be
   written correctly at registration, so no `corrected` appears in the function report.

## Recent Fix Log — 2026-08-26 (latest) — PUSH-04: push notifications delivered, for the first time

**✅ DEVICE-CONFIRMED by the owner: "I saw the push on device."** Phases 1 and 2 were both
necessary and neither was sufficient. This is what closed it.

### The report line that ended a month of guessing
After Phase 2 shipped, the owner reported a badge and an Activity row but no notification. **Both
of those are written without APNs being involved** — the Edge Function inserts the `notifications`
row before it contacts Apple, and `ActivityViewModel` sets the badge locally from that table. So
the two visible symptoms were fully explained by *zero* delivery, and proved nothing either way.

The functions returned HTTP 200, so nothing in `function_edge_logs` distinguished "delivered" from
"rejected". One `console.log` of the send report settled it in a single line:

```
[notify-expense] {"sent":0,"failed":1,"reasons":{"BadDeviceToken":1},"muted":0}
```

### `BadDeviceToken` does not mean the token is bad
It means *"not valid on **this** host"* — which has two causes needing opposite fixes: a wrong
recorded environment, or a provider-key/topic mismatch. Rather than guess, `deliver()` now retries
the **other** environment on `BadDeviceToken`:

- retry succeeds → the push lands **and** `device_tokens.environment` is corrected in place
- both hosts reject → the report says `BadDeviceToken(both:<reason>)`, which rules the environment
  out and points at the Apple key instead

The owner's row flipped `production` → `sandbox` and the push arrived. Their phone was running a
development-signed build; migration 048 had defaulted every pre-existing row to `production`,
because the client that writes the column ships in 1.5.

### Why this matters more than a one-off fix
**Every token registered before 048 is a guess**, and would have stayed wrong until that device
updated — for some users, never. The server now converges on the truth by itself, so correctness no
longer depends on the client shipping, and a user who moves between a TestFlight and an App Store
build is corrected on their next notification rather than going silent.

### Key Pattern — a symptom that survives the fix may not be evidence of the fix failing
The badge and the Activity row looked like partial success and were not: both come from a table
written *before* the network call they were being read as evidence of. **Before treating an
observation as evidence, name the code path that produces it.** Two independent user-visible
signals here had nothing to do with the subsystem under test.

### Key Pattern — instrument the boundary you cannot see across
`function_edge_logs` records the status code; it never records the body. A 200 from a function that
swallows an APNs rejection is indistinguishable from a delivery. **One log line of the outcome was
worth more than every inference drawn before it** — and it is now permanent, precisely so the next
failure is one query away instead of a week of hypotheses.

⚠️ **Supabase's log ingestion runs minutes behind**, and its analytics endpoint defaults to roughly
a 40-second window. An early query returned "0 invocations" for a period whose database writes were
already visible — a conclusion that was entirely an artifact of the default window. Always pass
`iso_timestamp_start`, and prefer a database check over a log check when both can answer.

### Still open
- **`device_tokens.environment` for everyone else is still a default**, not a measurement. They
  self-correct on their next notification, which is the point — but do not read the column as truth
  until a send has confirmed it.
- **1.5 should still ship**: the client writing `environment` at registration makes the first
  attempt correct rather than the second, and `PUSH-03` (a second device unregistering the first)
  and the recipient-side preference UI are client-side and unreleased.

## Recent Fix Log — 2026-08-25 — PUSH-01: the toggle gated the wrong person

Phase 2 of the push work. Phase 1 (`PUSH-02`, below) fixed *where* a notification was sent;
this fixes *whether*.

### "New Expenses" decided whether other people were notified
```swift
// AddExpenseViewModel.swift
if CacheService.defaults.bool(forKey: NotificationService.expensePreferenceKey) {
    await notifyExpenseAdded(...)
}
```
Nobody reads that label as *"suppress notifications for everyone in my groups"*, but that is what
it did — and `xBillApp.swift` registered the default as **`false`**. A payer who had never opened
Profile silently muted their whole group. Same shape for settlements (`GroupViewModel`) and
comments (`CommentService`); friend requests were ungated entirely, which is why that one path was
otherwise healthy.

The recipient's own preference was **never consulted by anything**, and could not be: it lived in
`UserDefaults` on the sender's device.

### Migration 049 — the place a recipient's choice can exist
`notification_preferences (user_id PK, expenses, settlements, comments, friend_requests,
updated_at)`, owner-only RLS in all three directions, `WITH CHECK` on UPDATE so a row cannot be
re-pointed at someone else (the gap 027 closed on four other tables).

**Every column defaults true, and a missing row also means on.** iOS is the real consent gate:
nothing displays without notification permission, and this app deletes its device token when it
finds permission revoked — so a token existing already means the person agreed. Defaulting to off
would have reproduced exactly the silence being fixed and required every existing user to go
find a setting.

### What changed where
| | |
|---|---|
| `_shared/apns.ts` | `recipientsAllowing(supabase, userIDs, column)` — one filter, four callers |
| all four functions | filter recipients by the recipient's own row; report `muted` (**per person**, not per token, now that a user may have several devices) |
| the three sender-side gates | **deleted** |
| `enableDefaultPreferencesAfterPermissionIfNeeded` + the four `prefPush*` defaults | **deleted** — they seeded state nothing reads any more |
| `NotificationPreferencesService` | new; server is authoritative, `UserDefaults` demoted to an offline cache so the switches are never blank |
| `ProfileView` | toggles write through and **revert on failure**; a new **Friend Requests** toggle, the one category that never had one |

### The in-app Activity row is deliberately NOT filtered
Muting a push means *"do not interrupt me"*, not *"hide this from my history"*. Every function
still writes its `notifications` row before consulting the preference — a row never written cannot
be caught up on later, and Activity is the only record of what happened.

### Fail open, and say so
If the preference lookup errors, everyone is allowed through and the response carries
`preferenceLookupFailed: true`. The two ways of being wrong are not symmetrical: notifying someone
who opted out is an annoyance they fix in one tap; suppressing everyone on a transient database
error is the failure that went a month unnoticed.

### Key Pattern — a routing or permission flag belongs to whoever owns the thing it acts on
Three flags in this feature were read from the wrong side of the wire: the APNs environment
(the recipient's signing), the notification preference (the recipient's choice), and the stale-token
verdict (APNs'). Ask of any flag crossing a boundary: **whose property is this?** If the answer is
"the other end's", it must not come from the request body or the sender's `UserDefaults`.

### Key Pattern — a test that compares against the constant it is guarding cannot fail
`absentCacheReadsAsOn` first asserted `cached == .default`. Against a mutant with every default
flipped to `false` — the exact original defect — **it passed**, because both sides moved together.
It now asserts the four booleans. Third instance of this in the project after `warningPenalises`
(`SCAN-02`) and `UIT-01`: assert the property that **distinguishes** the fix from the bug, never
one the fix merely happens to have.

**Verification:** unit **483/483**, 0 failed (7 new). Mutation-tested: flipping the defaults to off
fails exactly four tests and leaves the three that are independent of them passing. Debug and
Release both build; installed and launched.

**✅ DEPLOYED 2026-08-25**, migration before functions:

| Check | Result |
|---|---|
| `supabase migration list --linked` | `049 \| 049 \| 049` |
| Table | RLS on; SELECT/INSERT/UPDATE owner-only; UPDATE carries `WITH CHECK`; **0 DELETE policies**; all four columns default `true`; 0 rows |
| Functions | all four ACTIVE (expense v16, settlement v13, comment v11, friend-request v10) |
| Read path, live | absent row → `[]`, no `PGRST116`; after a write, the exact query `recipientsAllowing()` runs returns `expenses=false` |
| RLS, live | another user's row invisible; insert for another user → `42501`; anon sees nothing |

⚠️ **A client DELETE on this table answers 204 having deleted nothing** — there is no DELETE
policy, so it matches zero rows and the status describes the request, not the effect. Found while
verifying; recorded in the migration. Reset with an UPDATE setting every column true.

**Not verified, and not reachable from here:** that a muted recipient is actually skipped. Proving
it needs a second account with a device token, and the only other token-holders in production are
real people — exercising it would send them a real notification. It needs the same two-device test
that `PUSH-02`'s delivery claim needs; one session covers both.

## Recent Fix Log — 2026-08-25 — PUSH-02: the APNs host was chosen by the wrong device

Reported: *"why push notifications are not triggered when an expense is added"*. Two independent
defects, either of which alone stops delivery. **Phase 1 fixes the second; the first is scoped and
unbuilt.**

### The sender decided where the recipient's notification went
```javascript
const apnsHost = isDevelopment                    // ← all four notify functions
  ? 'https://api.sandbox.push.apple.com'
  : 'https://api.push.apple.com'
```
`isDevelopment` is `#if DEBUG` **on the sender's build**. Sandbox-vs-production is a property of
the **recipient's token** — of how *their* copy was signed. An App Store sender notifying a
debug-build recipient posted a sandbox token to the production host; a debug sender did the
reverse. **During testing that mismatch is the normal case**, which is why the owner's own device
received nothing.

`device_tokens` was `(id, user_id, token, platform, created_at)` — **no environment column**, so
the function could not have routed correctly even if it had wanted to.

### And it was deleting good tokens the whole time
The cleanup ran on `res.status === 410 || 400` and matched `Unregistered` **or `BadDeviceToken`**.
`BadDeviceToken` is exactly what a perfectly valid token returns when posted to the wrong host —
so every mismatched send **destroyed a working registration**, and the recipient had to reopen the
app before anyone could reach them again. Nothing recorded that it had happened.
`isDeadToken()` now matches `Unregistered` only.

### The fix
| Piece | |
|---|---|
| Migration **048** | `device_tokens.environment text not null default 'production'`, CHECK `('sandbox','production')` |
| `AuthService.apnsEnvironment` | the **only** place `#if DEBUG` legitimately answers this, because there it describes the local binary: Debug signs with `xBill.Debug.entitlements` (`aps-environment: development`), Release with `xBill.entitlements` (`production`) |
| `supabase/functions/_shared/apns.ts` | **new.** `apnsHost()`, `sendToToken()`, `isDeadToken()`, and the send report — the rule stated once |
| all four notify functions | select `environment`, send through `sendToToken`, return `{sent, failed, reasons}` |
| `isDevelopment` | **deleted** from all four client payloads and all four functions |

The shared module is deliberate. Four copies of one rule is how `INV-05` converted the emailed
invite link to https and **left the group QR on the custom scheme** for two more days.

### Silence used to look identical to success
Every function returned `{ sent: N }` counted from *tokens found*, not from APNs accepting them,
and the `catch` swallowed network errors entirely. The report now separates `sent` from `failed`
and names the reasons (`{"BadDeviceToken": 2}`) — never the tokens.

### What Phase 1 actually fixes, and for whom
Deploying the server half **without** an app update still helps: every row defaults to
`production`, so every user on the App Store build is now routed correctly **no matter who sends**.
The debug-build recipient — the owner's test device — stays wrong until it re-registers on 1.5.
That is the honest split: **production users are fixed by the deploy; the test device is fixed by
the release.**

### PUSH-01 is NOT fixed
The Profile toggle titled "New Expenses" still gates whether **other people** are notified when
**you** add an expense, and still defaults to `false`. The recipient's own preference is never
consulted and there is no server-side table to consult it in. That is Phase 2.

### Key Pattern — a routing decision belongs to whoever owns the thing being routed to
The sender cannot know how the recipient's app was signed, what their preferences are, or whether
their token is still live. Every one of those was being answered from the wrong side of the wire.
Ask, for any flag crossing a boundary: **whose property is this?** If the answer is "the other
end's", it must not come from the request body.

### Key Pattern — a cleanup rule needs the failure it fires on to mean what you think
`BadDeviceToken` was read as "this token is dead". It means "this token is not valid **here**" —
which is also what a correct token says on the wrong host. Deleting on it turned a routing bug
into data loss. Before acting destructively on an error code, write down what else could produce it.

**Verification:** unit **473/473**, 0 failed (4 new). Mutation-tested: renaming the `environment`
key fails exactly the two payload tests and neither build-constant test.
`scripts/check-apns-routing.sh` (new) asserts the rule across all four functions and was itself
mutation-tested three times — the first two versions **could not fire**, because they grepped for
words that appear in the explanatory comments. Debug and Release both build; installed and
launched on the simulator.

### PUSH-03 — a second device silently unregistered the first
Found while building the above and fixed at the owner's direction. `updateDeviceToken` ended with
`DELETE … WHERE user_id = ? AND token <> ?` — **every other token for that user**. A person with a
phone and a tablet could only be reached on whichever they opened last, and nothing said so.
`deleteDeviceTokens` had the mirror of it: revoking notifications on any one device unregistered
all of them.

The sibling delete is gone. Reaping is left to the one authority that knows a token is dead — APNs
answers `Unregistered` for an uninstalled app — and sign-out/revocation now names
`AuthService.lastRegisteredAPNsToken`. When this install has never seen its own token it falls back
to the old user-wide delete, deliberately: a token left behind means someone who revoked
notifications keeps receiving them (`MINOR-01`), which is worse than unregistering a sibling that
re-registers on next launch. `cleanupScope(lastRegistered:)` is pure so both directions are tested.

**Verification:** unit **476/476**, 0 failed (7 new across PUSH-02/03). Both mutation-tested:
renaming the `environment` key fails exactly the two payload tests; removing the cleanup fallback
fails exactly the two that assert it. Debug and Release both build; installed and launched.
`scripts/check-apns-routing.sh` passes and was itself mutation-tested three times — **its first two
versions could not fire**, because they grepped for words that also appear in the explanatory
comments.

**✅ DEPLOYED 2026-08-25**, migration before functions:

| Check | Result |
|---|---|
| `supabase migration list --linked` | `048 \| 048 \| 048` |
| Column | `environment text NOT NULL DEFAULT 'production'`, CHECK `('sandbox','production')` live and refusing a typo |
| Data | 4 rows, all `production`, **none touched** |
| Functions | all four ACTIVE (`notify-expense` v15, `notify-settlement` v12, `notify-comment` v10, `notify-friend-request` v9) |
| New code live | `notify-friend-request` returns `{"sent":0,"failed":0,"reasons":{}}` — the old build returned `{"sent":0}` |
| Auth guard | anon caller still gets **401** |

**Not verified, and not verifiable here:** that any notification arrives. **APNs does not deliver
to a simulator**, so no run in this project — green or otherwise — says anything about delivery.
Proving it needs two real devices on opposite builds, which is precisely the case that failed.

**Who this reaches today.** Every row defaults to `production`, so users on the App Store build are
now routed correctly **regardless of who sends**. A debug-build recipient — the owner's test device
— stays wrong until it re-registers, which happens on the first launch of the next release. So:
**production users are fixed by the deploy; the test device is fixed by 1.5.**

## Recent Fix Log — 2026-08-19 (latest) — the receipt scanner was measured for the first time

### 18%
`scripts/receipt-benchmark.sh` runs the shipped pipeline over **17 receipts with hand-written
ground truth** (`xBillTests/ReceiptCorpus/`, git-ignored — real receipts carry card digits and
addresses). 12 photographed paper receipts, 5 restaurant/rideshare including 3 dark-mode digital
screenshots. Every label's items + tax + tip reconciles to its printed total.

| Metric | Result |
|---|---|
| **TOTAL correct** | **3/17 (18%)** |
| **REFUSED outright** | **3/17** — all three dark-mode screenshots |
| TAX correct | 4/17 (24%) |
| Item count exact | 4/17 (24%) |
| Price recall | 29% |
| Name recall | 33% |

Every scanned receipt ran **Tier 2 heuristics** — Apple Intelligence is unavailable on the
simulator — so this measures exactly the code `SCAN-01`…`SCAN-06` changed.

### SCAN-07 — the quality gate refused every dark-mode digital receipt — FIXED
`checkImageQuality` rejected anything below a mean-luminance floor with *"Image is too dark — move
to better lighting and try again."* A dark-mode receipt screenshot is **mostly black by design**,
so all three in the corpus were refused before OCR ran, and the advice offered is meaningless for
a screenshot of an email. The check assumed its input was a photograph of paper; screenshotting an
emailed receipt is a normal way to hold one, and xBill accepts photo-library input, so this was
one tap away.

**The mean cannot separate the two cases.** An underexposed photograph and a correctly-exposed
inverted image both have a low mean. Only the second has a real population of **bright** pixels,
because its text is white. `exposureVerdict(meanLuminance:brightFraction:)` is a pure,
`nonisolated` rule over those two measurements; `brightPixelFraction` samples at 256px because
downscaling further averages thin white strokes into the background and would reintroduce the
very defect it exists to prevent.

Measured on the same 17 receipts, before → after:

| | before | after |
|---|---|---|
| REFUSED | **3** | **0** |
| TOTAL correct | 3/17 | 4/17 |
| TAX correct | 4/17 | 7/17 |
| Item count exact | 4/17 | 7/17 |
| Price recall | 29% | **46%** |
| Name recall | 33% | **51%** |

Uber now parses **perfectly** (total, tax, 3/3 items, 100% price and name); Chuko Ramen and Essex
Burger both reach 2/2 items at 100%/100%. Digital receipts parse far better than photographed
paper once they are allowed through — which is itself worth knowing.

### SCAN-08 — and then it refused a well-lit white receipt as "too bright"
Fixing the dark end surfaced its mirror immediately: the airport Starbucks receipt (18) was
refused with *"Image is too bright — reduce glare or avoid direct flash."* It is a white thermal
receipt, evenly lit, fully legible — **what a good receipt photo looks like.** Its mean luminance
is high because the paper is white and the print is sparse.

Identical defect, opposite end, and the same fix: **a high mean is only a problem if the other
tone has been destroyed.** A blown-out frame has no dark pixels left; white paper still has its
text. `exposureVerdict` now takes `darkFraction` as well, and `toneFractions` returns both in one
pass over the sampled bitmap.

Found only because the corpus contained a receipt of that kind — the unit tests written for
`SCAN-07` all passed throughout, because they encoded the same blind spot the code had.

Corpus effect of the pair, over 22 receipts: **refusals 4 → 0**, price recall 29% → 43%, name
recall 33% → 48%, tax 4/22 → 10/22.

### SCAN-09 / SCAN-10 — two ways the price pattern read the wrong number
Both in `extractDecimal`, both found by the corpus, both fixed:

- **SCAN-09** — an amount under a unit printed **without a leading zero** (`.05`, CVS bottle
  deposits) was invisible: the pattern required a digit before the separator. The integer part is
  now optional and a leading `.` is normalised before `Decimal(string:)`.
- **SCAN-10** — a **percentage rate** matched as an amount. `NY 8.875% TAX  .89` yielded `8.87`,
  because `8.875` contains `8.87` while the real amount had no leading digit — the two defects
  compounded, hiding the money and supplying a wrong number in its place. Two lookaheads now
  apply: `(?!\d)` rejects a third decimal digit (not money in any currency xBill supports), and
  `(?!\s*%)` rejects a two-decimal rate, which digit count alone cannot distinguish. `7.00%` and
  `8.00 %` both occur in the corpus.

Mutation-tested: reverting the pattern fails exactly the four defect tests while both regression
tests (`existingBehaviourPreserved`, `sizesIgnored`) correctly still pass.

**Honest result: the corpus aggregate did not move at all.** Byte-identical before and after —
TOTAL 5/22, price recall 43%, name recall 48%. The fixes are correct in isolation and proven so,
but on real OCR output they are masked by a defect further upstream, below.

### SCAN-11 — row grouping merged separate lines into one — FIXED, and it unblocked everything
`groupIntoRows` used a fixed threshold of `0.025` in **normalised** Y. Normalised Y depends on how
tall the receipt is and how many lines it holds, so one constant meant different things on
different receipts. On a 1000×3000 till slip it is ~75px while line spacing is ~40–60px, and
adjacent lines fused — the CVS receipt collapsed **six visual rows into one item** whose name was
six lines of text concatenated. Everything downstream operates on rows, so the column split
(`SCAN-06`), the price pattern (`SCAN-09/10`) and the discount keywords were all working on rubble.

**The fix is to measure rather than assume.** `OCRLine` now carries `height` — the normalised
bounding-box height Vision already reports — and the threshold is `median(height) × 0.6`. Text
height is what determines line spacing, so it is the only sound basis for deciding whether two
observations share a row. Line spacing is reliably above one text height and intra-row jitter well
below one, so 0.4–0.8 separates them; 0.6 sits mid-band rather than on an edge. `0.025` survives
only as the fallback when input carries no geometry (hand-built lines, cached rows).

Multi-page stacking compresses Y by the page count, so heights are compressed with it; the
separate `0.025 / pageCount` adjustment in `processScan` is gone.

**Corpus effect, 22 receipts:**

| | before | after |
|---|---|---|
| **TOTAL correct** | 5/22 (23%) | **15/22 (68%)** |
| **TAX correct** | 10/22 (45%) | **17/22 (77%)** |
| **Price recall** | 43% | **79%** |
| Name recall | 48% | 55% |
| Confidence gap | −0.18 | −0.04 |

`SCAN-06`, `SCAN-09` and `SCAN-10` had each moved the corpus by **zero** while this defect stood.
They are not worthless — they are the reason the numbers move now.

### SCAN-12 — phantom items — FIXED (35 → 5)
Once `SCAN-11` stopped merging rows, the failure mode inverted: the parser found **more** items
than exist. Payment, loyalty and summary lines that used to be swallowed into a merged row became
clean rows that parsed as items. This is the failure that costs money — a missing item is visible,
a phantom `AMOUNT PAID` gets assigned to somebody and silently charged.

**Every rule was derived from the 35 phantoms the corpus actually produced**, extracted by diffing
parsed against expected and read one by one. Not from imagination — which is how `credit` came to
match `CREDIT CARD PURCHASE` and turn a $13.80 payment into a −$13.80 discount.

Three groups:

1. **Metadata additions** — `due`, `balance`, `amount`, `tend`, `credit`, `debit`, `emv`,
   `method:`, `savings`, `coupons`, `you saved`, `items sold`. `due` rather than `balance due`
   because OCR returned *"Balanco Due"*, and the short word survives that.
2. **`isMeasurementOnly`** — a row with an amount but fewer than three letters once unit tokens are
   stripped is a weight or multiplier sub-line (`1.47 lb @ $3.99/lb`, `2 x 0.79`) or a bare figure
   (`$3.00`), not an item. Units are stripped as **whole tokens**: substring matching ate `Tea`,
   which contains `ea`.
3. **`savings` and `credit` removed from `discountKeywords`.** `SCAN-01` asserted that "plenty of
   receipts print a discount as a positive under a label". Across 22 real receipts that is false
   for exactly those two words — every positive line they matched was a summary (Kroger's savings
   totals, already reflected in item prices) or a payment. The item-level words (`discount`,
   `voucher`, `promo`, `off`, `rebate`) produced **zero** phantoms and stay.

**`charge` was tried and removed.** It suppressed one phantom (`CHARGE 13.55`) while destroying
Bhavani's `Total Charge:` and Uber's `CMH Airport Surcharge` — measured, reverted, and now covered
by a test asserting those three lines survive.

| | before | after |
|---|---|---|
| **Phantom items** | **35** | **5** |
| **Item count exact** | 8/22 (36%) | **14/22 (64%)** |
| Name recall | 55% | **64%** |
| TOTAL correct | 15/22 | 15/22 |
| Price recall | 79% | 75% |

**The price-recall dip is a deliberate trade.** Suppressing rows whose only name is a barcode or a
quantity prefix (`195882990040 10.47`, `1 @ 3.99  3.99`) loses their amounts until split-row
association exists. That is the right way round: an item named `195882990040` cannot be assigned to
a person, which is the whole purpose, and the loss surfaces as an items-vs-total mismatch the user
can see — whereas a phantom charge is invisible. **Visible incompleteness beats invisible
fabrication.**

### SCAN-13 — item name on one row, price on the next — FIXED
The largest remaining parsing loss, and the reason name recall trailed price recall. Four corpus
layouts split an item across two rows — Bhavani does it for all 14 items:

```
LAXMI GINGER POWDER 200 Gms          ← name, no price
     1 @    3.99          3.99       ← price, no usable name
```

It also happens on ordinary receipts when a long name simply **wraps**: GO by Citizens' "Vegetable
Spring Rolls" had its `$12.00` on the following line.

A row with no amount that reads as a name is **held**, and the next row carrying an amount but no
usable name of its own adopts it. The held name is cleared by **any** row with an amount, so it can
only ever reach the row immediately below — a name must not drift down the receipt attaching
itself to later prices (`heldNameUsedOnce` pins that).

**`isMeasurementOnly` needed a ratio, not just a count.** `"Reg 8.00  1.0 @ 8.00"` (Michaels)
clears the three-letter bar and is still a price row. A real name is mostly letters; a price row is
mostly digits, so letters ÷ non-space characters < 0.3 separates them where the count cannot.

| | before | after |
|---|---|---|
| **Price recall** | 75% | **90%** |
| **Item count exact** | 14/22 (64%) | **16/22 (73%)** |
| **Name recall** | 64% | **72%** |
| Bhavani (08) | 0/14, 0% | **12/14, 86%** |
| Michaels (03) name recall | 0% | **100%** |
| GO by Citizens (16) | 1/2 | **2/2, 100%** |

Confidence calibration crossed zero for the first time (**+0.02**) — still no real signal, but no
longer inverted.

### Key Pattern — substring keyword matching is the recurring defect in this file
Three separate bugs, one mechanism:

| Keyword | Matched inside | Damage |
|---|---|---|
| `credit` | `CREDIT CARD PURCHASE` | a $13.80 payment became a −$13.80 discount |
| `ea` (unit) | `Tea` | a real item suppressed as a measurement row |
| `table` | **`Vegetable`** | `Vegetable Spring Rolls` suppressed as furniture, so its wrapped price could never find it |

The third was found only because a split-row test failed for a reason that made no sense on
inspection. `isMetadata` now matches on **word boundaries**, asserted only where the keyword's own
edge is a word character so `www.`, `.com` and `method:` keep working. **Never add a short word to
a substring-matched keyword list** — and prefer boundary matching for all of them.

### Key Pattern — derive suppression rules from observed failures, never from plausibility
`discountKeywords` was written by imagining what a discount line looks like. Two of its eleven
words were wrong in a way that invented money, and it took a corpus to find out. The replacement
rules were read off 35 real phantoms. When a rule must decide what to *ignore*, the cost of a wrong
guess is silent, so the evidence has to come first.

### What the corpus says to fix next
### Key Pattern — a benchmark that reports only scores cannot tell you what to fix
Three fixes (`SCAN-06`, `SCAN-09`, `SCAN-10`) were correct, unit-tested, mutation-tested and moved
the corpus by **zero**, because a defect upstream of all three was destroying their input. That was
invisible until the report printed **parsed vs expected items** alongside the score. Add the dump
before the next round of parser work, not after.

### Tier 1 measured at last — on a physical iPhone 16 Pro (2026-08-22)
Every previous number in this file described **Tier 2 heuristics alone**, because Apple
Intelligence does not exist on the simulator. The benchmark now runs on device: the corpus is
copied into the test bundle by a build phase, since a sandboxed device cannot read the Mac's
filesystem. 22 receipts, 40 seconds.

**Apple Intelligence is available on the device and handled only 4 of 22 receipts (18%).**
The other 18 fell through to heuristics — `parseReceipt` throws and the `catch` drops to Tier 2.

| | simulator (all Tier 2) | device (mixed) |
|---|---|---|
| TOTAL correct | 15/22 | **17/22 (77%)** |
| TAX correct | 17/22 | **18/22 (82%)** |
| Item count exact | 16/22 | 14/22 |
| Price recall | 90% | 85% |
| Name recall | 72% | 70% |
| Confidence gap | +0.02 | **+0.19** |

**This settles the question that has hung over all the scanner work: the heuristic path is not
dead code.** It handles **82% of real receipts even on an Apple-Intelligence-capable device**, so
`SCAN-01`…`SCAN-14` reach the great majority of scans.

**And Tier 1 is not uniformly better.** On the four receipts it took:

| Receipt | Tier 1 (device) | Tier 2 (simulator) |
|---|---|---|
| 01 Kroger | ✗ total **21.12**, price 50% | ✓ total, price 80% |
| 03 Michaels | ✓ 2/2, 100% | ✓ 2/2, 100% |
| 04 Wayfair | ✓ but **1/2** items, 50% | ✓ 2/2, 100% |
| 13 Chuko | ✓ total | ✗ total nil |

It is **worse on two, equal on one, better on one**. Tier 1 running first is therefore not
self-evidently right, and "improve the LLM prompt" is not obviously the highest-value work —
the heuristics carry the load.

### ~~Unresolved: device vs simulator delta~~ — RESOLVED 2026-08-23
Receipts 06, 07 and 18 returned correct totals on device while the simulator showed `nil`. The
cause was neither SCAN-14 nor a Vision difference: the corpus copy phase added for this device run
writes into the `.xctest` **after signing**, so the simulator refused to launch the app and every
simulator benchmark after that point was measuring nothing. `SCAN-14` did land.

Device report retained at `xBillTests/ReceiptCorpus/reports/DEVICE-receipt-benchmark-2026-08-22.txt`.

### Key Pattern — TARGET_BUILD_DIR, not BUILT_PRODUCTS_DIR, for a host-embedded test bundle
The first device run reported "no corpus" in 0.001s while the build log said it had bundled 22
images. Both were true: the script wrote to `$BUILT_PRODUCTS_DIR/xBillTests.xctest`, but the bundle
that actually runs is the copy embedded at `$TARGET_BUILD_DIR` (`xBill.app/PlugIns/`). A build
phase that reports success into a directory nothing loads is indistinguishable from one that did
nothing.

### ~~Still open, found by the corpus~~ — five of six since fixed (reviewed 2026-08-23)
Kept as a record of what the corpus surfaced, with what actually happened:

| Item | Outcome |
|---|---|
| `.05` with no leading zero (CVS) | ✅ `SCAN-09` |
| a percentage rate matching the price pattern | ✅ `SCAN-10` |
| a receipt with no TOTAL line (18 Starbucks/HMSHost) | ✅ `SCAN-14` — total now correct |
| `CREDIT CARD AUTH` hitting the `credit` discount keyword | ✅ `SCAN-12` — 22 now produces 0 items, correctly |
| tax read as `-8.7` on 21 Starbucks | ✅ resolved by `SCAN-10`/`SCAN-16`; tax now correct |
| **22 ZOOB — printed 36.91 beats the handwritten 40.00** | ❌ **still open**, the only remaining scanner failure |

**A "still open" list that is not re-checked becomes a lie.** Five of these were fixed and the
section still claimed otherwise; anyone reading it would have re-investigated solved problems.

### The confidence score is no longer inverted, but still carries no signal
It was **−0.26** (higher confidence when *wrong*). After `SCAN-07`…`SCAN-17` it is **+0.02** on the
simulator and **+0.19** on device. No longer actively misleading — but a gap that small is noise,
not information. It still measures **OCR legibility**, not whether the parse worked, and no
reweighting changes that. Deriving it from parse outcomes (does the arithmetic close, did every row
yield both a name and a price) or removing the number remain the two honest options.

### The dominant structural failure
**Item name on one row, price on another** — Michaels, Bhavani (14/14 items), Burlington, every
weighted line on Patel Brothers, and `GO by Citizens` where a long name simply wrapped. The parser
names the item after the price row's left text (`"1 @ 3.99"`) and discards the real name. That is
most of the 67% name-recall shortfall, and it is a missing capability rather than a bug.

### Key Pattern — a benchmark that drops what it cannot process reports a lie
The first version `print`ed scan failures and omitted them from the table, so the three refusals
vanished and the headline read 21% over 14 receipts instead of 18% over 17. A refused receipt is a
**failure of the pipeline** and must occupy a row. Same shape as the gate below.

### Key Pattern — a benchmark is a gate on claims, not on builds
The suite asserts **nothing** about accuracy: no threshold has been earned. It is excluded from
`run-coverage.sh unit` via `-skip-testing`, and gated on the corpus being present rather than on
an environment variable — env vars do not reliably reach a test process through `xcodebuild`, and
the first attempt failed **closed and green**, reporting a pass in 0.024s having measured nothing.

**Verification:** benchmark run 2026-08-20, reports under `xBillTests/ReceiptCorpus/reports/`.
Unit suite unaffected. **What this does not say:** nothing about Tier 1 (Apple Intelligence),
which no simulator can exercise.

## Recent Fix Log — 2026-08-19 (later) — SCAN-06: the column split was a guess about layout

### A constant standing in for a measurement
`parseWithHeuristics` split every row into name and price at a hardcoded `midX < 0.55`. Nothing on
a receipt corresponds to that number, and it fails in **both** directions:

- **Prices left of 0.55** fall into the *name* column. `leftText` is then non-empty, so `stripPrice`
  never runs, and the item is named `"Coffee 3.50"` — the amount rendered twice on the review
  screen, once as text.
- **A name reaching past 0.55** falls into the *price* column, truncating the item to whatever sat
  left of the line: `"Chicken Sandwich"` becomes `"Chicken"`.

Both turn a correct OCR pass into a wrong review screen.

### What replaced it
`detectPriceColumnBoundary(rows:)` measures the boundary from the receipt's own geometry. The
signal it exploits: **prices are right-aligned**, so the rightmost element of a two-column row is
the price, and the left edge of where those elements sit is the column boundary.

Three guards, each with a test proving it fires:

| Guard | Why it exists |
|---|---|
| ≥ 2 samples | One two-column row is a coincidence, not a column. |
| spread ≤ `0.30` | Right-alignment makes prices cluster tightly; a wide spread means something other than a price column was measured, so the result is discarded. |
| floor `0.35` | A boundary in the middle would classify most of every row as price — not a layout that exists. |

Metadata rows are excluded before measuring: a card or reference number parses as a decimal and
would otherwise drag the boundary left across the whole receipt. A `0.08` margin absorbs the centre
shift between a narrow and a wide amount — right-alignment fixes an amount's *right* edge, so
`1234.56` sits measurably left of `9.99`.

### Key Pattern — land the measurement before the call site to get a real RED
The detector was committed with `parseWithHeuristics` still on `0.55`, and the suite run in that
state. **Exactly the 2 behavioural tests failed while all 5 measurement tests passed** — which
proves in one step that the new tests catch the old behaviour and that the measurement itself was
already correct. Cheaper and stronger than mutating the code afterwards to check.

**Verification:** unit **369/369**, 0 failed / 0 skipped
(`TestResults/Coverage/2026.08.19_19-45-20-unit.xcresult`; suite confirmed present by name, not
inferred from exit status). Debug build clean, installed and launched on the simulator.
**Not verified — and not verifiable here:** whether this improves accuracy on real receipts. There
is no corpus, so the effect size is unknown; what is established is that two specific layouts which
previously parsed wrongly now parse correctly. Collecting 15–20 photographed receipts with known
totals is the outstanding work that would turn this into a measurement.

## Recent Fix Log — 2026-08-19 — SCAN-05: receipt item assignment was per-item only

### The friction
Assignment had an "All" chip and one chip per member **on every row**, and nothing that operated on
the receipt. The most common real outcome — everyone shares everything — therefore cost one tap per
line. On a 20-item receipt that is 20 taps, and it is where people abandon the review screen and
split the total evenly instead, discarding the itemisation the scan just produced.

Added an **Assign everything** section above the items: `Everyone`, `Just me`, `Clear`. Per-item
chips are unchanged, so precise assignment still works — the bulk actions are a starting point, not
a replacement.

Three deliberate details:
- **Bulk actions replace rather than merge**, so Everyone → Just me does not leave the others attached.
- **`allItemsAssigned` is exact, not "contains"** — a partly-matching receipt must not light the chip.
- **"Just me" is hidden, not disabled,** when the user is unknown or not a member of this group. An
  inert control invites taps that do nothing, and silently assigning a non-member would build a
  split that cannot be saved.

`currentUserID` had to be plumbed `AddExpenseView` → `ReceiptScanView` → `ReceiptViewModel`; the
receipt flow never knew who the user was.

### SCAN-05b — the device found what the tests could not
On device, "Everyone" worked and **"Just me" never appeared**. Two hypotheses were formed and both
killed by evidence: the `is_active` filter on `activeMembers` (all three seeded members are active)
and the placement of `.onAppear` (it is on the outermost view). Instrumentation settled it —
`currentUserID=nil` while `memberCount=3`, i.e. members arrived and the user did not.

`members` was set in **two** places (`.onAppear` *and* `startManually`); `currentUserID` in only
one. `startManually` now carries it too, so state the review screen depends on no longer relies on
a lifecycle callback having fired first.

**Honest limit:** the `.onAppear` instrumentation only existed in the build that also carried the
fix, and that build shows `.onAppear` firing correctly with the right UUID. So *why* it was nil
beforehand is **not established** — two changes landed together. What is established: the value is
now set in two independent places, neither `startManually` nor `scan(pages:)` clears it, and the
camera path uses the same `.onAppear` that is now proven to fire.

### Key Pattern — state a screen depends on must not hinge on a lifecycle callback
If a view needs a value, pass it or set it at the point of use. `.onAppear` ordering is not a
contract, and a second writer of neighbouring state (`startManually` setting `members` but not
`currentUserID`) is how the two drift apart silently.

**Verification:** unit **362/362** (9 new: 7 for the bulk actions, 2 regressions for the device
defect), UI regression **18/18**. **Fully device-verified** by the user on the shipping build:
Just me replaces rather than merges, Clear resets, the active state clears when a single row is
changed, per-item chips and per-person totals still follow, and the bulk chips respond on their
edges. Placement above Merchant reviewed and **accepted** — the alternatives considered were
folding it into the section header or showing it only while items remain unassigned.

## Recent Fix Log — 2026-08-18 (later still) — SCAN-04: reconciliation refused the cases it existed for

### The threshold was inverted
`reconcile` only attempted a repair when `|delta| ≤ $2.00`, on the stated reasoning that a larger
gap meant a structural parse failure rather than a digit misread. That is the opposite of how OCR
errors behave: **a single misread digit produces a large delta.** `18.99` read as `78.99` is a $60
gap; even `4.99`→`1.99` is $3, already outside the cap. Small deltas come from rounding or a missed
penny item, which alternate prices rarely fix. The cap excluded exactly the cases the function
exists to repair, and admitted mostly the ones it cannot help.

It was not protecting cost either — this is a **single-substitution** search, `O(items × alternates)`.

### What replaced it, and a bound that was wrong twice over
A first attempt used `|delta| ≤ total`. A test caught it failing the headline case: a `78.99`
misread against a true total of `21.99` is a $60 gap that **legitimately exceeds the bill**.

Worse on reflection: since `delta = total − itemsSum`, such a bound can never exceed
`max(total, itemsSum)` — it would have been **a guard that never fires**, the same class of
defect this codebase has repeatedly been bitten by. It was removed rather than adjusted.

The real protection is **uniqueness**: a substitution is applied only when exactly one closes the
gap. The old code took the **first** match it found, so with two plausible corrections it silently
wrote one of them into the receipt — and a wrong price there flows straight into someone's split.
Ambiguity now leaves the validation warning for the user to resolve. Uniqueness is also what
screens out coincidental closure on a structurally broken parse, which is what the magnitude bound
was reaching for and failing to achieve.

### Key Pattern — prefer a guard that can fire
Two guards were considered and rejected here for the same reason: they could not fail. Before
adding a bound, ask what input makes it trigger; if none plausibly does, it is documentation
wearing a conditional. Mutation testing is the cheap check — removing the uniqueness guard fails
`ambiguousCorrectionIsRefused` **and nothing else**, which is what a load-bearing guard looks like.

**Verification:** unit **353/353** (6 new reconciliation tests), UI regression **18/18**.
Mutation-tested: reverting to first-match fails exactly the ambiguity test.

## Recent Fix Log — 2026-08-18 (later) — receipt scanning: SCAN-01/02/03

Three defects in the pure text→receipt layer, found by reading the pipeline rather than by a
failure report. All are in the **heuristic (Tier 2)** path; Tier 1 (Apple Intelligence) is
unaffected.

### SCAN-01 — a discount was parsed with the **wrong sign**, not dropped
`extractDecimal`'s pattern was `[\$£€₹¥￥₩]?\s*(\d{1,6}[.,]\d{2})` — **no minus**. So a line
reading `-2.00` extracted as `2.00`, passed the `amount > .zero` guard, and was appended as a
**+£2 item**. A £2 voucher therefore moved the item sum **£4** the wrong way and produced an
items-vs-total mismatch warning with no visible cause. On any receipt with a loyalty discount this
happened every time.

Now sign-aware: leading `-`, the trailing form some tills print (`2.00-`), and the **Unicode minus
`−` (U+2212)** that OCR frequently returns instead of ASCII. Discounts are also detected by wording,
because many receipts print them as a positive under a label. They are normalised negative and flow
through as items so they reach the review screen and the arithmetic closes. A discount bypasses
`parseQuantity` — "2x" never appears on a voucher line, and dividing a negative there could halve it.

### SCAN-02 — the confidence shown to the user was a **constant**
Tier 2 returned `warning == nil ? 0.75 : 0.55`. Every heuristic scan reported one of two numbers
regardless of how the OCR actually went, so a crisp receipt in good light and a blurred one at an
angle were indistinguishable to the user — while `OCRLine.confidence` was captured from Vision for
**every line and read nowhere**. A fabricated score is worse than none: it invites trust it has not
earned.

`aggregateConfidence` now derives it from the real line confidences, using the **mean of the weakest
half** rather than the overall mean — a receipt is only as trustworthy as its hardest-to-read lines,
and averaging across many clean rows hides the few misreads that change the total. A validation
warning discounts the result rather than replacing it.

### SCAN-03 — low-confidence rows were indistinguishable from clean ones
`ReceiptItem.confidence` now carries the weakest line confidence from its row, and the review screen
flags rows below `0.5`. The user checks three lines instead of re-reading fifteen, which is the
difference between a review step people use and one they skip. Defaults to `1`, so Tier 1 results
and hand-added items are never flagged. Excluded from `CodingKeys`, so nothing about encoding
changes.

### Key Pattern — mutation testing caught a test that proved nothing
`warningPenalises` originally asserted only `warned < clean` and `warned > 0`. **Both hold for the
constant `0.55`/`0.75` it was written to replace** — it would have passed against the exact defect
it existed to prevent, the same class as `UIT-01`. It now asserts that two *warned* receipts still
score differently, and it fails against the constant. Assert the property that **distinguishes** the
fix from the bug, not merely a property the fix happens to have.

### Considered and deliberately not done
- **Possible preprocessing double-up.** `VNDocumentCameraViewController` already applies perspective
  correction and enhancement; `preprocessForOCR` then adds grayscale, contrast ×1.4 and sharpen ×0.4.
  Stacking sharpening on enhanced output can create artefacts. This is an **experiment** — run the
  same receipts with and without and compare extracted totals — not a change to make on a hunch.
- **`reconcile` gives up above a $2.00 delta**, yet a single misread digit (`18.99`→`78.99`) is a $60
  delta, i.e. exactly when OCR alternates would help most. The threshold is backwards relative to
  where the errors are.
- **Item→person assignment** is the real bottleneck once parsing is correct, not OCR.

**Verification:** unit **346/346** (10 new), UI regression **18/18**. Mutation-tested with two
mutants — discarding the sign fails 2 tests, restoring the constant fails 4; the tests that pass
under each are correctly unaffected.

## Recent Fix Log — 2026-08-18 — App Intents phase 1, and a missing Info.plist key that broke Siri

### The feature
`xBill/Intents/` — `GroupEntity` + `GroupQuery`, `CheckBalanceIntent`, `XBillShortcuts`.

`CheckBalanceIntent` runs **headlessly** (`openAppWhenRun = false`): it answers from the balance
snapshot `CacheService` already writes to the App Group for the widget, so it needs no network, no
Supabase session and no app launch. That shaped the whole design — an intent may run out of
process, and xBill's session lives in a Keychain item with **no shared access group**, so an intent
cannot authenticate. **Reads come from the cache; anything that writes must open the app.**

`GroupEntity` resolves a spoken group name to a real group and exists for the intents that follow.
Its query filters archived groups: "add to Tokyo Trip" about a trip archived last year means the
active one, and offering the archived one files an expense where nobody will look for it.

### CRASH-adjacent find — `CFBundleDevelopmentRegion` was missing from every build ever shipped
Siri answered *"xBill hasn't added support for that"* while **Shortcuts and Spotlight both worked**.

The build log's ordering is what located it: SSU YAML *generated* ✓, *copied* ✓, then
`Archiving all locales.` → `error: Could not archive SSU artifacts`. Generation succeeded;
**archiving** failed. `Metadata.appintents/root.ssu.yaml` was written with `training: []`.

Cause: `xBill/Info.plist` had no `CFBundleDevelopmentRegion`, and the app has no `.lproj` bundles,
so the archiver had **no locale to archive for**. Xcode's *generated* Info.plist supplies that key
automatically; this one is hand-written (it must be, for the `$(SUPABASE_URL)` substitution) and so
never declared it. Fixed with a literal `en` — **not** `$(DEVELOPMENT_LANGUAGE)`, which xcodegen
does not define and which would have resolved to an empty string, i.e. worse than absent.

Why the failure was so misleading: intent metadata in `extract.actionsdata` was **perfect**, so the
two surfaces that read it worked. Only Siri reads the speech corpus. Two of three surfaces working
made it look like a phrasing problem, and the error message named "SSU artifacts" rather than
localisation.

**This key was absent from v1.0 and from the v1.1 currently in review.** It affects nothing else
today, but it would have blocked any future Siri work with an error naming the wrong subsystem.

### Key Pattern — an out-of-process surface is not verified by a green suite
Third instance this session, after `WIDGET-01` (framework embedding) and `WIDGET-02` (asset
resolution). `BalanceSummaryTests` covers the spoken **wording rules** — deliberately not
`AppIntent.perform()`, which is reachable only through Siri/Shortcuts and returns an opaque
`IntentResult`, so asserting on it would assert on Apple's framework rather than our behaviour.
Registration, phrase matching and out-of-process execution are **invisible to unit tests**, and
every real problem here lived in that gap. Device verification is mandatory, on all three surfaces.

Also learned: an **upgrade install does not reliably refresh Siri's shortcut vocabulary**; the
working state was reached only after going past a plain reinstall. A restart *before* the corpus
existed could not have helped — sequencing matters when the artifact is what is missing.

**Verification:** unit **336/336** (7 new, mutation-tested: 6 of 7 fail against a collapsed
`spokenSummary`, and the survivor correctly does not), UI regression **18/18**. Debug and Release
both build; `root.ssu.yaml` confirmed to carry all four utterances and the `xBill` synonym.
**Device-verified by the user on all three surfaces — Shortcuts, Spotlight and Siri.**

## Recent Fix Log — 2026-08-22 — INV-01/02: link and QR group invites never worked

### Reported live: "Invalid Invite. This invite link is invalid or has expired."
Two independent defects, and the first means **an invite has never been usable by the person it
was sent to.**

### INV-01 — the invitee cannot read the invite
`JoinGroupView.loadInvite()` previewed an invite with two direct table selects:
`group_invites` (RLS: creator **or existing member**, 027 CRIT-06) then `groups` (RLS: member or
creator, 007). **An invitee is neither, by definition** — that is what an invite is for. Both
return zero rows, `.single()` raises PGRST116, and the screen renders "Invalid Invite" before the
Join button exists. `join_group_via_invite` is SECURITY DEFINER and would have worked; the preview
fails first, so it is never reached.

Why it survived: whoever tested it was already the creator or a member, for whom both selects
succeed. **The one account that cannot test this flow is the only account that uses it.**

- New `get_invite_preview(p_token)` SECURITY DEFINER returns just the group's public face (name,
  emoji, currency, member count, expiry). Possession of the token is the capability; no RLS policy
  moves. Identical error for "no such token" and "expired", so it is not a token-existence oracle.
- New `InvitePreview` model — deliberately **not** `BillGroup`, which would imply access the
  caller does not have.
- **`GroupService.fetchInvite` deleted.** It could not succeed for its only real caller, and
  leaving it invites the same bug back.
- `JoinGroupView` treats a failed preview as **"cannot show the name"**, not "invalid invite": it
  renders a generic card and keeps the Join action live, letting the server adjudicate. That alone
  unblocks invites **without any database change**, which matters because the migration needs
  approval and an App Store release takes days regardless.

### INV-02 — a single-use token behind a QR code
027 (M-20) added `DELETE FROM group_invites` after a successful join. A QR code is shown to a table
of people or posted into a chat: the **first** scanner consumed it and everyone after saw
"expired". `expires_at` (7 days) is the intended lifetime and is now the only one.

### INV-03 — every invite email ever sent contained no way to join
`invite-member` builds a join link **only when `joinToken` is present**. `GroupService.inviteMembers`
sent `groupName`, `groupEmoji`, `inviterName` and `emails` — and **never a token**. So every invite
email in the product's history took the function's fallback branch: a "Download xBill" link and
nothing to join with. Its copy then said *"sign in with this email address to join the group"*,
which **nothing in xBill does** — there is no email-based auto-join anywhere in the system.

This is separate from INV-01. Fixing the join screen does not help an email that carries no token.

`inviteMembers` now takes `groupID` and `createdBy`, mints an invite, and sends `joinToken`. **One
token serves the whole batch** — reusable tokens (INV-02) mean inviting five people shares one link
instead of minting five.

### INV-04 — the emailed link was a custom URL scheme
Even with a token, the email linked to `xbill://join/<token>`. A custom scheme has **no handler on
a device without xBill** — which is exactly who receives an emailed invite — and many mail clients
will not linkify it at all. There is **no `associated-domains` entitlement and no AASA file**, so
universal links are not available either.

The email now links to `https://xbill.vijaygoyal.org/invite?token=…`, an ordinary https URL that
always opens. `web/invite/index.html` reads the token, hands off to `xbill://join/<token>` for
anyone who has the app, and offers the App Store plus the visible invite code for anyone who does
not.

**Proper universal links remain unbuilt** and are the only way to make a fresh install land
straight in the group: AASA file at `web/.well-known/`, the `associated-domains` entitlement, and a
provisioning refresh. Worth doing, not done here.

### Device confirmation of INV-01, on the shipped build
The owner opened the emailed link on a phone: the web page rendered, its button opened xBill, and
the app immediately raised **"Cannot coerce the result to a single JSON object."**

That is **PGRST116** — `.single()` against a zero-row result — and it is INV-01 reproducing
exactly. The phone runs **v1.1 from the App Store**, which still calls the removed `fetchInvite`:
direct select on `group_invites`, RLS returns nothing, `.single()` raises, and
`JoinGroupView.errorAlert` shows the raw message as the alert title.

Positive signal in the same report: **every hop before the app now works** — Resend delivers, the
Cloudflare page renders and hands off, the custom scheme launches xBill, and `xbill://join/<token>`
is parsed. Only the final client call is old code.

The fixed path contains **no `.single()`**: `fetchInvitePreview` and `joinGroupViaInvite` both go
through `.rpc(...).execute().value`.

### Key Pattern — a silent fallback needs a test on the real wire format
`JoinGroupView` degrades to a generic card when the preview fails, which is right for a network
error and is **also what a decoding failure looks like**. So `InvitePreview` drifting from the RPC's
column names, or choking on `expires_at`'s six-digit fractional seconds, would not surface as a bug
— invites would keep working and quietly stop naming the group. `InvitePreviewTests` pins the
payload captured verbatim from production and decodes it with `SupabaseManager.postgrestDecoder`,
the decoder PostgREST actually uses — not a hand-rolled one, which would prove nothing about the
app.

### Deployment state (2026-08-22)
| Piece | State |
|---|---|
| Migration `042` — preview RPC + multi-use tokens | ✅ **deployed**, verified against production |
| `invite-member` edge function — token-bearing https link | ✅ **deployed**, ACTIVE v7 `16:59:29Z` |
| `web/invite.html` + `web/invite/index.html` — reads `?token=`, hands off to the app | ✅ **deployed** 2026-08-22 via `wrangler pages deploy web --project-name=xbill --branch=main`. All four endpoints 200; `/invite` and `/invite/` now identical |
| App changes (INV-01 join screen, INV-03 token) | ⏳ **ships in 1.2** |

Deploying the function ahead of the web page is safe: emails currently carry **no** join link at
all, so a link to a page that ignores its token is not a regression — and no client can join by any
route until 1.2 ships regardless.

### Key Pattern — a capability check cannot be an RLS policy on the thing being granted
An invite exists to give access to someone who does not have it. Any policy of the form "you may
read this if you already belong" is therefore unsatisfiable for the only caller that matters. Route
these through a SECURITY DEFINER function keyed on the token, and never widen the table policy.

### Key Pattern — never render a local read failure as a verdict about the server's data
"Invalid Invite" was shown because *we* could not read the row. The app is not entitled to that
conclusion; only the join RPC can reach it. A failed preview means the name is unknown, nothing
more.

**Verification:** unit **407/407**, 0 failed, 0 skipped. Debug build clean.

**Migration 042 DEPLOYED 2026-08-22** with explicit approval; multi-use tokens approved by the
owner. `supabase migration list --linked` reads `042 | 042 | 042`. Verified against production,
read-only: `get_invite_preview` is `SECURITY DEFINER`, executable by `authenticated`, and returns
real rows for live tokens; a nonexistent token **raises** `Invalid or expired invite token` rather
than returning empty, so it is not a token-existence oracle; `join_group_via_invite` no longer
contains the `DELETE`; `member_count` matches the active-member count.

### ⚠️ The server fix does NOT reach users on the shipped app
v1.1 calls the deleted `fetchInvite` — a direct select still blocked by RLS — and then
`fetchGroup`, blocked by policy 007. **Every install in the wild still shows "Invalid Invite"
until 1.2 ships.** The server side cannot rescue it: making the old path work would require
widening the `groups` SELECT policy to non-members, which is a real security regression and must
not be done. There is also **no in-app workaround** — email invites land in the same
`JoinGroupView`, so they fail identically.

### Corroboration found while verifying
Four live invite tokens exist, all for one group, whose active membership is **1** — the creator.
Nobody has ever successfully joined by link or QR. Worth noting separately: `GroupInviteView`
mints a **new** invite on every appear, which is why there are four; now that tokens live until
expiry it should reuse an unexpired one instead. Minor, not fixed here.

## Recent Fix Log — 2026-08-22 (later) — INV-05: universal links

Closes the last gap in the invite flow. Tapping an invite link previously landed on the web page,
which offered a button that fired `xbill://join/<token>`; the link now opens the app **directly**,
and the page remains only as the fallback for someone without xBill installed.

### Four parts, all verified
| Part | State |
|---|---|
| `web/.well-known/apple-app-site-association` | ✅ deployed. Serves `content-type: application/json` — Cloudflare Pages cannot infer a type for an extensionless file, so `web/_headers` sets it. Apple **silently ignores** an AASA with the wrong type, which presents as universal links just not working, with no error anywhere. |
| Apple's CDN | ✅ `app-site-association.cdn-apple.com/a/v1/xbill.vijaygoyal.org` returns **200** with our JSON. This, not our own server, is what devices consult. |
| `associated-domains` entitlement | ✅ present in the **signed** binary (`applinks:xbill.vijaygoyal.org`) |
| App ID capability | ✅ registered. The first signed build failed — *"Provisioning profile … doesn't include the Associated Domains capability"* — and `xcodebuild -allowProvisioningUpdates` registered it and regenerated the profile. |

### `DeepLinkParser` — one parser for both routes
Universal links arrive as an `NSUserActivityTypeBrowsingWeb` activity, **not** through `onOpenURL`,
so they need a second handler. Both now call one pure `DeepLinkParser.parse(_:)`.

That is deliberate. `INV-01`…`INV-04` were four defects that each existed because two things meant
to agree had drifted — a join screen reading a table its user could not see, an email builder whose
token the caller never sent. Two URL handlers is the same trap, so there is one function and a test
asserting the two forms produce an identical result.

The parser checks the **host** rather than trusting delivery: a universal link is only delivered
for a declared domain, but `openURL` can hand the app anything.

### Pre-existing bug found by writing the test
`xbill://join/` produced `joinGroup(token: "/")`, because `lastPathComponent` returns `"/"` — not
`""` — for a trailing-slash URL, and the original handler only checked `isEmpty`. That token
reached the server, was rejected, and showed the user an error for a link that was simply empty.
Both routes now share one `sanitisedToken`.

### What still needs a device
The AASA, the CDN, the entitlement and the parser are all verified. **Nobody has yet tapped a real
link on a phone running a build with the entitlement** — that needs 1.3 on a device. Until then the
existing web-page button path continues to work, so nothing regresses.

**Verification:** unit **419/419** (9 new), 0 failed, 0 skipped. Debug and signed Release builds
clean.

## Recent Fix Log — 2026-08-23 — SCAN-15: a printed tax of zero was discarded

The parse loop guarded `rawAmount != .zero` **before** classifying the row, so a line reading
`TAX  0.00` was dropped as if it carried no amount at all. Three corpus receipts print exactly that
(Kroger ×2, Costco) and all three reported tax as `nil`.

**Nil and zero are different claims.** Nil means "this receipt did not tell us"; zero means "this
receipt told us there is none". The second is information, and it is the difference between a total
that reconciles and one that raises an unexplained mismatch. The guard now sits on the **item**
branch, where a zero-priced line genuinely is noise — a blank row, or a header mistaken for one.

### The other "leftover" was my mischaracterisation
I had recorded *"reconcile not firing"* on receipts 12 (Patel) and 19 (CVS). Reading what they
actually parse:

```
19  parsed  : CHARGE=13.55                    ← one item, and it is a phantom
    expected: 6 items
12  parsed  : SPINACH=1.99 | Sidata Gold 2008=21.99 | Drunsticks=2.45 | …
```

`reconcile` substitutes a **single alternate price** to close a **small** gap. With most items
missing the gap is not a misread digit, it is absent data — so there is nothing to fix in
`reconcile`. The real cause is residual row-merging plus genuinely degraded OCR on the two
worst-quality receipts in the corpus. That is a tuning experiment, not a defect, and it should not
be filed as one.

**Verification:** unit **423/423**, 0 failed (4 new). Corpus effect measured separately.

## Recent Fix Log — 2026-08-23 (later) — SCAN-16, and a broken benchmark that hid two answers

### SCAN-16 — a second tax line overwrote the first
`tax` was **assigned** on each matching row, so the last tax line won. ALDI prints two:

```
C:Taxable @7.000%     0.28
A:Taxable @0.00%      0.00
```

The zero used to be discarded by the non-zero guard that `SCAN-15` removed, which had been masking
the overwrite. With the guard gone ALDI's tax became `0` — **a receipt that had been right for the
wrong reason started being wrong.** Multiple tax lines are different rates on different subtotals,
so tax now **accumulates**. Tip is deliberately left assigning: there is corpus evidence for
multiple tax bands and none for multiple tips.

### The benchmark had been unrunnable on the simulator for a day
The corpus copy phase added for the Tier 1 device run writes into
`xBill.app/PlugIns/xBillTests.xctest/` **after the app is signed**, invalidating the signature. The
simulator then refuses to launch the app at all (`RequestDenied by SBMainWorkspace`). Device runs
were unaffected, so it went unnoticed — and it silently made every simulator benchmark since
2026-08-22 10:24 impossible. The phase is now **device-only**: a simulator test reads the corpus
from the source tree via `#filePath` and never needed the copy.

**That broken benchmark had hidden two conclusions**, both now settled:

- **`SCAN-14` did land.** It looked unverified because the only runs after it were broken. Totals
  on 07 ALDI, 13 Chuko and 18 Starbucks are now correct; 06 Trinetra is still `nil`.
- The device-vs-simulator delta flagged after the Tier 1 run was **the signing bug**, not a
  difference between device and simulator Vision.

### Corpus, simulator (Tier 2 only), across SCAN-14/15/16
| | before | after |
|---|---|---|
| TOTAL correct | 15/22 (68%) | **18/22 (82%)** |
| TAX correct | 17/22 (77%) | **20/22 (91%)** |
| Item count exact | 16/22 | 16/22 (73%) |
| Price recall | 90% | 90% |
| Name recall | 72% | 72% |

### Key Pattern — a fix can make a latent bug reachable
`SCAN-15` was correct and its own tests passed, and it still broke ALDI: removing a guard exposed
an overwrite that guard had been accidentally suppressing. **After removing a filter, re-measure
the things that were passing** — not only the ones that were failing. The corpus caught this; no
unit test would have, because each fix's tests only covered its own case.

**Verification:** unit **426/426**, 0 failed (3 new). Corpus above.

## Recent Fix Log — 2026-08-23 (later still) — SCAN-17: our own preprocessing was destroying digits

### The experiment that had been outstanding since day one
`preprocessForOCR` applied grayscale → contrast ×1.4 → sharpen ×0.4 before OCR. It was flagged on
day one as a possible **double-up**: `VNDocumentCameraViewController` already applies perspective
correction and enhancement, and stacking sharpening on enhanced output can create artefacts. It was
explicitly recorded as "an experiment — run the same receipts with and without and compare — not a
change to make on a hunch." The benchmark finally made that runnable.

**The enhancement was making OCR worse.** Same corpus, same code, identical in every other respect:

| | with enhancement | without |
|---|---|---|
| **TOTAL correct** | 18/22 (82%) | **21/22 (95%)** |
| **Name recall** | 72% | **80%** |
| TAX correct | 20/22 | 20/22 |
| Item count exact | 16/22 | 16/22 |
| Price recall | 90% | 90% |

Three receipts flipped from wrong to right, and they are **exactly the three previously written off
as unfixable**:

```
06 Trinetra   ✗ nil       →  ✓
12 Patel      ✗ 136.15    →  ✓      (truth 136.13 — a two-cent digit misread)
19 CVS        ✗ 13.65     →  ✓      (truth 13.55)
```

Those had been recorded as "genuinely degraded OCR on the two worst-quality receipts… a tuning
experiment, not a defect", and the advice given was **not to chase them**. The degradation was
ours. The receipts were fine.

Only 22 ZOOB still fails, and for an unrelated reason: a handwritten total losing to the printed one.

The resize to 1200px is **kept** — it bounds memory and is not part of the enhancement. Removing
the three filters also drops three GPU passes per page.

### Key Pattern — plausible image "enhancement" needs measuring, not reasoning
The comment justifying the filters read *"darkens ink, lightens paper"* and *"reinforces text edges
for higher-confidence character recognition"*. Both are plausible, both were wrong, and neither was
ever tested against a receipt. Vision's recogniser is trained on photographs, not on images
pre-sharpened by us — an operation that looks like help to a human eye is not necessarily help to
it.

More uncomfortable: this survived **seventeen scanner fixes**. Every one of `SCAN-01`…`SCAN-16`
was parsing text that our own filter had already damaged, and I twice advised the owner that
Patel and CVS were not worth chasing.

**Verification:** unit **426/426**, 0 failed. Corpus above, reproduced twice — once with the
experiment patch and once with the clean removal, identical results.

## Recent Fix Log — 2026-08-23 (later) — SPLIT-02: editing an amount moved no balances

### The defect
`saveEdit` wrote a new `amount` to `expenses` and left `splits` untouched. Balances derive from
splits, so correcting a £100 dinner to £120 displayed £120 while every balance still reflected
£100. The edit reported success and changed nothing. **Live in 1.2.**

### Proportional rescaling, because the strategy is not persisted
`splits` stores amounts only — nothing records whether the user chose equal, exact, percentage or
shares. A changed amount therefore cannot be re-split "the way they originally chose", and
re-splitting equally would silently flatten a deliberate 70/30 into 50/50.

`SplitCalculator.rescale(splits:from:to:payerID:)` scales by the ratio, which preserves whatever
the intent was without needing to know it. The rounding residue goes to the **payer** — they
fronted the money — so the parts sum exactly to the new total rather than leaking a penny.

It returns `nil` where there is no ratio to preserve (empty set, or a zero original). Since
`add_expense_with_splits` requires at least one split, an empty array can only mean *not loaded
yet*, and the message says so instead of claiming the expense has no shares.

### Migration 043 — one transaction, not three writes
`update_expense_with_splits` updates the expense, deletes its splits and inserts the new set
atomically, mirroring `add_expense_with_splits`. Doing it client-side would leave a window where an
expense's splits do not sum to it, and a crash inside that window would persist the mismatch.

**Not `SECURITY DEFINER`** — `splits` already carries group-member-scoped INSERT/DELETE/SELECT
policies and `expenses` an UPDATE policy (022), so RLS is the authorisation exactly as for a direct
write. The function adds atomicity, not privilege. It also **rejects a split set that does not sum
to the amount**, making that mismatch unrepresentable rather than a balance nobody can explain.

`expenses.updated_at` was added but is **not yet read**: it exists so optimistic concurrency can
be introduced without a second migration. Two people editing the same expense currently overwrite
each other silently.

### SPLIT-03 was withdrawn before any code was written
The scope claimed that changing "Paid by" without rewriting splits corrupts two balances. **That
was wrong.** `netBalances` skips the payer's own split, so the split set is payer-independent and
changing the payer inverts the credit correctly by itself — verified by test rather than argument,
because it was about to be built on.

### Key Pattern — money must not travel through a float literal, in tests either
`SplitRescaleTests.singleParticipant` failed against a correct implementation because the test
wrote `to: 73.29`. A `Decimal` from a float literal routes through `Double` and carries its error.
Production is safe (amounts are parsed from strings); the *test* was the unsafe path. Use
`Decimal(string:)` in assertions too.

**Verification:** unit **434/434**, 0 failed (8 new). Debug build clean.
**Migration 043 DEPLOYED 2026-08-23** with approval. `supabase migration list --linked` reads
`043 | 043 | 043`. Pre-flight first: all **46** live expenses already satisfied the invariant the
RPC enforces (0 mismatched), so nothing existing could be rejected by it. After deploy, still 0
mismatched and 0 rows touched.

All three guards verified against production **without writing anything** — each fails before any
UPDATE:

| Guard | Response |
|---|---|
| splits that do not sum | `Splits sum to 40.00 but the expense is 100` |
| an expense the caller cannot edit | `Expense not found, or you do not have permission to edit it` |
| empty split set | `An expense must have at least one split` |
| **anon**, calling with the anon key | `Expense not found, or you do not have permission to edit it` |

### ⚠️ `REVOKE … FROM PUBLIC` does not lock a function down on Supabase
`update_expense_with_splits`, `add_expense_with_splits`, `get_invite_preview` and
`join_group_via_invite` all carry the **identical** ACL: EXECUTE granted to `anon`, `authenticated`
and `service_role`. Supabase sets `ALTER DEFAULT PRIVILEGES` so every new function in `public`
gets an **explicit** grant to `anon` at creation, and revoking from `PUBLIC` does not remove an
explicit grant.

So the `REVOKE ALL … FROM PUBLIC` lines in migrations 042 and 043 read as if they restrict access
and **do not**. Nothing is exposed — these functions are `SECURITY INVOKER`, so RLS refuses an
anonymous caller (verified above), and the two `SECURITY DEFINER` ones fail on a null `auth.uid()`.
But the ceremony is misleading: to actually restrict, revoke from `anon` by name.

## Recent Fix Log — 2026-08-23 (Phase 2) — SPLIT-01: an expense can be re-split

The original question: *create a group, add an expense, a member joins later — can the expense be
split to them?* It could not. It can now.

### One split implementation, not two
The split rules lived inside `AddExpenseViewModel`. Reimplementing them for the edit sheet would
have been the fifth instance this session of two code paths meant to agree and drifting
(`INV-01`…`INV-04`). They were extracted into **`SplitEditor`**, which `AddExpenseViewModel` now
owns and forwards to — its public API is unchanged, so the view and 27 existing test references
were untouched.

The rules are too easy to get subtly wrong to duplicate: percentage validation exists because a
40/30/20 entry once saved silently with the missing 10% dumped on one participant, and the shares
clamp exists because that rule used to live in a button and only held while every caller
remembered it.

### `SplitEditor.forEditing` and the two rules that are not obvious
- **A departed member keeps their split.** An expense may legitimately be split with someone who
  has since left the group; dropping them would rewrite history and move their debt onto everyone
  else. They appear as "No longer in this group" and are preserved.
- **Seeded as `.exact`, never `.equal`.** The strategy is **not persisted** — `splits` stores
  amounts only. Presenting `.equal` would assert something about the user's original intent the
  data cannot support, and would flatten a deliberate 70/30 the moment they opened the sheet.

### Two save paths, deliberately
If the user **touched** the split section their choice is authoritative. If they did not, an amount
change is **rescaled proportionally** (SPLIT-02) rather than re-derived — re-deriving would have to
guess a strategy, and guessing "equal" would silently flatten a split they never opened the section
to change.

### The extraction regressed a test, and that is the point
`exactSplitValidationControlsSave` failed the moment `SplitEditor` was introduced: validation read
the editor's **stored** total, which only refreshes on recompute, so the form reported *"amounts
must add up to 0.00"* while showing a real amount. `validationError(for:)` now takes the total
explicitly — a pure function of (strategy, inputs, total) cannot go stale. **The existing suite
caught a real defect in a refactor whose own new tests all passed.**

**Verification:** unit **441/441**, 0 failed (7 new). Debug build clean, installed on the simulator.
**Not yet device-verified:** adding a late joiner to a real expense and watching both balances move
needs a build in hand — that is the check this whole change exists to satisfy.

## Recent Fix Log — 2026-08-23 (later) — INV-06: scanning a QR from a cold start joined nothing

### Reported
App killed. Native Camera scans the group QR. xBill launches and shows *"Join Smoky Mountains
Trip"* — the real group name. Tap Join. No group appears. Twice.

### What the data said before any theorising
**No `group_members` row was written at all.** Only the two successful joins from earlier that day
and one UI-test artifact. So the join failed, rather than succeeding-but-not-displaying.

### Root cause
`get_invite_preview` is callable **without a session** — verified by calling it with the anon key
and getting the full group back. So the screen naming the group correctly proves **nothing** about
whether the caller can act.

On a cold launch the Supabase SDK restores and refreshes the session **asynchronously**. Tapping
Join inside that window sent `auth.uid() = NULL`, and `join_group_via_invite` inserted it blindly:

```
23502  null value in column "user_id" of relation "group_members"
```

`AppError.from` has no mapping for a PostgREST constraint code, so it reached the user as nothing
at all. **A screen that can render before it can act must not offer the action.**

### Fixed in two layers
- **Client (`JoinGroupView`)** — awaits `auth.session` before joining, which forces the SDK to
  finish restoring or refreshing. On failure: *"Your session has expired. Sign in again, then
  reopen this invite."* **This is where the user-facing message comes from.**
- **Migration 044** — `join_group_via_invite` checks `auth.uid()` first, and `anon`'s EXECUTE is
  revoked (Supabase grants it by default; `REVOKE … FROM PUBLIC` does not remove it).

### ⚠️ The revoke made the RPC's own message unreachable
An expired JWT is treated as **`anon`** by PostgREST, so it now gets `42501 permission denied`
before reaching the function — meaning the `RAISE … 'You need to be signed in'` can only fire for a
non-anon role with no identity, such as `service_role`. **It is close to a guard that cannot fire**,
the pattern this codebase has been bitten by twice. It is kept as a backstop, but the layer that
actually helps a user is the client await. Do not add copy to the RPC believing users will see it.

### The group QR is now a universal link — FIXED
`GroupInvite.inviteURL` built `xbill://join/<token>`, the custom scheme the native Camera handles
worst, on the one surface that is *only* reached by scanning. `INV-05` converted the emailed link
and left this behind. It is now `https://xbill.vijaygoyal.org/invite?token=…`, which works on every
version:

| Recipient | What happens |
|---|---|
| app + `applinks` entitlement (1.3+) | iOS opens xBill directly |
| app, no entitlement (1.0–1.2) | the web page opens and hands off via `xbill://join/<token>` — exactly what those builds already understand |
| no app | the web page offers the App Store and shows the invite code |

Old QR codes already printed or shared keep working: `DeepLinkParser` resolves both forms to the
same intent, and a test asserts they agree.

### The add-friend QR is now a universal link too — FIXED 2026-08-24
`MyQRCodeView` and `AddFriendView` each built their own `xbill://add/<userID>` — a custom scheme,
in a QR code and a share link, with the same consequences as the group QR: the native Camera treats
it inconsistently, and it does nothing at all for someone without the app, who is precisely who you
send an add-friend link to.

All three pieces, because any two of them leave a link that resolves to nothing:

| Piece | State |
|---|---|
| `DeepLinkParser` case for `/add?user=<uuid>` | ✅ both forms resolve identically, asserted by test |
| AASA path `/add` + `/add/*` | ✅ deployed; **Apple's CDN already serves it** |
| `web/add.html` + `web/add/index.html` | ✅ deployed, 200 |
| Both generation sites → `XBillURLs.addFriend(userID:)` | ✅ one builder, not two |

**The generation now lives in one place on purpose.** Two copies is exactly how the *group* QR was
left on the old scheme when the emailed invite was converted in `INV-05`.

⚠️ **The web page was nearly shipped broken.** It was first produced by `sed`-transforming the
invite page, which rewrote `/invite` → `/add` but left `xbill://join/` untouched — it would have
handed a user id to the group-join handler. Caught by reading the generated file rather than
trusting the transform. It is now written out in full, with a comment recording the near-miss.

`xbill://reset` in `AuthService` stays as it is — a Supabase auth redirect configured in the
dashboard.

**Verification:** unit **459/459** (5 new). All six web endpoints 200; origin and Apple's CDN both
list `/invite`, `/invite/*`, `/add`, `/add/*`; the live `/add` page's only executable handoff is
`xbill://add/`.
**Not device-verified:** scanning an add-friend QR needs the next build.

**Verification:** unit **441/441**. Migration 044 verified against production: anon → `42501`,
authenticated with a bogus token → `Invalid or expired invite token` (so the identity check passes
and the token check rejects). `anon_exec: false`, `auth_exec: true`.
**Not verified:** the original cold-launch sequence on a real device. The mechanism is reproduced;
the exact user sequence is not, and the client fix ships in the next build.

## Recent Fix Log — 2026-08-24 — SPLIT-04/05: two defects shipped in 1.3, both mine

Reported by the owner within hours of 1.3 going live. Both were avoidable, and both were missed by
verification that looked thorough.

### SPLIT-04 — re-splitting an expense failed with a raw PostgREST error
> *"Could not find the function public.update_expense_with_splits(p_amount…"*

**Swift's synthesized `Encodable` omits a nil.** An expense with no notes sent **7 keys**, and
PostgREST resolves an RPC by the exact key set it receives — so it searched for a 7-argument
function, found none, and returned `PGRST202`. `update_expense_with_splits` had **0 default
arguments** while `add_expense_with_splits` has **8**, which is why creation never showed this.

**This trap is already documented in this repository** (`HANDOFF_PAYMENT_HANDLES.md`, for the
payment-handle payload). I hit the same one.

- `UpdateExpenseParams` now has a hand-written `encode(to:)` using `encode` — never
  `encodeIfPresent` — so every key is present and explicitly null.
- Migration **045** gives the optional arguments defaults, matching the create RPC. The client fix
  alone would suffice; depending solely on the client to serialise perfectly is the arrangement
  that just failed.

### SPLIT-05 — "By %" has never had an input, anywhere, since 1.0
Selecting *By %* left every percentage at `0`, so `validatePercentages` reported *"Percentages must
add up to 100. Currently: 0.00"* and **Save stayed disabled with no way out**. `AddExpenseView`
contained **zero** occurrences of "percentage" — the create form never had a field either. I then
built an edit sheet with the same four-option picker and only one working input.

New `SplitParticipantRow`, shared by **both** forms, renders the input each strategy needs: a
`TextField` for exact, a **percentage field**, a stepper for shares, read-only for equal. One row
for both forms, because two copies is precisely how the edit sheet came to be missing three of the
four inputs.

### Key Pattern — verifying the contract is not verifying the payload
`update_expense_with_splits` was tested against production with a hand-written body containing
`"p_notes": null`, and it passed. **The app sent something different.** A server-side check cannot
see how the client serialises, and every one of the three verification passes I ran was blind to it.
`UpdateExpensePayloadTests` now asserts the **encoded wire payload** — that the key set is
identical whatever is nil — using the encoder PostgREST actually uses.

### Key Pattern — an option that cannot be completed is worse than an absent option
A picker with four choices, one of which traps the user with a permanently disabled Save, is worse
than a picker with three. When adding a control with modes, check every mode has a way to finish —
not just the one being demonstrated.

**Verification:** unit **454/454**, 0 failed (9 new). Migration 045 deployed; the exact payload that
failed for the user now resolves to the function. Debug build clean.
**Not device-verified:** both fixes ship in the next build.

## Recent Fix Log — 2026-08-24 (later) — INV-07: a removed member could never rejoin

### Reported
Scan the group QR → the sheet names the group correctly → tap Join → land in xBill with no group.
Twice, identically.

### Evidence before theorising
**No `group_members` row was written**, so the join failed rather than succeeding-and-not-showing.
And the group's membership listed `sonthalia2sweta@gmail.com` with **`is_active = false`**.

### Root cause
Migration 036 introduced historical membership: removing someone sets `is_active = false` and
**keeps the row**, so old expenses can still name them. `memberGroupIDs` reads only
`is_active = true`.

`join_group_via_invite` guarded its insert with:

```sql
IF NOT EXISTS (SELECT 1 FROM group_members WHERE group_id = … AND user_id = …)
```

which does **not** consider `is_active`. A removed member's row still exists → the insert is
skipped → the function returns the group id → the client treats that as success → the sheet
dismisses → they are still inactive → no group. Deterministic, silent, identical on every retry.

**A function that reports success while doing nothing is the worst possible failure**: there is no
error to show, nothing to log, and the user's only evidence is an absence.

### It was already solved, and I missed it twice
Migration **036 shipped `add_or_reactivate_group_member` for exactly this case**, documented as
"invite acceptance reactivates existing inactive memberships instead of failing on conflict".
`join_group_via_invite` never used it — and **042 and 044 both rewrote that function and preserved
the bug**. I was editing the identity check and the token lifetime and never questioned the
existence check three lines below.

Migration **046** replaces it with an UPSERT that reactivates, covering all three cases in one
statement that cannot drift: never a member → insert; already a member → no observable change;
**removed member → reactivated**.

### Key Pattern — when rewriting a function, re-derive every guard in it, not just the one you came for
Two rewrites carried this defect through untouched because the surrounding lines looked like
context rather than logic. A guard that predates your change is still yours the moment you
re-emit the function.

### Key Pattern — `EXISTS` on a soft-deleted table is almost always wrong
Once a table keeps rows for history (`is_active`, `removed_at`, `deleted_at`), every `EXISTS`
against it must say which state it means. `NOT EXISTS(…)` silently reads "no row of any state",
which is rarely the question being asked.

**Verification:** deployed 2026-08-24; `migration list` reads `046 | 046 | 046`. The deployed
function upserts (`ON CONFLICT` present, old `IF NOT EXISTS` gone), `authenticated` may execute,
`anon` may not, and **no data changed** — the one inactive membership is still inactive, so the
fix takes effect the next time that person joins rather than by rewriting history.
**Server-side only: this takes effect immediately on 1.3, with no app update.**

### ✅ CONFIRMED FIXED on a real device 2026-08-24
The reporting user rescanned the QR and joined successfully. Verified in the data, not only on
screen: `sonthalia2sweta@gmail.com` on Smoky Mountains Trip is now **`is_active: true`**, having
been `false` before the deploy. The reactivation path worked end to end with **no client change** —
every user on 1.3 is fixed.

## Recent Fix Log — 2026-08-24 (later still) — UI-01: Manage Group scrolled endlessly

`XBillScrollView` used a `LazyVStack`. On Manage Group — three short sections and a 10-icon grid —
the scroll view reported far more height than it had, so swiping ran off into blank space.
`LazyVStack` → `VStack` fixes it.

### Measured, not reasoned
A UI probe (`testManageGroupStopsScrollingAtItsContentHeight`) swipes past the end and asserts some
content is still on screen. It **fails against `LazyVStack`, passes against `VStack`**, nothing else
changed. It stays as a regression test.

The first probe attempt was itself wrong: it tracked one element's Y position, and that element
scrolls out of the accessibility snapshot, so the query failed rather than measuring anything. The
working signal — *is anything on screen after scrolling past the end* — is a direct encoding of the
complaint.

### ⚠️ The cause I first wrote down was wrong
I recorded it as "a `LazyVGrid` inside a `LazyVStack`". **`CreateGroupView` has the same icon grid
in the same container and its probe passes even against `LazyVStack`.** So the grid is not
sufficient, and the precise trigger is **not established**. What is established: removing the
laziness fixes Manage Group and regresses nothing.

### The sweep — and a coverage claim that was false
The first sweep probed **three** screens and the summary said *"the other nine that share the
component were checked and were fine."* **They had not been.** Add Friend, Friends, Groups,
Activity, Profile, My QR and EmailAuth were never run. The owner asked "did you check Add Friend?"
and the answer was no.

`testAllTabScreensStopScrollingAtTheirContentHeight` now covers the whole set in one test, so the
claim and the evidence cannot come apart again.

| Screen | Result |
|---|---|
| Manage Group | ❌ against `LazyVStack`, ✅ now — **the only screen that had the defect** |
| Groups, Home, Friends, **Add Friend**, Recent Activity, Profile | ✅ |
| Create Group (same icon grid, same container) | ✅ never broken, even with the bug present |

The only remaining `LazyVGrid` outside a screen is in a `#Preview`, and is not shipped.

### The probe itself was wrong twice before it was right
1. **Tracked one element's Y across swipes.** That element scrolls out of the accessibility
   snapshot, so the query threw instead of measuring.
2. **Asserted a named top-of-screen anchor was still visible.** A screen with genuinely long
   content — the test account has 33 groups — legitimately scrolls its header away, so this
   reported Groups as broken when it was not. I nearly filed that as a second defect.

The signal that actually works: after swiping past the end, **is anything rendered at all**. Blank
space is the defect; a moved header is not.

### The full UI suite caught a regression of mine from earlier today
Extracting `SplitParticipantRow` renamed four accessibility identifiers (`includeToggle`,
`exactAmountField`, `decreaseShares`, `increaseShares`), and `testSplitModeControlsRegression`
failed. **An accessibility identifier is a contract with the test suite, not an implementation
detail.** Restored, and noted in the file.

### Key Pattern — a sweep means running the probe elsewhere, not assuming the fix generalises
The fix was global, so it was tempting to call the other screens covered. Mutation-testing the
sibling probe is what showed Create Group was never affected — which is what disproved the causal
story I had already committed.

**Verification:** unit **454/454**. Manage Group, Create Group and Home probes all pass; the Manage
Group probe fails against the reverted component. All three previously-failing UI tests pass on a
clean simulator.

## Recent Fix Log — 2026-08-24 — LAUNCH-01 and LOCK-01, both reported from a real device

### LAUNCH-01 — every cold launch flashed the login screen, then signed itself in
`ContentView` chose between `MainTabView` and `AuthView` on `currentUser != nil`. On a cold launch
`currentUser` is **always** nil until the SDK finishes an async session restore, so the signed-out
UI rendered first and then flipped.

**"Not signed in" and "not yet known" are different states**, and only the first should show
`AuthView`. `AuthViewModel.hasResolvedInitialSession` distinguishes them; until it is true the app
shows a silent wordmark on `bgPrimary` — a continuation of `UILaunchScreen`, not a spinner, so the
hand-off from the system launch image is invisible.

The flag is set in a **`defer` inside the event loop**, so every path marks the question answered —
including the early `break`s for "no session" and "unconfirmed email". Setting it only on the
success path strands a signed-out user.

### LOCK-01 — an idle phone woke its own screen to ask for Face ID
`lock()` runs on `.background`, which inserts `AppLockView` into the hierarchy **as the app is being
backgrounded** — and its bare `.task` immediately called `authenticate()`. `LAContext.evaluatePolicy`
presents the system biometric prompt, and **that wakes the screen**: a phone on a desk lit up and
asked for Face ID with nobody touching it.

Now `.task(id: scenePhase)` with `guard scenePhase == .active`. The prompt appears when the user
actually returns, which is the only moment it was ever meant to.

### ⚠️ The first attempt shipped a worse bug than the one it fixed
The `defer` was inserted with a `python` `str.replace` whose pattern had **12 spaces of indentation
where the file has 8**. `replace` does not fail on no match — it silently returns the string
unchanged, and the script printed a success line. The flag was therefore never set, and the app
**hung on the launch placeholder forever**. `OnboardingUITests` went 6/6 → **0/6**, which is how it
was caught.

Two things came out of that:
- **Every scripted edit asserts its pattern matched.** `s.replace` without an `assert` is a no-op
  that reports success — the third silent-transform failure in two days, after a `sed` that left
  `xbill://join/` in the add-friend page and a splice that duplicated 200 lines of tests.
- **The launch wait is bounded.** If `.initialSession` never arrives — a version change, an
  unreadable Keychain, an unforeseen error path — a 3-second timer falls through to `AuthView`.
  The worst case is now the flash this fixes, not a terminal blank screen.

**Verification:** unit **463/463**, `OnboardingUITests` **6/6** (0/6 against the broken first
attempt).

### ✅ Both DEVICE-VERIFIED 2026-08-24 on iPhone 16 Pro
The owner ran both on a Debug build installed over the App Store one:
- **LAUNCH-01** — cold launch shows one continuous screen; the login screen no longer appears.
- **LOCK-01** — a backgrounded app on an idle phone leaves the screen dark, and Face ID still
  prompts correctly on return. The fix changed *when* it prompts, not whether.

Both were only observable on a device: one is a sub-second race on cold launch, the other requires
a real background transition and a sleeping screen.

## Recent Fix Log — 2026-08-24 — UI-02: an EmptyView safe-area inset made every plain screen scroll into blank space

### Reported
Add Friend scrolled into blank space on a device. Freshly opened, nothing typed. Still present
after the `UI-01` `LazyVStack` fix.

### Four hypotheses, three wrong, and what actually settled it
Reading eliminated `Spacer()` in a vertical stack, `GeometryReader`, and infinite frames in every
component the screen composes. Two structural theories — the contradictory `toolbar(.hidden)` +
`toolbarBackground(.visible)` pair, and the negative header padding — **both failed a differential
test**: each is absent from Manage Group, which *was* broken, and present on screens that are fine.
A fourth guess (FAB-sized `bottomPadding` on a screen with no FAB) was real but was **not the
cause**.

What settled it was **instrumenting the device**. A DEBUG probe logging content height against the
viewport:

```
before:  screen=AddFriend contentHeight=882 viewportHeight=874 ratio=1.0x
after:   screen=AddFriend contentHeight=826 viewportHeight=874 ratio=0.9x   ← and it STILL scrolled
```

**Content shorter than the screen cannot scroll.** That single number eliminated the entire content
tree in one step and proved the extra extent came from outside it.

### The cause
`XBillScreenContainer` applied `.safeAreaInset(edge: .bottom) { stickyBottom() }` **unconditionally**,
so every screen without a sticky button still received an inset built from an `EmptyView`. That
inset contributes to a scroll view's scrollable extent from **outside its content** — which is why
no amount of reading the screen's own body could explain it. It is not in the body.

Now applied only when the sticky view is not `EmptyView`. `CreateGroupView` and `ProfileView` are
the two screens that pass a real one and keep the inset.

### Also fixed on the way (real, but not the cause)
`AddFriendView` and `GroupListView` inherited the container's default `bottomPadding` of
`floatingActionBottomPadding` (88pt), reserved to clear a floating action button **neither screen
has**. Every sibling already overrode it.

### Key Pattern — instrument the device before the third hypothesis, not after
Three guesses were spent before measuring, on a defect the owner could reproduce on demand and I
could not reproduce at all. **When someone can reproduce a bug reliably and you cannot, their
device is the fastest instrument available** — the probe took minutes to write and answered the
question no amount of code reading had.

### Key Pattern — a measurement that eliminates a whole layer beats one that confirms a suspicion
The useful number was not "the content is too tall". It was **"the content is shorter than the
screen"**, which made every candidate inside the content irrelevant at once.

**Verification:** unit **463/463**. **Device-confirmed by the owner**: Add Friend now stops at its
content. The DEBUG content-height probe stays in `XBillScrollView` — it is compiled out of Release
and cost nothing to keep.

## Recent Fix Log — 2026-08-24 — SPLIT-06: the percentage input asked the user to do the arithmetic

Percentage splitting worked after `SPLIT-05`, but the owner found the input unintuitive. Three
concrete faults, all from having reused the exact-amount field without asking what percentages
actually need:

| Fault | Fix |
|---|---|
| `TextField(value:format:)` showed a `0` that had to be deleted first, and rewrote partial input — "3" on the way to "30" | A plain `String` field. Empty shows nothing; `percentValue` tolerates a half-typed value and is locale-safe |
| No idea what a percentage was worth until after saving | The money appears beside each row and updates live |
| The running total lived in the user's head; the only feedback was `"Percentages must add up to 100. Currently: 65.00"` — after the fact, phrased as a failure, and the wrong number (what was used, not what is left) | `PercentageProgressHint`: **"25% left to assign"**, → **"All 100% assigned"** in green, and **"5% over — remove some"** when over |

Under-allocation is deliberately **not** coloured as an error — it is unfinished work, and colouring
it red while someone is still typing is what made the old message feel like a rebuke.

`percentageProgress` lives on `SplitEditor` and the hint is one shared view, so the create form and
the edit sheet cannot drift — the same reason `SplitParticipantRow` is shared.

**Verification:** unit **469/469** (6 new, covering count-down, exact completion, over-allocation
being distinguishable from under, and excluding a participant returning their share).
**✅ Device-confirmed by the owner 2026-08-24.**

## Recent Fix Log — 2026-08-25 — INV-08/09: an add-friend link opened the app and added nobody

Reported after 1.4 shipped: tapping a shared add-friend link opens xBill and nothing happens. Same
family as the group-join defects. **No `friends` row was ever written** — only two seed rows from
April and June — so the request never reached the database.

### INV-08 — the link was discarded on cold launch
`MainTabView`'s handler cleared the pending id and returned when `currentUser` was nil:

```swift
guard homeVM.currentUser != nil else {
    appState.pendingAddFriendUserID = nil   // ← discards it
    return
}
```

On a cold launch that is the **normal** state — the deep link is parsed while the session restore
is still in flight, the same window as `LAUNCH-01`. The sibling `pendingQuickAction` handler
already did the right thing (**load the user, then guard**); this one now matches it. The original
comment justified the clear as avoiding "a transparent flash": a cosmetic concern that was silently
throwing away what the user tapped.

### INV-09 — and there was nobody to add
The id was resolved through `fetchProfiles(ids:)`, a direct select on `public.profiles`, whose
SELECT policy is *your own row, **or** someone who shares an active group with you*. **A new friend
shares no group with you** — creating that relationship is the entire point of the link.

Verified against production before and after, same caller:

```
direct select        []
get_add_friend_preview   [{"display_name":"Vijay Goyal", …}]
```

Migration **047** adds `get_add_friend_preview`: SECURITY DEFINER, keyed on the id the link carries,
returning name and avatar and **not email** — the holder needs to recognise a person, not look up
an address (the same reasoning that removed email from `search_profiles` in 021). `anon` is revoked
by name, since Supabase's default grant survives `REVOKE … FROM PUBLIC`.

### Key Pattern — this is the THIRD instance of the same rule
> **A capability check cannot be an RLS policy on the thing being granted.**

`INV-01` (group invite preview read a table restricted to existing members), `INV-07` (join guarded
by an `EXISTS` that ignored `is_active`), and now `INV-09`. Every flow whose purpose is to *create*
a relationship must be routed through a SECURITY DEFINER function keyed on whatever the link
carries — never through a policy that presumes the relationship already exists.

**When touching any invite, share or add flow, check this first.** It has cost three separate
production defects.

**Verification:** unit **469/469**. Migration 047 deployed and verified against production: the
direct select returns `[]` while the RPC returns the profile for the same caller, no email is
exposed, and `anon` gets `42501`.

### ✅ Device-confirmed end to end 2026-08-25
The owner opened a real add-friend link. Confirmed **in the data**, not only on screen: a `friends`
row now exists from `imvijaygoyal@gmail.com` to `sonthalia2sweta@gmail.com`, created 23:08 and
already `accepted` — the request reached the database and was answered. Before the fix the table
held only two seed rows from April and June.

## Release status — v1.4 (6) APPROVED 2026-08-25

**Eight fixes, every one reported by the owner using the app.** Six were device-verified by him
before submission rather than after.

| Fix | Device-verified |
|---|---|
| `SPLIT-04` re-splitting failed with `PGRST202` | — |
| `SPLIT-05` "By %" had no input anywhere since 1.0 | ✅ |
| `SPLIT-06` percentage input made the user do the arithmetic | ✅ |
| `UI-01` Manage Group scrolled endlessly | — |
| `UI-02` an `EmptyView` safe-area inset made plain screens scroll into blank space | ✅ |
| Add-friend QR → universal link | — |
| `LAUNCH-01` login-screen flash on every cold launch | ✅ |
| `LOCK-01` idle phone waking itself for Face ID | ✅ |

| Check | Result |
|---|---|
| Unit | **469 passed**, 0 failed |
| UI regression | **22/22**, including the three new scroll probes |
| `OnboardingUITests` | 5/6 → the failure was `keyboard focus`, then **2/2 in isolation**; 6/6 twice earlier the same day |
| Widget | 7 tests |
| Release build | clean |
| Backend | handles NULL · migrations through **046** · all six web endpoints incl. AASA and `/add` return 200 |
| Archive | `1.4 (6)`, `UIDeviceFamily [1]`, region `en`, encryption `false`, `associated-domains` in the **signed** binary, 3 dSYMs, widget framework + `Assets.car`, Siri `nlu/` compiled, **0 corpus paths**, and **0 `scrollContentHeight` symbols** — the DEBUG probe compiled out as intended |

Simulator erased before the UI run, per `RELEASE_VERIFICATION.md`.

### What this release cost, and what it taught
Three of the eight (`SPLIT-04`, `SPLIT-05`, `UI-01`) were defects **I introduced or worsened in
1.3**. The pattern behind them is written up in
`.claude/skills/verifying-your-own-work/SKILL.md` — thirteen rules, each traceable to a specific
defect that reached a user or a wrong claim committed to this repository.

The single most valuable technique of the release was **instrumenting the owner's device**: a
DEBUG probe logging `contentHeight` against `viewportHeight` settled `UI-02` in one number after
three hypotheses had been proposed and disproved by reading.

### Approved 2026-08-25. Two checks still open
`SPLIT-04` (re-split an expense) and scanning the add-friend QR were never verified on hardware —
they are the last two of the eight without a device confirmation, and both are exercisable on the
build now live.

### Now unblocked by approval
- **`splits.is_settled`** — approved to drop months ago, still present and read by nothing.
  ⚠️ **Superseded 2026-08-29: the column stays permanently, and "read by nothing" was wrong** —
  it was read by the decoder. See the 2026-08-28/29 fix log.
- **`expenses.updated_at`** — added in 043 and still unread, so two people editing one expense
  overwrite each other silently.
- Any further migration or Edge Function work.

## Release status — v1.3 (5) APPROVED 2026-08-24 — replaces the pulled build 4

Build 4 was **pulled from review by the owner** so the QR and cold-launch join fixes could go in
the same release rather than trailing a few days behind. The version stays **1.3**; only the build
increments, so the release notes already written still apply.

**Added over build 4** (two files):
- `xBill/Models/GroupInvite.swift` — the QR encodes an **https universal link**, not `xbill://`
- `xBill/Views/Groups/JoinGroupView.swift` — awaits a valid session before joining (`INV-06`)

| Check | Result |
|---|---|
| Unit | **445 passed**, 0 failed |
| `OnboardingUITests` | **6/6** |
| Widget | **7 tests** |
| UI regression | 17/18 — `testArchiveUnarchiveRegression`, then **2/2 in isolation** after a simulator erase |
| Release build | clean |
| Backend | handles NULL · migrations through **044** · all web endpoints incl. AASA 200 |
| Archive | `1.3 (5)`, `UIDeviceFamily [1]`, region `en`, encryption `false`, `associated-domains` in the **signed** binary, 3 dSYMs, widget framework + `Assets.car`, Siri `nlu/` compiled, **0 corpus paths** |

### Approved 2026-08-24, first pass. Now do the device checks.
Four things in this release have **never been exercised on a device**, and each is the reason a
particular piece of work exists. In priority order:

1. **Scan the group QR with the native Camera from a killed app** — the exact reported sequence
   (`INV-06`). If this still silently fails, the diagnosis was wrong: the mechanism was reproduced,
   the device sequence was not.
2. **Tap an invite link from Messages** — universal links (`INV-05`) have never run on hardware.
3. **Add a late joiner to a real expense**; watch both balances move (`SPLIT-01`).
4. **Edit an expense amount**; confirm the other person's balance moves (`SPLIT-02` would fail).

Needing no build: a **second** person on the **same** invite link — the last unproven piece of
`INV-02`, and the failure mode that once made a QR work for exactly one scanner.

### `testArchiveUnarchiveRegression` — the pattern is now clear
It has failed only ever on runs that follow heavy simulator use, and passed **2/2 immediately after
an erase**, alongside `OnboardingUITests` recovering from an *"Early unexpected exit… never
finished bootstrapping"* in the same run. Cumulative record: many passes, failures only from a
degraded simulator. **Erase the simulator before a release UI run** rather than re-running and
hoping.



Cut specifically because three fixes could not be verified until they were on a device.

| Contents | |
|---|---|
| `INV-05` | universal links — an invite link opens the app directly |
| `SPLIT-01` | an expense can be re-split, including to a member who joined later |
| `SPLIT-02` | editing an amount now moves balances (it moved nothing) |
| `SCAN-15/16/17` | zero tax recorded, tax lines accumulate, and image enhancement removed |
| deep-link fix | `xbill://join/` no longer yields the token `"/"` |

| Check | Result |
|---|---|
| Unit | **441 passed**, 0 failed |
| UI regression | **18/18** — the archive test that flaked before 1.2 passed cleanly |
| `OnboardingUITests` | **6/6** |
| Widget | **7 tests** |
| Release build | clean |
| Payment handles NULL | ✅ `0` |
| Migrations local = remote | ✅ through 043 |
| Web endpoints | `/`, `/invite`, `/privacy`, `/terms`, **AASA** all 200 |
| Archive | `1.3 (4)`, `UIDeviceFamily [1]`, `CFBundleDevelopmentRegion en`, encryption `false`, **`associated-domains` in the signed binary**, 3 dSYMs, widget framework + `Assets.car`, Siri `nlu/` compiled, **0 receipt-corpus paths** |

Verified with `plistlib` throughout — `plutil -extract KEY json FILE` destroyed the 1.2 archive's
`Info.plist` during verification.

### The three checks this release exists to enable
Submitted 2026-08-23. None can be done before the build is installed — so they are the first
things to do the moment it clears review, not afterwards:
1. **Tap an invite link from Messages** — universal links have never been exercised on a device.
2. **Add a late joiner to a real expense** and watch both balances move (`SPLIT-01`).
3. **Edit an expense amount** and confirm the other person's balance moves (`SPLIT-02` would fail).

Plus, needing no build: get a **second** person onto the **same** invite link, which is the last
unproven piece of `INV-02`.

## Release status — v1.2 (3) APPROVED 2026-08-22

Everything in this release at the owner's explicit direction, after I twice recommended splitting
the invite fixes out: the full scanner rewrite (`SCAN-01`…`SCAN-14`), App Intents phase 1, the
About screen, and the invite fixes (`INV-01`…`INV-04`).

| Check | Result |
|---|---|
| Unit | **410 passed**, 0 failed, 0 skipped |
| UI regression | **17/18** — `testArchiveUnarchiveRegression` failed once, then passed 2/2 in isolation (7 passes, 1 failure) |
| `OnboardingUITests` | **6/6** — the suite the v1.1 post-mortem flagged as never run before a release |
| Widget | **7/7** |
| Release build | clean (DEBUG-only code compiles out) |
| Payment handles NULL | ✅ `profiles_with_handles = 0` |
| Migrations local = remote | ✅ through 042 |
| Licence | 4 ExchangeRate-API attribution sites, 0 bundled third-party fonts |
| Archive | `1.2 (3)`, `UIDeviceFamily [1]`, `CFBundleDevelopmentRegion en`, `ITSAppUsesNonExemptEncryption false`, 3 dSYMs, framework embedded, `Assets.car` in the `.appex` with 4 money colours, Siri `nlu/` compiled and non-empty, **zero receipt-corpus paths** |

Submitted 2026-08-22 and **approved 2026-08-22** — first pass, despite carrying the entire scanner rewrite alongside the invite fixes.

### Now unblocked by approval
- **`splits.is_settled` drop** — held during review, safe to do now.
  ⚠️ **Superseded 2026-08-29: it was never safe, and the column now stays permanently.**
- **Universal links** — both halves can proceed (AASA file + entitlement).
- Any further migration or Edge Function work.

### Watch now it is live
- **Invites in real use.** The fix is finally in users' hands. Four defects had made the flow impossible; only one owner-run test has ever exercised it.
- **Receipt scanning under real load** — 77% of totals on device, measured against 22 receipts. Real users will feed it things the corpus does not contain.
- **Crash reports**, particularly around the receipt review screen, which changed most.

### ✅ Invites CONFIRMED END TO END 2026-08-22
The owner tested with a second person on a 1.2 build: an invite link shared by **SMS and by email**
was opened by a non-member, who joined the group successfully. **This is the first time that path
has ever completed in this product's history.**

Confirmed by observation, not inference:
- `INV-01` — a non-member can preview and join (the RLS dead end is gone)
- `INV-03` — invite emails now carry a working token
- `INV-04` — the https link opens from email **and SMS**, and hands off to the app

**Still unconfirmed: `INV-02`, multi-use tokens.** One person joined, so a single-use token would
have behaved identically. Proving it needs a **second** person joining with the **same** link —
worth doing, because reverting to single-use is precisely what made QR codes fail for everyone
after the first scanner.

### Watch after approval
- **Receipt scanning is the likeliest review flag.** 77% of totals on device. The review notes
  should say the scan produces a draft the user confirms.
- **`SCAN-14` shipped without its own commit** — `git add -A` swept it into `f2010d4`. It is in the
  archive (`isTotalLine` present in source), but the history does not say so.

### What running the runbook cost and caught
Three process defects, all recorded in `RELEASE_VERIFICATION.md`: `plutil -extract … json FILE`
**destroyed the first archive's Info.plist** during verification; a Siri check asserting on
`root.ssu.yaml` reports a false failure because a successful archive carries compiled `nlu/`
instead; and "Executed 0 test" is XCTest's counter, which does not see Swift Testing cases — the
widget suite had in fact run 7/7.

### Still true and unshipped
`splits.is_settled` remains unread and undropped. ⚠️ **Superseded 2026-08-29 — it is now
permanently undropped by decision, and it was never "unread": the decoder read it.**
The receipt corpus is git-ignored and local-only,
so no other machine can run the benchmark.

## Release status — v1.1 (2) APPROVED 2026-08-18

v1.0 (1) approved 2026-08-11. **v1.1 (2) approved and Ready for Distribution 2026-08-18** — first
pass, including the name/subtitle/keyword change, which was the part most likely to draw scrutiny.

### Watch these now it is out
- **Search re-indexing.** The metadata change is the point of this release. Give it **48–72h** from
  going live before judging whether `xBill: Split Bills & Expenses` and the keyword set improved
  discoverability. v1.0 was effectively unsearchable.
- **The widget, from a public install.** `WIDGET-01/02` are verified in the archive and on a Debug
  device build, but a store install is the only end-to-end proof.
- **Crash reports for `CRASH-01`.** The trigger was never reproducible on demand, so absence of new
  reports is the only signal available — it is weak evidence, not proof.
- **Ratings.** At 0, both search ranking and conversion are suppressed. v1.1 adds two levers: the
  StoreKit prompt after 3 settlements (Apple-capped at 3/user/year) and the uncapped "Rate xBill"
  row in About.

### Shipped in v1.1 but NOT yet exercised by real users
`ASO-01` review prompt (needs 3 recorded settlements), and the App Intents work landed after
submission — **App Intents ship in 1.2, not 1.1.**

## Release status — v1.1 (2) submitted for review 2026-08-17

v1.0 (1) approved 2026-08-11 and live. **v1.1 (2) submitted 2026-08-17**, containing:

| Defect | Severity | Found by |
|---|---|---|
| `CRASH-01` — index-backed element bindings | crash on device | user's `.ips` |
| `WIDGET-01/02` — widget never worked since 2026-07-15 | feature dead | user testing it |
| `TAP-01` / `TAP-01b` — 19 controls with dead hit regions | usability | user noticing *where* he tapped |
| `LIC-01` — no ExchangeRate-API attribution | licence breach | licence audit |
| `MINOR-01` — silent APNs token-delete failure | privacy | pattern scan |
| `ASO-01` review prompt · Liquid Glass · icons · About screen | — | — |

**The archive was independently verified before submission** — not the build settings, the archive:
`UIDeviceFamily [1]`, no icon alpha, all three dSYMs present with the app's UUID matching the
binary, `ITSAppUsesNonExemptEncryption false`, `Frameworks/xBillWidgetCore.framework` embedded, and
`Assets.car` inside the `.appex`. The last two are `WIDGET-01/02`, which had only ever been proven
in Debug.

Metadata changed in this submission (name, subtitle, keywords) to fix discoverability — v1.0 was
effectively unsearchable: the name carried no keywords, the subtitle was empty, and the keyword
field unused.

### What this release should have taught the process
**Four of six defects were found by the user operating a real device**, with every suite green
throughout. Each was structurally invisible to the tests that existed: XCUITest taps element
centres so it cannot see hit regions; widget tests link the framework directly so they cannot see
bundle layout; nothing validates a vendor's licence terms. Before the next release, add to
`RELEASE_VERIFICATION.md`: **put the widget on a real home screen**, **run a licence check**, and
**run `OnboardingUITests`** — which is in no routine suite mode and was never exercised today.

## Recent Fix Log — 2026-08-17 (later still) — About screen

`xBill/Views/Profile/AboutView.swift` (new), reached from a single **About xBill** row at the
bottom of Profile.

Built for three reasons, only one of which was branding:

1. **Provenance** — "Made by Vijay Goyal", the tagline, and `Version 1.1 (2)`. The **build number**
   is shown alongside the marketing version deliberately: a report citing only "1.1" cannot be
   matched to a submission, and the two diverge across resubmissions. Support mail is pre-filled
   with both.
2. **The Profile footer had become a dumping ground** — Terms, Privacy, the required
   ExchangeRate-API credit and the version were four stacked lines of tertiary text. Now one row.
3. **There was no acknowledgements surface anywhere.** The app ships supabase-swift (MIT), Apple's
   swift-crypto/asn1/http-types (Apache-2.0) and two Point-Free packages (MIT). None compel an
   in-app notice, but this is the conventional home for them — and for the ExchangeRate-API credit,
   which is a **licence condition** rather than a courtesy.

**"Rate xBill" is placed above Contact Support on purpose.** It opens the App Store review composer
(`?action=write-review`). Unlike `ReviewPromptService`'s StoreKit prompt, which Apple caps at three
per user per year and may silently suppress, a link the user taps has no limit — and at 0 ratings,
which suppresses both search ranking and conversion, it is the cheaper of the two levers. New
constants `XBillURLs.appStore` / `.appStoreReview`.

The ExchangeRate-API attribution is **still also shown beside a live conversion** in Add Expense.
Burying a licence obligation one screen deep was the wrong trade, so it appears in both places.

**Verification:** unit **329/329**. Debug build clean; installed on the physical device.
**Gap worth knowing:** `scripts/run-coverage.sh regression-ui` runs only `RegressionUITests`.
`OnboardingUITests` — which asserts `isHittable` on the auth screen's Terms/Privacy links, touched
by the `TAP-01` contentShape work — is **not** part of either routine suite and was not run.

## Recent Fix Log — 2026-08-17 (later) — senior scan follow-ups (TAP-01b, MINOR-01)

A pattern scan over the codebase, aimed at the defect classes this project has actually produced.
Two fixes, and a note on what the method is worth.

### TAP-01b — four more dead tap targets
The eight files deferred from `TAP-01` were classified properly rather than left as "probably fine".
**Four** are genuinely affected:

- `FriendsView` **accept** and **decline** on a friend request — icon-only, so only the glyph
  strokes were live. These are one-shot actions on a request the user can only answer once.
- `FriendsView` friend-actions (`ellipsis.circle`) — same shape.
- `XBillIconPickerGrid` cell — a 36pt glyph inside a 56pt frame, so the border ring was dead.

The other four were checked and are fine — their labels fill their frames.

### MINOR-01 — silent APNs token-deletion failure
`try? await deleteDeviceTokens()` at four call sites, including the path taken when notification
permission is found **revoked**. Every caller is a cleanup path with no user action to offer, which
is why the `try?` looked harmless. It is not: a failed delete leaves the server holding an APNs
token for someone who explicitly denied notifications, and they keep receiving pushes. Replaced
with `AuthService.deleteDeviceTokensReportingFailure()`, which catches and logs — one place to
change, with the reasoning next to the code rather than repeated at four call sites.

### Checked and cleared (recorded so the next scan does not redo it)
Force-unwraps — the one candidate (`balances[currency]!` in `FriendsView`) is safe: local `let`,
key drawn from that dictionary's own `keys`. Supabase writes — every `delete`/`update` is guarded
by `.select("id")` + `AffectedRowID`; the grep was the false positive, not the code. No remaining
`ForEach($…)`. No non-cancellable timers. Money stays in `Decimal` (the `Double` uses are a chart
axis and a slider). `nonisolated(unsafe)` uses are documented and sound. The widget has no other
bundle-boundary assumptions beyond the two colours already fixed.

### Key Pattern — what a scan like this is and is not worth
It pattern-matches against **known** defect classes and finds more of the same. Note what it did
*not* find: `CRASH-01`, `TAP-01`, `WIDGET-01` and `WIDGET-02` all came from a crash report or from
the user operating the app. No grep would have surfaced any of them. Read a clean scan as "no new
instances of known patterns", never as "no bugs".

**Verification:** unit **329/329**, UI regression **18/18**, 0 failures / 0 skips. Debug build clean.

## Recent Fix Log — 2026-08-17 — WIDGET-01/02: the balance widget had never worked

The widget shipped broken in v1.0 and in every build since the 2026-07-15 widget-core split. Two
independent bundle-layout defects, neither reachable by any test in this project.

### WIDGET-01 — the framework was linked but never embedded
`xBillWidget` links `@rpath/xBillWidgetCore.framework/xBillWidgetCore`, and `project.yml` declared
`xBillWidgetCore` as a dependency of **the widget**. That links it without embedding it anywhere,
so `xBill.app` shipped with **no `Frameworks/` directory at all**. dyld could not resolve the
framework and the extension died on launch; iOS renders a blank placeholder for a crashed widget,
which is why this presented as "no data" and then as a black box rather than as a crash.

An extension resolves frameworks through `@executable_path/../../Frameworks` — the **host app's**
Frameworks directory. So the *app* must embed it, even though the app itself never uses it. Fixed
by adding `- target: xBillWidgetCore` / `embed: true` to the **app** target.

### WIDGET-02 — asset catalogs do not cross a bundle boundary
With the extension finally running, it drew "xBill" and "Owed to you" but no icon and no amount.
`Color("MoneyPositive")` resolves against `Bundle.main`, which for an app extension is the
**`.appex`** — and the `.appex` had no `Assets.car`. An unresolvable `Color(_:)` renders as
**clear**, so the two elements that used it were drawn invisible. The widget was holding correct
data and painting it in nothing.

**This was introduced by defect fix `L-43`**, which replaced hardcoded RGB with named colours —
correct in the app, silently broken in an extension. Fixed by giving the widget target its own
`Assets.xcassets` containing copies of `MoneyPositive`/`MoneyNegative`. ⚠️ If the app's values
change, update the widget's copy; there is no shared source across a bundle boundary.

### Key Pattern — widget tests cannot see the bundle
`xBillWidgetTests` passed **7/7 throughout both defects** and still does. It links
`xBillWidgetCore` directly into a test host and injects a `UserDefaults`, so it exercises provider
logic while testing neither framework embedding nor asset resolution — exactly what was broken.
**A widget is only verified by adding it to a real home screen.** Add that to the release runbook.

Diagnosis order matters here: the App Group, entitlements, provisioning profiles, code signatures
and the shared snapshot were all checked first and were all **correct** — the extension was never
running long enough to use any of them. What redirected the investigation was the user reporting a
"black box" rather than the "No data yet" text; that distinguishes a crashed extension from a
rendered empty state. The earlier "No data yet" was the *gallery placeholder*, which WidgetKit
draws without launching the provider.

**Verification:** `Frameworks/xBillWidgetCore.framework` present and signed in the built bundle;
`assetutil` confirms `MoneyPositive` and `MoneyNegative` are compiled into the `.appex`'s
`Assets.car`. Widget tests 7/7, unit 329/329. **Device-confirmed by the user:** the widget renders
the icon, "Owed to you" and `$0.00`, matching the Home tab's settled state.

## Recent Fix Log — 2026-08-16 — LIC-01: shipping exchange rates without the required attribution

### v1.0 shipped in breach of ExchangeRate-API's terms
`ExchangeRateService` calls `open.er-api.com` for every foreign-currency conversion. Its Open
Access terms **permit commercial use** — but only on condition that the app links back with the
words **"Rates By Exchange Rate API"**. The app displayed nothing; the only match anywhere in the
codebase was an error-message string. Live since 1.0.

Found by auditing the project rather than by any tool warning — nothing in a build, a test or App
Store validation flags a missing attribution.

- **`XBillURLs.exchangeRateAttribution`** — the URL lives with the other constants, commented as a
  **licence condition, not decoration**, so it is not deleted later as clutter.
- **Two placements, deliberately.** Beside the live conversion in `AddExpenseView`, *and*
  permanently in the `ProfileView` footer beside Terms and Privacy. The conversion preview only
  renders for a foreign-currency expense, so a user who never converts would otherwise never see
  the credit — attribution conditional on an optional feature is not attribution.
- Wording is verbatim as required; styled discreetly, which the terms explicitly allow.

### Also corrected: a comment asserting something nobody had checked
`ExchangeRateService` claimed *"no API key, 1500 req/month free tier."* There is **no monthly
quota** on the Open Access endpoint — it is IP rate-limited, answering HTTP 429 with a ~20 minute
cooldown. The 1-hour cache sits comfortably inside that. This is the third stale doc-claim found in
two days, after the release-status header and the email-confirmation note.

### Licence audit — everything else is clean
Fonts: system only, nothing bundled. Image assets: **zero** third-party files; every illustration is
drawn in SwiftUI. App icon: original raster art, not an SF Symbol — which matters, because SF
Symbols are licensed for **UI only** and may not be used in an app icon or logo. Dependencies:
supabase-swift (MIT), Apple's swift-crypto/asn1/http-types (Apache 2.0), Point-Free packages (MIT),
Deno std (MIT) — all permissive, none requiring a NOTICE. Venmo/PayPal appear as plain text for
interoperability (nominative use); keep them out of ASO keywords, where third-party trademarks are
a known rejection trigger.

**Add a licence check to the pre-submission runbook.** Nothing automated catches this class.

**Verification:** unit **329/329**, UI regression **18/18**, both 0 failures / 0 skips. Debug build
clean.

## Recent Fix Log — 2026-08-15 — TAP-01: buttons whose hit region was smaller than the button

### Found on a physical device; **no test suite here could have found it**
A user reported the Add Friend button "works on the second or third tap". It was not intermittent —
it was **positional**: tapping the middle worked, tapping the left or right did nothing.

With `.buttonStyle(.plain)`, SwiftUI derives the hit region from the **label's content**, not its
frame. `.frame(maxWidth: .infinity)` widens the painted area; `.background`, `.clipShape` and
`.glassEffect` all paint without contributing any hit region. So on a full-width CTA only the
centred `Text` was live, and on an icon button only the SF Symbol's **rendered strokes** were.

**All of this ships in 1.0 (1).** It is not a regression from the Liquid Glass work — the
`XBillCircularIconButton` case was never touched by it.

15 buttons across 13 files, all fixed with an explicit `.contentShape(...)`:

| Component | What was dead |
|---|---|
| `XBillButtonBase` | left/right of every primary and secondary CTA — 12 call sites |
| `XBillPageHeader` | the **back button**, on every detail and modal screen |
| `XBillFloatingAddButton` | everything except the `+` glyph strokes |
| `XBillCircularIconButton` | Add Friend / Create Group |
| `XBillSegmentedControl` | the padding beside each segment label |
| `XBillProfileCard`, `XBillSettingsRow`, legacy `XBillButton` | QR, Edit, settings rows, Forgot Password, Join Group |
| `GroupListView` rows | the gap between a group's name and its balance |
| `AuthView`, `EmailAuthView` | **Terms of Service / Privacy Policy links** and the sign-in toggle |
| `HomeView`, `AddIOUView`, `ProfileView`, `GroupSettingsView` | add, clear-search, avatar, remove-member |

### Key Pattern — a painted area is not a tappable area
Any `Button`/`NavigationLink` with `.buttonStyle(.plain)` whose label does not fill its frame needs
an explicit `.contentShape(...)`. Sweep for `buttonStyle(.plain)` in files lacking `contentShape`.

**And correct the received wisdom about XCUITest.** It taps an element's *centre*, which is usually
the live region — so it reports green through this entire defect class. But when the dead zone **is**
the centre it does catch it, and reports it as something else entirely: `GroupListView`'s row is
`avatar | title | ……gap…… | balance`, the centre landed in the gap, and the failure surfaced as
`"Group detail should open"` — a navigation timeout, not a hit-testing error. Nine files were
initially set aside as "probably fine"; that one was not, and neither was `ReceiptReviewView` in the
earlier CRASH-01 sweep. **"Probably fine" is not a category to trust once a defect class is known.**

### Flake ledger for `xBillUITests/RegressionUITests`
Recorded so the next recurrence starts with data instead of a guess.

- **`testArchiveUnarchiveRegression` — was a real regression, now fixed.** Passed 4/4 across
  2026-08-02…04, then failed twice in three runs on 08-12. It was **wrongly recorded as a transient
  flake** after it passed one re-run; the bundle history said otherwise. Cause: the missing
  `contentShape` on the group row. Two consecutive passes after the fix.
- **`testAuthValidationRegression` — genuine flake, unexplained.** Passed **9** runs including twice
  on the exact current code, then failed once on 08-15 with
  `Failed to not hittable … xBill.emailAuth.toggleModeButton`. It follows `dismissSheetIfPossible()`,
  so the Forgot Password sheet was most likely still dismissing and covering the button. Timing, not
  hit area. Not investigated further; if it exceeds roughly 1 in 10, harden the dismissal wait.

**Verification:** unit **329/329**. UI regression **18/18** on the run after the group-row fix, and
`testArchiveUnarchiveRegression` green in both subsequent runs. Debug and Release both build.
Installed on physical iPhone 16 Pro; **user confirmed on device** that the FAB, Add Friend, shares
steppers, back button and settings rows now respond on the first tap anywhere on the control.

## Recent Fix Log — 2026-08-12 (later still) — Liquid Glass on the interface layer

### The glass had been lost in the redesign, and this file claimed otherwise
`CLAUDE.md` listed seven Liquid Glass surfaces. Measurement found **one** live call site
(`BalanceBadge`) — and `BalanceBadge` was referenced nowhere, so the app had **no reachable glass
at all**. Two of the views named here (`GroupRowView`, `SettleUpView`) no longer exist; the rest
lost their glass during the DesignSystem migration and nobody noticed because nothing tested it.

**System chrome was already correct** and needed no work: the app links `iphonesimulator26.5` and
sets no `UIDesignRequiresCompatibility`, so tab bars, navigation bars and sheets get Liquid Glass
automatically on iOS 26. Only the custom surfaces had regressed.

### Applied to the interface layer only
Apple's guidance is that glass belongs to the layer floating **above** content, not to content
itself; glass-on-glass and text-on-glass hurt legibility, especially over this app's cream canvas.
So content rows and cards (`XBillExpenseRow`, `XBillGroupCard`, `XBillBalanceCard`,
`XBillFriendRow`) are deliberately unchanged.

| Component | Treatment | Call sites |
|---|---|---|
| `XBillFloatingAddButton` | tinted interactive glass, `Circle` | 1 |
| `XBillButtons` (shared base) | tinted interactive glass; **disabled stays flat** | 12 |
| `XBillSearchBar` | glass, rounded rect | 3 |
| `XBillSegmentedControl` | glass on the **selected** pill only | 3 |
| `AmountBadge` | **tinted** glass, `Capsule` | 6 |

- **Tinted variants added** to the `Extensions.swift` wrappers (`liquidGlass(tint:fallback:in:)`,
  `liquidGlassButton(tint:fallback:in:)`). Untinted `.regular` glass takes its colour from what is
  behind it, which would have rendered `AmountBadge`'s "owed to you" green and "you owe" red
  **identically** — destroying the semantic signal. `.tint()` keeps the meaning and lets glass
  supply only depth.
- **Disabled buttons stay flat.** Glass reads as live and touchable; a disabled control in glass
  invites taps that do nothing, undoing the E-1/E-2 affordance work.
- **Only the selected segment gets glass**, so the track does not become glass-on-glass.
- **Skipped as dead code:** `XBillTabBar` and `FABButton` (0 uses — the app uses the native tab
  bar, which gets glass free from the SDK). `BalanceBadge` was **deleted**; it was unreferenced and
  held the app's last orphaned glass call, so it read as part of the glass system while being
  unreachable.
- Deployment target is **iOS 17.0**, so every wrapper keeps an `#available(iOS 26, *)` guard and a
  defined flat fallback. Release was built as well as Debug to prove glass is not Debug-only.

### Key Pattern — tint glass whose colour carries meaning
Reach for `.glassEffect(.regular.tint(x))` rather than `.regular` wherever the fill is a signal
rather than decoration. And check a component is *referenced* before styling it — `BalanceBadge`
absorbed the only glass in the app while being dead.

**Verification:** unit **329/329**, UI regression **18/18**, both `0` failures / `0` skips
(`TestResults/Coverage/2026.08.12_20-27-32-regression-ui.xcresult`). Debug **and** Release builds
succeeded; installed, launched, and the rendered result inspected by screenshot — tinted glass
renders with brand colour and text contrast intact.
**Flake recorded, not diagnosed:** an earlier run of the same UI suite failed
`testArchiveUnarchiveRegression` **once**. It then passed both in isolation and on a full re-run,
and the original failure message was never captured, so the cause is **unknown**. Logged here so a
recurrence has a prior data point rather than looking like a first occurrence. A first attempt to
reproduce it was itself invalid — a bare `xcodebuild` omits the UI-test credentials and failed for
that unrelated reason.
**Not verified:** appearance on real hardware. Glass composites against live wallpaper and ambient
content that a simulator does not reproduce; contrast on the tinted badges deserves a device look
before submission.

## Recent Fix Log — 2026-08-12 (later) — CRASH-01: index-backed element bindings

### A production crash in the shipped build, from `ForEach($array)`
A device crash report for **1.0 (1)** — the build now live on the App Store — showed
`EXC_BREAKPOINT`/`SIGTRAP` on the main thread: `Array._checkSubscript` → `_assertionFailure`,
reached from `Switch.updateUIView` → `Binding<A>.subscript.getter`. An **array index out of range**
inside a SwiftUI element binding.

**There is no app frame below `main()`.** The trap happens inside SwiftUI's deferred update pass
(`_UIUpdateSequenceRunNext`), long after the body that produced the binding returned, so the stack
names no view. The site was identified by elimination: `ForEach($vm.splitInputs)` in
`AddExpenseView` held the app's only collection-bound `Toggle`, and `Toggle`/`Switch` frames are
explicit in the stack.

- **`AddExpenseView` (the crash site).** Now `ForEach(vm.splitInputs)` over **values**; the Toggle,
  the shares ±, and the exact-amount field each resolve the row by `userID` through the view model.
  `AddExpenseViewModel.toggle(participantID:)` already did the safe id lookup **and no view had
  ever called it** — the safe path was written and never wired up. Added `input(for:)`,
  `setAmount(_:participantID:)`, `adjustShares(by:participantID:)` (clamped at 1, a rule that
  previously lived in the `-` button and only held while every caller remembered it).
- **`ReceiptReviewView` (sibling, found by sweeping for other `ForEach($`).** Arguably worse:
  `.onDelete { vm.items.remove(atOffsets:) }` sits directly on a `ForEach($vm.items)`, so the array
  shrinks by user action while index-backed bindings are live. Converted to value iteration;
  `ItemRow` takes a value; the last binding-written field gained `updateName(itemID:name:)`; and
  `.onDelete` now maps offsets to **ids before mutating**, so a shifted row cannot be deleted by
  mistake. This site has **no `Toggle`**, so it is not what crashed — it is a live bug that had not
  been reported yet.

**What was not established:** the exact sequence that invalidates the index in `AddExpenseView`.
`splitInputs` is assigned only in `init` and the VM is correctly owned in `@State`, so the first
hypothesis — the array shrinking — was measured and **disproved**. The fix does not depend on
knowing: id resolution makes an out-of-range index *unrepresentable* rather than unlikely.

### Key Pattern — never `ForEach($collection)` for editable rows
Element bindings are backed by an **array index**, and UIKit reads them back during a deferred
update pass after the producing body has returned. Iterate values and resolve every edit by id
through the model. A bounds check at the call site is not equivalent — a call site can forget,
`firstIndex(where:) + guard` cannot. Sweep for `ForEach($` before shipping; the second instance
here was found only because the first was.

**Verification:** `scripts/run-coverage.sh unit` → **329 passed, 0 failed, 0 skipped**
(`TestResults/Coverage/2026.08.12_19-39-55-unit.xcresult`), new suite confirmed present by name.
Mutation-tested: replacing the three `guard let index … else { return }` with `?? 0` fails
`absentParticipantIsInert` and **only** that test — the four positive-direction tests correctly
still pass, since they use ids that exist. Version bumped to **1.1 (2)**, verified against the
**built artifact** (`CFBundleShortVersionString` `1.1`, `CFBundleVersion` `2`), installed and
launched on `DA97985A-F7CC-44F6-8281-9DD24C22B978` (PID 95320).
**Not verified:** that the crash is gone. It was never reproducible on demand, the tests cannot
reach SwiftUI's update cycle, and absence of a crash report is not proof. What is proven is that
the trapping construct no longer exists anywhere in the app.

## Recent Fix Log — 2026-08-12 — App Store review prompt (ASO-01)

### The app had no way to ever ask for a rating
v1.0 went live 2026-08-11 with **zero** StoreKit integration — no `requestReview`, no
`SKStoreReviewController`, no `import StoreKit` anywhere. At 0 ratings with no mechanism to ask,
the app stays at 0 ratings indefinitely, which suppresses both App Store search ranking and
conversion for everyone who does reach the page. Found while diagnosing why xBill was not
appearing in App Store search 24h after release.

- **`ReviewPromptService.swift` (new)** — `ReviewPromptPolicy` is a pure value type holding the
  rule; the `@Observable` service owns the persisted counter and raises `isRequestPending`.
  `requestReview` is only reachable through `@Environment(\.requestReview)`, so the **view** makes
  the call and the service makes the decision.
- **Trigger: a recorded settlement**, not an added expense. Adding an expense starts a chore;
  closing a debt ends one. The call sits at the end of `recordPayment`'s `do` block, so it is
  unreachable from the duplicate-payment early return and from every failure path.
- **Milestone: 3 settlements.** Apple allows only **three prompts per user per year**, system-wide.
  An ask spent on a user with one recorded payment cannot be made later when they are invested.
- **Version-gated.** Re-asks on a later version, never twice on the same one — StoreKit swallows a
  repeat, so it burns the signal without reaching the user.
- **Deferred 800 ms and skipped while App Lock is engaged.** Record Payment is a sheet that
  dismisses on success; raising a prompt mid-transition is the defect the payment-return prompt
  already shipped (2026-07-27), and presenting while locked renders behind the lock overlay.

### Key Pattern — test the rule, not the system call
`requestReview` hands the decision to StoreKit, which may display nothing and reports no outcome.
The app cannot observe whether a prompt appeared, so the only honest thing to test is the rule
leading up to it. Extracted as a pure function rather than an injection seam — a seam still permits
the StoreKit call, a pure function cannot. Same reasoning as `IOUService.validateParties`.

**Verification:** `scripts/run-coverage.sh unit` → **324 passed, 0 failed, 0 skipped**
(`TestResults/Coverage/2026.08.12_19-13-22-unit.xcresult`); both new suites confirmed present in the
result bundle by name, not inferred from the exit status. Mutation-tested: against a policy that
always returns true, **5 of the 8 tests fail** — the 3 that do not are the positive-direction tests,
which an always-true policy legitimately satisfies. Debug build succeeded; installed and launched on
`DA97985A-F7CC-44F6-8281-9DD24C22B978` (PID 89328).
**Not verified, and not verifiable here:** that a prompt actually appears. StoreKit decides, and it
deliberately shows nothing in most debug runs. Only real-device use over time proves display.

## Recent Fix Log — 2026-08-01 (later) — UI regression suite aligned to the settlements ledger

Baseline first: `scripts/run-coverage.sh regression-ui` was **15/15 green** before any change, so
the settlements rename had not broken the suite. Three findings came out of aligning it
(`AUDIT_REPORT.md` → `UIT-01`…`UIT-03`); the suite is now **16/16**.

- **UIT-01 — five accessibility identifiers did not exist at runtime.**
  `.accessibilityIdentifier` on the settlement row's enclosing `VStack` propagates to every
  descendant and **overwrites** their own, so `recordPaymentButton`, `venmoButton`,
  `paypalButton`, `noPaymentHandle` and `nonPartyCaption` were all reported as the row id. The
  identifier now sits on the header `HStack`, which already forms its own accessibility element.
  **The suite already referenced `xBill.settleUp.recordPaymentButton.` and it could never have
  matched** — it survived only inside `||` chains where another branch was true. A green
  assertion that cannot fail is worse than a missing one.
- **UIT-02** — `xBill.uitest.tab.groups` was a tap candidate in two test files and defined nowhere
  in the app; a leftover from the DEBUG hit-target overlay removed in M-66.
- **UIT-03 — the ledger had no UI coverage at all.** The seed fixtures create groups with the
  owner as the only member, and a single-member group cannot hold a debt, so the settle-up test
  could only assert the "All Settled Up!" empty state. None of the four defects device testing
  found earlier the same day was reachable from this suite. New
  `scripts/seed-ledger-regression-group.sql` seeds a three-member `SeedLedger-Regression` group
  producing one row of every kind ($7.00 debtor, $8.00 creditor, $15.50 non-party) plus both
  sides of the delete gate.

### Key Pattern — a container's accessibilityIdentifier overwrites its children's
Never put `.accessibilityIdentifier` on a row/card container that holds identified controls. It
propagates down and replaces theirs, silently deleting every inner identifier. Attach it to a
subview that already forms its own accessibility element (`.accessibilityElement(children:
.ignore)`), and after adding identifiers to a composite row, assert one of the *inner* ones from
a UI test — a prefix predicate sitting in an `||` chain will pass without ever matching.

### Key Pattern — a UI test fixture needs more than one member
`seed-ui-test-data.sh` seeds single-member groups, which can never carry a debt, so any
balance/settle-up assertion against them degenerates to the empty state. Multi-member scenarios
need `scripts/seed-ledger-regression-group.sql`. Its name follows the `SeedActive`/`SeedArchived`
convention deliberately: those names sit **outside** the disposable prefixes in
`purge-ui-test-groups.sh`, so a routine purge cannot delete the fixtures a regression run depends
on. `testSettleUpLedgerRegression` is **read-only** — it opens the Record Payment sheet and
cancels, because recording would move the fixture's balances and the next run would start
somewhere else. It covers the surfaces, not the writes.

## Recent Fix Log — 2026-08-01

### Settlements ledger — device verification, and a crash only the device could find
All 8 device tests pass against production (migration 041 + `notify-settlement` deployed). Four
defects were found on this branch **by device testing, with 255 unit tests green throughout and
eight code reviews passed**. That ratio is the point: every one of them was invisible to the suite.

- **The settle-up row named nobody (DEV-00, fixed in `dd40b74`).** Two avatars and an amount, so a
  row read "A → A $7.00" whenever two members shared an initial — precisely when knowing who owes
  whom matters most. Rows now name the parties in text.
- **`8` instead of `8.00` in Record Payment (`03d8079`).** `NSDecimalNumber.stringValue` drops
  trailing zeros — the API `H-39` banned, and the same behaviour that made PayPal.Me ignore a
  settlement amount (`95USD`). `PaymentLinkService.formattedAmount` already existed for exactly
  this; the sheet just wasn't using it. The final review flagged the line as a Minor and it was
  triaged as low-risk. It was visible on the first screen opened.
- **Settle-up rows had random identity (DEV-01, `eb78006`).** `SettlementSuggestion` stored an
  `id: UUID` that all four construction sites filled with `UUID()`, so every recompute gave
  structurally identical rows new identities. The stored id is **removed**, not assigned more
  carefully — `id` is now computed from `fromUserID|toUserID|currency` (currency included because
  `crossGroupSuggestions` minimizes per currency and concatenates). Also fixed six accessibility
  identifiers that changed on every refresh, which no UI test could have targeted.
- **SIGABRT deleting a payment (DEV-03, `022457c`) — the real crash.** `deletePayment` removed the
  row from `settlements`, then `await computeBalances()`, which **fetched splits over the network**
  before reassigning `settlementSuggestions`. That `await` split one user action into two
  separately published mutations of the same `List`, landing either side of a round-trip while the
  swipe-delete animation was in flight; `UICollectionView` aborted with *"the number of items ...
  after the update (3) must be equal to the number ... before the update (2), plus or minus the
  number inserted (0)"*. Recording or deleting a payment changes the ledger and **cannot change a
  split**, so `splitsMap` was already correct and the fetch was never needed. New synchronous
  `applyDerivedBalances()` keeps both mutations in one turn. `load()` still refetches.

**Two wrong diagnoses preceded the right one.** DEV-01 was shipped as the crash fix on mechanism
plausibility and disproved by the next device run; a second hypothesis (the `List` swapping to its
loading state) was killed before shipping by reading the predicate — both branches require
`settlementSuggestions.isEmpty`, and there were 2.

**What broke the loop was instrumentation, not insight (DEV-04).** The sentence identifying a UIKit
assertion exists **only** in the `NSException` `reason`; the `.ips` crash report does not carry it,
so it was reachable only by holding a `--console` session open at the instant of the crash. That
failed twice — once the console had detached, once the device went `tunnelState: unavailable`.
`AppDiagnostics.installUncaughtExceptionLogger()` now writes name, reason and stack into the
Documents log, making retrieval independent of when the crash happens. The next reproduction
produced the sentence, and the sentence produced the diagnosis.

Verification: **256 unit tests**, 0 failed (the DEV-03 regression test asserts both payment paths
fetch **zero** splits — a fetch is the suspension point — and was verified to fail against the
pre-fix code). Release build clean. Device: `deletePayment.enter` → `.committed` in ~50 ms,
`wasResurrected=false`, no `uncaughtException`. Database confirmed after each write: the creditor
path (`Bob Patel → App Reviewer $8.00`, `recorded_by` = App Reviewer) and the partial payment
(`App Reviewer → Alice Chen $3.00`, leaving $4.00 derived, not stored).
Evidence: `diagnostics/2026-08-01-settlements/`.

### Key Pattern — a user action must publish one state change, not several
Never `await` between two mutations that feed the same `List`. A suspension point splits one user
action into two updates; if an animation (a swipe action, a row removal) is in flight, SwiftUI
coalesces them against the collection view's already-applied state and `UICollectionView` aborts.
Before adding an `await` inside a mutation path, ask what it is fetching and whether that data can
have changed — here it could not, and the round-trip was pure cost plus a crash.

## Recent Fix Log — 2026-07-28

### Senior review remediation (REV-02 … REV-13)
A read-only senior review found 13 issues (`AUDIT_REPORT.md` → `REV-01`…`REV-13`). Twelve are fixed; `REV-01` is open pending a product decision. Highlights:

- **Partial settlement no longer lies (REV-02).** Splits were settled in a throwing task group, so one rejected write aborted the group while the writes that had already committed stood — the user saw a generic error and the app recorded none of them. Each split now settles independently, only what committed is confirmed locally, and a partial result reports "Only N of M parts were recorded" with no settlement push.
- **A deleted expense could resurrect (REV-03).** `applyFetchedExpenses` re-merges `locallyCreatedExpenses` entries a fetch does not return, and only clears an entry when the fetch *does* return it. `deleteExpense` never removed it, so a just-deleted local expense came back on every later load.
- **The stale-data warning could never fire (REV-04).** `applyFetchedExpenses` raised `balanceLoadFailed`; `computeBalances` then cleared it at the top, before any view read it. Cleared at the start of `load()`'s network branch instead.
- **Queued balance recomputes were dropped (REV-05).** The catch block's early `return`s discarded `shouldRecomputeBalances` — the exact failure the coalescing existed to prevent. They now `continue`, which re-checks the `repeat`/`while` condition.
- **Percentage splits were never validated (REV-10).** `canSave` only checked `.exact`, so a 40/30/20 entry saved with the missing 10% of the bill silently moved onto one participant by the remainder assignment. New `SplitCalculator.validatePercentages`.
- **Sub-cent settlement drift (REV-11).** `minimizeTransactions` emitted a rounded transfer but decremented balances by the unrounded one, so two 0.006 residuals each rounded up to a full cent — asking a debtor who owed one cent to pay two.
- **Affected-row checks generalised (REV-06).** New `xBill/Core/SupabaseWrite.swift` is the single place a zero-row write is detected; `RemoteNotificationService`'s local equivalents were folded into it and it now guards five delete paths.
- **REV-13 deliberately not "fixed".** Netting mutual debts reintroduces the defect `directSettlementSuggestions` exists to prevent — a netted $4 matches none of the debtor's whole splits.

`GroupViewModel` gained an injection seam (`GroupDataProviding` / `ExpenseDataProviding`, defaulted to the singletons) because every one of REV-02…REV-05 ran through a `.shared` service and could not otherwise be exercised. Mirrors the `ActivityViewModel` seam.

Verification: `scripts/run-coverage.sh unit` → **216 passed, 0 failed, 0 skipped**. Release build succeeded. REV-11 and the three GroupViewModel regressions were each confirmed to fail against the pre-fix code.

**`REV-01` — CLOSED on branch `feat/settlements-ledger`, not yet deployed.** The product decision was taken: neither gate the button to the debtor nor add a `SECURITY DEFINER` RPC, but replace `splits.is_settled` with a `public.settlements` ledger (migration 041) where **either party may record a payment** and the UI is gated to match the RLS exactly. The paragraph below describes the pre-branch state and is kept as the record of why. Historical: the live RLS policy on `splits` is `auth.uid() = user_id`, so only the debtor can settle, but the Settle Up list is unfiltered and the "Mark as Settled" button ungated. A creditor's tap silently affects zero rows, is force-hidden locally by `locallyConfirmedSettledSplitIDs`, and fires a settlement push. Fixing it needs a product decision: gate the button to the debtor, or add a `SECURITY DEFINER` RPC so a creditor can confirm receipt. **Do not widen the RLS policy** — `is_expense_group_member` would let any member settle anyone's debt.


### Notification unread state did not survive an app-lock cycle — ROOT CAUSE FIXED
On a physical iPhone, marking a Recent notification unread appeared to work, then reverted to read after backgrounding, Face ID unlock and returning. Two faults compounded; the device log — not the test suite — was what made either visible.

**Root cause.** The Activity list mixes two kinds of row: authoritative `public.notifications` rows, and historical expense-derived rows synthesised for accounts that predate migration 040. `NotificationItem.expense(...)` uses the **expense id** as the item id, and nothing distinguished the two origins, so a read/unread toggle on a history row issued `UPDATE public.notifications … WHERE id = <expense id>` — which matches **zero rows**. Verified read-only against the live database: 12 expenses, 3 notification rows, **zero id overlap**. `ActivityService.fetchRecentActivity` then forced `isRead = true` on every history row on every refresh, so the unread mark was erased by the refresh that runs after unlock.

**Why the symptom changed after `2911833`.** That commit added `.select("id").single()` as an acknowledgement. `.single()` only sets `Accept: application/vnd.pgrst.object+json`; on a zero-row match PostgREST answers PGRST116 **"Cannot coerce the result to a single JSON object"**. That reads as a response-shape fault and hides "no row matched", so the same zero-row write changed from a silent no-op into a user-visible *Activity Update Failed* alert. Before it, the write reported success, the pending intent was cleared, and the next refresh reverted the row — the originally reported behaviour.

**Fixes.**
- `NotificationItem.isServerBacked` distinguishes a real `notifications` row from expense-derived history. Cache entries written before the flag existed decode as local (`decodeIfPresent ?? false`).
- `ActivityViewModel.setReadState` (replaces the duplicated `markRead`/`markUnread` bodies) writes through **only** for server-backed rows. A history row's read state is local-only: no request, no pending intent to replay, no failure alert.
- New `ActivityReconciler.reconcile(remoteItems:legacyItems:storedItems:pendingReadStates:)` — a pure function — preserves the stored read state for history rows and defaults only *unseen* rows to read, so pre-040 history still never inflates the badge.
- `RemoteNotificationService.updateReadState` decodes the `return=representation` response as an **array** and checks the affected-row count via `acknowledgeUpdate(rows:id:)`, throwing `RemoteNotificationError.rowNotFound`. No dependence on `.single()`'s response shape.
- `NotificationReadStatePayload` encodes `read_at` as an explicit **UTC** ISO-8601 instant. The SDK's own strategy emits a zone-less `2023-11-14T22:13:20.000` that Postgres resolves with the session `TimeZone`; that is UTC on this project (verified with `show timezone;`) but the read time should not depend on a server setting. Unread still sends an explicit JSON `null`.
- Rollback on a failed write now reverts **only the affected row**. It previously restored a whole snapshot of `items`, which could revert unrelated rows changed while the write was in flight.
- `reconcilePendingReadStates` clears a pending intent on `rowNotFound` instead of retrying a write that can never succeed.
- `AppDiagnostics.describe` now logs PostgREST `code`/`detail`/`hint`. `localizedDescription` alone showed only the coercion message; `PGRST116` + "The result contains 0 rows" is the part that identifies the real fault.

**Verification.** `scripts/run-coverage.sh unit` → **185 passed, 0 failed, 0 skipped** (`TestResults/Coverage/2026.07.28_19-00-36-unit.xcresult`). Release build succeeded (confirms the DEBUG-only diagnostics still compile out). Debug build installed on physical iPhone 16 Pro `00008140-000135EE3432801C`. **Device-verified:** the user ran Recent → Mark Unread → background → Face ID unlock → return and confirmed the mark survived; the pulled log (`diagnostics/2026-07-28-notification-unread/after-fix.log`, session `2026-07-28T23:05:58Z`) shows the full lock/unlock cycle with **zero** `markRead.failed`/`markUnread.failed` and **zero** `Activity Update Failed` alerts — the last such entries are at `22:31:23Z` in the pre-fix session. The log carries no `readState.localOnly` line, so it does not establish which row kind was toggled; the history-row path is worth one explicit re-check on an older expense row.

### Notification delete path + diagnostics — follow-up batch
The delete path carried the same two faults as the read-state path, and the post-fix device log could not show which row kind a run had exercised. All fixed in the same session (NOTIF-09…NOTIF-12 in `AUDIT_REPORT.md`):

- **`RemoteNotificationService.delete` had no affected-row acknowledgement** — the same latent fault as the read-state update. An RLS miss, or an id that is not a notification row, returned HTTP 200 with an empty body and read as success. Now `.delete().eq("id").select("id")` decoded as an array through the shared `acknowledgeAffectedRows(_:id:)` (renamed from `acknowledgeUpdate`; both paths use it).
- **Deleting a history row did not stick** — the row vanished locally and the next fetch re-derived it from the expense list. History-row deletes are now local-only and recorded via `NotificationStore.dismissHistoryItem`; `ActivityReconciler` filters dismissed ids out of the legacy set. Capped at 200, user-scoped, and **never** applied to server rows — deletion there is authoritative and the fetch simply stops returning them.
- **Failed-delete rollback was unscoped** — it restored a whole snapshot of `items` and reinstated the row at the end of the list. It now restores only that row, at its original index.
- **Successful writes logged nothing** — so the first post-fix device log could only show the absence of errors, never which row kind ran. `ActivityViewModel.readState.remote` (id/isRead/succeeded) and `delete.localOnly` now make the path explicit in the log.

Verification: `scripts/run-coverage.sh unit` → **193 passed, 0 failed, 0 skipped** (`TestResults/Coverage/2026.07.28_19-41-38-unit.xcresult`); Release build succeeded; installed on the physical iPhone. **Read state is device-verified on both paths** — log session `2026-07-28T23:47:42Z` (`diagnostics/2026-07-28-notification-unread/after-followup.log`) shows `readState.localOnly … serverBacked=false` for a seeded history row and `readState.remote … succeeded=true` for a server row, both surviving the Face ID unlock, with zero failures; the user confirmed both unread dots persisted. The **delete** fixes are device-verified too: `delete.localOnly id=EEEEEEEE-0001-…` at `2026-07-29T00:30:11Z` — the same seeded history row — followed by a lock / Face ID / refresh cycle after which the row did not reappear. **0 failure lines** across the whole session. The only path left unexercised on device is deleting a *server-backed* row, deliberately skipped because it permanently removes one of only three real notification rows; its acknowledgement is the same `acknowledgeAffectedRows(_:id:)` confirmed live by the read-state update.

### Key Pattern — an Activity row is not necessarily a server row
`ActivityView` shows `public.notifications` rows *and* expense-derived history. Never route a read/unread/delete mutation to the notifications table without checking `NotificationItem.isServerBacked` — a history row carries an expense id and the write silently matches zero rows. A history row's read state and its deletion are **local-only**, held in `NotificationStore` and re-applied by `ActivityReconciler` on every fetch; without that the next refresh re-derives the row straight out of the expense list.

Equally, never use `.single()` as an affected-row check: it is only an Accept header, and a zero-row match surfaces as PGRST116 *"Cannot coerce the result to a single JSON object"* rather than "no rows". Decode `return=representation` as an array and count — `acknowledgeAffectedRows(_:id:)` is the single place that does this, and every mutating call on `notifications` goes through it.

And log the **success** path, not just failures. A log that only records errors can prove the absence of a failure but never which code path actually ran — that gap cost an extra device round-trip here.

## Recent Fix Log — 2026-07-27
- **Server-backed notification history** — Added migration `040_notifications.sql` and `RemoteNotificationService`. Expense, settlement, comment, and friend-request Edge Functions now persist recipient notifications with recipient-scoped dedupe keys; APNs badges count unread notification rows, and Activity read/delete actions update the server and icon badge. After a successful fetch, Activity uses the server snapshot for notification state while supplementing it with historical expense activity for existing accounts; the local store remains an offline cache.
  > **Superseded in part by the 2026-07-28 fix above.** Two claims here are no longer true: historical expense activity is **not** read-only — the user can mark it read/unread and delete it — and Activity read/delete actions **do not** always update the server. A history row carries an *expense* id, has no row in `public.notifications`, and its read state and deletion are local-only. Routing one to the server matches zero rows; that is precisely the defect fixed on 2026-07-28. Check `NotificationItem.isServerBacked` before any Activity mutation.
- **Settlement reloads no longer resurrect freshly settled rows** — A physical-device run showed local state at 3 suggestions, followed by a server reload returning 4 due to a stale read-after-write snapshot. Confirmed split IDs now overlay fetched splits for the lifetime of the group view model.
- **Settle Up applies confirmed settlement writes locally before reload** — A device run updated three splits successfully, but an immediate read returned the old suggestion count. The view model now marks those split IDs settled in its local map and recomputes suggestions immediately, while the server reload reconciles afterward.
- **Settlement success now refreshes Settle Up** — On-device logging showed `settleSplit` succeeded, but the follow-up `load()` was skipped because `recordSettlement` still held `isLoading = true`; the stale suggestion row remained visible. The operation now clears its loading state before reloading.
- **Settle Up now emits actionable direct-debt suggestions** — Net-balance minimization could invent a transfer amount that did not match any whole unsettled payer→debtor splits, causing the physical “Mark as Settled” path to reject a valid-looking row. Suggestions now aggregate actual direct splits, and payment-app buttons are shown only to the person who owes; incoming rows remain manually markable.
- **Removed obsolete `SettleUpView`** — `GroupDetailView` is the only live Settle Up implementation and contains the payment-handle and return-prompt work; deleting the unused view prevents future readers from following an incomplete path.
- **Profile refresh now respects unsaved edits** — `ProfileView` marks `ProfileViewModel.isEditing` while the edit sheet or payment-handle fields are being changed, suppressing background refresh overwrites until a successful save or explicit dismissal.
- **Payment-return prompt: two device-only defects found by on-device testing** — Neither was reachable from the simulator or either test suite; both need App Lock enabled, a real app switch and a physical device. (1) **Armed but never presented** — device logs showed the state machine running correctly (`pendingHandoff` consumed) while nothing appeared on screen. Setting `handoffPrompt` synchronously raises the dialog while `ContentView` is still animating `AppLockView` away over 0.3s, and SwiftUI drops a presentation made from a descendant mid-transition; `presentHandoffPromptIfReady()` now waits for that transition to settle. (2) **"Not yet" did not render** — a `.cancel`-role button inside a `confirmationDialog` is not reliably shown with its own title, so only "Mark as Settled" appeared. Switched to `.alert`, the correct control for a binary question, which guarantees both titled buttons. Added `handoffPrompt.deferred` / `.arming` / `.presented` diagnostics — distinguishing "never armed" from "armed but not presented" is what made this diagnosable instead of guesswork. Verified on device: `deferred(appLocked)` → `arming` → `presented`, both buttons render, "Not yet" leaves the settlement unsettled.
- **PayPal renders a profile page, not a payment screen, for a self-payment** — Investigated at length and **not an xBill defect**. With the tester's own handle on the demo profile and the PayPal app signed in as that account, `paypal.me/<handle>/<amount>` shows the profile rather than a payment screen. Confirmed by elimination: $1.90 and $9.50, both correctly formatted, both render the profile. An earlier Safari test of `5.00USD` *did* show a payment screen, but Safari and the PayPal app are different renderers and comparing across them was a false signal that caused the seed amounts to be rescaled twice for nothing. The device log proves xBill builds the correct URL and `openURL` accepts it. **Seeded demo handles are back to `NULL`** for App Store review, so a reviewer sees "Ask … to add a payment handle" rather than a link into the developer's personal PayPal.
- **Payment URL amounts render with exactly two decimal places** — `PaymentLinkService.formattedAmount` (`en_US_POSIX`, grouping disabled). String-interpolating a `Decimal` drops trailing zeros, so the link emitted `1.9USD` for $1.90 and `95USD` for $95.00, and **PayPal.Me ignores an amount that is not two decimals** — verified on device: `/1.9USD` renders the plain profile, `/5.00USD` opens a real $5.00 payment screen. This was a **pre-existing** bug affecting every round settlement amount, not one introduced by the seed scaling; it went unnoticed because the fabricated seed handle made every link fail earlier for a different reason. Grouping is disabled so 1234.50 renders `1234.50` rather than a URL-breaking `1,234.50`. The prior test asserting `12.50` → `"12.5"` had pinned the bug in place on the strength of an unverified comment claiming PayPal accepted that form.
- **`PaymentHandleValidator` — one validator, two distinct provider rule sets** — Handle rules previously lived in **three** places that disagreed: `ProfileView.venmoValidationMessage` / `paypalValidationMessage`, `PaymentLinkService.normalizedHandle`, and a second regex inside `paypalLink`. All three wrongly accepted `.`, `-`, `_` and 2-character handles, so a handle could pass entry validation and still never produce a working link. New `xBill/Services/PaymentHandleValidator.swift` is now the single source of truth, consumed by both entry (`ProfileView`, `ProfileViewModel`) and output (`PaymentLinkService`). Rules are **sourced from each provider, not inferred**: PayPal.Me is **3–20 ASCII letters and digits only** ("between 3 and 20 characters", "only using letters and numbers"); Venmo is **5–30 ASCII letters, digits, `-` and `_`** (per [Venmo help](https://help.venmo.com/cs/articles/check-or-edit-your-username-vhel208): "must be between 5 and 30 characters", "no special characters other than `-` and `_`"). **The charsets must stay separate** — `-`/`_` are legal for Venmo and illegal for PayPal, and `.` is illegal for both. Uses an explicit ASCII `Set<Character>`, deliberately *not* `CharacterSet.alphanumerics`, which would wrongly accept accented and non-Latin letters. A leading `@` is stripped when present rather than required, because a real username contains none. API: `validate(_:for:) -> Result` (`.valid(String)` / `.invalid(reason:)` / `.empty`) and `normalized(_:for:) -> String?`. Tightening was safe at this exact moment because the seed fix had left `profiles_with_handles = 0` — no stored handle could be invalidated.
- **Test-your-link, so a bad handle is caught by its owner** — Once a **saved** handle validates, `ProfileView` shows a "Test your PayPal/Venmo link" row opening `PaymentLinkService.profileLink(handle:method:)` — `https://paypal.me/<handle>` or `https://venmo.com/u/<handle>`, **with no amount**, so testing never opens a payment screen. Gated on the saved value with no unsaved edits, so it always tests what is actually stored. A live reachability check (scraping PayPal's `slugDoesNotExist` marker) was considered and **rejected**: that marker lives in an undocumented JS bundle, PayPal could rename it and the check would silently start passing bad handles, and Venmo has no equivalent. Letting the payment app answer "does this link work" is the robust form. Verified 2026-07-26: `venmo.com/u/<handle>` returns a clean 404 for a nonexistent handle, while `paypal.me/<handle>` returns 200 and renders PayPal's own error page.
- **Settle-up shows the destination and explains an absent one** — `GroupDetailView.settlementRow` now labels the button `PayPal · @handle` / `Venmo · @handle`, so a payer can spot a wrong recipient before leaving the app. When a recipient has no usable handle for either provider it renders "Ask <Name> to add a payment handle in their profile." instead of nothing at all — previously the button silently disappeared and looked like a bug. A partial case (one valid handle) still shows that one button.
- **"Did you complete this payment?" prompt on return** — xBill hands off to a payment app and never learns the outcome, so a debt could silently stay open. `GroupDetailView` records a pending handoff and, on the next `scenePhase == .active`, asks whether the payment completed → *Mark as Settled* (existing `recordSettlement`) or *Not yet*. Default is **unmarked; nothing auto-settles**. Three load-bearing guards: (1) armed only when `openURL`'s completion reports `accepted == true`, so it never fires if the payment app did not open; (2) cleared after one answer, so it cannot re-ask on every later foreground; (3) **deferred while `AppLockService.shared.isLocked`**, retried via `.onChange(of: AppLockService.shared.isLocked)` — App Lock engages on backgrounding, so returning from a payment app lands still-locked and presenting then would render the dialog *behind* the lock overlay and look like a hang. State lives in `@State private var pendingHandoff` — view state, not model state, since a handoff has no meaning once the screen is gone. Note: `GroupDetailView.body` was split into `baseContent` / `lifecycleContent` / `decoratedContent` to escape a Swift type-checker timeout triggered by the added `.onChange` and fifth `.confirmationDialog`; verified a pure refactor with identical modifiers and order.
- **Seeded demo amounts scaled ÷50** — Entering a real PayPal handle on the demo account makes the settle-up button open a **genuine payment screen** for the settlement amount; at $95.00 a stray tap during on-device testing sends real money. Every expense, split and the IOU in `supabase/seed_app_store_review_account.sql` divides by 50 to an exact 2-decimal value, so splits still sum to their totals and no `is_settled` flag changed. Tokyo Trip keeps 5 expenses, 15 splits, 3 members, 2 comments, 1 IOU; the settlement drops **$95.00 → $1.90**. Chose ÷50 over ÷100 (which would give $0.95) to stay above a possible but **unverified** $1.00 PayPal.Me minimum, rather than let "minimum" reintroduce a broken link. `SETUP_REVIEW_ACCOUNT.md` balances updated to owed **$4.40** / owes **$1.00** / net **$3.40**. Applied to the live database and verified there: every expense's splits sum exactly, IOU `0.50`, 15 splits with 5 settled, `profiles_with_handles = 0`.
- **`PaymentDiagnostics` generalised into `AppDiagnostics`** — The DEBUG-only on-device logger was named after the single PayPal-handoff investigation below, so the next agent debugging something unrelated would have started a second file and scattered the evidence. Renamed `xBill/Core/PaymentDiagnostics.swift` → `xBill/Core/AppDiagnostics.swift`; `log(_:_:_:)` now takes a `Category` (`.payment, .auth, .balance, .lifecycle, .sync`) as its first parameter, and `[category]` appears in every log line. `Category` is declared **outside** `#if DEBUG` — call sites pass `.payment` etc. in both Debug and Release builds, and Release compiles to the no-op stub. Log file renamed `Documents/payment-diagnostics.log` → `Documents/xbill-diagnostics.log`. Added a 2 MB size cap: once exceeded, `rotateIfNeeded` keeps the newest half of lines and writes a `===== ROTATED <timestamp> =====` header, so an append-only file on a device cannot grow without bound. All 27 call sites recategorised: `Extensions.swift` alert-presentation chokepoint and `ContentView`/`MainTabView`/`GroupDetailView` scenePhase/lifecycle events → `.lifecycle`; `HomeViewModel`/`GroupViewModel` load/balance events → `.balance`; `GroupDetailView.openPaymentURL.*` → `.payment`. `diagnostics/2026-07-27-paypal-handoff/README.md` updated with the new log filename in its retrieval commands and a new "Index of investigations" table as the entry point for future investigations. (**Superseded 2026-07-28:** that per-folder README was consolidated into `diagnostics/README.md`, now the single index — dated folders hold raw evidence only.) Verified: Debug simulator build, Release simulator build (confirms DEBUG-scoping), and full `xBillTests` all succeeded.
- **PayPal "Something went wrong" on settle-up handoff — ROOT CAUSE FIXED (not an xBill bug)** — Tapping PayPal on a Tokyo Trip settlement suggestion ended in a "Something went wrong" error. Three previous fix attempts edited xBill lifecycle code and none worked. **Root cause: `supabase/seed_app_store_review_account.sql` seeded fabricated payment handles** (`venmo_handle` / `paypal_handle` = `'appreviewer'`) for the demo profiles. `PaymentLinkService` renders those as live outbound deep links, so the PayPal app resolved `https://paypal.me/appreviewer/95USD`, found no such profile, and displayed **its own** error. The error was never produced by xBill. Confirmed by on-device instrumentation: across three background/foreground cycles xBill logged **zero** alerts, every `load` succeeded, `suggestions=2`, `hasLoadedBalances=true`, `balanceLoadFailed=false`, no spinner. Independently verified: `paypal.me/appreviewer/95USD` returns HTTP 200 serving PayPal.Me's *error* bundle (`slugDoesNotExist`, header `"Something went wrong"`), whereas a random slug returns a plain 404. Venmo used the same fabricated handle but its app degrades quietly instead of hard-failing, which is why Venmo looked "fixed". **Fix:** all seeded payment handles are now `NULL`, so `PaymentLinkService.paymentLink` returns `nil` and `GroupDetailView` renders no payment button — no broken link is reachable. Applied to the live DB as well (`profiles_with_handles` = 0; only the 3 seeded demo profiles were affected, no real user data). Verified on physical iPhone 16 Pro: no Venmo/PayPal buttons, no alert, no spinner. Files: `supabase/seed_app_store_review_account.sql`, `xBillTests/PaymentHandoffTests.swift` (new), `xBillUITests/RegressionUITests.swift`, `project.yml`.
- **Never seed a payment handle that is not a real Venmo/PayPal.Me profile** — A fabricated handle is not an inert placeholder; it becomes a live deep link whose failure surfaces inside the third-party app and reads as an xBill defect. This is also an App Store review risk: a reviewer following the settle-up flow would have hit PayPal's error screen.

## Key Pattern — Payment handle rules live in exactly one place
- All Venmo/PayPal.Me handle validation goes through `PaymentHandleValidator` (`xBill/Services/PaymentHandleValidator.swift`). Never re-add provider-specific validation to a view, view model, or service — three disagreeing copies is precisely what let an unusable handle be saved and then fail inside the payment app. Entry validation (`ProfileView`), persistence (`ProfileViewModel.saveProfile`) and link building (`PaymentLinkService`) must all call it, so they cannot drift apart.
- The two providers have **different** rules and the charsets must never be merged: PayPal.Me is 3–20 ASCII alphanumerics; Venmo is 5–30 with `-` and `_` also allowed. `.` is illegal for both. If a rule ever needs changing, change it in the validator and cite the provider's own documentation in the comment — these rules were previously guessed, and the guess was wrong in both directions.
- Never verify a handle by scraping the provider's website. Offer the user a "test your link" action that opens the provider's profile page instead; the payment app is the only reliable authority on whether its own link works.
- **`DEVELOPMENT_TEAM` added to `project.yml`** — It previously existed only in `project.pbxproj`, so every `xcodegen generate` wiped physical-device signing. This was the recurring "signing/project churn". Device builds are now reproducible.
- **`PaymentDiagnostics` (DEBUG-only instrumentation) added, later generalised to `AppDiagnostics`** — originally `xBill/Core/PaymentDiagnostics.swift`; see the generalisation bullet above — now `xBill/Core/AppDiagnostics.swift`, log path `Documents/xbill-diagnostics.log`. Three sinks: `os_log`, `print` (captured by `devicectl device process launch --console`), and the persisted Documents log, retrievable with `devicectl device copy from --domain-type appDataContainer --domain-identifier com.vijaygoyal.xbill --source Documents/xbill-diagnostics.log`. The whole implementation is inside `#if DEBUG` and compiles out of Release (Release build verified). The highest-value piece is the **alert-presentation chokepoint** in `View.errorAlert(item:)` / `errorAlert(error:)` in `Extensions.swift`, which records every alert actually shown with its call site — that is what proved xBill was raising no alert at all.
- **Alert-surface note** — `GroupListView.swift:89` binds `.errorAlert(item: $vm.errorAlert)` **outside** the NavigationStack on the *shared* `HomeViewModel`, and `MainTabView.swift` fires `homeVM.loadAll()` on every `didBecomeActive` with errors always shown. A `HomeViewModel` error therefore presents an alert *over* a pushed `GroupDetailView`, even though `GroupDetailView` itself loads with `showError: false`. This was not the cause here, but it is the path to check first for any "unexpected alert over a group screen" report.
- **Verification — 2026-07-27** — `xcodebuild test -only-testing:xBillTests` → `** TEST SUCCEEDED **` (full unit suite). New `xBillTests/PaymentHandoffTests` → 40 cases, 0 failures. Release build → `** BUILD SUCCEEDED **`. Physical-device verification on iPhone 16 Pro (`00008140-000135EE3432801C`), Debug build installed via `devicectl`.

## Recent Fix Log — 2026-07-26
- **Venmo-return "Refreshing balances…" hang — ROOT CAUSE FIXED** — After tapping Venmo from a group's Settle Up tab, killing Venmo, and returning, the group stuck permanently on "Refreshing balances…". Root cause: `GroupDetailView`'s `GroupViewModel` was constructed **inline inside the `.navigationDestination(for: BillGroup.self)` closure** in both `GroupListView.swift` and `HomeView.swift`. SwiftUI re-evaluates a `navigationDestination` closure on every enclosing-body re-render, so a brand-new `GroupViewModel` was built each time — discarding loaded `settlementSuggestions`/`hasLoadedBalances` — while `GroupDetailView.task` did not re-fire (stable view identity), so the fresh VM never called `load()`. The Venmo return triggered a re-render because `AppLockService.isLocked` toggles on background→foreground (ContentView's scenePhase handler). Diagnosed on physical device via a temporary on-screen state overlay: stuck flags read `exp=5 sug=0 L=0 LB=0 HLB=0 BLF=0 KNE=1` — the exact fingerprint of a freshly-`init`'d VM (expenses/KNE from cache, all flags false). **Fix:** `GroupDetailView` now owns its ViewModel in `@State` via an explicit `init(group:currentUserID:onGroupStatusChanged:)` using `State(initialValue: GroupViewModel(group:))`; both call sites pass `group:` instead of `vm: GroupViewModel(group:)`. `@State` initializes once per view identity and survives parent re-renders. Also fixes the same instability from any other re-render source (realtime updates, etc.), not just Venmo. Files: `xBill/Views/Groups/GroupDetailView.swift`, `xBill/Views/Groups/GroupListView.swift`, `xBill/Views/Main/HomeView.swift`. Verified: user confirmed on physical iPhone 16 Pro that returning from Venmo now keeps the settlement suggestions (no hang). Note: `SettleUpView.swift` remains dead code (only referenced by its own `#Preview`); the live settle-up UI is `settleUpTabEmbedded` inside `GroupDetailView`.

## Key Pattern — Own ViewModels in @State, never inline in a view builder
- Never construct an `@Observable` ViewModel inline inside a `navigationDestination` / `sheet` / other view-builder closure — SwiftUI re-runs those closures on every parent re-render and rebuilds the model, wiping its loaded state, and `.task` will not re-fire to reload it. Give the destination view an `init(...)` that stores the model via `State(initialValue:)` (or accept the model from a parent that owns it in `@State`). See the 2026-07-26 Venmo-return fix above.

## App Identity
- **Name:** xBill
- **Bundle ID:** `com.vijaygoyal.xbill`
- **Platform:** iOS 17+, iPhone only
- **Swift:** 6.0, strict concurrency enabled
- **Architecture:** SwiftUI + `@Observable` + Supabase (PostgreSQL + Auth + Realtime)
- **Project path:** `/Users/vijaygoyal/MyiOSApp/xBill`
- **Project generation:** `xcodegen generate` (from `project.yml`)
- **Architecture doc:** `ARCHITECTURE.md`
- **Design system plan:** `DESIGN.md`
- **App Store review plan:** `APPSTORE_REVIEW_PLAN.md`

## Recent Fix Log — 2026-07-15
- **UI test data purge tooling — 2026-07-16** — Added migration `039_purge_ui_test_groups.sql` with `public.purge_ui_test_groups(...)`, a guarded cleanup RPC that defaults to dry-run semantics and only targets approved UI-test prefixes for one owner. Added `scripts/purge-ui-test-groups.sh`, which resolves the owner from `XBILL_TEST_EMAIL` or ignored `xBillUITests/UITestCredentials.plist`, previews matching groups by default, and requires `--execute` before permanent deletion. Existing database cascades remove dependent `group_members`, `group_invites`, `expenses`, `splits`, and `comments`. `RELEASE_VERIFICATION.md` now documents dry-run and execute commands. Deployment: `supabase db push --linked` applied `039`; `supabase migration list --linked` confirmed local/remote match through `039`; dry-run for `xbill.uitest@example.com` returned `135` candidate groups (`69` active, `66` archived) with `deleted=false`.
- **UI test data purge execution — 2026-07-16** — Ran `scripts/purge-ui-test-groups.sh --execute` for `xbill.uitest@example.com`. The RPC deleted all `135` matching UI-test groups found by the previous dry-run (`69` active, `66` archived); dependent rows were removed by existing cascades. Verification query using `purge_ui_test_groups(p_execute => false, p_created_by => test_user_id)` returned `0` total, `0` active, and `0` archived matching groups.
- **Post-purge validation and cleanup — 2026-07-16** — Focused UI validation passed on iPhone 17 / iOS 26.5: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillUITests/RegressionUITests/testCreateGroupValidationRegression -only-testing:xBillUITests/RegressionUITests/testCoreGroupExpenseArchiveRegression` executed `2` tests with `0` failures and `0` skips. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.16_20-38-59--0400.xcresult`. Follow-up `scripts/purge-ui-test-groups.sh --execute` deleted the one archived validation group (`Regression-53536-801`); verification query returned `0` total, `0` active, and `0` archived matching UI-test groups. Release verification passed: `xcodebuild build -project xBill.xcodeproj -scheme xBill -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17'` ended with `** BUILD SUCCEEDED **`.
- **Release runbook and repo-state cleanup — 2026-07-16** — Reviewed leftover local files after the App Store/widget coverage batch. `RELEASE_VERIFICATION.md` is a real release runbook and was refreshed to the current migration baseline, 14-test `RegressionUITests` coverage list, and latest full coverage result `TestResults/Coverage/2026.07.15_22-03-05-full.xcresult` (`168` passed, `0` failed, `0` skipped). `supabase/migrations/037_groups_realtime_publication.sql` is a deployed migration documented on 2026-07-08, so it was added to source control to close the local history gap between `036` and `038`. Local generated state (`supabase/.temp/`, `.wrangler/`, Xcode `xcuserdata`) was added to ignore rules and removed from git tracking where previously tracked.
- **Block-user backend deployment — 2026-07-15** — Ran `supabase db push --linked`; remote project applied `038_block_user_rpc.sql`. Follow-up `supabase migration list` confirmed local and remote migration histories match through `038`. Direct schema dump verification was not available because `supabase db dump --schema public` requires Docker and Docker was not running locally.
- **App Store review-readiness fixes — 2026-07-15** — Implemented the four priority fixes from the App Store/security scan: updated `NSPhotoLibraryUsageDescription` to cover selected receipt/profile photos; added `XBillURLs.supportMailURL(...)`; added report actions for expense content and friend/user reports; added `FriendService.blockUser(id:)` plus `FriendDetailView` Block User confirmation; added `supabase/migrations/038_block_user_rpc.sql` so blocking removes existing friend rows and prevents future friend requests in either direction; tightened Release Supabase config validation to reject placeholder URL/key and unresolved `$(...)` build settings. Verification: sandboxed build failed before compile because CoreSimulator/package sandbox services were unavailable; escalated `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded. Deployment note: migration `038` was pushed after this code change; see the block-user backend deployment log above.
- **Stale code/documentation cleanup — 2026-07-15** — Removed unused `XBillBlackButton` from `xBill/DesignSystem/Components/XBillButtons.swift`, removed it from the design-system target component list, refreshed the current `GroupFlowUITests` / `RegressionUITests` file-map descriptions to match the stabilized 14-test suites, and corrected service-map entries for removed expense/Spotlight APIs. Verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded.
- **Full regression suite stabilization — 2026-07-15** — Removed the remaining skip-prone legacy `GroupFlowUITests` cases that depended on pre-existing archived groups and duplicated deterministic `RegressionUITests` coverage. Hardened the remaining GroupFlow archive assertion with stable active/archived row selectors, search-field filtering, and archived-section scrolling so the created group is verified in the correct list state after archiving.
- **Regression auth bootstrap hardening — 2026-07-15** — Updated `RegressionUITests.signInIfNeeded()` to retry signed-out email auth, use resilient tap fallbacks for auth/onboarding/notification prompts, and explicitly fail if the signed-in Groups surface does not load. This fixed the full-suite failure where credentials were present but the suite could still time out before recognizing the Groups surface.
- **Verification — 2026-07-15** — Targeted `GroupFlowUITests` passed on iPhone 17 / iOS 26.5 with `14` executed tests, `0` failures, and `0` skips. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.15_19-17-14--0400.xcresult`.
- **Full coverage verification — 2026-07-15** — `scripts/run-coverage.sh full` passed with structured `.xcresult` summary `161` passed tests, `0` failed tests, and `0` skipped tests. Result bundle: `TestResults/Coverage/2026.07.15_20-04-13-full.xcresult`; coverage reports: `TestResults/Coverage/2026.07.15_20-04-13-full-report.txt` and `TestResults/Coverage/2026.07.15_20-04-13-full-report.json`. Top-level coverage: `xBill.app 60.57% (17305/28569)`, `xBillTests.xctest 99.25% (1727/1740)`, `xBillUITests.xctest 78.03% (1556/1994)`, `xBillWidget.appex 0.00% (0/229)`.
- **Post-migration full regression verification — 2026-07-15** — After deploying `038_block_user_rpc.sql`, reran `scripts/run-coverage.sh full`; `.xcresult` summary reported `161` total tests, `161` passed, `0` failed, and `0` skipped. Result bundle: `TestResults/Coverage/2026.07.15_21-18-42-full.xcresult`; coverage reports: `TestResults/Coverage/2026.07.15_21-18-42-full-report.txt` and `TestResults/Coverage/2026.07.15_21-18-42-full-report.json`. Top-level coverage: `xBill.app 60.31% (17329/28734)`, `xBillTests.xctest 99.25% (1727/1740)`, `xBillUITests.xctest 78.03% (1556/1994)`, `xBillWidget.appex 0.00% (0/229)`.
- **Widget coverage enablement — 2026-07-15** — Moved widget provider/view/configuration logic from the app-extension binary into new `xBillWidgetCore.framework`, leaving `xBillWidget.appex` as the tiny `@main WidgetBundle` wrapper. Added `xBillWidgetTests/BalanceProviderTests.swift` with 7 Swift Testing checks for atomic snapshot precedence, legacy-key fallback, unavailable state, invalid numeric fail-closed behavior, refresh cadence, currency formatting, and stable widget kind. Added `scripts/run-coverage.sh widget` for fast widget-focused coverage. Verification: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillWidgetTests` passed 7 tests; `scripts/run-coverage.sh widget` passed and produced `TestResults/Coverage/2026.07.15_21-54-41-widget.xcresult`, `TestResults/Coverage/2026.07.15_21-54-41-widget-report.txt`, and `TestResults/Coverage/2026.07.15_21-54-41-widget-report.json`. Coverage: `xBillWidgetCore.framework 26.99% (61/226)`, `xBillWidgetTests.xctest 100.00% (104/104)`, and the WidgetKit wrapper `xBillWidget.appex 0.00% (0/3)`. Build verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17'` succeeded after the framework split.
- **Post-widget full regression verification — 2026-07-15** — Reran `scripts/run-coverage.sh full` after the widget-core split and coverage target additions. Structured `.xcresult` summary reported `168` total tests, `168` passed, `0` failed, and `0` skipped on iPhone 17 / iOS 26.5. Result bundle: `TestResults/Coverage/2026.07.15_22-03-05-full.xcresult`; coverage reports: `TestResults/Coverage/2026.07.15_22-03-05-full-report.txt` and `TestResults/Coverage/2026.07.15_22-03-05-full-report.json`. Top-level coverage: `xBill.app 60.33% (17335/28734)`, `xBillTests.xctest 99.25% (1727/1740)`, `xBillUITests.xctest 77.83% (1552/1994)`, `xBillWidgetCore.framework 26.99% (61/226)`, `xBillWidgetTests.xctest 100.00% (104/104)`, and the WidgetKit wrapper `xBillWidget.appex 0.00% (0/3)`.

## Recent Fix Log — 2026-07-14
- **Regression suite completeness batch — 2026-07-14** — Expanded `xBillUITests/RegressionUITests.swift` from 9 to 14 automated UI regression tests. New coverage exercises receipt scan/manual review surfaces, Add Expense split-mode controls, Manage Group invite and post-expense currency lock behavior, Settle Up plus Activity filters, and Profile QR/delete/sign-out cancellation flows. Added stable accessibility identifiers across `AddExpenseView`, `ReceiptScanView`, `ReceiptReviewView`, `GroupDetailView`, `ActivityView`, `MyQRCodeView`, and `XBillProfileCard` so tests target durable UI contracts instead of visible text/layout guesses.
- **Regression batch verification — 2026-07-14** — Targeted new-test batch passed: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillUITests/RegressionUITests/testReceiptManualReviewRegression -only-testing:xBillUITests/RegressionUITests/testSplitModeControlsRegression -only-testing:xBillUITests/RegressionUITests/testGroupSettingsInviteAndCurrencyLockRegression -only-testing:xBillUITests/RegressionUITests/testSettleUpAndActivitySurfacesRegression -only-testing:xBillUITests/RegressionUITests/testProfileQRCodeAndAccountCancelRegression` executed `5` tests with `0` failures. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.14_21-45-55--0400.xcresult`.
- **Latest verification — 2026-07-14** — Unit regression passed: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillTests` succeeded. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.14_21-53-00--0400.xcresult`. Full coverage-enabled UI regression passed: `scripts/run-coverage.sh regression-ui` executed all `14` `RegressionUITests` with `0` failures and `0` skips, producing `TestResults/Coverage/2026.07.14_21-54-04-regression-ui.xcresult`, text/JSON coverage reports, and top-level `xBill.app` coverage `59.18% (16906/28569)`.
- **UI regression credential automation — 2026-07-14** — Added `xBillUITests/Info.plist` with `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` build-setting expansion, updated `project.yml` so the UI test target uses that plist, and taught `scripts/run-coverage.sh regression-ui` to read the ignored local `xBillUITests/UITestCredentials.plist` only when environment credentials are absent. This lets coverage-enabled UI runs authenticate without committing or bundling a credentials resource. Missing credentials now fail the auth bootstrap tests instead of reporting a misleading skip. `RegressionUITests` and `GroupFlowUITests` still keep environment/test-bundle metadata lookup as the primary path, with plist-resource fallback only for older local bundles.
- **Regression UI robustness — 2026-07-14** — Broadened signed-in Groups surface detection to stable controls (`xBill.groups.createButton`, search field, active rows) and added a keyboard-focus retry helper for Create Group typing. Targeted verification passed: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillUITests/RegressionUITests/testCoreGroupExpenseArchiveRegression` succeeded with `1` executed test, `0` failures, and `0` skips. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.14_19-45-40--0400.xcresult`.
- **Verification — 2026-07-14** — Unit regression passed: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillTests` succeeded. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.14_19-48-59--0400.xcresult`. Full automated UI regression coverage also passed: `scripts/run-coverage.sh regression-ui` executed all `9` `RegressionUITests` with `0` failures and `0` skips, producing `TestResults/Coverage/2026.07.14_19-50-34-regression-ui.xcresult`, text/JSON coverage reports, and top-level `xBill.app` coverage `51.52% (14660/28453)`.

## Recent Fix Log — 2026-07-12
- **Unused component cleanup — 2026-07-12** — Removed stale `xBill/DesignSystem/Components/HomeHeader.swift`. The component had no references outside its own file after the Home/dashboard redesign and `xcodegen generate` removed it from the generated Xcode project.
- **UI-test credential source cleanup — 2026-07-12** — `project.yml` excludes the ignored local `xBillUITests/UITestCredentials.plist` from sources so credentials are not committed or bundled accidentally as a resource.
- **End-to-end test/coverage progress log — 2026-07-12** — Expanded automated regression coverage in priority order and documented the current verification flow. Key outcomes today: `RegressionUITests` became the preferred repeatable UI regression suite with 9 passing UI tests and no expected pending skips; `ViewModelCoverageTests` added 9 focused unit tests for expense/group view-model state and exposed two production bugs; `scripts/run-coverage.sh` now automates coverage-enabled runs and writes `.xcresult`, text, and JSON reports. Verification trail: focused ViewModel tests passed at `Test-xBill-2026.07.12_16-25-33--0400.xcresult`; `SplitCalculatorTests` passed at `Test-xBill-2026.07.12_16-59-14--0400.xcresult`; full `xBillTests` passed at `Test-xBill-2026.07.12_17-01-01--0400.xcresult`; coverage run passed at `TestResults/Coverage/2026.07.12_17-24-48-unit.xcresult`. Simulator verification: built app installed and launched on `DA97985A-F7CC-44F6-8281-9DD24C22B978`; latest launch PID was `73849`; screenshot `/tmp/xbill-simulator.png` confirmed xBill was rendering the welcome/sign-in screen even when the Simulator window was not visible to the user.
- **Automated coverage runner — 2026-07-12** — Added `scripts/run-coverage.sh` to make coverage runs repeatable. Default mode is `unit`, which runs `xBillTests` with `-enableCodeCoverage YES`; `full` runs the full `xBill` scheme; `regression-ui` runs `xBillUITests/RegressionUITests`. The script writes timestamped artifacts to `TestResults/Coverage/`: the `.xcresult`, a text `xccov` report, and a JSON `xccov` report, then prints only the top-level coverage summary. `TestResults/` is gitignored. Usage: `scripts/run-coverage.sh`, `scripts/run-coverage.sh full`, or `scripts/run-coverage.sh regression-ui`. Verification: `scripts/run-coverage.sh unit` passed and produced `TestResults/Coverage/2026.07.12_17-24-48-unit.xcresult` with top-level app coverage `xBill.app 6.28% (1792/28515)`.
- **ViewModel coverage expansion — 2026-07-12** — Added `xBillTests/ViewModelCoverageTests.swift` with 9 focused Swift Testing unit tests for `AddExpenseViewModel` and `GroupViewModel` local state: initial payer/currency/split defaults, amount parsing, `canSave` gating, exact split validation, equal split recompute after toggling participants, foreign-currency conversion gating, sorted expenses, active members, balances, `canChangeCurrency`, and optimistic `recordCreatedExpense` idempotency. The new tests exposed and fixed two production issues: comma decimal input such as `12,34` was previously parsed as `12`, and split recompute could leave stale amounts on excluded participants. `AddExpenseViewModel.amount` now normalizes comma decimals before POSIX parsing; `SplitCalculator` clears excluded participant amount/percentage values before equal/percentage/shares recompute. Verification: focused ViewModel tests passed at `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.12_16-25-33--0400.xcresult`; existing `SplitCalculatorTests` passed at `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.12_16-59-14--0400.xcresult`.
- **Automated UI regression suite execution — 2026-07-12** — `xBillUITests/RegressionUITests.swift` is the primary repeatable UI regression suite. It now executes all 9 regression tests with no expected pending skips: auth validation, main-tab loading, create-group validation, add-expense form validation, core group/expense/archive, expense-detail comments, archive/unarchive, profile/payment-handle validation, and friends add/search no-results. The remaining `XCTSkip` is only the credential guard for missing `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD`; unavailable app surfaces now fail instead of skip. `project.yml` excludes local ignored `xBillUITests/UITestCredentials.plist` so regenerated projects do not commit a machine-local credentials build input. Fixed the Add Expense validation cleanup path to return to the Groups route instead of trying to archive from the form-validation state. Verification on 2026-07-12: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillUITests/RegressionUITests` passed with `Executed 9 tests, with 0 failures (0 unexpected)`. Result bundle: `/Users/vijaygoyal/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Logs/Test/Test-xBill-2026.07.12_15-23-29--0400.xcresult`.

## Recent Fix Log — 2026-07-11
- **Release verification runbook — 2026-07-08** — Added `RELEASE_VERIFICATION.md` as the consolidated checklist for backend verification, reviewer seed checks, simulator smoke tests, realtime verification, account deletion, App Store privacy/review notes, assets, and known non-blocking caveats. Use it before App Store submission or after backend changes instead of reconstructing steps from scattered logs.
- **Groups realtime publication migration — 2026-07-08** — Backend verification found only `public.comments` in `supabase_realtime`, while the app subscribes to `public.groups` and `public.group_members` in `GroupService.groupChanges(userID:groupIDs:)` for Home/Groups refresh. Added migration `037_groups_realtime_publication.sql` with guarded `ALTER PUBLICATION supabase_realtime ADD TABLE` statements for `public.groups` and `public.group_members`. Deployed via `supabase db push --linked`; remote migration history now matches local through `037`, and publication verification shows `comments`, `group_members`, and `groups`.
- **Supabase keep-alive workflow hardening — 2026-06-24** — Diagnosed project pause despite GitHub Actions keep-alive. GitHub API showed `.github/workflows/supabase-keep-alive.yml` is active and ran successfully on 2026-06-09 manual dispatch plus scheduled runs on 2026-06-10, 06-13, 06-16, 06-19, and 06-22, so the issue was not that GitHub Actions "did nothing." Local DNS for `rhdhazevigbchmwzesok.supabase.co` returned no records while paused. Hardened the workflow so future runs validate that `SUPABASE_URL` points to expected project ref `rhdhazevigbchmwzesok`, fail loudly if secrets are missing or point to another project, PATCH `public.keep_alive`, then read back `id,updated_at` and fail if the row cannot be verified. This does not guarantee Supabase will count REST API traffic as free-tier activity; it makes the workflow self-verifying and exposes wrong secrets/paused endpoint failures. (`.github/workflows/supabase-keep-alive.yml`, `CLAUDE.md`)
- **VisionService Tier-1 improvements — 2026-06-15** — Three targeted fixes: (1) `preprocessForOCR` now uses the shared `Self.ciContext` (Metal GPU pipeline) instead of allocating a new `CIContext` per scan call. (2) `checkImageQuality` now also rejects images with luminance > 0.92 (`AppError.validationFailed("Image is too bright — reduce glare or avoid direct flash.")`) before the blur check, so flash-glare on thermal paper produces a meaningful error instead of a misleading "too blurry". (3) Quantity regex character class extended from `[xX@]` to `[xX@×]` so European receipt format `"2×1.99"` (U+00D7) parses qty=2 correctly. Five new tests in `xBillTests/VisionServiceTier1Tests.swift` cover all three changes; full 124-test suite passes.

## Recent Fix Log — 2026-06-14
- **App Group UserDefaults required-reason review — 2026-06-14** — Checked Apple's current required-reason API documentation. Apple defines `CA92.1` for app-only UserDefaults and `1C8F.1` for UserDefaults shared among apps/extensions/App Clips in the same App Group. Updated both `xBill/PrivacyInfo.xcprivacy` and `xBillWidget/PrivacyInfo.xcprivacy` to declare `CA92.1` plus `1C8F.1`, matching xBill's standard defaults and `group.com.vijaygoyal.xbill` App Group defaults. Updated `APPSTORE_REVIEW_PLAN.md` and `APPSTORE_PRIVACY_RECONCILIATION.md`.
- **Push notification consent semantics — 2026-06-14** — Notification category preferences now default off until iOS notification permission is granted. First grant enables expense/settlement/comment preferences once via `NotificationService.enableDefaultPreferencesAfterPermissionIfNeeded()`. Profile no longer shows enabled category toggles before OS permission; it shows an Enable action for not-determined status and a Settings action for denied status. APNs token upload is guarded by current authorization and `AuthService.deleteDeviceTokens()` removes stored tokens when permission is denied. Updated `APPSTORE_REVIEW_PLAN.md` to mark the consent-default risk fixed.
- **Contact discovery disclosure — 2026-06-14** — Added visible contact-import disclosure copy in `AddFriendView` and `InviteMembersView` before users open the contact picker. Copy states that only selected contacts are shared with xBill and selected email addresses are checked against xBill users for friend/member discovery. Updated `web/privacy/index.html` and `APPSTORE_PRIVACY_RECONCILIATION.md` to mirror the same selected-contact/no-full-address-book disclosure.
- **App Store reviewer demo account — 2026-06-14** — Added `supabase/seed_app_store_review_account.sql`, an idempotent hosted Supabase seed for `appreviewer@xbill.vijaygoyal.org`. The seed reuses the existing reviewer auth user, normalizes Supabase Auth metadata required for password sign-in, creates/updates the Tokyo Trip review group, 3 active members, 5 expenses, 15 splits, 1 IOU, 2 comments, and accepted friend rows. Reviewer password is managed outside git in Supabase Auth and App Store Connect review notes. Updated `SETUP_REVIEW_ACCOUNT.md` with the repeatable command and corrected expected balances: owed `$220`, owes `$50`, net `$170`.
- **App Store privacy reconciliation — 2026-06-14** — Added `APPSTORE_PRIVACY_RECONCILIATION.md` as the source of truth for App Store Connect privacy labels. Updated `xBill/PrivacyInfo.xcprivacy` so avatar photos and selected contacts are treated as linked data, and added linked `UserID` plus `OtherUserContactInfo` for Supabase/user identifiers and optional Venmo/PayPal handles. Updated `web/privacy/index.html` to explicitly cover internal account IDs, profile-photo uploads, OCR-only receipt images, selected contact email lookup through the backend, and payment handles. Updated `APPSTORE_REVIEW_PLAN.md` to point privacy-label work at the reconciliation artifact.
- **Balance recompute coalescing** — `GroupViewModel.computeBalances()` no longer drops recompute requests that arrive while async split fetching is already in progress; a pending recompute flag reruns balance/suggestion calculation with the latest state.
- **Settlement split safety** — `GroupViewModel.recordSettlement(_:)` now settles only whole matching splits up to the confirmed suggestion amount and fails visibly when a minimized settlement cannot be matched to current split rows, avoiding over-settling raw debt.
- **Scoped group realtime** — `GroupService.groupChanges(userID:groupIDs:)` filters `group_members` events by `user_id` and `groups` events by known group IDs; `HomeViewModel.startRealtimeUpdates()` loads group IDs before subscribing.
- **Notification diagnostics** — `ExpenseService.notifyExpenseAdded` and `notifySettlementRecorded` now log Edge Function failures with `Logger` instead of silently swallowing them.
- **Auth UI-test stability** — `EmailAuthView` exposes `xBill.emailAuth.submitButton`; `OnboardingUITests` target current placeholders/copy, retry first email-form navigation once, and avoid brittle page-header assertions for the auth form.
- **Cache test isolation** — `CacheServiceBalanceTests` clears the atomic `xbill_balance_snapshot` key plus legacy balance keys before checking default zero values.
- **Verification** — `xcodebuild test -only-testing:xBillTests` passed on iPhone 17 / iOS 26.5. `OnboardingUITests.testEmailSignUpFlow` passed after the retry fix; the preceding full onboarding run passed the other five onboarding tests and failed only that stale pre-retry test.

## Simulator
- **iPhone 17 Pro:** `DA97985A-F7CC-44F6-8281-9DD24C22B978` ← primary test device
- Build command:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -configuration Debug build
  ```
- Install + launch (simctl requires DEVELOPER_DIR — xcrun simctl won't resolve in this env):
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl install DA97985A-F7CC-44F6-8281-9DD24C22B978 <APP_PATH>
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl launch DA97985A-F7CC-44F6-8281-9DD24C22B978 com.vijaygoyal.xbill
  ```
- If simulator is Shutdown, boot it first:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/simctl boot DA97985A-F7CC-44F6-8281-9DD24C22B978
  ```
- If `simctl launch` succeeds but the Simulator window is not visible, force-open and activate the device:
  ```
  open -a Simulator --args -CurrentDeviceUDID DA97985A-F7CC-44F6-8281-9DD24C22B978
  osascript -e 'tell application "Simulator" to activate'
  ```
  Confirm state and rendering:
  ```
  xcrun simctl list devices | rg 'DA97985A|Booted'
  xcrun simctl io DA97985A-F7CC-44F6-8281-9DD24C22B978 screenshot /tmp/xbill-simulator.png
  ```
  Verified 2026-07-12: macOS reported Simulator frontmost/visible with window `iPhone 17 Pro - iOS 26.2`; screenshot `/tmp/xbill-simulator.png` showed xBill's welcome/sign-in screen. If the user still cannot see it, check Mission Control/Spaces/displays or Dock → Simulator → Show All Windows.
- **Always build, install, and launch on simulator after implementing a code change.** Do not stop at build/test success; the current app must be installed on `DA97985A-F7CC-44F6-8281-9DD24C22B978` unless the user explicitly says not to.

## Supabase
- **Project URL:** `https://rhdhazevigbchmwzesok.supabase.co`
- **Anon key:** stored in `Secrets.xcconfig` (gitignored) under `SUPABASE_URL` / `SUPABASE_ANON_KEY` build settings — NOT in `project.yml` (C1 fix)
- **Credentials injection:** `xBill/Info.plist` template uses `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` — do NOT use `GENERATE_INFOPLIST_FILE: YES` (it ignores custom build settings)
- **XcodeGen config:** `project.yml` must keep `configFiles` at the top level with `Debug: Secrets.xcconfig` and `Release: Secrets.xcconfig`. Do not nest it under `settings`; nested config files are ignored by generated Xcode projects.
- **Important xcconfig URL escaping:** In `.xcconfig`, `//` starts a comment, so write Supabase URLs as `https:/$()/rhdhazevigbchmwzesok.supabase.co`, not `https://rhdhazevigbchmwzesok.supabase.co`. If this regresses, the built app receives `SUPABASE_URL = https:` and sign-in fails with "A server with the specified hostname could not be found."
- **Auth:** Email/password + Sign In with Apple. **Email confirmation is ON** — enabled and verified 2026-08-04. Signup returns **no session**, `confirmation_sent_at` is populated, the user is bounced back to the sign-in screen with the "Check your email" banner, and tapping the emailed link opens the app via `xbill://auth/callback` and signs them in automatically. All four steps device-verified. (It was OFF until 2026-08-04; this file previously claimed ON when it was OFF, which sent someone hunting a mail-delivery problem that did not exist — if you doubt the current state, do not read it here, POST to `/auth/v1/signup` and look at whether a session comes back)
- **Push migrations:** `supabase db push` from `/Users/vijaygoyal/MyiOSApp/xBill`
- **URL scheme:** `xbill://` — registered in `Info.plist` (`CFBundleURLTypes`); Supabase dashboard Site URL + Redirect URL set to `xbill://auth/callback`
- **Resend SMTP:** configured in Supabase dashboard (Auth → SMTP) using `smtp.resend.com:465`, username `resend`, password = Resend API key
- **Edge Functions:** `supabase/functions/invite-member/index.ts` — sends group invite emails via Resend API; secrets: `RESEND_API_KEY`, `INVITE_FROM_EMAIL`

## App Store Review Notes
- Review-sensitive work is tracked in `APPSTORE_REVIEW_PLAN.md`; consult it before any submission-oriented change.
- Current known blockers/risks include account deletion retention/anonymization scope, contact-email discovery disclosures, third-party network disclosures, receipt upload/privacy-label consistency, App Group UserDefaults required-reason review, App Store Connect privacy-label reconciliation, and reviewer demo access.
- Friend invite sharing uses `XBillURLs.appInvite` (`https://xbill.vijaygoyal.org/invite`), not a placeholder App Store URL.
- Public web pages for the app's stable custom domain are hosted on Cloudflare Pages project `xbill` (domains: `xbill.pages.dev`, `xbill.vijaygoyal.org`; production branch label `main`; direct upload/no Git connection). Deploy source lives in this repo under `web/`: `web/index.html`, `web/invite/index.html`, `web/privacy/index.html`, `web/terms/index.html`.
- A separate Git-backed Cloudflare Pages web repo also exists at `/Users/vijaygoyal/Documents/xbill-web`, remote `github.com:imvijaygoyal1/xbill-web`, Pages URL `https://xbill-web.pages.dev`. It contains root-level static files: `index.html`, `invite/index.html`, `privacy/index.html`, `terms/index.html`. Latest verified fixed commit: `4d24915 Fix static pages rendering`.
- Verified 2026-05-03: `/`, `/invite`, `/privacy`, and `/terms` all return valid raw HTML; `/privacy` and `/terms` may redirect to trailing-slash URLs before `HTTP 200`.
- Do not submit until App Store Connect privacy labels, `PrivacyInfo.xcprivacy`, in-app legal links, and backend data flows have been reconciled.

## Public Web / Cloudflare Pages
- **Cloudflare Pages project:** `xbill`
- **Domains:** `https://xbill.vijaygoyal.org`, `https://xbill.pages.dev`
- **Deployment mode:** direct upload / no Git connection. Future agents cannot deploy by pushing this
  repo — but **an agent CAN deploy directly**: a wrangler OAuth login is stored under
  `~/Library/Preferences/.wrangler/config/`, and `npx wrangler@latest pages deploy web
  --project-name=xbill --branch=main --commit-dirty=true` works (verified 2026-08-22). The stored
  token had expired and refreshed itself silently. Strip `.DS_Store` from `web/` first — it
  otherwise ships as a published asset.
- **Deployable source folder:** `web/`
  - `web/index.html` → `https://xbill.vijaygoyal.org/`
  - `web/invite.html` → `https://xbill.vijaygoyal.org/invite`  ← **this is the file actually served**
  - `web/invite/index.html` → `https://xbill.vijaygoyal.org/invite/` (trailing slash only)
    ⚠️ Both exist. Cloudflare Pages strips `.html` and serves `invite.html` for `/invite`, so the
    directory index is **shadowed**. Verified 2026-08-22 by md5-matching the live response against
    both local files. Keep the two identical, or delete one — editing only `invite/index.html`
    changes nothing that a visitor sees, and a curl check against `/invite` will appear to pass.
  - `web/privacy/index.html` → `https://xbill.vijaygoyal.org/privacy`
  - `web/terms/index.html` → `https://xbill.vijaygoyal.org/terms`
- **Important:** Cloudflare direct upload replaces the deployed asset bundle. Upload the whole `web/` folder so `/privacy` and `/terms` are not accidentally removed when changing `/invite`.
- **Post-deploy verification:**
  ```
  curl -L -I https://xbill.vijaygoyal.org
  curl -L -I https://xbill.vijaygoyal.org/invite
  curl -L -I https://xbill.vijaygoyal.org/privacy
  curl -L -I https://xbill.vijaygoyal.org/terms
  curl -L https://xbill.vijaygoyal.org/privacy | head
  ```
- **Expected:** all endpoints end at `HTTP 200` and content starts with `<!DOCTYPE html>`. If output contains `Cocoa HTML Writer`, `<p class="p1">`, or `&lt;!DOCTYPE`, the page was saved as rich text and must be replaced with raw HTML.
- **Redirect rule warning:** do not add `_redirects` with `/* /index.html 200` for this static site. Cloudflare detects it as an infinite loop because `/index.html` can match the same catch-all rule again. These pages use directory `index.html` files, so Cloudflare Pages automatically serves `/invite`, `/privacy`, and `/terms` without a catch-all.
- **Git-backed web repo:** `/Users/vijaygoyal/Documents/xbill-web` is a separate repo for Cloudflare Pages Git deployment experiments. It is not the iOS app repo. Current structure is:
  - `index.html`
  - `invite/index.html`
  - `privacy/index.html`
  - `terms/index.html`
- **Git-backed verification:** `git ls-remote origin main` should show `4d24915...` or newer. `https://xbill-web.pages.dev/privacy` may first return `308 Location: /privacy/`, then `HTTP 200` when followed with `curl -L -I`; that trailing-slash redirect is normal and is not the previous infinite-loop error.
- **Routing rule history:** commit `dda384d` in `xbill-web` added `_redirects` for `/privacy` plus a catch-all rule and caused Cloudflare's "Infinite loop detected" warning/error. Commit `4d24915` removed `_redirects` and replaced Cocoa/Rich Text HTML with raw static HTML files.

## Database Schema

### Tables
| Table | Key columns |
|-------|-------------|
| `profiles` | `id uuid PK (→ auth.users)`, `email text`, `display_name text`, `avatar_url text`, `created_at` |
| `groups` | `id uuid PK`, `name text`, `emoji text`, `currency text DEFAULT 'USD'`, `created_by uuid`, `is_archived bool`, `created_at` |
| `group_members` | `group_id uuid`, `user_id uuid`, `joined_at` |
| `expenses` | `id uuid PK`, `group_id uuid`, `title text`, `amount numeric`, `currency text`, `category text`, `notes text`, `paid_by uuid`, `recurrence text DEFAULT 'none'`, `next_occurrence_date timestamptz`, `created_at` |
| `splits` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `amount numeric`, `is_settled bool` **(deprecated, permanent — never dropped, never written; see trap index)** |
| `comments` | `id uuid PK`, `expense_id uuid`, `user_id uuid`, `text text`, `created_at` |
| `group_invites` | `token text PK (default: uuid stripped of dashes)`, `group_id uuid`, `created_by uuid`, `expires_at (default: +7 days)` |
| `ious` | `id uuid PK`, `created_by uuid`, `lender_id uuid`, `borrower_id uuid`, `amount numeric`, `currency text`, `description text`, `is_settled bool`, `created_at` — CHECK: `created_by = lender_id OR created_by = borrower_id`, `lender_id != borrower_id` |

### RPC Functions
- `add_expense_with_splits(p_group_id, p_paid_by, p_amount, p_title, p_category, p_currency, p_notes, p_receipt_url, p_splits[], p_original_amount, p_original_currency, p_recurrence, p_next_occurrence_date)` — atomic expense + splits insert; `p_splits` is an array of `split_input` composite type `{user_id uuid, amount numeric}`; recurrence/next_occurrence_date are optional (default 'none'/null)

### Migrations (in order)
1. `001_initial_schema.sql` — All tables, RLS, `is_group_member()` + `is_expense_group_member()` helpers
2. `002_rpc_add_expense.sql` — `split_input` composite type + `add_expense_with_splits` RPC
3. `003_profiles_add_email.sql` — `ALTER TABLE profiles ADD COLUMN email text NOT NULL DEFAULT ''`
4. `004_profile_trigger.sql` — `handle_new_user()` trigger: auto-creates profile row on `auth.users` INSERT (runs as `SECURITY DEFINER`, bypasses RLS)
5. `005_backfill_profiles.sql` — Inserts profiles for existing auth users without profile rows
6. `006_groups_currency_member_rls.sql` — Adds `currency` to groups; fixes RLS to allow group creator to insert themselves as first member
7. `007_groups_creator_read.sql` — Fixes groups SELECT policy to allow `created_by = auth.uid()`, so the INSERT RETURNING clause succeeds before the creator is added as a member
13. `013_multi_currency.sql` — Adds `original_amount numeric` + `original_currency text` to expenses; recreates `add_expense_with_splits` RPC with new optional params
14. `014_ious.sql` — `ious` table with RLS; `lender_id`/`borrower_id`/`created_by` constraints
11. `011_expense_comments.sql` — `comments` table; RLS (group members can view/insert, author can delete); Realtime enabled
12. `012_group_invites.sql` — `group_invites` table; `join_group_via_invite(p_token)` SECURITY DEFINER RPC (validates expiry, idempotent insert into group_members, returns group_id)
15. `015_recurring_expenses.sql` — Adds `recurrence text DEFAULT 'none'` + `next_occurrence_date timestamptz` to expenses; recreates RPC with new optional params
16. `016_create_device_tokens_table.sql` — Creates `public.device_tokens (id, user_id → auth.users cascade, token, platform DEFAULT 'apns', created_at)`; RLS enabled; "Users manage own tokens" policy. (Migration 010 only added a `device_token` column to `profiles` — this is the actual table.)
17. `017_fix_user_delete_constraints.sql` — Changes `groups.created_by` and `expenses.paid_by` FK constraints from `ON DELETE RESTRICT` to `ON DELETE SET NULL` (with columns made nullable). Fixes auth user deletion being blocked when the user had created groups or paid for expenses.
18. `018_lookup_profiles_by_email.sql` — `SECURITY DEFINER` RPC `lookup_profiles_by_email`; excludes current user; granted only to `authenticated` role
19. `019_device_tokens_unique.sql` — Adds `UNIQUE (user_id, token)` constraint to `device_tokens` to prevent duplicate rows and enable safe upserts.
20. `020_friends_table.sql` — `friends` table (requester_id, addressee_id, status: pending/accepted/blocked); RLS (both parties select/delete, requester inserts, addressee updates); `send_friend_request(p_addressee_id)` idempotent RPC; `respond_to_friend_request(p_requester_id, p_accept)` RPC; `search_profiles(p_query)` RPC (ilike on email + display_name, max 20 results, excludes self).
21. `021_fix_search_profiles_no_email.sql` — (see Security section)
22. `022_expenses_update_rls.sql` — Adds `FOR UPDATE` RLS policy on `expenses` table using `is_group_member(group_id)`. Without this, all expense edits and recurring-instance `next_occurrence_date` advances silently failed for every user.
23. `023_high_rls_fixes.sql` — DELETE policy on `splits`; SELECT policy on `profiles` (group-member co-visibility); UPDATE policy on `device_tokens`.
24. `024_create_group_atomic.sql` — `create_group_with_member(p_name, p_emoji, p_currency)` SECURITY DEFINER RPC; performs group INSERT + group_members INSERT atomically; derives creator from `auth.uid()`; granted to `authenticated`.
38. `038_block_user_rpc.sql` — `block_user(p_user_id)` SECURITY DEFINER RPC; removes any existing friend/request row for the pair, inserts a blocked row, and replaces `send_friend_request` so blocked pairs cannot create new friend requests until the block row is removed. Deployed with `supabase db push --linked` on 2026-07-15; `supabase migration list` confirmed local/remote match through `038`.
39. `039_purge_ui_test_groups.sql` — `purge_ui_test_groups(p_execute, p_prefixes, p_created_by)` guarded cleanup RPC for UI-test-created groups. Defaults to dry-run style listing, restricts prefixes to known test patterns, and deletes only groups owned by the selected creator; existing cascades remove group members, invites, expenses, splits, and comments.
41. `041_settlements.sql` — the settlements ledger. Replaces `splits.is_settled` as the record of who has paid whom: a payment is its own row (`from_user_id`, `to_user_id`, `amount`, `recorded_by`) and balances are derived as *every split is debt, every settlement offsets it*. RLS: group members read; **either party** may record their own (both parties bounded to the group, `is_active` deliberately not required so someone who left can still be settled with); only the recorder may delete; **no UPDATE policy at all** — corrections are delete-then-record. Backfilled one settlement per settled non-payer split (2 rows; the other 5 settled splits are payers' own shares, balance-neutral and excluded). `splits.is_settled` is retained for one release, unread, as the re-derivation source. ⚠️ **Superseded 2026-08-29: retained *permanently*, not for one release** — shipped clients decode it and there is no force-update path. **Deployed 2026-08-01**; the balance-equivalence check returned zero rows and per-user balances were confirmed unchanged.
50. `050_is_settled_permanent.sql` — **comment-only; no data, schema-shape or policy change.** Puts the "`splits.is_settled` is deprecated and will never be dropped" rule *in the database*, as a `COMMENT ON COLUMN` and a `COMMENT ON CONSTRAINT` on `splits_settled_consistency`. It exists because the rule had only ever lived in documents you had to already know to go and read, and the column was re-proposed for deletion in six consecutive release cycles on the grounds that it is "read by nothing" — true of the logic, false of the decoding. Anyone inspecting the schema directly is now told before they act. **Deployed 2026-08-29**; `migration list --linked` reads `050 | 050 | 050`.
40. `040_notifications.sql` — server-backed in-app notification rows with recipient-scoped deduplication, unread/read RLS, and indexes for Activity and APNs badge counts. **Its RLS was audited on 2026-07-28 and is correct** (SELECT/UPDATE/DELETE all `auth.uid() = recipient_id`, UPDATE with a matching `WITH CHECK`). If a read-state write ever reports zero affected rows again, RLS is not the first suspect — check whether the id is an *expense* id from a history row instead.

## File Map

### Entry Point
- `xBill/xBillApp.swift` — `@main`, creates `AuthViewModel`, passes to `ContentView`, starts auth listener + loads current user; `.onOpenURL` dispatches on `url.host`: `"join"` → sets `authVM.pendingJoinRequest`; `"add"` → sets `AppState.shared.pendingAddFriendUserID` (QR/deep-link add-friend flow); default → passes to `supabase.auth.session(from:)` for auth redirects; `AppDelegate` conforms to `UNUserNotificationCenterDelegate`: `willPresent` returns `.banner + .sound + .badge`, `didReceive` sets `AppState.shared.pendingNotificationTarget`

### Edge Functions
- `supabase/functions/invite-member/index.ts` — Deno; calls Resend API to send group invite emails; expects `{ groupName, groupEmoji, inviterName, emails[] }`; returns `{ sent, failed[] }`
- `supabase/functions/notify-expense/index.ts` — Reads tokens from `device_tokens`; excludes sender using `callerID` (H-08: verified JWT identity, NOT body-supplied `payerId`); per-recipient badge via `batchUnreadCounts`; JWT cached 55 min; `apns-expiration: +1h`; stale token cleanup on 410/400; sandbox URL when `isDevelopment: true`; expects `{ expenseId, groupId, payerId, payerName, expenseTitle, amount, currency, isDevelopment }`
- `supabase/functions/notify-settlement/index.ts` — Expects **only** `{ settlementId, isDevelopment }`. Everything else is read from the `settlements` row itself: `group_id`, `from_user_id`, `to_user_id`, `amount`, `currency`, `recorded_by`. Nothing security-relevant comes from the request body, and no money crosses the wire as a `Double` any more. Pushes **whichever party did not record it** (`callerID === from_user_id ? to_user_id : from_user_id`) — under the settlements ledger the creditor can record a payment, so the recipient is not always the creditor; there is a `recipientIsPayer` copy branch so the debtor is not told "<their own name> paid you". H-09 preserved and strengthened: `recorded_by === callerID` is checked **before any row field is used** (403 otherwise), and `fromName` is fetched from `profiles` using the row's `from_user_id`, never `callerID`. Same JWT cache, 24h expiration, stale-token cleanup, sandbox URL logic. **Not yet deployed** — see the deploy-ordering note in the settlements-ledger spec: the migration must land before the function, and the function before any app build that can write a settlement
- `supabase/functions/notify-comment/index.ts` — Pushes all expense participants (splits + payer) except commenter; 60-char comment preview; same JWT cache, expiration, stale cleanup, sandbox URL; expects `{ expenseId, expenseTitle, groupId, groupName, commenterID, commenterName, commentText, isDevelopment }`
- `supabase/functions/notify-friend-request/index.ts` — Pushes the addressee when they receive a friend request; same JWT cache, stale-token cleanup, sandbox URL patterns; expects `{ toUserID, fromName, fromUserID, isDevelopment }`; fired fire-and-forget from `FriendService.sendFriendRequest`

### Design System
- **Current redesign direction:** xBill is migrating to a canonical Manhattan-disciplined playful fintech design system under `xBill/DesignSystem`. Before redesign work, read `DESIGN.md` and the Design System Architecture section in `ARCHITECTURE.md`.
- **Canonical target:** `xBill/DesignSystem/Tokens` for all colors, typography, spacing, radius, shadow, and gradient decisions; `xBill/DesignSystem/Components` for repeated UI; `xBill/Helpers` for greeting/balance message logic; `xBill/PreviewData` for realistic previews.
- **Migration rule:** do not add one-off styling in screens. Existing `xBill/Core/DesignSystem` and `xBill/Views/Components` APIs are legacy/compatibility surfaces during migration; wrap or alias them into the canonical system rather than creating another styling layer.
- **Required target components:** `XBillScreenBackground`, `XBillHeroCard`, `XBillBalanceCard`, `XBillActionCard`, `XBillGroupCard`, `XBillExpenseRow`, `XBillFriendRow`, `XBillNotificationRow`, `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, `XBillSettingsRow`, `XBillEmptyState`, `XBillPrimaryButton`, `XBillSecondaryButton`, `XBillTextField`, `XBillSearchBar`, `XBillSegmentedControl`, `XBillTabBar`, `XBillFloatingAddButton`, `XBillAvatarStack`, `XBillIconPickerGrid`, and `XBillQRCodeCard`.
- **Audit rule:** after UI migration, search for hardcoded `Color(hex:)`, raw `Color.white`/`Color.black`, screen-local `.font(.system(size:))`, hardcoded numeric padding/radius/shadows, and screen-local gradients.
- `xBill/DesignSystem/Tokens/AppColors.swift` — canonical adaptive light/dark palette for primary purple, soft lavender/dark navy backgrounds, surfaces, text, borders, money colors, and input colors.
- `xBill/DesignSystem/Tokens/AppTypography.swift` — canonical SF Pro font tokens: display, h1, h2, title, body, caption, amount, icon, tab label, and badge styles.
- `xBill/DesignSystem/Tokens/AppSpacing.swift` — canonical spacing scale plus `tapTarget = 44`, `controlHeight = 52`, `tabBarHeight`, and `floatingActionBottomPadding`.
- `xBill/DesignSystem/Tokens/AppRadius.swift` — canonical radius scale.
- `xBill/DesignSystem/Tokens/AppShadow.swift` — canonical adaptive card/hero/FAB shadow values plus legacy shadow compatibility helpers.
- `xBill/DesignSystem/Tokens/AppGradient.swift` — canonical hero and soft primary gradients.
- `xBill/DesignSystem/Components/` — canonical redesign components: screen background, screen headers, hero/balance/action/group/profile cards, rows, empty state, buttons, search bar, segmented control, custom tab bar, floating add button, avatar stack, icon picker, QR card, and SwiftUI-only visual assets.
- `xBill/DesignSystem/Components/XBillIllustrationKit.swift` — large reusable SwiftUI-only illustrations: `XBillSplitBillIllustration`, `XBillWalletIllustration`, `XBillEmptyStateIllustration`, `XBillFriendsIllustration`, `XBillReceiptIllustration`, and `XBillQRCodeIllustration`. Use 180–240pt visual scale for auth/empty/form/QR surfaces; no PNG/JPG assets.
- `xBill/DesignSystem/Components/XBillVisualAssets.swift` — smaller reusable visual primitives: `XBillLogoMark`, `XBillReceiptIcon`, `XBillAvatarPlaceholder`, `XBillCategoryIcon`, and `XBillQRPlaceholderFrame`.
- `xBill/DesignSystem/Components/XBillPageHeader.swift` — canonical page header with large title, optional subtitle, optional trailing action, optional back button, 24pt horizontal padding, 12pt top padding, 16pt bottom padding, and `AppColors.background`.
- `xBill/DesignSystem/Components/XBillDetailHeader.swift` — reusable modal/detail/form header wrapper for Add Friend, Add Expense, Add IOU, New Group, Edit Profile, and QR-style screens; uses `XBillPageHeader` with a 44pt back button and optional trailing action.
- `xBill/DesignSystem/Components/XBillScreenHeader.swift` — reusable main-screen header wrapper for Friends/Groups/Alerts/Profile-style screens; supports title, optional subtitle, and optional 44pt circular trailing icon action.
- `xBill/DesignSystem/Components/XBillScreenContainer.swift` — canonical screen wrapper around `XBillScreenBackground`; supports scroll/fixed modes, consistent horizontal padding, bottom padding, and sticky bottom CTA content.
- `xBill/DesignSystem/Components/XBillScrollView.swift` — canonical vertical scroll wrapper with consistent indicators, `LazyVStack`, `AppSpacing.lg` content spacing, and bottom padding for tab/sticky CTA clearance.
- `xBill/DesignSystem/Components/XBillIllustrationCard.swift` — reusable soft-surface illustration container with tokenized radius, border, background, and adaptive card shadow; used by `XBillEmptyState` and available for future empty/auth/detail art.
- `xBill/DesignSystem/Components/XBillDashboardPrimitives.swift` — reusable dashboard primitives: `XBillSectionHeader`, `XBillMetricCard`, `XBillStatusChip`, and `XBillCircularIconButton`; used by Home/Groups and intended for other metric/action dashboards.
- `xBill/DesignSystem/Components/XBillActionRow.swift` — reusable surface-card action row with leading SF Symbol container, title, optional subtitle, optional chevron, tokenized 44pt+ tap target; use for Import from Contacts, Share QR Link, Scan QR Code, and similar navigation/action rows.
- `xBill/DesignSystem/Components/XBillArchivedRow.swift` — reusable secondary-navigation row for archived groups or similar collapsible sections; icon, title, subtitle, chevron, tokenized soft surface/border, 44pt+ tap target, and VoiceOver state label.
- `xBill/DesignSystem/Components/XBillGroupCard.swift` — canonical group row/card: avatar placeholder, title/subtitle, active/archived status chip, optional avatar stack, optional semantic balance, optional chevron, tokenized surface/radius/border/shadow, and consolidated VoiceOver label.
- `xBill/DesignSystem/Components/XBillSearchBar.swift` — canonical rounded search field with tokenized surface/border/spacing/typography and placeholder accessibility label; use across Groups, Friends, Activity, Add Friend, and Group Details search surfaces.
- `xBill/DesignSystem/Components/XBillNotificationRow.swift` — reusable notification/activity card row with unread indicator, event icon, title/subtitle, timestamp, amount badge, optional chevron, tokenized surface styling, and consolidated VoiceOver label.
- `xBill/DesignSystem/Components/XBillProfilePrimitives.swift` — reusable profile/settings primitives: `XBillInfoRow`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, `XBillSettingsRow`, and `XBillSettingsChevron`; use for Profile, Settings, Edit Profile, and future form/settings surfaces.
- `xBill/DesignSystem/Components/XBillTabBar.swift` — reusable premium custom tab bar component. **Do not use it in `MainTabView` unless the product decision changes; the main app shell currently uses the native SwiftUI/iOS tab bar to avoid duplicate bottom navigation and preserve platform behavior.**
- `xBill/DesignSystem/Components/XBillButtons.swift` — canonical primary/secondary/black buttons plus compact `XBillPillButton` for Add/Pending row actions; all use tokenized colors, typography, radius, and 44pt+ tap targets.
- **Title/scroll pattern:** main tabs use in-content `XBillPageHeader` or screen-specific dashboard headers and hidden navigation chrome; modal/detail/form screens use `XBillPageHeader` with consistent back placement and sticky CTA where forms save. Avoid adding one-off `.navigationTitle` styling to redesigned screens.
- **2026-05-04 UI hardening:** top navigation chrome should use `AppColors.background`; reserve `AppColors.blackNav` for `XBillTabBar`. Sticky save actions are required for Add Expense and Add IOU. Empty Friends state must not show the Add IOU FAB because it overlaps the Add Friend CTA and there is no IOU target yet.
- **2026-05-05 Groups polish validation:** `xcodegen generate`, Debug simulator build, and unit tests passed. `GroupFlowUITests` was updated for the custom SwiftUI header/card architecture and passed with 16 executed tests, 2 expected simulator-dependent skips, and 0 failures. Clean up `com.vijaygoyal.xbill.uitests.xctrunner` after every UI test run.
- **2026-05-05 tab bar correction:** `MainTabView` must render exactly one native SwiftUI/iOS tab bar. Do not add `XBillTabBar` in a bottom `safeAreaInset` while `.tabItem` is present; that creates duplicate bottom navigation.
- **2026-05-06 Friends polish:** Friends tab uses `XBillScrollView`, `XBillScreenHeader`, `XBillEmptyState`, `XBillIllustrationCard`, `XBillSectionHeader`, and enhanced `XBillFriendRow`; pending requests, accepted friends, IOU counterparties, Add Friend sheet, Add IOU FAB, refresh, and friend-detail navigation are preserved. Validation: XcodeGen, Debug simulator build, xBillTests, UI-test-runner cleanup, simulator install, and simulator launch all succeeded.
- **2026-05-06 Add Friend polish:** Add Friend uses `XBillScreenContainer`, `XBillDetailHeader`, one `XBillIllustrationCard`, `XBillSearchBar`, `XBillActionRow`, `XBillFriendRow`, compact no-illustration `XBillEmptyState`, and `XBillPillButton`. Preserved profile search, contact import, app invite, `xbill://add/<userID>` QR-link sharing, preloaded QR deep-link suggestions, Add/Pending request state, and `onAdded`.
- **2026-05-06 Notifications polish:** Activity/Alerts now presents as `Notifications` with `XBillScreenHeader`, `XBillScreenContainer`, `XBillScrollView`, `XBillEmptyState`, `XBillSectionHeader`, and reusable `XBillNotificationRow`; unread grouping, mark-all-read, per-alert detail viewing, context-menu and swipe read/unread/delete actions, refresh/loading, empty state, notification store integration, and native tab bar behavior are preserved. Opening the tab no longer marks every alert read; badges update from per-item read state. Bell illustration appears once through the reusable empty state. Validation: `xBillTests` passed with 96 tests, UI-test-runner cleanup succeeded, and the app installed/launched on the simulator.
- **2026-05-06 Profile polish:** Profile uses a normal `ScrollView` inside `XBillScreenBackground` for stable native-tab scrolling, plus `XBillScreenHeader`, enhanced compact `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, and `XBillSettingsRow`; QR, edit profile, payment handles, notification toggles, app lock, sign out, delete account, legal links, refresh, and native tab bar behavior are preserved. Email is single-line middle-truncated and Edit is a fixed-width non-wrapping pill.
- `xBill/Helpers/GreetingHelper.swift` — time-of-day greeting helper for Home dashboard copy.
- `xBill/Helpers/BalanceMessageHelper.swift` — net-balance message helper for Home; keep output icon-free and let UI components provide SF Symbol status icons.
- `xBill/PreviewData/PreviewData.swift` — shared mock users, groups, and expenses for component previews.
- `xBill/Views/Components/XBillWordmark.swift` — `XBillWordmark` view: "xBill" in `.heavy` 22pt `brandPrimary`, tracking -0.8 + kerning -0.5; used as `.principal` toolbar item in `HomeView`
- `xBill/Core/DesignSystem/XBillTheme.swift` — `XBillTheme` enum (clay-inspired theme): `background` (warm cream `#faf9f7`), `surface` (white), `primaryBrand` (Ube 800), `accentMint` (Matcha 600), `accentCoral` (Pomegranate 400); clay multi-layer shadow; `cardRadius = 24`, `sectionRadius = 40`; `ClayCard` ViewModifier (white, 24pt corners, oat border `#dad4c8`, multi-layer shadow, optional dashed border); `ClayButtonStyle` (press: scaleEffect 0.94 + rotationEffect -3° + hard offset shadow); `SwatchSection` modifier for full-width colored sections; `View.asClayCard()` + `View.asSharpCard()` (alias) + `View.swatchSection(_:radius:)` extensions
- `xBill/Core/DesignSystem/XBillColors.swift` — `Color` extension with asset catalog tokens + clay swatch palette: `clayMatcha` (#078a52), `claySlushie` (#3bd3fd), `clayLemon` (#fbbd41), `clayUbe` (#43089f), `clayPomegranate` (#fc7981), `clayBlueberry` (#01418d), `clayCanvas` (#faf9f7), `clayOatBorder` (#dad4c8), `claySilver` (#9f9b93), plus light/dark swatch variants
- `xBill/Core/DesignSystem/XBillFonts.swift` — `Font` extension; clay weight hierarchy: 600 (headings/`.bold`/`.semibold`) / 500 (UI/`.medium`) / 400 (body/`.regular`); amounts use `.monospaced`; all others `.rounded`; `xbillUpperLabel` for uppercase labels (apply `.tracking(1.08)` at call site); **all tokens use Dynamic Type text styles** — do NOT revert to fixed `size:` integers
- `xBill/Core/DesignSystem/XBillLayout.swift` — `XBillSpacing`, `XBillRadius` (clay scale: `.sharp`=4, `.sm`=8, `.md`=12, `.card`=24, `.section`=40, `.full`=999), `XBillIcon` enums
- `xBill/Core/Extensions/HapticManager.swift` — `@MainActor enum HapticManager` with `impact(_:)`, `success()`, `error()`, `selection()` helpers

### Color Assets (Assets.xcassets)
31 named color sets with light/dark variants: `BrandPrimary`, `BrandAccent`, `BrandSurface`, `BrandDeep`, `BgPrimary`, `BgSecondary`, `BgTertiary`, `BgCard`, `TextPrimary`, `TextSecondary`, `TextTertiary`, `TextInverse`, `MoneyPositive`, `MoneyNegative`, `MoneySettled`, `MoneyTotal`, `MoneyPositiveBg`, `MoneyNegativeBg`, `MoneySettledBg`, `Separator`, `TabBarBg`, `NavBarBg`, `InputBg`, `InputBorder`, `CatFood`, `CatTravel`, `CatHome`, `CatEntertain`, `CatHealth`, `CatShopping`, `CatOther`

### Core
- `xBill/Core/AppState.swift` — `@Observable final class AppState: @unchecked Sendable` singleton (`AppState.shared`); `pendingQuickAction: QuickAction?` (.addExpense/.scanReceipt) set by AppDelegate; `spotlightTarget: SpotlightTarget?` (.group(UUID)) set by Spotlight NSUserActivity handler in xBillApp; `pendingNotificationTarget: NotificationTarget?` (.group(UUID)/.activity) set by `UNUserNotificationCenterDelegate.didReceive` on push notification tap; `pendingAddFriendUserID: UUID?` set when `xbill://add/<userID>` deep link is opened; all four consumed by MainTabView via `.task(id:)`
- `xBill/Core/SupabaseClient.swift` — `SupabaseManager.shared`; reads URL/key from `Bundle.main.infoDictionary`; Debug builds gracefully fall back to placeholder values for previews/UI-only tests; Release builds fail fast if URL/key are missing, placeholders, non-HTTPS, or unresolved `$(...)` build settings.
- `xBill/Core/AppError.swift` — `AppError` enum: `.network`, `.auth`, `.database`, `.confirmationRequired`, `.unknown`; `static func from(_ error: Error) -> AppError`
- `xBill/Core/Constants/XBillURLs.swift` — `enum XBillURLs` with `privacyPolicy`, `termsOfService`, `landingPage`, `appInvite`, `supportEmail`, and `supportMailURL(subject:body:)`; always reference these instead of hardcoding URL strings.
- `xBill/Core/Extensions.swift` — `View.errorAlert(error:)` modifier; `Decimal.formatted(currencyCode:)`; `errorAlert` shows `error.errorDescription` as title (not generic "Something went wrong"); `Color.init(hex:)` initializer for hex strings (e.g. `Color(hex: "#FF6B6B")`)
- `xBill/Core/KeychainManager.swift` — Keychain read/write helpers
- `xBill/Core/NetworkMonitor.swift` — `NWPathMonitor` wrapper

### Models
- `xBill/Models/IOU.swift` — `struct IOU` (id, createdBy, lenderID, borrowerID, amount, currency, description, isSettled, createdAt)
- `xBill/Models/Comment.swift` — `struct Comment: Codable, Identifiable, Sendable` (id, expenseID, userID, text, createdAt)
- `xBill/Models/GroupInvite.swift` — `struct GroupInvite: Codable, Identifiable, Sendable` (token, groupID, createdBy, expiresAt); `inviteURL` computed property → `xbill://join/<token>`
- `xBill/Models/Friend.swift` — `struct Friend: Codable, Identifiable, Sendable` → matches `friends` table (id, requesterID, addresseeID, status: FriendStatus, createdAt); `enum FriendStatus: String, Codable` (.pending/.accepted/.blocked)
- `xBill/Models/User.swift` — `struct User: Codable, Identifiable` → matches `profiles` table (id, email, displayName, avatarURL, createdAt)
- `xBill/Models/Group.swift` — `struct BillGroup: Codable, Identifiable` (NOT `Group` — would clash with `SwiftUI.Group`); `struct GroupMember`
- `xBill/Models/Expense.swift` — `struct Expense`, `enum Expense.Category` (with `displayName`, `systemImage`, `allCases`)
- `xBill/Models/Split.swift` — `struct Split`; `SplitStrategy` has `.equal`, `.percentage`, `.exact`, `.shares`; `SplitInput` has `shares: Int` (default 1) for weighted sharing
- `xBill/Models/Settlement.swift` — `struct Settlement: Codable, Identifiable, Sendable` → matches the `settlements` table (id, groupID, fromUserID, toUserID, amount `Decimal`, currency, recordedBy, createdAt); `SettlementInsert` payload (snake_case; `id`/`created_at` are server defaults and are never sent); `struct SettlementSuggestion: Identifiable` (fromUserID, fromName, toUserID, toName, amount, currency); `Settlement.PaymentMethod`
- `xBill/Models/Receipt.swift` — `struct Receipt` for OCR-scanned receipts; `transactionDate: Date?` added (coding key `transaction_date`) — extracted by `NSDataDetector` from OCR text and surfaced in ReceiptReviewView
- `xBill/Models/ActivityItem.swift` — legacy stub; replaced by `NotificationItem`
- `xBill/Models/NotificationItem.swift` — `struct NotificationItem: Identifiable, Sendable, Codable` (id, eventType, title, subtitle, amount, currency, category, createdAt, isRead, groupID, expenseID, **isServerBacked**); `NotificationEventType` enum (.expenseAdded, .settlementMade, .commentAdded, .friendRequest); static factories `.expense(...)`, `.settlement(...)` and `.remote(...)`. **`isServerBacked` is true only for `public.notifications` rows** — `.expense(...)` uses the *expense* id and is local history. Custom `init(from:)` decodes a missing key as `false` so pre-flag cache entries load.
- `xBill/Models/ReceiptJSON.swift` — `ParsedReceiptJSON` + `ParsedItemJSON` (Decodable); shared output schema for both FoundationModelService and heuristic parser

### Services
- `xBill/Services/ExchangeRateService.swift` — `actor`; fetches from `open.er-api.com/v6/latest/{base}` (no key needed); 1-hour in-memory cache; `convert(amount:from:to:)` and `rate(from:to:)`; `commonCurrencies` static array of 20 codes
- `xBill/Services/FriendService.swift` — `final class FriendService: Sendable`; `fetchFriends(userID:)`, `fetchPendingReceived(userID:)`, `fetchPendingSent(userID:)`, `sendFriendRequest(to:)` (calls `send_friend_request` RPC + fires `notify-friend-request` push as fire-and-forget), `acceptRequest(from:)`, `declineRequest(from:)`, `removeFriend(id:currentUserID:)`, `blockUser(id:)` (calls `block_user` RPC from migration 038), `searchProfiles(query:)` (partial ilike, uses `search_profiles` RPC from migration 020), `lookupByContactEmails([String])` (reuses migration 018 RPC), `friendshipStatus(currentUserID:otherUserID:)`, `fetchMutualGroupIDs(currentUserID:friendID:)` (parallel fetch of group_members for both users, returns intersection)
- `xBill/Services/IOUService.swift` — `fetchIOUs(userID:)` (two queries: as lender + as borrower, deduplicated), `fetchUserByEmail(_:)`, `createIOU(...)`, `settleIOU(id:)`, `settleAllIOUs(with:currentUserID:)`, `deleteIOU(id:)`
- `xBill/Services/CacheService.swift` — Prefers `UserDefaults(suiteName: "group.com.vijaygoyal.xbill")` (App Group for widget sharing), falls back to `.standard`; `nonisolated(unsafe)` static `defaults`; `saveGroups/loadGroups`, `saveExpenses/loadExpenses(groupID:)`, `saveMembers/loadMembers(groupID:)`; `saveBalance(netBalance:totalOwed:totalOwing:)` + load helpers for BalanceWidget
- `xBill/Services/AppLockService.swift` — `@Observable @MainActor` singleton; `isEnabled` via `UserDefaults`, `isLocked: Bool`, `authenticate()` via `LAContext.deviceOwnerAuthentication`, `lock()` (no-op when not enabled); `biometryType`, `lockIconName`, `unlockLabel` helpers
- `xBill/Services/CommentService.swift` — `fetchComments(expenseID:)`, `addComment(expenseID:userID:text:)`, `deleteComment(id:)`, `commentChanges(expenseID:) → AsyncStream<Void>` (Realtime subscription filtered by expense_id)
- `xBill/Services/AuthService.swift` — `signUpWithEmail`, `signInWithEmail`, `signInWithApple` (CryptoKit SHA256 nonce), `signOut`, `fetchProfile`, `currentUser()`; `sendPasswordReset` includes `redirectTo: URL(string: "xbill://reset")!` so deep link triggers `.passwordRecovery` event; `deleteAccount()` calls `delete-account` Edge Function with JWT header then signs out — throws `AppError.unauthenticated` if no session; all table refs use `"profiles"` (not `"users"`)
- `xBill/Services/GroupService.swift` — `fetchGroups(for:)` / `fetchArchivedGroups(for:)` (both two-step: `memberGroupIDs` → `groups` with server-side `is_archived` filter), `fetchMembers(groupID:)`, `createGroup(...)`, `addMember(groupId:userId:)`, `removeMember(groupId:userId:)`, `inviteMembers(emails:groupName:groupEmoji:inviterName:)`, `groupChanges(userID:) → AsyncStream<Void>` (subscribes to both `group_members` + `groups` tables), `createInvite(groupID:createdBy:)`, `fetchInvite(token:)`, `joinGroupViaInvite(token:) → UUID`
- `xBill/Services/ExpenseService.swift` — `fetchExpenses(groupID:)`, `fetchExpense(id:)`, `fetchSplits(expenseID:)`, `createExpense(...)` (uses `add_expense_with_splits` RPC — atomic; receipt images are OCR-only and not uploaded), `fetchDueRecurringExpenses(groupID:)`, `createRecurringInstance(...)`, `updateExpense(_:)`, `deleteExpense(id:)`. **No `settleSplit`** — it was deleted with the settlements ledger; it wrote `splits.is_settled`, which nothing reads, so it returned HTTP 200 and moved no balance. Record a payment via `SettlementService.recordSettlement`
- `xBill/Services/SplitCalculator.swift` — `splitEqually`, `splitByPercentage`, `splitByShares`, `validateExact`, `netBalances(expenses:splits:settlements:)`, `settlementSuggestions(expenses:splits:settlements:names:currency:)`, `minimizeTransactions(balances:names:currency:)`. `splitByShares` distributes proportionally to each `SplitInput.shares` value with rounding absorbed by first participant. **`netBalances` no longer consults `is_settled`**: every non-payer split is debt and every settlement offsets it (payer's own split is still skipped). Used by both `GroupViewModel` and `HomeViewModel` for consistent balance computation.
- `xBill/Services/SettlementService.swift` — `fetchSettlements(groupID:)` (newest-first), `recordSettlement(groupID:fromUserID:toUserID:amount:currency:recordedBy:)`, `deleteSettlement(id:)` (through `SupabaseWrite.requireAffected`, so an RLS miss throws instead of reporting success). Declares its own conformance to `SettlementDataProviding`
- `xBill/Services/SpotlightService.swift` — `enum SpotlightService`; `indexGroups(_:)` / `removeGroup(id:)` index only group names/emoji/currency via CoreSpotlight; `removeAllExpenses()` deletes previously indexed expense items by domain so financial titles are not exposed through Spotlight.
- `xBill/Services/PaymentLinkService.swift` — Venmo deep-link URL generation
- `xBill/Services/VisionService.swift` — Two-tier receipt parsing + 7 quality improvements (Gaps 1–6 + 7). Public API: `scanReceipt(from:)` and `scanMultiPage(from:[UIImage])`. Returns `ScanResult(receipt:confidence:tier:validationWarning:suggestedCategory:)`. **Gap 1 — Pre-Processing**: `preprocessForOCR` pipeline: resize to 1200px → `CIPhotoEffectNoir` grayscale → `CIColorControls` contrast 1.4×/brightness +0.05 → `CISharpenLuminance` 0.4; called in `recognizeText` before OCR; each step has graceful fallback. **Gap 2 — Quality Gate**: `checkImageQuality` throws for too-dark, too-blurry, or no-text images. **Gap 3 — OCR Config**: `customWords` (27 terms), `minimumTextHeight=0.015`, device `recognitionLanguages`, `topCandidates(3)` — alternates stored in `OCRLine.alternates: [String]` for Gap 7. **Gap 4 — Date**: `NSDataDetector` → `Receipt.transactionDate`. **Gap 5 — NL**: `detectLanguage` + `suggestCategory`. **Gap 6 — Multi-Page**: Y-offset stacking, proportional threshold. **Gap 7 — Constraint-Solving**: `private struct ParsedItem` tracks alternate prices per item; `parseWithHeuristics` returns `(receipt:Receipt, candidates:[ParsedItem])`; `reconcile(candidates:total:tax:tip:)` tries alternate OCR prices when |delta| ≤ $2.00; on success updates items and clears validation warning; only attempted on Tier 2 (Tier 1 handles this via LLM).
- `xBill/Services/FoundationModelService.swift` — `@available(iOS 26.0, *)`. `parseReceipt(ocrText:language:)` — `language` is BCP-47 tag from `NLLanguageRecognizer` (e.g. "fr", "de"), injected into the system prompt for non-English receipt accuracy. `@Generable` schema adds `transactionDate: String?` ("YYYY-MM-DD" format); re-parsed by `VisionService.extractTransactionDate`. Minimum quality check: rejects OCR text with < 3 lines. Returns `ParsedReceiptJSON` (now includes `transactionDate: String?`). Falls through to heuristics on failure.
- `xBill/Services/NotificationStore.swift` — local-first notification persistence; `merge([NotificationItem])` deduplicates by id, caps at 100 items, and preserves existing read state; per-item APIs: `markRead(id:)`, `markUnread(id:)`, `delete(id:)`; `markAllRead()` marks stored items read and updates `lastViewedAt()` for backward compatibility; `unreadCount()` returns unread stored items; **pending read intent** (`setPendingReadState`/`pendingReadStates`/`clearPendingReadState`/`applyingPendingReadStates`) survives a refresh mid-write; **history dismissals** (`dismissHistoryItem(id:userID:)`/`dismissedHistoryIDs(userID:)`, capped at 200, user-scoped) make a deleted history row stay deleted; all keys are user-scoped; uses `CacheService.defaults` (App Group UserDefaults); `clearAll()` for test teardown
- `xBill/Services/RemoteNotificationService.swift` — fetches authoritative notification rows and updates read/unread/delete state through RLS-protected Supabase queries. Every mutating call is acknowledged by **affected-row count** via `acknowledgeAffectedRows(_:id:)` → `RemoteNotificationError.rowNotFound`; never `.single()`. `NotificationReadStatePayload` encodes an explicit JSON `null` to clear `read_at` and an explicit **UTC** ISO-8601 instant to set it.
- `xBill/Services/ActivityService.swift` — returns `[NotificationItem]`; reads server-backed notifications first, supplements them with historical expense activity, and falls back to expense activity when the remote table is unavailable. Also defines `ActivityReconciler.reconcile(remoteItems:legacyItems:storedItems:pendingReadStates:dismissedHistoryIDs:)` — a **pure** function that preserves a history row's stored read state, defaults only *unseen* history to read (so pre-040 history never inflates the badge), filters dismissed history rows, and applies pending intent over a stale server response — and the `ActivityReadWriting` protocol the view model depends on.
- `xBill/Services/NotificationService.swift` — Local push notifications; settlement reminders only (`scheduleExpenseAddedNotification` removed — was firing locally for the person who added the expense, which is useless)
- `xBill/Services/ExpenseService.swift` — `notifyExpenseAdded(...)` and `notifySettlementRecorded(...)` both invoke Edge Functions as fire-and-forget `Task`s; both gated on `UserDefaults prefPush*` prefs
- `xBill/Services/CommentService.swift` — `addComment(expenseID:userID:text:expenseTitle:groupID:groupName:commenterName:)` fires `notify-comment` Edge Function after insert; gated on `NotificationService.commentPreferenceKey`
- `xBill/Views/Main/NotificationPermissionView.swift` — Pre-prompt sheet explaining push value before triggering OS dialog; "Allow Notifications" / "Not Now"; shown once via `@AppStorage("hasPromptedNotificationPermission")`
- `xBill/Services/ExportService.swift` — `@MainActor`; `generateCSV(group:expenses:memberNames:) -> Data`; `generatePDF(group:expenses:memberNames:balances:) -> Data` (PDFKit A4 report with summary, balances, expense table); `writeTemp(data:filename:) throws -> URL` for share sheet

### ViewModels
- `xBill/ViewModels/AuthViewModel.swift` — `@Observable @MainActor`; `currentUser: User?`, `confirmationEmailSent: Bool`, `isInPasswordRecovery: Bool`, `isLoading`, `error`, `pendingJoinRequest: InviteJoinRequest?`; `startListeningToAuthChanges()` handles `.passwordRecovery` event; `handlePasswordReset(newPassword:)` calls `supabase.auth.update`. `InviteJoinRequest` is a top-level `Identifiable` struct with `token: String`
- `xBill/ViewModels/HomeViewModel.swift` — loads groups, computes net balance + `recentExpenses: [RecentEntry]` (top 10 across all groups, members co-fetched); `RecentEntry` is `{ expense, members }` identifiable struct; `archivedGroups: [BillGroup]`; `crossGroupSuggestions: [SettlementSuggestion]` (cross-group debt, filtered to current user); `groupMemberCounts: [UUID: Int]` (member count per group, populated in `computeBalances`); `groupNetBalances: [UUID: Decimal]` (net balance per group for the current user, positive = owed to you); `unarchiveGroup(_:)` unarchives and refreshes both lists; `groupsNavigationPath: NavigationPath`; `createSampleData(userID:)` creates demo group + 3 expenses; `fullBalancesInGroup` returns `GroupBalanceData` (groupID, owed, owing, netBalance, memberCount, entries, currency, balances, names) — results cached in `groupBalancesCache` per refresh cycle; `computeBalances` clears cache, merges per-currency balance maps, calls `minimizeTransactions`, saves to CacheService, calls `WidgetCenter.shared.reloadAllTimelines()`; `startRealtimeUpdates()` is now synchronous, stores a cancellable `realtimeTask: Task<Void, Never>?` and cancel-and-restarts on each call; H-12: `loadAll()` catch block now calls `computeBalances` after cache restore so offline balances are correct
- `xBill/ViewModels/GroupViewModel.swift` — loads members + expenses, computes balances + settlement suggestions, `recordSettlement()`; `archiveGroup()` / `unarchiveGroup()` set `isArchived` via `GroupService.updateGroup` and update `CacheService` immediately (remove/append to active-groups cache); `createDueRecurringInstances(currentUserID:)` fetches due recurring expenses, creates new instances per-pair in isolated do/catch (CRIT-01 fix: failures on one expense don't abort the batch; template advance logged-but-not-thrown on failure), clears old `next_occurrence_date`; `addMember`/`removeMember` no longer manage `isLoading` directly (GVM-02: `load()` already manages it); CRIT-10: `load()` catch block unconditionally reads both cache arrays (not gated on isEmpty) and applies them if non-empty
- `xBill/ViewModels/AddExpenseViewModel.swift` — split calculation; `expenseCurrency` (defaults to group currency); `convertedAmount`/`exchangeRate` computed via `ExchangeRateService.shared`; `updateConversion()` called on currency/amount change; `finalAmount` = converted or raw; `save()` passes `originalAmount`/`originalCurrency` when foreign currency used; H-15: `save()` now has two `guard canSave, let payerID` checks — one fast-path at the top and one correctness guard after `await updateConversion()` to prevent stale form state from being saved
- `xBill/ViewModels/ProfileViewModel.swift` — profile editing; `loadStats(userID:)` fetches groups + expenses concurrently via `withTaskGroup` to compute `totalGroupsCount`, `totalExpensesCount`, `lifetimePaid`; `saveProfile(avatarImage:)`: H-17: validates+trims `displayName` before any network call (shows "Name required" alert if empty); H-16: uploads avatar first, then does ONE `updateProfile` write with final URL (eliminates double-write race where step 2 failure leaves DB with old URL from step 1)
- `xBill/ViewModels/ActivityViewModel.swift` — `items: [NotificationItem]`; `unreadCount: Int` synced from the server-backed local cache; read/unread/delete/mark-all actions update local state, then the remote row **only when `item.isServerBacked`** — a history row is local-only (no request, no pending intent, no failure alert). `init(service:store:currentUserIDProvider:)` takes defaulted injection seams so read-state behaviour is testable without a live PostgREST endpoint. A generation counter per id makes the newest toggle authoritative; rollback on a failed write is scoped to the single affected row.
- `xBill/ViewModels/ReceiptViewModel.swift` — receipt scan + review flow; `capturedPages: [UIImage]` (all scanned pages); `capturedImage: UIImage?` computed from `capturedPages.first`; `suggestedCategory: Expense.Category?` set from `ScanResult`; `scan(pages:)` calls `vision.scanMultiPage(from:)` (multi-page aware); `merchantName`, `totalAmount`, `tipAmount: String` mutable vars; `toggleAssignAll(to:)`, `updateUnitPrice`, `hasUnassignedItems`, `total(for:)`; **`startManually(members:)`** — creates blank Receipt, clears scan state + suggestedCategory, sets members

### Widget Extension
- `xBillWidget/xBillWidgetBundle.swift` — tiny `@main WidgetBundle` wrapper that imports `xBillWidgetCore` and exposes `xBillBalanceWidget`
- `xBillWidgetCore/xBillBalanceWidget.swift` — linkable framework implementation for the `StaticConfiguration` widget; `BalanceProvider` reads from shared `UserDefaults` (App Group) using atomic snapshot first and legacy keys as fallback; `BalanceEntry` has date/netBalance/totalOwed/totalOwing; `BalanceWidgetView` shows owed/owing in a simple layout; `.systemSmall`+`.systemMedium` families; refreshes every 30 minutes
- `xBillWidgetTests/BalanceProviderTests.swift` — widget-core coverage tests for snapshot/legacy loading, unavailable and invalid-data states, timeline cadence, formatting, and widget metadata
- `xBillWidget/Info.plist` — explicit plist with `NSExtensionPointIdentifier = com.apple.widgetkit-extension` (required for WidgetKit app extensions)
- `xBillWidget/xBillWidget.entitlements` — App Group entitlement `group.com.vijaygoyal.xbill`

### Views — App Lock
- `xBill/Views/AppLockView.swift` — full-screen overlay shown when `AppLockService.shared.isLocked`; brandPrimary background; biometry icon + wordmark + unlock button; `task` auto-triggers authentication on appear; uses `ClayButtonStyle`

### Views — Auth
- `xBill/Views/Auth/AuthView.swift` — adaptive `AppColors.background`; compact `XBillHeroCard` brand header; rounded auth card with Sign In with Apple and `XBillPrimaryButton` email continuation; legal links are split into accessible controls so they do not overflow on small widths; Terms presents `TermsOfServiceView()` sheet and Privacy opens `.safariSheet` to `XBillURLs.privacyPolicy`.
- `xBill/Views/Auth/EmailAuthView.swift` — rounded email/password card with explanatory heading, `XBillTextField` fields, `XBillPrimaryButton` submit with loading/disabled state, create-account/sign-in toggle, and "Forgot password?" sheet with `prefillEmail: vm.email`.
- `xBill/Views/Auth/ForgotPasswordView.swift` — two-step sheet (form → success); calls `AuthService.shared.sendPasswordReset`; inline error display; 30s resend cooldown via `Task`-based sleep loop (no `Timer`); shows success state even for "user not found" errors (account enumeration prevention); `HapticManager.success()/error()` feedback; private `HintRow` and `ResendButtonView` subviews
- `xBill/Views/Auth/ResetPasswordView.swift` — shown when app opened from password reset link; new + confirm password fields; calls `authVM.handlePasswordReset(newPassword:)`

### Views — Legal
- `xBill/Views/Legal/TermsOfServiceView.swift` — in-app ToS screen; native `NavigationStack` + `ScrollView`; header card with `brandPrimary` background; 10 `TOSSection` cards (numbered circle + title + body text); `XBillWordmark` in `.principal` toolbar; "Done" dismiss button; presented as `.sheet` (`.large` detent, drag indicator) from `AuthView` and `ProfileView`; file-private `TOSSection` struct takes `number`, `title`, `content: String` directly

### Views — Onboarding
- `xBill/Views/Onboarding/OnboardingView.swift` — 4-page swipeable onboarding (TabView .page style); shown once after first sign-in via `@AppStorage("hasCompletedOnboarding")` flag in `ContentView`; pages: Welcome, Groups, Receipts, Balances; "Skip" on pages 1–3, "Get Started" on page 4 — both set `hasCompletedOnboarding = true`

### Views — Main
- `xBill/Views/Main/ContentView.swift` — animated transition priority: `ResetPasswordView` → (logged in) `OnboardingView` (first launch only) or `MainTabView` → `AuthView`; `@AppStorage("hasCompletedOnboarding")` controls onboarding gate
- `xBill/Views/Main/NotificationPermissionView.swift` — Pre-prompt sheet (see Services section above)
- `xBill/Views/Main/MainTabView.swift` — 5 tabs: Home / Groups / Friends / Activity / Profile; Friends tab passes `homeVM.currentUser?.id` + `homeVM.groups`; four `.task(id:)` handlers: pendingQuickAction (groups tab + QuickAddExpenseSheet), spotlightTarget (group navigation), pendingNotificationTarget (group navigation), pendingAddFriendUserID (Friends tab + AddFriendView with preloaded user from `FriendService.searchProfiles`); `addFriendPreloadedUser: User?` + `showAddFriendFromQR: Bool` state for QR deep-link sheet
- `xBill/Views/Main/HomeView.swift` — dashboard screen rendered after sign-in; no greeting header; `BalanceHeroCard` (no arrow icon), icon-free `XBillMetricCard` summary cards, `XBillSectionHeader` with + button, vertical `XBillGroupCard` list (shows per-group member count and net balance), and Recent Expenses/Cross-Group sections. Invite Friends card hidden when user has groups. Create-group action via the My Groups section + button. `homeGroupCard(_:)` private helper reads `vm.groupNetBalances` and `vm.groupMemberCounts` for row data.
- `xBill/Views/Main/ActivityView.swift` — Alerts tab content presented as "Notifications"; uses reusable `XBillScreenHeader`, `XBillScreenContainer`, `XBillScrollView`, `XBillEmptyState`, `XBillSectionHeader`, and `XBillNotificationRow`; sections grouped by date; unread indicator per row; row tap marks that item read and opens `NotificationDetailSheet`; context menu and leading swipe toggle read/unread; context menu and trailing swipe delete; "Mark All Read" header action when `vm.hasUnread`; `onAppear` refreshes badge count without marking all alerts read; preserves amount badges, event icons, notification store integration, and full accessibility labels.

### Views — Groups
- `xBill/Views/Groups/CreateGroupView.swift` — 4×5 emoji grid picker (20 emojis), currency picker (uses `ExchangeRateService.commonCurrencies`), invite email field (wired: sends invite via `GroupService.inviteMembers` after group creation if non-empty, non-fatal error)
- `xBill/Views/Groups/GroupListView.swift` — groups list tab; shares `HomeViewModel`; tokenized Groups header with `XBillCircularIconButton`, `XBillSearchBar`, `XBillSectionHeader`, `XBillGroupCard`, and collapsible `XBillArchivedRow`; active groups section + archived section; archived rows expose context-menu "Unarchive"; navigates to `GroupDetailView` (guarded: only navigates when `vm.currentUser?.id` is non-nil; passes `onGroupStatusChanged` callback that calls `vm.refresh()` + `vm.loadArchivedGroups()`); `onCreated` callback appends new group directly to `vm.groups` and calls `SpotlightService.indexGroups` (no full network refresh); loads archived groups on `.task`. Active group rows show `showsStatusChip: false` (no "Active" badge), member count + currency as subtitle, and per-group net balance via `vm.groupNetBalances`.
- `xBill/Views/Groups/GroupDetailView.swift` — takes `onGroupStatusChanged: (() async -> Void)?` callback (called after archive or unarchive, triggers `HomeViewModel` refresh before dismiss); segmented Picker (Expenses/Balances/Settle Up) tabs; `AmountBadge` in balances; `AmountBadge(.total)` on expense rows; FAB only on Expenses tab; Settle Up embedded; toolbar menu has: Add Expense, Stats, Export (CSV/PDF via `ExportService`+`ShareSheetView`), Invite via Email, Invite via Link (QR), **Archive Group** (shown only when `!vm.group.isArchived`) or **Unarchive Group** (shown when `vm.group.isArchived`); archive confirmation shows unsettled-balance count if `!vm.settlementSuggestions.isEmpty`; `.task` also calls `vm.createDueRecurringInstances(currentUserID:)`; `.searchable` on Group to add search bar; horizontal `ExpenseFilterChip` strip for category filter on Expenses tab; `filteredExpenses` computed property filters `vm.sortedExpenses` by `searchText` and `filterCategory`
- `xBill/Views/Groups/QuickAddExpenseSheet.swift` — sheet for "Add Expense"/"Scan Receipt" quick actions; shows list of active groups; fetches members on group selection; presents `AddExpenseView` with optional `startWithScan: true`
- `xBill/Views/Groups/GroupInviteView.swift` — shows QR code (CoreImage `CIFilter.qrCodeGenerator`) + `ShareLink` for `xbill://join/<token>`; generates a new invite on appear; refresh button in toolbar
- `xBill/Views/Groups/JoinGroupView.swift` — confirms and handles group join via invite token; fetches group name, shows confirmation card, calls `joinGroupViaInvite` RPC on confirm
- `xBill/Views/Groups/SettlementSuggestionRow.swift` — one settle-up row. Names the parties in text (a row once read "A → A $7.00" when two members shared an initial), gates Record Payment on `isParty` to match migration 041's INSERT policy, captions the non-party case, and keeps its accessibility identifier on the **header** — a container-level one overwrites every child's (UIT-01). Reports intent through closures; the payment-handoff state machine stays in `GroupDetailView`
- `xBill/Views/Groups/GroupSettingsView.swift` — group name/icon/currency editing, invites, member list. Extracted from `GroupDetailView`
- `xBill/Views/Groups/ExpenseFilterChip.swift`, `xBill/Views/Groups/ExportShareItem.swift` — extracted from `GroupDetailView`
- `xBill/Views/Groups/RecordPaymentSheet.swift` — Record-a-payment sheet. Either party may record; amount parsing is locale-safe and rejects zero/negative; produces no `Double`
- `xBill/Views/Groups/PaymentHistorySection.swift` — Payment history list on the group's Settle Up tab. Swipe-to-delete is gated on `recordedBy == currentUserID`, matching the DELETE policy exactly; there is no edit affordance anywhere because there is no UPDATE policy
- `xBill/Views/Groups/SettleUpView.swift` — settlement suggestions with Venmo link + Mark Settled button
- `xBill/Views/Groups/InviteMembersView.swift` — email invite list; "Import from Contacts" button opens `CNContactPickerViewController` (no upfront permission needed); selected emails added to pending list; `lookupXBillUsers` checks DB via `GroupService.lookupProfilesByEmail`; "On xBill" badge on matching emails; calls `GroupService.inviteMembers` → `invite-member` Edge Function

### Views — Friends
- `xBill/Views/Friends/FriendsView.swift` — Friends tab; accepts `currentUserID` + `allGroups: [BillGroup]` (from `homeVM.groups`); loads accepted friends from `FriendService` + IOUs from `IOUService` in parallel; tokenized `XBillScrollView` layout with `XBillScreenHeader`; sections: Requests (inbound pending, inline accept/decline), Outstanding (friends with unsettled IOUs), All Clear (settled/no-IOU friends); header `person.badge.plus` button → `AddFriendView`; FAB → `AddIOUView`; empty state uses `XBillEmptyState` and one illustration card; contact suggestions use reusable friend rows; `FriendDetailView` receives `allGroups` for mutual-group display
- `xBill/Views/Friends/FriendDetailView.swift` — (defined in FriendsView.swift) outstanding + settled IOU sections; "Settle All" button; "Shared Groups" section showing mutual groups (loaded via `FriendService.fetchMutualGroupIDs` on `.task`); friend actions menu supports Add IOU, Report User via support mail, and Block User via `FriendService.blockUser`; accepts `allGroups: [BillGroup]` default-empty parameter
- `xBill/Views/Friends/AddFriendView.swift` — discovery-only sheet; tokenized `XBillScreenContainer` layout with `XBillDetailHeader`, one friends illustration card, `XBillSearchBar(accessibilityLabel: "Search friends")`, `XBillActionRow` actions for Import from Contacts and Share QR Link (`xbill://add/<currentUserID>`), partial search → debounced 350ms → `FriendService.searchProfiles`, compact no-results state plus app invite `ShareLink`, contact suggestions from `lookupByContactEmails`, and `XBillFriendRow` rows with `XBillPillButton` Add/Pending controls; accepts optional `preloadedUser` for QR deep-link pre-population
- `xBill/Views/Friends/AddIOUView.swift` — now shows friend picker from `FriendService.fetchFriends()` as primary selection; "Add by email" is secondary fallback; keeps email search for non-friends; `preselectedFriend` and `preselectedFriendID` params unchanged
- `xBill/Views/Expenses/AddExpenseView.swift` — `bgSecondary` sheet; hero amount `TextField`; currency picker `Menu` next to currency symbol; conversion preview when foreign currency; "Repeat" section with `Expense.Recurrence` picker (Does not repeat / Weekly / Monthly / Yearly); `ExchangeRateService.commonCurrencies` populates the currency picker
- `xBill/Views/Expenses/ExpenseDetailView.swift` — expense detail with split breakdown + Comments section (realtime); `currentUserID: UUID` required; comment input bar via `safeAreaInset(edge: .bottom)`; overflow menu includes Report Content via support mail plus edit/delete actions.
- `xBill/Views/Expenses/ReceiptScanView.swift` — accepts `members: [User]` + `onConfirmed: ([SplitInput]) -> Void`; `DocumentCameraView` now binds to `$vm.capturedPages: [UIImage]` and captures ALL pages (`0..<scan.pageCount`) for multi-page receipt support; photo library sets `vm.capturedPages = [image]`; `onChange(of: vm.capturedPages)` triggers `vm.scan(pages:)`; "Scan Again" clears `vm.capturedPages`; multi-page badge shown when `capturedPages.count > 1`; quality errors (Gap 2) surface via existing `.errorAlert(item:)` binding
- `xBill/Views/Expenses/ReceiptReviewView.swift` — item review, member chip assignment, per-person totals; confidence header now includes suggested category chip (Gap 5) from `vm.suggestedCategory`; Extras section shows "Receipt Date" row (Gap 4) from `vm.scannedReceipt?.transactionDate` formatted with `.date` style; merchant name editable via `XBillTextField`; tip and total editable; tax read-only; "Use These Splits" calls `onConfirmed`; file-private `ItemRow` with inline price + stepper + member chips

### Views — Profile
- `xBill/Views/Profile/ProfileView.swift` — Profile tab; tokenized `XBillScreenContainer` layout with `XBillScreenHeader`, enhanced `XBillProfileCard`, `XBillStatsCard`, `XBillFormSection`, `XBillPaymentHandleRow`, and `XBillSettingsRow`; preserves `showMyQR` sheet presenting `MyQRCodeView`, edit profile sheet/avatar picker, payment handle text fields, notification toggles, app lock toggle, sign out, delete account, ToS/Privacy links, refresh, and profile stats.
- `xBill/Views/Profile/MyQRCodeView.swift` — displays QR code for `xbill://add/<userID>` deep link using `CIFilter.qrCodeGenerator` (same pattern as `GroupInviteView`); `ShareLink` for the URL; `.interpolation(.none)` on the QR image to prevent blurring

### Views — Components
- **Migration note:** these components are the current reusable surface, but the redesign target is `xBill/DesignSystem/Components`. When touching these files for redesign work, either move the component, create a canonical wrapper, or document a temporary compatibility alias.
- `xBill/Views/Components/AvatarView.swift` — circular avatar; remote images via `AsyncImage`; fallback delegates to `XBillAvatarPlaceholder` for tokenized gradient avatar visuals.
- `xBill/Views/Components/BalanceBadge.swift` — green (owed to you) / red (you owe) badge (legacy; prefer `AmountBadge` for new screens)
- `xBill/Views/Components/AmountBadge.swift` — colored pill badge with `AmountDirection` (.positive/.negative/.settled/.total); uses design system money tokens
- `xBill/Views/Components/BalanceHeroCard.swift` — balance summary card: state label (uppercase tracked), amount (monospaced), subtitle. No directional arrow icon. `VStack` layout only; `label`, `amount`, `subtitle`, `isPositive` params unchanged.
- `xBill/Views/Components/XBillCard.swift` — generic card wrapper; delegates to `SharpCard` modifier (18pt corners, hairline border, drop shadow)
- `xBill/Views/Components/XBillButton.swift` — design-system button with `.primary/.secondary/.ghost/.destructive` styles; fires `HapticManager.impact` on tap
- `xBill/Views/Components/XBillTextField.swift` — `inputBg`/`inputBorder` styled text field; focus-animated border turns `brandPrimary`
- `xBill/Views/Components/CategoryIconView.swift` — compatibility wrapper around `XBillCategoryIcon`; `Expense.Category` still exposes `.emoji` and `.categoryBackground` for legacy labels.
- `xBill/Views/Components/OfflineBanner.swift` — orange banner shown via `safeAreaInset(edge:.top)` in HomeView and GroupDetailView when `NetworkMonitor.shared.isConnected == false`
- `xBill/Views/Components/ContactPickerView.swift` — `ContactPickerRepresentable: UIViewControllerRepresentable` wrapping `CNContactPickerViewController`; shared component used by both `InviteMembersView` and `AddFriendView`; `onPickedEmails: ([String]) -> Void` callback; handles both single and multi-contact selection
- `xBill/Views/Components/FABButton.swift` — 56pt `brandPrimary` circle FAB with shadow and haptic
- `xBill/Views/Components/GroupChipView.swift` — Home dashboard group card for horizontal group scroll; shows avatar placeholder, currency chip, active/archived status, and created date with tokenized surfaces/borders.
- `xBill/Views/Components/ExpenseRowView.swift` — expense list row; `showAmountBadge: Bool = false` — when true shows `AmountBadge(.total)` instead of plain amount text
- `xBill/Views/Components/EmptyStateView.swift` — wraps `ContentUnavailableView` (iOS 17+); `(icon:title:message:actionLabel?:action?)` API unchanged; action button uses `.borderedProminent` style; two variants compiled at runtime: with/without action
- `xBill/Views/Components/LoadingOverlay.swift` — centered spinner with message
- `xBill/Views/Components/SplitSlider.swift` — percentage split slider
- `xBill/Views/Components/SafariView.swift` — `UIViewControllerRepresentable` wrapping `SFSafariViewController`; branded with `UIColor(Color.brandPrimary)` bar tint + white controls; `View.safariSheet(isPresented:url:)` extension for presenting in-app; used for privacy policy links — do NOT use `openURL` env action for policy links
- `xBill/Views/Components/ShareSheetView.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController`; accepts a `URL` to share; used by `GroupDetailView` for CSV/PDF export

### Deployment Scripts
- `scripts/preflight-settlements-backfill.sql` — **Run this before `supabase db push`.** Read-only, references `public.settlements` nowhere, simulates the backfill in a CTE. Expect zero rows. This is the real gate; `verify-settlements-backfill.sql` can only run after the point of no return
- `scripts/verify-settlements-backfill.sql` — Post-migration confirmation. Valid **only** in the window immediately after the backfill: `old_balances` still reads `is_settled`, so once a real payment is recorded it reports drift for every genuine settlement

### Tests
- `xBillTests/SplitCalculatorTests.swift` — 17 tests: equal split (even/rounding/excluded/single), percentage (proportional/rounding), exact validation (pass/fail), net balances, single payer, circular debt, partially settled, two people, floating point precision (÷3), minimize transactions (basic/all-settled). Fixed 2026-04-29: added `recurrence: .none` to all `Expense` inits; removed stale `updatedAt:` arg; fixed `\.amount` key-path inference in `#expect`.
- `xBillTests/P2FeatureTests.swift` — 18 tests across 5 suites: CrossGroupDebt (balance merging, currency separation, minimisation), AppLock (lock/no-op state transitions, MainActor), ManualReceipt (startManually creates blank receipt, assigns members, clears previous scan), CacheServiceBalance (.serialized, round-trip and zero-default), ContactDiscovery (email validation, dedup, lowercasing).
- `xBillTests/P1NotificationTests.swift` — 17 tests across 4 suites: NotificationStore (.serialized, merge dedup, read-state preservation, sort order, unread count, markAllRead, markRead/markUnread, delete, 100-item cap), NotificationItemFactory (expense + settlement factory field mapping), ActivityViewModelUnread (hasUnread flag, markAllRead zeros VM, per-item read/delete VM state), NotificationItemCodable (expense + settlement JSON round-trip).
- `xBillTests/NotificationReadStateTests.swift` — 29 tests across 6 suites covering the 2026-07-28 unread-lifecycle defect: read-state PATCH payload (explicit JSON `null` to clear `read_at`, explicit UTC ISO-8601 instant to set it, encoded through `SupabaseManager.postgrestEncoder` so it pins the real wire format), affected-row acknowledgement (zero rows → `rowNotFound`, array response shape), `ActivityReconciler` (history unread survives a refresh, unseen history defaults to read, server state authoritative, pending intent overrides, dismissed history stays deleted, dismissal never hides a server row), `NotificationItem` origin (remote vs expense, legacy cache decodes as local, round-trip), `NotificationStore` dismissals (persist, user-scoped, capped), and `ActivityViewModel` mutations with an injected fake service (local-only routing for read state and delete, write-through for server rows, scoped rollback, in-place delete restore, last-toggle-wins).
- `xBillTests/GroupFlowTests.swift` — 27 tests across 6 suites: GroupFlowCachePattern (archive/unarchive array-manipulation logic, idempotency), BillGroupModel (Codable roundtrip, snake_case CodingKeys, Equatable, value-type semantics), GroupCreationLogic (onCreated append, canCreate guard, invite email trim), GroupArchiveLogic (balance-warning conditions, plural/singular, toolbar action context), CurrencyList (count=20, original 8 + 12 new, no duplicates), RealtimeContract (topic scoping). All tests are parallel-safe (no shared UserDefaults state).
- `xBillTests/ViewModelCoverageTests.swift` — 9 focused unit tests for `AddExpenseViewModel` and `GroupViewModel` deterministic local state, validation, split recompute, foreign-currency gating, sorted/active member views, balances, currency-change gating, and optimistic created-expense idempotency.
- `xBillUITests/OnboardingUITests.swift` — 6 focused login/onboarding XCUITests for the redesigned pre-auth entry screen, SwiftUI illustration identifiers, canonical `XBillPageHeader` title identifiers, accessible legal links, email sign-up form content, sign-in validation, sign-in/sign-up toggling, and forgot-password visibility. Launches with `--uitesting --reset-state`; DEBUG app launch handling clears UserDefaults and Keychain session data so each test starts unauthenticated.
- `xBillUITests/GroupFlowUITests.swift` — 14 XCUITests for group creation (form validation, Create button enable/disable, cancel, new group appears in list immediately), archive flow (toolbar menu, confirmation dialog, group moves to archived section on confirm), and active-group toolbar context. Tests can still skip only when the simulator is not signed in or when active-group prerequisite data is absent; archived-group state is covered by deterministic regression tests.
- `xBillUITests/RegressionUITests.swift` — 14 E2E/smoke XCUITests intended as the main repeatable UI regression suite. Checks cover auth validation, main-tab navigation, Create Group validation, Add Expense validation and split controls, core group/expense/archive/unarchive, expense-detail comments, receipt manual review, Manage Group invite/currency lock, Settle Up plus Activity filters, Friends add/search no-results, Profile edit/payment-handle validation, and Profile QR/delete/sign-out cancellation. Authenticated checks read `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` from the environment or test-bundle metadata; missing credentials fail the auth bootstrap instead of creating misleading skips.

## Key Patterns

### State Management
- `@Observable @MainActor final class SomeViewModel` for all VMs
- `@Bindable var vm: SomeViewModel` in views needing two-way binding
- `@State private var vm = SomeViewModel(...)` for locally owned VMs
- One `AuthViewModel` created at app root (`xBillApp`), passed down — never create a second instance

### Auth Flow
1. `xBillApp` creates `AuthViewModel`, starts `loadCurrentUser()` + `startListeningToAuthChanges()`
2. `ContentView` priority: `ResetPasswordView` (if `isInPasswordRecovery`) → `MainTabView` (if `currentUser != nil`) → `AuthView`
3. Sign-up with email → Supabase sends confirmation email → `response.session` is nil → `confirmationEmailSent = true` → show banner
4. DB trigger `handle_new_user()` auto-creates `profiles` row (SECURITY DEFINER, bypasses RLS)
5. Auth state listener: guards `session?.user.emailConfirmedAt != nil` before calling `loadCurrentUser()`; `.passwordRecovery` event sets `isInPasswordRecovery = true`
6. Password reset: user taps email link → `xbill://auth/callback` opens app → `.onOpenURL` calls `supabase.auth.session(from:)` → listener fires `.passwordRecovery` → `ResetPasswordView` shown
7. Sign-out: `AuthService.signOut()` → Supabase `.signedOut` event → listener clears `currentUser` + `isInPasswordRecovery` → `ContentView` transitions back to `AuthView`

### UI Test Auth State
- UI tests should launch with `--uitesting --reset-state` when they need an unauthenticated app. In DEBUG builds, `xBillApp.AppDelegate` responds by clearing the app's UserDefaults domain and deleting xBill Keychain generic-password entries through `KeychainManager.deleteAllForUITesting()`.
- Authenticated UI tests should use `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` environment variables. `xBillUITests/UITestCredentials.plist` is gitignored and excluded from XcodeGen sources so real credentials are not committed as build inputs.
- Current full UI regression command:
  ```
  xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:xBillUITests/RegressionUITests
  ```
- Verified 2026-07-14: `RegressionUITests` executed 14 selected tests with 0 failures and no expected pending skips on iPhone 17 / iOS 26.5. Latest coverage result bundle: `TestResults/Coverage/2026.07.14_21-54-04-regression-ui.xcresult`.
- Current focused login validation command:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme xBill -destination 'id=DA97985A-F7CC-44F6-8281-9DD24C22B978' -only-testing:xBillUITests/OnboardingUITests
  ```
- Verified 2026-05-04: `OnboardingUITests` executed 6 tests with 0 failures on simulator `DA97985A-F7CC-44F6-8281-9DD24C22B978`, including assertions for the onboarding split-bill illustration, sign-in wallet illustration, and canonical auth page header identifiers.

### Coverage Automation
- Preferred command for fast code-coverage signal:
  ```
  scripts/run-coverage.sh unit
  ```
- Widget-only coverage:
  ```
  scripts/run-coverage.sh widget
  ```
- Full scheme coverage, including UI tests:
  ```
  scripts/run-coverage.sh full
  ```
- UI regression coverage only:
  ```
  scripts/run-coverage.sh regression-ui
  ```
- Outputs are timestamped under `TestResults/Coverage/` as `<timestamp>-<mode>.xcresult`, `<timestamp>-<mode>-report.txt`, and `<timestamp>-<mode>-report.json`. `TestResults/` is intentionally gitignored.
- Latest verified full coverage run on 2026-07-15: `TestResults/Coverage/2026.07.15_22-03-05-full.xcresult`; structured summary was `168` passed tests, `0` failures, and `0` skips. Top-level coverage was `xBill.app 60.33% (17335/28734)`, `xBillTests.xctest 99.25% (1727/1740)`, `xBillUITests.xctest 77.83% (1552/1994)`, `xBillWidgetCore.framework 26.99% (61/226)`, `xBillWidgetTests.xctest 100.00% (104/104)`, and `xBillWidget.appex 0.00% (0/3)`.
- Latest verified widget-only coverage run on 2026-07-15: `TestResults/Coverage/2026.07.15_21-54-41-widget.xcresult`; 7 widget tests passed with `0` failures. Coverage was `xBillWidgetCore.framework 26.99% (61/226)`, `xBillWidgetTests.xctest 100.00% (104/104)`, and `xBillWidget.appex 0.00% (0/3)`. The `.appex` target is now only the WidgetKit `@main` wrapper; testable widget behavior lives in `xBillWidgetCore.framework`.
- Use `xcrun xccov view --report <path>.xcresult` for a readable report and `xcrun xccov view --report --json <path>.xcresult` for JSON.

### Auth Configuration Troubleshooting
- If email/password or Apple sign-in reports "A server with the specified hostname could not be found," first inspect the compiled app Info.plist, not the source plist:
  ```
  plutil -extract SUPABASE_URL raw ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphonesimulator/xBill.app/Info.plist
  plutil -extract SUPABASE_ANON_KEY raw ~/Library/Developer/Xcode/DerivedData/xBill-gigdzmkxlvnxfwffqeafujuupnja/Build/Products/Debug-iphonesimulator/xBill.app/Info.plist | wc -c
  ```
- Expected result: the URL is the full Supabase hostname and the anon key length is non-zero. If the URL prints only `https:`, fix `Secrets.xcconfig` to use `https:/$()/...`, regenerate with `xcodegen generate`, rebuild, reinstall, and relaunch.
- Keep `Secrets.xcconfig.example` synchronized with the escaping rule whenever credential setup docs change.

### Deep Link URL Scheme
- Scheme: `xbill://`; registered in `Info.plist` under `CFBundleURLTypes`
- All Supabase auth links (confirmation, password reset) redirect to `xbill://auth/callback`
- Group invite links: `xbill://join/<token>` — parsed in `xBillApp.onOpenURL`; sets `authVM.pendingJoinRequest`; `MainTabView` shows `JoinGroupView` sheet via `sheet(item: $authVM.pendingJoinRequest)`
- Add-friend links: `xbill://add/<userID>` — parsed in `xBillApp.onOpenURL`; sets `AppState.shared.pendingAddFriendUserID`; `MainTabView` resolves user via `FriendService.searchProfiles`, switches to Friends tab, shows `AddFriendView` with `preloadedUser`; QR code generated in `MyQRCodeView` (ProfileView)
- Set in Supabase dashboard: **Authentication → URL Configuration → Site URL + Redirect URLs**

### Sign In with Apple
- Raw nonce generated with `CryptoKit`, SHA256 hash sent to Apple, raw nonce sent to Supabase
- Entitlement: `com.apple.developer.applesignin: [Default]` in `xBill.entitlements`

**Supabase Apple provider — required dashboard setup (one-time):**
1. Apple Developer Portal → Certificates, IDs & Profiles → Keys → create a new key with "Sign in with Apple" enabled → download `.p8` file (note Key ID)
2. Apple Developer Portal → Identifiers → App ID `com.vijaygoyal.xbill` → ensure "Sign in with Apple" capability is enabled
3. Supabase dashboard → Authentication → Providers → Apple → enable and fill in:
   - **Services ID** (client_id): `com.vijaygoyal.xbill` (use the App ID for native flows)
   - **Team ID**: your 10-char Apple Team ID (e.g. `ABCDE12345`)
   - **Key ID**: from the `.p8` key you generated
   - **Private key**: paste full contents of the `.p8` file
4. Save and verify in Supabase Auth → Providers that Apple shows "Enabled"

**Known bugs (all fixed 2026-04-28/30):**
- ~~`AuthViewModel.swift:58` — `emailConfirmedAt` guard blocks Apple users on cold relaunch.~~ ✅ Fixed 2026-04-28
- ~~`xBill.entitlements` — `aps-environment: production` conflicts with debug provisioning.~~ ✅ Fixed 2026-04-28
- ~~**Thin profile for Apple users** — `fullName` from Apple credential was discarded; DB trigger created profile with `display_name = "User"` or relay-email local part.~~ ✅ Fixed 2026-04-30 — `AuthView` extracts `credential.fullName`, passes to `AuthViewModel.signInWithApple(displayName:)`, `AuthService` upserts into `profiles` before `fetchProfile`. `DisplayNamePayload` private struct added to `AuthService.swift`. Subsequent sign-ins send `nil` displayName so existing name is never overwritten.

### Supabase Insert/Update — Always Chain .select()
In Supabase Swift SDK v2, `.insert()` / `.update()` without `.select()` sends `Prefer: return=minimal` → empty response body → decoding to a model fails. Always chain `.select()` before `.single()`. This applies to ALL update calls — `AuthService.updateProfile` and `ExpenseService.updateExpense` both have this correctly:
```swift
let group: BillGroup = try await supabase.table("groups")
    .insert(payload)
    .select()   // ← required to get the row back
    .single()
    .execute()
    .value
```

### Supabase Join Queries
```swift
// Fetching groups a user belongs to — group is optional so compactMap filters nulls:
struct Row: Decodable { let group: BillGroup? }
let rows: [Row] = try await supabase.table("group_members")
    .select("group:groups(*)")
    .eq("user_id", value: userID)
    .execute().value
return rows.compactMap(\.group)
```

### Realtime Subscriptions
- `GroupService.groupChanges(userID:)` → creates Supabase Realtime channel → returns `AsyncStream<Void>`
- `HomeViewModel.startRealtimeUpdates()` iterates stream, calls `loadAll()` on each yield

### Naming — BillGroup vs Group
- The model is `BillGroup` (not `Group`) to avoid collision with `SwiftUI.Group`
- All previews and call sites use `BillGroup(...)`

### Liquid Glass (iOS 26+)
Three modifiers in `Extensions.swift` wrap the `#available(iOS 26, *)` check:
- `.liquidGlass(in: some Shape)` — non-interactive glass; falls back to `.regularMaterial`
- `.liquidGlass(fallback: some ShapeStyle, in: some Shape)` — non-interactive glass; falls back to the provided style (use when `.regularMaterial` would be wrong, e.g. tinted circles)
- `.liquidGlassButton(fallback: some ShapeStyle, in: some Shape)` — interactive glass; falls back to the tinted flat fill

Tab bar, navigation bars, and sheets get Liquid Glass automatically on iOS 26 — no manual work needed.

Applied surfaces:
- **FAB** (`HomeView`) — glass circle; accent fill on iOS 17. `fabForeground` computed property adapts icon color.
- **Group emoji circles** (`GroupRowView`) — `.liquidGlass(in: .circle)`; falls back to `.regularMaterial`
- **Avatar initials circle** (`AvatarView`) — `.liquidGlass(fallback: Color.accentColor.opacity(0.2), in: Circle())`
- **Emoji picker cells** (`CreateGroupView`) — `.liquidGlass(fallback: selected ? accentColor.opacity(0.18) : systemGray6, in: RoundedRectangle)`; accent border retained for selected cell on both OS versions
- **BalanceBadge** — glass capsule with colored text on iOS 26; colored fill with white text on iOS 17. `badgeForeground` computed property handles the difference.
- **EmptyStateView action button** — `.liquidGlassButton(fallback: Color.accentColor, in: Capsule())`; `emptyButtonForeground` adapts text color.
- **Venmo + Mark Settled buttons** (`SettleUpView`) — `.liquidGlassButton(fallback:in: .capsule)`

### Accessibility
- All font tokens use Dynamic Type text styles (`.largeTitle`, `.title`, `.subheadline`, etc.) — do NOT use fixed `size:` integers, which break Dynamic Type scaling
- Key display components expose `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(...)` so VoiceOver reads a single coherent description:
  - `BalanceHeroCard` — "\(label): \(amount), \(subtitle)"
  - `GroupChipView` — "\(group.name) group, \(group.currency)"
  - `ExpenseRowView` — "\(title), paid by \(name), \(amount)"
  - `AmountBadge` — "owed to you / you owe / settled / total: \(amount)"
- Use `.accessibilityHidden(true)` only on purely decorative icons. Major auth/empty-state illustrations are visible content and should expose stable accessibility labels/identifiers for UI tests.

### Error Display
- `errorAlert` modifier shows `error.errorDescription` as the alert title (not a generic string) — useful for debugging
- `error = nil` is only cleared on success, not at the start of an action (prevents alert dismissal)

### RLS Chicken-and-Egg for Group Creation
- Creator can't satisfy `is_group_member(group_id)` for a brand-new group
- Policy (migration 006) adds OR clause: `auth.uid() = user_id AND group.created_by = auth.uid()`

## Error Handling Pattern

All ViewModels use `var errorAlert: ErrorAlert?` (defined in `AppError.swift`) instead of `var error: AppError?`. The `ErrorAlert` struct is `Identifiable` so alerts persist until user dismisses — they are NOT cleared at the start of async operations. Views bind with `.errorAlert(item: $vm.errorAlert)` (defined in `Extensions.swift`). The old `errorAlert(error: Binding<AppError?>)` modifier is kept for local `@State` vars in non-ViewModel views (JoinGroupView, CreateGroupView, etc.).

## Delete Account

`AuthService.deleteAccount()` reads the session JWT and calls the `delete-account` Edge Function with `Authorization: Bearer <token>`, then signs out locally. `ProfileViewModel.deleteAccount()` delegates entirely to `auth.deleteAccount()` and only manages `isLoading`/`errorAlert` state.

**Edge Function deletion order** (device_tokens → profiles → auth user): device_tokens and profile failures are logged but non-fatal; auth user deletion is fatal (returns 500 on failure). **Never pass `user_id` in the request body** — identity is derived from the verified JWT via `adminClient.auth.getUser(jwt)`, then service role is used only for privileged deletion.

**`device_tokens` table** (`016_create_device_tokens_table.sql`): standalone table with `user_id uuid → auth.users(id) on delete cascade`, RLS enabled, single "Users manage own tokens" policy. Migration `010` only added a column to `profiles` — `016` creates the actual table.

**FK constraints** (`017_fix_user_delete_constraints.sql`): `groups.created_by` and `expenses.paid_by` were `ON DELETE RESTRICT` which blocked auth user deletion. Changed to `ON DELETE SET NULL` with nullable columns so groups and expenses persist after the creator/payer is deleted.

Deploy: `supabase db push && supabase functions deploy delete-account --project-ref <ref>`. Secrets required: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (auto-injected; add manually via `supabase secrets set` if missing).

## P1 Features (implemented 2026-04-30)

### In-App Notification Center
- **`NotificationItem`** (`Models/NotificationItem.swift`) — `Codable, Sendable` model replacing `ActivityItem`; `NotificationEventType` enum: `.expenseAdded` and `.settlementMade`; static factories `NotificationItem.expense(...)` and `NotificationItem.settlement(...)`
- **`NotificationStore`** (`Services/NotificationStore.swift`) — local-first persistence via App Group UserDefaults; `merge(_:)` deduplicates by id, caps at 100 items, and preserves existing read state; per-item `markRead(id:)`, `markUnread(id:)`, and `delete(id:)`; `markAllRead()` marks every stored item read and updates `lastViewedAt()` for backward compatibility; `unreadCount()` = unread stored items; `clearAll()` for test teardown
- **`ActivityService`** — now returns `[NotificationItem]`; merges DB-fetched expense items into store on each fetch (preserving read state for existing items)
- **`ActivityViewModel`** — `unreadCount: Int`, per-item `markRead(_:)`, `markUnread(_:)`, `delete(_:)`, `markAllRead()`, `refreshUnreadCount()`, and `hasUnread: Bool` computed
- **`ActivityView`** — title changed to "Notifications", `bell.fill` tab icon; unread blue dot per row; row tap opens alert details and marks that item read; context-menu and swipe actions support read/unread and delete; "Mark All Read" toolbar button; opening the tab does not clear unread count automatically
- **`MainTabView`** — `.badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)` on Activity tab; activity data refreshes at launch and when the app becomes active so badge count does not remain static
- **`GroupViewModel.recordSettlement()`** — writes `NotificationItem.settlement(...)` to `NotificationStore` after each successful settle-up
- **Settlement events** are write-side local notifications — generated when the current user records a settlement; persist across app restarts

## P2 Features (implemented 2026-04-29)

### Cross-Group Debt Simplification
- `HomeViewModel` now accumulates raw `[UUID: Decimal]` balance maps from all groups via `fullBalancesInGroup(_:userID:)` (returning `GroupBalanceData` struct)
- Merges per-currency balance maps and calls `SplitCalculator.minimizeTransactions` on each
- Filters results to only the current user (`crossGroupSuggestions: [SettlementSuggestion]`)
- `HomeView` shows "SIMPLIFY DEBTS" section when `crossGroupSuggestions` is non-empty

### Face ID / Passcode Lock
- `xBill/Services/AppLockService.swift` — `@Observable @MainActor` singleton; `isEnabled` (UserDefaults), `isLocked`, `authenticate()` via `LAContext.deviceOwnerAuthentication`, `lock()`
- `xBill/Views/AppLockView.swift` — full-screen lock overlay; shows biometry icon + "Unlock" button; auto-triggers Face ID on appear
- `ContentView` — `@State private var lockService = AppLockService.shared`; overlays `AppLockView` inside the `authVM.currentUser != nil` branch; `onChange(of: scenePhase)` calls `lockService.lock()` on `.background`
- `ProfileView` — "SECURITY" section with Toggle for Face ID/Passcode
- `Info.plist` — added `NSFaceIDUsageDescription`

### Manual Line-Item Receipt Entry
- `ReceiptViewModel.startManually(members:)` — creates a blank Receipt, clears items/scan state, assigns members
- `ReceiptScanView` — "Enter Manually" button (pencil icon) in the no-image state; sets `showReview = true` after calling `startManually(members:)`

### Onboarding Sample Data
- `HomeViewModel.createSampleData(userID:)` — creates "Sample Trip 🏖️" group + 3 sample expenses (Airfare $240, Hotel $180, Dinner $65) paid by the current user; appends to groups and updates cache
- `OnboardingView` — `onTrySampleData: (() async -> Void)? = nil` parameter; last page shows "Try with sample data" secondary button when callback is set; `isCreatingSample` state shows ProgressView
- `ContentView` — passes `onTrySampleData` closure that calls `HomeViewModel().createSampleData(userID:)` with the current user's ID

### Contact Discovery
- `InviteMembersView` — `CNContactPickerViewController` wrapped as `ContactPickerRepresentable`; "Import from Contacts" button opens picker; selected contacts' emails are added to pending list and looked up in the DB; "On xBill" badge on matching emails
- `GroupService.lookupProfilesByEmail([String]) async throws -> [User]` — calls `lookup_profiles_by_email` RPC
- `supabase/migrations/018_lookup_profiles_by_email.sql` — `SECURITY DEFINER` RPC; excludes current user from results; granted only to `authenticated` role
- `Info.plist` — added `NSContactsUsageDescription`

### WidgetKit Balance Widget
- `xBillWidgetCore/xBillBalanceWidget.swift` — `StaticConfiguration` widget and testable widget logic; `BalanceProvider` reads atomic snapshot net/owed/owing from shared UserDefaults with legacy-key fallback; refreshes every 30 min; `.systemSmall` + `.systemMedium` families
- `xBillWidget/xBillWidgetBundle.swift` — `@main WidgetBundle` wrapper importing `xBillWidgetCore`
- `xBillWidgetTests/BalanceProviderTests.swift` — 7 widget-core unit tests; run with `scripts/run-coverage.sh widget`
- `xBillWidget/Info.plist` — explicit plist with `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`
- `xBillWidget/xBillWidget.entitlements` — App Group `group.com.vijaygoyal.xbill`
- `project.yml` — `xBillWidgetCore` framework target added for linkable/testable widget logic; `xBillWidget` app-extension target depends on it and is embedded in xBill app; `xBillWidgetTests` added to the test scheme
- `CacheService` — now uses `UserDefaults(suiteName: "group.com.vijaygoyal.xbill") ?? .standard`; `nonisolated(unsafe)` for Swift 6 Sendable; `saveBalance(netBalance:totalOwed:totalOwing:)` + load helpers for widget consumption
- Both entitlements files — `com.apple.security.application-groups: [group.com.vijaygoyal.xbill]`
- `HomeViewModel` — calls `WidgetCenter.shared.reloadAllTimelines()` after computing balances
- **⚠️ REQUIRES**: Register App Group `group.com.vijaygoyal.xbill` in Apple Developer Portal → Identifiers before the widget can share data with the main app

## Critical Defect Fixes (2026-05-06)

All 20 critical defects from the senior developer audit (DEFECT_REPORT.md) fixed:

- **CRIT-01** — `Expense.payerID` is now `UUID?` to match nullable `paid_by` DB column (migration 017). All callers updated: `SplitCalculator.netBalances`, `ActivityService`, `ExportService`, `ExpenseRowView`, `GroupStatsView`, `GroupViewModel`, `ExpenseDetailView`.
- **CRIT-02** — `BillGroup.createdBy` is now `UUID?` to match nullable `created_by` DB column (migration 017).
- **CRIT-03** — `supabase/migrations/022_expenses_update_rls.sql` adds UPDATE RLS policy on `expenses` table using `is_group_member()`. Without this, all expense edits and `next_occurrence_date` updates silently failed.
- **CRIT-04** — `AppState.clear()` method added; called from `AuthViewModel.startListeningToAuthChanges()` on `.signedOut` event so stale nav targets never persist across user sessions.
- **CRIT-05** — `NotificationStore` now has `private let lock = NSLock()`. All public methods wrap read-modify-write cycles in `lock.withLock {}` to prevent TOCTOU races.
- **CRIT-06** — `CacheService.save<T>` and `load<T>` now create local `JSONEncoder`/`JSONDecoder` instances per call (not stored properties) to eliminate non-thread-safe shared encoder/decoder access.
- **CRIT-07** — `GroupViewModel.computeBalances()` now uses `withTaskGroup` to fetch all splits in parallel instead of serial N round-trips.
- **CRIT-08** — `GroupViewModel.recordSettlement()` fetches fresh splits for the relevant expenses (parallel `withTaskGroup`) instead of relying on stale `splitsMap`.
- **CRIT-09** — `HomeViewModel` balance task-group workers no longer capture the view model; each child receives immutable service dependencies, so navigating away does not retain `HomeViewModel` until all group fetches finish.
- **CRIT-10** — `HomeViewModel.loadAll()` now calls `await loadArchivedGroups()` on every successful network fetch so archived groups are always in sync.
- **CRIT-11** — `AddExpenseViewModel.save()` and `GroupViewModel.recordSettlement()` now `await` push notification calls inline instead of spawning untracked `Task {}` closures.
- **CRIT-12** — `AddExpenseViewModel.save()` captures `finalAmount` into `capturedAmount` after conversion but before any further `await`, preventing `amountText` edits from altering the saved amount mid-flight.
- **CRIT-13/14** — Supabase-backed services and `SupabaseManager` are `@MainActor` isolated. Cross-thread stores retain explicit synchronization; complete strict-concurrency compilation passes.
- **CRIT-15** — `AuthViewModel.startListeningToAuthChanges()` now guards `isListening` to prevent duplicate concurrent subscribers if called more than once.
- **CRIT-16** — `GroupViewModel.createDueRecurringInstances()` fixed: new instance created with `recurrence: .none, nextOccurrenceDate: nil` (not copying the template's recurrence); template advanced via new `ExpenseService.setNextOccurrenceDate(_:expenseID:)` instead of nulling the date out.
- **CRIT-17** — 4 vacuous tests in `GroupFlowTests.swift` rewritten to call `SplitCalculator.minimizeTransactions` and test production logic rather than hardcoded literals.
- **CRIT-18** — `ExpenseDetailView` swipe-to-delete comment now shows a `confirmationDialog` before deleting; errors are surfaced instead of swallowed.
- **CRIT-19** — `GroupDetailView` swipe-to-delete expense now shows a `confirmationDialog` (stored as `expenseToDelete: Expense?`).
- **CRIT-20** — "Mark as Settled" in `SettleUpView` and the embedded settle tab in `GroupDetailView` now show a `confirmationDialog` before calling `recordSettlement`.

## High Defect Fixes (2026-05-06/07)

All 45 High severity defects from the senior developer audit (DEFECT_REPORT.md) fixed (including H-05 and H-07, fixed 2026-05-07):

- **H-01** — `supabase/migrations/023_high_rls_fixes.sql`: DELETE policy on `splits` using `is_expense_group_member(expense_id)`.
- **H-02** — `supabase/migrations/023_high_rls_fixes.sql`: SELECT policy on `profiles` allowing group-member co-visibility.
- **H-03** — `supabase/migrations/023_high_rls_fixes.sql`: UPDATE policy on `device_tokens` so users can update their own tokens.
- **H-04** — `notify-friend-request/index.ts`: Removed `fromUserID` from APNs `userInfo` payload — prevents user ID leakage to the lock screen.
- **H-05** — `notify-expense/index.ts` + `notify-comment/index.ts`: replaced O(N) per-token `getUnreadCount` DB calls with one batched `batchUnreadCounts` query (fetches all unsettled split rows for all recipients in one go, aggregates in JS). Fixed phantom badge fallback from `?? 1` to `?? 0`.
- **H-06** — `IOUService.fetchUserByEmail`: uses `lookup_profiles_by_email` SECURITY DEFINER RPC via `supabase.client.rpc(...)` instead of direct table query.
- **H-07** — `supabase/migrations/024_create_group_atomic.sql`: new `create_group_with_member` SECURITY DEFINER RPC performs group INSERT + group_members INSERT in one transaction. `GroupService.createGroup` now calls the RPC instead of two separate round-trips, eliminating the window where the group exists but the creator is not a member.
- **H-08/H-15** — `ExchangeRateService`: rates cached as `Decimal` (via `Decimal(string: String(Double))` roundtrip); `rate(from:to:)` returns `Decimal`; all callers updated.
- **H-09** — `ActivityService.items(for:)` returns `Result<[NotificationItem], Error>` — errors surfaced rather than silently returning empty.
- **H-10** — `AuthService.updateDeviceToken`: insert-first (upsert on `user_id,token`), then delete stale tokens atomically.
- **H-11** — `SplitCalculator.validateExact`: takes absolute value before rounding to avoid false negative on negative differences.
- **H-12** — `SplitCalculator.splitEqually`: last participant gets `100 - distributedPct` to ensure percentages always sum to 100.
- **H-13** — `SplitCalculator.minimizeTransactions`: epsilon guard (0.005) prevents infinite loop on residual Decimal balances.
- **H-16** — `GroupViewModel.deleteExpense`: double-tap guard with `isLoading` flag.
- **H-17** — `GroupViewModel.archiveGroup`: variable renamed for clarity.
- **H-18** — `HomeViewModel`: `isComputingBalances` flag guards concurrent balance recomputes.
- **H-19** — `HomeViewModel.createSampleData`: errors surfaced via `errorAlert` instead of silently swallowed; `isLoading` guard added.
- **H-20** — `AuthViewModel.signUp`: silent errors (email confirmation required) suppressed from error alert.
- **H-21** — `AuthViewModel.isEmailValid`: regex-based validation `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`.
- **H-22** — `AuthViewModel`: auth listener no longer skips `loadCurrentUser()` on `.userUpdated` events.
- **H-23** — `ProfileViewModel.saveProfile`: updates profile row before avatar upload to avoid orphaned storage objects.
- **H-24** — `ProfileViewModel.loadStats`: auth errors surface `ErrorAlert(title: "Session Expired")` instead of being swallowed.
- **H-25** — `ProfileViewModel.signOut`: clears all PII fields.
- **H-26** — `ActivityViewModel.load`: reads items first, then syncs `unreadCount` from store.
- **H-27** — `ActivityViewModel`: suppresses unauthenticated errors to avoid spurious alert.
- **H-28** — `ReceiptViewModel.tip`: locale-safe Decimal parse (replaces `,` with `.`).
- **H-29/H-30** — `ReceiptViewModel.startManually/scan`: fully resets all scan state before starting.
- **H-31** — `HomeView.navigationDestination`: guarded with `if let userID = vm.currentUser?.id`.
- **H-32** — `FriendsView.currentUserID`: changed to `UUID?` throughout; `MainTabView` passes optional.
- **H-33** — `ActivityView`: removed duplicate `.onAppear` that triggered double-load.
- **H-34** — `GroupDetailView.task`: comment noting idempotency behavior.
- **H-35** — Widget: `BalanceEntry` now carries `currency: String`; amounts formatted with `NumberFormatter` using the stored currency code instead of hardcoded `$`.
- **H-36** — Widget timeline: produces 3 entries (now, +30min, +60min) with `.atEnd` policy instead of single-entry `.after(30min)`.
- **H-37** — Widget: shows "No data yet" state when `xbill_balance_available` key is absent from UserDefaults (first install or unregistered App Group).
- **H-38** — `GroupDetailView`: removed dead `@ToolbarContentBuilder private var toolbar` property.
- **H-39** — `AddExpenseView.applyReceiptSplits`: uses `"\(total)"` instead of `NSDecimalNumber.stringValue` to avoid scientific notation.
- **H-40** — `ContentView.onTrySampleData`: sets `hasCompletedOnboarding = true` after sample data creation so live `homeVM` in `MainTabView` fetches fresh data from Supabase.
- **H-41** — `VisionService`: replaced `Decimal(string:)!` force-unwrap with literal arithmetic (`Decimal(2)/Decimal(100)`).
- **H-42** — `PaymentLinkService.venmoLink`: validates username matches `^[a-zA-Z0-9._-]+$` before building payment URL; falls back to search URL for display names.
- **H-43** — `ExpenseDetailView`: merged two racing `.task` modifiers into one with `async let` concurrency for splits and comments.
- **H-44** — `ReceiptViewModel.asSplitInputs`: zero-amount members included with `isIncluded = false` instead of excluded.
- **CacheService**: `saveBalance` now accepts and stores `currency: String` and `xbill_balance_available` flag; `loadBalanceCurrency()` and `loadBalanceAvailable()` helpers added.
- **IOUService.fetchUserByEmail**: fixed to use `supabase.client.rpc(...)` (was `supabase.rpc(...)` which doesn't exist on `SupabaseManager`).
- **AddExpenseView**: rate display uses `NSDecimalNumber(decimal:).doubleValue` for `String(format:)` compatibility after `exchangeRate` changed to `Decimal`.

## Architectural Fixes (2026-05-08)

All 4 architectural findings from the May 2026 senior developer audit resolved:

- **ARCH-01** ✅ — `SplitCalculator.fetchSplitsMap(for:using:)` static async method extracted. Both `GroupViewModel.computeBalances()` and `HomeViewModel.fullBalancesInGroup()` call this shared method instead of duplicating the parallel `withTaskGroup` split-fetch loop. Identical algorithm guaranteed.
- **ARCH-02** ✅ — `AuthService.currentUserID` is now a synchronous computed property (`supabase.auth.currentUser?.id`) reading from the SDK's in-memory session cache. Removed `get async` wrapper and two `await` call sites within `AuthService`.
- **ARCH-03** ✅ — `IOUService.fetchIOUs(userID:)` replaced two parallel `async let` queries with a single `.or("lender_id.eq.\(uid),borrower_id.eq.\(uid)")` query. Lender + borrower IOUs now come from the same DB snapshot.
- **ARCH-04** ✅ — `MainTabView` adds `.onChange(of: authVM.currentUser)` that writes to `homeVM.currentUser`. Profile saves now propagate through `AuthViewModel.startListeningToAuthChanges` (`.userUpdated` event) → `authVM.currentUser` → `.onChange` → `homeVM.currentUser`.

## Login Screen Keyboard Jump Fix (2026-05-08)

Four root causes of jumpiness when focusing email/password fields, all resolved (commit `35d0c84`):

- **Dual `@FocusState`** ✅ — Removed `@FocusState private var isFocused` and `.focused($isFocused)` from `XBillTextField`. Border style now driven by `isFocused: Bool = false` parameter passed by the caller. Only one `@FocusState` per field — the one in `EmailAuthView`.
- **`lineWidth` geometry animation** ✅ — `XBillTextField` overlay now uses constant `lineWidth: 1.5`. Only the border color animates on focus (no geometry change competing with the keyboard/scroll animations).
- **190pt non-collapsible illustration** ✅ — `XBillWalletIllustration` is hidden via `if !keyboardVisible` with `.transition(.opacity.combined(with: .move(edge: .top)))` and a coordinated `easeInOut(0.2)` on the parent `VStack`. Scroll jump distance reduced to near zero.
- **`LazyVStack` mid-animation re-layout** ✅ — `EmailAuthView` no longer uses `XBillScreenContainer` → `XBillScrollView` → `LazyVStack`. Replaced with `XBillScreenBackground` + plain `ScrollView` + `VStack`. Added `.scrollDismissesKeyboard(.interactively)`.

**Pattern note:** `XBillTextField.isFocused` must always be set via `focusedField == .fieldName` comparison from the caller's `@FocusState`. Do not re-add an internal `@FocusState` to `XBillTextField`.

## Auth Screen Fixes (2026-05-08)

Five issues found in a senior developer audit of `AuthView` + `EmailAuthView`, all resolved:

- **E-1 — Disabled button invisible (Critical)** ✅ — `XBillButtonBase` now uses `AppColors.textSecondary` as foreground when `isDisabled` (previously kept `textInverse` = white, which is invisible on `surfaceSoft` background). Opacity no longer drops to 0.72 on disabled — only on loading. Fix in `XBillButtons.swift`.
- **E-2 — Disabled button has no shape affordance (Medium)** ✅ — `XBillButtonBase` now strokes `AppColors.border` (1pt) around the disabled button shape, giving it a clear button outline even when the background is light. Fix in `XBillButtons.swift`.
- **E-3 — Fragile negative-padding on XBillPageHeader (Low)** ✅ — `EmailAuthView` restructured: `XBillPageHeader` is now in the outermost `VStack` (no horizontal padding applied), and the illustration + form card live in an inner padded `VStack`. Eliminates the `.padding(.horizontal, -AppSpacing.lg)` double-negation hack.
- **W-1 — Large illustration pushes auth card below fold on iPhone SE (Medium)** ✅ — `AuthView` illustration reduced from `size: 220` to `size: 160`.
- **W-2 — LazyVStack on static welcome screen (Low)** ✅ — `AuthView` replaced `XBillScreenContainer` → `XBillScrollView` → `LazyVStack` with `XBillScreenBackground` + plain `ScrollView` + `VStack` (same pattern as `EmailAuthView`).

**`XBillButtonBase` disabled-state rule:** background = `surfaceSoft`, foreground = `textSecondary`, border = `border` (1pt), opacity = 1.0. Never use `textInverse` (white) for a disabled button that renders on `surfaceSoft`.

## Auth Screen Loop Fix (2026-05-08)

Landing-page ↔ welcome-screen loop on cold launch. Three root causes, all resolved:

- **RC-1 — Duplicate `loadCurrentUser()` on startup** ✅ — `xBillApp` previously fired two concurrent Tasks: `.task { await authVM.loadCurrentUser() }` AND `startListeningToAuthChanges()` (which also calls `loadCurrentUser()` on `.initialSession`). The two calls raced; if either threw first, it cleared `currentUser` while the other was still setting it, causing ContentView to animate back and forth. Fix: removed the direct `loadCurrentUser()` task — the auth listener's `.initialSession` is the sole startup load path.
- **RC-2 — `loadCurrentUser()` cleared user on any error** ✅ — The catch block set `currentUser = nil` for transient network errors, timeouts, and decode failures. Any such error immediately animated back to `AuthView`. Fix: catch block is now a no-op. The `.signedOut` auth event is the sole authoritative signal for clearing `currentUser`.
- **RC-3 — Auth listener called `loadCurrentUser()` with nil session** ✅ — `.initialSession` fires on every cold launch with `session == nil` when no user is signed in. Without a session guard, this made a network round-trip guaranteed to throw (hitting the RC-2 catch). Fix: added `guard session != nil else { break }` at the top of the `.initialSession, .signedIn, .tokenRefreshed, .userUpdated` case.

**Auth state rule:** `currentUser` is set only by `loadCurrentUser()` (on success) and cleared only by the `.signedOut` event. Never clear it on catch. The single `.task { await authVM.startListeningToAuthChanges() }` in `xBillApp` is the only startup entry point — do not add a second concurrent `loadCurrentUser()` call.

## Profile Screen Bug Fixes (2026-05-09)

Two bugs fixed on the Profile screen after the defect audit shipped.

### PF-1 — "Cannot coerce the result to a single JSON object" ✅
- **Root cause:** `AuthService.fetchProfile()` has a fallback upsert path for accounts pre-dating the DB trigger. The path used `.upsert(payload).single().execute()` — missing `.select()` before `.single()`. Without `.select()`, the Supabase SDK sends `Prefer: return=minimal` → empty response body → `.single()` throws "Cannot coerce the result to a single JSON object".
- **Fix:** Added `.select()` before `.single()` in the upsert fallback path in `AuthService.fetchProfile()` (line ~193). Matches the documented "Always Chain .select()" pattern in Key Patterns.
- **File:** `xBill/Services/AuthService.swift`

### PF-2 — "Request rate limit reached" ✅
- **Root cause:** On startup and again when the Profile tab was opened, `auth.currentUser()` → `supabase.auth.session` (which triggers a JWT refresh if the token is expired) was called by three overlapping sources simultaneously: the auth state listener, `homeVM.loadCurrentUser()`, and `profileVM.load()` (from `MainTabView.task`). Then a 4th call fired when the user tapped the Profile tab (`ProfileView.task`). Supabase free tier rate-limits `/auth/v1/token?grant_type=refresh_token` — this produces the "Request rate limit reached" error.
- **Three-part fix:**
  1. **Removed `await profileVM.load()` from `MainTabView.task`** — the profile tab loads itself via `ProfileView.task` when first visited; there is no value in preloading profile stats before the user navigates there.
  2. **Seeded `profileVM.user` / `profileVM.displayName` from `authVM.currentUser` via `.onChange`** — the profile card shows user data (name, avatar) immediately when the tab is opened, without any auth call. Added to the existing `.onChange(of: authVM.currentUser)` handler in `MainTabView`.
  3. **`ProfileViewModel.load()` skips `auth.currentUser()` when `user` is already set** — if the user was seeded via `.onChange`, `load()` goes straight to `loadStats`. Falls back to `auth.currentUser()` only when `user` is nil (edge-case first launch before onChange fires).
- **Files:** `xBill/Views/Main/MainTabView.swift`, `xBill/ViewModels/ProfileViewModel.swift`

**Profile auth call rule:** `ProfileViewModel.load()` must not call `auth.currentUser()` when `user` is already populated. The auth listener + `homeVM.loadCurrentUser()` are the canonical source of the current user. `ProfileViewModel` gets the user via `MainTabView.onChange(of: authVM.currentUser)` and only computes stats via `loadStats(userID:)` on its own.

## Second-Pass Defect Fixes (2026-05-09)

All 20 defects from the second senior developer audit (v2) fixed. Key changes:

- **CRIT-01** — `ExpenseDetailView.saveEdit()` now preserves `originalAmount`/`originalCurrency` fields; multi-currency metadata no longer destroyed on every edit.
- **CRIT-02** — `KeychainSessionStorage.retrieve()` `kSecAttrService` corrected from `"com.xbill.app"` to `"com.vijaygoyal.xbill"`; session tokens no longer orphaned.
- **HIGH-01** — `notify-settlement/index.ts` phantom badge fixed: `badgeCount ?? 0` (was `?? 1`). ✅ Deployed 2026-05-09.
- **HIGH-02** — Venmo/PayPal payment handles: migration `026_venmo_paypal_handles.sql` adds columns, `User` model adds fields, `AuthService.updateProfile` extended, `ProfileViewModel` saves/loads handles. ✅ Deployed 2026-05-09.
- **HIGH-03** — `FriendsView.netBalances(with:)` guard against nil `currentUserID` prevents inverted IOU balances.
- **HIGH-04** — `NotificationItem.settlement` dedup hash now includes currency to prevent cross-currency collisions.
- **MED-01** — `GroupViewModel.createDueRecurringInstances`: split fetches parallelized with `withTaskGroup`.
- **MED-02** — `ExchangeRateService.session`: moved to stored actor property (eliminates per-call `URLSession` allocation).
- **MED-03** — `CacheService.saveBalance` stores amounts as `String` to avoid `Double` precision loss; widget reads via `Double(defaults.string(...))`.
- **MED-04** — `VisionService.ciContext`: now a `private static let` (eliminates per-call `CIContext` allocation).
- **MED-05** — `ActivityService` merges partial results before error check; throws on any error; `ActivityViewModel` reads store on partial failure.
- **MED-06** — `CreateGroupView` accepts `inviterName: String` parameter; `CreateGroupView` no longer makes a redundant `currentUser()` network call.
- **MED-07** — `MainTabView` quick-action handler loads user before showing sheet; uses `if let userID` guard (no more random-UUID payer).
- **MED-08** — `FriendsView.friendRow`: blank email suppressed in subtitle via `flatMap`.
- **MED-09** — `HomeViewModel.createSampleData` is `async throws`; `ContentView` surfaces errors via `.alert`.
- **LOW-01** — `FoundationModelService`: `_cachedSession` force-unwrap replaced with `guard let` + throw.
- **LOW-02** — `SplitInput(from:)`: Release builds now log via `Logger(...).fault(...)` in addition to DEBUG assertionFailure.
- **LOW-03** — `AuthViewModel.startListeningToAuthChanges`: session-user-ID dedup skips redundant `loadCurrentUser()` calls; always allows `.userUpdated` through; resets on `.signedOut`.
- **LOW-04** — Widget balance currency fallback uses `Locale.current.currency?.identifier ?? "USD"` (bundled with MED-03).

## Third-Pass Defect Fixes (2026-05-10)

All 11 Critical and 37 High defects from the v3 senior developer audit (DEFECT_REPORT_V3.md) fixed in commit `35b7940`.

### Critical Fixes
- **CRIT-01** — `GroupViewModel.createDueRecurringInstances`: per-expense try/catch; one failure no longer aborts batch; `displayName` populated from `memberNames` map after `SplitInput(from:)` mapping.
- **CRIT-02** — `SplitInput(from:)`: removed `#if DEBUG assertionFailure` block; all builds log via `Logger(...).fault(...)` — no debug-only crash when recurring expense templates have incomplete split data.
- **CRIT-03/04/05/06/07** — Migration `027_crit_rls_fixes.sql`: `groups` UPDATE `WITH CHECK (auth.uid() = created_by)`, new `groups` DELETE policy (creator only), `ious` UPDATE `WITH CHECK`, `friends` UPDATE restricted to addressee accepting/blocking, `group_invites` SELECT to creator or member, `device_tokens` `WITH CHECK (auth.uid() = user_id)`, profiles email functional index, drop 7-param RPC overload, `join_group_via_invite` deletes token on use (single-use).
- **CRIT-08** — `IOUService.settleIOU`: added `.eq("is_settled", value: false)` idempotency guard + `.select().single()` so RLS failures throw instead of returning silent HTTP 200.
- **CRIT-09** — `FoundationModelService`: converted from `final class` to `actor`; `_cachedSession` is actor-isolated `private var`; `isAvailable` is `nonisolated`.
- **CRIT-10** — `GroupViewModel.load()` catch block unconditionally restores from cache (not gated on `members.isEmpty`).
- **CRIT-11** — `ExpenseDetailView` delete confirmation: `Task { await ...; onDeleted?(); dismiss() }` — dismiss after async work, not before.

### High Fixes
- **H-01/H-02** — `SplitCalculator.splitEqually`: remainder goes to LAST participant; percentages computed with `100 - distributedPct` for last entry so they always sum to 100.
- **H-03** — `AuthViewModel.handlePasswordReset`: password length validated >= 8 before network call.
- **H-04** — `AuthService.isNotFoundError`: matches `PGRST116` or `HTTP 406` case-insensitively (not broad `"406"` substring).
- **H-05/H-06** — `ExpenseService.setNextOccurrenceDate`: added `.select()` so RLS failures throw; removed dead `NullNextOccurrence` struct.
- **H-07** — `xBillApp`: removed duplicate `application(_:continue:userActivity:)` from `AppDelegate` (iOS 17+ uses SwiftUI `.onContinueUserActivity`).
- **H-08** — `notify-expense/index.ts`: `payerId` for sender exclusion now sourced from `callerID` (verified JWT), not body.
- **H-09** — `notify-settlement/index.ts`: `fromUserID`/`fromName` sourced from JWT `callerID`; `toUserID` validated as group member before proceeding.
- **H-12** — `HomeViewModel.loadAll()` catch block calls `computeBalances(for:)` after cache restore so offline balance view is correct.
- **H-14** — `HomeViewModel.startRealtimeUpdates()`: stores `realtimeTask: Task<Void, Never>?` handle; cancels existing task before creating new one.
- **H-15** — `AddExpenseViewModel.save()`: re-checks `canSave` after `await updateConversion()` using already-bound local `payerID`.
- **H-16** — `ProfileViewModel.saveProfile`: uploads avatar first, then does ONE `updateProfile` write with `finalAvatarURL`.
- **H-17** — `ProfileViewModel.saveProfile`: validates and trims `displayName` before any network call.
- **H-21** — `FriendsView.ious(with:)` and `netBalances(with:)`: constrained to current user as lender or borrower (no third-party IOUs).
- **H-22** — `AppLockService`: `cachedBiometryType` stored once at init; removed repeated `LAContext` creation in computed properties.
- **H-24/H-25** — `ExportService`: CSV uses `\r\n` + UTF-8 BOM; `currencyFormatter.locale = en_US_POSIX`; PDF column widths prevent "Paid By" clipping.
- **H-26** — `GroupDetailView`: removed `placement: .navigationBarDrawer` from `.searchable` (fails with hidden nav bar).
- **H-27** — `GroupDetailView`: removed dead `@State private var showSettleUp` and its `.sheet` binding.
- **H-28** — `HomeView` navigation destination: shows `ProgressView("Loading...")` when `currentUser?.id` is nil.
- **H-29** — `SettleUpView`: `@State private var isSettling` guard prevents double-tap on "Mark Settled".
- **H-30/H-31** — `FriendsView`: removed dead `contactSuggestions`/`quickAdd`; added toolbar `ProgressView` during refresh.
- **H-32** — `MainTabView` quick action: checks `currentUser != nil && !groups.isEmpty` before showing sheet.
- **H-33** — `ProfileView`: "Payment Handles" section header shows a "Save" button (disabled during load) whenever `venmoHandle` or `paypalEmail` differs from the saved `vm.user` values. Calls `vm.saveProfile(avatarImage: nil)`.
- **H-34** — `ProfileViewModel`: added `primaryCurrency: String` (most-used currency across fetched groups, default "USD"); `ProfileView` stats card uses `vm.primaryCurrency` instead of hardcoded `"USD"`.
- **H-35** — `ExpenseDetailView`: ProgressView overlay on Save button has `.allowsHitTesting(false)`.
- **H-36** — `ExpenseDetailView.openEditSheet()`: uses `NSDecimalRound` to avoid scientific notation in amount string.
- **H-37** — `ExchangeRateService.rates(base:)`: HTTP status code checked before JSON decoding; non-2xx throws descriptive error.

- `notify-settlement` ✅ — derives every identity field from the settlement row rather than the caller (2026-08-01). Preserves `H-09` and strengthens it: the body carries only `{settlementId, isDevelopment}`, the row is read with the service role, `recorded_by === callerID` is checked before any field is used, and the push goes to whichever party is *not* the caller. Necessary because either party may now record — the old `fromUserID = callerID` would have announced a creditor as the payer and pushed to themselves.

## Known TODOs
- **App Group registration** (for widget data sharing): register `group.com.vijaygoyal.xbill` in Apple Developer Portal → Certificates, IDs & Profiles → Identifiers → App Groups
- App Store Assets: screenshots, preview video, keyword strategy (only remaining P0 blocker)

## All v3 Low Defects Fixed (2026-05-13, commit 126ed55)

All 30 v3 Low defects resolved. Key changes:

- **L-01** — `Expense.Category`/`Recurrence` custom decoders fall back to `.other`/`.none` on unrecognized DB values
- **L-03** — `SplitCalculator.validateExact` formats amounts to 2dp in error strings
- **L-05** — `AppDelegate` token registration logs failures via `Logger`
- **L-06** — Dead `fetchUnsettledExpenses` removed from `ExpenseService`
- **L-08** — `AuthViewModel.passwordResetSent` flag added
- **L-10** — `splits_settled_consistency` CHECK constraint (migration 030)
- **L-11** — `join_group_via_invite` unified error message (migration 030)
- **L-12** — `VisionService.recognizeText` passes `UIImage` orientation to Vision — rotated receipts now OCR correctly
- **L-13** — `GroupDetailView` FAB `.accessibilityLabel("Add Expense")`
- **L-14** — `GroupDetailView` export error feedback via `vm.errorAlert`
- **L-16** — `ActivityView.groupedItems` `DateFormatter` → `private static let`
- **L-17** — `ProfileView` stats `.redacted(reason:)` skeleton while loading
- **L-18** — `ProfileView` avatar picker uses `PHPickerViewController` (replaces deprecated `UIImagePickerController`)
- **L-19** — `HomeView` recent expense rows are tappable `NavigationLink`s to `ExpenseDetailView`
- **L-20** — `SettleUpView` amount color direction-aware (red=you owe, green=owed to you)
- **L-21** — `ContentView` sample data alert uses `errorDescription` as title
- **L-22** — `ReceiptViewModel.confidenceLabel` uses `if/else if` instead of `PartialRangeFrom` switch
- **L-23** — `ReceiptViewModel.updateUnitPrice/updateQuantity` use copy-mutate pattern
- **L-24** — `VisionService.validateHeuristic` cached — called only once per scan
- **L-25** — `ExchangeRateService` persists rates to `UserDefaults` — stale disk cache used offline
- **L-26** — `AddIOUView` description capped at 200 chars with counter
- **L-27** — `CacheService.saveBalance` writes single JSON blob atomically
- **L-28** — `AuthViewModel.hasStartedListener` static flag prevents duplicate auth listeners
- **L-29** — `InviteJoinRequest` moved to `GroupInvite.swift`
- **Migration 030** ✅ — L-10 + L-11 pushed to production DB (2026-05-13)

## Deployed Edge Functions (production)
- `notify-expense` ✅ — H-05 badge batching live (2026-05-07)
- `notify-comment` ✅ — H-05 badge batching live (2026-05-07)
- `notify-friend-request` ✅ — H-04 fromUserID removal live (2026-05-07)
- `notify-settlement` ✅ — HIGH-01 phantom badge fix live (2026-05-09)
- `invite-member` ✅ — group email invites live (2026-05-09); secrets: `RESEND_API_KEY` + `INVITE_FROM_EMAIL=invites@xbill.vijaygoyal.org`
- Migrations 023 + 024 ✅ — pushed to production DB (2026-05-07)
- Migration 026 ✅ — `venmo_handle` + `paypal_email` columns live (2026-05-09)
- `notify-expense` ✅ — H-08 callerID sender-exclusion live (2026-05-13)
- `notify-settlement` ✅ — H-09 callerID fromUserID/fromName + toUserID group-member validation live (2026-05-13)
- Migration 027 ✅ — pushed to production DB (2026-05-13). CRIT-03 groups UPDATE (creator-only), M-22 groups DELETE (creator-only), CRIT-04 ious UPDATE WITH CHECK, CRIT-05 friends UPDATE (addressee, accepted/blocked only), CRIT-06 group_invites SELECT (creator or member), CRIT-07 device_tokens FOR ALL WITH CHECK, H-10 profiles email functional index, H-11 drop old 7-param add_expense_with_splits overload, M-20 join_group_via_invite single-use token (DROP+CREATE to preserve uuid return type)
- Migration 028 ✅ — pushed to production DB (2026-05-13). M-21 creator DELETE policy on group_members so creator can remove any member.
- Migration 050 ✅ — pushed to production DB (2026-08-29). Comment-only: records in the database that `splits.is_settled` is deprecated and permanent. No data, schema-shape or policy change. `migration list --linked` reads `050 | 050 | 050`.
- Migration 051 ✅ — pushed to production DB (2026-08-31). `updated_by` column; `updated_at` backfilled to `created_at` on **60 of 62** rows and made `NOT NULL DEFAULT now()`; `update_expense_with_splits` DROP+CREATEd with `p_expected_updated_at timestamptz DEFAULT NULL`, raising SQLSTATE `XB409` on conflict. `migration list --linked` reads `051 | 051 | 051`; exactly **1** overload (the 9-arg one), `anon_exec = false` / `auth_exec = true`. Guard verified live in **both** directions without writing — stale token → `XB409`, real token → accepted — using a `DO` block whose closing `RAISE` rolls the probe back. ⚠️ **The client that sends the token is unreleased**, so `DEFAULT NULL` means no live user is protected yet.
- Migration 052 ✅ — pushed to production DB (2026-08-31). `purge_ui_test_groups`: adds `PaymentReturn`, `ScrollProbe` and `Validation` to both prefix lists, and **revokes EXECUTE from `anon` by name**. ⚠️ **`anon` could previously execute this `SECURITY DEFINER` function** — its ownership guard is `IF caller_id IS NOT NULL AND …`, and `auth.uid()` is NULL for an anonymous caller, so the guard was *skipped*; an unauthenticated caller passing `p_created_by` + `p_execute => true` could delete another user's prefixed groups. Confirmed live (anon POST returned **HTTP 200** before, **401 / 42501** after) and 039's `REVOKE … FROM PUBLIC` did nothing, because Supabase grants `anon` EXECUTE explicitly. The NULL-caller path is kept deliberately: `scripts/purge-ui-test-groups.sh` runs on a privileged connection where `auth.uid()` is NULL. Then purged **51** orphaned groups (37 `PaymentReturn` since 2026-07-27 carrying 37 expenses/37 splits, 14 `ScrollProbe` since 2026-08-24); production went 63 → 26 expenses, 83 → 46 splits.
- Migration 029 ✅ — pushed to production DB (2026-05-13). M-18 group_members INSERT profile-existence check, M-19 search_profiles 2-char minimum, M-24 composite index on group_members(user_id,group_id), M-48 send_friend_request ON CONFLICT DO NOTHING with pair unique index.
- `notify-expense` ✅ — M-23 APNs expiry 24h live (2026-05-13)
- `notify-settlement` ✅ — M-23 APNs expiry 24h live (2026-05-13)
- `notify-comment` ✅ — M-23 APNs expiry 24h live (2026-05-13)
- `notify-friend-request` ✅ — M-23 APNs expiry 24h live (2026-05-13)

## Low Defect Fixes (2026-05-07)

All 47 Low severity defects from the senior developer audit (DEFECT_REPORT.md) fixed:

### Views (L-02 through L-15, L-43, L-45)
- **L-02** — `ExpenseDetailView`: "Settled" label color changed from `.green` to `Color.moneySettled`.
- **L-03** — `ExpenseDetailView`: category `Label` icon gets `.accessibilityHidden(true)` — VoiceOver skips raw image name.
- **L-04** — `ReceiptScanView`: disabled Scan button gets `.accessibilityHint("Document camera is not available on this device")`.
- **L-05** — `ReceiptReviewView`: `.onChange(of: showAddItem)` resets `newItemName`/`newItemPrice` to `""` on dismiss, including swipe-down.
- **L-06** — `SettleUpView`: settlement amount color changed from `.red` to `Color.moneyNegative`.
- **L-07** — `EmailAuthView`: removed inner duplicate `VStack` subtitle — `XBillPageHeader` is now the single source.
- **L-08** — `EmailAuthView`: email field gets `.submitLabel(.next)` + `.onSubmit { focusedField = .password }`; password field gets `.submitLabel(.go)` + `.onSubmit { action }`.
- **L-09** — `MainTabView`: `.badge(activityVM.unreadCount > 0 ? activityVM.unreadCount : 0)` simplified to `.badge(activityVM.unreadCount)`.
- **L-10** — `MainTabView`: QR-friend sheet now dismisses immediately (`.onAppear { showAddFriendFromQR = false }`) when `currentUser` is nil.
- **L-11** — `FriendsView`: unreachable "From Your Contacts" section removed — `contactSuggestions` was never populated by `loadAll()`.
- **L-12** — `AddFriendView`: `addFriendURL` force-unwrap replaced with `URL?`; `ShareLink` wrapped in `if let`.
- **L-13** — `MyQRCodeView`: deep-link URL force-unwrap replaced with optional binding; `ShareLink` and QR `.task` guarded.
- **L-14** — `GroupInviteView`: already safe (no force-unwrap present); skipped.
- **L-15** — `ProfileView`: version fallback changed from `"1.0"` to `"—"`.
- **L-43** — `xBillBalanceWidget`: hardcoded RGB colors replaced with `Color("MoneyPositive")` and `Color("MoneyNegative")`.
- **L-45** — `QuickAddExpenseSheet`: member load extracted to `loadMembers(for:)` method; "Retry" button in error alert re-calls it.

### Models, Core, Services (L-16 through L-34)
- **L-16** — `KeychainManager`: service ID corrected from `"com.xbill.app"` to `"com.vijaygoyal.xbill"`.
- **L-17** — `NetworkMonitor`: `deinit` calling `monitor.cancel()` off main actor removed (singleton never deallocated).
- **L-18** — `Expense.nextDate(from:)`: `.none` case already returns `nil`; no change needed.
- **L-19** — `Split.SplitInput(from:)`: `#if DEBUG assertionFailure` added when `displayName` is empty.
- **L-20** — `Friend.status`: changed from `let` to `var` to allow optimistic local mutation.
- **L-21** — `NotificationItem.settlement`: added comment: "Settlements have no spending category; .other is the canonical placeholder."
- **L-24** — `AuthService.uploadAvatar`: appends `?t=<epoch>` cache-buster to avatar URL after upload.
- **L-25** — `GroupService`/`FriendService`: added comment "createdAt synthesised — not the actual registration date; do not sort by this field." at all `createdAt: Date()` synthesis sites.
- **L-26** — `ExchangeRateService`: `URLSession` uses `URLSessionConfiguration` with `timeoutIntervalForRequest = 10`.
- **L-27** — `ActivityService`: expense fetch per group uses `.limit(50)`; `fetchRecentActivity` already honours the `limit` parameter.
- **L-28** — `NotificationService`: `"settlementID"` casing corrected to `"settlementId"` (matches `"groupId"` convention).
- **L-29** — `VisionService`: O(n²) row-grouping replaced with O(n log n) single-pass Dictionary approach.
- **L-30** — `FoundationModelService`: `LanguageModelSession` cached in `_cachedSession` (one per service lifetime); recreated only when nil.
- **L-31** — `ExportService.writeTemp`: UUID suffix in temp filename prevents concurrent-export file corruption.
- **L-32** — `VisionService`: merchant extraction skips all-caps noise lines (`"THANK YOU"`, `"RECEIPT"`, etc.) before assigning merchant name.
- **L-33** — `SpotlightService`: errors logged via `os_log` (`Logger(subsystem:category:)`) instead of silently discarded.
- **L-34** — `AddExpenseViewModel`: payer name fallback chain: `nameMap[payerID] ?? (payerID == currentUserID ? currentUser.displayName : nil) ?? "Someone"`.

### Tests (L-35 through L-44)
- **L-35** — `P3HelperTests.swift` (new): `GreetingHelperTests` — 8 boundary tests covering hours 4, 5, 11, 12, 16, 17, 21, 22.
- **L-36** — `P3HelperTests.swift` (new): `BalanceMessageHelperTests` — 5 tests covering zero, positive, negative, small positive, small negative.
- **L-37** — `OnboardingUITests`: marketing-copy selectors replaced with resilient `scrollViews.firstMatch.exists` checks.
- **L-38** — `GroupFlowUITests`: timestamp-based unique group name replaces `Int.random` (prevents CI collision).
- **L-39** — `GroupFlowUITests`: `addTeardownBlock` added to archive the created test group via UI after each test.
- **L-40** — `OnboardingUITests`: `signInToggle` selector refined to avoid matching the "Sign In" submit button.
- **L-41** — `P2FeatureTests`: `var usdBalances`/`var eurBalances` changed to `let` in `currencySeparation()`.
- **L-42** — `SecurityFixTests`: silent `guard … else { return }` replaced with `Issue.record(…)` so precondition failures surface.
- **L-44** — `P1NotificationTests`: `expenseFactoryEmptyEmoji` test added; `NotificationItem.expense` factory fixed to use `emojiPrefix` to avoid leading space when `groupEmoji` is `""`.

### Backend Edge Functions (L-22, L-23, L-46, L-47)
- **L-22** — `delete-account/index.ts`: CORS headers + OPTIONS preflight handler added.
- **L-23** — All notify functions: comment added clarifying Deno Edge isolate-scope for `cachedJWT` (no real race condition).
- **L-46** — `018_lookup_profiles_by_email.sql`: history note added (email removed in migration 025).
- **L-47** — All 6 Edge Functions: `@supabase/supabase-js@2` pinned to `@2.49.1`.

## All v3 Medium Defects Fixed (2026-05-13)

All 44 remaining Medium defects from the v3 audit fixed in commits `09d2f7e` + `ac9ba65` (2026-05-13).

### Swift fixes (commit ac9ba65)
- **M-01** — `SplitCalculator.splitByShares` last-participant percentage correction (`100 - distributedPct`)
- **M-02** — `AuthViewModel`: set `lastLoadedUserID = user.id.uuidString` after direct sign-in to block redundant listener reload
- **M-03** — `CacheService.save` skips write when `encrypt` returns nil — no plaintext fallback when Keychain unavailable
- **M-04** — `NotificationStore.clearItems()` dead API removed
- **M-05** — `IOU.createdBy` changed to `UUID?` — NULL legacy rows no longer crash decoder
- **M-10** — `IOUService.fetchUserByEmail` uses `.whitespacesAndNewlines` trim
- **M-12** — `VisionService.extractDecimal` uses `matches.last` — returns rightmost price (line total, not unit price)
- **M-13** — `VisionService` detects `¥`/`₩` currency symbols → JPY/KRW
- **M-14** — `FriendsView.friendIDsWithBalance` uses `Set<UUID>` — O(1) lookup instead of O(n²)
- **M-25** — `IOUService.createIOU` validates caller is lender or borrower before DB call
- **M-27** — `GroupViewModel.recordSettlement` removes unnecessary `[weak self]`
- **M-28** — `HomeViewModel.unarchiveGroup` rollback restores both `groups` and `archivedGroups`
- **M-29** — `HomeViewModel.deleteGroup` `isLoading` guard + cache update after deletion
- **M-30** — `HomeViewModel.computeBalances` name merge uses `{ _, new in new }` — newer name wins
- **M-31** — Push pref keys use `CacheService.defaults` (App Group suite, not `.standard`)
- **M-33** — `AddExpenseViewModel.updateConversion` cancels stale tasks via `conversionTask: Task<Void, Never>?`
- **M-34** — `ProfileViewModel.loadStats` batches 5 groups at a time instead of all-at-once
- **M-35** — `GroupDetailView` resets `searchText`/`filterCategory` on tab switch
- **M-36** — `GroupDetailView` Balances/Settle Up tabs show `ProgressView` while `isLoading`
- **M-37** — `FriendDetailView` uses `@State private var localIOUs` refreshed after settle
- **M-38** — `FriendDetailView.loadMutualGroups()` no longer bails silently when `allGroups` is empty
- **M-39** — `FriendDetailView` uses `XBillPageHeader` with hidden nav bar (design system consistent)
- **M-40** — `ActivityViewModel.markAllRead()` immediately maps `items` array to `isRead = true`
- **M-41** — `ReceiptViewModel.asSplitInputs()` single O(N) pass (was O(N×M) per member)
- **M-42** — `ReceiptViewModel.scan(pages:)` sets `capturedPages = pages` at start — no stale pages
- **M-43** — `ExpenseDetailView` delete swipe shown only on own comments via per-row `.swipeActions`
- **M-44** — `ExpenseDetailView` realtime subscription errors logged via `Logger` instead of silent fail
- **M-45** — `MainTabView` QR deep-link sheet guarded on `currentUser != nil` — no transparent flash
- **M-46** — `MainTabView` foreground refresh also calls `homeVM.loadAll()` alongside `activityVM.load()`
- **M-47** — `MainTabView` deep-link uses `fetchProfiles(ids:)` not `searchProfiles` for UUID lookups
- **M-50** — `ProfileView` bottom padding reduced from ~80pt to `AppSpacing.lg` (no FAB on profile tab)
- **M-52** — `ProfileViewModel.loadStats` excludes recurring templates from `lifetimePaid`

### Earlier batch (commit 09d2f7e)
- **M-06/M-07/M-08/M-09/M-11/M-17/M-21/M-51** — see "Data Correctness Fixes" history below

### Backend fixes (migration 029 + edge function deploys)
- **M-18** — `group_members` INSERT policy requires `user_id` exists in `profiles`
- **M-19** — `search_profiles` RPC enforces minimum 2-char query
- **M-23** — APNs `apns-expiration` extended to 24h across all 4 notify functions
- **M-24** — Composite index `group_members(user_id, group_id)` for RLS query perf
- **M-48** — `send_friend_request` uses `INSERT … ON CONFLICT DO NOTHING` with unique pair index

### Already correct / confirmed no-ops
- **M-15** — `ExportService.currencyFormatter` already had `en_US_POSIX` locale
- **M-16** — `AppLockService.authenticate` already only disables on `passcodeNotSet`
- **M-20** — Fixed in migration 027 (single-use invite tokens)
- **M-22** — Fixed in migration 027 (groups DELETE creator-only)
- **M-26** — `recordSettlement` already correctly scoped by expense pre-filter
- **M-32** — `canSave` re-check after `await` already in place from H-15

### Previous batch (commit 09d2f7e)

- **M-06** — `homeVM` moved to `ContentView` (`@State private var homeVM = HomeViewModel()`); `MainTabView` takes `var homeVM: HomeViewModel` (no `@State`). Sample data now writes to the live instance visible on the Groups tab.
- **M-07** — `GroupViewModel.createDueRecurringInstances`: computes `newNextDate` BEFORE the `splitInputs.isEmpty` guard. Empty-split templates log via `Logger.fault` and advance the date rather than retrying infinitely.
- **M-08** — `ExpenseService.fetchDueRecurringExpenses(groupID:)`: removed `payerID` parameter + `.eq("paid_by", ...)` filter. All group members' due recurring templates are now instantiated, not just the current user's.
- **M-09** — `ExpenseService.iso8601Formatter`: marked `nonisolated(unsafe) private static let` to satisfy Swift 6 strict concurrency (`ISO8601DateFormatter` is not `Sendable`).
- **M-11/M-51** — `ReceiptViewModel.grandTotal`: now reads user-edited `totalAmount` string first (`Decimal(string:) ?? itemSum+tax+tip`) so manual corrections propagate to `AddExpenseView`.
- **M-17** — `GroupStatsView.memberData`: deduplicates nil-payerID entries ("Unknown", "Unknown (2)", …) using a counter to prevent duplicate chart IDs that crashed SwiftUI Charts.
- **M-21** — `GroupService.removeMember`: uses `.select("user_id")` to detect silent RLS no-ops (0 rows ⇒ throws "Only the group creator can remove other members."); migration 028 adds the required creator DELETE policy on `group_members`.

## Medium Defect Fixes (2026-05-07)

All 62 Medium severity defects from the senior developer audit (DEFECT_REPORT.md) fixed:

### ViewModels
- **M-01** — `AddExpenseViewModel.recomputeSplits()`: zeros all split amounts when total ≤ zero before returning.
- **M-02** — `AddExpenseViewModel.canSave`: added `&& splitValidationError == nil` guard.
- **M-03** — `AddExpenseViewModel.amount`: locale-safe Decimal parse tries `en_US_POSIX` first, then comma→dot fallback.
- **M-04** — `GroupViewModel`: `isComputingBalances` flag prevents concurrent balance recomputes.
- **M-05** — `GroupViewModel.recordSettlement withThrowingTaskGroup`: uses `[weak self]` + `guard let self`.
- **M-06** — `HomeViewModel.unarchiveGroup`: captures original index, re-inserts on catch (rollback on failure).
- **M-07** — `HomeViewModel`: `isComputingBalances` guard before widget cache write.
- **M-08** — `AuthViewModel.toggleMode()`: only clears errorAlert when `!isLoading`.
- **M-10** — `ProfileViewModel`: `isEditing: Bool`; `load()` skips display-field update when `isEditing`.
- **M-13** — `ActivityViewModel.markAllRead()`: sets `unreadCount = store.unreadCount()` instead of hardcoded 0.
- **M-14** — `ReceiptViewModel`: two-step struct mutation replaced with single `var updated` assignment.

### Services & Core
- **M-17** — `GroupService.groupChanges`: inner Task handles retained + cancelled in `continuation.onTermination`.
- **M-18** — `FriendService`: documented fire-and-forget Task; added `fetchProfiles(ids: Set<UUID>)`.
- **M-19** — `AppLockService.migrateFromUserDefaultsIfNeeded()`: changed from `nonisolated` to `@MainActor`.
- **M-20** — `AuthService.fetchProfile`: catch block uses `isNotFoundError` helper; network/RLS errors rethrown.
- **M-21** — `CommentService`: push preference key reads from App Group UserDefaults (`group.com.vijaygoyal.xbill`).
- **M-22** — `VisionService.processScan`: runs `checkImageQuality` per page; skips on failure, doesn't throw.
- **M-23** — `ExportService.generateCSV`: `df.locale = Locale(identifier: "en_US_POSIX")`.
- **M-24** — `ExportService.generatePDF`: column layout adjusted to fit 499pt content width (Date 48/Title 150/Category 100/Amount 80/PaidBy 120).
- **M-27** — `NotificationStore.merge`: deduplicates within `newItems` via `var seen = Set<UUID>()` before merging.
- **M-28** — `NotificationItem.settlement` factory: generates deterministic UUID from djb2-style hash of fromUserID+toUserID+amount with RFC-4122 version/variant bits — stable across launches for deduplication.
- **M-29** — `KeychainSessionStorage.retrieve`: `errSecInteractionNotAllowed` now throws `NSError` (transient) instead of returning nil (sign-out).
- **M-30** — `AppError`: `CancellationError` detected and mapped to `.unknown("cancelled")`; `isSilent` catches both.
- **M-32** — `supabase/migrations/025_medium_fixes.sql`: `send_friend_request` checks both directions (A→B OR B→A) before inserting to prevent bidirectional duplicates.
- **M-33** — `supabase/migrations/025_medium_fixes.sql`: `lookup_profiles_by_email` RPC omits `email` from RETURNS TABLE and SELECT list.
- **M-42** — `FriendService.fetchProfiles(ids:)`: new method for FriendsView to batch-fetch profiles.
- **M-62** — `supabase/functions/invite-member/index.ts`: optional `joinToken` in body; email HTML includes `xbill://join/<token>` deep-link button + App Store fallback.

### Views
- **M-35** — `GroupDetailView`: empty state message conditional on searchText vs filterCategory.
- **M-36** — `GroupDetailView`: `.searchable` moved to outermost ZStack.
- **M-37** — `InviteMembersView`: `isValidEmail` uses regex `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`.
- **M-38** — `InviteMembersView`: button title "Send Invites" when empty; "Send N Invite(s)" otherwise.
- **M-39** — `AppLockView`: `isAuthenticating` guard prevents concurrent LAContext calls.
- **M-40** — `ActivityView`: grouping key uses `yyyy-MM-dd` + `en_US_POSIX`; display header uses locale-formatted abbreviated date.
- **M-41** — `ProfileView`: `@State private var lockService = AppLockService.shared` for proper @Observable observation.
- **M-42** — `FriendsView.loadAll()`: uses `friendService.fetchProfiles(ids:)` instead of direct Supabase query.
- **M-43** — `AddFriendView`: `.onDisappear { searchTask?.cancel() }`.
- **M-44** — `ReceiptScanView`: `@State private var photoTask` with cancel-before-assign pattern.
- **M-45** — `ReceiptReviewView.ItemRow`: `.onChange(of: item.unitPrice)` keeps `priceText` in sync.
- **M-48** — `GroupListView`: search bar hidden in completely empty state.
- **M-49** — `GroupListView`: `ContentUnavailableView` for no search results.
- **M-50** — `QuickAddExpenseSheet`: proper do/catch with `@State var memberLoadError` and alert.
- **M-51** — `GroupInviteView`: `ContentUnavailableView` when QR generation fails.
- **M-52** — `MyQRCodeView`: `@State private var qrImage` generated once in `.task`.
- **M-53** — `GroupInviteView` + `MyQRCodeView`: `private static let ciContext = CIContext()` shared instance.
- **M-54** — `GroupStatsView`: `monthlyData.count >= 1` (was `> 1`).
- **M-55** — `CreateGroupView.canCreate`: validates `inviteEmail` with same regex when non-empty.

### Tests
- **M-46** — `P1NotificationTests`: `clearAll()` in setUp/tearDown of each NotificationStoreTests test; limitation documented; `settlementFactory` test updated to verify deterministic ID (M-28) instead of `item.id == suggestion.id`.
- **M-47** — `P2FeatureTests`: balance tolerance tightened from 0.01 to 0.001.
- **M-56** — `SplitCalculatorTests`: `equalSplitAllExcluded` test added.
- **M-57** — `SplitCalculatorTests`: `percentageSplitUnderSum` + `percentageSplitOverSum` tests added.
- **M-58** — `SplitCalculatorTests`: CircularDebt uses `XCTAssertNil` / explicit nil check.
- **M-59** — `GroupFlowUITests`: `app.buttons["Cancel"].firstMatch.tap()` replaces normalized coordinate tap.
- **M-60** — `OnboardingUITests`: `app.secureTextFields["Password"]` / `app.secureTextFields["Confirm Password"]`.
- **M-61** — `OnboardingUITests`: Added `XCTAssertTrue(signInButton.isEnabled)` after valid input.
- **M-62** — `GroupFlowUITests`: Added `test000SignInWithEnvironmentCredentials()` and helpers to sign in through the email auth UI when `XBILL_TEST_EMAIL` / `XBILL_TEST_PASSWORD` are supplied by environment or test-bundle metadata. No credentials are stored in source; `project.yml` excludes the ignored local `UITestCredentials.plist` from the test target, and the 2026-07-14 coverage runner can read that local plist into environment/build settings without bundling it as a resource.
- **M-63** — Superseded by 2026-07-12 regression work. Earlier `GroupFlowUITests` verification on 2026-06-09 signed in but skipped deeper tests due to brittle tab selectors. The current `RegressionUITests` suite uses the dedicated UI-test route harness for feature flows and a separate real-tab-shell smoke test; latest verification passed 9 selected tests with 0 failures and no expected pending skips on 2026-07-12.
- **M-64** — `NotificationStoreTests`: `NotificationStore` now supports custom `itemsKey` / `lastViewedKey` initialization. Persistence tests use per-test keys to avoid parallel Swift Testing races with `ActivityViewModelUnreadTests` clearing `NotificationStore.shared`; fixed intermittent `mergePreservesReadState()` failure. Final full `xcodebuild test` on iPhone 17 iOS 26.5: `119` passed, `17` skipped, `0` failed.

### Pending backend deploys
- Migration 025 (`send_friend_request` dedup + `lookup_profiles_by_email` email redaction): `supabase db push`
- Updated `invite-member` Edge Function (join token deep-link): `supabase functions deploy invite-member`

## App Store Compliance
- `PrivacyInfo.xcprivacy` added to both `xBill/` and `xBillWidget/` targets (required since May 2024). Declares: `NSPrivacyTracking: false`, collected data types (email, name, financial info, photos/videos, contacts, device ID), `UserDefaults` required-reason `CA92.1`. **Contacts added 2026-05-02** (automated scanner blocker).
- `ITSAppUsesNonExemptEncryption: false` added to `Info.plist` (app uses only standard OS TLS — no custom crypto).
- `delete-account` Edge Function: **ACTIVE (v6)** — deployed 2026-04-16. Not a pending TODO.

## Security — Additional Fixes (2026-05-02)

### C1 — Supabase credentials moved out of project.yml ✅
- Created `Secrets.xcconfig` (gitignored) — holds `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
- Created `Secrets.xcconfig.example` (committed) — template with placeholder values.
- Created `.gitignore` — excludes `Secrets.xcconfig` from git.
- Updated `project.yml`: removed credentials from `settings.base`; added `settings.configFiles` pointing to `Secrets.xcconfig` for both debug and release configurations.
- Info.plist continues to reference `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` build settings — no Swift changes needed.

### H1 — JWT auth guard on 4 notification Edge Functions ✅
- All four functions (`notify-expense`, `notify-settlement`, `notify-comment`, `notify-friend-request`) now call `requireAuth(req)` before processing. `requireAuth` extracts `Authorization: Bearer <jwt>`, calls `adminClient.auth.getUser(jwt)`, returns 401 on failure. No iOS client changes needed — `supabase.functions.invoke()` automatically sends the user JWT when authenticated.

### H4 — JWT auth guard on invite-member Edge Function ✅
- `invite-member/index.ts` now calls `requireAuth(req)` at the top of the handler, returning 401 for unauthenticated requests. Prevents unauthenticated email spam via xBill's Resend account.

### M1 — search_profiles no longer returns email column ✅
- **`supabase/migrations/021_fix_search_profiles_no_email.sql`** — `CREATE OR REPLACE FUNCTION search_profiles` removes `email` from RETURNS TABLE and SELECT list. Email is still used in the `WHERE` clause so searching by email address still works; the address is just never sent back.
- **`xBill/Services/FriendService.swift`** — `searchProfiles` `Row` struct drops the `email` field; User constructed with `email: ""` (display-only, never shown from search results).

### M4 — CORS wildcard replaced on all Edge Functions ✅
- All 5 Edge Functions: `corsHeaders['Access-Control-Allow-Origin']` changed from `'*'` to `SUPABASE_URL` (the project's own domain). Mobile app calls are unaffected (iOS does not send Origin headers).

### L1 — appLockEnabled moved from UserDefaults to Keychain ✅
- **`xBill/Services/AppLockService.swift`** — `isEnabled` getter/setter now reads/writes `KeychainManager.Keys.appLockEnabled` via `KeychainManager.shared`. Key uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — backup-excluded, device-bound.
- **Migration path**: `migrateFromUserDefaultsIfNeeded()` (called from `init()`) reads the old `appLockEnabled` UserDefaults key, writes it to Keychain, then removes the UserDefaults key. Silent no-op on fresh installs.
- **`xBill/Core/KeychainManager.swift`** — Added `Keys.appLockEnabled = "app_lock_enabled"`.
- **`xBillTests/SecurityFixTests.swift`** (new) — 14 new tests: `AppLockKeychainTests` (5, `.serialized`), `SearchProfilesEmailTests` (3), `KeychainManagerBoolTests` (4). All pass.

## Security — Hard Blockers Fixed (2026-05-02)

### M5 — Privacy manifest Contacts gap ✅
- Added `NSPrivacyCollectedDataTypeContacts` to `xBill/PrivacyInfo.xcprivacy`. App uses `CNContactPickerViewController`; omission would cause automated scanner rejection at upload time.

### M3 — App Lock silent bypass ✅
- **`xBill/Services/AppLockService.swift`** — `authenticate()` now sets `isEnabled = false` (in addition to `isLocked = false`) when `canEvaluatePolicy` fails. Devices with no passcode auto-disable App Lock rather than appearing protected while unlocking silently.

### M2 — Spotlight exposes financial data ✅
- **`xBill/Services/SpotlightService.swift`** — Removed `indexExpenses` and `removeExpense`; replaced with `removeAllExpenses()` (deletes by domain). Expense titles contain amounts and categories visible from lock screen.
- **`xBill/ViewModels/GroupViewModel.swift`** — Removed `SpotlightService.indexExpenses(...)` call.
- **`xBill/xBillApp.swift`** — One-time startup migration: calls `SpotlightService.removeAllExpenses()` guarded by `spotlightExpensesCleared_v1` UserDefaults flag.

### H2 — Session tokens in device-only Keychain ✅
- **`xBill/Core/KeychainSessionStorage.swift`** (new) — Implements `AuthLocalStorage` using `KeychainManager`. `KeychainManager.save` now sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — sessions are never in backups and cannot be migrated to another device.
- **`xBill/Core/SupabaseClient.swift`** — `SupabaseClientOptions.AuthOptions(storage: KeychainSessionStorage(), ...)`. Replaces SDK default which used `kSecAttrAccessibleAfterFirstUnlock` (backup-eligible).

### H3 — Financial data encrypted in App Group UserDefaults ✅
- **`xBill/Core/KeychainManager.swift`** — Added `cacheEncryptionKey()`: generates/persists a `SymmetricKey(size: .bits256)` in Keychain with `ThisDeviceOnly` access.
- **`xBill/Services/CacheService.swift`** — Added `static encrypt/decrypt` (AES-GCM via CryptoKit). Private `save<T>` and `load<T>` helpers now encrypt before write and decrypt after read. Balance keys (`xbill_net_balance/owed/owing`) intentionally left unencrypted — widget-readable summary data.
- **`xBill/Services/NotificationStore.swift`** — `loadAll` and `merge` updated to call `CacheService.decrypt/encrypt`. Smooth migration: `decrypt` falls back to raw data if stored value was written unencrypted (first launch after update).
- **All 74 existing tests pass** after these changes.

## Security — Low Findings Fixed (2026-05-02)

### C2 — Apple developer credentials removed from generate_apple_secret.js ✅
- `generate_apple_secret.js` — `TEAM_ID`, `KEY_ID`, `CLIENT_ID`, `KEY_FILE` replaced with placeholder strings; the existing guard at line 16 will reject placeholders and prompt the user to fill them in before running.

### L2 — PayPal username alphanumeric validation ✅
- **`xBill/Services/PaymentLinkService.swift`** — `paypalLink(to:amount:currency:)` now guards with a regex `^[a-zA-Z0-9._-]+$` before building the URL; returns `nil` for usernames containing spaces, `@`, `%`, path characters, or empty strings.
- **`xBillTests/SecurityFixTests.swift`** — 7 new tests in `L2 — PayPal username validation` suite covering valid/invalid username cases.

### L3 — Deno std pinned version upgraded ✅
- All 5 Edge Functions (`notify-expense`, `notify-settlement`, `notify-comment`, `notify-friend-request`, `invite-member`) updated from `std@0.168.0` to `std@0.224.0`.

### L4 — GCC_GENERATE_DEBUGGING_SYMBOLS made per-config ✅
- **`project.yml`** — Removed `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` from global `settings.base`. Added explicit `GCC_GENERATE_DEBUGGING_SYMBOLS: YES` to the `debug` config and `GCC_GENERATE_DEBUGGING_SYMBOLS: NO` to the `release` config. Any future config added requires an explicit opt-in.

### L5 — APNs userInfo trimmed to routing-only IDs ✅
- **`notify-expense/index.ts`** — Removed `expenseId` from the APNs payload `userInfo`; `groupId` retained for notification-tap navigation.
- **`notify-settlement/index.ts`** — Removed `settlementId` from the APNs payload `userInfo`; `groupId` retained.
- **`notify-comment/index.ts`** — Removed `expenseId` from the APNs payload `userInfo`; `groupId` retained.
- **`notify-friend-request/index.ts`** — `fromUserID` retained (needed to preload `AddFriendView` on notification tap); no other IDs removed.

## Expense Model Notes
- `Expense.payerID` CodingKey maps to `"paid_by"` (DB column name, not `"payer_id"`)
- `Expense` does NOT have an `updatedAt` field — DB column does not exist; do not add it to previews or tests
- `ExpenseService.createExpense` uses `add_expense_with_splits` RPC (atomic); splits are encoded as `[RPCSplitParam]` with CodingKeys `p_*` prefix

## Recent Fix Log — 2026-06-09

### M-70 — Member history, backend alignment, and final review cleanup
- Added migration `supabase/migrations/036_member_history_and_paypal_handle.sql`, deployed to project `rhdhazevigbchmwzesok` on 2026-06-12/2026-06-13. Local and remote migration history now match through version 036.
- Backend now stores PayPal.me usernames in `profiles.paypal_handle`. The app decodes legacy `paypal_email` for compatibility but writes the new `paypal_handle` field.
- `group_members` now keeps historical membership state with `is_active`, `removed_at`, `display_name_snapshot`, and `avatar_url_snapshot`. Member removal deactivates access instead of deleting history.
- Added RPCs `add_or_reactivate_group_member(...)` and `deactivate_group_member(...)`; invite acceptance reactivates existing inactive memberships instead of failing on conflict.
- Active membership now gates group access and invite visibility, while historical members can still render names/avatars for old expenses, splits, activity rows, and balances.
- Group Detail now shows active vs historical member counts, disables removal for inactive members, and uses active members for new expenses.
- Home balances and Recent Activity now fetch historical members where needed so older expense history does not degrade when someone is removed.
- PayPal naming cleanup: app logic now uses `paypalHandle`/PayPal.me semantics while keeping a compatibility alias for older model call sites.
- Review/privacy cleanup: updated `APPSTORE_REVIEW_PLAN.md` and `web/privacy/index.html` for OCR-only receipts, avatar deletion, retained shared expense history, payment handles, and historical membership snapshots.
- UI test hardening: `GroupFlowUITests.testActiveGroupShowsArchiveNotUnarchive` now uses the same 6-second detail readiness wait as the shared helper.
- Verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'` succeeded before deployment on 2026-06-12.
- Regression: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -only-testing:xBillTests` succeeded on 2026-06-13 after the PayPal handle model rename.
- UI regression: full `GroupFlowUITests` exposed one short-wait failure; after patching, the targeted failing test passed on 2026-06-13.
- Simulator: current build installed on iPhone 17 Pro iOS 26.5 simulator `CA2078AC-6559-4BF3-93CB-370CF27E92EA`.

### M-69 — Senior review findings remediation pass
- Payment links no longer use settlement display names as Venmo/PayPal identifiers. `PaymentLinkService.paymentLink` now requires the recipient `User` and only generates links from saved, valid handles.
- PayPal profile entry now uses PayPal.me handle semantics instead of email validation; saved Venmo/PayPal handles are normalized by removing a leading `@`.
- Group currency is locked after the first expense. Name/icon edits remain available, but currency changes are blocked to avoid relabeling historical amounts without conversion.
- Member removal now checks financial history before deleting group membership. Members who have paid expenses or appear in splits are retained as historical members so settlement/history names stay intact.
- Recurring expense instantiation moved to backend RPC `create_recurring_expense_instance(...)` via migration 034, atomically claiming the template occurrence, creating the one-off instance, copying splits, and advancing `next_occurrence_date`.
- Added migration 035 to preserve `splits.user_id` values when an auth account is deleted, preventing split rows from being cascaded away and changing shared group history.
- Home balance refresh now falls back to cached expenses/members with a stale-data warning instead of caching fake zero balances on fetch failure.
- Quick Add now opens with cached members when live member fetch fails.
- Receipt scanner delegate now updates bindings on the main actor.
- Recent Activity UI copy now describes the current surface as recent expense/settlement activity rather than a complete audit log.
- Account deletion Edge Function now also removes the user's avatar object from Supabase Storage; delete confirmation copy clarifies retained shared expense records.
- Added backend migrations: `supabase/migrations/034_recurring_instance_rpc.sql` and `supabase/migrations/035_preserve_splits_on_account_delete.sql`.
- Verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'` succeeded on 2026-06-12.
- Regression: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -only-testing:xBillTests` succeeded on 2026-06-12.
- Deployment: `supabase db push` applied migrations 034 and 035 to project `rhdhazevigbchmwzesok` on 2026-06-12; `supabase functions deploy delete-account` deployed the avatar-cleanup function update. Added local no-op `031_remote_history_placeholder.sql` because remote migration history already contained version 031 and the local file was missing.

### M-68 — Receipt scan product decision: OCR-only
- Product decision: receipt scanning is OCR-only. Images are used temporarily for Vision/OCR and are not uploaded or attached to saved expenses.
- Removed the unused `ExpenseService.uploadReceiptImage(_:expenseID:)` Supabase Storage helper.
- `ExpenseService.createExpense(...)` now always sends `p_receipt_url = nil`, preserving the existing backend RPC shape while making saved expenses image-free.
- Updated Add Expense / Receipt Scan copy from attachment-style wording to OCR analysis wording.
- Updated `APPSTORE_REVIEW_PLAN.md` so privacy review treats receipt images as temporary OCR inputs unless receipt attachment is deliberately added later.
- Verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'` succeeded on 2026-06-12.

### M-67 — UI/Product audit implementation pass
- Senior UI audit found Home lacked orientation and global quick actions, Add Expense hid receipt scanning too low in a long form, Group Detail hid management actions behind a dense menu, Alerts/Notifications naming was inconsistent, offline actions disappeared without explanation, group/member management UI was incomplete, and Profile payment handles lacked validation feedback.
- Implementation target: keep backend schema unchanged, reuse existing `QuickAddExpenseSheet`, `GroupService.updateGroup`, `GroupViewModel.removeMember`, invite email/link views, and design-system components.
- Implemented Home dashboard orientation and visible quick actions for Add Expense / Scan Receipt with offline or missing-group disabled copy.
- Moved Add Expense receipt scanning into a primary top callout so users do not have to reach the bottom of the form to scan.
- Added Group Detail `Manage` entry points and a `GroupSettingsView` sheet for editing group name/icon/currency, inviting by email/link, viewing members, and owner-only member removal.
- Kept Add Expense visible on Group Detail while offline and now shows a clear offline error instead of silently hiding the action.
- Renamed Alerts/Notifications surfaces to `Activity` consistently and added an All/Unread activity filter.
- Added Friends search and Profile payment-handle validation for Venmo/PayPal before save.
- Verification: `xcodebuild build -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA'` succeeded on 2026-06-12.
- Regression: `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -only-testing:xBillUITests/GroupFlowUITests` passed `17` tests / `0` failures on 2026-06-12.

### M-65 — GroupFlowUITests iOS 26 simulator accessibility investigation
- Added DEBUG-only Groups startup path in `ContentView` while investigating iOS 26/XCTest tab-bar issues; explicit simulator install verified the Debug app can mount `GroupListView` directly.
- Added accessibility identifiers to native `MainTabView` tab labels and group/create controls, plus active/archived group row labels in Home/Groups.
- Added a DEBUG-only UIKit hit target over the Groups create button to try to give XCTest a real `UIButton` accessibility element.
- Updated `GroupFlowUITests` to launch with Groups startup flags, tolerate the simulator already being signed in, and use fallback coordinates when XCTest cannot find SwiftUI elements.
- Historical note: `testCreateGroupSheetOpens` previously failed on iPhone 17 / iOS 26.5 because XCTest did not expose/tap the visible Groups header/create elements. This was later addressed by the dedicated route harness and the 2026-07-11 `RegressionUITests` suite, which passed end-to-end create/expense/archive/unarchive flows.

### M-66 — Dedicated UI test route harness for iOS 26 simulator instability
- Added a `UITesting` Xcode build configuration and switched the shared scheme's `TestAction` to use it. The app target compiles test runs with `DEBUG UI_TESTING`.
- Added a runtime-gated DEBUG route harness in `ContentView` activated only by `--uitesting` / `XBILL_UITESTING`. Normal Debug launches still render `MainTabView`; UI tests can start directly on `groups`, `createGroup`, `createGroupThenOpen`, or `firstGroupDetail`.
- Removed the DEBUG-only invisible UIKit create-button overlay from `GroupListView`; `GroupListView` now has explicit launch-presentation options used by the harness to present Create Group or open a newly created group deterministically.
- Updated `GroupFlowUITests` to use `--uitest-route`, fixed `groupSurfaceExists` so it no longer always returns true, and made create-form tests start from the presented Create Group screen.
- Added an iOS 26-safe archive confirmation cancel helper that searches all accessibility element types before using an outside-sheet dismissal tap.
- Verification on 2026-06-11, iPhone 17 Pro iOS 26.5 (`CA2078AC-6559-4BF3-93CB-370CF27E92EA`): `xcodebuild test -project xBill.xcodeproj -scheme xBill -destination 'platform=iOS Simulator,id=CA2078AC-6559-4BF3-93CB-370CF27E92EA' -only-testing:xBillUITests/GroupFlowUITests` passed `17` tests / `0` failures.
- Rationale: XCTest on iOS 26.5 can visually render SwiftUI screens while failing to expose/tap the tab bar and native confirmation-dialog cancel action consistently. The harness bypasses fragile setup navigation while keeping the actual feature screens and backend service flows under test.

## Group Flow — Fixed Issues (audited 2026-04-28, all fixed same day)

### Group Creation (all fixed)
- **Dead invite-email UI** — Fixed: `create()` now calls `GroupService.inviteMembers` after group creation if the field is non-empty. Invite errors are non-fatal (`try?`) so they don't block group creation.
- **`onCreated` ignores the returned group** — Fixed: `GroupListView` now appends `newGroup` to `vm.groups` directly and calls `SpotlightService.indexGroups` — no extra network round-trip.
- **Currency picker hard-coded subset** — Fixed: `CreateGroupView.currencies` now uses `ExchangeRateService.commonCurrencies` (20 currencies).
- **`currentUserID` placeholder** — Fixed: `GroupListView.navigationDestination` now guards `if let userID = vm.currentUser?.id` and only renders `GroupDetailView` when the user is confirmed loaded.

### Archive Flow (all fixed)
- **Stale active list + archived list after archiving (P0)** — Fixed: `GroupDetailView` takes `onGroupStatusChanged: (() async -> Void)?`. After a successful archive or unarchive, the callback is awaited before `dismiss()`, triggering `vm.refresh()` + `vm.loadArchivedGroups()` in `HomeViewModel`.
- **"Archive Group" shown for already-archived groups** — Fixed: Toolbar now checks `vm.group.isArchived` and shows "Unarchive Group" / "Archive Group" accordingly.
- **No unsettled-balance warning before archiving** — Fixed: Archive confirmation dialog message now includes unsettled-balance count when `!vm.settlementSuggestions.isEmpty`.
- **Cache not invalidated on archive** — Fixed: `GroupViewModel.archiveGroup()` removes the group from `CacheService` after a successful DB update; `unarchiveGroup()` appends it back.

### De-Archive Flow (all fixed)
- **`GroupViewModel.unarchiveGroup()` was dead code** — Fixed: Wired to "Unarchive Group" button in `GroupDetailView` toolbar (shown only when `vm.group.isArchived`), with its own confirmation dialog. `onGroupStatusChanged` callback triggers `HomeViewModel` refresh on success.
- **Realtime misses archive-only changes** — Fixed: `GroupService.groupChanges` now subscribes to both `group_members` and `groups` tables on the same channel using two concurrent `Task` loops. Either table change triggers a yield to the caller.

### Service Layer (fixed)
- **Client-side archived filter** — Fixed: `fetchGroups` and `fetchArchivedGroups` now use a two-step approach (`memberGroupIDs` → `groups` with `is_archived` filter) matching the existing `fetchMembers` pattern. Filtering now happens server-side via `.eq("is_archived", value: false/true)` on the `groups` table.
