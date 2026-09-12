# Agent instructions — xBill

**Read `CLAUDE.md` → "Start here" before doing anything.** It is the authoritative guide and
is deliberately not duplicated here; a second copy would drift from it.

It gives you, in order: a reading order for a cold start, a document map saying which file
owns what (and what must never go in it), a trap index of behaviours that have already caused
real defects, and the checklist to follow when finishing a piece of work.

The four rules that are violated most often:

1. **`AUDIT_REPORT.md` is the single source for findings.** One row per defect: ID, file,
   issue, status, fix. Never restate a finding in another document.
2. **`diagnostics/README.md` is the only README under `diagnostics/`.** Dated folders hold raw
   evidence only. Append a row to the index; do not add a second README. (A `PreToolUse` hook
   in `.claude/settings.json` blocks this for Claude Code, but it cannot stop other tools.)
3. **Never claim device or lifecycle behaviour from a green test suite.** App Lock, Face ID,
   real app switches and push are not reachable from tests. Build, install on the physical
   device, have the user reproduce, then pull and read the log. Every serious defect in this
   project was found that way, with both suites green throughout.
4. **If a previous agent broke one of these, consolidate rather than extend.** Two documents
   describing one defect will drift, and the next reader may act on the stale one.

Do not deploy migrations or modify live Supabase data without explicit approval. Read-only
queries for diagnosis are fine and are often the fastest way to confirm a hypothesis.

Two more, both learned the expensive way in September 2026:

5. **A default argument that resolves to a `.shared` singleton is a hidden dependency on the
   machine.** 27 tests silently read the host's real network path and 14 the live Supabase session;
   the only symptom was a balance of zero, indistinguishable from broken arithmetic. The same
   applies to a **wall-clock timeout** inside code under test — see FLAKE-02/03/04/05.
6. **The symptom is not the diagnosis.** Two separate defects produced byte-identical error text;
   what told them apart was a test *duration* (48 s against 0.032 s for its own siblings). Check
   `xcresulttool get test-results test-details --test-id ...` before re-diagnosing a familiar
   message.

Current state lives in `CLAUDE.md` → "Release status". As of 2026-09-12: **v1.7 (9) approved and
live**, repo on **1.8 (10)** with PERF-01…04 and SCAN-PERF-01 landed and migration 059 deployed.
