create or replace view public.public_store_review_summaries
with (security_invoker = false)
as
select
  r.id,
  r.order_id,
  r.customer_id,
  null::text as customer_name,
  null::text as customer_phone,
  r.store_id,
  s.name as store_name,
  o.status as order_status,
  o.payment_status,
  0::numeric as total_amount,
  r.rating,
  r.comment,
  r.created_at,
  r.updated_at
from public.order_reviews r
join public.orders o on o.id = r.order_id
join public.stores s on s.id = r.store_id
where o.status = 'delivered';

create or replace view public.product_review_summaries
with (security_invoker = false)
as
select
  r.id,
  r.order_id,
  r.customer_id,
  null::text as customer_name,
  null::text as customer_phone,
  r.store_id,
  s.name as store_name,
  oi.product_id,
  oi.product_name,
  r.rating,
  r.comment,
  r.created_at,
  r.updated_at
from public.order_reviews r
join public.orders o on o.id = r.order_id
join public.stores s on s.id = r.store_id
join public.order_items oi on oi.order_id = r.order_id
where o.status = 'delivered';

grant select on public.public_store_review_summaries to authenticated;
grant select on public.product_review_summaries to authenticated;
