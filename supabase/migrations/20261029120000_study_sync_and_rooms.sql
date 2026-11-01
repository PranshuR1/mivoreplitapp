-- Study sessions synced to the account, and study rooms.
--
-- Study sessions: the iPhone app and usemivo.app/study both finish sessions (a task, a start and
-- an end). Signed in, each one is saved here so the same account shows the same streak and history
-- on the website and in the app. The phone keeps its video and its scroll balance; only the
-- session record is stored. Nothing here can credit scroll time: the app earns that on the phone
-- from video it saved itself.
--
-- Study rooms: one link per person (usemivo.app/room/<code>). When the owner opens it and is in
-- a session, anyone with the link sees the owner's first name, what they are working on (if the
-- owner allows it) and how long they have been going, and can sit with them by giving a first
-- name. No account is needed to look or to sit. No video or photo is ever involved.
--
-- Nothing in these tables is readable or writable directly. Every access goes through the
-- security-definer functions below. Only two of them (study_room_view, study_room_sit) can be
-- called without signing in, and both need the room's random code.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.study_sessions (
    -- Made on the device that ran the session, so a retry never saves it twice.
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    task text not null check (char_length(task) between 1 and 120),
    started_at timestamptz not null,
    ended_at timestamptz not null,
    -- Seconds that are on saved video on the phone. Always 0 for the website.
    recorded_seconds integer not null default 0 check (recorded_seconds >= 0),
    scroll_seconds_earned integer not null default 0 check (scroll_seconds_earned >= 0),
    source text not null check (source in ('ios', 'web')),
    created_at timestamptz not null default now(),
    check (ended_at > started_at),
    check (ended_at - started_at <= interval '16 hours')
);

create index if not exists study_sessions_user_started_idx on public.study_sessions (user_id, started_at desc);

