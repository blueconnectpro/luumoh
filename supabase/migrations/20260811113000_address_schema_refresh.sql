alter table public.customer_addresses
  add column if not exists latitude numeric(10, 7),
  add column if not exists longitude numeric(10, 7);

create or replace function public.customer_save_address(
  p_label text,
  p_address text,
  p_is_default boolean default false,
  p_latitude numeric default null,
  p_longitude numeric default null
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

  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'Latitude is invalid';
  end if;

  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'Longitude is invalid';
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
    is_default,
    latitude,
    longitude
  )
  values (
    auth.uid(),
    coalesce(nullif(trim(coalesce(p_label, '')), ''), 'Home'),
    trim(p_address),
    p_is_default,
    p_latitude,
    p_longitude
  )
  returning id into v_address_id;

  return v_address_id;
end;
$$;

grant execute on function public.customer_save_address(
  text,
  text,
  boolean,
  numeric,
  numeric
) to authenticated;

notify pgrst, 'reload schema';
