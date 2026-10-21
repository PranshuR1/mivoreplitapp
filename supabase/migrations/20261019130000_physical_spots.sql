-- Mivo Spots: official physical Spots.
--
-- A physical Spot is an NFC tag Mivo programmed before sale. The tag carries
-- exactly one thing: https://usemivo.app/s/<spot_id>. This table is the
-- registry behind that ID — who (if anyone) has claimed it, and whether Mivo
-- has switched it off. Everything about what a Spot *does* (name, apps, mode,
-- duration) stays in the app and is never written to the tag or stored here.
--
-- Nothing in this table is readable or writable directly. Every access goes
-- through the security-definer functions below, so a signed-in user can only
-- ask "what is the state of this ID for me" and "claim it" — never list IDs
-- or see who owns one.

create extension if not exists pgcrypto;

create table if not exists public.physical_spot_batches (
    id uuid primary key default gen_random_uuid(),
    label text not null check (char_length(label) between 1 and 80),
    spot_count integer not null check (spot_count > 0),
    created_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now()
);

create table if not exists public.physical_spots (
    -- Random, not sequential, and not derived from any database counter.
    spot_id text primary key check (spot_id ~ '^[A-Z0-9]{6,12}$'),
    status text not null default 'unclaimed' check (status in ('unclaimed', 'claimed', 'disabled')),
    owner_user_id uuid references auth.users(id) on delete set null,
    batch_id uuid references public.physical_spot_batches(id) on delete set null,
    claimed_at timestamptz,
    created_at timestamptz not null default now(),
    disabled_at timestamptz,
    disabled_reason text,
    updated_at timestamptz not null default now()
);

create index if not exists physical_spots_owner_idx on public.physical_spots (owner_user_id) where owner_user_id is not null;
create index if not exists physical_spots_batch_idx on public.physical_spots (batch_id, created_at);
create index if not exists physical_spots_status_idx on public.physical_spots (status);

-- Failed lookups, kept briefly so guessing IDs can be throttled.
create table if not exists public.physical_spot_failed_lookups (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    looked_up_at timestamptz not null default now()
);
create index if not exists physical_spot_failed_lookups_user_idx
    on public.physical_spot_failed_lookups (user_id, looked_up_at desc);

alter table public.physical_spot_batches enable row level security;
alter table public.physical_spots enable row level security;
alter table public.physical_spot_failed_lookups enable row level security;
revoke all on public.physical_spot_batches from anon, authenticated;
revoke all on public.physical_spots from anon, authenticated;
revoke all on public.physical_spot_failed_lookups from anon, authenticated;

-- If an owner's account is deleted the Spot becomes claimable again, so the
-- tag a customer paid for is not stranded.
create or replace function public.physical_spots_before_update()
returns trigger
language plpgsql
as $$
begin
    if old.owner_user_id is not null and new.owner_user_id is null then
        new.claimed_at := null;
        if new.status = 'claimed' then new.status := 'unclaimed'; end if;
    end if;
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists physical_spots_before_update on public.physical_spots;
create trigger physical_spots_before_update
    before update on public.physical_spots
    for each row execute function public.physical_spots_before_update();

-- ---------------------------------------------------------------------------
-- ID generation (manufacturing)
-- ---------------------------------------------------------------------------

-- 31 characters, no I/L/O/0/1, so an ID read aloud or printed on a box is
-- unambiguous. Rejection sampling keeps every character equally likely.
create or replace function public._physical_spot_new_id(id_length integer default 8)
returns text
language plpgsql
volatile
set search_path = public, extensions
as $$
declare
    alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    result text := '';
    random_bytes bytea;
    idx integer;
    byte_value integer;
begin
    if id_length < 6 or id_length > 12 then raise exception 'invalid_id_length'; end if;
    while char_length(result) < id_length loop
        random_bytes := extensions.gen_random_bytes(32);
        for idx in 0..31 loop
            byte_value := get_byte(random_bytes, idx);
            if byte_value < 248 then -- 248 = 8 * 31
                result := result || substr(alphabet, (byte_value % 31) + 1, 1);
                exit when char_length(result) = id_length;
            end if;
        end loop;
    end loop;
    return result;
end;
$$;

