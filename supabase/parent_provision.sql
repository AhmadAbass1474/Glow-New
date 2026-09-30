-- ولي الأمر ينشئ حساب الطفل ويربطه بنفسه.
-- شغّل هذا الملف مرة واحدة من Supabase → SQL Editor.

create or replace function public.attach_my_parent(p_parent_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;

  update public.children_profiles
  set parent_id = p_parent_id
  where id = auth.uid();

  if not found then
    raise exception 'child profile missing';
  end if;
end;
$$;

revoke all on function public.attach_my_parent(uuid) from public;
grant execute on function public.attach_my_parent(uuid) to authenticated;
