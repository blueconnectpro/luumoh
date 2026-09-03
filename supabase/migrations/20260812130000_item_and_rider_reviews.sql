create table if not exists public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_item_id, customer_id),
  unique (order_id, product_id, customer_id)
);

create table if not exists public.rider_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  rider_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, customer_id)
);

drop trigger if exists product_reviews_touch_updated_at on public.product_reviews;
create trigger product_reviews_touch_updated_at
before update on public.product_reviews
for each row execute function public.touch_updated_at();

drop trigger if exists rider_reviews_touch_updated_at on public.rider_reviews;
create trigger rider_reviews_touch_updated_at
before update on public.rider_reviews
for each row execute function public.touch_updated_at();

alter table public.product_reviews enable row level security;
alter table public.rider_reviews enable row level security;

drop policy if exists "product reviews scoped read" on public.product_reviews;
create policy "product reviews scoped read" on public.product_reviews
  for select using (
    customer_id = auth.uid()
    or public.is_store_member(store_id)
    or public.is_admin()
  );

drop policy if exists "rider reviews scoped read" on public.rider_reviews;
create policy "rider reviews scoped read" on public.rider_reviews
  for select using (
    customer_id = auth.uid()
    or rider_id = auth.uid()
    or public.is_store_member(store_id)
    or public.is_admin()
  );

create or replace function public.customer_upsert_product_review(
  p_order_id uuid,
  p_product_id uuid,
  p_rating integer,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_order_item record;
  v_review_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;

  select id, customer_id, store_id, status
  into v_order
  from public.orders
  where id = p_order_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status <> 'delivered' then
    raise exception 'Only delivered order items can be reviewed';
  end if;

  select id, product_id
  into v_order_item
  from public.order_items
  where order_id = p_order_id
    and product_id = p_product_id
  limit 1;

  if not found then
    raise exception 'Item was not found on this order';
  end if;

  insert into public.product_reviews (
    order_id,
    order_item_id,
    product_id,
    customer_id,
    store_id,
    rating,
    comment
  )
  values (
    p_order_id,
    v_order_item.id,
    v_order_item.product_id,
    v_order.customer_id,
    v_order.store_id,
    p_rating,
    nullif(trim(coalesce(p_comment, '')), '')
  )
  on conflict (order_item_id, customer_id)
  do update set
    rating = excluded.rating,
    comment = excluded.comment
  returning id into v_review_id;

  return v_review_id;
end;
$$;

create or replace function public.customer_upsert_rider_review(
  p_order_id uuid,
  p_rating integer,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_review_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;

  select id, customer_id, store_id, rider_id, status
  into v_order
  from public.orders
  where id = p_order_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.status <> 'delivered' then
    raise exception 'Only delivered orders can be reviewed';
  end if;

  if v_order.rider_id is null then
    raise exception 'This order has no rider to review';
  end if;

  insert into public.rider_reviews (
    order_id,
    rider_id,
    customer_id,
    store_id,
    rating,
    comment
  )
  values (
    p_order_id,
    v_order.rider_id,
    v_order.customer_id,
    v_order.store_id,
    p_rating,
    nullif(trim(coalesce(p_comment, '')), '')
  )
  on conflict (order_id, customer_id)
  do update set
    rating = excluded.rating,
    comment = excluded.comment
  returning id into v_review_id;

  return v_review_id;
end;
$$;

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
  r.product_id,
  oi.product_name,
  r.rating,
  r.comment,
  r.created_at,
  r.updated_at
from public.product_reviews r
join public.orders o on o.id = r.order_id
join public.stores s on s.id = r.store_id
join public.order_items oi on oi.id = r.order_item_id
where o.status = 'delivered';

create or replace view public.rider_review_summaries
with (security_invoker = true)
as
select
  r.id,
  r.order_id,
  r.rider_id,
  public.order_profile_name(r.order_id, r.rider_id) as rider_name,
  r.customer_id,
  public.order_profile_name(r.order_id, r.customer_id) as customer_name,
  r.store_id,
  s.name as store_name,
  r.rating,
  r.comment,
  r.created_at,
  r.updated_at
from public.rider_reviews r
join public.orders o on o.id = r.order_id
join public.stores s on s.id = r.store_id;

grant select on public.product_review_summaries to authenticated;
grant select on public.rider_review_summaries to authenticated;
grant execute on function public.customer_upsert_product_review(uuid, uuid, integer, text) to authenticated;
grant execute on function public.customer_upsert_rider_review(uuid, integer, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.product_reviews;
exception
  when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.rider_reviews;
exception
  when duplicate_object then null;
end;
$$;
