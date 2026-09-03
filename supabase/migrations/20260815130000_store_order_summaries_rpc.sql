create or replace function public.store_order_summaries(
  p_store_id uuid
)
returns table (
  id uuid,
  customer_id uuid,
  store_id uuid,
  store_name text,
  rider_id uuid,
  status public.order_status,
  payment_status public.payment_status,
  items_subtotal numeric,
  discount_amount numeric,
  delivery_fee numeric,
  service_fee numeric,
  total_amount numeric,
  store_payout_amount numeric,
  rider_payout_amount numeric,
  platform_fee_amount numeric,
  delivery_address text,
  eta_minutes integer,
  eta_updated_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  customer_name text,
  customer_phone text,
  rider_name text,
  rider_phone text,
  preparation_minutes integer,
  cancellation_reason text,
  fulfillment_type text,
  store_latitude numeric,
  store_longitude numeric,
  delivery_latitude numeric,
  delivery_longitude numeric,
  delivery_distance_km numeric,
  store_address text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_store_id is null then
    raise exception 'Store id is required';
  end if;

  if not public.is_store_member(p_store_id) and not public.is_admin() then
    raise exception 'Not allowed to view this store orders';
  end if;

  return query
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
  join public.stores s on s.id = o.store_id
  where o.store_id = p_store_id
  order by o.created_at desc;
end;
$$;

grant execute on function public.store_order_summaries(uuid)
to authenticated;

revoke execute on function public.store_order_summaries(uuid)
from anon;
