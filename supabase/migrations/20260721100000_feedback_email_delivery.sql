create table if not exists public.feedback_email_deliveries (
    feedback_id uuid primary key references public.feedback_items(id) on delete cascade,
    recipient text not null default 'info.mivoapp@gmail.com',
    status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
    provider_message_id text,
    error_message text,
    attempt_count integer not null default 0,
    last_attempted_at timestamptz,
    sent_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.feedback_email_deliveries enable row level security;

-- Delivery state is server-only. Users continue to access their submission through
-- feedback_items, while the Edge Function uses the service role for delivery.
revoke all on table public.feedback_email_deliveries from anon, authenticated;
