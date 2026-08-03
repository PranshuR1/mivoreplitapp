create table if not exists public.weekly_experiments (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    type text not null check (type in ('protected_window','reduce_extensions','stronger_friction')),
    status text not null check (status in ('proposed','active','completed','declined')),
    title text not null,
    reason text not null,
    primary_metric text not null,
    rule jsonb not null default '{}'::jsonb,
    baseline_metrics jsonb not null default '{}'::jsonb,
    result_metrics jsonb,
    starts_at timestamptz,
    ends_at timestamptz,
    outcome text check (outcome is null or outcome in ('helped','no_clear_change','made_things_worse')),
    final_decision text check (final_decision is null or final_decision in ('keep','adjust','stop')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index if not exists one_active_weekly_experiment_per_user
    on public.weekly_experiments(user_id) where status = 'active';
create index if not exists weekly_experiments_user_created_idx
    on public.weekly_experiments(user_id, created_at desc);

alter table public.weekly_experiments enable row level security;
create policy "weekly_experiment_own_read" on public.weekly_experiments
    for select to authenticated using (user_id = auth.uid());
create policy "weekly_experiment_own_insert" on public.weekly_experiments
    for insert to authenticated with check (user_id = auth.uid());
create policy "weekly_experiment_own_update" on public.weekly_experiments
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "weekly_experiment_admin_aggregate" on public.weekly_experiments
    for select to authenticated using (public.is_app_admin());

create or replace function public.admin_weekly_experiment_summary()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
    if not public.is_app_admin() then raise exception 'admin_required'; end if;
    return jsonb_build_object(
        'proposed', count(*) filter (where status='proposed'),
        'active', count(*) filter (where status='active'),
        'completed', count(*) filter (where status='completed'),
        'helped', count(*) filter (where outcome='helped'),
        'inconclusive', count(*) filter (where outcome='no_clear_change'),
        'worsened', count(*) filter (where outcome='made_things_worse')
    ) from public.weekly_experiments;
end; $$;
grant execute on function public.admin_weekly_experiment_summary() to authenticated;
