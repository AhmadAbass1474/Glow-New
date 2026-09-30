-- المرحلة الأولى: منظمة، معلم، طالب.
-- شغّل هذا الملف مرة واحدة من Supabase → SQL Editor.

create table if not exists public.organizations (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_teachers (
  id uuid primary key references auth.users (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.student_invites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  teacher_id uuid not null references public.organization_teachers (id) on delete cascade,
  name text not null,
  age int not null,
  code text not null unique,
  student_id uuid,
  created_at timestamptz not null default now()
);

alter table public.children_profiles
  add column if not exists organization_id uuid,
  add column if not exists teacher_id uuid;

alter table public.organizations enable row level security;
alter table public.organization_teachers enable row level security;
alter table public.student_invites enable row level security;

drop policy if exists organizations_select on public.organizations;
create policy organizations_select
on public.organizations
for select
to authenticated
using (
  id = auth.uid()
  or id in (
    select organization_id
    from public.organization_teachers
    where id = auth.uid()
  )
);

drop policy if exists organizations_insert on public.organizations;
create policy organizations_insert
on public.organizations
for insert
to authenticated
with check (id = auth.uid());

drop policy if exists organization_teachers_select on public.organization_teachers;
create policy organization_teachers_select
on public.organization_teachers
for select
to authenticated
using (
  id = auth.uid()
  or organization_id = auth.uid()
);

drop policy if exists organization_teachers_insert on public.organization_teachers;
create policy organization_teachers_insert
on public.organization_teachers
for insert
to authenticated
with check (id = auth.uid());

drop policy if exists student_invites_select on public.student_invites;
create policy student_invites_select
on public.student_invites
for select
to authenticated
using (
  teacher_id = auth.uid()
  or organization_id = auth.uid()
);

drop policy if exists student_invites_insert on public.student_invites;
create policy student_invites_insert
on public.student_invites
for insert
to authenticated
with check (
  teacher_id = auth.uid()
  and organization_id = (
    select organization_id
    from public.organization_teachers
    where id = auth.uid()
  )
);

drop policy if exists children_org_select on public.children_profiles;
create policy children_org_select
on public.children_profiles
for select
to authenticated
using (
  teacher_id = auth.uid()
  or organization_id = auth.uid()
);

drop policy if exists child_progress_org_select on public.child_progress;
create policy child_progress_org_select
on public.child_progress
for select
to authenticated
using (
  child_id in (
    select id
    from public.children_profiles
    where teacher_id = auth.uid()
      or organization_id = auth.uid()
  )
);

drop policy if exists organizations_update on public.organizations;
create policy organizations_update
on public.organizations
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists organization_teachers_update on public.organization_teachers;
create policy organization_teachers_update
on public.organization_teachers
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

do $$
begin
  if to_regclass('public.child_activity') is not null then
    execute 'drop policy if exists child_activity_org_select on public.child_activity';
    execute 'create policy child_activity_org_select on public.child_activity for select to authenticated using (child_id in (select id from public.children_profiles where teacher_id = auth.uid() or organization_id = auth.uid()))';
  end if;
end $$;

grant select, insert, update on public.organizations to authenticated;
grant select, insert, update on public.organization_teachers to authenticated;
grant select, insert on public.student_invites to authenticated;

create or replace function public.preview_student_invite(p_code text)
returns table (name text, age int)
language sql
security definer
set search_path = public
as $$
  select student_invites.name, student_invites.age
  from public.student_invites
  where code = p_code
    and student_id is null;
$$;

create or replace function public.claim_student_invite(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  invite public.student_invites%rowtype;
begin
  select *
  into invite
  from public.student_invites
  where code = p_code
    and student_id is null;

  if not found then
    raise exception 'invite not found';
  end if;

  update public.children_profiles
  set organization_id = invite.organization_id,
      teacher_id = invite.teacher_id,
      name = invite.name,
      age = invite.age
  where id = auth.uid();

  if not found then
    raise exception 'student profile missing';
  end if;

  update public.student_invites
  set student_id = auth.uid()
  where id = invite.id;
end;
$$;

revoke all on function public.preview_student_invite(text) from public;
revoke all on function public.claim_student_invite(text) from public;
grant execute on function public.preview_student_invite(text) to anon, authenticated;
grant execute on function public.claim_student_invite(text) to authenticated;
