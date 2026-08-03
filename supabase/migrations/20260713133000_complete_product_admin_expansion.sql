-- Native product expansion, reliability, rollout controls, privacy, and founder tooling.
-- Administrative access remains inside the iPhone app and is enforced here.

create extension if not exists pgcrypto;

create table if not exists public.feature_flags (
    key text primary key,
    enabled boolean not null default false,
    rollout_percentage integer not null default 0 check (rollout_percentage in (0, 5, 25, 50, 100)),
    minimum_version text,
    target_role text check (target_role is null or target_role in ('user', 'admin', 'ambassador', 'super_admin')),
    founder_preview boolean not null default true,
    automatically_paused boolean not null default false,
    pause_reason text,
    updated_by uuid references auth.users(id) on delete set null,
    updated_at timestamptz not null default now()
);

insert into public.feature_flags(key, enabled, rollout_percentage, founder_preview) values
    ('today_guide', true, 100, true),
    ('recovery_mode', true, 100, true),
    ('live_activities', true, 100, true),
    ('app_personalities', true, 100, true),
    ('monthly_effect_report', true, 100, true),
    ('experiment_library', true, 100, true),
    ('accountability_partners', false, 0, true),
    ('diagnostics', false, 0, true)
on conflict (key) do nothing;

create table if not exists public.client_health_events (
    id bigint generated always as identity primary key,
    user_id uuid references auth.users(id) on delete set null,
    kind text not null,
    related_feature text references public.feature_flags(key) on delete set null,
    app_version text,
    ios_version text,
    device_family text,
    success boolean not null default true,
    duration_ms integer check (duration_ms is null or duration_ms between 0 and 600000),
    payload jsonb not null default '{}'::jsonb,
    occurred_at timestamptz not null default now()
);
create index if not exists client_health_events_kind_time_idx on public.client_health_events(kind, occurred_at desc);
create index if not exists client_health_events_feature_time_idx on public.client_health_events(related_feature, occurred_at desc);
create index if not exists client_health_events_version_time_idx on public.client_health_events(app_version, occurred_at desc);

create table if not exists public.release_health_rollups (
    id bigint generated always as identity primary key,
    version text not null,
    rollup_date date not null,
    active_users integer,
    attempts integer,
    crashes integer,
    crash_free_rate numeric,
    login_success_rate numeric,
    sync_success_rate numeric,
    session_completion_rate numeric,
    retention_rate numeric,
    source text not null default 'mivo',
    created_at timestamptz not null default now(),
    unique(version, rollup_date, source)
);

create table if not exists public.data_quality_issues (
    id uuid primary key default gen_random_uuid(),
    issue_key text not null unique,
    issue_type text not null,
    severity text not null default 'warning' check (severity in ('info', 'warning', 'critical')),
    summary text not null,
    affected_user_id uuid references auth.users(id) on delete set null,
    target_table text,
    target_id text,
    repair_payload jsonb not null default '{}'::jsonb,
    status text not null default 'open' check (status in ('open', 'repaired', 'dismissed')),
    auto_repairable boolean not null default false,
    detected_at timestamptz not null default now(),
    resolved_at timestamptz,
    resolved_by uuid references auth.users(id) on delete set null
);
create index if not exists data_quality_issues_open_idx on public.data_quality_issues(status, detected_at desc);

create table if not exists public.recovery_plans (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    date text not null,
    status text not null check (status in ('proposed', 'active', 'completed', 'declined')),
    reason text not null,
    outside_window_minutes integer not null default 0,
    not_worthwhile_extension_count integer not null default 0,
    created_at timestamptz not null default now(),
    resolved_at timestamptz,
    raw_plan jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    primary key(user_id, id)
);

create table if not exists public.monthly_effect_reports (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    month_key text not null,
    valid_days integer not null,
    session_count integer not null,
    report jsonb not null,
    generated_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key(user_id, id),
    unique(user_id, month_key)
);

