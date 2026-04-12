-- =============================================================================
-- 001_initial_schema.sql
-- xBill — initial database schema
-- =============================================================================

-- ---------------------------------------------------------------------------
-- profiles
-- Mirrors auth.users. Populated on first sign-in via upsert in AuthService.
-- ---------------------------------------------------------------------------
create table public.profiles (
    id              uuid primary key references auth.users (id) on delete cascade,
    display_name    text        not null default '',
    avatar_url      text,
    venmo_handle    text,
    paypal_email    text,
    created_at      timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: own read"
    on public.profiles for select
    using ( auth.uid() = id );

create policy "profiles: own insert"
    on public.profiles for insert
    with check ( auth.uid() = id );

create policy "profiles: own update"
    on public.profiles for update
    using ( auth.uid() = id )
    with check ( auth.uid() = id );


-- ---------------------------------------------------------------------------
-- groups
-- ---------------------------------------------------------------------------
create table public.groups (
    id          uuid        primary key default gen_random_uuid(),
    name        text        not null,
    emoji       text        not null default '💸',
    created_by  uuid        not null references auth.users (id) on delete restrict,
    is_archived boolean     not null default false,
    created_at  timestamptz not null default now()
);

alter table public.groups enable row level security;


-- ---------------------------------------------------------------------------
-- group_members  (must exist before is_group_member references it)
-- ---------------------------------------------------------------------------
create table public.group_members (
    group_id    uuid        not null references public.groups (id) on delete cascade,
    user_id     uuid        not null references auth.users    (id) on delete cascade,
    joined_at   timestamptz not null default now(),
    primary key (group_id, user_id)
);

alter table public.group_members enable row level security;


-- ---------------------------------------------------------------------------
-- Helper functions (defined after the tables they query)
-- ---------------------------------------------------------------------------

-- Returns true when the calling user is a member of the given group
create or replace function public.is_group_member(group_id uuid)
returns boolean
language sql
security definer
stable
as $$
    select exists (
        select 1 from public.group_members gm
        where gm.group_id = $1
          and gm.user_id  = auth.uid()
    );
$$;

-- ---------------------------------------------------------------------------
-- groups RLS policies (now that is_group_member exists)
-- ---------------------------------------------------------------------------
create policy "groups: members can read"
    on public.groups for select
    using ( public.is_group_member(id) );

create policy "groups: members can update"
    on public.groups for update
    using ( public.is_group_member(id) );

create policy "groups: authenticated users can create"
    on public.groups for insert
    with check ( auth.uid() = created_by );


-- ---------------------------------------------------------------------------
-- group_members RLS policies
-- ---------------------------------------------------------------------------
create policy "group_members: members can read"
    on public.group_members for select
    using ( public.is_group_member(group_id) );

create policy "group_members: members can insert"
    on public.group_members for insert
    with check ( public.is_group_member(group_id) );

create policy "group_members: own row delete"
    on public.group_members for delete
    using ( auth.uid() = user_id );


-- ---------------------------------------------------------------------------
-- expenses
-- ---------------------------------------------------------------------------
create table public.expenses (
    id          uuid            primary key default gen_random_uuid(),
    group_id    uuid            not null references public.groups (id) on delete cascade,
    paid_by     uuid            not null references auth.users    (id) on delete restrict,
    amount      numeric(10, 2)  not null check (amount > 0),
    description text            not null default '',
    category    text            not null default 'other',
    receipt_url text,
    created_at  timestamptz     not null default now()
);

create index expenses_group_id_idx on public.expenses (group_id);
create index expenses_paid_by_idx  on public.expenses (paid_by);

alter table public.expenses enable row level security;

-- Defined here because it queries public.expenses (must exist first)
create or replace function public.is_expense_group_member(expense_id uuid)
returns boolean
language sql
security definer
stable
as $$
    select exists (
        select 1
        from   public.expenses e
        join   public.group_members gm on gm.group_id = e.group_id
        where  e.id       = $1
          and  gm.user_id = auth.uid()
    );
$$;

create policy "expenses: group members can read"
    on public.expenses for select
    using ( public.is_group_member(group_id) );

create policy "expenses: group members can insert"
    on public.expenses for insert
    with check ( public.is_group_member(group_id) and auth.uid() = paid_by );

create policy "expenses: payer can delete"
    on public.expenses for delete
    using ( auth.uid() = paid_by );


-- ---------------------------------------------------------------------------
-- splits
-- ---------------------------------------------------------------------------
create table public.splits (
    id          uuid            primary key default gen_random_uuid(),
    expense_id  uuid            not null references public.expenses (id) on delete cascade,
    user_id     uuid            not null references auth.users      (id) on delete cascade,
    amount      numeric(10, 2)  not null check (amount >= 0),
    is_settled  boolean         not null default false,
    settled_at  timestamptz,
    unique (expense_id, user_id)
);

create index splits_expense_id_idx on public.splits (expense_id);
create index splits_user_id_idx    on public.splits (user_id);

alter table public.splits enable row level security;

create policy "splits: group members can read"
    on public.splits for select
    using ( public.is_expense_group_member(expense_id) );

create policy "splits: group members can insert"
    on public.splits for insert
    with check ( public.is_expense_group_member(expense_id) );

create policy "splits: own row settle"
    on public.splits for update
    using  ( auth.uid() = user_id )
    with check ( auth.uid() = user_id );
