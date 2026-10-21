-- Mivo Spots: track which codes have been written onto a physical tag.
--
-- Staff programming a batch of stickers one after another need the app to hand
-- out the next code that is not on a tag yet, and to remember it afterwards —
-- otherwise one code could end up on two stickers, and two stickers sharing a
-- code would let whoever scans first claim both.
--
-- programmed_at is set by staff when a code has been written and verified on a
-- tag. It plays no part in customers claiming a Spot.

alter table public.physical_spots add column if not exists programmed_at timestamptz;

-- The next code in a batch that has not been written to a tag, plus progress.
create or replace function public.admin_next_unprogrammed_physical_spot(input_batch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    next_id text;
    total_count integer;
    programmed_count integer;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    select count(*), count(*) filter (where programmed_at is not null)
    into total_count, programmed_count
    from public.physical_spots where batch_id = input_batch_id;

    select spot_id into next_id
    from public.physical_spots
    where batch_id = input_batch_id and programmed_at is null and status <> 'disabled'
    order by created_at, spot_id
    limit 1;

    return jsonb_build_object(
        'spot_id', next_id,
        'url', case when next_id is null then null else 'https://usemivo.app/s/' || next_id end,
        'programmed', programmed_count,
        'total', total_count
    );
end;
$$;

create or replace function public.admin_mark_physical_spot_programmed(
    input_spot_id text,
    input_programmed boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    wanted text := upper(trim(coalesce(input_spot_id, '')));
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    update public.physical_spots
    set programmed_at = case when input_programmed then coalesce(programmed_at, now()) else null end
    where spot_id = wanted;
    if not found then raise exception 'spot_not_found'; end if;
end;
$$;

-- Batches, lists and single-Spot lookups now report programming progress.
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
            'disabled_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.status = 'disabled'),
            'programmed_count', (select count(*) from public.physical_spots s where s.batch_id = b.id and s.programmed_at is not null)
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
                       b.label as batch_label, s.created_at, s.claimed_at, s.programmed_at,
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
               s.disabled_reason, s.programmed_at, p.email as owner_email
        from public.physical_spots s
        left join public.physical_spot_batches b on b.id = s.batch_id
        left join public.user_profiles p on p.user_id = s.owner_user_id
        where s.spot_id = upper(trim(coalesce(input_spot_id, '')))
    ) detail;
    if result is null then raise exception 'spot_not_found'; end if;
    return result;
end;
$$;

revoke all on function public.admin_next_unprogrammed_physical_spot(uuid) from public, anon;
revoke all on function public.admin_mark_physical_spot_programmed(text, boolean) from public, anon;
grant execute on function public.admin_next_unprogrammed_physical_spot(uuid) to authenticated;
grant execute on function public.admin_mark_physical_spot_programmed(text, boolean) to authenticated;