create table if not exists public.experiment_templates (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid references auth.users(id) on delete cascade,
    type text not null check (type in ('protected_window', 'reduce_extensions', 'stronger_friction')),
    title text not null,
    detail text not null,
    rule jsonb not null default '{}'::jsonb,
    active boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists public.accountability_connections (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    partner_email text not null,
    partner_email_hash text not null,
    status text not null default 'pending' check (status in ('pending', 'active', 'revoked')),
    automatic_sharing_enabled boolean not null default false,
    preview_confirmed_at timestamptz,
    created_at timestamptz not null default now(),
    revoked_at timestamptz,
    unique(owner_user_id, partner_email_hash)
);

create table if not exists public.accountability_summaries (
    id uuid primary key default gen_random_uuid(),
    connection_id uuid not null references public.accountability_connections(id) on delete cascade,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    week_start date not null,
    week_end date not null,
    summary jsonb not null,
    token_hash text not null unique,
    expires_at timestamptz not null,
    sent_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    unique(connection_id, week_start)
);

create table if not exists public.app_store_daily_metrics (
    id bigint generated always as identity primary key,
    metric_date date not null,
    app_version text,
    downloads integer,
    installations integer,
    deletions integer,
    sessions integer,
    crashes integer,
    conversion_rate numeric,
    retention_rate numeric,
    reporting_status text not null default 'unavailable' check (reporting_status in ('available', 'suppressed', 'unavailable', 'delayed')),
    import_id text,
    imported_at timestamptz not null default now(),
    unique(metric_date, app_version, import_id)
);

create table if not exists public.admin_review_items (
    id uuid primary key default gen_random_uuid(),
    type text not null,
    title text not null,
    detail text not null,
    source_table text,
    source_id text,
    status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'archived')),
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    resolved_at timestamptz,
    resolved_by uuid references auth.users(id) on delete set null
);
create unique index if not exists admin_review_items_open_source_idx
    on public.admin_review_items(source_table, source_id, type) where status = 'pending';

create table if not exists public.referral_risk_flags (
    id uuid primary key default gen_random_uuid(),
    attribution_id uuid references public.referral_attributions(id) on delete cascade,
    signal_type text not null,
    risk_score numeric not null default 0 check (risk_score between 0 and 100),
    hashed_installation_signal text,
    detail text not null,
    status text not null default 'review_hold' check (status in ('review_hold', 'cleared', 'confirmed')),
    created_at timestamptz not null default now(),
    reviewed_at timestamptz,
    reviewed_by uuid references auth.users(id) on delete set null
);

create table if not exists public.privacy_requests (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    request_type text not null check (request_type in ('export', 'delete', 'revoke_consent', 'correct_data')),
    status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'rejected')),
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    handled_by uuid references auth.users(id) on delete set null
);

alter table public.feature_flags enable row level security;
alter table public.client_health_events enable row level security;
alter table public.release_health_rollups enable row level security;
alter table public.data_quality_issues enable row level security;
alter table public.recovery_plans enable row level security;
alter table public.monthly_effect_reports enable row level security;
alter table public.experiment_templates enable row level security;
alter table public.accountability_connections enable row level security;
alter table public.accountability_summaries enable row level security;
alter table public.app_store_daily_metrics enable row level security;
alter table public.admin_review_items enable row level security;
alter table public.referral_risk_flags enable row level security;
alter table public.privacy_requests enable row level security;

create policy "feature_flags_founder_read" on public.feature_flags for select to authenticated using (public.is_super_admin());
create policy "feature_flags_founder_write" on public.feature_flags for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy "health_event_own_insert" on public.client_health_events for insert to authenticated with check (user_id = auth.uid());
create policy "health_event_founder_read" on public.client_health_events for select to authenticated using (public.is_super_admin());
create policy "release_rollup_founder" on public.release_health_rollups for select to authenticated using (public.is_super_admin());
create policy "quality_issue_founder" on public.data_quality_issues for select to authenticated using (public.is_super_admin());
create policy "recovery_plan_own" on public.recovery_plans for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "monthly_report_own" on public.monthly_effect_reports for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "experiment_template_read" on public.experiment_templates for select to authenticated using (active and (owner_user_id is null or owner_user_id = auth.uid()));
create policy "accountability_connection_own" on public.accountability_connections for select to authenticated using (owner_user_id = auth.uid());
create policy "accountability_summary_own" on public.accountability_summaries for select to authenticated using (owner_user_id = auth.uid());
create policy "app_store_metrics_founder" on public.app_store_daily_metrics for select to authenticated using (public.is_super_admin());
create policy "review_items_founder" on public.admin_review_items for select to authenticated using (public.is_super_admin());
create policy "risk_flags_founder" on public.referral_risk_flags for select to authenticated using (public.is_super_admin());
create policy "privacy_request_own_read" on public.privacy_requests for select to authenticated using (user_id = auth.uid() or public.is_super_admin());
create policy "privacy_request_own_insert" on public.privacy_requests for insert to authenticated with check (user_id = auth.uid());

create or replace function public.get_my_feature_flags()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare caller_role text;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    select case when public.is_super_admin() then 'super_admin' else coalesce(account_role, 'user') end
      into caller_role from public.user_profiles where user_id = auth.uid();
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'key', f.key,
            'enabled', f.enabled and (f.target_role is null or f.target_role = caller_role),
            'rollout_percentage', f.rollout_percentage,
            'minimum_version', f.minimum_version,
            'target_role', f.target_role,
            'founder_preview', f.founder_preview,
            'automatically_paused', f.automatically_paused,
            'updated_at', f.updated_at
        ) order by f.key) from public.feature_flags f
    ), '[]'::jsonb);
end; $$;
grant execute on function public.get_my_feature_flags() to authenticated;

