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
    values ('Mivo Referral Campaign ' || campaign_number,
        'Invite people to build a more intentional relationship with scrolling.',
        'draft', '0.1-draft', auth.uid())
    returning * into created;
    insert into public.referral_milestones (campaign_id, target_count)
    select created.id, target from unnest(array[1, 3, 5, 10, 20]) target;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), 'campaign_created', 'referral_campaign', created.id::text, to_jsonb(created));
    return to_jsonb(created);
end;
$$;
grant execute on function public.admin_create_referral_campaign() to authenticated;

create or replace function public.admin_referral_dashboard()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select jsonb_build_object(
        'campaigns', coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from public.referral_campaigns c), '[]'::jsonb),
        'standings', coalesce((select jsonb_agg(row_data order by (row_data->>'qualified_count')::int desc, row_data->>'reached_at' asc)
            from (select jsonb_build_object(
                'campaign_id', a.campaign_id, 'user_id', a.referrer_user_id,
                'name', coalesce(p.name, 'Mivo user'), 'email', p.email,
                'referral_code', rp.referral_code,
                'qualified_count', count(*) filter (where a.status = 'qualified'),
                'pending_count', count(*) filter (where a.status = 'pending'),
                'reached_at', max(a.qualified_at)) row_data
                from public.referral_attributions a
                left join public.user_profiles p on p.user_id = a.referrer_user_id
                left join public.referral_profiles rp on rp.user_id = a.referrer_user_id
                group by a.campaign_id, a.referrer_user_id, p.name, p.email, rp.referral_code) standings_data), '[]'::jsonb),
        'consent_requests', coalesce((select jsonb_agg(to_jsonb(r) - 'request_token_hash' order by r.created_at desc)
            from public.parental_consent_requests r), '[]'::jsonb),
        'users', coalesce((select jsonb_agg(jsonb_build_object(
            'user_id', p.user_id, 'email', p.email, 'name', p.name, 'created_at', p.created_at,
            'onboarding_complete', coalesce(s.onboarding_complete, false),
            'session_count', (select count(*) from public.sessions se where se.user_id = p.user_id),
            'total_minutes', (select coalesce(sum(actual_duration), 0) from public.sessions se where se.user_id = p.user_id),
            'reflection_count', (select count(*) from public.sessions se where se.user_id = p.user_id and reflection is not null)
        ) order by p.created_at desc) from public.user_profiles p
        left join public.app_settings s on s.user_id = p.user_id), '[]'::jsonb)
    ) into result;
    return result;
end;
$$;
grant execute on function public.admin_referral_dashboard() to authenticated;
