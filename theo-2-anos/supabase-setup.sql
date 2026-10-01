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
  guests jsonb not null default '[]'::jsonb,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_accessed_at timestamptz not null default now(),
  access_count integer not null default 1
);

alter table public.rsvps add column if not exists guests jsonb not null default '[]'::jsonb;
alter table public.rsvps enable row level security;

revoke all on table public.rsvps from anon;
grant select on table public.rsvps to authenticated;

drop policy if exists "authenticated can read rsvps" on public.rsvps;
create policy "authenticated can read rsvps" on public.rsvps for select to authenticated using (true);

create or replace function public.submit_rsvp_v2(
  p_device_id text,
  p_name text,
  p_status text,
  p_adults integer,
  p_children integer,
  p_guests jsonb,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_item jsonb;
begin
  if length(trim(coalesce(p_name,''))) < 1 or length(p_name) > 80 then raise exception 'invalid name'; end if;
  if p_status not in ('sim','talvez','nao') then raise exception 'invalid status'; end if;
  if p_adults < 0 or p_adults > 10 or p_children < 0 or p_children > 10 then raise exception 'invalid party size'; end if;
  if jsonb_typeof(p_guests) <> 'array' then raise exception 'invalid guests'; end if;
  if jsonb_array_length(p_guests) <> p_adults + p_children then raise exception 'guest count mismatch'; end if;
  for v_item in select * from jsonb_array_elements(p_guests)
  loop
    if coalesce(length(trim(v_item->>'name')),0) < 1 or length(v_item->>'name') > 80 then raise exception 'invalid guest name'; end if;
    if (v_item->>'type') not in ('adult','child') then raise exception 'invalid guest type'; end if;
  end loop;

  insert into public.rsvps(device_id,name,status,adults,children,guests,note)
  values (p_device_id,trim(p_name),p_status,p_adults,p_children,p_guests,nullif(trim(coalesce(p_note,'')),''))
  on conflict (device_id) do update set
    name=excluded.name,status=excluded.status,adults=excluded.adults,children=excluded.children,
    guests=excluded.guests,note=excluded.note,updated_at=now(),last_accessed_at=now(),
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
  update public.rsvps set last_accessed_at=now(),access_count=access_count+1 where device_id=p_device_id;
end;
$$;

revoke all on function public.submit_rsvp_v2(text,text,text,integer,integer,jsonb,text) from public;
revoke all on function public.touch_visit(text) from public;
grant execute on function public.submit_rsvp_v2(text,text,text,integer,integer,jsonb,text) to anon, authenticated;
grant execute on function public.touch_visit(text) to anon, authenticated;
