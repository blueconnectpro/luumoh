create or replace function public.notification_audience_for_user(
  p_user_id uuid,
  p_type text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_type text := lower(trim(coalesce(p_type, '')));
begin
  select role::text into v_role
  from public.profiles
  where id = p_user_id;

  if v_role = 'admin' then
    return 'admin';
  elsif v_role = 'rider' then
    return 'rider';
  elsif v_role = 'store_admin' then
    return 'store';
  end if;

  if v_type like 'admin_%' or v_type like 'settlement_%' then
    return 'admin';
  elsif v_type like 'store_%'
     or v_type in ('order_paid', 'review_created', 'store_assigned', 'store_permissions_updated') then
    return 'store';
  elsif v_type like 'rider_%'
     or v_type in ('delivery_assigned', 'ready_for_pickup') then
    return 'rider';
  else
    return 'customer';
  end if;
end;
$$;

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
  v_data jsonb := coalesce(p_data, '{}'::jsonb);
  v_type text := trim(coalesce(p_type, 'general'));
  v_audience text;
begin
  if p_user_id is null then
    return null;
  end if;

  v_audience := coalesce(
    nullif(trim(v_data->>'audience'), ''),
    public.notification_audience_for_user(p_user_id, v_type)
  );
  v_data := v_data || jsonb_build_object('audience', v_audience);

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
    v_type,
    trim(coalesce(p_title, 'Luumoh update')),
    trim(coalesce(p_body, '')),
    v_data
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
  v_data jsonb := coalesce(p_data, '{}'::jsonb) ||
    jsonb_build_object('audience', 'store');
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
      v_data,
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
  v_data jsonb := coalesce(p_data, '{}'::jsonb) ||
    jsonb_build_object('audience', 'admin');
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
      v_data,
      p_actor_id
    );
  end loop;
end;
$$;

create or replace function public.user_notifications_set_audience()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.data := coalesce(new.data, '{}'::jsonb);
  if nullif(trim(new.data->>'audience'), '') is null then
    new.data := new.data || jsonb_build_object(
      'audience',
      public.notification_audience_for_user(new.user_id, new.type)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists user_notifications_set_audience on public.user_notifications;
create trigger user_notifications_set_audience
before insert or update on public.user_notifications
for each row execute function public.user_notifications_set_audience();

update public.user_notifications notification
set data = coalesce(notification.data, '{}'::jsonb) ||
  jsonb_build_object(
    'audience',
    public.notification_audience_for_user(notification.user_id, notification.type)
  )
where nullif(trim(coalesce(notification.data->>'audience', '')), '') is null;

revoke execute on function public.notification_audience_for_user(uuid, text)
  from anon, authenticated;
revoke execute on function public.user_notifications_set_audience()
  from anon, authenticated;
