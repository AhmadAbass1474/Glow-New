-- نقل حساب طفل من هاتف إلى آخر.
-- شغّل هذا الملف مرة واحدة من Supabase → SQL Editor بعد device_children.sql.

create table if not exists public.account_transfers (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children_profiles (id) on delete cascade,
  code text not null unique,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists account_transfers_code_idx
  on public.account_transfers (code);

alter table public.account_transfers enable row level security;

drop policy if exists account_transfers_insert on public.account_transfers;
create policy account_transfers_insert
on public.account_transfers
for insert
to authenticated
with check (child_id = auth.uid());

drop policy if exists account_transfers_select on public.account_transfers;
create policy account_transfers_select
on public.account_transfers
for select
to authenticated
using (child_id = auth.uid());

grant select, insert on public.account_transfers to authenticated;

create or replace function public.claim_account_transfer(
  p_code text,
  p_device_id text,
  p_slot text
) returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  transfer public.account_transfers%rowtype;
  profile public.children_profiles%rowtype;
  new_email text;
  new_password text;
begin
  if p_code is null or p_code !~ '^[A-Za-z0-9_-]{20,80}$' then
    raise exception 'invalid_code';
  end if;
  if p_device_id is null
     or length(p_device_id) < 4
     or length(p_device_id) > 128
     or p_device_id ~ '[[:space:]@]' then
    raise exception 'invalid_device';
  end if;
  if p_slot is null or p_slot !~ '^[a-z0-9]{0,16}$' then
    raise exception 'invalid_slot';
  end if;

  select * into transfer
  from public.account_transfers
  where code = p_code
  for update;

  if not found or transfer.consumed_at is not null or transfer.expires_at < now() then
    raise exception 'expired';
  end if;

  if p_slot = '' then
    new_email := p_device_id || '@glow.app';
    new_password := p_device_id || '_secret_glow_2026';
  else
    new_email := p_device_id || '.' || p_slot || '@glow.app';
    new_password := p_device_id || '.' || p_slot || '_secret_glow_2026';
  end if;

  if exists (
    select 1 from auth.users
    where email = new_email and id <> transfer.child_id
  ) then
    raise exception 'slot_taken';
  end if;

  update auth.users
  set email = new_email,
      encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf', 6)),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      updated_at = now()
  where id = transfer.child_id;

  update auth.identities
  set provider_id = new_email,
      identity_data = jsonb_build_object(
        'sub', transfer.child_id::text,
        'email', new_email,
        'email_verified', true
      ),
      updated_at = now()
  where user_id = transfer.child_id and provider = 'email';

  select * into profile
  from public.children_profiles
  where id = transfer.child_id;

  insert into public.device_children (
    child_id, device_id, slot, name, age, avatar_url, child_code
  ) values (
    profile.id, p_device_id, p_slot, profile.name, profile.age,
    coalesce(profile.avatar_url, ''), profile.child_code
  )
  on conflict (child_id) do update
  set device_id = excluded.device_id,
      slot = excluded.slot,
      name = excluded.name,
      age = excluded.age,
      avatar_url = excluded.avatar_url,
      child_code = excluded.child_code;

  update public.account_transfers
  set consumed_at = now()
  where id = transfer.id;

  return json_build_object(
    'id', profile.id,
    'name', profile.name,
    'age', profile.age,
    'avatar_url', coalesce(profile.avatar_url, ''),
    'child_code', profile.child_code
  );
end;
$$;

revoke all on function public.claim_account_transfer(text, text, text) from public;
grant execute on function public.claim_account_transfer(text, text, text) to anon, authenticated;
