-- Expose onboarding ambassador attribution to the founder user database.
-- This intentionally does not use referral campaign attribution.
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
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;

    select jsonb_build_object(
        'campaigns', coalesce((
            select jsonb_agg(to_jsonb(c) order by c.updated_at desc)
            from public.referral_campaigns c
        ), '[]'::jsonb),
        'standings', '[]'::jsonb,
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
                'reflection_count', (select count(*) from public.sessions se where se.user_id = p.user_id and reflection is not null),
                'referral_source', o.referral_source,
                'referral_ambassador_name', o.referral_ambassador_name,
                'ambassador_user_id', assignment.ambassador_user_id,
                'ambassador_account_name', ambassador_profile.name,
                'ambassador_referred_at', case
                    when o.referral_source = 'ambassador' then p.created_at
                    else null
                end
            ) order by p.created_at desc)
            from public.user_profiles p
            left join public.app_settings s on s.user_id = p.user_id
            left join public.onboarding_profiles o on o.user_id = p.user_id
            left join public.ambassador_name_assignments assignment
                on assignment.active
               and assignment.normalized_name = public.normalize_ambassador_name(o.referral_ambassador_name)
            left join public.user_profiles ambassador_profile
                on ambassador_profile.user_id = assignment.ambassador_user_id
        ), '[]'::jsonb)
    ) into result;

    return result;
end;
$$;

grant execute on function public.admin_referral_dashboard() to authenticated;