create or replace function public.admin_feature_flags()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    return coalesce((select jsonb_agg(to_jsonb(f) - 'pause_reason' - 'updated_by' order by f.key) from public.feature_flags f), '[]'::jsonb);
end; $$;
grant execute on function public.admin_feature_flags() to authenticated;

create or replace function public.admin_update_feature_flag(
    input_key text,
    input_enabled boolean,
    input_rollout_percentage integer,
    input_minimum_version text default null,
    input_target_role text default null,
    input_founder_preview boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
declare before_row jsonb; saved public.feature_flags%rowtype;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_rollout_percentage not in (0, 5, 25, 50, 100) then raise exception 'invalid_rollout_stage'; end if;
    if input_target_role is not null and input_target_role not in ('user','admin','ambassador','super_admin') then raise exception 'invalid_target_role'; end if;
    select to_jsonb(f) into before_row from public.feature_flags f where key = input_key;
    insert into public.feature_flags(key,enabled,rollout_percentage,minimum_version,target_role,founder_preview,automatically_paused,pause_reason,updated_by,updated_at)
    values(input_key,input_enabled,input_rollout_percentage,nullif(trim(input_minimum_version),''),input_target_role,input_founder_preview,false,null,auth.uid(),now())
    on conflict(key) do update set
        enabled=excluded.enabled, rollout_percentage=excluded.rollout_percentage,
        minimum_version=excluded.minimum_version, target_role=excluded.target_role,
        founder_preview=excluded.founder_preview, automatically_paused=false,
        pause_reason=null, updated_by=auth.uid(), updated_at=now()
    returning * into saved;
    insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,before_value,after_value)
    values(auth.uid(),'feature_flag_updated','feature_flag',saved.key,before_row,to_jsonb(saved));
    return to_jsonb(saved) - 'pause_reason' - 'updated_by';
end; $$;
grant execute on function public.admin_update_feature_flag(text,boolean,integer,text,text,boolean) to authenticated;

create or replace function public.ingest_client_health_event(input_kind text, input_payload jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare sanitized jsonb; related text; attempts integer; failures integer;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if length(coalesce(input_payload,'{}'::jsonb)::text) > 16384 then raise exception 'diagnostic_payload_too_large'; end if;
    sanitized := coalesce(input_payload,'{}'::jsonb) - array[
        'app_name','app_names','application_token','application_tokens','intention','reflection',
        'reflection_note','session_note','urge_note','email','name','stack','stack_trace'
    ];
    related := nullif(sanitized->>'related_feature','');
    insert into public.client_health_events(
        user_id,kind,related_feature,app_version,ios_version,device_family,success,duration_ms,payload
    ) values (
        auth.uid(), left(input_kind,80), related,
        nullif(sanitized->>'app_version',''), nullif(sanitized->>'ios_version',''),
        nullif(sanitized->>'device_family',''), coalesce((sanitized->>'success')::boolean, input_kind not like '%failure%'),
        case when sanitized ? 'duration_ms' then greatest(0,least(600000,(sanitized->>'duration_ms')::integer)) else null end,
        sanitized
    );

    if related is not null then
        select count(*), count(*) filter(where not success) into attempts, failures
        from public.client_health_events where related_feature=related and occurred_at >= now()-interval '30 minutes';
        if attempts >= 20 and failures::numeric / attempts::numeric > 0.10 then
            update public.feature_flags set automatically_paused=true,
                pause_reason='Error rate exceeded 10% over 30 minutes with at least 20 attempts', updated_at=now()
            where key=related and not automatically_paused;
            if found then
                insert into public.admin_audit_log(action,target_type,target_id,reason,after_value)
                values('feature_rollout_automatically_paused','feature_flag',related,'automatic_reliability_threshold',
                    jsonb_build_object('attempts',attempts,'failures',failures,'window_minutes',30));
            end if;
        end if;
    end if;
end; $$;
grant execute on function public.ingest_client_health_event(text,jsonb) to authenticated;

create or replace function public.save_recovery_plan(input_plan jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    insert into public.recovery_plans(user_id,id,date,status,reason,outside_window_minutes,not_worthwhile_extension_count,created_at,resolved_at,raw_plan,updated_at)
    values(auth.uid(),input_plan->>'id',input_plan->>'date',input_plan->>'status',input_plan->>'reason',
      coalesce((input_plan->>'outsideWindowMinutes')::integer,0),coalesce((input_plan->>'notWorthwhileExtensionCount')::integer,0),
      coalesce((input_plan->>'createdAt')::timestamptz,now()),nullif(input_plan->>'resolvedAt','')::timestamptz,input_plan,now())
    on conflict(user_id,id) do update set status=excluded.status,reason=excluded.reason,
      outside_window_minutes=excluded.outside_window_minutes,not_worthwhile_extension_count=excluded.not_worthwhile_extension_count,
      resolved_at=excluded.resolved_at,raw_plan=excluded.raw_plan,updated_at=now();
end; $$;
grant execute on function public.save_recovery_plan(jsonb) to authenticated;

create or replace function public.save_monthly_effect_report(input_report jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if coalesce((input_report->>'validDays')::integer,0) < 7 or coalesce((input_report->>'sessionCount')::integer,0) < 3 then
        raise exception 'insufficient_valid_data';
    end if;
    insert into public.monthly_effect_reports(user_id,id,month_key,valid_days,session_count,report,generated_at,updated_at)
    values(auth.uid(),input_report->>'id',input_report->>'monthKey',(input_report->>'validDays')::integer,
      (input_report->>'sessionCount')::integer,input_report,coalesce((input_report->>'generatedAt')::timestamptz,now()),now())
    on conflict(user_id,id) do update set valid_days=excluded.valid_days,session_count=excluded.session_count,
      report=excluded.report,generated_at=excluded.generated_at,updated_at=now();
end; $$;
grant execute on function public.save_monthly_effect_report(jsonb) to authenticated;

create or replace function public.get_accountability_connections()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'partner_email_masked',regexp_replace(c.partner_email,'(^.).*(@.*$)','\\1***\\2'),
      'status',c.status,'automatic_sharing_enabled',c.automatic_sharing_enabled,
      'created_at',c.created_at,'revoked_at',c.revoked_at
    ) order by c.created_at desc) from public.accountability_connections c where c.owner_user_id=auth.uid()),'[]'::jsonb);
