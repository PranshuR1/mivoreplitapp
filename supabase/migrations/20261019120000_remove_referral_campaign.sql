-- Remove the referral campaign / referral challenge and the ambassador program.
--
-- NOT APPLIED. Review, then run against a staging copy first. This migration
-- permanently deletes referral codes, attributions, milestones, campaign rule
-- versions, ambassador name assignments, and the two onboarding columns that
-- only existed for the campaign. Roll out in this order:
--   1. apply this migration (it adds admin_user_dashboard, which the new app
--      build calls in place of admin_referral_dashboard);
--   2. ship the app build that no longer contains the referral hub;
--   3. empty and delete the private "campaign-rules" storage bucket from the
--      Supabase dashboard (SQL cannot remove the stored files).
-- Older app builds still in the wild lose their Referral Hub and the founder
-- admin screens that call the dropped functions once this is applied.
--
-- onboarding_profiles.referral_source is deliberately kept: it is the answer to
-- "Where did you find us?" and still feeds admin_product_dashboard.

-- 1. New accounts no longer receive a referral code. Same body as
--    20260712150000_change_super_admin_email.sql minus the referral insert.
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
        on conflict (user_id) do update
        set email = excluded.email, role = 'super_admin', updated_at = now();
    end if;
    return new;
end;
$$;

-- 2. Finishing onboarding no longer qualifies a referral.
drop trigger if exists qualify_referral_on_onboarding on public.app_settings;
drop function if exists public.qualify_referral_after_onboarding();

-- 3. The founder user list and parental-consent queue used to ride along with
--    the referral dashboard. They get their own function, without campaigns,
--    standings, or ambassador attribution.
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
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;

    select jsonb_build_object(
        'consent_requests', coalesce((
            select jsonb_agg(to_jsonb(r) - 'request_token_hash' order by r.created_at desc)
            from public.parental_consent_requests r
        ), '[]'::jsonb),
        'users', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', p.user_id,
                'email', p.email,
                'name', p.name,
                'created_at', p.created_at,
                'account_role', p.account_role,
                'onboarding_complete', coalesce(s.onboarding_complete, false),
                'calibration_complete', (o.scroll_estimate_minutes is not null),
                'last_active_at', (
                    select max(active_time) from (
                        select max(se.updated_at) active_time from public.sessions se where se.user_id = p.user_id
                        union all select max(t.updated_at) from public.truth_checks t where t.user_id = p.user_id
                        union all select max(e.occurred_at) from public.analytics_events e where e.user_id = p.user_id
                        union all select max(d.last_seen_at) from public.device_bindings d where d.user_id = p.user_id
                    ) activity
                ),
                'session_count', (select count(*) from public.sessions se where se.user_id = p.user_id),
                'intervention_count', (select count(*) from public.sessions se where se.user_id = p.user_id),
                'truth_check_count', (select count(*) from public.truth_checks t where t.user_id = p.user_id),
                'total_minutes', (select coalesce(sum(actual_duration), 0) from public.sessions se where se.user_id = p.user_id),
                'reflection_count', (select count(*) from public.sessions se where se.user_id = p.user_id and reflection is not null)
            ) order by p.created_at desc)
            from public.user_profiles p
            left join public.app_settings s on s.user_id = p.user_id
            left join public.onboarding_profiles o on o.user_id = p.user_id
        ), '[]'::jsonb)
    ) into result;

    return result;
end;
$$;
grant execute on function public.admin_user_dashboard() to authenticated;

-- 4. Founder user detail no longer returns a referral profile.
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

-- 5. Admin review queue: drop the campaign and referral-risk paths.
delete from public.admin_review_items
where type in ('campaign', 'referral_review')
   or source_table in ('referral_campaigns', 'referral_risk_flags');

drop trigger if exists queue_campaign_native_review on public.referral_campaigns;

create or replace function public.queue_native_admin_review()
returns trigger language plpgsql security definer set search_path = public as $$
declare review_type text; review_title text; review_detail text; source_value text;
begin
    if tg_table_name='announcements' and new.status='draft' then
      review_type:='announcement'; review_title:='Announcement draft'; review_detail:=new.title; source_value:=new.id::text;
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

-- 6. Nightly job: keep the data-quality scan, drop the referral risk scan.
do $$
begin
    if exists(select 1 from pg_extension where extname='pg_cron') then
      if exists(select 1 from cron.job where jobname='mivo-nightly-data-quality') then
        perform cron.unschedule('mivo-nightly-data-quality');
      end if;
      perform cron.schedule('mivo-nightly-data-quality','17 4 * * *','select public.run_data_quality_scan();');
    end if;
exception when undefined_table or invalid_schema_name or insufficient_privilege then
    null;
end $$;

-- 7. Ambassador role removed. Existing ambassador accounts become ordinary users.
update public.user_profiles set account_role = 'user', updated_at = now() where account_role = 'ambassador';
alter table public.user_profiles drop constraint if exists user_profiles_account_role_check;
alter table public.user_profiles add constraint user_profiles_account_role_check
    check (account_role in ('user', 'admin'));

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
    if input_role not in ('user', 'admin') then raise exception 'invalid_role'; end if;
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
        'can_manage_announcements', founder or account_role_value = 'admin'
    );
end;
$$;
grant execute on function public.current_account_access() to authenticated;

-- 8. Drop the campaign, referral, and ambassador RPCs.
drop function if exists public.attach_referral_code(text);
drop function if exists public.get_my_referral_summary();
drop function if exists public.admin_create_referral_campaign();
drop function if exists public.admin_set_referral_status(uuid, text, text);
drop function if exists public.admin_referral_dashboard();
drop function if exists public.scan_referral_risk_signals();
drop function if exists public.admin_ambassador_attribution_options(uuid);
drop function if exists public.admin_set_ambassador_names(uuid, text[]);
drop function if exists public.ambassador_dashboard();

-- 9. Drop the data. CASCADE removes the policies, triggers, and foreign keys
--    that hang off these tables.
drop table if exists public.referral_risk_flags cascade;
drop table if exists public.referral_attributions cascade;
drop table if exists public.referral_profiles cascade;
drop table if exists public.referral_milestones cascade;
drop table if exists public.campaign_rule_versions cascade;
drop table if exists public.referral_campaigns cascade;
drop table if exists public.ambassador_name_assignments cascade;

drop function if exists public.protect_referral_campaign_terms();
drop function if exists public.audit_campaign_change();
drop function if exists public.generate_mivo_referral_code();
drop function if exists public.normalize_ambassador_name(text);

-- 10. Campaign-only onboarding columns (the code a user typed, and the
--     ambassador name they entered).
alter table public.onboarding_profiles drop column if exists referral_ambassador_name;
alter table public.onboarding_profiles drop column if exists referral_campaign_code;

-- 11. Official-rules storage policies. The bucket itself must be emptied and
--     deleted from the dashboard.
drop policy if exists "authenticated_read_campaign_rules" on storage.objects;
drop policy if exists "super_admin_manage_campaign_rules" on storage.objects;
