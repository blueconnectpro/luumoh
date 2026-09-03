create or replace view public.payment_summaries
with (security_invoker = true)
as
select
  p.id,
  p.order_id,
  o.store_id,
  s.name as store_name,
  o.customer_id,
  p.provider,
  p.payment_reference,
  p.provider_transaction_reference,
  p.amount,
  p.status,
  p.checkout_url,
  p.created_at,
  p.updated_at
from public.payments p
join public.orders o on o.id = p.order_id
join public.stores s on s.id = o.store_id;
