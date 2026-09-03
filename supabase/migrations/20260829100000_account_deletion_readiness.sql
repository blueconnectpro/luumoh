alter table public.orders
  drop constraint if exists orders_customer_id_fkey;

alter table public.orders
  alter column customer_id drop not null;

alter table public.orders
  add constraint orders_customer_id_fkey
  foreign key (customer_id)
  references public.profiles(id)
  on delete set null;

create or replace view public.order_summaries
with (security_invoker = true) as
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
  case
    when o.customer_id is null then 'Deleted customer'
    else public.order_profile_name(o.id, o.customer_id)
  end as customer_name,
  case
    when o.customer_id is null then null::text
    else public.order_profile_phone(o.id, o.customer_id)
  end as customer_phone,
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

notify pgrst, 'reload schema';
