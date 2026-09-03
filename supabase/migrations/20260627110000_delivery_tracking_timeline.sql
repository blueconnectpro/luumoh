create or replace function public.accept_rider_order(
  p_order_id uuid,
  p_eta_minutes integer default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_profile_role() not in ('rider', 'admin') then
    raise exception 'Only riders can accept orders';
  end if;

  if p_eta_minutes is not null and p_eta_minutes < 0 then
    raise exception 'ETA cannot be negative';
  end if;

  update public.orders
  set rider_id = auth.uid(),
      status = 'out_for_delivery',
      eta_minutes = p_eta_minutes,
      eta_updated_at = case when p_eta_minutes is null then eta_updated_at else now() end
  where id = p_order_id
    and rider_id is null
    and payment_status = 'paid'
    and status = 'ready_for_pickup';

  if not found then
    raise exception 'Order is not available';
  end if;

  insert into public.delivery_events(order_id, rider_id, status, eta_minutes, note)
  values (
    p_order_id,
    auth.uid(),
    'out_for_delivery',
    p_eta_minutes,
    coalesce(p_note, 'Rider accepted order')
  );
end;
$$;
