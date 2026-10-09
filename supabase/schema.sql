-- ==============================================================================
-- TRICRYPT SUPABASE DATABASE SCHEMA: LOGIN DETAILS ONLY
-- ==============================================================================
-- This schema stores strictly the details collected during user login:
--   1. id (UUID linking to auth.users)
--   2. email (the email entered in the login form)
--   3. remember_me (boolean state of the "Remember me!" checkbox)
--   4. login_time (timestamp when the user authenticated/logged in)
-- ==============================================================================

-- 1. Create the user_logins table
create table if not exists public.user_logins (
  id uuid references auth.users(id) on delete cascade primary key,
  email text not null,
  remember_me boolean not null default true,
  login_time timestamp with time zone not null default timezone('utc'::text, now())
);

-- 2. Enable Row Level Security (RLS)
alter table public.user_logins enable row level security;

-- Drop existing policies if re-running
drop policy if exists "Users can read own login details" on public.user_logins;
drop policy if exists "Users can insert own login details" on public.user_logins;
drop policy if exists "Users can update own login details" on public.user_logins;

-- 3. RLS Policies: Each authenticated user can only access & mutate their own login row
create policy "Users can read own login details"
  on public.user_logins
  for select
  to authenticated
  using (auth.uid() = id);

create policy "Users can insert own login details"
  on public.user_logins
  for insert
  to authenticated
  with check (auth.uid() = id);

create policy "Users can update own login details"
  on public.user_logins
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 4. Enable Supabase Realtime Replication
-- This allows the Flutter client to stream updates instantly when login_time or remember_me changes
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'user_logins'
  ) then
    alter publication supabase_realtime add table public.user_logins;
  end if;
end;
$$;

-- 5. Optional Auto-Create Trigger on New User Signup
-- Automatically initializes a row in user_logins whenever an account is created in auth.users
create or replace function public.handle_new_user_login()
returns trigger as $$
begin
  insert into public.user_logins (id, email, remember_me, login_time)
  values (
    new.id,
    new.email,
    true,
    timezone('utc'::text, now())
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user_login();

-- ==============================================================================
-- Schema creation complete!
-- You can verify by running: SELECT * FROM public.user_logins;
-- ==============================================================================
