---
name: verifying-your-own-work
description: Use before claiming any change is done, verified, swept, or root-caused — and before writing a causal explanation into a comment, commit message, or report. Built from defects that reached real users of this project.
---

# Verifying your own work

Every rule here comes from a specific defect that **shipped to users of this app** or a wrong claim
that was written into this repository. None is hypothetical. Dates and IDs are included so the
evidence can be re-read.

The failures are not carelessness about details. Every one came from verifying the layer being
worked in and **assuming the boundary**, or from stating a conclusion broader than the evidence
gathered.

---

## 1. Verify the payload, not the contract

**SPLIT-04, 2026-08-24 — shipped in 1.3.** An RPC was tested against production with a hand-written
JSON body and passed. The app sent something different: Swift's synthesized `Encodable` **omits a
nil**, so an expense with no notes sent 7 keys instead of 8, and PostgREST — which resolves a
function by its exact key set — returned `PGRST202 Could not find the function`. Users hit a raw
error on the feature the release was named for.

- Testing a server contract proves nothing about what the client serialises.
- Assert the **encoded bytes** the client actually produces, using the encoder the transport really
  uses (`SupabaseManager.postgrestEncoder`), not one constructed in the test.
- Any optional in an RPC payload: use `encode`, never `encodeIfPresent`.

**Ask:** *Did I test the thing my code produces, or a thing I typed by hand?*

---

## 2. Every mode of a control needs a way to finish

**SPLIT-05, 2026-08-24 — present since 1.0.** A split-strategy picker offered four options. "By %"
had **no percentage input anywhere in the app**. Choosing it left every value at 0, validation said
*"Percentages must add up to 100. Currently: 0.00"*, and Save was permanently disabled. The split
*maths* was well tested; nobody checked the mode could be completed.

- After adding or changing a control with modes, walk **every** mode to a finished state.
- An option that traps the user is worse than an option that does not exist.

---

## 3. When you re-emit a function, every line in it becomes yours

**INV-07, 2026-08-24 — live defect, users could not rejoin a group.** `join_group_via_invite` was
rewritten **twice** (migrations 042 and 044) for unrelated reasons. Both rewrites carried through an
`IF NOT EXISTS` guard that ignored `is_active`, so a removed member's row was found, the insert
skipped, and the function **returned success having done nothing**.

- `CREATE OR REPLACE` means you are re-asserting the whole body. Re-derive every guard, not only
  the one you came for.
- **`EXISTS` against a soft-deleted table is almost always wrong.** Once rows are kept for history
  (`is_active`, `removed_at`, `deleted_at`), `NOT EXISTS(…)` silently means "no row in any state",
  which is rarely the question.
- A function that reports success while doing nothing is the worst failure mode available: no
  error, nothing logged, and the user's only evidence is an absence.

---

## 4. Never claim coverage you did not run

**UI-01 sweep, 2026-08-24.** After fixing a scroll bug in a shared component, the summary said *"the
other nine screens that share the component were checked and were fine."* **Two had been checked.**
The user asked "did you check Add Friend?" — it had not been, and neither had five others.

- Say exactly what was run: *"probed Manage Group, Create Group and Home; seven others not probed."*
- A global fix touching N screens is not evidence about N screens. It is evidence about the one you
  measured.
- If a sweep is worth claiming, it is worth encoding as one test that covers the whole set, so the
  claim and the evidence cannot come apart.

**Ask:** *Can I name each item I checked? If not, I did not check them.*

---

## 5. Do not write a cause you have not isolated

**UI-01, 2026-08-24.** A code comment and commit message stated the cause was "a `LazyVGrid` inside
a `LazyVStack`". `CreateGroupView` has that identical combination and was never affected. The
explanation was plausible, committed, and wrong — left in place it would have misled the next
reader into a false model of the component.

- A fix that works is evidence the fix works. It is **not** evidence of why.
- Isolate by mutation: put the bug back and see what fails. If a sibling passes with the bug
  present, the mechanism you named is not sufficient.
