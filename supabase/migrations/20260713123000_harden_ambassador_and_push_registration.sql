create or replace function public.admin_set_ambassador_names(
    input_user_id uuid,
    input_normalized_names text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    selected_name text;
    representative_name text;
    conflicting_user uuid;
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if not exists (
        select 1 from public.user_profiles
        where user_id = input_user_id and account_role = 'ambassador'
    ) then raise exception 'ambassador_role_required'; end if;

    update public.ambassador_name_assignments
    set active = false, updated_at = now()
    where ambassador_user_id = input_user_id
      and not (normalized_name = any(coalesce(input_normalized_names, array[]::text[])));

    foreach selected_name in array coalesce(input_normalized_names, array[]::text[])
    loop
        selected_name := public.normalize_ambassador_name(selected_name);
        if selected_name = '' then continue; end if;

        conflicting_user := null;
        select ambassador_user_id into conflicting_user
        from public.ambassador_name_assignments
        where normalized_name = selected_name and active and ambassador_user_id <> input_user_id;
        if conflicting_user is not null then raise exception 'ambassador_name_already_assigned'; end if;

        select min(trim(referral_ambassador_name)) into representative_name
        from public.onboarding_profiles
        where referral_source = 'ambassador'
          and public.normalize_ambassador_name(referral_ambassador_name) = selected_name;
        representative_name := coalesce(representative_name, selected_name);

        insert into public.ambassador_name_assignments(
            ambassador_user_id, entered_name, normalized_name, active, created_by
        ) values (input_user_id, representative_name, selected_name, true, auth.uid())
        on conflict (normalized_name) do update
        set ambassador_user_id = excluded.ambassador_user_id,
            entered_name = excluded.entered_name,
            active = true,
            updated_at = now();
    end loop;

    insert into public.admin_audit_log(actor_user_id, action, target_user_id, target_type, target_id, after_value)
    values (
        auth.uid(), 'ambassador_names_assigned', input_user_id, 'ambassador', input_user_id::text,
        jsonb_build_object('normalized_names', coalesce(input_normalized_names, array[]::text[]))
    );
end;
$$;
grant execute on function public.admin_set_ambassador_names(uuid, text[]) to authenticated;

create or replace function public.register_admin_push_device(
    input_installation_id text,
    input_device_token text,
    input_environment text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_super_admin() then raise exception 'super_admin_required'; end if;
    if input_environment not in ('sandbox', 'production') then raise exception 'invalid_push_environment'; end if;
    if trim(input_installation_id) = '' or trim(input_device_token) = '' then raise exception 'push_device_data_required'; end if;

    delete from public.admin_push_devices
    where user_id = auth.uid()
      and (installation_id = input_installation_id or device_token = input_device_token);
    insert into public.admin_push_devices(user_id, installation_id, device_token, environment, active, last_registered_at)
    values (auth.uid(), input_installation_id, input_device_token, input_environment, true, now());
end;
$$;
grant execute on function public.register_admin_push_device(text, text, text) to authenticated;
