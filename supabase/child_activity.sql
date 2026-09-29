-- تقرير ولي الأمر اليومي.
-- شغّل هذا الملف مرة واحدة من Supabase → SQL Editor.

create table if not exists public.child_activity (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children_profiles (id) on delete cascade,
  kind text not null,
  title text not null default '',
  body text not null default '',
  mission_id text,
  question text,
  chosen_answer text,
  correct_answer text,
  is_correct boolean,
  stars int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists child_activity_child_created_idx
  on public.child_activity (child_id, created_at desc);

alter table public.child_activity enable row level security;

drop policy if exists child_activity_insert on public.child_activity;
create policy child_activity_insert
on public.child_activity
for insert
to authenticated
with check (child_id = auth.uid());

drop policy if exists child_activity_select on public.child_activity;
create policy child_activity_select
on public.child_activity
for select
to authenticated
using (
  child_id = auth.uid()
  or exists (
    select 1
    from public.children_profiles
    where id = child_activity.child_id
      and parent_id = auth.uid()
  )
);

grant select, insert on public.child_activity to authenticated;
