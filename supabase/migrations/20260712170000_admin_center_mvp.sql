alter table public.user_profiles add column if not exists account_role text not null default 'user'
    check (account_role in ('user', 'admin', 'ambassador'));

update public.user_profiles p set account_role = 'admin'
where exists (select 1 from public.app_admins a where a.user_id = p.user_id);

create table if not exists public.analytics_events (
    id bigint generated always as identity primary key,
    user_id uuid references auth.users(id) on delete cascade,
    event_name text not null,
    source text,
    metadata jsonb not null default '{}'::jsonb,
    occurred_at timestamptz not null default now()
);
create index if not exists analytics_events_name_time_idx on public.analytics_events(event_name, occurred_at desc);
create index if not exists analytics_events_user_time_idx on public.analytics_events(user_id, occurred_at desc);
alter table public.analytics_events enable row level security;
create policy "analytics_event_own_insert" on public.analytics_events for insert to authenticated with check (user_id = auth.uid());
create policy "analytics_event_admin_read" on public.analytics_events for select to authenticated using (public.is_super_admin());

create table if not exists public.feedback_items (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) on delete set null,
    type text not null default 'feedback' check (type in ('bug', 'feedback', 'feature', 'support', 'review')),
    subject text not null,
    message text not null,
    status text not null default 'new' check (status in ('new', 'investigating', 'fixed', 'closed')),
    assigned_to text,
    internal_notes text,
    app_version text,
    device_info text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table public.feedback_items enable row level security;
create policy "feedback_own_insert" on public.feedback_items for insert to authenticated with check (user_id = auth.uid());
create policy "feedback_own_read" on public.feedback_items for select to authenticated using (user_id = auth.uid() or public.is_super_admin());
create policy "feedback_admin_manage" on public.feedback_items for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

create or replace function public.is_app_admin(check_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
    select exists(select 1 from public.app_admins where user_id = check_user_id and role in ('super_admin', 'admin'));
$$;
grant execute on function public.is_app_admin(uuid) to authenticated;

create or replace function public.log_analytics_event(input_event_name text, input_source text default null, input_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$ begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    insert into public.analytics_events(user_id,event_name,source,metadata)
    values(auth.uid(),input_event_name,input_source,coalesce(input_metadata,'{}'::jsonb));
end; $$;
grant execute on function public.log_analytics_event(text,text,jsonb) to authenticated;

create or replace function public.submit_feedback(input_type text,input_subject text,input_message text,input_app_version text,input_device_info text)
returns jsonb language plpgsql security definer set search_path=public as $$ declare created public.feedback_items%rowtype; begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    insert into public.feedback_items(user_id,type,subject,message,app_version,device_info)
    values(auth.uid(),input_type,trim(input_subject),trim(input_message),input_app_version,input_device_info) returning * into created;
    return to_jsonb(created);
end; $$;
grant execute on function public.submit_feedback(text,text,text,text,text) to authenticated;

create or replace function public.admin_set_user_role(input_user_id uuid,input_role text)
returns void language plpgsql security definer set search_path=public as $$ declare before_role text; begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_role not in ('user','admin','ambassador') then raise exception 'invalid_role'; end if;
    if public.is_super_admin(input_user_id) then raise exception 'cannot_change_founder_role'; end if;
    select account_role into before_role from public.user_profiles where user_id=input_user_id;
    update public.user_profiles set account_role=input_role,updated_at=now() where user_id=input_user_id;
    if input_role='admin' then
        insert into public.app_admins(user_id,email,role,updated_at)
        select user_id,email,'admin',now() from public.user_profiles where user_id=input_user_id
        on conflict(user_id) do update set role='admin',email=excluded.email,updated_at=now();
    else
        delete from public.app_admins where user_id=input_user_id and role='admin';
    end if;
    insert into public.admin_audit_log(actor_user_id,action,target_user_id,target_type,target_id,before_value,after_value)
    values(auth.uid(),'user_role_changed',input_user_id,'user',input_user_id::text,jsonb_build_object('role',before_role),jsonb_build_object('role',input_role));
end; $$;
grant execute on function public.admin_set_user_role(uuid,text) to authenticated;

create or replace function public.admin_update_feedback(input_id uuid,input_status text,input_assigned_to text,input_internal_notes text)
returns void language plpgsql security definer set search_path=public as $$ begin
    if not public.is_app_admin() then raise exception 'admin_required'; end if;
    update public.feedback_items set status=input_status,assigned_to=nullif(input_assigned_to,''),internal_notes=nullif(input_internal_notes,''),updated_at=now() where id=input_id;
    insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,after_value)
    values(auth.uid(),'feedback_updated','feedback',input_id::text,jsonb_build_object('status',input_status,'assigned_to',input_assigned_to));
end; $$;
grant execute on function public.admin_update_feedback(uuid,text,text,text) to authenticated;

create or replace function public.admin_feedback_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$ begin
    if not public.is_app_admin() then raise exception 'admin_required'; end if;
    return coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at desc) from public.feedback_items f),'[]'::jsonb);
end; $$;
grant execute on function public.admin_feedback_dashboard() to authenticated;