-- The generator itself. Not callable from the app: run it from the Supabase
-- SQL editor (as the project owner), or go through admin_generate_physical_spots.
--   select * from public._generate_physical_spots(100, 'Batch 1');
create or replace function public._generate_physical_spots(
    input_count integer,
    input_label text,
    input_actor uuid default null,
    input_id_length integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    new_batch_id uuid;
    created_ids text[] := '{}';
    candidate text;
    attempts integer := 0;
    result jsonb;
begin
    if input_count is null or input_count < 1 or input_count > 5000 then raise exception 'invalid_count'; end if;
    if input_label is null or char_length(trim(input_label)) = 0 then raise exception 'label_required'; end if;

    insert into public.physical_spot_batches (label, spot_count, created_by)
    values (left(trim(input_label), 80), input_count, input_actor)
    returning id into new_batch_id;

    while coalesce(array_length(created_ids, 1), 0) < input_count loop
        attempts := attempts + 1;
        if attempts > input_count * 20 then raise exception 'id_space_exhausted'; end if;
        candidate := public._physical_spot_new_id(input_id_length);
        insert into public.physical_spots (spot_id, batch_id)
        values (candidate, new_batch_id)
        on conflict (spot_id) do nothing;
        if found then created_ids := created_ids || candidate; end if;
    end loop;

    select jsonb_build_object(
        'batch_id', new_batch_id,
        'label', left(trim(input_label), 80),
        'spots', coalesce(jsonb_agg(jsonb_build_object(
            'spot_id', s.spot_id,
            'url', 'https://usemivo.app/s/' || s.spot_id,
            'status', s.status,
            'created_at', s.created_at
        ) order by s.created_at, s.spot_id), '[]'::jsonb)
    ) into result
    from public.physical_spots s
    where s.batch_id = new_batch_id;

    return result;
end;
$$;

revoke all on function public._physical_spot_new_id(integer) from public, anon, authenticated;
revoke all on function public._generate_physical_spots(integer, text, uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Customer-facing
-- ---------------------------------------------------------------------------

-- Throttle guessing: too many unknown IDs in a short window stops further lookups.
create or replace function public._physical_spot_check_rate(caller uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if (select count(*) from public.physical_spot_failed_lookups
        where user_id = caller and looked_up_at > now() - interval '15 minutes') >= 15 then
        raise exception 'rate_limited';
    end if;
end;
$$;

create or replace function public._physical_spot_note_failure(caller uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    delete from public.physical_spot_failed_lookups where looked_up_at < now() - interval '1 day';
    insert into public.physical_spot_failed_lookups (user_id) values (caller);
end;
$$;

revoke all on function public._physical_spot_check_rate(uuid) from public, anon, authenticated;
revoke all on function public._physical_spot_note_failure(uuid) from public, anon, authenticated;

-- What is this ID to me? Never says who owns a Spot someone else has claimed.
--   invalid   no such ID
--   unclaimed anyone signed in may claim it
--   yours     already claimed by the caller (a new phone, or data cleared)
--   taken     claimed by someone else
--   disabled  switched off by Mivo
create or replace function public.resolve_physical_spot(input_spot_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    found_spot public.physical_spots;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    perform public._physical_spot_check_rate(caller);

    select * into found_spot from public.physical_spots where spot_id = wanted;
    if not found then
        perform public._physical_spot_note_failure(caller);
        return jsonb_build_object('state', 'invalid');
    end if;
    if found_spot.status = 'disabled' then return jsonb_build_object('state', 'disabled'); end if;
    if found_spot.owner_user_id is null then return jsonb_build_object('state', 'unclaimed'); end if;
    if found_spot.owner_user_id = caller then
        return jsonb_build_object('state', 'yours', 'claimed_at', found_spot.claimed_at);
    end if;
    return jsonb_build_object('state', 'taken');
end;
$$;

-- Atomic: of two people claiming the same unclaimed Spot, exactly one wins.
-- Claiming a Spot you already own succeeds again (a retry after a dropped
-- connection is not an error).
create or replace function public.claim_physical_spot(input_spot_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    claimed_spot public.physical_spots;
    existing public.physical_spots;
begin
    if caller is null then raise exception 'authentication_required'; end if;
    perform public._physical_spot_check_rate(caller);

    update public.physical_spots
    set owner_user_id = caller, status = 'claimed', claimed_at = now()
    where spot_id = wanted and status = 'unclaimed' and owner_user_id is null
    returning * into claimed_spot;
    if found then
        return jsonb_build_object('state', 'claimed', 'owner_user_id', caller, 'claimed_at', claimed_spot.claimed_at);
    end if;

    select * into existing from public.physical_spots where spot_id = wanted;
    if not found then
        perform public._physical_spot_note_failure(caller);
        return jsonb_build_object('state', 'invalid');
    end if;
    if existing.status = 'disabled' then return jsonb_build_object('state', 'disabled'); end if;
    if existing.owner_user_id = caller then
        return jsonb_build_object('state', 'claimed', 'owner_user_id', caller, 'claimed_at', existing.claimed_at);
    end if;
    return jsonb_build_object('state', 'taken');
end;
$$;

-- Lets an owner hand a Spot on (gift, resale) or start over. No-op for anyone else.
create or replace function public.release_physical_spot(input_spot_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    update public.physical_spots
    set owner_user_id = null,
        claimed_at = null,
        status = case when status = 'disabled' then 'disabled' else 'unclaimed' end
    where spot_id = upper(trim(coalesce(input_spot_id, ''))) and owner_user_id = caller;
end;
$$;

-- The caller's own Spots, so a phone can notice a Spot that was disabled,
-- released or moved on another device.
create or replace function public.my_physical_spots()
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
            'spot_id', s.spot_id, 'status', s.status, 'claimed_at', s.claimed_at
        ) order by s.claimed_at)
        from public.physical_spots s
        where s.owner_user_id = caller
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.resolve_physical_spot(text) from public, anon;
revoke all on function public.claim_physical_spot(text) from public, anon;
revoke all on function public.release_physical_spot(text) from public, anon;
revoke all on function public.my_physical_spots() from public, anon;
grant execute on function public.resolve_physical_spot(text) to authenticated;
grant execute on function public.claim_physical_spot(text) to authenticated;
grant execute on function public.release_physical_spot(text) to authenticated;
grant execute on function public.my_physical_spots() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin / manufacturing
-- ---------------------------------------------------------------------------

create or replace function public.admin_generate_physical_spots(input_count integer, input_label text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    result jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    result := public._generate_physical_spots(input_count, input_label, auth.uid());
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, after_value)
    values (auth.uid(), 'physical_spots_generated', 'physical_spot_batch', result->>'batch_id',
            jsonb_build_object('label', result->>'label', 'count', input_count));
    return result;
end;
$$;

create or replace function public.admin_physical_spot_batches()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'id', b.id, 'label', b.label, 'spot_count', b.spot_count, 'created_at', b.created_at,
            'claimed_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.owner_user_id is not null),
            'disabled_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.status = 'disabled')
        ) order by b.created_at desc)
        from public.physical_spot_batches b
    ), '[]'::jsonb);
end;
$$;

create or replace function public.admin_list_physical_spots(
    input_batch_id uuid default null,
    input_status text default null,
    input_limit integer default 200,
    input_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    page_size integer := least(greatest(coalesce(input_limit, 200), 1), 1000);
    page_offset integer := greatest(coalesce(input_offset, 0), 0);
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status is not null and input_status not in ('unclaimed', 'claimed', 'disabled') then
        raise exception 'invalid_status';
    end if;
    return jsonb_build_object(
        'total', (select count(*) from public.physical_spots s
                  where (input_batch_id is null or s.batch_id = input_batch_id)
                    and (input_status is null or s.status = input_status)),
        'spots', coalesce((
            select jsonb_agg(row_to_json(page)::jsonb order by page.created_at, page.spot_id)
            from (
                select s.spot_id, 'https://usemivo.app/s/' || s.spot_id as url, s.status,
                       b.label as batch_label, s.created_at, s.claimed_at,
                       p.email as owner_email
                from public.physical_spots s
                left join public.physical_spot_batches b on b.id = s.batch_id
                left join public.user_profiles p on p.user_id = s.owner_user_id
                where (input_batch_id is null or s.batch_id = input_batch_id)
                  and (input_status is null or s.status = input_status)
                order by s.created_at, s.spot_id
                limit page_size offset page_offset
            ) page
        ), '[]'::jsonb)
    );
end;
$$;

create or replace function public.admin_physical_spot_status(input_spot_id text)
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
    select row_to_json(detail)::jsonb into result
    from (
        select s.spot_id, 'https://usemivo.app/s/' || s.spot_id as url, s.status,
               b.label as batch_label, s.created_at, s.claimed_at, s.disabled_at,
               s.disabled_reason, p.email as owner_email
        from public.physical_spots s
        left join public.physical_spot_batches b on b.id = s.batch_id
        left join public.user_profiles p on p.user_id = s.owner_user_id
        where s.spot_id = upper(trim(coalesce(input_spot_id, '')))
    ) detail;
    if result is null then raise exception 'spot_not_found'; end if;
    return result;
end;
$$;

-- Disabling keeps the owner, so enabling again restores exactly what it was.
create or replace function public.admin_set_physical_spot_disabled(
    input_spot_id text,
    input_disabled boolean,
    input_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    wanted text := upper(trim(coalesce(input_spot_id, '')));
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select to_jsonb(s) into before_row from public.physical_spots s where spot_id = wanted;
    if before_row is null then raise exception 'spot_not_found'; end if;

    update public.physical_spots
    set status = case
            when input_disabled then 'disabled'
            when owner_user_id is null then 'unclaimed'
            else 'claimed'
        end,
        disabled_at = case when input_disabled then now() else null end,
        disabled_reason = case when input_disabled then left(input_reason, 200) else null end
    where spot_id = wanted;

    select to_jsonb(s) into after_row from public.physical_spots s where spot_id = wanted;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, reason, before_value, after_value)
    values (auth.uid(),
            case when input_disabled then 'physical_spot_disabled' else 'physical_spot_enabled' end,
            'physical_spot', wanted, input_reason, before_row, after_row);
end;
$$;

revoke all on function public.admin_generate_physical_spots(integer, text) from public, anon;
revoke all on function public.admin_physical_spot_batches() from public, anon;
revoke all on function public.admin_list_physical_spots(uuid, text, integer, integer) from public, anon;
revoke all on function public.admin_physical_spot_status(text) from public, anon;
revoke all on function public.admin_set_physical_spot_disabled(text, boolean, text) from public, anon;
grant execute on function public.admin_generate_physical_spots(integer, text) to authenticated;
grant execute on function public.admin_physical_spot_batches() to authenticated;
grant execute on function public.admin_list_physical_spots(uuid, text, integer, integer) to authenticated;
grant execute on function public.admin_physical_spot_status(text) to authenticated;
grant execute on function public.admin_set_physical_spot_disabled(text, boolean, text) to authenticated;
