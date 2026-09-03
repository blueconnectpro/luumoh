do $$
begin
  alter publication supabase_realtime add table public.store_members;
exception
  when duplicate_object then null;
end;
$$;
