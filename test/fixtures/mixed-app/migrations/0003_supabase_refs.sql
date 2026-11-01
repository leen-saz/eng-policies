-- Exercises the Supabase stand-ins of the Postgres migration check: auth.users and supabase_vault
create extension if not exists supabase_vault with schema vault;
create table if not exists public.members (id uuid primary key references auth.users (id) on delete cascade);
create or replace function public.put_secret(p_name text, p_value text) returns uuid
language sql security definer set search_path = '' as $$
  select vault.create_secret(p_value, p_name)
$$;
create or replace function public.read_secrets() returns table (name text, value text)
language sql security definer set search_path = '' as $$
  select name, decrypted_secret from vault.decrypted_secrets
$$;
revoke all on function public.put_secret(text, text) from public, anon, authenticated;
grant execute on function public.put_secret(text, text) to service_role;
