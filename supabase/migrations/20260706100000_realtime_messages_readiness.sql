create table if not exists public.order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists order_messages_order_created_idx
  on public.order_messages(order_id, created_at desc);

create index if not exists order_messages_sender_created_idx
  on public.order_messages(sender_id, created_at desc);

alter table public.order_messages enable row level security;

create or replace function public.can_access_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order_id
      and (
        o.customer_id = auth.uid()
        or o.rider_id = auth.uid()
        or public.is_store_member(o.store_id)
        or public.is_admin()
      )
  );
$$;

drop policy if exists "order messages scoped read" on public.order_messages;
create policy "order messages scoped read" on public.order_messages
  for select using (public.can_access_order(order_id));

create or replace view public.order_message_summaries
with (security_invoker = true)
as
select
  om.id,
  om.order_id,
  om.sender_id,
  public.order_profile_name(om.order_id, om.sender_id) as sender_name,
  case
    when om.sender_id = o.customer_id then 'customer'
    when om.sender_id = o.rider_id then 'rider'
    when exists (
      select 1
      from public.store_members sm
      where sm.store_id = o.store_id
        and sm.user_id = om.sender_id
    ) then 'store_admin'
    else 'admin'
  end as sender_role,
  om.message,
  om.created_at,
  o.customer_id,
  o.store_id,
  s.name as store_name,
  o.rider_id
from public.order_messages om
join public.orders o on o.id = om.order_id
join public.stores s on s.id = o.store_id;

grant select on public.order_message_summaries to authenticated;

create or replace function public.send_order_message(
  p_order_id uuid,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.can_access_order(p_order_id) then
    raise exception 'You cannot message on this order';
  end if;

  if length(trim(coalesce(p_message, ''))) < 1 then
    raise exception 'Message is required';
  end if;

  if length(trim(p_message)) > 1000 then
    raise exception 'Message is too long';
  end if;

  insert into public.order_messages (
    order_id,
    sender_id,
    message
  )
  values (
    p_order_id,
    auth.uid(),
    trim(p_message)
  )
  returning id into v_message_id;

  return v_message_id;
end;
$$;

create or replace function public.notify_order_message_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order record;
  v_sender_name text;
  v_short_order text := left(new.order_id::text, 8);
  v_recipient_id uuid;
begin
  select
    o.customer_id,
    o.store_id,
    o.rider_id,
    s.owner_id,
    s.name as store_name
  into v_order
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = new.order_id;

  select nullif(trim(full_name), '')
  into v_sender_name
  from public.profiles
  where id = new.sender_id;

  for v_recipient_id in
    select distinct recipient_id
    from (
      select v_order.customer_id as recipient_id
      union all
      select v_order.rider_id
      union all
      select v_order.owner_id
      union all
      select sm.user_id
      from public.store_members sm
      where sm.store_id = v_order.store_id
      union all
      select p.id
      from public.profiles p
      where p.role = 'admin'
    ) recipients
    where recipient_id is not null
      and recipient_id <> new.sender_id
  loop
    perform public.create_user_notification(
      v_recipient_id,
      'order_message',
      'New order message',
      coalesce(v_sender_name, 'A Luumoh user') || ' sent a message on order #' || v_short_order || '.',
      jsonb_build_object(
        'order_id', new.order_id,
        'store_id', v_order.store_id,
        'message_id', new.id,
        'sender_id', new.sender_id
      ),
      new.sender_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists order_messages_notify_insert on public.order_messages;
create trigger order_messages_notify_insert
after insert on public.order_messages
for each row execute function public.notify_order_message_insert();

create or replace function public.admin_realtime_readiness()
returns table (
  table_name text,
  in_realtime boolean,
  rls_enabled boolean,
  policy_count integer,
  risk text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only admins can run realtime readiness checks';
  end if;

  return query
  with required_tables(table_name) as (
    values
      ('stores'),
      ('products'),
      ('inventory_items'),
      ('inventory_reservations'),
      ('orders'),
      ('order_items'),
      ('payments'),
      ('delivery_events'),
      ('profiles'),
      ('store_members'),
      ('customer_addresses'),
      ('rider_availability'),
      ('order_issues'),
      ('user_notifications'),
      ('order_reviews'),
      ('store_settlements'),
      ('rider_settlements'),
      ('payment_webhook_events'),
      ('order_messages')
  )
  select
    rt.table_name::text,
    exists (
      select 1
      from pg_publication_tables pt
      where pt.pubname = 'supabase_realtime'
        and pt.schemaname = 'public'
        and pt.tablename = rt.table_name
    ) as in_realtime,
    coalesce(c.relrowsecurity, false) as rls_enabled,
    count(p.polname)::integer as policy_count,
    case
      when not exists (
        select 1
        from pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = rt.table_name
      ) then 'error'
      when not coalesce(c.relrowsecurity, false) then 'error'
      when count(p.polname) = 0 then 'warning'
      else 'ok'
    end as risk
  from required_tables rt
  left join pg_class c
    on c.relname = rt.table_name
   and c.relnamespace = 'public'::regnamespace
  left join pg_policy p on p.polrelid = c.oid
  group by rt.table_name, c.relrowsecurity
  order by
    case
      when not exists (
        select 1
        from pg_publication_tables pt
        where pt.pubname = 'supabase_realtime'
          and pt.schemaname = 'public'
          and pt.tablename = rt.table_name
      ) then 0
      when not coalesce(c.relrowsecurity, false) then 1
      when count(p.polname) = 0 then 2
      else 3
    end,
    rt.table_name;
end;
$$;

grant execute on function public.can_access_order(uuid)
  to authenticated;
revoke execute on function public.can_access_order(uuid)
  from anon;
grant execute on function public.send_order_message(uuid, text)
  to authenticated;
revoke execute on function public.send_order_message(uuid, text)
  from anon;
revoke execute on function public.notify_order_message_insert()
  from anon, authenticated;
revoke execute on function public.admin_realtime_readiness()
  from anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.order_messages;
exception
  when duplicate_object then null;
end;
$$;
