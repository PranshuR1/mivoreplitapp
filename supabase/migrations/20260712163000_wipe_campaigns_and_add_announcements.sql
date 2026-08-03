delete from public.referral_campaigns;

create table if not exists public.announcements (
    id uuid primary key default gen_random_uuid(), title text not null check (char_length(title) between 1 and 80),
    body text not null check (char_length(body) between 1 and 1000),
    status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
    published_at timestamptz, expires_at timestamptz,
    created_by uuid not null references auth.users(id),
    created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.announcement_receipts (
    announcement_id uuid not null references public.announcements(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    seen_at timestamptz, dismissed_at timestamptz,
    primary key (announcement_id, user_id)
);
alter table public.announcements enable row level security;
alter table public.announcement_receipts enable row level security;
create policy "announcement_user_read" on public.announcements for select to authenticated using (
    public.is_super_admin() or (status = 'published' and published_at <= now() and (expires_at is null or expires_at > now())));
create policy "announcement_admin_manage" on public.announcements for all to authenticated
    using (public.is_super_admin()) with check (public.is_super_admin());
create policy "announcement_receipt_own" on public.announcement_receipts for all to authenticated
    using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.get_unseen_announcements() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
 return coalesce((select jsonb_agg(to_jsonb(a) order by a.published_at desc) from public.announcements a
  where a.status='published' and a.published_at<=now() and (a.expires_at is null or a.expires_at>now())
  and not exists (select 1 from public.announcement_receipts r where r.announcement_id=a.id and r.user_id=auth.uid() and r.seen_at is not null)), '[]'::jsonb);
end; $$;
grant execute on function public.get_unseen_announcements() to authenticated;
create or replace function public.mark_announcement_seen(input_announcement_id uuid, input_dismissed boolean default false)
returns void language plpgsql security definer set search_path=public as $$ begin
 insert into public.announcement_receipts(announcement_id,user_id,seen_at,dismissed_at)
 values(input_announcement_id,auth.uid(),now(),case when input_dismissed then now() else null end)
 on conflict(announcement_id,user_id) do update set seen_at=coalesce(public.announcement_receipts.seen_at,now()),
 dismissed_at=case when input_dismissed then now() else public.announcement_receipts.dismissed_at end;
end; $$;
grant execute on function public.mark_announcement_seen(uuid,boolean) to authenticated;
create or replace function public.admin_announcement_dashboard() returns jsonb language plpgsql stable security definer set search_path=public as $$ begin
 if not public.is_super_admin() then raise exception 'admin_required'; end if;
 return coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.announcements a),'[]'::jsonb);
end; $$;
grant execute on function public.admin_announcement_dashboard() to authenticated;
create or replace function public.admin_create_announcement(input_title text,input_body text,input_expires_at timestamptz default null,input_publish_now boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$ declare created public.announcements%rowtype; begin
 if not public.is_super_admin() then raise exception 'admin_required'; end if;
 insert into public.announcements(title,body,status,published_at,expires_at,created_by)
 values(trim(input_title),trim(input_body),case when input_publish_now then 'published' else 'draft' end,
 case when input_publish_now then now() else null end,input_expires_at,auth.uid()) returning * into created;
 insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,after_value)
 values(auth.uid(),case when input_publish_now then 'announcement_published' else 'announcement_created' end,'announcement',created.id::text,to_jsonb(created));
 return to_jsonb(created); end; $$;
grant execute on function public.admin_create_announcement(text,text,timestamptz,boolean) to authenticated;
create or replace function public.admin_set_announcement_status(input_announcement_id uuid,input_status text)
returns void language plpgsql security definer set search_path=public as $$ declare before_row jsonb; after_row jsonb; begin
 if not public.is_super_admin() then raise exception 'admin_required'; end if;
 if input_status not in('published','archived') then raise exception 'invalid_status'; end if;
 select to_jsonb(a) into before_row from public.announcements a where id=input_announcement_id;
 update public.announcements set status=input_status,published_at=case when input_status='published' then coalesce(published_at,now()) else published_at end,
 updated_at=now() where id=input_announcement_id;
 select to_jsonb(a) into after_row from public.announcements a where id=input_announcement_id;
 insert into public.admin_audit_log(actor_user_id,action,target_type,target_id,before_value,after_value)
 values(auth.uid(),'announcement_'||input_status,'announcement',input_announcement_id::text,before_row,after_row); end; $$;
grant execute on function public.admin_set_announcement_status(uuid,text) to authenticated;
