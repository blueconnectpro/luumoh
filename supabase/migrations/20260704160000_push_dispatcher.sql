alter table public.notification_deliveries
  drop constraint if exists notification_deliveries_status_check;

alter table public.notification_deliveries
  add constraint notification_deliveries_status_check
  check (status in ('pending', 'processing', 'sent', 'failed', 'skipped'));

create or replace view public.notification_delivery_summaries as
select
  nd.id,
  nd.notification_id,
  nd.user_id,
  p.full_name as user_name,
  un.type,
  un.title,
  un.body,
  nd.provider,
  nd.status,
  nd.attempts,
  nd.last_error,
  nd.payload,
  nd.created_at,
  nd.sent_at,
  nd.updated_at
from public.notification_deliveries nd
join public.user_notifications un on un.id = nd.notification_id
left join public.profiles p on p.id = nd.user_id
where public.is_admin() or nd.user_id = auth.uid();

create or replace function public.claim_pending_notification_deliveries(
  p_limit integer default 25
)
returns table (
  delivery_id uuid,
  notification_id uuid,
  user_id uuid,
  device_id uuid,
  provider text,
  device_token text,
  payload jsonb,
  attempts integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service role can claim notification deliveries';
  end if;

  return query
  with claimed as (
    select nd.id
    from public.notification_deliveries nd
    where nd.status = 'pending'
       or (
         nd.status = 'processing'
         and nd.updated_at < now() - interval '5 minutes'
       )
    order by nd.created_at
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update skip locked
  )
  update public.notification_deliveries nd
  set status = 'processing',
      attempts = nd.attempts + 1,
      updated_at = now()
  from claimed
  join public.notification_devices device on device.id is not null
  where nd.id = claimed.id
    and device.id = nd.device_id
  returning
    nd.id,
    nd.notification_id,
    nd.user_id,
    nd.device_id,
    nd.provider,
    device.device_token,
    nd.payload,
    nd.attempts;
end;
$$;

create or replace function public.mark_notification_delivery_result(
  p_delivery_id uuid,
  p_status text,
  p_last_error text default null,
  p_response jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service role can update notification deliveries';
  end if;

  if p_status not in ('sent', 'failed', 'skipped', 'pending') then
    raise exception 'Unsupported delivery status %', p_status;
  end if;

  update public.notification_deliveries
  set status = p_status,
      last_error = nullif(trim(coalesce(p_last_error, '')), ''),
      payload = payload || jsonb_build_object(
        'dispatch_response',
        coalesce(p_response, '{}'::jsonb)
      ),
      sent_at = case when p_status = 'sent' then now() else sent_at end,
      updated_at = now()
  where id = p_delivery_id;
end;
$$;

revoke execute on function public.claim_pending_notification_deliveries(integer)
  from anon, authenticated;
revoke execute on function public.mark_notification_delivery_result(uuid, text, text, jsonb)
  from anon, authenticated;

grant select on public.notification_delivery_summaries to authenticated;
