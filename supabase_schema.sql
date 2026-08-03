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
    referral_ambassador_name text,
    referral_campaign_code text,
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

alter table public.onboarding_profiles
    add column if not exists referral_ambassador_name text;
alter table public.onboarding_profiles
    add column if not exists referral_campaign_code text;

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

-- Referral campaign, super-admin, official rules, and parental consent.
create extension if not exists pgcrypto;

create table if not exists public.app_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    role text not null check (role in ('super_admin', 'admin')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.referral_campaigns (
    id uuid primary key default gen_random_uuid(),
    name text not null default 'Mivo Referral Campaign',
    description text not null default 'Invite people to build a more intentional relationship with scrolling.',
    status text not null default 'draft' check (status in ('draft', 'active', 'paused', 'ended')),
    starts_at timestamptz,
    ends_at timestamptz,
    timezone text not null default 'America/New_York',
    first_prize_cents integer not null default 15000 check (first_prize_cents >= 0),
    second_prize_cents integer not null default 10000 check (second_prize_cents >= 0),
    third_prize_cents integer not null default 5000 check (third_prize_cents >= 0),
    reward_type text not null default 'cash',
    rules_pdf_url text,
    rules_version text not null default '0.1-draft',
    rules_hash text,
    rules_published_at timestamptz,
    terms_url text,
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (starts_at is null or ends_at is null or starts_at < ends_at)
);

drop index if exists public.one_live_referral_campaign_idx;
create unique index one_live_referral_campaign_idx
    on public.referral_campaigns ((1)) where status in ('active', 'paused');

create table if not exists public.referral_milestones (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null references public.referral_campaigns(id) on delete cascade,
    target_count integer not null check (target_count > 0),
    reward_description text,
    created_at timestamptz not null default now(),
    unique (campaign_id, target_count)
);

create table if not exists public.campaign_rule_versions (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null references public.referral_campaigns(id) on delete cascade,
    version text not null,
    storage_path text not null,
    sha256 text not null,
    is_draft boolean not null default true,
    published_by uuid not null references auth.users(id),
    effective_at timestamptz,
    created_at timestamptz not null default now(),
    unique (campaign_id, version)
);

create table if not exists public.referral_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    referral_code text not null unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (referral_code ~ '^MIVO-[A-Z0-9]{6}$')
);

create table if not exists public.referral_attributions (
    id uuid primary key default gen_random_uuid(),
    campaign_id uuid not null references public.referral_campaigns(id) on delete cascade,
    referred_user_id uuid not null unique references auth.users(id) on delete cascade,
    referrer_user_id uuid not null references auth.users(id) on delete cascade,
    code_used text not null,
    status text not null default 'pending' check (status in ('pending', 'qualified', 'disqualified')),
    attached_at timestamptz not null default now(),
    qualified_at timestamptz,
    disqualified_at timestamptz,
    disqualification_reason text,
    updated_at timestamptz not null default now(),
    check (referred_user_id <> referrer_user_id)
);

create index if not exists referral_attributions_referrer_idx
    on public.referral_attributions (campaign_id, referrer_user_id, status, qualified_at);

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

create or replace function public.generate_mivo_referral_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    candidate text;
begin
    loop
        candidate := 'MIVO-' || upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text), 1, 6));
        exit when not exists (select 1 from public.referral_profiles where referral_code = candidate);
    end loop;
    return candidate;
end;
$$;

create or replace function public.bootstrap_mivo_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    insert into public.referral_profiles (user_id, referral_code)
    values (new.id, public.generate_mivo_referral_code())
    on conflict (user_id) do nothing;

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

insert into public.referral_profiles (user_id, referral_code)
select u.id, public.generate_mivo_referral_code()
from auth.users u
where not exists (select 1 from public.referral_profiles p where p.user_id = u.id);

delete from public.app_admins where role = 'super_admin'
    and user_id not in (select id from auth.users where lower(email) = 'pranshuraithatha0@gmail.com');
insert into public.app_admins (user_id, email, role)
select id, lower(email), 'super_admin' from auth.users
where lower(email) = 'pranshuraithatha0@gmail.com'
on conflict (user_id) do update set email = excluded.email, role = excluded.role, updated_at = now();

insert into public.referral_campaigns (name, description, status, rules_version)
select 'Mivo Referral Campaign', 'Invite people to build a more intentional relationship with scrolling.', 'draft', '0.1-draft'
where not exists (select 1 from public.referral_campaigns);

insert into public.referral_milestones (campaign_id, target_count)
select c.id, t.target
from public.referral_campaigns c
cross join unnest(array[1, 3, 5, 10, 20]) as t(target)
on conflict (campaign_id, target_count) do nothing;

