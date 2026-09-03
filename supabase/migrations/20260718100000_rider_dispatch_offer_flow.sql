create or replace function public.store_mark_order_ready_and_dispatch(
  p_order_id uuid,
  p_eta_minutes integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_rider record;
  v_eta integer;
begin
  select
    o.id,
    o.store_id,
    o.status,
    o.payment_status,
    o.rider_id,
    o.fulfillment_type,
    o.store_latitude,
    o.store_longitude,
    s.latitude as fallback_store_latitude,
    s.longitude as fallback_store_longitude
  into v_order
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not public.is_store_member(v_order.store_id) and not public.is_admin() then
    raise exception 'Not allowed to update this order';
  end if;

  if v_order.payment_status <> 'paid' then
    raise exception 'Only paid orders can be marked ready';
  end if;

  if v_order.status not in ('accepted', 'preparing', 'ready_for_pickup') then
    raise exception 'Only accepted or preparing orders can be marked ready';
  end if;

  if v_order.status <> 'ready_for_pickup' then
    update public.orders
    set status = 'ready_for_pickup',
        updated_at = now()
    where id = p_order_id;

    insert into public.delivery_events(order_id, status, note)
    values (p_order_id, 'ready_for_pickup', 'Store marked order ready for delivery');
  end if;

  if v_order.fulfillment_type = 'pickup' then
    return null;
  end if;

  if v_order.rider_id is not null then
    return v_order.rider_id;
  end if;

  select
    ra.rider_id,
    public.distance_km(
      coalesce(v_order.store_latitude, v_order.fallback_store_latitude),
      coalesce(v_order.store_longitude, v_order.fallback_store_longitude),
      latest.latitude,
      latest.longitude
    ) as distance_km,
    ra.last_seen_at
  into v_rider
  from public.rider_availability ra
  join public.profiles p on p.id = ra.rider_id and p.role = 'rider'
  left join lateral (
    select rlu.latitude, rlu.longitude
    from public.rider_location_updates rlu
    where rlu.rider_id = ra.rider_id
    order by rlu.created_at desc
    limit 1
  ) latest on true
  where ra.is_online = true
  order by
    public.distance_km(
      coalesce(v_order.store_latitude, v_order.fallback_store_latitude),
      coalesce(v_order.store_longitude, v_order.fallback_store_longitude),
      latest.latitude,
      latest.longitude
    ) nulls last,
    ra.last_seen_at desc
  limit 1;

  if v_rider.rider_id is null then
    return null;
  end if;

  v_eta := coalesce(
    p_eta_minutes,
    case
      when v_rider.distance_km is null then 25
      else greatest(8, least(60, ceil(v_rider.distance_km * 4 + 8)::integer))
    end
  );

  update public.orders
  set rider_id = v_rider.rider_id,
      eta_minutes = v_eta,
      eta_updated_at = now(),
      updated_at = now()
  where id = p_order_id
    and payment_status = 'paid'
    and status = 'ready_for_pickup'
    and rider_id is null;

  if not found then
    return null;
  end if;

  insert into public.delivery_events(order_id, rider_id, status, eta_minutes, note)
  values (
    p_order_id,
    v_rider.rider_id,
    'ready_for_pickup',
    v_eta,
    case
      when v_rider.distance_km is null then 'Store marked ready; notified online rider'
      else 'Store marked ready; notified nearest online rider (' || round(v_rider.distance_km, 2) || ' km away)'
    end
  );

  return v_rider.rider_id;
end;
$$;

grant execute on function public.store_mark_order_ready_and_dispatch(uuid, integer)
to authenticated;

revoke execute on function public.store_mark_order_ready_and_dispatch(uuid, integer)
from anon;

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
      status = 'out_for_delivery',
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
    'out_for_delivery',
    p_eta_minutes,
    coalesce(p_note, 'Rider accepted order')
  );
end;
$$;

grant execute on function public.accept_rider_order(uuid, integer, text)
to authenticated;

revoke execute on function public.accept_rider_order(uuid, integer, text)
from anon;