- Writing *"the precise trigger is not established"* is more useful than a confident wrong cause.

---

## 6. A verification step must not mutate what it inspects

**2026-08-22 — destroyed a completed App Store archive.** `plutil -extract KEY json FILE` writes the
extracted value **back over the file** unless the format is `raw` or `-o -` is given. Checking
`UIDeviceFamily` replaced a 2,199-byte `Info.plist` with 3 bytes, and every later check reported
keys as missing — indistinguishable from a broken build. The archive had to be rebuilt.

- Before running a command against a release artifact, know whether it writes.
- Read plists with `plutil -p` or Python `plistlib`. Never `plutil -extract … json FILE`.
- Related: **do not parse `plutil -p` output with grep/sed** — it misaligned values across
  neighbouring keys and reported `CFBundleShortVersionString` as `"iPhoneOS"`.

---

## 7. Prove the run you are reporting actually happened

Three separate false greens in one session:

- **A benchmark reported "no corpus" in 0.024s and passed.** The gate was an environment variable
  that never reached the test process. A gate that fails closed **and green** is worse than none.
- **Stale numbers reported as fresh.** A benchmark's output file was unchanged because the run had
  failed to launch; the numbers quoted were from a previous run whose timestamp looked current.
- **"Executed 0 test" alongside `TEST SUCCEEDED`.** That is XCTest's counter, which does not see
  Swift Testing cases. The suite had in fact run 7/7.

Before quoting a number:

- Record the newest artifact **before** the run; confirm a **new** one appeared after.
- Read the structured `.xcresult` summary, not the exit status and not a grep of stdout.
- Confirm the suite is present **by name** in the result bundle.

---

## 8. A build phase that succeeds into the wrong directory is silent

**2026-08-22 and 2026-08-23 — two variants.**

- A phase copied files into `$BUILT_PRODUCTS_DIR/…xctest`, but the bundle that runs is the copy
  embedded at `$TARGET_BUILD_DIR` (`App.app/PlugIns/`). The log said "bundled 22 images"; the test
  found none.
- The same phase wrote into the `.xctest` **after code signing**, invalidating the signature. The
  simulator then refused to launch the app entirely (`RequestDenied by SBMainWorkspace`), which
  silently made every simulator benchmark impossible **for a day**.

- Assert the artifact exists **where it is loaded from**, not where the script wrote it.
- Anything writing into a signed bundle must run before signing, or not at all.

---

## 9. Money never travels through a float literal — including in tests

**2026-08-23.** `SplitRescaleTests` failed against a *correct* implementation because the test wrote
`to: 73.29`. A `Decimal` from a float literal routes through `Double` and carries its error.
Production was safe (amounts parse from strings); the **test** was the unsafe path.

Use `Decimal(string:)` in assertions too.

---

## 10. An accessibility identifier is a contract, not an implementation detail

**2026-08-24.** Extracting a shared row renamed four identifiers, and a regression test that matched
them by prefix failed. Renaming one silently breaks every predicate that matches it.

Before renaming an identifier, grep the UI test target for it.

---

## 11. Do not call a failure a flake until the record says so

**2026-08-12.** `testArchiveUnarchiveRegression` failed, passed a re-run, and was logged as
transient. The bundle history showed 4/4 passes before the change and 2 failures in 3 runs after —
a real regression, from a missing `contentShape`.

Later the same test was intermittent again; the pattern turned out to be **simulator state**, and it
passed 2/2 after `simctl erase`.

- Check the historical record in past `.xcresult` bundles before classifying anything.
- **Erase the simulator before a release UI run.** Repeated heavy runs degrade it, and
  `OnboardingUITests` failing to bootstrap in the same run is the tell.

---

## 12. Ceremony that does not enforce anything is worse than none