alter table public.app_admins enable row level security;
alter table public.referral_campaigns enable row level security;
alter table public.referral_milestones enable row level security;
alter table public.campaign_rule_versions enable row level security;
alter table public.referral_profiles enable row level security;
alter table public.referral_attributions enable row level security;
alter table public.parental_consent_requests enable row level security;
alter table public.parental_consent_records enable row level security;
alter table public.admin_audit_log enable row level security;

drop policy if exists "admin_role_self_read" on public.app_admins;
create policy "admin_role_self_read" on public.app_admins
    for select to authenticated using (user_id = auth.uid() or public.is_super_admin());

drop policy if exists "campaign_user_read" on public.referral_campaigns;
create policy "campaign_user_read" on public.referral_campaigns
    for select to authenticated using (status in ('active', 'paused', 'ended') or public.is_super_admin());
drop policy if exists "campaign_admin_write" on public.referral_campaigns;
create policy "campaign_admin_write" on public.referral_campaigns
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "milestone_user_read" on public.referral_milestones;
create policy "milestone_user_read" on public.referral_milestones
    for select to authenticated using (
        public.is_super_admin() or exists (
            select 1 from public.referral_campaigns c
            where c.id = campaign_id and c.status in ('active', 'paused', 'ended')
        )
    );
drop policy if exists "milestone_admin_write" on public.referral_milestones;
create policy "milestone_admin_write" on public.referral_milestones
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

drop policy if exists "campaign_rule_user_read" on public.campaign_rule_versions;
create policy "campaign_rule_user_read" on public.campaign_rule_versions
    for select to authenticated using (
        public.is_super_admin() or exists (
            select 1 from public.referral_campaigns c
            where c.id = campaign_id and c.status in ('active', 'paused', 'ended') and not is_draft
        )
    );
drop policy if exists "campaign_rule_admin_insert" on public.campaign_rule_versions;
create policy "campaign_rule_admin_insert" on public.campaign_rule_versions
    for insert to authenticated with check (public.is_super_admin() and published_by = auth.uid());

create or replace function public.protect_referral_campaign_terms()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'active' then
        if new.starts_at is null or new.ends_at is null or new.ends_at <= new.starts_at then
            raise exception 'campaign_dates_required';
        end if;
        if new.rules_pdf_url is null or new.rules_hash is null or lower(new.rules_version) like '%draft%' then
            raise exception 'final_rules_required';
        end if;
    end if;

    if old.status in ('active', 'paused', 'ended') and lower(old.rules_version) not like '%draft%' then
        if new.starts_at is distinct from old.starts_at
            or new.timezone is distinct from old.timezone
            or new.first_prize_cents is distinct from old.first_prize_cents
            or new.second_prize_cents is distinct from old.second_prize_cents
            or new.third_prize_cents is distinct from old.third_prize_cents
            or new.rules_pdf_url is distinct from old.rules_pdf_url
            or new.rules_hash is distinct from old.rules_hash
            or new.rules_version is distinct from old.rules_version then
            raise exception 'active_campaign_terms_locked';
        end if;
        if new.ends_at < old.ends_at then raise exception 'campaign_end_can_only_be_extended'; end if;
    end if;
    return new;
end;
$$;
drop trigger if exists protect_referral_campaign_terms_trigger on public.referral_campaigns;
create trigger protect_referral_campaign_terms_trigger
    before update on public.referral_campaigns
    for each row execute function public.protect_referral_campaign_terms();

drop policy if exists "referral_profile_self_read" on public.referral_profiles;
create policy "referral_profile_self_read" on public.referral_profiles
    for select to authenticated using (user_id = auth.uid() or public.is_super_admin());

drop policy if exists "referral_admin_read" on public.referral_attributions;
create policy "referral_admin_read" on public.referral_attributions
    for select to authenticated using (public.is_super_admin());

drop policy if exists "consent_admin_all" on public.parental_consent_requests;
create policy "consent_admin_all" on public.parental_consent_requests
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "consent_record_admin_all" on public.parental_consent_records;
create policy "consent_record_admin_all" on public.parental_consent_records
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "audit_admin_read" on public.admin_audit_log;
create policy "audit_admin_read" on public.admin_audit_log
    for select to authenticated using (public.is_super_admin());

