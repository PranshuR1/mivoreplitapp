-- Mivo Clear: server-controlled focused social rules and privacy-minimal usage records.

insert into public.feature_flags(key, enabled, rollout_percentage, founder_preview) values
    ('mivo_clear', true, 100, true),
    ('mivo_clear_instagram', true, 100, true),
    ('mivo_clear_tiktok', true, 100, true),
    ('mivo_clear_youtube', true, 100, true)
on conflict (key) do update set
    enabled = excluded.enabled,
    rollout_percentage = excluded.rollout_percentage;

create table if not exists public.mivo_clear_platform_rules (
    platform text primary key check (platform in ('instagram', 'tiktok', 'youtube')),
    enabled boolean not null default false,
    version integer not null check (version > 0),
    home_url text not null check (home_url like 'https://%'),
    allowed_hosts text[] not null,
    blocked_path_prefixes text[] not null default '{}',
    hidden_selectors text[] not null default '{}',
    quick_actions jsonb not null default '[]'::jsonb,
    updated_by uuid references auth.users(id) on delete set null,
    updated_at timestamptz not null default now()
);

insert into public.mivo_clear_platform_rules
    (platform, enabled, version, home_url, allowed_hosts, blocked_path_prefixes, hidden_selectors, quick_actions)
values
    ('instagram', true, 2, 'https://www.instagram.com/direct/inbox/',
     array['instagram.com','facebook.com'], array['/reels','/explore','/shopping','/live'],
     array['a[href^=''/reels'']','a[href^=''/explore'']','a[href*=''/shopping'']','a[href*=''/live'']','[aria-label=''Reels'']','[aria-label=''Explore'']','[data-testid=''clips-tab'']','[data-testid=''explore-tab'']','article:has(a[href*=''/reels/''])','div[role=''button'']:has([aria-label=''Live''])'],
     '[{"id":"messages","title":"Messages","icon":"message.fill","path":"/direct/inbox/"},{"id":"following","title":"Following","icon":"person.2.fill","path":"/"},{"id":"search","title":"Search","icon":"magnifyingglass","path":"/explore/search/"},{"id":"post","title":"Post","icon":"plus.square.fill","path":"/create/style/"}]'::jsonb),
    ('tiktok', true, 2, 'https://www.tiktok.com/messages',
     array['tiktok.com'], array['/foryou','/following','/live','/shop'],
     array['a[href=''/foryou'']','a[href=''/following'']','a[href^=''/live'']','a[href^=''/shop'']','[data-e2e=''recommend-list-item-container'']','[data-e2e=''live-nav-item'']','[data-e2e=''shop-entrance'']','[data-e2e=''recommend-list'']','[data-e2e=''following-feed'']'],
     '[{"id":"messages","title":"Messages","icon":"message.fill","path":"/messages"},{"id":"search","title":"Search","icon":"magnifyingglass","path":"/search"},{"id":"profile","title":"Profile","icon":"person.crop.circle","path":"/profile"},{"id":"upload","title":"Upload","icon":"square.and.arrow.up","path":"/upload"}]'::jsonb),
    ('youtube', true, 2, 'https://www.youtube.com/feed/subscriptions',
     array['youtube.com','youtu.be','googlevideo.com'], array['/','/shorts','/feed/trending','/gaming','/live','/shopping'],
     array['a[href^=''/shorts'']','ytd-reel-shelf-renderer','ytd-rich-section-renderer:has(a[href^=''/shorts''])','ytd-guide-entry-renderer:has(a[href^=''/shorts''])','ytm-reel-shelf-renderer','ytm-pivot-bar-item-renderer:has(a[href^=''/shorts''])','ytd-watch-next-secondary-results-renderer'],
     '[{"id":"subscriptions","title":"Subscriptions","icon":"rectangle.stack.fill","path":"/feed/subscriptions"},{"id":"search","title":"Search","icon":"magnifyingglass","path":"/results"},{"id":"playlists","title":"Playlists","icon":"list.bullet.rectangle","path":"/feed/playlists"}]'::jsonb)
on conflict (platform) do update set
    enabled = excluded.enabled,
    version = excluded.version,
    home_url = excluded.home_url,
    allowed_hosts = excluded.allowed_hosts,
    blocked_path_prefixes = excluded.blocked_path_prefixes,
    hidden_selectors = excluded.hidden_selectors,
    quick_actions = excluded.quick_actions,
    updated_at = now();

create table if not exists public.mivo_clear_sessions (
    user_id uuid not null references auth.users(id) on delete cascade,
    id text not null,
    platform text not null check (platform in ('instagram', 'tiktok', 'youtube')),
    entry_point text not null check (entry_point in ('home', 'settings', 'shield', 'deep_link')),
    started_at timestamptz not null,
    ended_at timestamptz not null,
    active_seconds integer not null check (active_seconds between 0 and 86400),
    blocked_route_count integer not null default 0 check (blocked_route_count between 0 and 10000),
    filter_version integer not null check (filter_version > 0),
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);
create index if not exists mivo_clear_sessions_user_started_idx
    on public.mivo_clear_sessions(user_id, started_at desc);

