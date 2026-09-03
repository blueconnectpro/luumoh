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
      ra.last_seen_at
    from public.rider_availability ra
    join public.profiles p on p.id = ra.rider_id and p.role = 'rider'
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
  order by ranked.distance_km asc, ranked.last_seen_at desc
  limit 1;
end;
$$;

grant execute on function public.nearest_online_rider_pickup_estimate(uuid)
to authenticated;

revoke execute on function public.nearest_online_rider_pickup_estimate(uuid)
from anon;
