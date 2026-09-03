create table if not exists public.order_reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id),
  unique (order_id, customer_id)
);

drop trigger if exists order_reviews_touch_updated_at on public.order_reviews;

create trigger order_reviews_touch_updated_at
before update on public.order_reviews
for each row execute function public.touch_updated_at();

alter table public.order_reviews enable row level security;

drop policy if exists "order reviews scoped read" on public.order_reviews;
create policy "order reviews scoped read" on public.order_reviews
  for select using (
    customer_id = auth.uid()
    or public.is_store_member(store_id)
    or public.is_admin()
  );

create or replace function public.customer_upsert_order_review(
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
  v_existing_review_id uuid;
  v_is_new boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_rating is null or p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;

  select id, customer_id, store_id, status, payment_status
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

  select id
  into v_existing_review_id
  from public.order_reviews
  where order_id = p_order_id;

  if v_existing_review_id is null then
    insert into public.order_reviews (
      order_id,
      customer_id,
      store_id,
      rating,
      comment
    )
    values (
      p_order_id,
      v_order.customer_id,
      v_order.store_id,
      p_rating,
      nullif(trim(coalesce(p_comment, '')), '')
    )
    returning id into v_review_id;
    v_is_new := true;
  else
    update public.order_reviews
    set rating = p_rating,
        comment = nullif(trim(coalesce(p_comment, '')), '')
    where id = v_existing_review_id
      and customer_id = auth.uid()
    returning id into v_review_id;

    if v_review_id is null then
      raise exception 'Review cannot be updated';
    end if;
  end if;

  perform public.notify_store_users(
    v_order.store_id,
    'order_review_submitted',
    case when v_is_new then 'New customer review' else 'Customer review updated' end,
    'Order #' || left(p_order_id::text, 8) || ' received ' || p_rating || ' stars.',
    jsonb_build_object(
      'order_id', p_order_id,
      'store_id', v_order.store_id,
      'review_id', v_review_id,
      'rating', p_rating
    )
  );

  perform public.notify_admin_users(
    'order_review_submitted',
    case when v_is_new then 'New customer review' else 'Customer review updated' end,
    'Order #' || left(p_order_id::text, 8) || ' received ' || p_rating || ' stars.',
    jsonb_build_object(
      'order_id', p_order_id,
      'store_id', v_order.store_id,
      'review_id', v_review_id,
      'rating', p_rating
    )
  );

  return v_review_id;
end;
$$;

create or replace view public.order_review_summaries
with (security_invoker = true)
as
select
  r.id,
  r.order_id,
  r.customer_id,
  public.order_profile_name(r.order_id, r.customer_id) as customer_name,
  public.order_profile_phone(r.order_id, r.customer_id) as customer_phone,
  r.store_id,
  s.name as store_name,
  o.status as order_status,
  o.payment_status,
  o.total_amount,
  r.rating,
  r.comment,
  r.created_at,
  r.updated_at
from public.order_reviews r
join public.orders o on o.id = r.order_id
join public.stores s on s.id = r.store_id;

do $$
begin
  alter publication supabase_realtime add table public.order_reviews;
exception
  when duplicate_object then null;
end;
$$;
