create or replace function public.delete_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_notifications
  where id = p_notification_id
    and user_id = auth.uid();
end;
$$;

grant execute on function public.delete_notification(uuid) to authenticated;

notify pgrst, 'reload schema';