end; $$;
grant execute on function public.get_accountability_connections() to authenticated;

create or replace function public.set_accountability_sharing(input_connection_id text,input_enabled boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare saved public.accountability_connections%rowtype;
begin
    update public.accountability_connections set automatic_sharing_enabled=input_enabled,
      preview_confirmed_at=case when input_enabled then coalesce(preview_confirmed_at,now()) else preview_confirmed_at end,
      status=case when input_enabled and status='pending' then 'active' else status end
    where id=input_connection_id::uuid and owner_user_id=auth.uid() and status<>'revoked' returning * into saved;
    if saved.id is null then raise exception 'connection_not_found'; end if;
    return jsonb_build_object('id',saved.id,'partner_email_masked',regexp_replace(saved.partner_email,'(^.).*(@.*$)','\\1***\\2'),
      'status',saved.status,'automatic_sharing_enabled',saved.automatic_sharing_enabled,'created_at',saved.created_at,'revoked_at',saved.revoked_at);
end; $$;
grant execute on function public.set_accountability_sharing(text,boolean) to authenticated;

create or replace function public.revoke_accountability_connection(input_connection_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
    update public.accountability_connections set status='revoked',automatic_sharing_enabled=false,revoked_at=now()
      where id=input_connection_id::uuid and owner_user_id=auth.uid();
    update public.accountability_summaries set revoked_at=now()
      where connection_id=input_connection_id::uuid and owner_user_id=auth.uid() and revoked_at is null;
end; $$;
grant execute on function public.revoke_accountability_connection(text) to authenticated;

create or replace function public.create_privacy_request(input_request_type text)
returns void language plpgsql security definer set search_path = public as $$
declare created_id uuid;
begin
    if input_request_type not in ('export','delete','revoke_consent','correct_data') then raise exception 'invalid_request_type'; end if;
    insert into public.privacy_requests(user_id,request_type) values(auth.uid(),input_request_type) returning id into created_id;
    insert into public.admin_review_items(type,title,detail,source_table,source_id,payload)
      values('privacy_request','Privacy request',replace(input_request_type,'_',' '),'privacy_requests',created_id::text,
        jsonb_build_object('request_type',input_request_type,'user_id',auth.uid()));
end; $$;
grant execute on function public.create_privacy_request(text) to authenticated;

create or replace function public.run_data_quality_scan()
returns integer language plpgsql security definer set search_path = public as $$
declare found_count integer := 0; row_item record;
begin
    -- Session stored under the completion day instead of its start day.
    for row_item in
        select s.user_id,s.id,s.date,s.start_time,(s.start_time::timestamptz)::date::text correct_date
        from public.sessions s
        where s.start_time ~ '^\d{4}-\d{2}-\d{2}T' and s.date <> (s.start_time::timestamptz)::date::text
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,repair_payload,auto_repairable)
        values('wrong-day:'||row_item.user_id||':'||row_item.id,'wrong_day_session','warning',
          'A session is filed under '||row_item.date||' but started on '||row_item.correct_date||'.',row_item.user_id,'sessions',row_item.id,
          jsonb_build_object('correct_date',row_item.correct_date),true)
        on conflict(issue_key) do update set detected_at=now(),summary=excluded.summary
          where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    -- Durations that cannot represent a valid Mivo session.
    for row_item in
        select user_id,id,planned_duration,actual_duration from public.sessions
        where planned_duration <= 0 or actual_duration < 0 or actual_duration > 1440 or planned_duration > 1440
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,repair_payload,auto_repairable)
        values('duration:'||row_item.user_id||':'||row_item.id,'impossible_duration','critical',
          'A session contains an impossible planned or actual duration.',row_item.user_id,'sessions',row_item.id,
          jsonb_build_object('planned_duration',row_item.planned_duration,'actual_duration',row_item.actual_duration),false)
        on conflict(issue_key) do update set detected_at=now() where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    -- Exact duplicate records with different client-generated IDs are deterministic to repair.
    for row_item in
        select user_id,min(id) keep_id,max(id) duplicate_id,start_time,end_time
        from public.sessions group by user_id,start_time,end_time,intention,actual_duration
        having count(*) > 1
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,repair_payload,auto_repairable)
        values('duplicate:'||row_item.user_id||':'||row_item.duplicate_id,'duplicate_session','warning',
          'Two identical session records were synced.',row_item.user_id,'sessions',row_item.duplicate_id,
          jsonb_build_object('keep_id',row_item.keep_id,'duplicate_id',row_item.duplicate_id),true)
        on conflict(issue_key) do update set detected_at=now() where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    -- Multiple daily schedule records for one day can make enforcement disagree between devices.
    for row_item in
        select user_id,date,min(id) keep_id,max(id) duplicate_id
        from public.daily_scroll_schedules group by user_id,date having count(*) > 1
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,repair_payload,auto_repairable)
        values('schedule-duplicate:'||row_item.user_id||':'||row_item.date,'schedule_mismatch','critical',
          'More than one locked schedule exists for the same day.',row_item.user_id,'daily_scroll_schedules',row_item.duplicate_id,
          jsonb_build_object('keep_id',row_item.keep_id,'duplicate_id',row_item.duplicate_id),false)
        on conflict(issue_key) do update set detected_at=now() where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    -- Observation start dates in the future produce incorrect day numbers.
    for row_item in
        select user_id,observation_started_at from public.onboarding_profiles
        where observation_started_at > now() + interval '5 minutes'
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,repair_payload,auto_repairable)
        values('observation-future:'||row_item.user_id,'observation_day_error','critical',
          'Observation start is in the future, so the displayed day can be wrong.',row_item.user_id,'onboarding_profiles',row_item.user_id::text,
          jsonb_build_object('observation_started_at',row_item.observation_started_at),false)
        on conflict(issue_key) do update set detected_at=now() where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    -- A recent account with no state sync after onboarding is a likely sync backlog.
    for row_item in
        select p.user_id from public.user_profiles p join public.app_settings a using(user_id)
        left join public.user_state u using(user_id)
        where a.onboarding_complete and p.created_at >= now()-interval '30 days' and u.user_id is null
    loop
        insert into public.data_quality_issues(issue_key,issue_type,severity,summary,affected_user_id,target_table,target_id,auto_repairable)
        values('missing-sync:'||row_item.user_id,'missing_sync_data','warning',
          'Onboarding completed but no synchronized user state exists.',row_item.user_id,'user_state',row_item.user_id::text,false)
        on conflict(issue_key) do update set detected_at=now() where public.data_quality_issues.status='open';
        found_count := found_count + 1;
    end loop;

    return found_count;
