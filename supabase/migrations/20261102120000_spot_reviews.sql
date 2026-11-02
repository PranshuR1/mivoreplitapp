-- Mivo Spot reviews.
--
-- Only people who bought Spots can review them: the caller needs an order that has been mailed or
-- delivered (matched the same way my_spot_orders() matches orders to an account). One review per
-- account; writing again replaces it. Reviews go live straight away and Mivo can hide one.
--
-- usemivo.app/shop reads the published reviews through spot_reviews_public() (no sign-in) to show
-- them and to fill the page's Product rating data for search engines. Nothing in the table is
-- readable or writable directly.

create extension if not exists pgcrypto;

create table if not exists public.spot_reviews (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null unique references auth.users(id) on delete cascade,
    rating integer not null check (rating between 1 and 5),
    body text not null default '' check (char_length(body) <= 1000),
    display_name text not null check (char_length(display_name) between 1 and 40),
    status text not null default 'published' check (status in ('published', 'hidden')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists spot_reviews_published_idx on public.spot_reviews (created_at desc) where status = 'published';

alter table public.spot_reviews enable row level security;
revoke all on public.spot_reviews from anon, authenticated;

drop trigger if exists spot_reviews_touch on public.spot_reviews;
create trigger spot_reviews_touch
    before update on public.spot_reviews
    for each row execute function public.spot_orders_touch();

-- Whether this account has a Spot order that has reached the buyer. Same matching rule as
-- my_spot_orders(): orders placed while signed in, or paid with the email of a Google/Apple account.
create or replace function public.spot_review_eligible(caller uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.spot_orders o
        left join auth.users u on u.id = caller
        where o.status in ('mailed', 'delivered')
          and (
              o.user_id = caller
              or (
                  coalesce(u.raw_app_meta_data->>'provider', '') in ('google', 'apple')
                  and u.email is not null
                  and lower(o.email) = lower(u.email)
              )
          )
    );
$$;

revoke all on function public.spot_review_eligible(uuid) from public, anon, authenticated;

-- The caller's review and whether they may write one.
create or replace function public.my_spot_review()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    mine jsonb;
begin
    if caller is null then raise exception 'authentication_required'; end if;

    select jsonb_build_object(
        'rating', r.rating,
        'body', r.body,
        'display_name', r.display_name,
        'status', r.status,
        'updated_at', r.updated_at
    ) into mine
    from public.spot_reviews r
    where r.user_id = caller;

    return jsonb_build_object('eligible', public.spot_review_eligible(caller), 'review', mine);
end;
$$;

-- Write or replace the caller's review. A review Mivo hid stays hidden when it is edited.
create or replace function public.submit_spot_review(input_rating integer, input_body text, input_display_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    clean_body text := trim(coalesce(input_body, ''));
    clean_name text := trim(coalesce(input_display_name, ''));
begin
    if caller is null then raise exception 'authentication_required'; end if;
    if not public.spot_review_eligible(caller) then raise exception 'not_eligible'; end if;
    if input_rating is null or input_rating not between 1 and 5 then raise exception 'invalid_rating'; end if;
    if char_length(clean_name) not between 1 and 40 then raise exception 'invalid_name'; end if;
    if char_length(clean_body) > 1000 then raise exception 'invalid_body'; end if;

    insert into public.spot_reviews (user_id, rating, body, display_name)
    values (caller, input_rating, clean_body, clean_name)
    on conflict (user_id) do update
    set rating = excluded.rating,
        body = excluded.body,
        display_name = excluded.display_name;

    return public.my_spot_review();
end;
$$;

create or replace function public.delete_my_spot_review()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
begin
    if caller is null then raise exception 'authentication_required'; end if;
    delete from public.spot_reviews where user_id = caller;
    return found;
end;
$$;

-- What anyone can see: the count and average of published reviews, and the newest ones.
create or replace function public.spot_reviews_public(input_limit integer default 20)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'count', (select count(*) from public.spot_reviews where status = 'published'),
        'average', (select round(avg(rating)::numeric, 2) from public.spot_reviews where status = 'published'),
        'reviews', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', left(r.id::text, 8),
                'rating', r.rating,
                'body', r.body,
                'display_name', r.display_name,
                'created_at', r.created_at
            ) order by r.created_at desc)
            from (
                select * from public.spot_reviews
                where status = 'published'
                order by created_at desc
                limit least(greatest(coalesce(input_limit, 20), 1), 50)
            ) r
        ), '[]'::jsonb)
    );
$$;

-- Hide or re-publish a review. `input_review_code` is the 8-character id shown on the site.
create or replace function public.admin_set_spot_review_status(input_review_code text, input_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    wanted text := lower(trim(coalesce(input_review_code, '')));
    target uuid;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status not in ('published', 'hidden') then raise exception 'invalid_status'; end if;

    select r.id into target from public.spot_reviews r where left(r.id::text, 8) = wanted;
    if target is null then raise exception 'review_not_found'; end if;

    update public.spot_reviews set status = input_status where id = target;

    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, before_value, after_value)
    values (auth.uid(), 'spot_review_status', 'spot_review', wanted, null, jsonb_build_object('status', input_status));
end;
$$;

revoke all on function public.my_spot_review() from public, anon;
revoke all on function public.submit_spot_review(integer, text, text) from public, anon;
revoke all on function public.delete_my_spot_review() from public, anon;
revoke all on function public.admin_set_spot_review_status(text, text) from public, anon;
grant execute on function public.my_spot_review() to authenticated;
grant execute on function public.submit_spot_review(integer, text, text) to authenticated;
grant execute on function public.delete_my_spot_review() to authenticated;
grant execute on function public.admin_set_spot_review_status(text, text) to authenticated;

revoke all on function public.spot_reviews_public(integer) from public;
grant execute on function public.spot_reviews_public(integer) to anon, authenticated;
