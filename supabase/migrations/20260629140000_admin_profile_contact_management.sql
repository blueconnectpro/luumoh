create or replace function public.admin_update_profile_contact(
  p_user_id uuid,
  p_full_name text,
  p_phone text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only admins can update profile contact details';
  end if;

  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;

  update public.profiles
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), '')
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;