end; $$;
revoke all on function public.run_data_quality_scan() from public;
grant execute on function public.run_data_quality_scan() to service_role;

create or replace function public.admin_repair_data_quality_issue(input_issue_id text)
returns void language plpgsql security definer set search_path = public as $$
declare issue public.data_quality_issues%rowtype; before_row jsonb; after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    select * into issue from public.data_quality_issues where id=input_issue_id::uuid for update;
    if issue.id is null or issue.status <> 'open' then raise exception 'issue_not_open'; end if;
    if not issue.auto_repairable then raise exception 'founder_review_required'; end if;

    if issue.issue_type='wrong_day_session' then
        select to_jsonb(s) into before_row from public.sessions s where s.user_id=issue.affected_user_id and s.id=issue.target_id;
        update public.sessions set date=issue.repair_payload->>'correct_date',updated_at=now()
          where user_id=issue.affected_user_id and id=issue.target_id;
        select to_jsonb(s) into after_row from public.sessions s where s.user_id=issue.affected_user_id and s.id=issue.target_id;
    elsif issue.issue_type='duplicate_session' then
        select to_jsonb(s) into before_row from public.sessions s where s.user_id=issue.affected_user_id and s.id=issue.target_id;
        delete from public.sessions where user_id=issue.affected_user_id and id=issue.repair_payload->>'duplicate_id';
        after_row := jsonb_build_object('deleted_duplicate_id',issue.repair_payload->>'duplicate_id','kept_id',issue.repair_payload->>'keep_id');
    else
        raise exception 'unsupported_deterministic_repair';
    end if;

    update public.data_quality_issues set status='repaired',resolved_at=now(),resolved_by=auth.uid() where id=issue.id;
    insert into public.admin_audit_log(actor_user_id,action,target_user_id,target_type,target_id,before_value,after_value)
      values(auth.uid(),'data_quality_issue_repaired',issue.affected_user_id,issue.target_table,issue.target_id,before_row,after_row);
