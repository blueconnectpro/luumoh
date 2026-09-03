create table if not exists public.store_employee_activities (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  summary text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists store_employee_activities_store_created_idx
  on public.store_employee_activities(store_id, created_at desc);

create table if not exists public.store_staff_presence (
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_active boolean not null default false,
  last_login_at timestamptz,
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, user_id)
);

alter table public.store_employee_activities enable row level security;
alter table public.store_staff_presence enable row level security;

drop policy if exists "store employee activities scoped read" on public.store_employee_activities;
create policy "store employee activities scoped read" on public.store_employee_activities
  for select using (public.is_store_member(store_id) or public.is_admin());

drop policy if exists "store staff presence scoped read" on public.store_staff_presence;
create policy "store staff presence scoped read" on public.store_staff_presence
  for select using (public.is_store_member(store_id) or public.is_admin());

create or replace function public.log_store_employee_activity(
  p_store_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid default null,
  p_summary text default '',
  p_metadata jsonb default '{}'::jsonb,
  p_actor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_store_id is null then
    return null;
  end if;

  insert into public.store_employee_activities (
    store_id,
    actor_id,
    action,
    entity_type,
    entity_id,
    summary,
    metadata
  )
  values (
    p_store_id,
    coalesce(p_actor_id, auth.uid()),
    p_action,
    p_entity_type,
    p_entity_id,
    coalesce(p_summary, ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.register_store_staff_presence(
  p_store_id uuid,
  p_is_active boolean default true
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

  if not public.is_store_member(p_store_id) and not public.is_admin() then
    raise exception 'Not allowed to update staff presence for this store';
  end if;

  insert into public.store_staff_presence (
    store_id,
    user_id,
    is_active,
    last_login_at,
    last_seen_at,
    updated_at
  )
  values (
    p_store_id,
    auth.uid(),
    p_is_active,
    case when p_is_active then now() else null end,
    now(),
    now()
  )
  on conflict (store_id, user_id) do update
    set is_active = excluded.is_active,
        last_login_at = case
          when excluded.is_active then now()
          else store_staff_presence.last_login_at
        end,
        last_seen_at = now(),
        updated_at = now();

  perform public.log_store_employee_activity(
    p_store_id,
    case when p_is_active then 'staff_login' else 'staff_inactive' end,
    'presence',
    auth.uid(),
    case when p_is_active then 'Staff opened store dashboard' else 'Staff marked inactive' end,
    '{}'::jsonb,
    auth.uid()
  );
end;
$$;

create or replace view public.store_employee_activity_summaries
with (security_invoker = true)
as
select
  sea.id,
  sea.store_id,
  s.name as store_name,
  sea.actor_id,
  coalesce(nullif(p.full_name, ''), p.phone, 'System') as actor_name,
  p.role as actor_role,
  sea.action,
  sea.entity_type,
  sea.entity_id,
  sea.summary,
  sea.metadata,
  sea.created_at
from public.store_employee_activities sea
join public.stores s on s.id = sea.store_id
left join public.profiles p on p.id = sea.actor_id;

create or replace view public.store_staff_presence_summaries
with (security_invoker = true)
as
select
  ssp.store_id,
  st.name as store_name,
  ssp.user_id,
  coalesce(nullif(p.full_name, ''), p.phone, 'Store staff') as staff_name,
  null::text as staff_email,
  p.phone as staff_phone,
  p.role as staff_role,
  sm.can_manage_inventory,
  sm.can_manage_orders,
  ssp.is_active,
  ssp.last_login_at,
  ssp.last_seen_at,
  ssp.updated_at
from public.store_staff_presence ssp
join public.stores st on st.id = ssp.store_id
left join public.profiles p on p.id = ssp.user_id
left join public.store_members sm
  on sm.store_id = ssp.store_id
 and sm.user_id = ssp.user_id;

create or replace function public.log_product_employee_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text;
  v_summary text;
begin
  if tg_op = 'INSERT' then
    v_action := 'product_created';
    v_summary := 'Created product ' || new.name;
  elsif old.is_available is distinct from new.is_available
        or old.unavailable_until is distinct from new.unavailable_until then
    v_action := 'product_availability_updated';
    v_summary := 'Updated availability for ' || new.name;
  else
    v_action := 'product_updated';
    v_summary := 'Edited product ' || new.name;
  end if;

  perform public.log_store_employee_activity(
    new.store_id,
    v_action,
    'product',
    new.id,
    v_summary,
    jsonb_build_object(
      'name', new.name,
      'is_available', new.is_available,
      'unavailable_until', new.unavailable_until,
      'price', new.price
    )
  );

  return new;
end;
$$;

drop trigger if exists products_log_employee_activity on public.products;
create trigger products_log_employee_activity
after insert or update on public.products
for each row execute function public.log_product_employee_activity();

create or replace function public.log_inventory_employee_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.log_store_employee_activity(
    new.store_id,
    'inventory_adjusted',
    'inventory_movement',
    new.id,
    'Adjusted inventory by ' || new.quantity_delta,
    jsonb_build_object(
      'product_id', new.product_id,
      'quantity_delta', new.quantity_delta,
      'reason', new.reason,
      'note', new.note
    ),
    new.created_by
  );

  return new;
end;
$$;

drop trigger if exists inventory_movements_log_employee_activity on public.inventory_movements;
create trigger inventory_movements_log_employee_activity
after insert on public.inventory_movements
for each row execute function public.log_inventory_employee_activity();

create or replace function public.log_delivery_event_employee_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
begin
  select store_id into v_store_id
  from public.orders
  where id = new.order_id;

  perform public.log_store_employee_activity(
    v_store_id,
    'order_' || new.status::text,
    'order',
    new.order_id,
    coalesce(new.note, 'Order status updated to ' || new.status::text),
    jsonb_build_object(
      'status', new.status,
      'eta_minutes', new.eta_minutes,
      'delivery_event_id', new.id
    ),
    coalesce(new.rider_id, auth.uid())
  );

  return new;
end;
$$;

drop trigger if exists delivery_events_log_employee_activity on public.delivery_events;
create trigger delivery_events_log_employee_activity
after insert on public.delivery_events
for each row execute function public.log_delivery_event_employee_activity();

grant select on public.store_employee_activity_summaries to authenticated;
grant select on public.store_staff_presence_summaries to authenticated;
grant execute on function public.register_store_staff_presence(uuid, boolean)
  to authenticated;
revoke execute on function public.register_store_staff_presence(uuid, boolean)
  from anon;
revoke execute on function public.log_store_employee_activity(uuid, text, text, uuid, text, jsonb, uuid)
  from anon, authenticated;

do $$
begin
  begin
    alter publication supabase_realtime add table public.store_employee_activities;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.store_staff_presence;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end;
$$;
