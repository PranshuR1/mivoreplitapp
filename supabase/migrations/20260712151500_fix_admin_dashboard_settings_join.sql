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
                    'user_id', a.referrer_user_id, 'name', coalesce(p.name, 'Mivo user'), 'email', p.email,
                    'referral_code', rp.referral_code,
                    'qualified_count', count(*) filter (where a.status = 'qualified'),
                    'pending_count', count(*) filter (where a.status = 'pending'),
                    'reached_at', max(a.qualified_at)
                ) row_data
                from public.referral_attributions a
                left join public.user_profiles p on p.user_id = a.referrer_user_id
                left join public.referral_profiles rp on rp.user_id = a.referrer_user_id
                group by a.referrer_user_id, p.name, p.email, rp.referral_code
            ) standings_data
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
