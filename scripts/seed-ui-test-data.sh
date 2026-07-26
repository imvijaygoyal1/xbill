#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UITEST_CREDENTIALS_PLIST="${PROJECT_ROOT}/xBillUITests/UITestCredentials.plist"
EXECUTE="false"
OWNER_EMAIL="${XBILL_TEST_EMAIL:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/seed-ui-test-data.sh [--execute] [--owner-email EMAIL]

Defaults to dry-run. Use --execute to create or repair stable seed groups for
the UI test account before a full regression run.

The target owner defaults to XBILL_TEST_EMAIL, then the ignored local
xBillUITests/UITestCredentials.plist. Seed groups use exact names that are not
included in purge-ui-test-groups.sh disposable prefixes:

  SeedActive-Regression
  SeedArchived-Regression

Examples:
  scripts/seed-ui-test-data.sh
  scripts/seed-ui-test-data.sh --execute
  scripts/seed-ui-test-data.sh --owner-email xbill.uitest@example.com
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

echo "UI test seed data"
echo "Owner:   ${OWNER_EMAIL}"
echo "Execute: ${EXECUTE}"
echo

if [[ "${EXECUTE}" != "true" ]]; then
  echo "Dry-run only. Re-run with --execute to create or repair seed groups."
  echo
fi

if [[ "${EXECUTE}" == "true" ]]; then
  supabase db query --linked "
do \$\$
begin
  if not exists (
    select 1
    from public.profiles
    where lower(email) = lower('${OWNER_EMAIL}')
  ) then
    raise exception 'UI test profile not found for ${OWNER_EMAIL}';
  end if;
end
\$\$;

with owner_profile as (
  select id
  from public.profiles
  where lower(email) = lower('${OWNER_EMAIL}')
  limit 1
),
desired(name, is_archived) as (
  values
    ('SeedActive-Regression', false),
    ('SeedArchived-Regression', true)
),
updated as (
  update public.groups g
     set emoji = 'T',
         currency = 'USD',
         is_archived = d.is_archived
    from desired d
   where g.created_by = (select id from owner_profile)
     and g.name = d.name
   returning g.id, g.name, g.is_archived
),
inserted as (
  insert into public.groups (name, emoji, currency, created_by, is_archived)
  select d.name, 'T', 'USD', owner_profile.id, d.is_archived
    from desired d
    cross join owner_profile
   where not exists (
      select 1
        from public.groups g
       where g.created_by = owner_profile.id
         and g.name = d.name
   )
  returning id, name, is_archived
),
seed_groups as (
  select id, name, is_archived from updated
  union all
  select id, name, is_archived from inserted
),
member_upsert as (
  insert into public.group_members (group_id, user_id, is_active, removed_at)
  select sg.id, owner_profile.id, true, null
    from seed_groups sg
    cross join owner_profile
  on conflict (group_id, user_id) do update
     set is_active = true,
         removed_at = null
  returning group_id
)
select
  sg.id as group_id,
  sg.name as group_name,
  sg.is_archived,
  true as seeded,
  exists (select 1 from inserted i where i.id = sg.id) as created
from seed_groups sg
order by sg.name;
"
else
  supabase db query --linked "
with owner_profile as (
  select id
  from public.profiles
  where lower(email) = lower('${OWNER_EMAIL}')
  limit 1
),
desired(name, is_archived) as (
  values
    ('SeedActive-Regression', false),
    ('SeedArchived-Regression', true)
)
select
  g.id as group_id,
  d.name as group_name,
  op.id is not null as owner_found,
  d.is_archived as desired_archived,
  coalesce(g.is_archived = d.is_archived, false) as archived_matches,
  gm.user_id is not null and coalesce(gm.is_active, true) as active_member_exists,
  g.id is null as would_create
from desired d
left join owner_profile op on true
left join public.groups g
  on g.created_by = op.id
 and g.name = d.name
left join public.group_members gm
  on gm.group_id = g.id
 and gm.user_id = op.id
order by d.name;
"
fi
