create table if not exists public.order_issues (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  category text not null,
  message text not null,
  status text not null default 'open' check (
    status in ('open', 'in_review', 'resolved', 'closed')
  ),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists order_issues_touch_updated_at on public.order_issues;

create trigger order_issues_touch_updated_at
before update on public.order_issues
for each row execute function public.touch_updated_at();

alter table public.order_issues enable row level security;

drop policy if exists "order issues scoped read" on public.order_issues;
create policy "order issues scoped read" on public.order_issues
  for select using (
    customer_id = auth.uid()
    or public.is_store_member(store_id)
    or public.is_admin()
  );

drop policy if exists "order issues customer insert" on public.order_issues;
create policy "order issues customer insert" on public.order_issues
  for insert with check (
    customer_id = auth.uid()
    and exists (
      select 1
      from public.orders o
      where o.id = order_id
        and o.customer_id = auth.uid()
        and o.store_id = store_id
    )
  );

drop policy if exists "order issues admin update" on public.order_issues;
create policy "order issues admin update" on public.order_issues
  for update using (public.is_admin())
  with check (public.is_admin());

create or replace function public.customer_create_order_issue(
  p_order_id uuid,
  p_category text,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_issue_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select id, customer_id, store_id
  into v_order
  from public.orders
  where id = p_order_id
    and customer_id = auth.uid();

  if not found then
    raise exception 'Order not found';
  end if;

  if length(trim(coalesce(p_category, ''))) = 0 then
    raise exception 'Issue category is required';
  end if;

  if length(trim(coalesce(p_message, ''))) < 5 then
    raise exception 'Tell us a little more about the issue';
  end if;

  insert into public.order_issues (
    order_id,
    customer_id,
    store_id,
    category,
    message
  )
  values (
    p_order_id,
    v_order.customer_id,
    v_order.store_id,
    trim(p_category),
    trim(p_message)
  )
  returning id into v_issue_id;

  return v_issue_id;
end;
$$;

create or replace function public.admin_update_order_issue(
  p_issue_id uuid,
  p_status text,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can update order issues';
  end if;

  if p_status not in ('open', 'in_review', 'resolved', 'closed') then
    raise exception 'Invalid issue status';
  end if;

  update public.order_issues
  set status = p_status,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), '')
  where id = p_issue_id;

  if not found then
    raise exception 'Issue not found';
  end if;
end;
$$;

create or replace view public.order_issue_summaries
with (security_invoker = true)
as
select
  oi.id,
  oi.order_id,
  oi.customer_id,
  public.order_profile_name(oi.order_id, oi.customer_id) as customer_name,
  public.order_profile_phone(oi.order_id, oi.customer_id) as customer_phone,
  oi.store_id,
  s.name as store_name,
  o.status as order_status,
  o.payment_status,
  o.total_amount,
  oi.category,
  oi.message,
  oi.status,
  oi.admin_note,
  oi.created_at,
  oi.updated_at
from public.order_issues oi
join public.orders o on o.id = oi.order_id
join public.stores s on s.id = oi.store_id;

do $$
begin
  alter publication supabase_realtime add table public.order_issues;
exception
  when duplicate_object then null;
end;
$$;
