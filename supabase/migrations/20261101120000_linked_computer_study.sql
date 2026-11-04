-- One account-owned session, explicitly claimed by one desktop. No titles, URLs or input leave it.
alter table public.study_sessions drop constraint if exists study_sessions_source_check;
alter table public.study_sessions add constraint study_sessions_source_check check (source in ('ios', 'web', 'desktop'));
alter table public.study_sessions add column if not exists focused_seconds integer;

create table public.linked_study_sessions (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    task text not null check (char_length(task) between 1 and 120),
    status text not null default 'waiting' check (status in ('waiting', 'active', 'finished', 'cancelled')),
    requested_at timestamptz not null default now(),
    started_at timestamptz,
    ended_at timestamptz,
    last_seen_at timestamptz,
    desktop_id uuid,
    activity text not null default 'uncertain' check (activity in ('focus', 'drift', 'away', 'uncertain')),
    focused_seconds double precision not null default 0,
    distracted_seconds double precision not null default 0,
    away_seconds double precision not null default 0,
    uncertain_seconds double precision not null default 0,
    reward_device_id uuid,
    reward_day text,
    reward_seconds integer not null default 0
);
create unique index linked_study_one_live_per_user on public.linked_study_sessions(user_id) where status in ('waiting', 'active');
create index linked_study_history on public.linked_study_sessions(user_id, requested_at desc);
alter table public.linked_study_sessions enable row level security;
revoke all on public.linked_study_sessions from public, anon, authenticated;

create function public._linked_study_json(s public.linked_study_sessions) returns jsonb
language sql stable set search_path = public as $$
    select jsonb_build_object(
        'id', s.id, 'task', s.task, 'status', s.status, 'requestedAt', s.requested_at,
        'startedAt', s.started_at, 'endedAt', s.ended_at, 'lastSeenAt', s.last_seen_at,
        'desktopID', s.desktop_id, 'activity', s.activity,
        'focusedSeconds', floor(s.focused_seconds)::integer,
        'distractedSeconds', floor(s.distracted_seconds)::integer,
        'awaySeconds', floor(s.away_seconds)::integer,
        'uncertainSeconds', floor(s.uncertain_seconds)::integer);
$$;

-- A new sample credits the PREVIOUS state only while the connection was continuous.
-- Sleep, app termination, lost connectivity and disabled tracking cannot backfill focus credit.
create function public._linked_study_tick(input_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions; seconds double precision;
begin
    select * into s from public.linked_study_sessions where id = input_id for update;
    if s.status <> 'active' or s.last_seen_at is null then return; end if;
    seconds := extract(epoch from (now() - s.last_seen_at));
    if seconds < 0 or seconds > 20 then return; end if;
    update public.linked_study_sessions set
        focused_seconds = focused_seconds + case when activity = 'focus' then seconds else 0 end,
        distracted_seconds = distracted_seconds + case when activity = 'drift' then seconds else 0 end,
        away_seconds = away_seconds + case when activity = 'away' then seconds else 0 end,
        uncertain_seconds = uncertain_seconds + case when activity = 'uncertain' then seconds else 0 end
    where id = input_id;
end;
$$;

create function public.my_linked_study() returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    -- Expire abandoned requests. Long-disconnected sessions remain finishable with saved totals.
    update public.linked_study_sessions set status = 'cancelled', ended_at = now()
      where user_id = auth.uid() and status = 'waiting' and requested_at < now() - interval '24 hours';
    select * into s from public.linked_study_sessions where user_id = auth.uid()
      order by (status in ('waiting', 'active')) desc, requested_at desc limit 1;
    return case when s.id is null then null else public._linked_study_json(s) end;
end;
$$;

create function public.request_linked_study(input_id uuid, input_task text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions; cleaned text;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 7911));
    select * into s from public.linked_study_sessions where user_id = auth.uid() and status in ('waiting', 'active') limit 1;
    if s.id is not null then return public._linked_study_json(s); end if;
    cleaned := public._study_clean_text(input_task, 120);
    if cleaned = '' then raise exception 'task_required'; end if;
    insert into public.linked_study_sessions(id, user_id, task) values(input_id, auth.uid(), cleaned)
      on conflict (id) do nothing;
    select * into s from public.linked_study_sessions where id = input_id and user_id = auth.uid();
    if s.id is null then raise exception 'invalid_session'; end if;
    return public._linked_study_json(s);
end;
$$;

