create table if not exists public.rider_availability (
  rider_id uuid primary key references public.profiles(id) on delete cascade,
  is_online boolean not null default false,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists rider_availability_touch_updated_at
on public.rider_availability;

create trigger rider_availability_touch_updated_at
before update on public.rider_availability
for each row execute function public.touch_updated_at();

alter table public.rider_availability enable row level security;

drop policy if exists "rider availability scoped read"
on public.rider_availability;

create policy "rider availability scoped read" on public.rider_availability
  for select using (rider_id = auth.uid() or public.is_admin());

drop policy if exists "rider availability scoped insert"
on public.rider_availability;

create policy "rider availability scoped insert" on public.rider_availability
  for insert with check (rider_id = auth.uid() or public.is_admin());

drop policy if exists "rider availability scoped update"
on public.rider_availability;

create policy "rider availability scoped update" on public.rider_availability
  for update using (rider_id = auth.uid() or public.is_admin())
  with check (rider_id = auth.uid() or public.is_admin());

create or replace function public.is_current_rider_online()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce((
    select ra.is_online
    from public.rider_availability ra
    where ra.rider_id = auth.uid()
  ), false)
$$;

create or replace function public.rider_set_availability(
  p_is_online boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can update availability';
  end if;

  insert into public.rider_availability (
    rider_id,
    is_online,
    last_seen_at
  )
  values (
    auth.uid(),
    p_is_online,
    now()
  )
  on conflict (rider_id) do update
  set is_online = excluded.is_online,
      last_seen_at = now(),
      updated_at = now();
end;
$$;

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
      eta_updated_at = case when p_eta_minutes is null then eta_updated_at else now() end
  where id = p_order_id
    and rider_id is null
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

drop policy if exists "orders scoped read" on public.orders;

create policy "orders scoped read" on public.orders
  for select using (
    customer_id = auth.uid()
    or rider_id = auth.uid()
    or (
      rider_id is null
      and status = 'ready_for_pickup'
      and public.is_current_rider_online()
    )
    or public.is_store_member(store_id)
    or public.is_admin()
  );

do $$
begin
  alter publication supabase_realtime add table public.rider_availability;
exception
  when duplicate_object then null;
end;
$$;
