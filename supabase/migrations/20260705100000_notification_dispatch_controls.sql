create or replace function public.retry_failed_notification_deliveries(
  p_limit integer default 100,
  p_max_attempts integer default 5
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only admins can retry notification deliveries';
  end if;

  with retryable as (
    select id
    from public.notification_deliveries
    where status = 'failed'
      and attempts < greatest(1, coalesce(p_max_attempts, 5))
    order by updated_at
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  )
  update public.notification_deliveries nd
  set status = 'pending',
      last_error = null,
      updated_at = now()
  from retryable
  where nd.id = retryable.id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.cleanup_old_notification_deliveries(
  p_retention_days integer default 30
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_retention_days integer := greatest(7, coalesce(p_retention_days, 30));
begin
  if auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only admins can clean up notification deliveries';
  end if;

  delete from public.notification_deliveries
  where status in ('sent', 'skipped')
    and updated_at < now() - make_interval(days => v_retention_days);

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

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
    where (
        nd.status = 'pending'
        or (
          nd.status = 'processing'
          and nd.updated_at < now() - interval '5 minutes'
        )
      )
      and nd.attempts < 5
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

revoke execute on function public.retry_failed_notification_deliveries(integer, integer)
  from anon;
revoke execute on function public.cleanup_old_notification_deliveries(integer)
  from anon;
revoke execute on function public.claim_pending_notification_deliveries(integer)
  from anon, authenticated;