create or replace function public.admin_product_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_app_admin() then raise exception 'admin_required'; end if;
 with activity as (
   select user_id, updated_at::date activity_day from public.sessions
   union select user_id, updated_at::date from public.truth_checks
   union select user_id, occurred_at::date from public.analytics_events where event_name='app_open'
 ), metrics as (
   select
    (select count(*) from public.user_profiles) total_users,
    (select count(distinct user_id) from activity where activity_day=current_date) dau,
    (select count(distinct user_id) from activity where activity_day>=current_date-29) mau,
    (select count(*) from public.user_profiles where created_at::date=current_date) new_today,
    (select count(*) from public.user_profiles where created_at>=date_trunc('week',now())) new_week,
    (select count(*) from public.user_profiles where created_at>=date_trunc('month',now())) new_month,
    (select round(count(*)::numeric/nullif((select count(*) from public.user_profiles),0),2) from public.sessions) avg_sessions,
    (select round(count(*)::numeric/nullif((select count(*) from public.user_profiles),0),2) from public.truth_checks) avg_truth,
    (select round(100.0*count(*) filter(where onboarding_complete)/nullif(count(*),0),1) from public.app_settings) onboarding_pct,
    (select round(100.0*count(*) filter(where reflection is not null)/nullif(count(*),0),1) from public.sessions) reflection_pct,
    (select round(avg(abs(actual-guess)),1) from public.truth_checks) avg_truth_gap
 ), retention as (
   select
    coalesce(round(100.0*count(*) filter(where exists(select 1 from activity a where a.user_id=p.user_id and a.activity_day=p.created_at::date+1))/nullif(count(*) filter(where p.created_at::date<=current_date-1),0),1),0) d1,
    coalesce(round(100.0*count(*) filter(where exists(select 1 from activity a where a.user_id=p.user_id and a.activity_day=p.created_at::date+7))/nullif(count(*) filter(where p.created_at::date<=current_date-7),0),1),0) d7,
    coalesce(round(100.0*count(*) filter(where exists(select 1 from activity a where a.user_id=p.user_id and a.activity_day=p.created_at::date+30))/nullif(count(*) filter(where p.created_at::date<=current_date-30),0),1),0) d30
   from public.user_profiles p
 )
 select jsonb_build_object(
  'overview',(select to_jsonb(metrics) from metrics),
  'retention',(select to_jsonb(retention) from retention),
  'timeseries',(select coalesce(jsonb_agg(jsonb_build_object('date',d.metric_date,'downloads',(select count(*) from public.analytics_events e where e.event_name='download' and e.occurred_at::date=d.metric_date),'active_users',(select count(distinct a.user_id) from activity a where a.activity_day=d.metric_date)) order by d.metric_date),'[]'::jsonb) from (select generate_series(current_date-29,current_date,interval '1 day')::date metric_date)d),
  'versions',(select coalesce(jsonb_agg(jsonb_build_object('version',version,'users',users) order by users desc),'[]'::jsonb) from (select metadata->>'app_version' version,count(distinct user_id) users from public.analytics_events where event_name='app_open' and metadata?'app_version' group by 1)v),
  'funnel',jsonb_build_array(
    jsonb_build_object('stage','App Store views','count',(select count(*) from public.analytics_events where event_name='app_store_view')),
    jsonb_build_object('stage','Downloads','count',(select count(*) from public.analytics_events where event_name='download')),
    jsonb_build_object('stage','Accounts','count',(select count(*) from public.user_profiles)),
    jsonb_build_object('stage','Onboarding','count',(select count(*) from public.app_settings where onboarding_complete)),
    jsonb_build_object('stage','Screen Time access','count',(select count(distinct user_id) from public.analytics_events where event_name='screen_time_permission')),
    jsonb_build_object('stage','First truth check','count',(select count(distinct user_id) from public.truth_checks)),
    jsonb_build_object('stage','Day 7 active','count',(select count(*) from public.user_profiles p where exists(select 1 from activity a where a.user_id=p.user_id and a.activity_day=p.created_at::date+7)))
  ),
  'sources',(select coalesce(jsonb_agg(jsonb_build_object('source',coalesce(o.referral_source,'Unknown'),'signups',count(*),'onboarded',count(*) filter(where s.onboarding_complete)) order by count(*) desc),'[]'::jsonb) from public.onboarding_profiles o left join public.app_settings s on s.user_id=o.user_id group by o.referral_source),
  'triggers',(select coalesce(jsonb_agg(jsonb_build_object('trigger',urge_reason,'count',total) order by total desc),'[]'::jsonb) from (select coalesce(urge_reason,'Not recorded') urge_reason,count(*) total from public.sessions group by 1)t)
 ) into result;
 return result;
end; $$;
grant execute on function public.admin_product_dashboard() to authenticated;

create or replace function public.admin_referral_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; begin
 if not public.is_app_admin() then raise exception 'admin_required'; end if;
 select jsonb_build_object(
 'campaigns',coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from public.referral_campaigns c),'[]'::jsonb),
 'standings','[]'::jsonb,
 'consent_requests',case when public.is_super_admin() then coalesce((select jsonb_agg(to_jsonb(r)-'request_token_hash' order by r.created_at desc) from public.parental_consent_requests r),'[]'::jsonb) else '[]'::jsonb end,
 'users',coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'email',p.email,'name',p.name,'created_at',p.created_at,'account_role',p.account_role,'onboarding_complete',coalesce(s.onboarding_complete,false),'session_count',(select count(*) from public.sessions se where se.user_id=p.user_id),'total_minutes',(select coalesce(sum(actual_duration),0) from public.sessions se where se.user_id=p.user_id),'reflection_count',(select count(*) from public.sessions se where se.user_id=p.user_id and reflection is not null)) order by p.created_at desc) from public.user_profiles p left join public.app_settings s on s.user_id=p.user_id),'[]'::jsonb)
 ) into result; return result; end; $$;
grant execute on function public.admin_referral_dashboard() to authenticated;
