-- Lock-in: a friend ("keyholder") who approves unlocks, and the requests they answer.
--
-- Everything here is reached through the lockin-keyholder and lockin-milo Edge
-- Functions, which use the service role. RLS is on with no policies, so the app and
-- anyone holding the anon key cannot read or write these tables directly.

create table if not exists public.lock_in_keyholders (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  owner_name text not null default '' check (char_length(owner_name) <= 40),
  keyholder_name text not null check (char_length(keyholder_name) between 1 and 40),
  keyholder_email text not null check (char_length(keyholder_email) <= 254),
  -- The invite link carries a random token; only its hash is stored.
  invite_token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'active', 'revoked')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz
);

-- One keyholder at a time per person; a revoked one frees the slot.
create unique index if not exists lock_in_keyholders_one_live_per_owner
  on public.lock_in_keyholders (owner_user_id)
  where status <> 'revoked';

create table if not exists public.lock_in_unlock_requests (
  id uuid primary key default gen_random_uuid(),
  keyholder_id uuid not null references public.lock_in_keyholders(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  lock_id text not null check (char_length(lock_id) between 1 and 64),
  task text not null check (char_length(task) between 1 and 80),
  -- Milo's one-sentence account of the evidence. Never photos.
  summary text not null check (char_length(summary) between 1 and 400),
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'expired')),
  keyholder_note text check (char_length(keyholder_note) <= 200),
  -- The lock's check-in time. Past it, an approval would change nothing.
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create index if not exists lock_in_unlock_requests_owner_lock
  on public.lock_in_unlock_requests (owner_user_id, lock_id, created_at desc);

-- One row per Milo review, to cap how many a person can ask for in a day.
create table if not exists public.lock_in_milo_calls (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists lock_in_milo_calls_user_recent
  on public.lock_in_milo_calls (user_id, created_at desc);

alter table public.lock_in_keyholders enable row level security;
alter table public.lock_in_unlock_requests enable row level security;
alter table public.lock_in_milo_calls enable row level security;
