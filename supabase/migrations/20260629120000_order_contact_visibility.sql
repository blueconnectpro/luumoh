create or replace function public.order_profile_name(
  p_order_id uuid,
  p_profile_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(p.full_name), '')
  from public.orders o
  join public.profiles p on p.id = p_profile_id
  where o.id = p_order_id
    and p.id in (o.customer_id, o.rider_id)
    and (
      o.customer_id = auth.uid()
      or o.rider_id = auth.uid()
      or public.is_store_member(o.store_id)
      or public.is_admin()
    )
$$;

create or replace function public.order_profile_phone(
  p_order_id uuid,
  p_profile_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select nullif(trim(p.phone), '')
  from public.orders o
  join public.profiles p on p.id = p_profile_id
  where o.id = p_order_id
    and p.id in (o.customer_id, o.rider_id)
    and (
      o.customer_id = auth.uid()
      or o.rider_id = auth.uid()
      or public.is_store_member(o.store_id)
      or public.is_admin()
    )
$$;

create or replace view public.order_summaries
with (security_invoker = true)
as
select
  o.id,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.rider_id,
  o.status,
  o.payment_status,
  o.total_amount,
  o.delivery_address,
  o.eta_minutes,
  o.eta_updated_at,
  o.created_at,
  o.updated_at,
  public.order_profile_name(o.id, o.customer_id) as customer_name,
  public.order_profile_phone(o.id, o.customer_id) as customer_phone,
  public.order_profile_name(o.id, o.rider_id) as rider_name,
  public.order_profile_phone(o.id, o.rider_id) as rider_phone
from public.orders o
join public.stores s on s.id = o.store_id;
