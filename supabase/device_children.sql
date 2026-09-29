-- حسابات الأطفال على نفس الجهاز.
-- شغّل هذا الملف مرة واحدة من Supabase → SQL Editor.

create table if not exists public.device_children (
  child_id uuid primary key references public.children_profiles (id) on delete cascade,
  device_id text not null,
  slot text not null default '',
  name text not null,
  age int not null default 0,
  avatar_url text not null default '',
  child_code text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists device_children_device_id_idx
  on public.device_children (device_id);

alter table public.device_children enable row level security;

create or replace function public.current_device_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select device_id
  from public.device_children
  where child_id = auth.uid()
  limit 1;
$$;

revoke all on function public.current_device_id() from public;
grant execute on function public.current_device_id() to authenticated;

drop policy if exists device_children_select on public.device_children;
create policy device_children_select
on public.device_children
for select
to authenticated
using (
  child_id = auth.uid()
  or device_id = public.current_device_id()
);

drop policy if exists device_children_insert on public.device_children;
create policy device_children_insert
on public.device_children
for insert
to authenticated
with check (child_id = auth.uid());

drop policy if exists device_children_update on public.device_children;
create policy device_children_update
on public.device_children
for update
to authenticated
using (child_id = auth.uid())
with check (child_id = auth.uid());

grant select, insert, update on public.device_children to authenticated;
