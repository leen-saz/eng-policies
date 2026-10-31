-- Supabase-style table: RLS on, owner-only policy. Proves the postgres migration check handles auth.uid() and roles.
create table if not exists public.notes (
  id bigint generated always as identity primary key,
  owner uuid not null,
  body text not null,
  created_at timestamptz not null default now()
);
alter table public.notes enable row level security;
create policy notes_owner on public.notes for all to authenticated
  using (owner = auth.uid()) with check (owner = auth.uid());
grant select, insert on public.notes to authenticated;
