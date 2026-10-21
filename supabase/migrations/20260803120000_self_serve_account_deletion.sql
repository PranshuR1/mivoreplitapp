-- Self-serve account deletion (Apple App Store guideline 5.1.1(v)).
-- Lets a signed-in user delete their own account without admin involvement.

-- admin_audit_log.actor_user_id had no ON DELETE behaviour, so any audit row
-- naming a user as the actor pinned that user's auth.users row in place. Self
-- deletion always writes such a row (the user is their own actor), which would
-- fail the subsequent delete with a foreign key violation. Preserve the audit
-- trail by nulling the actor instead; the deleted identity is kept in
-- before_value and reason.
do $$
begin
    if exists (
        select 1
        from pg_constraint
        where conname = 'admin_audit_log_actor_user_id_fkey'
          and conrelid = 'public.admin_audit_log'::regclass
    ) then
        alter table public.admin_audit_log
            drop constraint admin_audit_log_actor_user_id_fkey;
    end if;
end
$$;

alter table public.admin_audit_log
    add constraint admin_audit_log_actor_user_id_fkey
    foreign key (actor_user_id) references auth.users(id) on delete set null;

create or replace function public.delete_my_account(input_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    caller_id uuid := auth.uid();
    caller_email text;
    before_value jsonb;
begin
    if caller_id is null then
        raise exception 'authentication_required';
    end if;

    -- A super admin owns announcements and campaign rule versions through NOT NULL
    -- foreign keys that do not cascade, so deleting them would abort on a foreign
    -- key violation partway through. Fail fast with a message the app can explain.
    if public.is_super_admin(caller_id) then
        raise exception 'super_admin_self_delete_blocked';
    end if;

    select email into caller_email from auth.users where id = caller_id;

    select jsonb_build_object(
        'user_id', caller_id,
        'email', caller_email,
        'deleted_at', now()
    ) into before_value;

    insert into public.admin_audit_log (
        actor_user_id, action, target_user_id, target_type, target_id, reason, before_value
    )
    values (
        caller_id,
        'user_self_deleted',
        caller_id,
        'user',
        caller_id::text,
        coalesce(nullif(btrim(input_reason), ''), 'Self-serve deletion from Mivo Privacy Center'),
        before_value
    );

    -- Every user-owned table references auth.users(id) on delete cascade, so this
    -- removes the auth identity and all associated rows in one statement.
    delete from auth.users where id = caller_id;
end;
$$;

revoke all on function public.delete_my_account(text) from public;
grant execute on function public.delete_my_account(text) to authenticated;
