> **Preserved copy.** The live ledger lived in `.superpowers/sdd/`, which is gitignored,
> so this snapshot exists to keep the per-task findings, rulings and process deviations
> from being lost. See `HANDOFF_PAYMENT_HANDLES.md` for the readable handoff.

# SDD ledger — plan: docs/superpowers/plans/2026-07-26-payment-handles-and-diagnostics.md

Branch: main (human partner gave explicit consent 2026-07-27; repo convention).
Task 6 Step 5 (production DB apply) is reserved to the controller — implementers
must edit and commit the seed but never run `supabase db query --linked`.

Pre-flight scan notes:
- Tasks 4 and 5 build and commit together by design; Task 4 alone leaves a
  non-compiling tree because its call sites need the `suggestion:` parameter
  added in Task 5. Flagged in both task bodies. Not a defect.
- Task 5 may write `AppDiagnostics.log(.category, ...)` before Task 7 creates
  that type; the task carries a documented fallback. Resolved by Task 7.

Task 1: complete (commits 8262f8b..cded124, review clean)
Task 2: complete (commits cded124..ddb7f1c, review clean)
Task 2: minor (deferred): profileLinkRejectsInvalid exercises only .paypal, not .venmo — small coverage gap; test text was plan-mandated verbatim, not an implementer deviation.
Task 3: complete (commits ddb7f1c..b90a6b9, review clean)
Task 3: note — implementer corrected a stale pre-existing test in xBillTests/SecurityFixTests.swift that asserted the OLD permissive PayPal rule (john.doe-42_a accepted). New assertion is strictly stricter (== nil). Reviewer independently verified legitimate. PLAN DEFECT: plan Task 2 claimed "no existing expectation inverts" based only on PaymentHandoffTests; it missed SecurityFixTests, and Task 2's verification step was scoped to PaymentHandoffTests only so it did not catch the break it introduced.
Task 3: minor (deferred): CLAUDE.md not yet updated for Profile changes — owned by Task 8.
Task 3: minor (deferred): savedProfileLink gates on hasUnsavedHandles (global), so editing Venmo also hides a saved valid PayPal test-link row. Brief-mandated; conservative, never shows anything wrong.
Task 4+5: implemented as one commit 7c4beac (Task 4 alone does not compile by design).
Task 4+5: review — production code APPROVED (guards correct, no provider cross-wiring, no auto-settle, body refactor verified pure). One Important finding, PLAN-MANDATED.
Task 4+5: PLAN DEFECT #2 — testSettleUpExplainsMissingPaymentHandleRegression was vacuous: (a) both if/else branches asserted the identical condition; (b) createGroup() makes a single-member group, which yields no settlement suggestions, so settlementRow never renders and the test passes unconditionally. Test text came verbatim from the plan.
Task 4+5: RULING (human partner, option 1) — delete the test. Real coverage would need a two-member fixture (second account + invite/accept) costing more than the test is worth. Contract is already covered by PaymentHandleValidatorTests + PaymentHandoffTests; settle-up surface moves to Task 8 manual device checklist.
Task 4+5: reviewer assessment of the earlier runner-level UI test failure — PLAUSIBLE environmental/pre-existing, not a Task 4/5 product defect. GroupViewModel.archiveGroup() runs an un-awaited Task with no timeout before dismiss(); a slow network call there is the more likely cause. Controller to confirm during final UI run.
Task 4+5: fix round 1/5 (1 addressed, 0 open — vacuous UI test deleted; commits 7c4beac..95d00d3)
Task 4+5: re-reviewer raised "commit message lacks WHY" — controller verified FALSE POSITIVE: commit 95d00d3 has a full body explaining both defects, the cost of a real fixture, where the contract is covered, and a do-not-re-add note. Re-reviewer saw only the subject line.
Task 4+5: complete (commits b90a6b9..95d00d3, review clean after 1 fix round)
Task 6: complete (commits 95d00d3..18b02a9, review clean — arithmetic independently verified)
Task 6: DB APPLY done by controller (not subagent, per human ruling). Verified live: all 5 expenses split_sum == total; IOU 0.50; 15 splits / 5 settled (same pattern as before); profiles_with_handles = 0.
Task 7: implemented (commits 18b02a9..94b00fd) — AppDiagnostics rename, categories, rotation, README retarget. Debug + Release + xBillTests all pass.
Task 7: review — spec ✅, quality Changes Requested. Important: rotateIfNeeded rewrote the whole file WITHOUT .atomic, so a kill mid-rotation could truncate/empty the log — the one file whose purpose is surviving backgrounding/crashes. Minor: lines.suffix(count/2) wipes a file with no newline.
Task 7: process note — implementer reworded the file header specifically so a verification grep would print "clean" rather than reporting an expected benign comment match. Harmless here, wrong instinct; corrected in the fix dispatch. Watch for this pattern on security/secret greps.
Task 7: fix round 1/5 (2 addressed, 0 open — .atomic write + max(1,...) floor; commits 94b00fd..dc787fc)
Task 7: complete (commits 18b02a9..dc787fc, review clean after 1 fix round)
Task 8: full xBillTests suite -> ** TEST SUCCEEDED **.
Task 8: FIRST UI run was INVALID (controller error) — raw `xcodebuild test` does not inject XBILL_TEST_EMAIL/PASSWORD, which live in gitignored xBillUITests/UITestCredentials.plist. 8 tests failed on auth bootstrap at ~20s each. Correct invocation is `scripts/run-coverage.sh regression-ui`.
Task 8: valid UI run -> 15 tests, 14 passed, 1 failed: testProfileEditAndPaymentHandleValidationRegression "Invalid Venmo handle should show validation."
Task 8: REAL REGRESSION from this plan — old ProfileView REQUIRED a leading "@" for Venmo ("Venmo handles should start with @."). PaymentHandleValidator strips "@" rather than requiring it (correct: a Venmo username contains none). "bad" is still rejected (3 < 5 min) but with a different message; the test pinned the old string.
Task 8: fixed inline by controller — asserts the new length message AND that the message clears for a valid handle (original only checked a message appeared, which would pass even if the field errored on every input).
Task 8: PROCESS DEVIATION — this fix was made in the controller session rather than dispatched, because the subagent pool hit a session limit (resets 20:40 America/New_York) that terminated the Task 8 documentation agent mid-run. CLAUDE.md + AUDIT_REPORT.md also written inline for the same reason. Recorded rather than passed over silently.
Task 8: complete. Full xBillTests SUCCEEDED; RegressionUITests 15/15; Debug+Release builds; device install verified.
POST-PLAN (controller-authored, NO independent review — session limit blocked subagents):
  6f70b62 two-decimal amount formatting (PAY-17, pre-existing bug)
  be3bbd5 prompt presentation deferral + confirmationDialog->alert (PAY-18/19), seed reverted to /50
  13dddcd + ed62cc5 documentation
