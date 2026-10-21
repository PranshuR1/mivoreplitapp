-- Mivo Supabase schema
-- Run in Supabase SQL Editor, or apply through a Postgres client.

create table if not exists public.user_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    name text not null,
    created_at timestamptz,
    updated_at timestamptz not null default now()
);

create table if not exists public.onboarding_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    observation_started_at timestamptz,
    referral_source text,
    primary_intention text,
    scroll_estimate_minutes integer,
    preferred_apps text[] not null default '{}',
    preferred_scroll_windows jsonb not null default '[]'::jsonb,
    intentions text[] not null default '{}',
    age integer,
    age_range text,
    check_in_interval_minutes integer,
    daily_scroll_goal_minutes integer,
    raw_profile jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);

create table if not exists public.app_settings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    onboarding_complete boolean not null default false,
    notifications_enabled boolean not null default false,
    tutorial_complete boolean,
    notifications_choice_made boolean,
    accountability_enabled boolean,
    check_in_interval_minutes integer,
    raw_settings jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);

create table if not exists public.sessions (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    date text not null,
    start_time text not null,
    end_time text not null,
    planned_duration integer not null,
    actual_duration integer not null,
    intention text not null,
    extended_once boolean not null default false,
    reflection text,
    reflection_note text not null default '',
    urge_reason text,
    urge_note text,
    outcome_score text,
    emergency_unlock_used boolean,
    emergency_unlock_reason text,
    raw_session jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.truth_checks (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    date text not null,
    guess integer not null,
    actual integer not null,
    raw_truth_check jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.daily_scroll_schedules (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    date text not null,
    windows jsonb not null default '[]'::jsonb,
    created_at text not null,
    raw_schedule jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.weekly_reports (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    week_start text not null,
    week_end text not null,
    total_minutes integer not null,
    recovered_minutes integer not null,
    session_count integer not null,
    top_urge_reason text,
    hardest_window text not null,
    extended_count integer not null,
    emergency_unlock_count integer not null,
    recommendation text not null,
    raw_report jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.app_intervention_rules (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    app_name text not null,
    mode text not null,
    raw_rule jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table if not exists public.user_summaries (
    user_id uuid primary key references auth.users(id) on delete cascade,
    accountability_week_start text,
    accountability_week_end text,
    accountability_share_text text,
    widget_recovered_minutes_today integer,
    widget_screen_time_minutes_today integer,
    widget_next_scroll_window text,
    widget_plan_state text,
    widget_streak_text text,
    widget_updated_at text,
    accountability_summary jsonb,
    widget_shared_summary jsonb,
    updated_at timestamptz not null default now()
);

create table if not exists public.ai_summary_entries (
    user_id uuid not null references auth.users(id) on delete cascade,
    entry_index integer not null,
    summary text not null,
    updated_at timestamptz not null default now(),
    primary key (user_id, entry_index)
);

create table if not exists public.user_state (
    user_id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    name text not null,
    profile jsonb not null default '{}'::jsonb,
    settings jsonb not null default '{}'::jsonb,
    sessions jsonb not null default '[]'::jsonb,
    truth_checks jsonb not null default '[]'::jsonb,
    daily_scroll_schedules jsonb not null default '[]'::jsonb,
    weekly_reports jsonb not null default '[]'::jsonb,
    app_intervention_rules jsonb not null default '[]'::jsonb,
    accountability_summary jsonb,
    widget_shared_summary jsonb,
    ai_dataset jsonb not null default '[]'::jsonb,
    mivo_still_sessions jsonb not null default '[]'::jsonb,
    app_friction_profiles jsonb not null default '[]'::jsonb,
    user_swap jsonb,
    intervention_attempts jsonb not null default '[]'::jsonb,
    daily_screen_time_observations jsonb not null default '[]'::jsonb,
    time_loans jsonb not null default '[]'::jsonb,
    intent_game_history jsonb not null default '[]'::jsonb,
    drop_path_time_adjustments jsonb not null default '[]'::jsonb,
    recall_check_ins jsonb not null default '[]'::jsonb,
    instagram_wrapper_sessions jsonb not null default '[]'::jsonb,
    instagram_recall_prompts jsonb not null default '[]'::jsonb,
    updated_at timestamptz not null default now()
);
alter table public.user_state add column if not exists mivo_still_sessions jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists app_friction_profiles jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists user_swap jsonb;
alter table public.user_state add column if not exists intervention_attempts jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists daily_screen_time_observations jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists time_loans jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists intent_game_history jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists drop_path_time_adjustments jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists recall_check_ins jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists instagram_wrapper_sessions jsonb not null default '[]'::jsonb;
alter table public.user_state add column if not exists instagram_recall_prompts jsonb not null default '[]'::jsonb;

create table if not exists public.device_bindings (
    device_id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    account_email text not null,
    created_at timestamptz not null default now(),
    last_seen_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;
alter table public.onboarding_profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.sessions enable row level security;
alter table public.truth_checks enable row level security;
alter table public.daily_scroll_schedules enable row level security;
alter table public.weekly_reports enable row level security;
alter table public.app_intervention_rules enable row level security;
alter table public.user_summaries enable row level security;
alter table public.ai_summary_entries enable row level security;
alter table public.user_state enable row level security;
alter table public.device_bindings enable row level security;

do $$
declare
    t text;
begin
    foreach t in array array[
        'user_profiles',
        'onboarding_profiles',
        'app_settings',
        'sessions',
        'truth_checks',
        'daily_scroll_schedules',
        'weekly_reports',
        'app_intervention_rules',
        'user_summaries',
        'ai_summary_entries',
        'user_state'
    ]
    loop
        execute format('drop policy if exists "own_select" on public.%I', t);
        execute format('drop policy if exists "own_insert" on public.%I', t);
        execute format('drop policy if exists "own_update" on public.%I', t);
        execute format('drop policy if exists "own_delete" on public.%I', t);
        execute format('create policy "own_select" on public.%I for select to authenticated using (auth.uid() = user_id)', t);
        execute format('create policy "own_insert" on public.%I for insert to authenticated with check (auth.uid() = user_id)', t);
        execute format('create policy "own_update" on public.%I for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
        execute format('create policy "own_delete" on public.%I for delete to authenticated using (auth.uid() = user_id)', t);
    end loop;
end $$;

drop policy if exists "own_select" on public.device_bindings;
drop policy if exists "own_insert" on public.device_bindings;
drop policy if exists "own_update" on public.device_bindings;
drop policy if exists "own_delete" on public.device_bindings;
create policy "own_select" on public.device_bindings
    for select to authenticated using (auth.uid() = user_id);
create policy "own_insert" on public.device_bindings
    for insert to authenticated with check (auth.uid() = user_id);

create index if not exists sessions_user_date_idx on public.sessions (user_id, date);
create index if not exists truth_checks_user_date_idx on public.truth_checks (user_id, date);
create index if not exists schedules_user_date_idx on public.daily_scroll_schedules (user_id, date);
create index if not exists weekly_reports_user_week_idx on public.weekly_reports (user_id, week_start);
create index if not exists user_profiles_email_idx on public.user_profiles (lower(email));
create index if not exists device_bindings_user_idx on public.device_bindings (user_id);

-- Super-admin and parental consent.
create extension if not exists pgcrypto;

create table if not exists public.app_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    role text not null check (role in ('super_admin', 'admin')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.parental_consent_requests (
    id uuid primary key default gen_random_uuid(),
    request_token_hash text not null,
    parent_email text not null,
    birth_month integer not null check (birth_month between 1 and 12),
    birth_year integer not null check (birth_year between 1900 and 2200),
    status text not null default 'pending' check (status in ('pending', 'needs_information', 'approved', 'rejected', 'expired', 'revoked')),
    evidence_storage_path text,
    reviewer_note text,
    reviewed_by uuid references auth.users(id),
    reviewed_at timestamptz,
    expires_at timestamptz not null default (now() + interval '30 days'),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.parental_consent_records (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.parental_consent_requests(id) on delete cascade,
    child_user_id uuid unique references auth.users(id) on delete cascade,
    parent_email text not null,
    consent_method text not null default 'manual_document_review',
    policy_version text not null default '2026-07',
    consented_at timestamptz not null,
    revoked_at timestamptz,
    reviewed_by uuid not null references auth.users(id),
    created_at timestamptz not null default now()
);
create unique index if not exists parental_consent_one_record_per_request_idx
    on public.parental_consent_records (request_id);

create table if not exists public.admin_audit_log (
    id bigint generated always as identity primary key,
    actor_user_id uuid references auth.users(id) on delete set null,
    action text not null,
    target_user_id uuid references auth.users(id) on delete set null,
    target_type text,
    target_id text,
    reason text,
    before_value jsonb,
    after_value jsonb,
    created_at timestamptz not null default now()
);

create table if not exists public.announcements (
    id uuid primary key default gen_random_uuid(),
    title text not null check (char_length(title) between 1 and 80),
    body text not null check (char_length(body) between 1 and 1000),
    status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
    published_at timestamptz,
    expires_at timestamptz,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.announcement_receipts (
    announcement_id uuid not null references public.announcements(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    seen_at timestamptz,
    dismissed_at timestamptz,
    primary key (announcement_id, user_id)
);

alter table public.announcements enable row level security;
alter table public.announcement_receipts enable row level security;

drop policy if exists "announcement_user_read" on public.announcements;
create policy "announcement_user_read" on public.announcements for select to authenticated using (
    public.is_super_admin() or (status = 'published' and published_at <= now() and (expires_at is null or expires_at > now()))
);
drop policy if exists "announcement_admin_manage" on public.announcements;
create policy "announcement_admin_manage" on public.announcements for all to authenticated
    using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "announcement_receipt_own" on public.announcement_receipts;
create policy "announcement_receipt_own" on public.announcement_receipts for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.is_super_admin(check_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.app_admins
        where user_id = check_user_id and role = 'super_admin'
    );
$$;

revoke all on function public.is_super_admin(uuid) from public;
grant execute on function public.is_super_admin(uuid) to authenticated;

create or replace function public.bootstrap_mivo_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if lower(coalesce(new.email, '')) = 'pranshuraithatha0@gmail.com' then
        delete from public.app_admins where role = 'super_admin' and user_id <> new.id;
        insert into public.app_admins (user_id, email, role, updated_at)
        values (new.id, lower(new.email), 'super_admin', now())
        on conflict (user_id) do update set email = excluded.email, role = 'super_admin', updated_at = now();
    end if;
    return new;
end;
$$;

drop trigger if exists mivo_bootstrap_auth_user on auth.users;
create trigger mivo_bootstrap_auth_user
    after insert or update of email on auth.users
    for each row execute function public.bootstrap_mivo_user();

delete from public.app_admins where role = 'super_admin'
    and user_id not in (select id from auth.users where lower(email) = 'pranshuraithatha0@gmail.com');
insert into public.app_admins (user_id, email, role)
select id, lower(email), 'super_admin' from auth.users
where lower(email) = 'pranshuraithatha0@gmail.com'
on conflict (user_id) do update set email = excluded.email, role = excluded.role, updated_at = now();

alter table public.app_admins enable row level security;
alter table public.parental_consent_requests enable row level security;
alter table public.parental_consent_records enable row level security;
alter table public.admin_audit_log enable row level security;

drop policy if exists "admin_role_self_read" on public.app_admins;
create policy "admin_role_self_read" on public.app_admins
    for select to authenticated using (user_id = auth.uid() or public.is_super_admin());

drop policy if exists "consent_admin_all" on public.parental_consent_requests;
create policy "consent_admin_all" on public.parental_consent_requests
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "consent_record_admin_all" on public.parental_consent_records;
create policy "consent_record_admin_all" on public.parental_consent_records
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "audit_admin_read" on public.admin_audit_log;
create policy "audit_admin_read" on public.admin_audit_log
    for select to authenticated using (public.is_super_admin());

create or replace function public.create_parental_consent_request(
    input_parent_email text, input_birth_month integer, input_birth_year integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    request_id uuid := gen_random_uuid();
    request_token uuid := gen_random_uuid();
begin
    if input_parent_email is null or position('@' in input_parent_email) < 2 then
        raise exception 'invalid_parent_email';
    end if;
    insert into public.parental_consent_requests (
        id, request_token_hash, parent_email, birth_month, birth_year
    ) values (
        request_id, encode(extensions.digest(request_token::text, 'sha256'), 'hex'), lower(trim(input_parent_email)),
        input_birth_month, input_birth_year
    );
    return jsonb_build_object('request_id', request_id, 'request_token', request_token, 'status', 'pending');
end;
$$;
grant execute on function public.create_parental_consent_request(text, integer, integer) to anon, authenticated;

create or replace function public.parental_consent_status(input_request_id uuid, input_request_token uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
    select coalesce((
        select jsonb_build_object('status', status, 'reviewer_note', reviewer_note, 'expires_at', expires_at)
        from public.parental_consent_requests
        where id = input_request_id
          and request_token_hash = encode(extensions.digest(input_request_token::text, 'sha256'), 'hex')
    ), jsonb_build_object('status', 'not_found'));
$$;
grant execute on function public.parental_consent_status(uuid, uuid) to anon, authenticated;

create or replace function public.claim_approved_parental_consent(
    input_request_id uuid, input_request_token uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if not exists (
        select 1 from public.parental_consent_requests
        where id = input_request_id
          and status = 'approved'
          and request_token_hash = encode(extensions.digest(input_request_token::text, 'sha256'), 'hex')
          and expires_at > now()
    ) then raise exception 'parental_consent_not_approved'; end if;
    update public.parental_consent_records
    set child_user_id = auth.uid()
    where request_id = input_request_id and child_user_id is null;
    if not found then raise exception 'parental_consent_already_claimed'; end if;
end;
$$;
grant execute on function public.claim_approved_parental_consent(uuid, uuid) to authenticated;

create or replace function public.admin_user_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    result jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select jsonb_build_object(
        'consent_requests', coalesce((
            select jsonb_agg(to_jsonb(r) - 'request_token_hash' order by r.created_at desc)
            from public.parental_consent_requests r
        ), '[]'::jsonb),
        'users', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', p.user_id, 'email', p.email, 'name', p.name, 'created_at', p.created_at,
                'onboarding_complete', coalesce(s.onboarding_complete, false),
                'session_count', (select count(*) from public.sessions se where se.user_id = p.user_id),
                'total_minutes', (select coalesce(sum(actual_duration), 0) from public.sessions se where se.user_id = p.user_id),
                'reflection_count', (select count(*) from public.sessions se where se.user_id = p.user_id and reflection is not null)
            ) order by p.created_at desc)
            from public.user_profiles p
            left join public.app_settings s on s.user_id = p.user_id
        ), '[]'::jsonb)
    ) into result;
    return result;
end;
$$;
grant execute on function public.admin_user_dashboard() to authenticated;

create or replace function public.get_unseen_announcements()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((select jsonb_agg(to_jsonb(a) order by a.published_at desc)
        from public.announcements a
        where a.status = 'published' and a.published_at <= now()
          and (a.expires_at is null or a.expires_at > now())
          and not exists (select 1 from public.announcement_receipts r
              where r.announcement_id = a.id and r.user_id = auth.uid() and r.seen_at is not null)), '[]'::jsonb);
end; $$;
grant execute on function public.get_unseen_announcements() to authenticated;

create or replace function public.mark_announcement_seen(input_announcement_id uuid, input_dismissed boolean default false)
returns void language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    insert into public.announcement_receipts (announcement_id, user_id, seen_at, dismissed_at)
    values (input_announcement_id, auth.uid(), now(), case when input_dismissed then now() else null end)
    on conflict (announcement_id, user_id) do update set
        seen_at = coalesce(public.announcement_receipts.seen_at, now()),
        dismissed_at = case when input_dismissed then now() else public.announcement_receipts.dismissed_at end;
end; $$;
grant execute on function public.mark_announcement_seen(uuid, boolean) to authenticated;

create or replace function public.admin_announcement_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    return coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.announcements a), '[]'::jsonb);
end; $$;
grant execute on function public.admin_announcement_dashboard() to authenticated;

create or replace function public.admin_create_announcement(
    input_title text, input_body text, input_expires_at timestamptz default null, input_publish_now boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
declare created public.announcements%rowtype;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    insert into public.announcements (title, body, status, published_at, expires_at, created_by)
    values (trim(input_title), trim(input_body), case when input_publish_now then 'published' else 'draft' end,
        case when input_publish_now then now() else null end, input_expires_at, auth.uid()) returning * into created;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), case when input_publish_now then 'announcement_published' else 'announcement_created' end,
        'announcement', created.id::text, to_jsonb(created));
    return to_jsonb(created);
end; $$;
grant execute on function public.admin_create_announcement(text, text, timestamptz, boolean) to authenticated;

create or replace function public.admin_set_announcement_status(input_announcement_id uuid, input_status text)
returns void language plpgsql security definer set search_path = public as $$
declare before_row jsonb; after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status not in ('published', 'archived') then raise exception 'invalid_status'; end if;
    select to_jsonb(a) into before_row from public.announcements a where id = input_announcement_id;
    update public.announcements set status = input_status,
        published_at = case when input_status = 'published' then coalesce(published_at, now()) else published_at end,
        updated_at = now() where id = input_announcement_id;
    select to_jsonb(a) into after_row from public.announcements a where id = input_announcement_id;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, before_value, after_value)
    values (auth.uid(), 'announcement_' || input_status, 'announcement', input_announcement_id::text, before_row, after_row);
end; $$;
grant execute on function public.admin_set_announcement_status(uuid, text) to authenticated;

create or replace function public.admin_review_parental_consent(
    input_request_id uuid, input_status text, input_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status not in ('approved', 'rejected', 'needs_information', 'revoked') then raise exception 'invalid_status'; end if;
    select to_jsonb(r) - 'request_token_hash' into before_row from public.parental_consent_requests r where id = input_request_id;
    update public.parental_consent_requests set
        status = input_status, reviewer_note = input_note, reviewed_by = auth.uid(), reviewed_at = now(), updated_at = now()
    where id = input_request_id;
    select to_jsonb(r) - 'request_token_hash' into after_row from public.parental_consent_requests r where id = input_request_id;
    if input_status = 'approved' then
        insert into public.parental_consent_records (
            request_id, parent_email, consented_at, reviewed_by
        ) select id, parent_email, now(), auth.uid() from public.parental_consent_requests where id = input_request_id
        on conflict do nothing;
    end if;
    if input_status in ('approved', 'rejected', 'revoked') then
        delete from storage.objects
        where bucket_id = 'parental-consent-evidence'
          and name = (select evidence_storage_path from public.parental_consent_requests where id = input_request_id);
        update public.parental_consent_requests
        set evidence_storage_path = null, updated_at = now()
        where id = input_request_id;
    end if;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, reason, before_value, after_value)
    values (auth.uid(), 'parental_consent_' || input_status, 'parental_consent_request', input_request_id::text, input_note, before_row, after_row);
end;
$$;
grant execute on function public.admin_review_parental_consent(uuid, text, text) to authenticated;

create or replace function public.admin_get_user_detail(input_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    return jsonb_build_object(
        'profile', (select to_jsonb(p) from public.user_profiles p where p.user_id = input_user_id),
        'onboarding', (select to_jsonb(o) from public.onboarding_profiles o where o.user_id = input_user_id),
        'settings', (select to_jsonb(s) from public.app_settings s where s.user_id = input_user_id),
        'sessions', coalesce((select jsonb_agg(to_jsonb(se) order by se.start_time desc) from public.sessions se where se.user_id = input_user_id), '[]'::jsonb),
        'truth_checks', coalesce((select jsonb_agg(to_jsonb(t) order by t.date desc) from public.truth_checks t where t.user_id = input_user_id), '[]'::jsonb),
        'schedules', coalesce((select jsonb_agg(to_jsonb(d) order by d.date desc) from public.daily_scroll_schedules d where d.user_id = input_user_id), '[]'::jsonb),
        'reports', coalesce((select jsonb_agg(to_jsonb(w) order by w.week_start desc) from public.weekly_reports w where w.user_id = input_user_id), '[]'::jsonb)
    );
end;
$$;
grant execute on function public.admin_get_user_detail(uuid) to authenticated;

create or replace function public.admin_update_session(
    input_user_id uuid,
    input_session_id text,
    input_planned_duration integer,
    input_actual_duration integer,
    input_reflection text,
    input_reflection_note text,
    input_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_planned_duration < 0 or input_actual_duration < 0 then raise exception 'invalid_duration'; end if;
    select to_jsonb(s) into before_row from public.sessions s
    where user_id = input_user_id and id = input_session_id;
    update public.sessions set
        planned_duration = input_planned_duration,
        actual_duration = input_actual_duration,
        reflection = nullif(input_reflection, ''),
        reflection_note = coalesce(input_reflection_note, ''),
        raw_session = raw_session || jsonb_build_object(
            'plannedDuration', input_planned_duration,
            'actualDuration', input_actual_duration,
            'reflection', nullif(input_reflection, ''),
            'reflectionNote', coalesce(input_reflection_note, '')
        ),
        updated_at = now()
    where user_id = input_user_id and id = input_session_id;
    select to_jsonb(s) into after_row from public.sessions s
    where user_id = input_user_id and id = input_session_id;
    insert into public.admin_audit_log (actor_user_id, action, target_user_id, target_type, target_id, reason, before_value, after_value)
    values (auth.uid(), 'session_update', input_user_id, 'session', input_session_id, input_reason, before_row, after_row);
end;
$$;
grant execute on function public.admin_update_session(uuid, text, integer, integer, text, text, text) to authenticated;

create or replace function public.admin_reset_user_progress(input_user_id uuid, input_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_value jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if public.is_super_admin(input_user_id) then raise exception 'cannot_reset_super_admin'; end if;
    select public.admin_get_user_detail(input_user_id) into before_value;
    delete from public.sessions where user_id = input_user_id;
    delete from public.truth_checks where user_id = input_user_id;
    delete from public.daily_scroll_schedules where user_id = input_user_id;
    delete from public.weekly_reports where user_id = input_user_id;
    delete from public.app_intervention_rules where user_id = input_user_id;
    delete from public.ai_summary_entries where user_id = input_user_id;
    delete from public.user_summaries where user_id = input_user_id;
    update public.app_settings set onboarding_complete = false, tutorial_complete = false,
        raw_settings = raw_settings || jsonb_build_object('onboardingComplete', false, 'tutorialComplete', false),
        updated_at = now() where user_id = input_user_id;
    update public.user_state set sessions = '[]', truth_checks = '[]', daily_scroll_schedules = '[]',
        weekly_reports = '[]', app_intervention_rules = '[]', ai_dataset = '[]', updated_at = now()
    where user_id = input_user_id;
    insert into public.admin_audit_log (actor_user_id, action, target_user_id, target_type, target_id, reason, before_value)
    values (auth.uid(), 'user_progress_reset', input_user_id, 'user', input_user_id::text, input_reason, before_value);
end;
$$;
grant execute on function public.admin_reset_user_progress(uuid, text) to authenticated;

create or replace function public.admin_delete_user(input_user_id uuid, input_reason text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    before_value jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if public.is_super_admin(input_user_id) then raise exception 'cannot_delete_super_admin'; end if;
    select public.admin_get_user_detail(input_user_id) into before_value;
    insert into public.admin_audit_log (actor_user_id, action, target_user_id, target_type, target_id, reason, before_value)
    values (auth.uid(), 'user_deleted', input_user_id, 'user', input_user_id::text, input_reason, before_value);
    delete from auth.users where id = input_user_id;
end;
$$;
grant execute on function public.admin_delete_user(uuid, text) to authenticated;

create or replace function public.delete_my_account(input_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    caller_id uuid := auth.uid();
    caller_email text;
    before_value jsonb;
begin
    if caller_id is null then
        raise exception 'authentication_required';
    end if;

    -- A super admin owns announcements and campaign rule versions through NOT NULL
    -- foreign keys that do not cascade, so deleting them would abort on a foreign
    -- key violation partway through. Fail fast with a message the app can explain.
    if public.is_super_admin(caller_id) then
        raise exception 'super_admin_self_delete_blocked';
    end if;

    select email into caller_email from auth.users where id = caller_id;

    select jsonb_build_object(
        'user_id', caller_id,
        'email', caller_email,
        'deleted_at', now()
    ) into before_value;

    insert into public.admin_audit_log (
        actor_user_id, action, target_user_id, target_type, target_id, reason, before_value
    )
    values (
        caller_id,
        'user_self_deleted',
        caller_id,
        'user',
        caller_id::text,
        coalesce(nullif(btrim(input_reason), ''), 'Self-serve deletion from Mivo Privacy Center'),
        before_value
    );

    -- Every user-owned table references auth.users(id) on delete cascade, so this
    -- removes the auth identity and all associated rows in one statement.
    delete from auth.users where id = caller_id;
end;
$$;
revoke all on function public.delete_my_account(text) from public;
grant execute on function public.delete_my_account(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'parental-consent-evidence',
    'parental-consent-evidence',
    false,
    10485760,
    array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "super_admin_manage_parental_evidence" on storage.objects;
create policy "super_admin_manage_parental_evidence" on storage.objects
    for all to authenticated using (bucket_id = 'parental-consent-evidence' and public.is_super_admin())
    with check (bucket_id = 'parental-consent-evidence' and public.is_super_admin());

-- Mac companion app activity sync + general (non-admin) push device
-- registry, backing "Block my iPhone too" and cross-device activity
-- history. See mivomac/IPHONE_FOCUS_RECEIVER.md and
-- mivomac/Supabase/20260819190000_mac_activity_and_push_sync.sql.

create table if not exists public.mac_activity_records (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    app_name text not null,
    bundle_id text not null,
    window_title text not null,
    url_string text,
    started_at timestamptz not null,
    ended_at timestamptz not null,
    category text not null check (category in ('focus','neutral','drift','away')),
    source text not null check (source in ('rule','manual','localAI','cloudAI')),
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists mac_activity_records_user_started_idx
    on public.mac_activity_records (user_id, started_at desc);

create table if not exists public.mac_focus_sessions (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    intention text not null,
    mode text not null check (mode in ('classic','adaptive','open','micro','academic')),
    started_at timestamptz not null,
    planned_minutes integer,
    ended_at timestamptz,
    reflection jsonb,
    paused_seconds double precision,
    is_locked boolean not null default false,
    restrict_to_intention boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists mac_focus_sessions_user_started_idx
    on public.mac_focus_sessions (user_id, started_at desc);
alter table public.mac_focus_sessions add column if not exists is_locked boolean not null default false;
alter table public.mac_focus_sessions add column if not exists restrict_to_intention boolean not null default false;

alter table public.mac_activity_records enable row level security;
alter table public.mac_focus_sessions enable row level security;
drop policy if exists "mac_activity_records_own" on public.mac_activity_records;
create policy "mac_activity_records_own" on public.mac_activity_records
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "mac_focus_sessions_own" on public.mac_focus_sessions;
create policy "mac_focus_sessions_own" on public.mac_focus_sessions
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.mac_activity_records to authenticated;
grant select, insert, update, delete on public.mac_focus_sessions to authenticated;

create table if not exists public.mac_recall_checkins (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    app_or_domain text not null,
    actual_minutes_today integer not null,
    described_activity text not null default '',
    checked_at timestamptz not null,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists mac_recall_checkins_user_checked_idx
    on public.mac_recall_checkins (user_id, checked_at desc);
alter table public.mac_recall_checkins enable row level security;
drop policy if exists "mac_recall_checkins_own" on public.mac_recall_checkins;
create policy "mac_recall_checkins_own" on public.mac_recall_checkins
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.mac_recall_checkins to authenticated;

create table if not exists public.user_push_devices (
    user_id uuid not null references auth.users(id) on delete cascade,
    installation_id text not null,
    device_token text not null,
    environment text not null check (environment in ('sandbox','production')),
    updated_at timestamptz not null default now(),
    primary key (user_id, installation_id)
);
alter table public.user_push_devices enable row level security;
drop policy if exists "user_push_devices_own" on public.user_push_devices;
create policy "user_push_devices_own" on public.user_push_devices
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.user_push_devices to authenticated;

-- Mac onboarding answers (theme, focus protection, calendar auto-focus,
-- notifications, stated intention), persisted so they survive a
-- reinstall/new Mac. See mivomac/Supabase/20260821120000_mac_preferences_sync.sql.
create table if not exists public.mac_preferences (
    user_id uuid primary key references auth.users(id) on delete cascade,
    theme_mode text,
    tracking_enabled boolean,
    capture_window_titles boolean,
    capture_browser_urls boolean,
    strict_focus_enabled boolean,
    close_drift_apps boolean,
    notifications_enabled boolean,
    calendar_auto_focus_enabled boolean,
    sync_focus_to_phone boolean,
    drift_threshold_minutes integer,
    intention_title text,
    intention_detail text,
    onboarding_complete boolean not null default false,
    raw_preferences jsonb not null default '{}'::jsonb,
    raw_intent jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);
alter table public.mac_preferences enable row level security;
drop policy if exists "mac_preferences_own" on public.mac_preferences;
create policy "mac_preferences_own" on public.mac_preferences
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.mac_preferences to authenticated;

-- Windows companion app (mivowindows) — same shape as the mac_* tables
-- above, adapted to process names instead of bundle IDs since that's the
-- closest equivalent identifier available on Windows.
create table if not exists public.windows_activity_records (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    process_name text not null,
    window_title text not null,
    url_string text,
    started_at timestamptz not null,
    ended_at timestamptz not null,
    category text not null check (category in ('focus','neutral','drift','away')),
    source text not null check (source in ('rule','manual')),
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists windows_activity_records_user_started_idx
    on public.windows_activity_records (user_id, started_at desc);

create table if not exists public.windows_focus_sessions (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    intention text not null,
    mode text not null check (mode in ('classic','adaptive','open','micro','academic')),
    started_at timestamptz not null,
    planned_minutes integer,
    ended_at timestamptz,
    reflection jsonb,
    paused_seconds double precision,
    is_locked boolean not null default false,
    restrict_to_intention boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists windows_focus_sessions_user_started_idx
    on public.windows_focus_sessions (user_id, started_at desc);

create table if not exists public.windows_preferences (
    user_id uuid primary key references auth.users(id) on delete cascade,
    tracking_enabled boolean not null default true,
    close_drift_apps boolean not null default false,
    strict_focus_enabled boolean not null default true,
    notifications_enabled boolean not null default false,
    launch_at_login boolean not null default false,
    onboarding_complete boolean not null default false,
    intention_title text,
    raw_preferences jsonb not null default '{}'::jsonb,
    raw_intent jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);

alter table public.windows_activity_records enable row level security;
alter table public.windows_focus_sessions enable row level security;
alter table public.windows_preferences enable row level security;
drop policy if exists "windows_activity_records_own" on public.windows_activity_records;
create policy "windows_activity_records_own" on public.windows_activity_records
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "windows_focus_sessions_own" on public.windows_focus_sessions;
create policy "windows_focus_sessions_own" on public.windows_focus_sessions
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "windows_preferences_own" on public.windows_preferences;
create policy "windows_preferences_own" on public.windows_preferences
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update, delete on public.windows_activity_records to authenticated;
grant select, insert, update, delete on public.windows_focus_sessions to authenticated;
grant select, insert, update, delete on public.windows_preferences to authenticated;

-- Mivo Spots: official physical Spots (see supabase/migrations/20261019130000_physical_spots.sql).
create extension if not exists pgcrypto;

create table if not exists public.physical_spot_batches (
    id uuid primary key default gen_random_uuid(),
    label text not null check (char_length(label) between 1 and 80),
    spot_count integer not null check (spot_count > 0),
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.physical_spots (
    -- Random, not sequential, and not derived from any database counter.
    spot_id text primary key check (spot_id ~ '^[A-Z0-9]{6,12}$'),
    status text not null default 'unclaimed' check (status in ('unclaimed', 'claimed', 'disabled')),
    owner_user_id uuid references auth.users(id) on delete set null,
    batch_id uuid references public.physical_spot_batches(id) on delete set null,
    claimed_at timestamptz,
    created_at timestamptz not null default now(),
    disabled_at timestamptz,
    disabled_reason text,
    updated_at timestamptz not null default now()
);

create index if not exists physical_spots_owner_idx on public.physical_spots (owner_user_id) where owner_user_id is not null;
create index if not exists physical_spots_batch_idx on public.physical_spots (batch_id, created_at);
create index if not exists physical_spots_status_idx on public.physical_spots (status);

-- Failed lookups, kept briefly so guessing IDs can be throttled.
create table if not exists public.physical_spot_failed_lookups (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    looked_up_at timestamptz not null default now()
);
create index if not exists physical_spot_failed_lookups_user_idx
    on public.physical_spot_failed_lookups (user_id, looked_up_at desc);

alter table public.physical_spot_batches enable row level security;
alter table public.physical_spots enable row level security;
alter table public.physical_spot_failed_lookups enable row level security;
revoke all on public.physical_spot_batches from anon, authenticated;
revoke all on public.physical_spots from anon, authenticated;
revoke all on public.physical_spot_failed_lookups from anon, authenticated;

-- If an owner's account is deleted the Spot becomes claimable again, so the
-- tag a customer paid for is not stranded.
create or replace function public.physical_spots_before_update()
returns trigger
language plpgsql
as $$
begin
    if old.owner_user_id is not null and new.owner_user_id is null then
        new.claimed_at := null;
        if new.status = 'claimed' then new.status := 'unclaimed'; end if;
    end if;
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists physical_spots_before_update on public.physical_spots;
create trigger physical_spots_before_update
    before update on public.physical_spots
    for each row execute function public.physical_spots_before_update();

-- ---------------------------------------------------------------------------
-- ID generation (manufacturing)
-- ---------------------------------------------------------------------------

-- 31 characters, no I/L/O/0/1, so an ID read aloud or printed on a box is
-- unambiguous. Rejection sampling keeps every character equally likely.
create or replace function public._physical_spot_new_id(id_length integer default 8)
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    result text := '';
    random_bytes bytea;
    idx integer;
    byte_value integer;
begin
    if id_length < 6 or id_length > 12 then raise exception 'invalid_id_length'; end if;
    while char_length(result) < id_length loop
        random_bytes := extensions.gen_random_bytes(32);
        for idx in 0..31 loop
            byte_value := get_byte(random_bytes, idx);
            if byte_value < 248 then -- 248 = 8 * 31
                result := result || substr(alphabet, (byte_value % 31) + 1, 1);
                exit when char_length(result) = id_length;
            end if;
        end loop;
    end loop;
    return result;
end;
$$;

-- The generator itself. Not callable from the app: run it from the Supabase
-- SQL editor (as the project owner), or go through admin_generate_physical_spots.
--   select * from public._generate_physical_spots(100, 'Batch 1');
create or replace function public._generate_physical_spots(
    input_count integer,
    input_label text,
    input_actor uuid default null,
    input_id_length integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    new_batch_id uuid;
    created_ids text[] := '{}';
    candidate text;
    attempts integer := 0;
    result jsonb;
begin
    if input_count is null or input_count < 1 or input_count > 5000 then raise exception 'invalid_count'; end if;
    if input_label is null or char_length(trim(input_label)) = 0 then raise exception 'label_required'; end if;

    insert into public.physical_spot_batches (label, spot_count, created_by)
    values (left(trim(input_label), 80), input_count, input_actor)
    returning id into new_batch_id;

    while coalesce(array_length(created_ids, 1), 0) < input_count loop
        attempts := attempts + 1;
        if attempts > input_count * 20 then raise exception 'id_space_exhausted'; end if;
        candidate := public._physical_spot_new_id(input_id_length);
        insert into public.physical_spots (spot_id, batch_id)
        values (candidate, new_batch_id)
        on conflict (spot_id) do nothing;
        if found then created_ids := created_ids || candidate; end if;
    end loop;

    select jsonb_build_object(
        'batch_id', new_batch_id,
        'label', left(trim(input_label), 80),
        'spots', coalesce(jsonb_agg(jsonb_build_object(
            'spot_id', s.spot_id,
            'url', 'https://usemivo.app/s/' || s.spot_id,
            'status', s.status,
            'created_at', s.created_at
        ) order by s.created_at, s.spot_id), '[]'::jsonb)
    ) into result
    from public.physical_spots s
    where s.batch_id = new_batch_id;

    return result;
end;
$$;

revoke all on function public._physical_spot_new_id(integer) from public, anon, authenticated;
revoke all on function public._generate_physical_spots(integer, text, uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Customer-facing
-- ---------------------------------------------------------------------------

-- Throttle guessing: too many unknown IDs in a short window stops further lookups.
create or replace function public._physical_spot_check_rate(caller uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if (select count(*) from public.physical_spot_failed_lookups
        where user_id = caller and looked_up_at > now() - interval '15 minutes') >= 15 then
        raise exception 'rate_limited';
    end if;
end;
$$;

create or replace function public._physical_spot_note_failure(caller uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.physical_spot_failed_lookups where looked_up_at < now() - interval '1 day';
    insert into public.physical_spot_failed_lookups (user_id) values (caller);
end;
$$;

revoke all on function public._physical_spot_check_rate(uuid) from public, anon, authenticated;
revoke all on function public._physical_spot_note_failure(uuid) from public, anon, authenticated;

-- What is this ID to me? Never says who owns a Spot someone else has claimed.
--   invalid   no such ID
--   unclaimed anyone signed in may claim it
--   yours     already claimed by the caller (a new phone, or data cleared)
--   taken     claimed by someone else
--   disabled  switched off by Mivo
create or replace function public.resolve_physical_spot(input_spot_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    found_spot public.physical_spots;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    perform public._physical_spot_check_rate(caller);

    select * into found_spot from public.physical_spots where spot_id = wanted;
    if not found then
        perform public._physical_spot_note_failure(caller);
        return jsonb_build_object('state', 'invalid');
    end if;
    if found_spot.status = 'disabled' then return jsonb_build_object('state', 'disabled'); end if;
    if found_spot.owner_user_id is null then return jsonb_build_object('state', 'unclaimed'); end if;
    if found_spot.owner_user_id = caller then
        return jsonb_build_object('state', 'yours', 'claimed_at', found_spot.claimed_at);
    end if;
    return jsonb_build_object('state', 'taken');
end;
$$;

-- Atomic: of two people claiming the same unclaimed Spot, exactly one wins.
-- Claiming a Spot you already own succeeds again (a retry after a dropped
-- connection is not an error).
create or replace function public.claim_physical_spot(input_spot_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    claimed_spot public.physical_spots;
    existing public.physical_spots;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    perform public._physical_spot_check_rate(caller);

    update public.physical_spots
    set owner_user_id = caller, status = 'claimed', claimed_at = now()
    where spot_id = wanted and status = 'unclaimed' and owner_user_id is null
    returning * into claimed_spot;
    if found then
        return jsonb_build_object('state', 'claimed', 'owner_user_id', caller, 'claimed_at', claimed_spot.claimed_at);
    end if;

    select * into existing from public.physical_spots where spot_id = wanted;
    if not found then
        perform public._physical_spot_note_failure(caller);
        return jsonb_build_object('state', 'invalid');
    end if;
    if existing.status = 'disabled' then return jsonb_build_object('state', 'disabled'); end if;
    if existing.owner_user_id = caller then
        return jsonb_build_object('state', 'claimed', 'owner_user_id', caller, 'claimed_at', existing.claimed_at);
    end if;
    return jsonb_build_object('state', 'taken');
end;
$$;

-- Lets an owner hand a Spot on (gift, resale) or start over. No-op for anyone else.
create or replace function public.release_physical_spot(input_spot_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    update public.physical_spots
    set owner_user_id = null,
        claimed_at = null,
        status = case when status = 'disabled' then 'disabled' else 'unclaimed' end
    where spot_id = upper(trim(coalesce(input_spot_id, ''))) and owner_user_id = caller;
end;
$$;

-- The caller's own Spots, so a phone can notice a Spot that was disabled,
-- released or moved on another device.
create or replace function public.my_physical_spots()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'spot_id', s.spot_id, 'status', s.status, 'claimed_at', s.claimed_at
        ) order by s.claimed_at)
        from public.physical_spots s
        where s.owner_user_id = caller
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.resolve_physical_spot(text) from public, anon;
revoke all on function public.claim_physical_spot(text) from public, anon;
revoke all on function public.release_physical_spot(text) from public, anon;
revoke all on function public.my_physical_spots() from public, anon;
grant execute on function public.resolve_physical_spot(text) to authenticated;
grant execute on function public.claim_physical_spot(text) to authenticated;
grant execute on function public.release_physical_spot(text) to authenticated;
grant execute on function public.my_physical_spots() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin / manufacturing
-- ---------------------------------------------------------------------------

create or replace function public.admin_generate_physical_spots(input_count integer, input_label text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    result jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    result := public._generate_physical_spots(input_count, input_label, auth.uid());
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), 'physical_spots_generated', 'physical_spot_batch', result->>'batch_id',
            jsonb_build_object('label', result->>'label', 'count', input_count));
    return result;
end;
$$;

create or replace function public.admin_physical_spot_batches()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', b.id, 'label', b.label, 'spot_count', b.spot_count, 'created_at', b.created_at,
            'claimed_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.owner_user_id is not null),
            'disabled_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.status = 'disabled')
        ) order by b.created_at desc)
        from public.physical_spot_batches b
    ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_physical_spots(
    input_batch_id uuid default null,
    input_status text default null,
    input_limit integer default 200,
    input_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    page_size integer := least(greatest(coalesce(input_limit, 200), 1), 1000);
    page_offset integer := greatest(coalesce(input_offset, 0), 0);
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status is not null and input_status not in ('unclaimed', 'claimed', 'disabled') then
        raise exception 'invalid_status';
    end if;
    return jsonb_build_object(
        'total', (select count(*) from public.physical_spots s
                  where (input_batch_id is null or s.batch_id = input_batch_id)
                    and (input_status is null or s.status = input_status)),
        'spots', coalesce((
            select jsonb_agg(row_to_json(page)::jsonb order by page.created_at, page.spot_id)
            from (
                select s.spot_id, 'https://usemivo.app/s/' || s.spot_id as url, s.status,
                       b.label as batch_label, s.created_at, s.claimed_at,
                       p.email as owner_email
                from public.physical_spots s
                left join public.physical_spot_batches b on b.id = s.batch_id
                left join public.user_profiles p on p.user_id = s.owner_user_id
                where (input_batch_id is null or s.batch_id = input_batch_id)
                  and (input_status is null or s.status = input_status)
                order by s.created_at, s.spot_id
                limit page_size offset page_offset
            ) page
        ), '[]'::jsonb)
    );
end;
$$;

create or replace function public.admin_physical_spot_status(input_spot_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    result jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select row_to_json(detail)::jsonb into result
    from (
        select s.spot_id, 'https://usemivo.app/s/' || s.spot_id as url, s.status,
               b.label as batch_label, s.created_at, s.claimed_at, s.disabled_at,
               s.disabled_reason, p.email as owner_email
        from public.physical_spots s
        left join public.physical_spot_batches b on b.id = s.batch_id
        left join public.user_profiles p on p.user_id = s.owner_user_id
        where s.spot_id = upper(trim(coalesce(input_spot_id, '')))
    ) detail;
    if result is null then raise exception 'spot_not_found'; end if;
    return result;
end;
$$;

-- Disabling keeps the owner, so enabling again restores exactly what it was.
create or replace function public.admin_set_physical_spot_disabled(
    input_spot_id text,
    input_disabled boolean,
    input_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select to_jsonb(s) into before_row from public.physical_spots s where spot_id = wanted;
    if before_row is null then raise exception 'spot_not_found'; end if;

    update public.physical_spots
    set status = case
            when input_disabled then 'disabled'
            when owner_user_id is null then 'unclaimed'
            else 'claimed'
        end,
        disabled_at = case when input_disabled then now() else null end,
        disabled_reason = case when input_disabled then left(input_reason, 200) else null end
    where spot_id = wanted;

    select to_jsonb(s) into after_row from public.physical_spots s where spot_id = wanted;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, reason, before_value, after_value)
    values (auth.uid(),
            case when input_disabled then 'physical_spot_disabled' else 'physical_spot_enabled' end,
            'physical_spot', wanted, input_reason, before_row, after_row);
end;
$$;

revoke all on function public.admin_generate_physical_spots(integer, text) from public, anon;
revoke all on function public.admin_physical_spot_batches() from public, anon;
revoke all on function public.admin_list_physical_spots(uuid, text, integer, integer) from public, anon;
revoke all on function public.admin_physical_spot_status(text) from public, anon;
revoke all on function public.admin_set_physical_spot_disabled(text, boolean, text) from public, anon;
grant execute on function public.admin_generate_physical_spots(integer, text) to authenticated;
grant execute on function public.admin_physical_spot_batches() to authenticated;
grant execute on function public.admin_list_physical_spots(uuid, text, integer, integer) to authenticated;
grant execute on function public.admin_physical_spot_status(text) to authenticated;
grant execute on function public.admin_set_physical_spot_disabled(text, boolean, text) to authenticated;