end; $$;
grant execute on function public.admin_repair_data_quality_issue(text) to authenticated;

create or replace function public.admin_resolve_review_item(input_item_id text,input_action text)
returns void language plpgsql security definer set search_path = public as $$
declare item public.admin_review_items%rowtype; before_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_action not in ('approve','reject','archive') then raise exception 'invalid_review_action'; end if;
    select * into item from public.admin_review_items where id=input_item_id::uuid for update;
    if item.id is null or item.status<>'pending' then raise exception 'review_not_pending'; end if;
    before_row := to_jsonb(item);

    if item.source_table='privacy_requests' then
        update public.privacy_requests set status=case when input_action='approve' then 'processing' else 'rejected' end,
          handled_by=auth.uid() where id=item.source_id::uuid;
    elsif item.source_table='referral_risk_flags' then
        update public.referral_risk_flags set status=case when input_action='approve' then 'cleared' else 'confirmed' end,
          reviewed_at=now(),reviewed_by=auth.uid() where id=item.source_id::uuid;
    elsif item.source_table='announcements' and input_action='approve' then
        update public.announcements set status='published',published_at=coalesce(published_at,now()),updated_at=now()
          where id=item.source_id::uuid and status='draft';
    end if;

    update public.admin_review_items set status=case input_action when 'approve' then 'approved' when 'reject' then 'rejected' else 'archived' end,
      resolved_at=now(),resolved_by=auth.uid() where id=item.id;
    insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,before_value,after_value)
      values(auth.uid(),'review_item_'||input_action,item.type,item.id::text,before_row,
        jsonb_build_object('status',case input_action when 'approve' then 'approved' when 'reject' then 'rejected' else 'archived' end));
end; $$;
grant execute on function public.admin_resolve_review_item(text,text) to authenticated;

create or replace function public.admin_expansion_dashboard()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare result jsonb;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    with reliability_types(kind,title) as (values
      ('crash','Crashes'),('hang','Hangs'),('login_failure','Login failures'),('api_failure','API errors'),
      ('sync_failure','Sync backlog'),('notification_failure','Notification failures'),
      ('screen_time_permission_failure','Screen Time permission failures'),('shield_failure','Shield failures'),
      ('stuck_session','Stuck sessions')
    ), reliability as (
      select r.kind,r.title,count(h.id)::numeric value,
        case when count(h.id)>=5 then 'critical' when count(h.id)>0 then 'warning' else 'info' end severity,
        coalesce(max(h.occurred_at),now()) updated_at
      from reliability_types r left join public.client_health_events h
        on h.kind=r.kind and h.occurred_at>=now()-interval '24 hours' group by r.kind,r.title
    ), versions as (
      select coalesce(nullif(e.metadata->>'app_version',''),'Unknown') version,count(distinct e.user_id)::integer active_users
      from public.analytics_events e where e.event_name='app_open' and e.occurred_at>=now()-interval '30 days' group by 1
    )
    select jsonb_build_object(
      'reliability',coalesce((select jsonb_agg(jsonb_build_object(
        'key',kind,'title',title,'value',value,'unit','events','severity',severity,'updated_at',updated_at
      ) order by case severity when 'critical' then 0 when 'warning' then 1 else 2 end,title) from reliability),'[]'::jsonb),
      'releases',coalesce((select jsonb_agg(jsonb_build_object(
        'version',v.version,'active_users',v.active_users,
        'crash_free_rate',case when v.active_users>0 then round(100.0*greatest(0,v.active_users-(select count(distinct h.user_id) from public.client_health_events h where h.app_version=v.version and h.kind='crash' and h.occurred_at>=now()-interval '30 days'))/v.active_users,1) else null end,
        'login_success_rate',(select case when count(*)>0 then round(100.0*count(*) filter(where h.success)/count(*),1) else null end from public.client_health_events h where h.app_version=v.version and h.kind in('login','login_failure') and h.occurred_at>=now()-interval '30 days'),
        'sync_success_rate',(select case when count(*)>0 then round(100.0*count(*) filter(where h.success)/count(*),1) else null end from public.client_health_events h where h.app_version=v.version and h.kind in('sync','sync_failure') and h.occurred_at>=now()-interval '30 days'),
        'session_completion_rate',(select case when count(*) filter(where e.event_name='session_started')>0 then round(100.0*count(*) filter(where e.event_name in('session_completed','session_reflected'))/count(*) filter(where e.event_name='session_started'),1) else null end from public.analytics_events e where e.metadata->>'app_version'=v.version and e.occurred_at>=now()-interval '30 days'),
        'retention_rate',null,'source','Mivo devices'
      ) order by v.version desc) from versions v),'[]'::jsonb),
      'data_quality_issues',coalesce((select jsonb_agg(jsonb_build_object(
        'id',q.id,'issue_type',q.issue_type,'severity',q.severity,'summary',q.summary,
        'affected_user_id',q.affected_user_id,'status',q.status,'auto_repairable',q.auto_repairable,'detected_at',q.detected_at
      ) order by case q.severity when 'critical' then 0 when 'warning' then 1 else 2 end,q.detected_at desc)
        from public.data_quality_issues q where q.status='open'),'[]'::jsonb),
      'approvals',coalesce((select jsonb_agg(jsonb_build_object(
        'id',a.id,'type',a.type,'title',a.title,'detail',a.detail,'status',a.status,'created_at',a.created_at
      ) order by a.created_at desc) from public.admin_review_items a where a.status='pending'),'[]'::jsonb),
      'security_events',coalesce((select jsonb_agg(jsonb_build_object(
        'id',l.id::text,'action',l.action,'actor_label',coalesce(p.name,'System'),
        'target_label',coalesce(l.target_type||case when l.target_id is null then '' else ' · '||l.target_id end,null),
        'occurred_at',l.created_at,
        'severity',case when l.action like '%delete%' or l.action like '%suspicious%' then 'critical'
                        when l.action like '%role%' or l.action like '%export%' then 'warning' else 'info' end
      ) order by l.created_at desc) from (select * from public.admin_audit_log order by created_at desc limit 100) l
        left join public.user_profiles p on p.user_id=l.actor_user_id),'[]'::jsonb),
      'app_store_data_available',exists(select 1 from public.app_store_daily_metrics where reporting_status='available'),
      'generated_at',now()
    ) into result;
    return result;
