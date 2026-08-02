#!/usr/bin/env bash
#
# Fails if a UI test references an accessibility identifier the app never sets.
#
# WHY THIS EXISTS
# A UI-test predicate that matches nothing does not fail — it sits inside an `||` chain where
# another branch is true, and the suite stays green while asserting nothing. That is strictly
# worse than a missing assertion, because a missing one is visible.
#
# Three instances surfaced on 2026-08-01 alone:
#   * `xBill.uitest.tab.groups`               — left behind by the DEBUG overlay removed in M-66
#   * `xBill.settleUp.recordPaymentButton.`   — never matched: a container-level
#                                               `.accessibilityIdentifier` was overwriting every
#                                               child's identifier (UIT-01)
#   * a hand-written `XCTAssertFalse(deleteButton.exists)` that could only ever be true
#
# The first two are exactly what this catches. Run it in CI, or before trusting a green suite.
#
# Dynamic identifiers are handled: `"xBill.settleUp.suggestionRow.\(id)"` registers the literal
# prefix `xBill.settleUp.suggestionRow.`, and any referenced identifier starting with a known
# prefix counts as defined.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP_DIR="xBill"
TEST_DIRS=("xBillUITests")

# Identifiers the app sets. An interpolation ends the literal, leaving a usable prefix.
defined="$(grep -rhoE '"xBill\.[A-Za-z0-9_.]*' "${APP_DIR}" --include="*.swift" \
           | sed 's/^"//' | sort -u)"

# Identifiers the tests ask for — complete string literals only.
used="$(grep -rhoE '"xBill\.[A-Za-z0-9_.]+"' "${TEST_DIRS[@]}" --include="*.swift" \
        | tr -d '"' | sort -u)"

missing=()
while IFS= read -r id; do
    [[ -z "${id}" ]] && continue
    # Exact match, or the app defines a prefix this identifier extends.
    if grep -qxF "${id}" <<<"${defined}"; then continue; fi
    matched=false
    while IFS= read -r prefix; do
        [[ -z "${prefix}" ]] && continue
        if [[ "${id}" == "${prefix}"* && "${id}" != "${prefix}" ]]; then matched=true; break; fi
    done <<<"${defined}"
    [[ "${matched}" == true ]] || missing+=("${id}")
done <<<"${used}"

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "OK: every accessibility identifier referenced by the UI tests is set by the app."
    exit 0
fi

echo "error: UI tests reference ${#missing[@]} identifier(s) the app never sets." >&2
echo "These predicates can never match, so any assertion using them passes without testing anything." >&2
for id in "${missing[@]}"; do echo "  - ${id}" >&2; done
exit 1
