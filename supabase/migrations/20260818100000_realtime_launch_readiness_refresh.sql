do $$
begin
  alter publication supabase_realtime add table public.inventory_movements;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.promo_codes;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.platform_fee_settings;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

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
      ('inventory_movements'),
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
      ('notification_deliveries'),
      ('order_reviews'),
      ('product_reviews'),
      ('rider_reviews'),
      ('promo_codes'),
      ('platform_fee_settings'),
      ('store_settlements'),
      ('rider_settlements'),
      ('payment_webhook_events'),
      ('order_messages'),
      ('rider_location_updates'),
      ('store_opening_hours'),
      ('store_employee_activities'),
      ('store_staff_presence')
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

revoke execute on function public.admin_realtime_readiness()
  from anon, authenticated;