end; $$;
grant execute on function public.admin_expansion_dashboard() to authenticated;

create or replace function public.admin_sanitized_user_timeline(input_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    return coalesce((
      select jsonb_agg(event order by event_time desc) from (
        select jsonb_build_object('type','account_created','at',p.created_at,'status','complete') event,p.created_at event_time
          from public.user_profiles p where p.user_id=input_user_id
        union all select jsonb_build_object('type','onboarding','at',s.updated_at,'status',case when s.onboarding_complete then 'complete' else 'pending' end),s.updated_at
          from public.app_settings s where s.user_id=input_user_id
        union all select jsonb_build_object('type','session','at',se.updated_at,'status',case when se.reflection is null then 'saved' else 'reflected' end,'duration_minutes',se.actual_duration),se.updated_at
          from public.sessions se where se.user_id=input_user_id
        union all select jsonb_build_object('type','experiment','at',w.updated_at,'status',w.status,'experiment_type',w.type),w.updated_at
          from public.weekly_experiments w where w.user_id=input_user_id
        union all select jsonb_build_object('type','support','at',f.updated_at,'status',f.status,'support_type',f.type),f.updated_at
          from public.feedback_items f where f.user_id=input_user_id
        union all select jsonb_build_object('type','system','at',h.occurred_at,'status',case when h.success then 'ok' else 'error' end,'event',h.kind),h.occurred_at
          from public.client_health_events h where h.user_id=input_user_id
      ) timeline
    ),'[]'::jsonb);
end; $$;
grant execute on function public.admin_sanitized_user_timeline(uuid) to authenticated;

create or replace function public.import_app_store_daily_metrics(input_rows jsonb,input_import_id text)
returns integer language plpgsql security definer set search_path = public as $$
declare row_data jsonb; imported integer := 0;
begin
    if auth.role()<>'service_role' and not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    for row_data in select value from jsonb_array_elements(coalesce(input_rows,'[]'::jsonb)) loop
      insert into public.app_store_daily_metrics(metric_date,app_version,downloads,installations,deletions,sessions,crashes,conversion_rate,retention_rate,reporting_status,import_id)
      values((row_data->>'metric_date')::date,nullif(row_data->>'app_version',''),
        nullif(row_data->>'downloads','')::integer,nullif(row_data->>'installations','')::integer,
        nullif(row_data->>'deletions','')::integer,nullif(row_data->>'sessions','')::integer,
        nullif(row_data->>'crashes','')::integer,nullif(row_data->>'conversion_rate','')::numeric,
        nullif(row_data->>'retention_rate','')::numeric,coalesce(row_data->>'reporting_status','unavailable'),input_import_id)
      on conflict(metric_date,app_version,import_id) do update set downloads=excluded.downloads,installations=excluded.installations,
        deletions=excluded.deletions,sessions=excluded.sessions,crashes=excluded.crashes,conversion_rate=excluded.conversion_rate,
        retention_rate=excluded.retention_rate,reporting_status=excluded.reporting_status,imported_at=now();
      imported := imported + 1;
    end loop;
    if auth.uid() is not null then
      insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,after_value)
      values(auth.uid(),'app_store_analytics_imported','app_store_import',input_import_id,jsonb_build_object('rows',imported));
    end if;
    return imported;