create or replace function public.attach_referral_code(input_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    campaign public.referral_campaigns%rowtype;
    referrer uuid;
    normalized text := upper(trim(input_code));
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    select * into campaign from public.referral_campaigns
    where status = 'active' and starts_at <= now() and ends_at > now()
    order by starts_at desc limit 1;
    if campaign.id is null then raise exception 'no_active_campaign'; end if;

    select user_id into referrer from public.referral_profiles where referral_code = normalized;
    if referrer is null then raise exception 'invalid_referral_code'; end if;
    if referrer = auth.uid() then raise exception 'self_referral_not_allowed'; end if;
    if exists (select 1 from public.referral_attributions where referred_user_id = auth.uid()) then
        raise exception 'referral_already_attached';
    end if;

    insert into public.referral_attributions (
        campaign_id, referred_user_id, referrer_user_id, code_used
    ) values (campaign.id, auth.uid(), referrer, normalized);

    return jsonb_build_object('status', 'pending', 'code', normalized, 'campaign_id', campaign.id);
end;
$$;
grant execute on function public.attach_referral_code(text) to authenticated;

create or replace function public.qualify_referral_after_onboarding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.onboarding_complete and (tg_op = 'INSERT' or not coalesce(old.onboarding_complete, false)) then
        update public.referral_attributions
        set status = 'qualified', qualified_at = coalesce(qualified_at, now()), updated_at = now()
        where referred_user_id = new.user_id and status = 'pending';
    end if;
    return new;
end;
$$;
drop trigger if exists qualify_referral_on_onboarding on public.app_settings;
create trigger qualify_referral_on_onboarding
    after insert or update of onboarding_complete on public.app_settings
    for each row execute function public.qualify_referral_after_onboarding();

create or replace function public.get_my_referral_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    campaign public.referral_campaigns%rowtype;
    code text;
    qualified_count integer := 0;
    pending_count integer := 0;
    next_target integer;
    private_rank integer;
    people jsonb := '[]'::jsonb;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    insert into public.referral_profiles (user_id, referral_code)
    values (auth.uid(), public.generate_mivo_referral_code()) on conflict (user_id) do nothing;
    select referral_code into code from public.referral_profiles where user_id = auth.uid();

    select * into campaign from public.referral_campaigns
    where status in ('active', 'paused', 'ended')
    order by case status when 'active' then 0 when 'paused' then 1 else 2 end, coalesce(ends_at, updated_at) desc
    limit 1;

    if campaign.id is not null then
        select count(*) filter (where status = 'qualified'), count(*) filter (where status = 'pending')
        into qualified_count, pending_count
        from public.referral_attributions
        where campaign_id = campaign.id and referrer_user_id = auth.uid();

        select min(target_count) into next_target from public.referral_milestones
        where campaign_id = campaign.id and target_count > qualified_count;

        with totals as (
            select referrer_user_id, count(*) as total, max(qualified_at) as reached_at
            from public.referral_attributions
            where campaign_id = campaign.id and status = 'qualified'
            group by referrer_user_id
        ), ranked as (
            select referrer_user_id, dense_rank() over (order by total desc, reached_at asc) as rank
            from totals
        ) select rank into private_rank from ranked where referrer_user_id = auth.uid();

        select coalesce(jsonb_agg(jsonb_build_object(
            'id', a.id, 'first_name', split_part(coalesce(p.name, 'Mivo user'), ' ', 1),
            'status', a.status, 'date', a.attached_at
        ) order by a.attached_at desc), '[]'::jsonb)
        into people
        from public.referral_attributions a
        left join public.user_profiles p on p.user_id = a.referred_user_id
        where a.campaign_id = campaign.id and a.referrer_user_id = auth.uid();
    end if;

    return jsonb_build_object(
        'referral_code', code,
        'qualified_count', qualified_count,
        'pending_count', pending_count,
        'next_milestone', next_target,
        'private_rank', private_rank,
        'referred_users', people,
        'campaign', case when campaign.id is null then null else jsonb_build_object(
            'id', campaign.id, 'name', campaign.name, 'description', campaign.description,
            'status', campaign.status, 'starts_at', campaign.starts_at, 'ends_at', campaign.ends_at,
            'timezone', campaign.timezone, 'first_prize_cents', campaign.first_prize_cents,
            'second_prize_cents', campaign.second_prize_cents, 'third_prize_cents', campaign.third_prize_cents,
            'rules_pdf_url', campaign.rules_pdf_url, 'rules_version', campaign.rules_version,
            'rules_published_at', campaign.rules_published_at
        ) end
    );
end;
$$;
grant execute on function public.get_my_referral_summary() to authenticated;

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

create or replace function public.admin_referral_dashboard()
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
        'campaigns', coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from public.referral_campaigns c), '[]'::jsonb),
        'standings', coalesce((
            select jsonb_agg(row_data order by (row_data->>'qualified_count')::int desc, row_data->>'reached_at' asc)
            from (
                select jsonb_build_object(
                    'campaign_id', a.campaign_id,
                    'user_id', a.referrer_user_id, 'name', coalesce(p.name, 'Mivo user'), 'email', p.email,
                    'referral_code', rp.referral_code,
                    'qualified_count', count(*) filter (where a.status = 'qualified'),
                    'pending_count', count(*) filter (where a.status = 'pending'),
                    'reached_at', max(a.qualified_at)
                ) row_data
                from public.referral_attributions a
                left join public.user_profiles p on p.user_id = a.referrer_user_id
                left join public.referral_profiles rp on rp.user_id = a.referrer_user_id
                group by a.campaign_id, a.referrer_user_id, p.name, p.email, rp.referral_code
            ) s
        ), '[]'::jsonb),
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
grant execute on function public.admin_referral_dashboard() to authenticated;

