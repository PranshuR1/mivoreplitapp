-- Separate founder, announcement-admin, ambassador, and user capabilities.

create or replace function public.normalize_ambassador_name(input_name text)
returns text
language sql
immutable
parallel safe
as $$
    select lower(regexp_replace(trim(coalesce(input_name, '')), '\s+', ' ', 'g'));
$$;

create table if not exists public.ambassador_name_assignments (
    id uuid primary key default gen_random_uuid(),
    ambassador_user_id uuid not null references auth.users(id) on delete cascade,
    entered_name text not null,
    normalized_name text not null unique,
    active boolean not null default true,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (char_length(normalized_name) between 1 and 80)
);
create index if not exists ambassador_name_assignments_user_idx
    on public.ambassador_name_assignments (ambassador_user_id, active);
alter table public.ambassador_name_assignments enable row level security;

drop policy if exists "ambassador_assignment_super_admin_read" on public.ambassador_name_assignments;
create policy "ambassador_assignment_super_admin_read" on public.ambassador_name_assignments
    for select to authenticated using (public.is_super_admin());

create table if not exists public.admin_push_devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    installation_id text not null,
    device_token text not null unique,
    environment text not null check (environment in ('sandbox', 'production')),
    active boolean not null default true,
    last_registered_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    unique (user_id, installation_id, environment)
);
alter table public.admin_push_devices enable row level security;

create table if not exists public.admin_account_alerts (
    user_id uuid primary key references auth.users(id) on delete cascade,
    push_status text not null default 'pending',
    email_status text not null default 'pending',
    push_error text,
    email_error text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);
alter table public.admin_account_alerts enable row level security;

create table if not exists public.new_account_alert_jobs (
    user_id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    processed_at timestamptz
);
alter table public.new_account_alert_jobs enable row level security;

create or replace function public.enqueue_new_account_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.new_account_alert_jobs(user_id)
    values (new.user_id)
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists enqueue_new_account_alert_trigger on public.user_profiles;
create trigger enqueue_new_account_alert_trigger
    after insert on public.user_profiles
    for each row execute function public.enqueue_new_account_alert();

-- Existing non-founder app_admin rows become restricted announcement admins.
update public.user_profiles p
set account_role = 'admin', updated_at = now()
where exists (
    select 1 from public.app_admins a
    where a.user_id = p.user_id and a.role = 'admin'
);
delete from public.app_admins where role = 'admin';

