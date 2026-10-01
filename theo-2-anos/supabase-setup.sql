-- Banco do convite Theo 2 anos
-- Rode este arquivo no SQL Editor do Supabase.

create extension if not exists pgcrypto;

create table if not exists public.rsvps (
  id uuid primary key default gen_random_uuid(),
  device_id text unique not null,
  name text not null,
  status text not null check (status in ('sim','talvez','nao')),
  adults integer not null default 1 check (adults between 0 and 10),
  children integer not null default 0 check (children between 0 and 10),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  access_count integer not null default 1
);

alter table public.rsvps enable row level security;

revoke all on table public.rsvps from anon;
grant select on table public.rsvps to authenticated;

drop policy if exists "authenticated can read rsvps" on public.rsvps;
create policy "authenticated can read rsvps"
on public.rsvps
for select
to authenticated
using (true);

create or replace function public.submit_rsvp(
  p_device_id text,
  p_name text,
  p_status text,
  p_adults integer default 1,
  p_children integer default 0,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if length(trim(coalesce(p_name,''))) < 1 or length(p_name) > 80 then
    raise exception 'invalid name';
  end if;
  if p_status not in ('sim','talvez','nao') then
    raise exception 'invalid status';
  end if;
  if p_adults < 0 or p_adults > 10 or p_children < 0 or p_children > 10 then
    raise exception 'invalid party size';
  end if;

  insert into public.rsvps(device_id,name,status,adults,children,note)
  values (p_device_id,trim(p_name),p_status,p_adults,p_children,nullif(trim(coalesce(p_note,'')),''))
  on conflict (device_id) do update set
    name=excluded.name,
    status=excluded.status,
    adults=excluded.adults,
    children=excluded.children,
    note=excluded.note,
    updated_at=now(),
    last_accessed_at=now(),
    access_count=public.rsvps.access_count+1
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.touch_visit(p_device_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.rsvps
  set last_accessed_at=now(), access_count=access_count+1
  where device_id=p_device_id;
end;
$$;

revoke all on function public.submit_rsvp(text,text,text,integer,integer,text) from public;
revoke all on function public.touch_visit(text) from public;
grant execute on function public.submit_rsvp(text,text,text,integer,integer,text) to anon, authenticated;
grant execute on function public.touch_visit(text) to anon, authenticated;
