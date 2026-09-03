create or replace view public.customer_catalog
with (security_invoker = true)
as
select
  p.id as product_id,
  p.store_id,
  s.name as store_name,
  p.name,
  p.description,
  p.price,
  p.image_url,
  greatest(
    coalesce(ii.quantity_on_hand, 0) - coalesce((
      select sum(ir.quantity)
      from public.inventory_reservations ir
      where ir.product_id = p.id
        and ir.active = true
        and ir.expires_at > now()
    ), 0),
    0
  )::integer as quantity_available,
  (
    public.is_store_taking_orders(s.id)
    and p.is_available
    and (p.unavailable_until is null or p.unavailable_until <= now())
    and greatest(
      coalesce(ii.quantity_on_hand, 0) - coalesce((
        select sum(ir.quantity)
        from public.inventory_reservations ir
        where ir.product_id = p.id
          and ir.active = true
          and ir.expires_at > now()
      ), 0),
      0
    ) > 0
  ) as is_available,
  public.customer_category_group(p.category) as category,
  p.unavailable_until,
  s.latitude as store_latitude,
  s.longitude as store_longitude,
  p.image_urls,
  s.category as store_category
from public.products p
join public.stores s on s.id = p.store_id
left join public.inventory_items ii on ii.product_id = p.id
where s.is_active = true;

grant select on public.customer_catalog to authenticated;

notify pgrst, 'reload schema';
