create or replace function public.notify_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short_order text := left(new.id::text, 8);
  v_payment_type text;
  v_payment_title text;
  v_payment_body text;
begin
  if old.payment_status is distinct from new.payment_status
     and new.payment_status = 'paid' then
    perform public.create_user_notification(
      new.customer_id,
      'payment_success',
      'Payment successful',
      'Payment for order #' || v_short_order || ' was received.',
      jsonb_build_object(
        'audience', 'customer',
        'order_id', new.id,
        'store_id', new.store_id,
        'payment_status', new.payment_status
      )
    );

    perform public.notify_store_users(
      new.store_id,
      'order_paid',
      'New paid order',
      'Order #' || v_short_order || ' is paid and ready to prepare.',
      jsonb_build_object('order_id', new.id, 'store_id', new.store_id)
    );

    perform public.notify_admin_users(
      'order_paid',
      'Order paid',
      'Order #' || v_short_order || ' has been paid.',
      jsonb_build_object('order_id', new.id, 'store_id', new.store_id)
    );
  end if;

  if old.payment_status is distinct from new.payment_status
     and new.payment_status in ('failed', 'expired', 'refunded') then
    v_payment_type := case new.payment_status
      when 'failed' then 'payment_failed'
      when 'expired' then 'payment_expired'
      else 'payment_refunded'
    end;
    v_payment_title := case new.payment_status
      when 'failed' then 'Payment failed'
      when 'expired' then 'Payment expired'
      else 'Payment refunded'
    end;
    v_payment_body := case new.payment_status
      when 'failed' then 'Payment for order #' || v_short_order || ' failed.'
      when 'expired' then 'Payment for order #' || v_short_order || ' expired.'
      else 'Payment for order #' || v_short_order || ' was marked refunded.'
    end;

    perform public.create_user_notification(
      new.customer_id,
      v_payment_type,
      v_payment_title,
      v_payment_body,
      jsonb_build_object(
        'audience', 'customer',
        'order_id', new.id,
        'store_id', new.store_id,
        'payment_status', new.payment_status
      )
    );

    perform public.notify_admin_users(
      v_payment_type,
      v_payment_title,
      v_payment_body,
      jsonb_build_object(
        'order_id', new.id,
        'store_id', new.store_id,
        'payment_status', new.payment_status
      )
    );
  end if;

  if old.status is distinct from new.status then
    perform public.create_user_notification(
      new.customer_id,
      'order_status',
      'Order status updated',
      'Order #' || v_short_order || ' is now ' || replace(new.status::text, '_', ' ') || '.',
      jsonb_build_object(
        'audience', 'customer',
        'order_id', new.id,
        'store_id', new.store_id,
        'status', new.status
      )
    );

    if new.rider_id is not null
       and new.status in ('cancelled', 'ready_for_pickup') then
      perform public.create_user_notification(
        new.rider_id,
        'order_status',
        case
          when new.status = 'ready_for_pickup' then 'Pickup ready'
          else 'Assigned order updated'
        end,
        'Order #' || v_short_order || ' is now ' || replace(new.status::text, '_', ' ') || '.',
        jsonb_build_object(
          'audience', 'rider',
          'order_id', new.id,
          'store_id', new.store_id,
          'status', new.status
        )
      );
    end if;

    if new.status in ('out_for_delivery', 'delivered', 'cancelled') then
      perform public.notify_store_users(
        new.store_id,
        'order_status',
        'Order status updated',
        'Order #' || v_short_order || ' is now ' || replace(new.status::text, '_', ' ') || '.',
        jsonb_build_object(
          'order_id', new.id,
          'store_id', new.store_id,
          'status', new.status
        )
      );
    end if;
  end if;

  if old.rider_id is distinct from new.rider_id and new.rider_id is not null then
    perform public.create_user_notification(
      new.rider_id,
      'rider_assigned',
      'New delivery assigned',
      'Order #' || v_short_order || ' has been assigned to you.',
      jsonb_build_object(
        'audience', 'rider',
        'order_id', new.id,
        'store_id', new.store_id,
        'rider_id', new.rider_id
      )
    );

    perform public.create_user_notification(
      new.customer_id,
      'rider_assigned',
      'Rider assigned',
      'A rider has been assigned to order #' || v_short_order || '.',
      jsonb_build_object(
        'audience', 'customer',
        'order_id', new.id,
        'store_id', new.store_id,
        'rider_id', new.rider_id
      )
    );

    perform public.notify_store_users(
      new.store_id,
      'rider_assigned',
      'Rider assigned',
      'A rider has been assigned to order #' || v_short_order || '.',
      jsonb_build_object(
        'order_id', new.id,
        'store_id', new.store_id,
        'rider_id', new.rider_id
      )
    );
  end if;

  if old.eta_minutes is distinct from new.eta_minutes
     and new.eta_minutes is not null then
    perform public.create_user_notification(
      new.customer_id,
      'eta_updated',
      'ETA updated',
      'Your rider ETA for order #' || v_short_order || ' is ' || new.eta_minutes || ' min.',
      jsonb_build_object(
        'audience', 'customer',
        'order_id', new.id,
        'store_id', new.store_id,
        'eta_minutes', new.eta_minutes
      )
    );
  end if;

  return new;
end;
$$;

update public.user_notifications notification
set data = coalesce(notification.data, '{}'::jsonb) ||
  jsonb_build_object('audience', 'hidden')
from public.profiles profile
where profile.id = notification.user_id
  and profile.role = 'rider'
  and lower(notification.type) like 'payment\_%' escape '\';

notify pgrst, 'reload schema';
