create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists user_notifications_user_created_idx
  on public.user_notifications(user_id, created_at desc);

create index if not exists user_notifications_user_unread_idx
  on public.user_notifications(user_id)
  where read_at is null;

alter table public.user_notifications enable row level security;

drop policy if exists "notifications read own" on public.user_notifications;
create policy "notifications read own" on public.user_notifications
  for select using (user_id = auth.uid());

drop policy if exists "notifications update own read state" on public.user_notifications;

create or replace function public.create_user_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text default '',
  p_data jsonb default '{}'::jsonb,
  p_actor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_notification_id uuid;
begin
  if p_user_id is null then
    return null;
  end if;

  insert into public.user_notifications (
    user_id,
    actor_id,
    type,
    title,
    body,
    data
  )
  values (
    p_user_id,
    p_actor_id,
    trim(coalesce(p_type, 'general')),
    trim(coalesce(p_title, 'Luumoh update')),
    trim(coalesce(p_body, '')),
    coalesce(p_data, '{}'::jsonb)
  )
  returning id into v_notification_id;

  return v_notification_id;
end;
$$;

create or replace function public.notify_store_users(
  p_store_id uuid,
  p_type text,
  p_title text,
  p_body text default '',
  p_data jsonb default '{}'::jsonb,
  p_actor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct user_id
    from public.store_members
    where store_id = p_store_id
    union
    select owner_id
    from public.stores
    where id = p_store_id
      and owner_id is not null
  loop
    perform public.create_user_notification(
      v_user_id,
      p_type,
      p_title,
      p_body,
      p_data,
      p_actor_id
    );
  end loop;
end;
$$;

create or replace function public.notify_admin_users(
  p_type text,
  p_title text,
  p_body text default '',
  p_data jsonb default '{}'::jsonb,
  p_actor_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select id
    from public.profiles
    where role = 'admin'
  loop
    perform public.create_user_notification(
      v_user_id,
      p_type,
      p_title,
      p_body,
      p_data,
      p_actor_id
    );
  end loop;
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id
    and user_id = auth.uid();
end;
$$;

create or replace function public.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notifications
  set read_at = coalesce(read_at, now())
  where user_id = auth.uid()
    and read_at is null;
end;
$$;

revoke execute on function public.create_user_notification(
  uuid,
  text,
  text,
  text,
  jsonb,
  uuid
) from anon, authenticated;

revoke execute on function public.notify_store_users(
  uuid,
  text,
  text,
  text,
  jsonb,
  uuid
) from anon, authenticated;

revoke execute on function public.notify_admin_users(
  text,
  text,
  text,
  jsonb,
  uuid
) from anon, authenticated;

create or replace function public.notify_order_issue_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_name text;
  v_short_order text;
begin
  select name into v_store_name
  from public.stores
  where id = new.store_id;

  v_short_order := left(new.order_id::text, 8);

  perform public.create_user_notification(
    new.customer_id,
    'support_issue_created',
    'Support issue received',
    'We received your issue for order #' || v_short_order || '.',
    jsonb_build_object(
      'issue_id', new.id,
      'order_id', new.order_id,
      'store_id', new.store_id,
      'status', new.status
    )
  );

  perform public.notify_store_users(
    new.store_id,
    'support_issue_created',
    'Customer reported an issue',
    coalesce(v_store_name, 'Store') || ' has a new issue on order #' || v_short_order || '.',
    jsonb_build_object(
      'issue_id', new.id,
      'order_id', new.order_id,
      'store_id', new.store_id,
      'status', new.status
    )
  );

  perform public.notify_admin_users(
    'support_issue_created',
    'New support issue',
    coalesce(v_store_name, 'Store') || ' has a new issue on order #' || v_short_order || '.',
    jsonb_build_object(
      'issue_id', new.id,
      'order_id', new.order_id,
      'store_id', new.store_id,
      'status', new.status
    )
  );

  return new;
end;
$$;

create or replace function public.notify_order_issue_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status is distinct from new.status
     or old.admin_note is distinct from new.admin_note then
    perform public.create_user_notification(
      new.customer_id,
      'support_issue_updated',
      'Support issue updated',
      'Your issue for order #' || left(new.order_id::text, 8) ||
        ' is now ' || replace(new.status, '_', ' ') || '.',
      jsonb_build_object(
        'issue_id', new.id,
        'order_id', new.order_id,
        'store_id', new.store_id,
        'status', new.status
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists order_issues_notify_insert on public.order_issues;
create trigger order_issues_notify_insert
after insert on public.order_issues
for each row execute function public.notify_order_issue_insert();

drop trigger if exists order_issues_notify_update on public.order_issues;
create trigger order_issues_notify_update
after update on public.order_issues
for each row execute function public.notify_order_issue_update();

create or replace function public.notify_order_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_short_order text := left(new.id::text, 8);
begin
  if old.payment_status is distinct from new.payment_status
     and new.payment_status = 'paid' then
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

drop trigger if exists orders_notify_update on public.orders;
create trigger orders_notify_update
after update on public.orders
for each row execute function public.notify_order_update();

revoke execute on function public.notify_order_issue_insert()
  from anon, authenticated;
revoke execute on function public.notify_order_issue_update()
  from anon, authenticated;
revoke execute on function public.notify_order_update()
  from anon, authenticated;

do $$
begin
  alter publication supabase_realtime add table public.user_notifications;
exception
  when duplicate_object then null;
end;
$$;
