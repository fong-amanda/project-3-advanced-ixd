-- Shared Space: Supabase schema
-- Run this once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it drops and recreates policies and functions, but NOT tables.
--
-- Model
--   rooms ─┬─ room_members      (who may read/write a room; host + at most one guest)
--          ├─ items             (one row per thing in the room; Sort decisions live here)
--          ├─ designs           (up to 3 redesign options; likes live here)
--          └─ design_placements (only what a design changes: a moved/hidden real item, or a new piece)
--
-- Sync rules the apps rely on
--   * Every table has id, room_id, updated_at, deleted_at. Clients never hard-delete; they set deleted_at.
--   * updated_at is written by the client and used for last-write-wins.
--   * A design never stores Sort decisions. Apps combine items.status with placements at render time.

create extension if not exists pgcrypto;

-- ───────────────────────── tables ─────────────────────────

create table if not exists public.rooms (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique check (code ~ '^[A-Z0-9]{5}$'),
  name             text not null,
  current_use      text not null default '',
  future_use       text not null default '',
  width_cm         integer not null default 340,
  length_cm        integer not null default 380,
  height_cm        integer not null default 250,
  host_user_id     uuid not null references auth.users(id) on delete cascade,
  host_name        text not null,
  guest_user_id    uuid references auth.users(id) on delete set null,
  guest_name       text,
  invited_at       timestamptz,
  guest_joined_at  timestamptz,
  scan_version     integer not null default 0,
  geometry_path    text,           -- Storage path of the simplified room geometry JSON
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

create table if not exists public.room_members (
  room_id      uuid not null references public.rooms(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null check (role in ('host', 'guest')),
  display_name text not null default '',
  joined_at    timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.items (
  id               uuid primary key,
  room_id          uuid not null references public.rooms(id) on delete cascade,
  name             text not null,
  category         text not null default 'other',
  source           text not null default 'manual' check (source in ('scanned', 'manual')),
  scan_object_id   uuid,
  width_cm         double precision not null default 50,
  depth_cm         double precision not null default 50,
  height_cm        double precision not null default 50,
  x_cm             double precision not null default 0,
  y_cm             double precision not null default 0,
  z_cm             double precision not null default 0,
  yaw_deg          double precision not null default 0,
  owner            text not null default 'unassigned' check (owner in ('unassigned', 'host', 'guest', 'shared')),
  status           text not null default 'undecided' check (status in ('undecided', 'keep', 'keepMove', 'sendToOwner', 'letGo')),
  move_destination text,
  decided_by       text check (decided_by in ('host', 'guest')),
  decided_at       timestamptz,
  suggestion       text check (suggestion in ('keep', 'keepMove', 'sendToOwner', 'letGo')),
  suggested_by     text check (suggested_by in ('host', 'guest')),
  suggested_at     timestamptz,
  note             text not null default '',
  note_by          text check (note_by in ('host', 'guest')),
  pickup_date      timestamptz,
  photo_path       text,
  sort_order       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
create index if not exists items_room_idx on public.items(room_id);

create table if not exists public.designs (
  id              uuid primary key,
  room_id         uuid not null references public.rooms(id) on delete cascade,
  name            text not null,
  sort_order      integer not null default 0,
  host_likes      boolean not null default false,
  guest_likes     boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index if not exists designs_room_idx on public.designs(room_id);

create table if not exists public.design_placements (
  id          uuid primary key,
  room_id     uuid not null references public.rooms(id) on delete cascade,
  design_id   uuid not null references public.designs(id) on delete cascade,
  item_id     uuid references public.items(id) on delete cascade,  -- a real item moved/hidden in this design
  catalog_id  text,                                                -- or a new piece from the catalogue
  x_cm        double precision not null default 0,
  z_cm        double precision not null default 0,
  yaw_deg     double precision not null default 0,
  hidden      boolean not null default false,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  check ((item_id is null) <> (catalog_id is null))
);
create index if not exists placements_room_idx on public.design_placements(room_id);

-- ───────────────────────── helpers ─────────────────────────

create or replace function public.is_room_member(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from room_members where room_id = rid and user_id = auth.uid());
$$;

create or replace function public.is_room_host(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from room_members where room_id = rid and user_id = auth.uid() and role = 'host');
$$;

-- The creator of a room becomes its host member automatically.
create or replace function public.add_host_member()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into room_members (room_id, user_id, role, display_name)
  values (new.id, new.host_user_id, 'host', new.host_name)
  on conflict (room_id, user_id) do nothing;
  return new;
end $$;

drop trigger if exists rooms_add_host on public.rooms;
create trigger rooms_add_host after insert on public.rooms
for each row execute function public.add_host_member();

-- Look up a room by its code before joining ("Maya invited you"). Raises room_not_found.
create or replace function public.peek_room(p_code text)
returns json language plpgsql stable security definer set search_path = public as $$
declare r rooms;
begin
  select * into r from rooms where code = upper(p_code) and deleted_at is null;
  if not found then raise exception 'room_not_found'; end if;
  return json_build_object(
    'id', r.id, 'name', r.name, 'future_use', r.future_use,
    'host_name', r.host_name, 'guest_name', r.guest_name,
    'is_host', r.host_user_id = auth.uid()
  );
end $$;

-- Join a room as its guest. A room has one guest; whoever joins with the code becomes it
-- (so the same person can rejoin after reinstalling the app).
create or replace function public.join_room(p_code text, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare r rooms;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into r from rooms where code = upper(p_code) and deleted_at is null;
  if not found then raise exception 'room_not_found'; end if;
  if r.host_user_id = auth.uid() then return r.id; end if;

  delete from room_members where room_id = r.id and role = 'guest' and user_id <> auth.uid();
  insert into room_members (room_id, user_id, role, display_name)
  values (r.id, auth.uid(), 'guest', p_name)
  on conflict (room_id, user_id) do update set display_name = excluded.display_name;

  update rooms set guest_user_id = auth.uid(),
                   guest_name = p_name,
                   guest_joined_at = coalesce(guest_joined_at, now()),
                   updated_at = now()
  where id = r.id;
  return r.id;
end $$;

-- Like / unlike a design. Lets the guest like without being allowed to edit designs.
create or replace function public.set_design_like(p_design uuid, p_liked boolean)
returns void language plpgsql security definer set search_path = public as $$
declare rid uuid; my_role text;
begin
  select room_id into rid from designs where id = p_design;
  select role into my_role from room_members where room_id = rid and user_id = auth.uid();
  if my_role is null then raise exception 'not_a_member'; end if;
  if my_role = 'host' then
    update designs set host_likes = p_liked, updated_at = now() where id = p_design;
  else
    update designs set guest_likes = p_liked, updated_at = now() where id = p_design;
  end if;
end $$;

-- Leave a room as the guest.
create or replace function public.leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from room_members where room_id = p_room and user_id = auth.uid() and role = 'guest';
  update rooms set guest_user_id = null, updated_at = now()
  where id = p_room and guest_user_id = auth.uid();
end $$;

-- ───────────────────────── row level security ─────────────────────────

alter table public.rooms             enable row level security;
alter table public.room_members      enable row level security;
alter table public.items             enable row level security;
alter table public.designs           enable row level security;
alter table public.design_placements enable row level security;

drop policy if exists rooms_select on public.rooms;
drop policy if exists rooms_insert on public.rooms;
drop policy if exists rooms_update on public.rooms;
create policy rooms_select on public.rooms for select using (host_user_id = auth.uid() or public.is_room_member(id));
create policy rooms_insert on public.rooms for insert with check (host_user_id = auth.uid());
create policy rooms_update on public.rooms for update using (public.is_room_host(id));

drop policy if exists members_select on public.room_members;
create policy members_select on public.room_members for select using (public.is_room_member(room_id));

-- Both people can write items. "Only the owner decides" is enforced in the apps.
drop policy if exists items_select on public.items;
drop policy if exists items_insert on public.items;
drop policy if exists items_update on public.items;
create policy items_select on public.items for select using (public.is_room_member(room_id));
create policy items_insert on public.items for insert with check (public.is_room_member(room_id));
create policy items_update on public.items for update using (public.is_room_member(room_id));

-- Designs: everyone in the room can see them; only the host edits.
drop policy if exists designs_select on public.designs;
drop policy if exists designs_insert on public.designs;
drop policy if exists designs_update on public.designs;
create policy designs_select on public.designs for select using (public.is_room_member(room_id));
create policy designs_insert on public.designs for insert with check (public.is_room_host(room_id));
create policy designs_update on public.designs for update using (public.is_room_host(room_id));

drop policy if exists placements_select on public.design_placements;
drop policy if exists placements_insert on public.design_placements;
drop policy if exists placements_update on public.design_placements;
create policy placements_select on public.design_placements for select using (public.is_room_member(room_id));
create policy placements_insert on public.design_placements for insert with check (public.is_room_host(room_id));
create policy placements_update on public.design_placements for update using (public.is_room_host(room_id));

-- ───────────────────────── realtime ─────────────────────────

do $$
declare t text;
begin
  foreach t in array array['rooms', 'items', 'designs', 'design_placements'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ───────────────────────── storage ─────────────────────────
-- Bucket "rooms": <room_id>/geometry.json and <room_id>/items/<item_id>.jpg

insert into storage.buckets (id, name, public)
values ('rooms', 'rooms', false)
on conflict (id) do nothing;

drop policy if exists rooms_files_read on storage.objects;
drop policy if exists rooms_files_write on storage.objects;
drop policy if exists rooms_files_update on storage.objects;
create policy rooms_files_read on storage.objects for select
  using (bucket_id = 'rooms' and public.is_room_member(((storage.foldername(name))[1])::uuid));
create policy rooms_files_write on storage.objects for insert
  with check (bucket_id = 'rooms' and public.is_room_member(((storage.foldername(name))[1])::uuid));
create policy rooms_files_update on storage.objects for update
  using (bucket_id = 'rooms' and public.is_room_member(((storage.foldername(name))[1])::uuid));
