create table if not exists public.keep_alive (
  id int primary key,
  updated_at timestamptz not null default now()
);

insert into public.keep_alive (id)
values (1)
on conflict (id) do nothing;

alter table public.keep_alive enable row level security;

drop policy if exists "Allow anon keep alive read" on public.keep_alive;

create policy "Allow anon keep alive read"
on public.keep_alive
for select
to anon
using (true);
