-- Read-side counterparts to save_recovery_plan / save_monthly_effect_report /
-- record_mivo_clear_session, all of which were push-only until now: Supabase
-- has held a full history for each ever since those functions were added,
-- but a signed-out or reinstalled device had no way to read any of it back.
-- Same security-definer + auth.uid() pattern as the existing
-- get_accountability_connections, so no new table grants are needed.

create or replace function public.get_recovery_plans()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(p.raw_plan order by p.created_at desc)
        from public.recovery_plans p where p.user_id = auth.uid()
    ), '[]'::jsonb);
end; $$;
grant execute on function public.get_recovery_plans() to authenticated;

create or replace function public.get_monthly_effect_reports()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(r.report order by r.generated_at desc)
        from public.monthly_effect_reports r where r.user_id = auth.uid()
    ), '[]'::jsonb);
end; $$;
grant execute on function public.get_monthly_effect_reports() to authenticated;

-- mivo_clear_sessions has no raw-jsonb column (its fields were always
-- stored flat), so this rebuilds the exact camelCase shape MivoClearSession
-- decodes, formatting timestamps the same way ISO8601DateFormatter's
-- default output does (no fractional seconds, "Z" suffix) so a restored
-- session's startedAt/endedAt strings match what the app itself produces.
create or replace function public.get_mivo_clear_sessions()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', s.id,
            'platform', s.platform,
            'entryPoint', s.entry_point,
            'startedAt', to_char(s.started_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'endedAt', to_char(s.ended_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'activeSeconds', s.active_seconds,
            'blockedRouteCount', s.blocked_route_count,
            'filterVersion', s.filter_version
        ) order by s.started_at desc)
        from public.mivo_clear_sessions s where s.user_id = auth.uid()
    ), '[]'::jsonb);
end; $$;
grant execute on function public.get_mivo_clear_sessions() to authenticated;