create or replace function public.admin_create_referral_campaign()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    created public.referral_campaigns%rowtype;
    campaign_number integer;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if exists (select 1 from public.referral_campaigns where status in ('draft', 'active', 'paused')) then
        raise exception 'finish_current_campaign_first';
    end if;

    select count(*) + 1 into campaign_number from public.referral_campaigns;
    insert into public.referral_campaigns (name, description, status, rules_version, created_by)
    values (
        'Mivo Referral Campaign ' || campaign_number,
        'Invite people to build a more intentional relationship with scrolling.',
        'draft',
        '0.1-draft',
        auth.uid()
    ) returning * into created;

    insert into public.referral_milestones (campaign_id, target_count)
    select created.id, target from unnest(array[1, 3, 5, 10, 20]) target;

    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), 'campaign_created', 'referral_campaign', created.id::text, to_jsonb(created));

    return to_jsonb(created);
end;
$$;
grant execute on function public.admin_create_referral_campaign() to authenticated;

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
        'reports', coalesce((select jsonb_agg(to_jsonb(w) order by w.week_start desc) from public.weekly_reports w where w.user_id = input_user_id), '[]'::jsonb),
        'referral', (select to_jsonb(r) from public.referral_profiles r where r.user_id = input_user_id)
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

create or replace function public.admin_set_referral_status(
    input_attribution_id uuid, input_status text, input_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_row jsonb;
    after_row jsonb;
    target uuid;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status not in ('pending', 'qualified', 'disqualified') then raise exception 'invalid_status'; end if;
    select to_jsonb(a), a.referred_user_id into before_row, target
    from public.referral_attributions a where id = input_attribution_id;
    update public.referral_attributions set
        status = input_status,
        qualified_at = case when input_status = 'qualified' then coalesce(qualified_at, now()) else null end,
        disqualified_at = case when input_status = 'disqualified' then now() else null end,
        disqualification_reason = case when input_status = 'disqualified' then input_reason else null end,
        updated_at = now()
    where id = input_attribution_id;
    select to_jsonb(a) into after_row from public.referral_attributions a where id = input_attribution_id;
    insert into public.admin_audit_log (actor_user_id, action, target_user_id, target_type, target_id, reason, before_value, after_value)
    values (auth.uid(), 'referral_status_' || input_status, target, 'referral_attribution', input_attribution_id::text, input_reason, before_row, after_row);
end;
$$;
grant execute on function public.admin_set_referral_status(uuid, text, text) to authenticated;

create or replace function public.audit_campaign_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is not null then
        insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, before_value, after_value)
        values (auth.uid(), 'campaign_' || lower(tg_op), 'referral_campaign', coalesce(new.id, old.id)::text,
                case when tg_op = 'INSERT' then null else to_jsonb(old) end,
                case when tg_op = 'DELETE' then null else to_jsonb(new) end);
    end if;
    if tg_op = 'DELETE' then return old; end if;
    return new;
end;
$$;
drop trigger if exists audit_referral_campaign_changes on public.referral_campaigns;
create trigger audit_referral_campaign_changes
    after insert or update or delete on public.referral_campaigns
    for each row execute function public.audit_campaign_change();

insert into storage.buckets (id, name, public)
values ('campaign-rules', 'campaign-rules', false)
on conflict (id) do update set public = false;

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

drop policy if exists "authenticated_read_campaign_rules" on storage.objects;
create policy "authenticated_read_campaign_rules" on storage.objects
    for select to authenticated using (bucket_id = 'campaign-rules');
drop policy if exists "super_admin_manage_campaign_rules" on storage.objects;
create policy "super_admin_manage_campaign_rules" on storage.objects
    for all to authenticated using (bucket_id = 'campaign-rules' and public.is_super_admin())
    with check (bucket_id = 'campaign-rules' and public.is_super_admin());

drop policy if exists "super_admin_manage_parental_evidence" on storage.objects;
create policy "super_admin_manage_parental_evidence" on storage.objects
    for all to authenticated using (bucket_id = 'parental-consent-evidence' and public.is_super_admin())
    with check (bucket_id = 'parental-consent-evidence' and public.is_super_admin());
