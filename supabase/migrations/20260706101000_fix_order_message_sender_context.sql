create or replace function public.order_message_sender_name(
  p_order_id uuid,
  p_sender_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(p.full_name), ''),
    case
      when exists (
        select 1
        from public.store_members sm
        join public.orders o on o.store_id = sm.store_id
        where o.id = p_order_id
          and sm.user_id = p_sender_id
      ) then (
        select s.name
        from public.orders o
        join public.stores s on s.id = o.store_id
        where o.id = p_order_id
      )
      else 'Luumoh user'
    end
  )
  from public.profiles p
  where p.id = p_sender_id
    and public.can_access_order(p_order_id)
$$;

create or replace function public.order_message_sender_role(
  p_order_id uuid,
  p_sender_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when o.customer_id = p_sender_id then 'customer'
    when o.rider_id = p_sender_id then 'rider'
    when exists (
      select 1
      from public.store_members sm
      where sm.store_id = o.store_id
        and sm.user_id = p_sender_id
    ) then 'store_admin'
    else coalesce((
      select p.role::text
      from public.profiles p
      where p.id = p_sender_id
    ), 'admin')
  end
  from public.orders o
  where o.id = p_order_id
    and public.can_access_order(p_order_id)
$$;

create or replace view public.order_message_summaries
with (security_invoker = true)
as
select
  om.id,
  om.order_id,
  om.sender_id,
  public.order_message_sender_name(om.order_id, om.sender_id) as sender_name,
  public.order_message_sender_role(om.order_id, om.sender_id) as sender_role,
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
grant execute on function public.order_message_sender_name(uuid, uuid)
  to authenticated;
grant execute on function public.order_message_sender_role(uuid, uuid)
  to authenticated;
revoke execute on function public.order_message_sender_name(uuid, uuid)
  from anon;
revoke execute on function public.order_message_sender_role(uuid, uuid)
  from anon;
