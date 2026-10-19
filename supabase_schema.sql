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
    updated_at timestamptz not null default now()
);

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
    actor_user_id uuid references auth.users(id),
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
