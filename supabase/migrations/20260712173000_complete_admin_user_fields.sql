alter table public.feedback_items drop constraint if exists feedback_items_type_check;
alter table public.feedback_items add constraint feedback_items_type_check
    check (type in ('bug','feedback','feature','support','review','deletion'));

create or replace function public.admin_referral_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; begin
 if not public.is_app_admin() then raise exception 'admin_required'; end if;
 select jsonb_build_object(
 'campaigns',coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from public.referral_campaigns c),'[]'::jsonb),
 'standings','[]'::jsonb,
 'consent_requests',case when public.is_super_admin() then coalesce((select jsonb_agg(to_jsonb(r)-'request_token_hash' order by r.created_at desc) from public.parental_consent_requests r),'[]'::jsonb) else '[]'::jsonb end,
 'users',coalesce((select jsonb_agg(jsonb_build_object(
   'user_id',p.user_id,'email',p.email,'name',p.name,'created_at',p.created_at,'account_role',p.account_role,
   'onboarding_complete',coalesce(s.onboarding_complete,false),
   'calibration_complete',(o.scroll_estimate_minutes is not null),
   'last_active_at',(select max(active_time) from (
      select max(se.updated_at) active_time from public.sessions se where se.user_id=p.user_id
      union all select max(t.updated_at) from public.truth_checks t where t.user_id=p.user_id
      union all select max(e.occurred_at) from public.analytics_events e where e.user_id=p.user_id
      union all select max(d.last_seen_at) from public.device_bindings d where d.user_id=p.user_id
   ) activity),
   'session_count',(select count(*) from public.sessions se where se.user_id=p.user_id),
   'intervention_count',(select count(*) from public.sessions se where se.user_id=p.user_id),
   'truth_check_count',(select count(*) from public.truth_checks t where t.user_id=p.user_id),
   'total_minutes',(select coalesce(sum(actual_duration),0) from public.sessions se where se.user_id=p.user_id),
   'reflection_count',(select count(*) from public.sessions se where se.user_id=p.user_id and reflection is not null)
 ) order by p.created_at desc) from public.user_profiles p
 left join public.app_settings s on s.user_id=p.user_id
 left join public.onboarding_profiles o on o.user_id=p.user_id),'[]'::jsonb)
 ) into result; return result; end; $$;
grant execute on function public.admin_referral_dashboard() to authenticated;