**2026-08-23.** Migrations carried `REVOKE ALL ON FUNCTION … FROM PUBLIC`, which reads as a lock and
**is not one**: Supabase's `ALTER DEFAULT PRIVILEGES` grants EXECUTE to `anon` explicitly on every
new function in `public`, and revoking from `PUBLIC` does not remove an explicit grant. Nothing was
exposed — RLS refused anonymous callers — but the next reader would have believed the function was
restricted.

Related: **a guard that cannot fire is documentation wearing a conditional.** Two were written and
removed this session for that reason. Before adding a bound, name the input that triggers it; if
none plausibly does, delete it.

---

## 13. When they can reproduce it and you cannot, instrument their device

**UI-02, 2026-08-24.** Add Friend scrolled into blank space on the owner's phone. It could not be
reproduced on a simulator, and **three hypotheses were written and discarded** — a lazy container,
a contradictory toolbar pair, negative padding — each eliminated by a differential test only after
being proposed.

A DEBUG probe logging the scroll view's content height took minutes to write:

```
screen=AddFriend contentHeight=826 viewportHeight=874 ratio=0.9x
```

Content **shorter than the screen** cannot scroll — and it was still scrolling. That one number
eliminated the entire content tree at a stroke and proved the extra extent came from outside it: a
`safeAreaInset` built from an `EmptyView`, applied unconditionally by a shared container. Nothing
in the screen's own body could ever have shown it, because it is not in the body.

- Someone who can reproduce a bug on demand is the fastest instrument available. Use them early.
- Prefer a measurement that **eliminates a whole layer** over one that confirms a suspicion. "The
  content is shorter than the screen" was worth more than any number of candidate causes inside it.
- Three guesses is two too many. After the first hypothesis fails a differential test, stop
  theorising and go and measure.

---

## 14. A capability check cannot be an RLS policy on the thing being granted

**Three separate production defects, same rule.** Every flow whose *purpose* is to create a
relationship was gated on a policy that assumed the relationship already existed:

| | |
|---|---|
| `INV-01` | the group-invite preview read `group_invites`, restricted to creators and **existing members** — an invitee is neither |
| `INV-07` | `join_group_via_invite` guarded on `EXISTS(…)` ignoring `is_active`, so a **removed** member's row blocked their own rejoin |
| `INV-09` | the add-friend link resolved a profile through `profiles`, whose policy requires a **shared active group** — which a new friend never has |

Each presented identically to the user: the app opens, appears to work, and nothing happens.

- Route these through a `SECURITY DEFINER` function keyed on whatever the link carries. **Possession
  of the token or id is the capability.** Never widen the table policy.
- Return the minimum: `get_add_friend_preview` returns a name and avatar and **not email**.
- Revoke `anon` **by name** — Supabase's `ALTER DEFAULT PRIVILEGES` grants EXECUTE explicitly, and
  `REVOKE … FROM PUBLIC` does not remove an explicit grant (see rule 12).

**Check this first on any invite, share, or add flow.** Recognising the pattern took three
occurrences; the second and third were both found only by querying production directly rather than
trusting the client code to be doing something sensible.

---

## The check before saying "done"

1. Did I test what my code **produces**, or something I typed by hand?
2. Can I **name** every item I claim to have checked?
3. Am I asserting a **cause** I isolated, or one that merely sounds right?
4. Did the run I am quoting **actually happen** — new artifact, structured result, suite present by
   name?
5. Did any verification step **write** to what it inspected?
6. If I removed a guard or a filter, did I re-measure the things that were **already passing**?
   (`SCAN-15` was correct, its own tests passed, and it broke a receipt that had been fine.)

---

## The pattern under all of it

**Verifying the layer you worked in and assuming the boundary.**

The server contract was right and the client payload was wrong. The split maths was right and the
input was missing. The identity check was right and the guard below it was wrong. The fix was right
and the explanation was wrong.

In this project, **the great majority of defects that reached users were found by the owner using
the app, not by any suite** — four of six in 1.1, three in 1.3. That ratio has not improved through
more tests. It improves by getting builds onto a device sooner, and by not claiming more than was
measured.
