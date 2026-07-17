#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UITEST_CREDENTIALS_PLIST="${PROJECT_ROOT}/xBillUITests/UITestCredentials.plist"
EXECUTE="false"
OWNER_EMAIL="${XBILL_TEST_EMAIL:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/purge-ui-test-groups.sh [--execute] [--owner-email EMAIL]

Defaults to dry-run. Use --execute to permanently delete matching UI-test
groups and their dependent rows through existing ON DELETE CASCADE constraints.

The target owner defaults to XBILL_TEST_EMAIL, then the ignored local
xBillUITests/UITestCredentials.plist. Only approved test prefixes are purged:
Regression, ExpenseForm, ArchiveCycle, ExpenseDetail, ReceiptManual,
SplitModes, GroupSettings, SettleSurface, UITest, ArchiveTest.

Examples:
  scripts/purge-ui-test-groups.sh
  scripts/purge-ui-test-groups.sh --execute
  scripts/purge-ui-test-groups.sh --owner-email xbill.uitest@example.com
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      EXECUTE="true"
      shift
      ;;
    --owner-email)
      if [[ $# -lt 2 ]]; then
        echo "error: --owner-email requires a value" >&2
        exit 2
      fi
      OWNER_EMAIL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${OWNER_EMAIL}" && -f "${UITEST_CREDENTIALS_PLIST}" ]]; then
  OWNER_EMAIL="$(/usr/libexec/PlistBuddy -c 'Print :XBILL_TEST_EMAIL' "${UITEST_CREDENTIALS_PLIST}" 2>/dev/null || true)"
fi

if [[ -z "${OWNER_EMAIL}" ]]; then
  echo "error: owner email is required. Export XBILL_TEST_EMAIL or pass --owner-email." >&2
  exit 2
fi

if [[ "${OWNER_EMAIL}" == *"'"* ]]; then
  echo "error: owner email cannot contain a single quote." >&2
  exit 2
fi

cd "${PROJECT_ROOT}"

echo "UI test group purge"
echo "Owner:   ${OWNER_EMAIL}"
echo "Execute: ${EXECUTE}"
echo

if [[ "${EXECUTE}" != "true" ]]; then
  echo "Dry-run only. Re-run with --execute to delete the listed groups."
  echo
fi

supabase db query --linked "
with owner_profile as (
  select id
  from public.profiles
  where lower(email) = lower('${OWNER_EMAIL}')
  limit 1
),
purged as (
  select *
  from public.purge_ui_test_groups(
    p_execute => ${EXECUTE},
    p_created_by => (select id from owner_profile)
  )
)
select
  group_id,
  group_name,
  was_archived,
  deleted
from purged
order by group_name;
"