create or replace function public.is_app_admin(check_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.is_super_admin(check_user_id);
$$;
grant execute on function public.is_app_admin(uuid) to authenticated;

create or replace function public.can_manage_announcements(check_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select public.is_super_admin(check_user_id)
        or exists (
            select 1 from public.user_profiles p
            where p.user_id = check_user_id and p.account_role = 'admin'
        );
$$;
grant execute on function public.can_manage_announcements(uuid) to authenticated;

create or replace function public.current_account_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    account_role_value text;
    founder boolean;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    founder := public.is_super_admin();
    select account_role into account_role_value from public.user_profiles where user_id = auth.uid();
    if founder then account_role_value := 'super_admin'; end if;
    account_role_value := coalesce(account_role_value, 'user');
    return jsonb_build_object(
        'role', account_role_value,
        'is_super_admin', founder,
        'can_manage_announcements', founder or account_role_value = 'admin',
        'can_view_ambassador_dashboard', account_role_value = 'ambassador'
    );
end;
$$;
grant execute on function public.current_account_access() to authenticated;

create or replace function public.admin_set_user_role(input_user_id uuid, input_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_role text;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_role not in ('user', 'admin', 'ambassador') then raise exception 'invalid_role'; end if;
    if public.is_super_admin(input_user_id) then raise exception 'cannot_change_founder_role'; end if;
    select account_role into before_role from public.user_profiles where user_id = input_user_id;
    if not found then raise exception 'user_not_found'; end if;

    update public.user_profiles
    set account_role = input_role, updated_at = now()
    where user_id = input_user_id;
    delete from public.app_admins where user_id = input_user_id and role = 'admin';

    insert into public.admin_audit_log(
        actor_user_id, action, target_user_id, target_type, target_id, before_value, after_value
    ) values (
        auth.uid(), 'user_role_changed', input_user_id, 'user', input_user_id::text,
        jsonb_build_object('role', before_role), jsonb_build_object('role', input_role)
    );
end;
$$;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

create or replace function public.admin_ambassador_attribution_options(input_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    return jsonb_build_object(
        'assigned', coalesce((
            select jsonb_agg(jsonb_build_object(
                'entered_name', a.entered_name,
                'normalized_name', a.normalized_name,
                'count', (
                    select count(*) from public.onboarding_profiles o
                    where o.referral_source = 'ambassador'
                      and public.normalize_ambassador_name(o.referral_ambassador_name) = a.normalized_name
                )
            ) order by a.entered_name)
            from public.ambassador_name_assignments a
            where a.ambassador_user_id = input_user_id and a.active
        ), '[]'::jsonb),
        'unassigned', coalesce((
            select jsonb_agg(jsonb_build_object(
                'entered_name', names.entered_name,
                'normalized_name', names.normalized_name,
                'count', names.usage_count
            ) order by names.usage_count desc, names.entered_name)
            from (
                select min(trim(o.referral_ambassador_name)) entered_name,
                       public.normalize_ambassador_name(o.referral_ambassador_name) normalized_name,
                       count(*) usage_count
                from public.onboarding_profiles o
                where o.referral_source = 'ambassador'
                  and public.normalize_ambassador_name(o.referral_ambassador_name) <> ''
                  and not exists (
                      select 1 from public.ambassador_name_assignments a
                      where a.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
                        and a.active
                  )
                group by public.normalize_ambassador_name(o.referral_ambassador_name)
            ) names
        ), '[]'::jsonb)
    );
end;
$$;
grant execute on function public.admin_ambassador_attribution_options(uuid) to authenticated;

create or replace function public.admin_set_ambassador_names(
    input_user_id uuid,
    input_normalized_names text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    selected_name text;
    representative_name text;
    conflicting_user uuid;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if not exists (
        select 1 from public.user_profiles
        where user_id = input_user_id and account_role = 'ambassador'
    ) then raise exception 'ambassador_role_required'; end if;

    update public.ambassador_name_assignments
    set active = false, updated_at = now()
    where ambassador_user_id = input_user_id
      and not (normalized_name = any(coalesce(input_normalized_names, array[]::text[])));

    foreach selected_name in array coalesce(input_normalized_names, array[]::text[])
    loop
        selected_name := public.normalize_ambassador_name(selected_name);
        if selected_name = '' then continue; end if;

        select ambassador_user_id into conflicting_user
        from public.ambassador_name_assignments
        where normalized_name = selected_name and active and ambassador_user_id <> input_user_id;
        if conflicting_user is not null then raise exception 'ambassador_name_already_assigned'; end if;

        select min(trim(referral_ambassador_name)) into representative_name
        from public.onboarding_profiles
        where referral_source = 'ambassador'
          and public.normalize_ambassador_name(referral_ambassador_name) = selected_name;
        representative_name := coalesce(representative_name, selected_name);

        insert into public.ambassador_name_assignments(
            ambassador_user_id, entered_name, normalized_name, active, created_by
        ) values (input_user_id, representative_name, selected_name, true, auth.uid())
        on conflict (normalized_name) do update
        set ambassador_user_id = excluded.ambassador_user_id,
            entered_name = excluded.entered_name,
            active = true,
            updated_at = now();
    end loop;

    insert into public.admin_audit_log(actor_user_id, action, target_user_id, target_type, target_id, after_value)
    values (
        auth.uid(), 'ambassador_names_assigned', input_user_id, 'ambassador', input_user_id::text,
        jsonb_build_object('normalized_names', coalesce(input_normalized_names, array[]::text[]))
    );
end;
$$;
grant execute on function public.admin_set_ambassador_names(uuid, text[]) to authenticated;

create or replace function public.ambassador_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    account_role_value text;
begin
    select account_role into account_role_value from public.user_profiles where user_id = auth.uid();
    if account_role_value <> 'ambassador' then raise exception 'ambassador_required'; end if;

    return jsonb_build_object(
        'total_count', (
            select count(*) from public.onboarding_profiles o
            join public.ambassador_name_assignments a
              on a.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
             and a.ambassador_user_id = auth.uid() and a.active
            where o.referral_source = 'ambassador'
        ),
        'completed_count', (
            select count(*) from public.onboarding_profiles o
            join public.ambassador_name_assignments a
              on a.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
             and a.ambassador_user_id = auth.uid() and a.active
            join public.app_settings s on s.user_id = o.user_id and s.onboarding_complete
            where o.referral_source = 'ambassador'
        ),
        'pending_count', (
            select count(*) from public.onboarding_profiles o
            join public.ambassador_name_assignments a
              on a.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
             and a.ambassador_user_id = auth.uid() and a.active
            left join public.app_settings s on s.user_id = o.user_id
            where o.referral_source = 'ambassador' and not coalesce(s.onboarding_complete, false)
        ),
        'people', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', p.user_id,
                'first_name', split_part(trim(p.name), ' ', 1),
                'joined_at', p.created_at,
                'onboarding_complete', coalesce(s.onboarding_complete, false),
                'referral_status', coalesce(r.status, 'joined')
            ) order by p.created_at desc)
            from public.onboarding_profiles o
            join public.ambassador_name_assignments a
              on a.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
             and a.ambassador_user_id = auth.uid() and a.active
            join public.user_profiles p on p.user_id = o.user_id
            left join public.app_settings s on s.user_id = o.user_id
            left join public.referral_attributions r on r.referred_user_id = o.user_id
            where o.referral_source = 'ambassador'
        ), '[]'::jsonb)
    );
end;
$$;
grant execute on function public.ambassador_dashboard() to authenticated;

create or replace function public.register_admin_push_device(
    input_installation_id text,
    input_device_token text,
    input_environment text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_environment not in ('sandbox', 'production') then raise exception 'invalid_push_environment'; end if;
    insert into public.admin_push_devices(user_id, installation_id, device_token, environment, active, last_registered_at)
    values (auth.uid(), input_installation_id, input_device_token, input_environment, true, now())
    on conflict (user_id, installation_id, environment) do update
    set device_token = excluded.device_token, active = true, last_registered_at = now();
end;
$$;
grant execute on function public.register_admin_push_device(text, text, text) to authenticated;

create or replace function public.unregister_admin_push_device(input_installation_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.admin_push_devices
    set active = false, last_registered_at = now()
    where user_id = auth.uid() and installation_id = input_installation_id;
end;
$$;
grant execute on function public.unregister_admin_push_device(text) to authenticated;

-- Announcement admins can create and edit only their own drafts. Founder publication stays separate.
drop policy if exists "announcement_admin_manage" on public.announcements;
create policy "announcement_admin_manage" on public.announcements
    for all to authenticated
    using (public.is_super_admin())
    with check (public.is_super_admin());

create or replace function public.admin_announcement_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.can_manage_announcements() then raise exception 'announcement_admin_required'; end if;
    if public.is_super_admin() then
        return coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.announcements a), '[]'::jsonb);
    end if;
    return coalesce((
        select jsonb_agg(to_jsonb(a) order by a.created_at desc)
        from public.announcements a
        where a.created_by = auth.uid() and a.status = 'draft'
    ), '[]'::jsonb);
end;
$$;
grant execute on function public.admin_announcement_dashboard() to authenticated;

create or replace function public.admin_create_announcement(
    input_title text,
    input_body text,
    input_expires_at timestamptz default null,
    input_publish_now boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    created public.announcements%rowtype;
    publish_allowed boolean;
begin
    if not public.can_manage_announcements() then raise exception 'announcement_admin_required'; end if;
    publish_allowed := public.is_super_admin() and input_publish_now;
    insert into public.announcements(title, body, status, published_at, expires_at, created_by)
    values (
        trim(input_title), trim(input_body),
        case when publish_allowed then 'published' else 'draft' end,
        case when publish_allowed then now() else null end,
        input_expires_at, auth.uid()
    ) returning * into created;
    insert into public.admin_audit_log(actor_user_id, action, target_type, target_id, after_value)
    values (
        auth.uid(), case when publish_allowed then 'announcement_published' else 'announcement_created' end,
        'announcement', created.id::text, to_jsonb(created)
    );
    return to_jsonb(created);
end;
$$;
grant execute on function public.admin_create_announcement(text, text, timestamptz, boolean) to authenticated;

create or replace function public.admin_update_announcement_draft(
    input_announcement_id uuid,
    input_title text,
    input_body text,
    input_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    updated public.announcements%rowtype;
begin
    if not public.can_manage_announcements() then raise exception 'announcement_admin_required'; end if;
    update public.announcements
    set title = trim(input_title), body = trim(input_body), expires_at = input_expires_at, updated_at = now()
    where id = input_announcement_id and status = 'draft'
      and (public.is_super_admin() or created_by = auth.uid())
    returning * into updated;
    if updated.id is null then raise exception 'editable_draft_not_found'; end if;
    insert into public.admin_audit_log(actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), 'announcement_draft_updated', 'announcement', updated.id::text, to_jsonb(updated));
    return to_jsonb(updated);
end;
$$;
grant execute on function public.admin_update_announcement_draft(uuid, text, text, timestamptz) to authenticated;

create or replace function public.admin_set_announcement_status(input_announcement_id uuid, input_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_status not in ('published', 'archived') then raise exception 'invalid_status'; end if;
    select to_jsonb(a) into before_row from public.announcements a where id = input_announcement_id;
    update public.announcements
    set status = input_status,
        published_at = case when input_status = 'published' then coalesce(published_at, now()) else published_at end,
        updated_at = now()
    where id = input_announcement_id;
    select to_jsonb(a) into after_row from public.announcements a where id = input_announcement_id;
    insert into public.admin_audit_log(actor_user_id, action, target_type, target_id, before_value, after_value)
    values (auth.uid(), 'announcement_' || input_status, 'announcement', input_announcement_id::text, before_row, after_row);
end;
$$;
grant execute on function public.admin_set_announcement_status(uuid, text) to authenticated;

-- Repair the nested aggregate in the product dashboard and keep it founder-only.
create or replace function public.admin_product_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
 if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
 with activity as (
   select user_id, updated_at::date activity_day from public.sessions
   union select user_id, updated_at::date from public.truth_checks
   union select user_id, occurred_at::date from public.analytics_events where event_name = 'app_open'
 ), metrics as (
   select
    (select count(*) from public.user_profiles) total_users,
    (select count(distinct user_id) from activity where activity_day = current_date) dau,
    (select count(distinct user_id) from activity where activity_day >= current_date - 29) mau,
    (select count(*) from public.user_profiles where created_at::date = current_date) new_today,
    (select count(*) from public.user_profiles where created_at >= date_trunc('week', now())) new_week,
    (select count(*) from public.user_profiles where created_at >= date_trunc('month', now())) new_month,
    (select round(count(*)::numeric / nullif((select count(*) from public.user_profiles), 0), 2) from public.sessions) avg_sessions,
    (select round(count(*)::numeric / nullif((select count(*) from public.user_profiles), 0), 2) from public.truth_checks) avg_truth,
    (select round(100.0 * count(*) filter(where onboarding_complete) / nullif(count(*), 0), 1) from public.app_settings) onboarding_pct,
    (select round(100.0 * count(*) filter(where reflection is not null) / nullif(count(*), 0), 1) from public.sessions) reflection_pct,
    (select round(avg(abs(actual - guess)), 1) from public.truth_checks) avg_truth_gap
 ), retention as (
   select
    coalesce(round(100.0 * count(*) filter(where exists(select 1 from activity a where a.user_id = p.user_id and a.activity_day = p.created_at::date + 1)) / nullif(count(*) filter(where p.created_at::date <= current_date - 1), 0), 1), 0) d1,
    coalesce(round(100.0 * count(*) filter(where exists(select 1 from activity a where a.user_id = p.user_id and a.activity_day = p.created_at::date + 7)) / nullif(count(*) filter(where p.created_at::date <= current_date - 7), 0), 1), 0) d7,
    coalesce(round(100.0 * count(*) filter(where exists(select 1 from activity a where a.user_id = p.user_id and a.activity_day = p.created_at::date + 30)) / nullif(count(*) filter(where p.created_at::date <= current_date - 30), 0), 1), 0) d30
   from public.user_profiles p
 ), source_metrics as (
   select coalesce(o.referral_source, 'Unknown') source,
          count(*) signups,
          count(*) filter(where coalesce(s.onboarding_complete, false)) onboarded
   from public.onboarding_profiles o
   left join public.app_settings s on s.user_id = o.user_id
   group by coalesce(o.referral_source, 'Unknown')
 )
 select jsonb_build_object(
  'overview', (select to_jsonb(metrics) from metrics),
  'retention', (select to_jsonb(retention) from retention),
  'timeseries', (select coalesce(jsonb_agg(jsonb_build_object(
      'date', d.metric_date,
      'downloads', (select count(*) from public.analytics_events e where e.event_name = 'download' and e.occurred_at::date = d.metric_date),
      'active_users', (select count(distinct a.user_id) from activity a where a.activity_day = d.metric_date)
  ) order by d.metric_date), '[]'::jsonb) from (select generate_series(current_date - 29, current_date, interval '1 day')::date metric_date) d),
  'versions', (select coalesce(jsonb_agg(jsonb_build_object('version', version, 'users', users) order by users desc), '[]'::jsonb) from (
      select metadata->>'app_version' version, count(distinct user_id) users
      from public.analytics_events where event_name = 'app_open' and metadata ? 'app_version' group by 1
  ) v),
  'funnel', jsonb_build_array(
    jsonb_build_object('stage', 'App Store views', 'count', (select count(*) from public.analytics_events where event_name = 'app_store_view')),
    jsonb_build_object('stage', 'Downloads', 'count', (select count(*) from public.analytics_events where event_name = 'download')),
    jsonb_build_object('stage', 'Accounts', 'count', (select count(*) from public.user_profiles)),
    jsonb_build_object('stage', 'Onboarding', 'count', (select count(*) from public.app_settings where onboarding_complete)),
    jsonb_build_object('stage', 'Screen Time access', 'count', (select count(distinct user_id) from public.analytics_events where event_name = 'screen_time_permission')),
    jsonb_build_object('stage', 'First truth check', 'count', (select count(distinct user_id) from public.truth_checks)),
    jsonb_build_object('stage', 'Day 7 active', 'count', (select count(*) from public.user_profiles p where exists(select 1 from activity a where a.user_id = p.user_id and a.activity_day = p.created_at::date + 7)))
  ),
  'sources', (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'signups', signups, 'onboarded', onboarded) order by signups desc), '[]'::jsonb) from source_metrics),
  'triggers', (select coalesce(jsonb_agg(jsonb_build_object('trigger', urge_reason, 'count', total) order by total desc), '[]'::jsonb) from (
      select coalesce(urge_reason, 'Not recorded') urge_reason, count(*) total from public.sessions group by 1
  ) t)
 ) into result;
 return result;
end;
$$;
grant execute on function public.admin_product_dashboard() to authenticated;
