-- Where each Spot in an order is going, as the buyer picked on usemivo.app/shop (Desk, Bedside, Car...).
--
-- One entry per Spot, in order, using the place keys the stripe-spot-orders Edge Function knows;
-- "blank" means no pick. Empty when the buyer picked nothing. Staff read it through
-- admin_list_spot_orders(), which already returns every column; customers do not see it.

alter table public.spot_orders
    add column if not exists spot_picks text[] not null default '{}'
    check (cardinality(spot_picks) <= 20);
