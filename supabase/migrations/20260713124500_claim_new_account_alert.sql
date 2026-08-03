alter table public.admin_account_alerts
    add column if not exists last_attempted_at timestamptz;

create or replace function public.claim_new_account_alert(input_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    inserted_count integer;
    alert_row public.admin_account_alerts%rowtype;
begin
    if auth.role() <> 'service_role' then raise exception 'service_role_required'; end if;
    if not exists (select 1 from public.user_profiles where user_id = input_user_id) then
        raise exception 'user_not_found';
    end if;

    insert into public.admin_account_alerts(
        user_id, push_status, email_status, last_attempted_at
    ) values (input_user_id, 'processing', 'processing', now())
    on conflict (user_id) do nothing;
    get diagnostics inserted_count = row_count;

    select * into alert_row from public.admin_account_alerts where user_id = input_user_id for update;
    if inserted_count = 0 then
        if alert_row.push_status = 'sent' and alert_row.email_status = 'sent' then
            return jsonb_build_object(
                'claimed', false,
                'push_status', alert_row.push_status,
                'email_status', alert_row.email_status
            );
        end if;
        if alert_row.last_attempted_at is not null
           and alert_row.last_attempted_at > now() - interval '5 minutes' then
            return jsonb_build_object(
                'claimed', false,
                'push_status', alert_row.push_status,
                'email_status', alert_row.email_status
            );
        end if;
        update public.admin_account_alerts
        set last_attempted_at = now(), completed_at = null
        where user_id = input_user_id;
    end if;

    return jsonb_build_object(
        'claimed', true,
        'push_status', alert_row.push_status,
        'email_status', alert_row.email_status
    );
end;
$$;
revoke all on function public.claim_new_account_alert(uuid) from public;
grant execute on function public.claim_new_account_alert(uuid) to service_role;
