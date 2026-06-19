
-- =====================================================================
-- TMS PHASE 1 — MIGRATION 1: Schemas, enums, profiles, roles, sites
-- =====================================================================

-- ---------- Schemas ----------
create schema if not exists tms_internal;

-- Ensure PostgREST can reach public; tms_internal stays out of exposed schemas
grant usage on schema public to anon, authenticated, service_role;
grant usage on schema tms_internal to authenticated, service_role;

revoke all on all tables in schema tms_internal from public, anon, authenticated;
revoke all on all functions in schema tms_internal from public, anon, authenticated;
alter default privileges in schema tms_internal revoke all on tables from public, anon, authenticated;
alter default privileges in schema tms_internal revoke all on functions from public, anon, authenticated;

-- ---------- Enums ----------
do $$ begin
  create type public.cleaning_visit_status as enum
    ('draft','planned','in_progress','submitted_for_review','reviewed','closed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.review_status as enum
    ('draft','submitted','superseded');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.review_type as enum
    ('dm_lightweight','joint_walk','ops_spot','gm_spot');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.action_status as enum
    ('open','assigned','in_progress','blocked','awaiting_verification','closed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.action_priority as enum
    ('urgent','high','normal','low');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.focus_item_status as enum
    ('selected','completed','partially_completed','not_completed','inaccessible','deferred','not_applicable');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.scope_classification as enum
    ('routine_cleaning','rotating_focus','maintenance_site_fabric','access',
     'equipment_chemical','out_of_scope','additional_resource','urgent_hs');
exception when duplicate_object then null; end $$;

-- ---------- updated_at helper ----------
create or replace function public.tms_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- profiles ----------
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete restrict,
  email         text,
  display_name  text,
  disabled_at   timestamptz,
  disabled_by   uuid references auth.users(id) on delete restrict,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

grant select on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;

create policy "profiles_select_self_or_admin"
  on public.profiles for select to authenticated
  using (true);   -- internal app; all authenticated users may read profile basics

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.tms_set_updated_at();

-- Auto-create profile on auth user creation, no role assigned
create or replace function public.tms_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tms_handle_new_user();

-- ---------- sites ----------
create table if not exists public.sites (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique,
  name         text not null,
  timezone     text not null default 'Europe/London',
  archived_at  timestamptz,
  archived_by  uuid references auth.users(id) on delete restrict,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

grant select on public.sites to authenticated;
grant all on public.sites to service_role;
alter table public.sites enable row level security;
drop trigger if exists trg_sites_updated_at on public.sites;
create trigger trg_sites_updated_at before update on public.sites
  for each row execute function public.tms_set_updated_at();

-- ---------- role_definitions ----------
create table if not exists public.role_definitions (
  code         text primary key,
  label        text not null,
  description  text,
  is_global    boolean not null default false,   -- true = role may have null site_id
  is_active    boolean not null default true,    -- inactive records remain for FK history
  sort_order   int not null default 100,
  created_at   timestamptz not null default now()
);

grant select on public.role_definitions to authenticated;
grant all on public.role_definitions to service_role;
alter table public.role_definitions enable row level security;
create policy "roledefs_read_all_authenticated"
  on public.role_definitions for select to authenticated using (true);

-- ---------- user_site_roles ----------
create table if not exists public.user_site_roles (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete restrict,
  role_code    text not null references public.role_definitions(code) on delete restrict,
  site_id      uuid references public.sites(id) on delete restrict,
  granted_at   timestamptz not null default now(),
  granted_by   uuid references auth.users(id) on delete restrict
);

-- Partial unique indexes — global vs site
create unique index if not exists user_site_roles_global_uidx
  on public.user_site_roles(user_id, role_code) where site_id is null;
create unique index if not exists user_site_roles_site_uidx
  on public.user_site_roles(user_id, role_code, site_id) where site_id is not null;

grant select on public.user_site_roles to authenticated;
grant all on public.user_site_roles to service_role;
alter table public.user_site_roles enable row level security;

-- Trigger: global vs site validation
create or replace function public.tms_validate_user_site_role()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_is_global boolean;
begin
  select is_global into v_is_global
    from public.role_definitions where code = new.role_code;
  if v_is_global is null then
    raise exception 'unknown role_code: %', new.role_code;
  end if;

  if v_is_global and new.site_id is not null then
    raise exception 'global role % must not have a site_id', new.role_code;
  end if;
  if (not v_is_global) and new.site_id is null then
    raise exception 'site-scoped role % requires a site_id', new.role_code;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_user_site_roles_validate on public.user_site_roles;
create trigger trg_user_site_roles_validate
  before insert or update on public.user_site_roles
  for each row execute function public.tms_validate_user_site_role();

-- ---------- tms_internal helpers (referenced by RLS policies) ----------
create or replace function tms_internal.is_tms_admin(_user uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.user_site_roles
    where user_id = _user and role_code = 'tms_admin' and site_id is null
  );
$$;

create or replace function tms_internal.has_site_role(_user uuid, _site uuid, _roles text[])
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.user_site_roles usr
    where usr.user_id = _user
      and (usr.site_id = _site or (usr.site_id is null and usr.role_code = 'tms_admin'))
      and usr.role_code = any(_roles)
  );
$$;

create or replace function tms_internal.has_any_site_access(_user uuid, _site uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1 from public.user_site_roles
    where user_id = _user
      and (site_id = _site or (site_id is null and role_code = 'tms_admin'))
  );
$$;

revoke all on function tms_internal.is_tms_admin(uuid) from public;
revoke all on function tms_internal.has_site_role(uuid, uuid, text[]) from public;
revoke all on function tms_internal.has_any_site_access(uuid, uuid) from public;
grant execute on function tms_internal.is_tms_admin(uuid) to authenticated;
grant execute on function tms_internal.has_site_role(uuid, uuid, text[]) to authenticated;
grant execute on function tms_internal.has_any_site_access(uuid, uuid) to authenticated;

-- ---------- RLS policies that depend on helpers ----------

-- sites: anyone with site access (or admin) may read; archived rows still visible
create policy "sites_read_with_access"
  on public.sites for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), id));

-- user_site_roles: a user may see their own roles; admins see everything
create policy "user_site_roles_self_or_admin"
  on public.user_site_roles for select to authenticated
  using (user_id = auth.uid() or tms_internal.is_tms_admin(auth.uid()));
