create or replace function public.admin_repair_finance_reconciliation()
returns table (
  metric text,
  repaired_count numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_count numeric;
  v_rider_count numeric;
begin
  if auth.role() <> 'service_role'
     and current_user not in ('postgres', 'supabase_admin')
     and not public.is_admin() then
    raise exception 'Only admins can repair finance reconciliation';
  end if;

  insert into public.store_settlements (
    store_id,
    order_id,
    gross_items_amount,
    discount_amount,
    net_items_amount,
    service_fee_amount,
    payout_amount,
    status
  )
  select
    o.store_id,
    o.id,
    coalesce(o.items_subtotal, o.total_amount),
    coalesce(o.discount_amount, 0),
    coalesce(
      o.store_payout_amount,
      greatest(o.total_amount - o.delivery_fee - o.service_fee, 0)
    ),
    coalesce(o.service_fee, 0),
    coalesce(
      o.store_payout_amount,
      greatest(o.total_amount - o.delivery_fee - o.service_fee, 0)
    ),
    case when o.status = 'cancelled' then 'cancelled' else 'pending' end
  from public.orders o
  where o.payment_status = 'paid'
    and not exists (
      select 1
      from public.store_settlements ss
      where ss.order_id = o.id
    );
  get diagnostics v_store_count = row_count;

  insert into public.rider_settlements (
    rider_id,
    store_id,
    order_id,
    delivery_fee_amount,
    rider_payout_amount,
    platform_delivery_margin,
    status
  )
  select
    o.rider_id,
    o.store_id,
    o.id,
    coalesce(o.delivery_fee, 0),
    coalesce(o.rider_payout_amount, 0),
    greatest(coalesce(o.delivery_fee, 0) - coalesce(o.rider_payout_amount, 0), 0),
    'pending'
  from public.orders o
  where o.payment_status = 'paid'
    and o.status = 'delivered'
    and o.rider_id is not null
    and not exists (
      select 1
      from public.rider_settlements rs
      where rs.order_id = o.id
    );
  get diagnostics v_rider_count = row_count;

  return query
  values
    ('missing_store_settlements_inserted'::text, v_store_count),
    ('missing_rider_settlements_inserted'::text, v_rider_count);
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
  if auth.role() <> 'service_role'
     and current_user not in ('postgres', 'supabase_admin')
     and not public.is_admin() then
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
  select
    'paid_order_payment_total_delta',
    abs(
      coalesce((select sum(total_amount) from public.orders where payment_status = 'paid'), 0) -
      coalesce((select sum(amount) from public.payments where status = 'paid'), 0)
    ),
    case
      when abs(
        coalesce((select sum(total_amount) from public.orders where payment_status = 'paid'), 0) -
        coalesce((select sum(amount) from public.payments where status = 'paid'), 0)
      ) <= 0.01 then 'ok'
      else 'error'
    end

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
    'paid_orders_with_payment_amount_shortfall',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.orders o
  where o.payment_status = 'paid'
    and not exists (
      select 1
      from public.payments p
      where p.order_id = o.id
        and p.status = 'paid'
        and p.amount >= o.total_amount
    )

  union all
  select
    'paid_payments_without_paid_order',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.payments p
  join public.orders o on o.id = p.order_id
  where p.status = 'paid'
    and o.payment_status <> 'paid'

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
    'store_settlement_amount_mismatches',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.store_settlements ss
  join public.orders o on o.id = ss.order_id
  where o.payment_status = 'paid'
    and (
      abs(ss.gross_items_amount - coalesce(o.items_subtotal, o.total_amount)) > 0.01
      or abs(ss.discount_amount - coalesce(o.discount_amount, 0)) > 0.01
      or abs(ss.net_items_amount - coalesce(o.store_payout_amount, greatest(o.total_amount - o.delivery_fee - o.service_fee, 0))) > 0.01
      or abs(ss.service_fee_amount - coalesce(o.service_fee, 0)) > 0.01
      or abs(ss.payout_amount - coalesce(o.store_payout_amount, greatest(o.total_amount - o.delivery_fee - o.service_fee, 0))) > 0.01
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
  select
    'rider_settlement_amount_mismatches',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'error' end
  from public.rider_settlements rs
  join public.orders o on o.id = rs.order_id
  where o.payment_status = 'paid'
    and o.status = 'delivered'
    and o.rider_id is not null
    and (
      abs(rs.delivery_fee_amount - coalesce(o.delivery_fee, 0)) > 0.01
      or abs(rs.rider_payout_amount - coalesce(o.rider_payout_amount, 0)) > 0.01
      or abs(rs.platform_delivery_margin - greatest(coalesce(o.delivery_fee, 0) - coalesce(o.rider_payout_amount, 0), 0)) > 0.01
    )

  union all
  select
    'failed_payment_webhook_events',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'warning' end
  from public.payment_webhook_events
  where processing_status = 'failed'

  union all
  select
    'recent_failed_payment_webhook_events',
    count(*)::numeric,
    case when count(*) = 0 then 'ok' else 'warning' end
  from public.payment_webhook_events
  where processing_status = 'failed'
    and created_at >= now() - interval '24 hours'

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

revoke execute on function public.admin_repair_finance_reconciliation()
  from anon, authenticated;
revoke execute on function public.admin_finance_reconciliation()
  from anon, authenticated;

select *
from public.admin_repair_finance_reconciliation();
