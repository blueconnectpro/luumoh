create extension if not exists pg_cron with schema extensions;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'expire-stale-pending-orders'
  ) then
    perform cron.unschedule('expire-stale-pending-orders');
  end if;

  perform cron.schedule(
    'expire-stale-pending-orders',
    '*/5 * * * *',
    'select public.expire_stale_pending_orders();'
  );
end;
$$;
