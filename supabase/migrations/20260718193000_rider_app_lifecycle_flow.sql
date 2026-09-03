create or replace view public.order_summaries
with (security_invoker = true)
as
select
  o.id,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.rider_id,
  o.status,
  o.payment_status,
  o.items_subtotal,
  o.discount_amount,
  o.delivery_fee,
  o.service_fee,
  o.total_amount,
  o.store_payout_amount,
  o.rider_payout_amount,
  o.platform_fee_amount,
  o.delivery_address,
  o.eta_minutes,
  o.eta_updated_at,
  o.created_at,
  o.updated_at,
  public.order_profile_name(o.id, o.customer_id) as customer_name,
  public.order_profile_phone(o.id, o.customer_id) as customer_phone,
  public.order_profile_name(o.id, o.rider_id) as rider_name,
  public.order_profile_phone(o.id, o.rider_id) as rider_phone,
  o.preparation_minutes,
  o.cancellation_reason,
  o.fulfillment_type,
  o.store_latitude,
  o.store_longitude,
  o.delivery_latitude,
  o.delivery_longitude,
  o.delivery_distance_km,
  s.address as store_address
from public.orders o
join public.stores s on s.id = o.store_id;

grant select on public.order_summaries to authenticated;

create or replace function public.accept_rider_order(
  p_order_id uuid,
  p_eta_minutes integer default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can accept orders';
  end if;

  if not public.is_current_rider_online() then
    raise exception 'Go online before accepting orders';
  end if;

  if p_eta_minutes is not null and p_eta_minutes < 0 then
    raise exception 'ETA cannot be negative';
  end if;

  update public.orders
  set rider_id = auth.uid(),
      eta_minutes = p_eta_minutes,
      eta_updated_at = case when p_eta_minutes is null then eta_updated_at else now() end,
      updated_at = now()
  where id = p_order_id
    and (rider_id is null or rider_id = auth.uid())
    and payment_status = 'paid'
    and status = 'ready_for_pickup';

  if not found then
    raise exception 'Order is not available';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, eta_minutes, note)
  values (
    p_order_id,
    auth.uid(),
    'ready_for_pickup',
    p_eta_minutes,
    coalesce(p_note, 'Rider accepted order and is heading to store')
  );
end;
$$;

grant execute on function public.accept_rider_order(uuid, integer, text)
to authenticated;

revoke execute on function public.accept_rider_order(uuid, integer, text)
from anon;

create or replace function public.decline_rider_order(
  p_order_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can decline orders';
  end if;

  update public.orders
  set rider_id = null,
      eta_minutes = null,
      eta_updated_at = null,
      updated_at = now()
  where id = p_order_id
    and rider_id = auth.uid()
    and payment_status = 'paid'
    and status = 'ready_for_pickup';

  if not found then
    raise exception 'Order is not assigned to this rider offer';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, note)
  values (
    p_order_id,
    auth.uid(),
    'ready_for_pickup',
    coalesce(p_note, 'Rider declined pickup offer')
  );
end;
$$;

grant execute on function public.decline_rider_order(uuid, text)
to authenticated;

revoke execute on function public.decline_rider_order(uuid, text)
from anon;