create function public.connect_linked_study(input_id uuid, input_desktop_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if input_desktop_id is null then raise exception 'device_required'; end if;
    select * into s from public.linked_study_sessions where id = input_id and user_id = auth.uid() for update;
    if s.id is null then raise exception 'session_not_found'; end if;
    if s.status not in ('waiting', 'active') then return public._linked_study_json(s); end if;
    if s.desktop_id is not null and s.desktop_id <> input_desktop_id
       and s.last_seen_at > now() - interval '20 seconds' then raise exception 'computer_already_connected'; end if;
    update public.linked_study_sessions set status = 'active', started_at = coalesce(started_at, now()),
      desktop_id = input_desktop_id, last_seen_at = now(), activity = 'uncertain' where id = input_id returning * into s;
    return public._linked_study_json(s);
end;
$$;

create function public.ping_linked_study(input_id uuid, input_desktop_id uuid, input_activity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if input_activity is null or input_activity not in ('focus', 'drift', 'away', 'uncertain') then raise exception 'invalid_activity'; end if;
    select * into s from public.linked_study_sessions where id = input_id and user_id = auth.uid() for update;
    if s.id is null then raise exception 'session_not_found'; end if;
    if s.status <> 'active' then return public._linked_study_json(s); end if;
    if s.desktop_id is distinct from input_desktop_id then raise exception 'wrong_computer'; end if;
    -- A session cannot run indefinitely if someone leaves their computer on.
    if s.started_at < now() - interval '16 hours' then
        return public.finish_linked_study(input_id);
    end if;
    perform public._linked_study_tick(input_id);
    update public.linked_study_sessions set last_seen_at = now(), activity = input_activity where id = input_id returning * into s;
    -- Keep an existing open room live, respecting its task visibility settings.
    update public.study_rooms set live_task = s.task, live_started_at = s.started_at,
      live_seen_at = now(), updated_at = now() where owner_user_id = auth.uid() and is_open;
    return public._linked_study_json(s);
end;
$$;

create function public.finish_linked_study(input_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    select * into s from public.linked_study_sessions where id = input_id and user_id = auth.uid() for update;
    if s.id is null then raise exception 'session_not_found'; end if;
    if s.status in ('finished', 'cancelled') then return public._linked_study_json(s); end if;
    perform public._linked_study_tick(input_id);
    update public.linked_study_sessions set status = case when started_at is null then 'cancelled' else 'finished' end,
      ended_at = case when started_at is null then now() else least(now(), started_at + interval '16 hours') end
      where id = input_id returning * into s;
    if s.status = 'finished' and s.ended_at > s.started_at then
        insert into public.study_sessions(id, user_id, task, started_at, ended_at, source, focused_seconds)
        values(s.id, s.user_id, s.task, s.started_at, s.ended_at, 'desktop',
          least(floor(s.focused_seconds)::integer, floor(extract(epoch from s.ended_at - s.started_at))::integer))
        on conflict (id) do nothing;
    end if;
    update public.study_rooms set live_task = null, live_started_at = null, live_seen_at = null,
      updated_at = now() where owner_user_id = auth.uid() and live_started_at = s.started_at;
    return public._linked_study_json(s);
end;
$$;

-- Reward delivery is assigned to one phone installation. Repeated calls return the SAME grants.
-- The phone persists the grant ID and balance together, and applies its existing daily cap.
-- Plus is supplied by the phone's existing entitlement check, as in the video study flow.
create function public.linked_study_rewards(input_device_id uuid, input_has_plus boolean, input_time_zone text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.linked_study_sessions; today text; first_study timestamptz; used integer; amount integer;
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if input_device_id is null then raise exception 'device_required'; end if;
    if not exists(select 1 from pg_timezone_names where name = input_time_zone) then raise exception 'invalid_time_zone'; end if;
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 7911));
    today := to_char(now() at time zone input_time_zone, 'YYYY-MM-DD');
    select min(started_at) into first_study from public.study_sessions where user_id = auth.uid() and source in ('ios', 'desktop');
    select coalesce(sum(reward_seconds), 0) into used from public.linked_study_sessions where user_id = auth.uid() and reward_day = today;
    for s in select * from public.linked_study_sessions where user_id = auth.uid() and status = 'finished'
      and reward_device_id is null and to_char(ended_at at time zone input_time_zone, 'YYYY-MM-DD') = today
      order by ended_at for update loop
        amount := 0;
        if input_has_plus or s.started_at < first_study + interval '7 days' then
            amount := least(greatest(0, floor(s.focused_seconds / 3)::integer), greatest(0, 3600 - used));
        end if;
        -- Keep locked rewards available if Plus is activated later today.
        if amount > 0 then
            update public.linked_study_sessions set reward_device_id = input_device_id, reward_day = today,
              reward_seconds = amount where id = s.id;
            used := used + amount;
        end if;
    end loop;
    return coalesce((select jsonb_agg(jsonb_build_object('sessionID', id, 'dayKey', reward_day, 'scrollSeconds', reward_seconds))
      from public.linked_study_sessions where user_id = auth.uid() and reward_device_id = input_device_id and reward_day = today), '[]'::jsonb);
end;
$$;

-- Extend the existing history contract, preserving every old field.
create or replace function public.my_study_sessions(input_since timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((select jsonb_agg(to_jsonb(s) order by s.started_at desc) from (
      select id, task, started_at, ended_at, recorded_seconds, scroll_seconds_earned, source, focused_seconds
      from public.study_sessions where user_id = auth.uid() and started_at >= coalesce(input_since, now() - interval '120 days')
      order by started_at desc limit 500) s), '[]'::jsonb);
end;
$$;

revoke all on function public._linked_study_json(public.linked_study_sessions) from public, anon, authenticated;
revoke all on function public._linked_study_tick(uuid) from public, anon, authenticated;
revoke all on function public.my_linked_study() from public, anon;
revoke all on function public.request_linked_study(uuid, text) from public, anon;
revoke all on function public.connect_linked_study(uuid, uuid) from public, anon;
revoke all on function public.ping_linked_study(uuid, uuid, text) from public, anon;
revoke all on function public.finish_linked_study(uuid) from public, anon;
revoke all on function public.linked_study_rewards(uuid, boolean, text) from public, anon;
grant execute on function public.my_linked_study() to authenticated;
grant execute on function public.request_linked_study(uuid, text) to authenticated;
grant execute on function public.connect_linked_study(uuid, uuid) to authenticated;
grant execute on function public.ping_linked_study(uuid, uuid, text) to authenticated;
grant execute on function public.finish_linked_study(uuid) to authenticated;
grant execute on function public.linked_study_rewards(uuid, boolean, text) to authenticated;
