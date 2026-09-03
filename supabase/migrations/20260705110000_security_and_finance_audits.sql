create or replace function public.admin_security_policy_audit()
returns table (
  table_name text,
  rls_enabled boolean,
  policy_count integer,
  risk text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only admins can run security audits';
  end if;

  return query
  select
    c.relname::text as table_name,
    c.relrowsecurity as rls_enabled,
    count(p.polname)::integer as policy_count,
    case
      when not c.relrowsecurity then 'error'
      when count(p.polname) = 0 then 'warning'
      else 'ok'
    end as risk
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policy p on p.polrelid = c.oid
  where n.nspname = 'public'
    and c.relkind = 'r'
  group by c.relname, c.relrowsecurity
  order by
    case
      when not c.relrowsecurity then 0
      when count(p.polname) = 0 then 1
      else 2
    end,
    c.relname;
end;
$$;

create or replace function public.admin_finance_reconciliation()
returns table (
  metric text,
  value numeric,
  severity text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only admins can run finance reconciliation';
  end if;

  return query
  select 'paid_order_count', count(*)::numeric, 'info'
  from public.orders
  where payment_status = 'paid'

  union all
  select 'paid_order_total', coalesce(sum(total_amount), 0), 'info'
  from public.orders
  where payment_status = 'paid'

  union all
  select 'paid_payment_total', coalesce(sum(amount), 0), 'info'
  from public.payments
  where status = 'paid'

  union all
  select 'platform_fee_total', coalesce(sum(platform_fee_amount), 0), 'info'
  from public.orders
  where payment_status = 'paid'

  union all
  select 'store_payout_total', coalesce(sum(payout_amount), 0), 'info'
  from public.store_settlements
  where status in ('pending', 'processing', 'paid')

  union all
  select 'rider_payout_total', coalesce(sum(rider_payout_amount), 0), 'info'
  from public.rider_settlements
  where status in ('pending', 'processing', 'paid')

  union all
  select
    'paid_orders_without_paid_payment',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.orders o
  where o.payment_status = 'paid'
    and not exists (
      select 1
      from public.payments p
      where p.order_id = o.id
        and p.status = 'paid'
    )

  union all
  select
    'paid_orders_without_store_settlement',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.orders o
  where o.payment_status = 'paid'
    and not exists (
      select 1
      from public.store_settlements ss
      where ss.order_id = o.id
    )

  union all
  select
    'delivered_orders_without_rider_settlement',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.orders o
  where o.payment_status = 'paid'
    and o.status = 'delivered'
    and o.rider_id is not null
    and not exists (
      select 1
      from public.rider_settlements rs
      where rs.order_id = o.id
    )

  union all
  select 'pending_store_settlement_total', coalesce(sum(payout_amount), 0), 'info'
  from public.store_settlements
  where status = 'pending'

  union all
  select 'pending_rider_settlement_total', coalesce(sum(rider_payout_amount), 0), 'info'
  from public.rider_settlements
  where status = 'pending';
end;
$$;

revoke execute on function public.admin_security_policy_audit()
  from anon, authenticated;
revoke execute on function public.admin_finance_reconciliation()
  from anon, authenticated;