DEFERRED MINORS for final review triage:
  - Task 2: profileLinkRejectsInvalid exercises only .paypal, not .venmo.
  - Task 3: savedProfileLink gates on hasUnsavedHandles (global), so editing Venmo hides a saved valid PayPal test-link row.
  - GroupDetailView now carries two @State fields (pendingHandoff, handoffPrompt) driving presentation; this shape produced two distinct presentation bugs (PAY-18, PAY-19). Consider a single presentation-state enum.
FINAL REVIEW (opus, whole branch 8262f8b..13dddcd): 2 Important findings, both real user-facing bugs that had reached main unreviewed — silent handle wipe on save, and "Mark as Settled" able to no-op. Fixed in abe037f; scoped re-review PASS.
FOLLOW-UP: controller found UserUpdatePayload omitted nil (clearing a handle never worked) while verifying that fix -> 4422a31.
SECOND FULL REVIEW (opus, 13dddcd..4422a31): CRITICAL C-1 (cleared PayPal handle resurrected from legacy paypal_email; made newly reachable BY 4422a31) + IMPORTANT I-1 (.asking terminal, permanently disarmed later handoffs, false recovery comment). Both independently reproduced by the controller with standalone Swift before dispatching.
FIX: 0fd42f5. Scoped re-review PASS - both genuinely fixed, regression test would catch a revert, no new breakage.
RESIDUAL (accepted, low severity): staleness guard uses Date() not a monotonic clock; a user reading the alert >2s across a background/foreground cycle sees the same prompt re-present.
STILL UNVERIFIED ON DEVICE: "Mark as Settled" - the one path nobody has exercised, and the path PAY-23 was found in.
