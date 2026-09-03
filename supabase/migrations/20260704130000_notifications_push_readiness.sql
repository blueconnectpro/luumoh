create table if not exists public.notification_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('android', 'ios', 'web', 'test')),
  provider text not null default 'fcm' check (provider in ('fcm', 'apns', 'web_push', 'test')),
  device_token text not null,
  device_name text,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, provider, device_token)
);

create index if not exists notification_devices_user_active_idx
  on public.notification_devices(user_id)
  where is_active;

alter table public.notification_devices enable row level security;

drop policy if exists "notification devices read own" on public.notification_devices;
create policy "notification devices read own" on public.notification_devices
  for select using (user_id = auth.uid());

create table if not exists public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.user_notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.notification_devices(id) on delete set null,
  channel text not null default 'push' check (channel in ('push')),
  provider text not null check (provider in ('fcm', 'apns', 'web_push', 'test')),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed', 'skipped')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (notification_id, device_id, channel)
);

create index if not exists notification_deliveries_pending_idx
  on public.notification_deliveries(created_at)
  where status = 'pending';

create index if not exists notification_deliveries_user_created_idx
  on public.notification_deliveries(user_id, created_at desc);

alter table public.notification_deliveries enable row level security;

drop policy if exists "notification deliveries read own" on public.notification_deliveries;
create policy "notification deliveries read own" on public.notification_deliveries
  for select using (user_id = auth.uid());

create or replace function public.register_notification_device(
  p_platform text,
  p_provider text,
  p_device_token text,
  p_device_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_device_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_platform not in ('android', 'ios', 'web', 'test') then
    raise exception 'Unsupported notification platform %', p_platform;
  end if;

  if p_provider not in ('fcm', 'apns', 'web_push', 'test') then
    raise exception 'Unsupported notification provider %', p_provider;
  end if;

  if length(trim(coalesce(p_device_token, ''))) < 8 then
    raise exception 'Device token is required';
  end if;

  insert into public.notification_devices (
    user_id,
    platform,
    provider,
    device_token,
    device_name,
    is_active,
    last_seen_at,
    updated_at
  )
  values (
    auth.uid(),
    p_platform,
    p_provider,
    trim(p_device_token),
    nullif(trim(coalesce(p_device_name, '')), ''),
    true,
    now(),
    now()
  )
  on conflict (user_id, provider, device_token) do update
  set platform = excluded.platform,
      device_name = excluded.device_name,
      is_active = true,
      last_seen_at = now(),
      updated_at = now()
  returning id into v_device_id;

  return v_device_id;
end;
$$;

create or replace function public.unregister_notification_device(
  p_device_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notification_devices
  set is_active = false,
      updated_at = now()
  where id = p_device_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.queue_notification_push_delivery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_deliveries (
    notification_id,
    user_id,
    device_id,
    provider,
    payload
  )
  select
    new.id,
    new.user_id,
    nd.id,
    nd.provider,
    jsonb_build_object(
      'notification_id', new.id,
      'type', new.type,
      'title', new.title,
      'body', new.body,
      'data', new.data,
      'created_at', new.created_at
    )
  from public.notification_devices nd
  where nd.user_id = new.user_id
    and nd.is_active = true
  on conflict (notification_id, device_id, channel) do nothing;

  return new;
end;
$$;

drop trigger if exists user_notifications_queue_push_delivery on public.user_notifications;
create trigger user_notifications_queue_push_delivery
after insert on public.user_notifications
for each row execute function public.queue_notification_push_delivery();

create or replace function public.notify_store_member_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_name text;
begin
  select name into v_store_name
  from public.stores
  where id = new.store_id;

  if tg_op = 'INSERT' then
    perform public.create_user_notification(
      new.user_id,
      'store_assigned',
      'Store access granted',
      'You can now manage ' || coalesce(v_store_name, 'this store') || '.',
      jsonb_build_object(
        'store_id', new.store_id,
        'can_manage_inventory', new.can_manage_inventory,
        'can_manage_orders', new.can_manage_orders
      ),
      auth.uid()
    );
  elsif old.can_manage_inventory is distinct from new.can_manage_inventory
     or old.can_manage_orders is distinct from new.can_manage_orders then
    perform public.create_user_notification(
      new.user_id,
      'store_permissions_updated',
      'Store permissions updated',
      'Your permissions for ' || coalesce(v_store_name, 'this store') || ' were updated.',
      jsonb_build_object(
        'store_id', new.store_id,
        'can_manage_inventory', new.can_manage_inventory,
        'can_manage_orders', new.can_manage_orders
      ),
      auth.uid()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists store_members_notify_assignment on public.store_members;
create trigger store_members_notify_assignment
after insert or update on public.store_members
for each row execute function public.notify_store_member_assignment();

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

    if new.rider_id is not null then
      perform public.create_user_notification(
        new.rider_id,
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
  end if;

  if old.status is distinct from new.status then
    perform public.create_user_notification(
      new.customer_id,
      'order_status',
      'Order status updated',
      'Order #' || v_short_order || ' is now ' || replace(new.status::text, '_', ' ') || '.',
      jsonb_build_object(
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
        'Assigned order updated',
        'Order #' || v_short_order || ' is now ' || replace(new.status::text, '_', ' ') || '.',
        jsonb_build_object(
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
        'order_id', new.id,
        'store_id', new.store_id,
        'eta_minutes', new.eta_minutes
      )
    );
  end if;

  return new;
end;
$$;

revoke execute on function public.register_notification_device(text, text, text, text)
  from anon;
revoke execute on function public.unregister_notification_device(uuid)
  from anon;
revoke execute on function public.queue_notification_push_delivery()
  from anon, authenticated;
revoke execute on function public.notify_store_member_assignment()
  from anon, authenticated;
revoke execute on function public.notify_order_update()
  from anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.notification_deliveries;
exception
  when duplicate_object then null;
end;
$$;
