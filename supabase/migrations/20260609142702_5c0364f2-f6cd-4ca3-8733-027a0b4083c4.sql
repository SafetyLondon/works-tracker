
-- =====================================================================
-- A1: code columns + parent-scoped uniques (with deterministic backfill)
-- =====================================================================

alter table public.template_rating_lines add column if not exists code text;
alter table public.template_scope_items  add column if not exists code text;
alter table public.focus_items           add column if not exists code text;

-- Backfill template_rating_lines.code = 'LINE_<2-digit display order rank>'
with ranked as (
  select id,
         'LINE_' || lpad(
           (row_number() over (partition by visit_template_id order by display_order, id))::text,
           2, '0') as new_code
    from public.template_rating_lines
   where code is null
)
update public.template_rating_lines trl
   set code = r.new_code
  from ranked r where r.id = trl.id;

-- Backfill template_scope_items.code keyed by item_type
with ranked as (
  select id,
         upper(item_type) || '_' || lpad(
           (row_number() over (partition by visit_template_id, item_type
                               order by display_order, id))::text,
           2, '0') as new_code
    from public.template_scope_items
   where code is null
)
update public.template_scope_items tsi
   set code = r.new_code
  from ranked r where r.id = tsi.id;

-- Backfill focus_items.code per site
with ranked as (
  select id,
         'FI_' || lpad(
           (row_number() over (partition by site_id order by display_order, id))::text,
           3, '0') as new_code
    from public.focus_items
   where code is null
)
update public.focus_items fi
   set code = r.new_code
  from ranked r where r.id = fi.id;

-- Enforce NOT NULL
do $$ begin
  if exists (select 1 from public.template_rating_lines where code is null) then
    raise exception 'template_rating_lines.code backfill incomplete';
  end if;
  if exists (select 1 from public.template_scope_items where code is null) then
    raise exception 'template_scope_items.code backfill incomplete';
  end if;
  if exists (select 1 from public.focus_items where code is null) then
    raise exception 'focus_items.code backfill incomplete';
  end if;
end $$;

alter table public.template_rating_lines alter column code set not null;
alter table public.template_scope_items  alter column code set not null;
alter table public.focus_items           alter column code set not null;

-- Parent-scoped UNIQUE constraints
alter table public.template_rating_lines
  add constraint trl_template_code_uk unique (visit_template_id, code);
alter table public.template_scope_items
  add constraint tsi_template_code_uk unique (visit_template_id, code);
alter table public.focus_items
  add constraint focus_items_site_code_uk unique (site_id, code);

-- rotation_programmes: anchor_date becomes optional; clear any pre-existing
-- placeholder anchors (must be set by admin via rpc_set_rotation_anchor).
alter table public.rotation_programmes alter column anchor_date drop not null;
update public.rotation_programmes set anchor_date = null;

-- Helper returns NULL when anchor is unset (no recommendations until ready)
create or replace function tms_internal.recommended_rotation_week(_programme uuid, _visit_date date)
returns int language sql stable security definer set search_path = pg_catalog, public as
$$
  select case when rp.anchor_date is null then null
              else ((floor(((_visit_date - rp.anchor_date)::int) / 7.0)::int)
                    % rp.cycle_length_weeks) + 1 end
    from public.rotation_programmes rp
   where rp.id = _programme;
$$;

-- =====================================================================
-- A2: transition trigger expression fix
-- =====================================================================

create or replace function public.tms_validate_visit_transition()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'::public.cleaning_visit_status then
      new.status = any(array['planned','in_progress','cancelled']::public.cleaning_visit_status[])
    when 'planned'::public.cleaning_visit_status then
      new.status = any(array['in_progress','cancelled']::public.cleaning_visit_status[])
    when 'in_progress'::public.cleaning_visit_status then
      new.status = any(array['submitted_for_review','cancelled']::public.cleaning_visit_status[])
    when 'submitted_for_review'::public.cleaning_visit_status then
      new.status = any(array['reviewed','in_progress','cancelled']::public.cleaning_visit_status[])
    when 'reviewed'::public.cleaning_visit_status then
      new.status = any(array['closed','in_progress']::public.cleaning_visit_status[])
    when 'closed'::public.cleaning_visit_status then
      new.status = any(array['in_progress']::public.cleaning_visit_status[])
    else false
  end;
  if not ok then
    raise exception 'illegal cleaning_visit status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create or replace function public.tms_validate_action_transition()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'open'::public.action_status then
      new.status = any(array['assigned','in_progress','cancelled']::public.action_status[])
    when 'assigned'::public.action_status then
      new.status = any(array['in_progress','blocked','cancelled']::public.action_status[])
    when 'in_progress'::public.action_status then
      new.status = any(array['blocked','awaiting_verification','cancelled']::public.action_status[])
    when 'blocked'::public.action_status then
      new.status = any(array['in_progress','cancelled']::public.action_status[])
    when 'awaiting_verification'::public.action_status then
      new.status = any(array['closed','in_progress','cancelled']::public.action_status[])
    else false
  end;
  if not ok then
    raise exception 'illegal action status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- =====================================================================