alter table public.mivo_clear_platform_rules enable row level security;
alter table public.mivo_clear_sessions enable row level security;

drop policy if exists "mivo_clear_rules_authenticated_read" on public.mivo_clear_platform_rules;
create policy "mivo_clear_rules_authenticated_read" on public.mivo_clear_platform_rules
    for select to authenticated using (true);
drop policy if exists "mivo_clear_rules_founder_write" on public.mivo_clear_platform_rules;
create policy "mivo_clear_rules_founder_write" on public.mivo_clear_platform_rules
    for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
drop policy if exists "mivo_clear_sessions_own" on public.mivo_clear_sessions;
create policy "mivo_clear_sessions_own" on public.mivo_clear_sessions
    for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.get_mivo_clear_configuration()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    return coalesce((
        select jsonb_agg(jsonb_build_object(
            'platform', r.platform,
            'enabled', r.enabled,
            'version', r.version,
            'home_url', r.home_url,
            'allowed_hosts', r.allowed_hosts,
            'blocked_path_prefixes', r.blocked_path_prefixes,
            'hidden_selectors', r.hidden_selectors,
            'quick_actions', r.quick_actions,
            'updated_at', r.updated_at
        ) order by r.platform)
        from public.mivo_clear_platform_rules r
    ), '[]'::jsonb);
end; $$;
grant execute on function public.get_mivo_clear_configuration() to authenticated;

create or replace function public.record_mivo_clear_session(input_session jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
    p_platform text := input_session->>'platform';
    p_entry text := coalesce(input_session->>'entryPoint', input_session->>'entry_point');
    p_started text := coalesce(input_session->>'startedAt', input_session->>'started_at');
    p_ended text := coalesce(input_session->>'endedAt', input_session->>'ended_at');
    p_seconds integer := coalesce((input_session->>'activeSeconds')::integer, (input_session->>'active_seconds')::integer, 0);
    p_blocked integer := coalesce((input_session->>'blockedRouteCount')::integer, (input_session->>'blocked_route_count')::integer, 0);
    p_version integer := coalesce((input_session->>'filterVersion')::integer, (input_session->>'filter_version')::integer, 0);
begin
    if auth.uid() is null then raise exception 'authentication_required'; end if;
    if p_platform not in ('instagram','tiktok','youtube') or p_entry not in ('home','settings','shield','deep_link') then
        raise exception 'invalid_mivo_clear_session';
    end if;
    insert into public.mivo_clear_sessions
        (user_id,id,platform,entry_point,started_at,ended_at,active_seconds,blocked_route_count,filter_version)
    values
        (auth.uid(), input_session->>'id', p_platform, p_entry, p_started::timestamptz, p_ended::timestamptz,
         least(greatest(p_seconds,0),86400), least(greatest(p_blocked,0),10000), p_version)
    on conflict (user_id,id) do update set
        ended_at=excluded.ended_at, active_seconds=excluded.active_seconds,
        blocked_route_count=excluded.blocked_route_count, filter_version=excluded.filter_version;
end; $$;
grant execute on function public.record_mivo_clear_session(jsonb) to authenticated;

create or replace function public.admin_update_mivo_clear_rule(input_rule jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare before_row jsonb; saved public.mivo_clear_platform_rules%rowtype;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    select to_jsonb(r) into before_row from public.mivo_clear_platform_rules r where platform=input_rule->>'platform';
    update public.mivo_clear_platform_rules set
        enabled=(input_rule->>'enabled')::boolean,
        version=(input_rule->>'version')::integer,
        home_url=input_rule->>'homeUrl',
        allowed_hosts=array(select jsonb_array_elements_text(input_rule->'allowedHosts')),
        blocked_path_prefixes=array(select jsonb_array_elements_text(input_rule->'blockedPathPrefixes')),
        hidden_selectors=array(select jsonb_array_elements_text(input_rule->'hiddenSelectors')),
        quick_actions=input_rule->'quickActions', updated_by=auth.uid(), updated_at=now()
    where platform=input_rule->>'platform' returning * into saved;
    if saved.platform is null then raise exception 'unknown_platform'; end if;
    insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,before_value,after_value)
    values(auth.uid(),'mivo_clear_rule_updated','mivo_clear_rule',saved.platform,before_row,to_jsonb(saved));
    return to_jsonb(saved);
end; $$;
grant execute on function public.admin_update_mivo_clear_rule(jsonb) to authenticated;
