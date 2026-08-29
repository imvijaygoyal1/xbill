-- 050_is_settled_permanent.sql
--
-- Records, IN THE DATABASE, that `public.splits.is_settled` is deprecated and will never be
-- dropped. Comment-only: no data changes, no schema shape changes, no policy changes.
--
-- WHY THIS EXISTS
-- The column has been proposed for deletion in six consecutive release cycles, each time on the
-- stated grounds that it is "read by nothing". That is true of the LOGIC — `netBalances` has
-- ignored it since migration 041 replaced it with the settlements ledger — and false of the
-- DECODING. `Split.isSettled` was a non-optional Bool with a synthesised Decodable, and splits
-- are fetched with `select=*`, so dropping the column omits the key and throws `keyNotFound` on
-- every split: expenses and balances dead, not degraded, for every client that has not updated.
--
-- A column you never branch on is still a column you parse.
--
-- The client stopped decoding it on 2026-08-28. That does NOT make the drop safe, because it only
-- helps clients running that build or later. Every install on 1.0–1.5 still decodes it, and this
-- app has **no force-update and no minimum-version gate** — so that population never provably
-- empties. There is no date on which the drop becomes safe, only a date on which someone decides
-- the remaining clients do not matter, with a total failure mode if they are wrong.
--
-- Against that, the prize is one boolean on a small table. Nothing gets simpler or faster.
--
-- Decision 2026-08-29 by the owner: the column stays permanently. This is closed, not deferred.
--
-- The comment lives here rather than only in CLAUDE.md so that someone inspecting the schema
-- directly — psql, the Supabase dashboard, a migration tool, a future DBA who has never seen this
-- repository — is told before they act. Every previous statement of this rule lived in a document
-- you had to already know to go and read.
--
-- IF ANYONE EVER REOPENS THIS: the gate must be measured, not assumed. That means a client-version
-- column written at device-token registration and a DROP conditional on observed adoption. That is
-- real work for a payoff of one boolean, which is itself the argument for leaving it alone.

COMMENT ON COLUMN public.splits.is_settled IS
    'DEPRECATED, PERMANENT — DO NOT DROP. Superseded by public.settlements (migration 041); '
    'no application logic branches on it and nothing writes it. It is NOT unused: clients on '
    'app versions 1.0-1.5 DECODE this key non-optionally, so dropping the column throws '
    'keyNotFound on every split and breaks expenses and balances for them. There is no '
    'force-update mechanism, so that population never provably empties. Decision 2026-08-29: '
    'this column stays permanently. See migration 050 and CLAUDE.md.';

-- The CHECK is retained for the same reason: it is only reachable if something writes the column,
-- which nothing does, and dropping it would be the first step of the sequence this migration
-- exists to stop.
COMMENT ON CONSTRAINT splits_settled_consistency ON public.splits IS
    'Retained with the deprecated is_settled column (migration 050). Unreachable in practice: '
    'nothing writes is_settled. Do not drop it as cleanup.';