-- A3: role catalogue migration (conflict-safe)
-- =====================================================================

insert into public.role_definitions(code, label, is_global, description)
values
  ('tms_admin',                  'TMS Admin',                  true,  'Full TMS administrative privileges across all sites'),
  ('tms_supervisor',             'TMS Supervisor',             false, 'Site-level TMS supervisor responsible for visit delivery'),
  ('tms_operative',              'TMS Operative',              false, 'Site-level TMS operative; can be assigned cleaning actions'),
  ('centre_dm_reviewer',         'Centre Duty Manager (Reviewer)', false, 'Centre duty manager performing lightweight next-morning reviews'),
  ('centre_operations_manager',  'Centre Operations Manager',  false, 'Centre operations manager — verification and oversight'),
  ('centre_gm',                  'Centre General Manager',     false, 'Centre general manager — verification and oversight'),
  ('read_only_viewer',           'Read-only Viewer',           false, 'Read-only visibility of site activity; no mutations')
on conflict (code) do update set
  label = excluded.label,
  is_global = excluded.is_global,
  description = excluded.description;

-- Reinsert legacy assignments under canonical codes (idempotent)
insert into public.user_site_roles (user_id, role_code, site_id, granted_by, granted_at)
  select user_id, 'tms_supervisor', site_id, granted_by, granted_at
    from public.user_site_roles where role_code = 'site_supervisor'
  on conflict do nothing;
insert into public.user_site_roles (user_id, role_code, site_id, granted_by, granted_at)
  select user_id, 'centre_operations_manager', site_id, granted_by, granted_at
    from public.user_site_roles where role_code = 'ops_manager'
  on conflict do nothing;
insert into public.user_site_roles (user_id, role_code, site_id, granted_by, granted_at)
  select user_id, 'centre_gm', site_id, granted_by, granted_at
    from public.user_site_roles where role_code = 'gm'
  on conflict do nothing;
insert into public.user_site_roles (user_id, role_code, site_id, granted_by, granted_at)
  select user_id, 'read_only_viewer', site_id, granted_by, granted_at
    from public.user_site_roles where role_code = 'viewer'
  on conflict do nothing;

delete from public.user_site_roles
 where role_code in ('site_supervisor','ops_manager','gm','viewer');

delete from public.role_definitions rd
 where rd.code in ('site_supervisor','ops_manager','gm','viewer')
   and not exists (select 1 from public.user_site_roles usr where usr.role_code = rd.code);

-- =====================================================================
-- A8: historic snapshot columns + acceptance_standard
-- =====================================================================

alter table public.focus_items
  add column if not exists acceptance_standard text;

alter table public.review_line_scores
  add column if not exists line_label_snapshot text;

alter table public.focus_item_scores
  add column if not exists focus_label_snapshot text,
  add column if not exists focus_location_snapshot text,
  add column if not exists focus_acceptance_snapshot text;

-- =====================================================================
-- A13: urgent H&S actions must reference a source row
-- =====================================================================

alter table public.actions drop constraint if exists actions_urgent_hs_source_chk;
alter table public.actions
  add constraint actions_urgent_hs_source_chk
  check (
    urgent_hs_flag = false
    or coalesce(source_review_line_score_id::text,
                source_focus_item_score_id::text,
                source_constraint_id::text) is not null
  );

comment on table public.rotation_programmes is
  'Rotation programmes. anchor_date NULL means the programme is not yet operational; '
  'rpc_set_rotation_anchor activates it. Lifecycle is archived_at; readiness is anchor_date IS NOT NULL.';
