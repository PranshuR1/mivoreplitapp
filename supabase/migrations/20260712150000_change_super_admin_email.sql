create or replace function public.bootstrap_mivo_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    insert into public.referral_profiles (user_id, referral_code)
    values (new.id, public.generate_mivo_referral_code())
    on conflict (user_id) do nothing;

    if lower(coalesce(new.email, '')) = 'pranshuraithatha0@gmail.com' then
        delete from public.app_admins where role = 'super_admin' and user_id <> new.id;
        insert into public.app_admins (user_id, email, role, updated_at)
        values (new.id, lower(new.email), 'super_admin', now())
        on conflict (user_id) do update
        set email = excluded.email, role = 'super_admin', updated_at = now();
    end if;
    return new;
end;
$$;

delete from public.app_admins
where role = 'super_admin'
  and user_id not in (
      select id from auth.users where lower(email) = 'pranshuraithatha0@gmail.com'
  );

insert into public.app_admins (user_id, email, role)
select id, lower(email), 'super_admin'
from auth.users
where lower(email) = 'pranshuraithatha0@gmail.com'
on conflict (user_id) do update
set email = excluded.email, role = excluded.role, updated_at = now();