end; $$;
revoke all on function public.import_app_store_daily_metrics(jsonb,text) from public;
grant execute on function public.import_app_store_daily_metrics(jsonb,text) to authenticated,service_role;

create or replace function public.scan_referral_risk_signals()
returns integer language plpgsql security definer set search_path = public as $$
declare flagged integer := 0; row_item record; new_flag uuid;
begin
    for row_item in
      select a.id,a.referrer_user_id,count(*) count_in_hour
      from public.referral_attributions a join public.referral_attributions peer
        on peer.referrer_user_id=a.referrer_user_id and peer.attached_at between a.attached_at-interval '1 hour' and a.attached_at+interval '1 hour'
      where a.status='pending' group by a.id,a.referrer_user_id having count(*)>=5
    loop
      insert into public.referral_risk_flags(attribution_id,signal_type,risk_score,detail)
      select row_item.id,'signup_burst',least(100,row_item.count_in_hour*10),'Multiple signups arrived close together.'
      where not exists(select 1 from public.referral_risk_flags where attribution_id=row_item.id and signal_type='signup_burst' and status='review_hold')
      returning id into new_flag;
      if new_flag is not null then
        insert into public.admin_review_items(type,title,detail,source_table,source_id,payload)
          values('referral_review','Referral needs review','Signup burst detected. No automatic disqualification was made.',
            'referral_risk_flags',new_flag::text,jsonb_build_object('attribution_id',row_item.id));
        flagged := flagged+1;
      end if;
      new_flag := null;
    end loop;
    return flagged;
end; $$;
revoke all on function public.scan_referral_risk_signals() from public;
grant execute on function public.scan_referral_risk_signals() to service_role;

create or replace function public.cleanup_product_operational_data()
returns void language plpgsql security definer set search_path = public as $$
begin
    delete from public.client_health_events where occurred_at < now()-interval '90 days';
    delete from public.release_health_rollups where rollup_date < current_date-interval '13 months';
    delete from public.app_store_daily_metrics where metric_date < current_date-interval '13 months';
    delete from public.accountability_summaries where expires_at < now()-interval '30 days';
end; $$;
revoke all on function public.cleanup_product_operational_data() from public;
grant execute on function public.cleanup_product_operational_data() to service_role;

create or replace function public.queue_native_admin_review()
returns trigger language plpgsql security definer set search_path = public as $$
declare review_type text; review_title text; review_detail text; source_value text;
begin
    if tg_table_name='announcements' and new.status='draft' then
      review_type:='announcement'; review_title:='Announcement draft'; review_detail:=new.title; source_value:=new.id::text;
    elsif tg_table_name='referral_campaigns' and new.status='draft' then
      review_type:='campaign'; review_title:='Campaign draft'; review_detail:=new.name; source_value:=new.id::text;
    elsif tg_table_name='parental_consent_requests' and new.status in('pending','needs_information') then
      review_type:='parental_consent'; review_title:='Parental consent review'; review_detail:='A consent request needs founder review.'; source_value:=new.id::text;
    else
      return new;
    end if;
    insert into public.admin_review_items(type,title,detail,source_table,source_id,payload)
      values(review_type,review_title,review_detail,tg_table_name,source_value,'{}'::jsonb)
    on conflict(source_table,source_id,type) where status='pending' do nothing;
    return new;
end; $$;

drop trigger if exists queue_announcement_native_review on public.announcements;
create trigger queue_announcement_native_review after insert or update of status on public.announcements
for each row execute function public.queue_native_admin_review();
drop trigger if exists queue_campaign_native_review on public.referral_campaigns;
create trigger queue_campaign_native_review after insert or update of status on public.referral_campaigns
for each row execute function public.queue_native_admin_review();
drop trigger if exists queue_consent_native_review on public.parental_consent_requests;
create trigger queue_consent_native_review after insert or update of status on public.parental_consent_requests
for each row execute function public.queue_native_admin_review();

-- Supabase Cron installs pg_cron in production projects. If available, register the
-- nightly scans; otherwise the same functions remain available to scheduled Edge Functions.
do $$
begin
    if exists(select 1 from pg_extension where extname='pg_cron') then
      if not exists(select 1 from cron.job where jobname='mivo-nightly-data-quality') then
        perform cron.schedule('mivo-nightly-data-quality','17 4 * * *','select public.run_data_quality_scan(); select public.scan_referral_risk_signals();');
      end if;
      if not exists(select 1 from cron.job where jobname='mivo-operational-retention') then
        perform cron.schedule('mivo-operational-retention','41 4 * * *','select public.cleanup_product_operational_data();');
      end if;
    end if;
exception when undefined_table or invalid_schema_name or insufficient_privilege then
    null;
end $$;
