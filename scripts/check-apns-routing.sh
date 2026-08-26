#!/bin/bash
# check-apns-routing.sh — structural guard for PUSH-02.
#
# The APNs host must be chosen from the RECIPIENT's token environment, never from the sender's
# build. That rule lived in four separate functions and was wrong in all four; this asserts it
# cannot quietly come back, and that no function is left behind when the others change.
#
# Run from the repo root. Exits non-zero on any violation.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FUNCS="notify-expense notify-settlement notify-comment notify-friend-request"
fail=0

note() { printf '  %s\n' "$1"; }
bad()  { printf '  ✗ %s\n' "$1"; fail=1; }

echo "APNs routing (PUSH-02)"

# 1. No function may pick a host from a request-body flag, or hardcode one at all.
for f in $FUNCS; do
    p="supabase/functions/$f/index.ts"
    [ -f "$p" ] || { bad "$f: index.ts missing"; continue; }
    if grep -q "isDevelopment" "$p"; then
        bad "$f: reads isDevelopment — the host must come from the recipient's token"
    fi
    if grep -q "push.apple.com" "$p"; then
        bad "$f: hardcodes an APNs host — it belongs in _shared/apns.ts"
    fi
done

# 2. Every function must route through the shared module, so one cannot drift from the rest.
for f in $FUNCS; do
    p="supabase/functions/$f/index.ts"
    grep -q "_shared/apns.ts" "$p" 2>/dev/null \
        || bad "$f: does not import _shared/apns.ts"
    # `deliver` is the entry point: it sends via sendToToken and, on BadDeviceToken, retries the
    # other environment and reports the one that worked. A function calling sendToToken directly
    # would send correctly but lose the self-correction, so require deliver by name.
    grep -q "await deliver(" "$p" 2>/dev/null \
        || bad "$f: does not send through deliver() — loses environment recovery"
done

# 3. Every function must actually select the column it routes on. Selecting without it yields
#    `undefined`, which falls back to production — silently wrong for every sandbox device.
for f in $FUNCS; do
    p="supabase/functions/$f/index.ts"
    # Match the select clause itself, not the word. A first version grepped for "environment"
    # anywhere in the file and passed against a function whose select had been reverted — the
    # explanatory comments contain the word. A guard that cannot fire is documentation.
    grep -qE "\.select\('token[^']*, *environment'\)" "$p" 2>/dev/null \
        || bad "$f: does not select device_tokens.environment — routing would fall back to production"
done

# 4. A token must be deleted only when APNs calls it Unregistered. Deleting on BadDeviceToken is
#    what destroyed working registrations whenever the environment mismatched.
# Match the string literal, not the word: the explanatory comments name it deliberately.
if grep -rq "'BadDeviceToken'" --include=index.ts supabase/functions/; then
    bad "a function still acts on BadDeviceToken — see isDeadToken() in _shared/apns.ts"
fi

# 5. The client is the only place allowed to answer sandbox-vs-production, because only there
#    does #if DEBUG describe the binary whose entitlement is in question.
grep -q 'aps-environment' xBill/xBill.Debug.entitlements \
  && grep -q 'development' xBill/xBill.Debug.entitlements \
  || bad "xBill.Debug.entitlements no longer declares aps-environment: development"
grep -A1 'aps-environment' xBill/xBill.entitlements | grep -q 'production' \
  || bad "xBill.entitlements no longer declares aps-environment: production"

if [ "$fail" -eq 0 ]; then
    note "✓ all four functions route per recipient token via _shared/apns.ts"
    note "✓ entitlements still match what AuthService.apnsEnvironment reports"
fi
exit $fail
