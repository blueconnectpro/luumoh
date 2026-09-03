drop function if exists public.send_order_message(uuid, text);

create function public.send_order_message(
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
  v_order record;
  v_sender_name text;
  v_short_order text := left(p_order_id::text, 8);
  v_recipient_id uuid;
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

  select
    o.customer_id,
    o.store_id,
    o.rider_id,
    s.owner_id,
    s.name as store_name
  into v_order
  from public.orders o
  join public.stores s on s.id = o.store_id
  where o.id = p_order_id;

  select nullif(trim(full_name), '')
  into v_sender_name
  from public.profiles
  where id = auth.uid();

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
      and recipient_id <> auth.uid()
  loop
    perform public.create_user_notification(
      v_recipient_id,
      'order_message',
      'New order message',
      coalesce(v_sender_name, 'A Luumoh user') || ' sent a message on order #' || v_short_order || '.',
      jsonb_build_object(
        'order_id', p_order_id,
        'store_id', v_order.store_id,
        'message_id', v_message_id,
        'sender_id', auth.uid()
      ),
      auth.uid()
    );
  end loop;

  return v_message_id;
end;
$$;

grant execute on function public.send_order_message(uuid, text)
  to authenticated;
revoke execute on function public.send_order_message(uuid, text)
  from anon;

notify pgrst, 'reload schema';
