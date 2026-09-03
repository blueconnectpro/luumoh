create table if not exists public.customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  label text not null default 'Home',
  address text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customer_addresses_customer_id_idx
  on public.customer_addresses(customer_id);

drop trigger if exists customer_addresses_touch_updated_at
on public.customer_addresses;

create trigger customer_addresses_touch_updated_at
before update on public.customer_addresses
for each row execute function public.touch_updated_at();

alter table public.customer_addresses enable row level security;

create policy "customer addresses scoped read" on public.customer_addresses
  for select using (customer_id = auth.uid() or public.is_admin());

create policy "customer addresses scoped insert" on public.customer_addresses
  for insert with check (customer_id = auth.uid() or public.is_admin());

create policy "customer addresses scoped update" on public.customer_addresses
  for update using (customer_id = auth.uid() or public.is_admin())
  with check (customer_id = auth.uid() or public.is_admin());

create policy "customer addresses scoped delete" on public.customer_addresses
  for delete using (customer_id = auth.uid() or public.is_admin());

create or replace function public.customer_save_address(
  p_label text,
  p_address text,
  p_is_default boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_address_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  if length(trim(coalesce(p_address, ''))) = 0 then
    raise exception 'Address is required';
  end if;

  if p_is_default then
    update public.customer_addresses
    set is_default = false
    where customer_id = auth.uid();
  end if;

  insert into public.customer_addresses (
    customer_id,
    label,
    address,
    is_default
  )
  values (
    auth.uid(),
    coalesce(nullif(trim(coalesce(p_label, '')), ''), 'Home'),
    trim(p_address),
    p_is_default
  )
  returning id into v_address_id;

  return v_address_id;
end;
$$;

create or replace function public.customer_set_default_address(
  p_address_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  update public.customer_addresses
  set is_default = false
  where customer_id = auth.uid();

  update public.customer_addresses
  set is_default = true
  where id = p_address_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Address not found';
  end if;
end;
$$;

create or replace function public.customer_delete_address(
  p_address_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  delete from public.customer_addresses
  where id = p_address_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Address not found';
  end if;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.customer_addresses;
exception
  when duplicate_object then null;
end;
$$;
