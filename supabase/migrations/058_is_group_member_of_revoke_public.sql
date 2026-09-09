-- 058_is_group_member_of_revoke_public.sql
--
-- Completes what 055 and 057 tried to do. Both revoked EXECUTE from `anon` — and that WORKED:
-- `anon=X` is absent from the ACL. But the function still answered an anonymous POST with HTTP 200,
-- because PostgreSQL grants EXECUTE on every new function to **PUBLIC** by default, and
-- `has_function_privilege('anon', ...)` is satisfied through PUBLIC.
--
--   is_group_member_of   =X/postgres | postgres=X | authenticated=X | service_role=X
--                        ^ empty grantee = PUBLIC
--   search_profiles      postgres=X  | authenticated=X | service_role=X      (no PUBLIC entry)
--
-- ⚠️ THE RULE, BOTH DIRECTIONS. `CLAUDE.md` already records one half: *"REVOKE ... FROM PUBLIC does
-- not remove an explicit anon grant — revoke by name."* The converse is equally true and was not
-- recorded: **revoking from `anon` does not remove PUBLIC's grant.** A function is only closed to
-- anonymous callers when BOTH are revoked. Neither revoke alone is sufficient, and each looks like
-- it worked.
revoke execute on function public.is_group_member_of(uuid, uuid) from public;
revoke execute on function public.is_group_member_of(uuid, uuid) from anon;
