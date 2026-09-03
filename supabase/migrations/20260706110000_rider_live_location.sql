create table if not exists public.rider_location_updates (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  rider_id uuid not null references public.profiles(id) on delete cascade,
  latitude numeric(9, 6) not null check (latitude between -90 and 90),
  longitude numeric(9, 6) not null check (longitude between -180 and 180),
  accuracy_meters numeric(10, 2) check (accuracy_meters is null or accuracy_meters >= 0),
  heading numeric(6, 2) check (heading is null or (heading >= 0 and heading <= 360)),
  speed_mps numeric(10, 2) check (speed_mps is null or speed_mps >= 0),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists rider_location_updates_order_created_idx
  on public.rider_location_updates(order_id, created_at desc);

create index if not exists rider_location_updates_rider_created_idx
  on public.rider_location_updates(rider_id, created_at desc);

alter table public.rider_location_updates enable row level security;

drop policy if exists "rider location scoped read" on public.rider_location_updates;
create policy "rider location scoped read" on public.rider_location_updates
  for select using (public.can_access_order(order_id));

create or replace view public.rider_location_summaries
with (security_invoker = true)
as
select
  rlu.id,
  rlu.order_id,
  rlu.rider_id,
  public.order_profile_name(rlu.order_id, rlu.rider_id) as rider_name,
  rlu.latitude,
  rlu.longitude,
  rlu.accuracy_meters,
  rlu.heading,
  rlu.speed_mps,
  rlu.note,
  rlu.created_at,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.status as order_status,
  o.payment_status
from public.rider_location_updates rlu
join public.orders o on o.id = rlu.order_id
join public.stores s on s.id = o.store_id;

grant select on public.rider_location_summaries to authenticated;

create or replace function public.rider_update_order_location(
  p_order_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_meters numeric default null,
  p_heading numeric default null,
  p_speed_mps numeric default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_location_id uuid;
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  select id, rider_id, status, payment_status
  into v_order
  from public.orders
  where id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.payment_status <> 'paid' then
    raise exception 'Location can only be shared for paid orders';
  end if;

  if v_order.status in ('delivered', 'cancelled') then
    raise exception 'Location cannot be shared for completed orders';
  end if;

  if not (v_order.rider_id = v_actor or public.is_admin()) then
    raise exception 'Order is not assigned to this rider';
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90 then
    raise exception 'Latitude must be between -90 and 90';
  end if;

  if p_longitude is null or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Longitude must be between -180 and 180';
  end if;

  insert into public.rider_location_updates (
    order_id,
    rider_id,
    latitude,
    longitude,
    accuracy_meters,
    heading,
    speed_mps,
    note
  )
  values (
    p_order_id,
    coalesce(v_order.rider_id, v_actor),
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_heading,
    p_speed_mps,
    nullif(trim(coalesce(p_note, '')), '')
  )
  returning id into v_location_id;

  return v_location_id;
end;
$$;

grant execute on function public.rider_update_order_location(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text
) to authenticated;
revoke execute on function public.rider_update_order_location(
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  numeric,
  text
) from anon;

do $$
begin
  alter publication supabase_realtime add table public.rider_location_updates;
exception
  when duplicate_object then null;
end;
$$;

create or replace function public.admin_realtime_readiness()
returns table (
  table_name text,
  in_realtime boolean,
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
    raise exception 'Only admins can run realtime readiness checks';
  end if;

  return query
  with required_tables(table_name) as (
    values
      ('stores'),
      ('products'),
      ('inventory_items'),
      ('inventory_reservations'),
      ('orders'),
      ('order_items'),
      ('payments'),
      ('delivery_events'),
      ('profiles'),
      ('store_members'),
      ('customer_addresses'),
      ('rider_availability'),
      ('order_issues'),
      ('user_notifications'),
      ('order_reviews'),
      ('store_settlements'),
      ('rider_settlements'),
      ('payment_webhook_events'),
      ('order_messages'),
      ('rider_location_updates')
  )
  select
    rt.table_name::text,
    exists (
      select 1
      from pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = rt.table_name
    ) as in_realtime,
    coalesce(c.relrowsecurity, false) as rls_enabled,
    count(p.polname)::integer as policy_count,
    case
      when not exists (
        select 1
        from pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = rt.table_name
      ) then 'error'
      when not coalesce(c.relrowsecurity, false) then 'error'
      when count(p.polname) = 0 then 'warning'
      else 'ok'
    end as risk
  from required_tables rt
  left join pg_class c
    on c.relname = rt.table_name
   and c.relnamespace = 'public'::regnamespace
  left join pg_policy p on p.polrelid = c.oid
  group by rt.table_name, c.relrowsecurity
  order by
    case
      when not exists (
        select 1
        from pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = rt.table_name
      ) then 0
      when not coalesce(c.relrowsecurity, false) then 1
      when count(p.polname) = 0 then 2
      else 3
    end,
    rt.table_name;
end;
$$;
