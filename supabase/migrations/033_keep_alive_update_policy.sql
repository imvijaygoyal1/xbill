drop policy if exists "Allow anon keep alive update" on public.keep_alive;

create policy "Allow anon keep alive update"
on public.keep_alive
for update
to anon
using (id = 1)
with check (id = 1);
