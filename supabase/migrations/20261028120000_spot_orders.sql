-- Mivo Spots orders.
--
-- Spots are sold through Stripe Payment Links. The `stripe-spot-orders` Edge Function receives
-- Stripe's webhook and records each paid checkout here, so a customer can see their orders and
-- their status on usemivo.app/account, and Mivo can mark them mailed (with tracking).
--
-- Nothing in this table is readable or writable directly. Customers read their own orders through
-- my_spot_orders(); Mivo staff use the two admin functions below (or the SQL editor).

create extension if not exists pgcrypto;

create table if not exists public.spot_orders (
    id uuid primary key default gen_random_uuid(),
    stripe_session_id text not null unique,
    stripe_payment_intent text unique,
    -- Set when the buyer was signed in on usemivo.app: the Buy button adds their id as client_reference_id.
    user_id uuid references auth.users(id) on delete set null,
    email text,
    customer_name text,
    item text not null default 'other' check (item in ('single', 'pack', 'other')),
    spots integer not null default 1 check (spots > 0),
    -- Cents.
    amount_subtotal integer not null check (amount_subtotal >= 0),
    amount_shipping integer not null default 0 check (amount_shipping >= 0),
    amount_total integer not null check (amount_total >= 0),
    currency text not null default 'usd',
    ship_name text,
    ship_address text,
    status text not null default 'paid' check (status in ('paid', 'mailed', 'delivered', 'refunded', 'cancelled')),
    mailed_at timestamptz,
    tracking_url text check (tracking_url is null or tracking_url ~ '^https://'),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists spot_orders_user_idx on public.spot_orders (user_id) where user_id is not null;
create index if not exists spot_orders_email_idx on public.spot_orders (lower(email));
create index if not exists spot_orders_created_idx on public.spot_orders (created_at desc);

alter table public.spot_orders enable row level security;
revoke all on public.spot_orders from anon, authenticated;

create or replace function public.spot_orders_touch()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists spot_orders_touch on public.spot_orders;
create trigger spot_orders_touch
    before update on public.spot_orders
    for each row execute function public.spot_orders_touch();

-- The caller's own orders: the ones bought while signed in to their account, plus the ones paid
-- with the same email when the account was created through Google or Apple (those providers
-- verify the address). An email/password account never matches on email alone, because that
-- address is not verified, so nobody can read someone else's order by registering with their email.
create or replace function public.my_spot_orders()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    caller uuid := auth.uid();
    caller_email text;
    email_verified boolean;
begin
    if caller is null then raise exception 'authentication_required'; end if;

    select lower(u.email), coalesce(u.raw_app_meta_data->>'provider', '') in ('google', 'apple')
    into caller_email, email_verified
    from auth.users u
    where u.id = caller;

    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'order_id', upper(left(o.id::text, 8)),
            'item', o.item,
            'spots', o.spots,
            'amount_subtotal', o.amount_subtotal,
            'amount_shipping', o.amount_shipping,
            'amount_total', o.amount_total,
            'currency', o.currency,
            'status', o.status,
            'mailed_at', o.mailed_at,
            'tracking_url', o.tracking_url,
            'ship_name', o.ship_name,
            'ship_address', o.ship_address,
            'created_at', o.created_at
        ) order by o.created_at desc)
        from public.spot_orders o
        where o.user_id = caller
           or (coalesce(email_verified, false) and caller_email is not null and lower(o.email) = caller_email)
    ), '[]'::jsonb);
end;
$$;

revoke all on function public.my_spot_orders() from public, anon;
grant execute on function public.my_spot_orders() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin / fulfilment
-- ---------------------------------------------------------------------------

create or replace function public.admin_list_spot_orders(input_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    return coalesce((
        select jsonb_agg(to_jsonb(o) - 'stripe_session_id' - 'stripe_payment_intent'
            || jsonb_build_object('order_code', upper(left(o.id::text, 8)))
            order by o.created_at desc)
        from (select * from public.spot_orders order by created_at desc limit least(greatest(coalesce(input_limit, 50), 1), 200)) o
    ), '[]'::jsonb);
end;
$$;

-- Mark an order mailed (with an optional tracking link), delivered, cancelled or refunded.
-- `input_order_code` is the 8-character order number the customer sees.
create or replace function public.admin_update_spot_order(
    input_order_code text,
    input_status text,
    input_tracking_url text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    wanted text := upper(trim(coalesce(input_order_code, '')));
    target uuid;
    before_row jsonb;
    after_row jsonb;
begin
    if not public.is_super_admin() then raise exception 'admin_required'; end if;
    if input_status not in ('paid', 'mailed', 'delivered', 'refunded', 'cancelled') then
        raise exception 'invalid_status';
    end if;

    select o.id, to_jsonb(o) into target, before_row
    from public.spot_orders o
    where upper(left(o.id::text, 8)) = wanted;
    if target is null then raise exception 'order_not_found'; end if;

    update public.spot_orders
    set status = input_status,
        mailed_at = case
            when input_status in ('mailed', 'delivered') then coalesce(mailed_at, now())
            else mailed_at
        end,
        tracking_url = coalesce(nullif(trim(input_tracking_url), ''), tracking_url)
    where id = target;

    select to_jsonb(o) into after_row from public.spot_orders o where o.id = target;
    insert into public.admin_audit_log (actor_user_id, action, target_type, target_id, before_value, after_value)
    values (auth.uid(), 'spot_order_updated', 'spot_order', wanted, before_row - 'email', after_row - 'email');
end;
$$;

revoke all on function public.admin_list_spot_orders(integer) from public, anon;
revoke all on function public.admin_update_spot_order(text, text, text) from public, anon;
grant execute on function public.admin_list_spot_orders(integer) to authenticated;
grant execute on function public.admin_update_spot_order(text, text, text) to authenticated;
