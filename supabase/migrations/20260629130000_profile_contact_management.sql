drop policy if exists "profiles update own or admin" on public.profiles;

create policy "profiles admin update" on public.profiles
  for update using (public.is_admin())
  with check (public.is_admin());

create or replace function public.update_my_profile(
  p_full_name text,
  p_phone text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Full name is required';
  end if;

  update public.profiles
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), '')
  where id = auth.uid();

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;