create table if not exists public.study_rooms (
    owner_user_id uuid primary key references auth.users(id) on delete cascade,
    -- Random and unguessable: 10 characters from a 31-character alphabet.
    code text not null unique check (code ~ '^[A-Z0-9]{10}$'),
    display_name text not null default 'Someone' check (char_length(display_name) between 1 and 24),
    is_open boolean not null default false,
    show_task boolean not null default true,
    -- The session in progress, refreshed by the owner's phone or browser about every 30 seconds.
    live_task text check (char_length(live_task) <= 120),
    live_started_at timestamptz,
    live_seen_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.study_room_visitors (
    owner_user_id uuid not null references public.study_rooms(owner_user_id) on delete cascade,
    -- Made by the visitor's browser. It is not an account.
    visitor_id uuid not null,
    name text not null check (char_length(name) between 1 and 24),
    seen_at timestamptz not null default now(),
    removed boolean not null default false,
    primary key (owner_user_id, visitor_id)
);

alter table public.study_sessions enable row level security;
alter table public.study_rooms enable row level security;
alter table public.study_room_visitors enable row level security;
revoke all on public.study_sessions from anon, authenticated;
revoke all on public.study_rooms from anon, authenticated;
revoke all on public.study_room_visitors from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helpers (not callable from the app)
-- ---------------------------------------------------------------------------

-- One line of text for a name or a task: control characters and runs of whitespace become one space.
create or replace function public._study_clean_text(input text, max_length integer)
returns text
language sql
immutable
as $$
    select left(btrim(regexp_replace(coalesce(input, ''), '[[:cntrl:][:space:]]+', ' ', 'g')), max_length);
$$;

-- Ten characters, no I/L/O/0/1. Rejection sampling keeps every character equally likely; bytes 6
-- and 8 of a UUID carry its version and variant bits, so they are skipped.
create or replace function public._study_room_new_code()
returns text
language plpgsql
volatile
as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    result text := '';
    raw bytea;
    idx integer;
    byte_value integer;
begin
    while char_length(result) < 10 loop
        raw := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
        for idx in 0..15 loop
            continue when idx in (6, 8);
            byte_value := get_byte(raw, idx);
            if byte_value < 248 then -- 248 = 8 * 31
                result := result || substr(alphabet, (byte_value % 31) + 1, 1);
                exit when char_length(result) = 10;
            end if;
        end loop;
    end loop;
    return result;
end;
$$;

-- The owner's whole view of their room, including who is sitting with them.
create or replace function public._study_room_owner_json(owner uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    r public.study_rooms;
    live boolean;
begin
    select * into r from public.study_rooms where owner_user_id = owner;
    if not found then return jsonb_build_object('has_room', false); end if;
    live := r.live_started_at is not null and r.live_seen_at > now() - interval '2 minutes';
    return jsonb_build_object(
        'has_room', true,
        'code', r.code,
        'display_name', r.display_name,
        'is_open', r.is_open,
        'show_task', r.show_task,
        'studying', live,
        'task', case when live then r.live_task end,
        'started_at', case when live then r.live_started_at end,
        'sitting', coalesce((
            select jsonb_agg(jsonb_build_object('id', v.visitor_id, 'name', v.name) order by v.seen_at desc)
            from public.study_room_visitors v
            where v.owner_user_id = owner and not v.removed and v.seen_at > now() - interval '90 seconds'
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public._study_clean_text(text, integer) from public, anon, authenticated;
revoke all on function public._study_room_new_code() from public, anon, authenticated;
revoke all on function public._study_room_owner_json(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Study sessions
-- ---------------------------------------------------------------------------

-- Saves up to 50 finished sessions. Saving one that already exists changes nothing, so a retry or
-- a second device is safe. A bad entry is skipped and counted, not fatal. The website cannot claim
-- video: its sessions are stored with no recorded seconds and no scroll time.
create or replace function public.sync_study_sessions(input_sessions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    item jsonb;
    accepted integer := 0;
    rejected integer := 0;
    new_id uuid;
    new_task text;
    new_start timestamptz;
    new_end timestamptz;
    new_source text;
    length_seconds integer;
    new_recorded integer;
    new_earned integer;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    if input_sessions is null or jsonb_typeof(input_sessions) <> 'array' then raise exception 'invalid_sessions'; end if;
    if jsonb_array_length(input_sessions) > 50 then raise exception 'too_many_sessions'; end if;
    if (select count(*) from public.study_sessions where user_id = caller) >= 5000 then
        raise exception 'session_limit_reached';
    end if;

    for item in select value from jsonb_array_elements(input_sessions) loop
        begin
            new_id := (item->>'id')::uuid;
            new_task := public._study_clean_text(item->>'task', 120);
            new_start := (item->>'started_at')::timestamptz;
            new_end := (item->>'ended_at')::timestamptz;
            new_source := case when item->>'source' = 'web' then 'web' else 'ios' end;

            if new_task = ''
               or new_end <= new_start
               or new_end - new_start > interval '16 hours'
               or new_end > now() + interval '5 minutes'
               or new_start < now() - interval '3 years' then
                rejected := rejected + 1;
                continue;
            end if;

            length_seconds := floor(extract(epoch from (new_end - new_start)))::integer;
            if new_source = 'web' then
                new_recorded := 0;
                new_earned := 0;
            else
                new_recorded := least(greatest(coalesce((item->>'recorded_seconds')::integer, 0), 0), length_seconds);
                -- The daily earn cap is 60 minutes, so one session cannot have earned more.
                new_earned := least(greatest(coalesce((item->>'scroll_seconds_earned')::integer, 0), 0), 3600);
            end if;

            insert into public.study_sessions (id, user_id, task, started_at, ended_at, recorded_seconds, scroll_seconds_earned, source)
            values (new_id, caller, new_task, new_start, new_end, new_recorded, new_earned, new_source)
            on conflict (id) do nothing;
            if found then accepted := accepted + 1; end if;
        exception when others then
            rejected := rejected + 1;
        end;
    end loop;

    return jsonb_build_object('accepted', accepted, 'rejected', rejected);
end;
$$;

-- The caller's sessions, newest first: the last 120 days unless a start is given, at most 500.
create or replace function public.my_study_sessions(input_since timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', s.id,
            'task', s.task,
            'started_at', s.started_at,
            'ended_at', s.ended_at,
            'recorded_seconds', s.recorded_seconds,
            'scroll_seconds_earned', s.scroll_seconds_earned,
            'source', s.source
        ) order by s.started_at desc)
        from (
            select * from public.study_sessions
            where user_id = caller and started_at >= coalesce(input_since, now() - interval '120 days')
            order by started_at desc
            limit 500
        ) s
    ), '[]'::jsonb);
end;
$$;

-- Only sessions made on the website can be removed one by one: the phone owns the ones it
-- recorded, along with the scroll time they earned.
create or replace function public.delete_study_session(input_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    delete from public.study_sessions where id = input_id and user_id = caller and source = 'web';
    return found;
end;
$$;

-- Removes every saved session. The phone keeps its own copy.
create or replace function public.delete_my_study_history()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    removed integer;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    delete from public.study_sessions where user_id = caller;
    get diagnostics removed = row_count;
    return removed;
end;
$$;

-- ---------------------------------------------------------------------------
-- Study room: the owner
-- ---------------------------------------------------------------------------

-- The caller's room, or {"has_room": false}. Never creates one.
create or replace function public.my_study_room()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    return public._study_room_owner_json(caller);
end;
$$;

-- Makes the caller's room if they have none (closed, so nobody can see it yet), then returns it.
-- The name starts as the first word of the account name.
create or replace function public.ensure_study_room()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    suggested text;
    attempts integer := 0;
begin
    if caller is null then raise exception 'authentication_required'; end if;

    if not exists (select 1 from public.study_rooms where owner_user_id = caller) then
        select public._study_clean_text(
            split_part(btrim(coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name', '')), ' ', 1), 24)
        into suggested
        from auth.users u
        where u.id = caller;
        suggested := coalesce(nullif(suggested, ''), 'Someone');

        loop
            attempts := attempts + 1;
            if attempts > 10 then raise exception 'code_unavailable'; end if;
            begin
                insert into public.study_rooms (owner_user_id, code, display_name)
                values (caller, public._study_room_new_code(), suggested);
                exit;
            exception when unique_violation then
                -- Either the code collided or a parallel call just made this person's room.
                if exists (select 1 from public.study_rooms where owner_user_id = caller) then exit; end if;
            end;
        end loop;
    end if;

    return public._study_room_owner_json(caller);
end;
$$;

-- Any of the three can be left null to keep it as it is. Closing the room sends visitors away.
create or replace function public.update_study_room(
    input_display_name text default null,
    input_is_open boolean default null,
    input_show_task boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    new_name text := public._study_clean_text(input_display_name, 24);
begin
    if caller is null then raise exception 'authentication_required'; end if;
    if input_display_name is not null and new_name = '' then raise exception 'name_required'; end if;

    update public.study_rooms
    set display_name = coalesce(nullif(new_name, ''), display_name),
        is_open = coalesce(input_is_open, is_open),
        show_task = coalesce(input_show_task, show_task),
        updated_at = now()
    where owner_user_id = caller;
    if not found then raise exception 'room_not_found'; end if;

    if input_is_open = false then
        delete from public.study_room_visitors where owner_user_id = caller;
    end if;
    return public._study_room_owner_json(caller);
end;
$$;

-- A new link for the room. The old one stops working and everyone sitting is sent away.
create or replace function public.rotate_study_room_code()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    attempts integer := 0;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    if not exists (select 1 from public.study_rooms where owner_user_id = caller) then raise exception 'room_not_found'; end if;

    loop
        attempts := attempts + 1;
        if attempts > 10 then raise exception 'code_unavailable'; end if;
        begin
            update public.study_rooms set code = public._study_room_new_code(), updated_at = now() where owner_user_id = caller;
            exit;
        exception when unique_violation then
            null;
        end;
    end loop;

    delete from public.study_room_visitors where owner_user_id = caller;
    return public._study_room_owner_json(caller);
end;
$$;

-- Sends one visitor away. They can only come back with a new browser or after the link changes,
-- so rotate the link for anyone who should stay out.
create or replace function public.remove_study_room_visitor(input_visitor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    update public.study_room_visitors set removed = true, seen_at = now()
    where owner_user_id = caller and visitor_id = input_visitor_id;
    return public._study_room_owner_json(caller);
end;
$$;

-- The owner's phone or browser says "still studying" about every 30 seconds. A room with no
-- word for two minutes reads as not studying, so a closed tab never leaves a stuck "live".
-- Returns the room (with who is sitting), or {"has_room": false} when there is none.
create or replace function public.study_room_ping(input_task text, input_started_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    clean_task text := public._study_clean_text(input_task, 120);
begin
    if caller is null then raise exception 'authentication_required'; end if;
    if clean_task = '' or input_started_at is null
       or input_started_at > now() + interval '1 minute'
       or input_started_at < now() - interval '16 hours' then
        raise exception 'invalid_session';
    end if;

    update public.study_rooms
    set live_task = clean_task, live_started_at = least(input_started_at, now()), live_seen_at = now()
    where owner_user_id = caller;
    return public._study_room_owner_json(caller);
end;
$$;

-- The session is over. Visitors are cleared with it.
create or replace function public.study_room_end()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    update public.study_rooms
    set live_task = null, live_started_at = null, live_seen_at = null
    where owner_user_id = caller;
    delete from public.study_room_visitors where owner_user_id = caller;
    return public._study_room_owner_json(caller);
end;
$$;

-- Deletes the room, its link and its visitors.
create or replace function public.delete_my_study_room()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    delete from public.study_rooms where owner_user_id = caller;
end;
$$;

-- ---------------------------------------------------------------------------
-- Study room: anyone with the link
-- ---------------------------------------------------------------------------

-- What a visitor may see. A room that is closed, or a code that does not exist, both answer
-- {"found": false}, so the answer never says whether a code was ever real.
create or replace function public.study_room_view(input_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    r public.study_rooms;
    live boolean;
begin
    select * into r from public.study_rooms where code = upper(btrim(coalesce(input_code, ''))) and is_open;
    if not found then return jsonb_build_object('found', false); end if;
    live := r.live_started_at is not null and r.live_seen_at > now() - interval '2 minutes';
    return jsonb_build_object(
        'found', true,
        -- The server's clock, so a visitor's timer is right even if their own clock is not.
        'now', now(),
        'name', r.display_name,
        'studying', live,
        'task', case when live and r.show_task then r.live_task end,
        'started_at', case when live then r.live_started_at end,
        'sitting', coalesce((
            select jsonb_agg(v.name order by v.seen_at desc)
            from public.study_room_visitors v
            where v.owner_user_id = r.owner_user_id and not v.removed and v.seen_at > now() - interval '90 seconds'
        ), '[]'::jsonb)
    );
end;
$$;

-- "I'm sitting with you": a visitor's browser says so about every 30 seconds, with a first name
-- and an id it made itself. At most 12 people sit at once. Someone the owner removed is refused.
create or replace function public.study_room_sit(input_code text, input_visitor_id uuid, input_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    r public.study_rooms;
    existing public.study_room_visitors;
    clean_name text := public._study_clean_text(input_name, 24);
begin
    if input_visitor_id is null then raise exception 'visitor_required'; end if;
    if clean_name = '' then raise exception 'name_required'; end if;

    select * into r from public.study_rooms where code = upper(btrim(coalesce(input_code, ''))) and is_open;
    if not found then return jsonb_build_object('found', false); end if;

    delete from public.study_room_visitors where owner_user_id = r.owner_user_id and seen_at < now() - interval '1 day';

    select * into existing from public.study_room_visitors
    where owner_user_id = r.owner_user_id and visitor_id = input_visitor_id;
    if found and existing.removed then raise exception 'removed'; end if;
    if not found and (
        select count(*) from public.study_room_visitors
        where owner_user_id = r.owner_user_id and not removed and seen_at > now() - interval '90 seconds'
    ) >= 12 then
        raise exception 'room_full';
    end if;

    insert into public.study_room_visitors (owner_user_id, visitor_id, name)
    values (r.owner_user_id, input_visitor_id, clean_name)
    on conflict (owner_user_id, visitor_id) do update set name = excluded.name, seen_at = now();

    return public.study_room_view(input_code);
end;
$$;

-- ---------------------------------------------------------------------------
-- Who can call what
-- ---------------------------------------------------------------------------

revoke all on function public.sync_study_sessions(jsonb) from public, anon;
revoke all on function public.my_study_sessions(timestamptz) from public, anon;
revoke all on function public.delete_study_session(uuid) from public, anon;
revoke all on function public.delete_my_study_history() from public, anon;
revoke all on function public.my_study_room() from public, anon;
revoke all on function public.ensure_study_room() from public, anon;
revoke all on function public.update_study_room(text, boolean, boolean) from public, anon;
revoke all on function public.rotate_study_room_code() from public, anon;
revoke all on function public.remove_study_room_visitor(uuid) from public, anon;
revoke all on function public.study_room_ping(text, timestamptz) from public, anon;
revoke all on function public.study_room_end() from public, anon;
revoke all on function public.delete_my_study_room() from public, anon;
revoke all on function public.study_room_view(text) from public;
revoke all on function public.study_room_sit(text, uuid, text) from public;

grant execute on function public.sync_study_sessions(jsonb) to authenticated;
grant execute on function public.my_study_sessions(timestamptz) to authenticated;
grant execute on function public.delete_study_session(uuid) to authenticated;
grant execute on function public.delete_my_study_history() to authenticated;
grant execute on function public.my_study_room() to authenticated;
grant execute on function public.ensure_study_room() to authenticated;
grant execute on function public.update_study_room(text, boolean, boolean) to authenticated;
grant execute on function public.rotate_study_room_code() to authenticated;
grant execute on function public.remove_study_room_visitor(uuid) to authenticated;
grant execute on function public.study_room_ping(text, timestamptz) to authenticated;
grant execute on function public.study_room_end() to authenticated;
grant execute on function public.delete_my_study_room() to authenticated;
-- The only two a signed-out visitor can call.
grant execute on function public.study_room_view(text) to anon, authenticated;
grant execute on function public.study_room_sit(text, uuid, text) to anon, authenticated;
