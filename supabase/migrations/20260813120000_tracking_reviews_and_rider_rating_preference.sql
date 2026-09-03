create or replace function public.customer_mark_order_received(
  p_order_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.orders
  set status = 'delivered',
      updated_at = now()
  where id = p_order_id
    and customer_id = auth.uid()
    and payment_status = 'paid'
    and status in ('out_for_delivery', 'picked_up');

  if not found then
    raise exception 'Order cannot be marked received';
  end if;

  insert into public.delivery_events(order_id, status, note)
  values (p_order_id, 'delivered', 'Customer confirmed delivery received');
end;
$$;

grant execute on function public.customer_mark_order_received(uuid)
to authenticated;

revoke execute on function public.customer_mark_order_received(uuid)
from anon;

create or replace view public.rider_rating_summaries
with (security_invoker = false)
as
select
  p.id as rider_id,
  coalesce(avg(rr.rating), 0)::numeric(4, 2) as average_rating,
  count(rr.id)::integer as review_count
from public.profiles p
left join public.rider_reviews rr on rr.rider_id = p.id
where p.role = 'rider'
group by p.id;

grant select on public.rider_rating_summaries to authenticated;

create or replace function public.nearest_online_rider_pickup_estimate(
  p_store_id uuid
)
returns table (
  rider_id uuid,
  distance_km numeric,
  eta_minutes integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store record;
begin
  select id, latitude, longitude
  into v_store
  from public.stores
  where id = p_store_id;

  if not found then
    raise exception 'Store not found';
  end if;

  if not public.is_store_member(p_store_id) and not public.is_admin() then
    raise exception 'Not allowed to inspect this store';
  end if;

  if v_store.latitude is null or v_store.longitude is null then
    return;
  end if;

  return query
  select
    ranked.rider_id,
    round(ranked.distance_km, 2) as distance_km,
    greatest(5, least(45, ceil(ranked.distance_km * 4 + 6)::integer)) as eta_minutes
  from (
    select
      ra.rider_id,
      public.distance_km(
        v_store.latitude,
        v_store.longitude,
        latest.latitude,
        latest.longitude
      ) as distance_km,
      coalesce(rating.average_rating, 0) as average_rating,
      coalesce(rating.review_count, 0) as review_count,
      ra.last_seen_at
    from public.rider_availability ra
    join public.profiles p on p.id = ra.rider_id and p.role = 'rider'
    left join public.rider_rating_summaries rating
      on rating.rider_id = ra.rider_id
    join lateral (
      select rlu.latitude, rlu.longitude
      from public.rider_location_updates rlu
      where rlu.rider_id = ra.rider_id
      order by rlu.created_at desc
      limit 1
    ) latest on true
    where ra.is_online = true
  ) ranked
  where ranked.distance_km is not null
  order by
    ranked.distance_km - least(ranked.average_rating, 5) * 0.35 asc,
    ranked.review_count desc,
    ranked.average_rating desc,
    ranked.last_seen_at desc
  limit 1;
end;
$$;

grant execute on function public.nearest_online_rider_pickup_estimate(uuid)
to authenticated;

revoke execute on function public.nearest_online_rider_pickup_estimate(uuid)
from anon;

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
    ranked.rider_id,
    ranked.distance_km,
    ranked.average_rating,
    ranked.review_count,
    ranked.last_seen_at
  into v_rider
  from (
    select
      ra.rider_id,
      public.distance_km(
        coalesce(v_order.store_latitude, v_order.fallback_store_latitude),
        coalesce(v_order.store_longitude, v_order.fallback_store_longitude),
        latest.latitude,
        latest.longitude
      ) as distance_km,
      coalesce(rating.average_rating, 0) as average_rating,
      coalesce(rating.review_count, 0) as review_count,
      ra.last_seen_at
    from public.rider_availability ra
    join public.profiles p on p.id = ra.rider_id and p.role = 'rider'
    left join public.rider_rating_summaries rating
      on rating.rider_id = ra.rider_id
    left join lateral (
      select rlu.latitude, rlu.longitude
      from public.rider_location_updates rlu
      where rlu.rider_id = ra.rider_id
      order by rlu.created_at desc
      limit 1
    ) latest on true
    where ra.is_online = true
  ) ranked
  order by
    case when ranked.distance_km is null then 1 else 0 end,
    coalesce(ranked.distance_km, 25) - least(ranked.average_rating, 5) * 0.35 asc,
    ranked.review_count desc,
    ranked.average_rating desc,
    ranked.last_seen_at desc
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
      when v_rider.distance_km is null then 'Store marked ready; notified highly rated online rider'
      else 'Store marked ready; notified preferred rider (' || round(v_rider.distance_km, 2) || ' km away, ' || round(v_rider.average_rating, 1) || '/5)'
    end
  );

  return v_rider.rider_id;
end;
$$;

grant execute on function public.store_mark_order_ready_and_dispatch(uuid, integer)
to authenticated;

revoke execute on function public.store_mark_order_ready_and_dispatch(uuid, integer)
from anon;
