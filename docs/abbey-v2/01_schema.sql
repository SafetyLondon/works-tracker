-- =====================================================================
-- Abbey v2 cleaning model — ADDITIVE schema (forward-only, non-destructive)
-- =====================================================================
-- STAGED, NOT YET APPLIED. This file lives under docs/ so Lovable does NOT
-- auto-apply it. On sign-off it is moved verbatim into
-- supabase/migrations/<timestamp>_abbey_v2_schema.sql and pushed.
--
-- Principles (per owner decision 2026-06-20):
--   * Clean v2 replacement model, implemented ADDITIVELY.
--   * No DROP, no destructive ALTER of legacy tables.
--   * Legacy tables (visit_templates, template_rating_lines, focus_items,
--     rotation_programmes/steps, visit_rating_lines, visit_focus_*, reviews,
--     review_line_scores, focus_item_scores) are left untouched.
--   * The database is the source of truth for what is DUE; the frontend never
--     decides the rotation week.
--   * Reuses existing shared infra: public.sites, public.cleaning_visits,
--     public.evidence_items, tms_internal.* role helpers, the 1-5/N/A rating
--     idea, and the existing rotation-week maths.
-- =====================================================================

-- ---------- Enums ----------
do $$ begin
  create type public.cleaning_task_kind as enum ('baseline','rotation','optional');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.generated_task_source as enum
    ('baseline','rotation','carry_forward','one_off','optional','out_of_scope_observation');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.visit_task_result_status as enum
    ('completed','partial','not_completed','inaccessible','not_applicable');
exception when duplicate_object then null; end $$;

-- ---------- areas ----------
create table if not exists public.areas (
  id             uuid primary key default gen_random_uuid(),
  site_id        uuid not null references public.sites(id) on delete restrict,
  code           text not null,
  name           text not null,
  display_order  int not null default 0,
  is_out_of_scope boolean not null default false,  -- generates no routine tasks
  archived_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (site_id, code)
);
-- Composite key so sub_areas can bind (id, site_id) for same-site integrity.
create unique index if not exists areas_id_site_uidx on public.areas(id, site_id);
grant select on public.areas to authenticated;
grant all on public.areas to service_role;
alter table public.areas enable row level security;
create policy "areas_read_with_site_access" on public.areas
  for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- sub_areas (validated asset list) ----------
create table if not exists public.sub_areas (
  id             uuid primary key default gen_random_uuid(),
  area_id        uuid not null references public.areas(id) on delete restrict,
  code           text not null,
  name           text not null,
  display_order  int not null default 0,
  archived_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (area_id, code)
);
grant select on public.sub_areas to authenticated;
grant all on public.sub_areas to service_role;
alter table public.sub_areas enable row level security;
create policy "sub_areas_read_with_site_access" on public.sub_areas
  for select to authenticated
  using (exists (
    select 1 from public.areas a
    where a.id = area_id and tms_internal.has_any_site_access(auth.uid(), a.site_id)
  ));

-- ---------- task_families (global catalogue) ----------
create table if not exists public.task_families (
  code        text primary key,
  label       text not null,
  sort_order  int not null default 100,
  is_active   boolean not null default true
);
grant select on public.task_families to authenticated;
grant all on public.task_families to service_role;
alter table public.task_families enable row level security;
create policy "task_families_read_all" on public.task_families
  for select to authenticated using (true);

-- ---------- task_templates (reusable cleaning/rating tasks) ----------
create table if not exists public.task_templates (
  id                              uuid primary key default gen_random_uuid(),
  site_id                         uuid not null references public.sites(id) on delete restrict,
  code                            text not null,
  name                            text not null,
  task_family_code                text references public.task_families(code) on delete restrict,
  task_kind                       public.cleaning_task_kind not null default 'baseline',
  acceptance_criteria             text,        -- replaces legacy focus_items.acceptance_standard
  requires_supervisor_verification boolean not null default false,
  display_order                   int not null default 0,
  archived_at                     timestamptz,
  created_at                      timestamptz not null default now(),
  unique (site_id, code)
);
create unique index if not exists task_templates_id_site_uidx on public.task_templates(id, site_id);
grant select on public.task_templates to authenticated;
grant all on public.task_templates to service_role;
alter table public.task_templates enable row level security;
create policy "task_templates_read_with_site_access" on public.task_templates
  for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- service_schedules (Tue/Fri/Sun service days) ----------
-- Bridges to legacy visit_templates so generation can run against an existing
-- cleaning_visits row during transition. legacy_visit_template_id is a nullable
-- read-only reference; no legacy row is mutated.
create table if not exists public.service_schedules (
  id                      uuid primary key default gen_random_uuid(),
  site_id                 uuid not null references public.sites(id) on delete restrict,
  code                    text not null,
  name                    text not null,
  expected_weekday        int check (expected_weekday between 0 and 6),  -- 0=Sun..6=Sat
  planned_duration_hours  numeric(4,1),
  legacy_visit_template_id uuid references public.visit_templates(id) on delete restrict,
  display_summary         text,
  archived_at             timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (site_id, code)
);
create unique index if not exists service_schedules_id_site_uidx
  on public.service_schedules(id, site_id);
-- At most one v2 schedule bound to a given legacy template (for clean bridging).
create unique index if not exists service_schedules_legacy_uidx
  on public.service_schedules(legacy_visit_template_id)
  where legacy_visit_template_id is not null;
grant select on public.service_schedules to authenticated;
grant all on public.service_schedules to service_role;
alter table public.service_schedules enable row level security;
create policy "service_schedules_read_with_site_access" on public.service_schedules
  for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- schedule_baseline_tasks (always-due set per schedule) ----------
create table if not exists public.schedule_baseline_tasks (
  id                   uuid primary key default gen_random_uuid(),
  service_schedule_id  uuid not null references public.service_schedules(id) on delete restrict,
  task_template_id     uuid not null references public.task_templates(id) on delete restrict,
  area_id              uuid references public.areas(id) on delete restrict,
  sub_area_id          uuid references public.sub_areas(id) on delete restrict,
  display_order        int not null default 0,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  unique (service_schedule_id, task_template_id, area_id, sub_area_id)
);
grant select on public.schedule_baseline_tasks to authenticated;
grant all on public.schedule_baseline_tasks to service_role;
alter table public.schedule_baseline_tasks enable row level security;
create policy "sbt_read_with_site_access" on public.schedule_baseline_tasks
  for select to authenticated
  using (exists (
    select 1 from public.service_schedules ss
    where ss.id = service_schedule_id
      and tms_internal.has_any_site_access(auth.uid(), ss.site_id)
  ));

-- ---------- rotation_anchors (v2 rotation programmes) ----------
create table if not exists public.rotation_anchors (
  id                   uuid primary key default gen_random_uuid(),
  site_id              uuid not null references public.sites(id) on delete restrict,
  service_schedule_id  uuid not null references public.service_schedules(id) on delete restrict,
  code                 text not null,
  name                 text not null,
  cycle_length         int not null check (cycle_length between 1 and 52),
  cycle_unit           text not null default 'week' check (cycle_unit in ('week')),
  anchor_start_date    date,                 -- null = rotation not live yet
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.rotation_anchors to authenticated;
grant all on public.rotation_anchors to service_role;
alter table public.rotation_anchors enable row level security;
create policy "rotation_anchors_read_with_site_access" on public.rotation_anchors
  for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- rotation_segments (positions in the cycle) ----------
create table if not exists public.rotation_segments (
  id                  uuid primary key default gen_random_uuid(),
  rotation_anchor_id  uuid not null references public.rotation_anchors(id) on delete restrict,
  position            int not null check (position >= 1),
  title               text not null,
  description         text,
  display_order       int not null default 0,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  unique (rotation_anchor_id, position)
);
grant select on public.rotation_segments to authenticated;
grant all on public.rotation_segments to service_role;
alter table public.rotation_segments enable row level security;
create policy "rotation_segments_read_with_site_access" on public.rotation_segments
  for select to authenticated
  using (exists (
    select 1 from public.rotation_anchors ra
    where ra.id = rotation_anchor_id
      and tms_internal.has_any_site_access(auth.uid(), ra.site_id)
  ));

-- ---------- rotation_segment_tasks (tasks due when a segment is active) ----------
create table if not exists public.rotation_segment_tasks (
  id                  uuid primary key default gen_random_uuid(),
  rotation_segment_id uuid not null references public.rotation_segments(id) on delete restrict,
  task_template_id    uuid not null references public.task_templates(id) on delete restrict,
  area_id             uuid references public.areas(id) on delete restrict,
  sub_area_id         uuid references public.sub_areas(id) on delete restrict,
  display_order       int not null default 0,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  unique (rotation_segment_id, task_template_id, area_id, sub_area_id)
);
grant select on public.rotation_segment_tasks to authenticated;
grant all on public.rotation_segment_tasks to service_role;
alter table public.rotation_segment_tasks enable row level security;
create policy "rst_read_with_site_access" on public.rotation_segment_tasks
  for select to authenticated
  using (exists (
    select 1 from public.rotation_segments rs
    join public.rotation_anchors ra on ra.id = rs.rotation_anchor_id
    where rs.id = rotation_segment_id
      and tms_internal.has_any_site_access(auth.uid(), ra.site_id)
  ));

-- ---------- generated_visit_tasks (the unified per-visit list) ----------
-- One row per task generated for a specific cleaning visit. Snapshots preserve
-- the wording even if catalogue rows change later (mirrors the legacy snapshot
-- pattern). validated-list-or-Other enforced by CHECKs.
create table if not exists public.generated_visit_tasks (
  id                       uuid primary key default gen_random_uuid(),
  cleaning_visit_id        uuid not null references public.cleaning_visits(id) on delete restrict,
  site_id                  uuid not null references public.sites(id) on delete restrict,
  source                   public.generated_task_source not null,
  rotation_anchor_id       uuid references public.rotation_anchors(id) on delete restrict,
  rotation_segment_id      uuid references public.rotation_segments(id) on delete restrict,
  -- target location
  area_id                  uuid references public.areas(id) on delete restrict,
  area_snapshot            text,
  sub_area_id              uuid references public.sub_areas(id) on delete restrict,
  other_sub_area_text      text,
  -- the task
  task_template_id         uuid references public.task_templates(id) on delete restrict,
  other_task_text          text,
  task_family_code         text references public.task_families(code) on delete restrict,
  task_name_snapshot       text not null,
  acceptance_snapshot      text,
  -- state
  is_due                   boolean not null default true,
  requires_supervisor_verification boolean not null default false,
  carried_from_task_id     uuid references public.generated_visit_tasks(id) on delete restrict,
  display_order            int not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  -- validated-list-or-Other: a task must be identified by a template or free text
  constraint gvt_task_identified_chk
    check (task_template_id is not null or coalesce(other_task_text,'') <> ''),
  -- if a sub-area is named it is either validated or free text, never both blank
  constraint gvt_subarea_chk
    check (sub_area_id is not null or other_sub_area_text is null
           or coalesce(other_sub_area_text,'') <> '')
);
create index if not exists gvt_visit_idx on public.generated_visit_tasks(cleaning_visit_id);
create index if not exists gvt_site_idx on public.generated_visit_tasks(site_id);
-- Same-visit composite key for results to bind safely.
create unique index if not exists gvt_id_visit_uidx
  on public.generated_visit_tasks(id, cleaning_visit_id);
grant select on public.generated_visit_tasks to authenticated;
grant all on public.generated_visit_tasks to service_role;
alter table public.generated_visit_tasks enable row level security;
drop trigger if exists trg_gvt_updated_at on public.generated_visit_tasks;
create trigger trg_gvt_updated_at before update on public.generated_visit_tasks
  for each row execute function public.tms_set_updated_at();
create policy "gvt_read_with_site_access" on public.generated_visit_tasks
  for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- visit_task_results (completion + 1-5/N/A rating + verification) ----------
create table if not exists public.visit_task_results (
  id                       uuid primary key default gen_random_uuid(),
  generated_visit_task_id  uuid not null references public.generated_visit_tasks(id) on delete restrict,
  cleaning_visit_id        uuid not null,
  status                   public.visit_task_result_status,
  rating                   smallint check (rating between 1 and 5),
  is_na                    boolean not null default false,
  na_reason                text,
  operative_note           text,
  supervisor_reviewed      boolean not null default false,
  supervisor_verified      boolean not null default false,  -- distinct safety/quality sign-off
  supervisor_note          text,
  completed_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  unique (generated_visit_task_id),
  -- bind result to the same visit as its task (same-visit integrity)
  foreign key (generated_visit_task_id, cleaning_visit_id)
    references public.generated_visit_tasks(id, cleaning_visit_id) on delete restrict,
  -- 1-5 or N/A-with-reason, mirroring the legacy review score model
  constraint vtr_rating_or_na_chk
    check ((is_na = true and rating is null and coalesce(na_reason,'') <> '')
        or (is_na = false)),
  rating_band_display text generated always as (
    case when is_na then 'na'
         when rating is null then null
         when rating <= 2 then 'red'
         when rating = 3 then 'amber'
         else 'green' end) stored,
  is_failure boolean generated always as (rating is not null and rating <= 2) stored
);
create index if not exists vtr_visit_idx on public.visit_task_results(cleaning_visit_id);
grant select on public.visit_task_results to authenticated;
grant all on public.visit_task_results to service_role;
alter table public.visit_task_results enable row level security;
drop trigger if exists trg_vtr_updated_at on public.visit_task_results;
create trigger trg_vtr_updated_at before update on public.visit_task_results
  for each row execute function public.tms_set_updated_at();
create policy "vtr_read_with_site_access" on public.visit_task_results
  for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- generated_visit_task_evidence (reuses evidence_items) ----------
create table if not exists public.generated_visit_task_evidence (
  generated_visit_task_id uuid not null references public.generated_visit_tasks(id) on delete restrict,
  evidence_item_id        uuid not null references public.evidence_items(id) on delete restrict,
  caption                 text,
  created_at              timestamptz not null default now(),
  primary key (generated_visit_task_id, evidence_item_id)
);
grant select on public.generated_visit_task_evidence to authenticated;
grant all on public.generated_visit_task_evidence to service_role;
alter table public.generated_visit_task_evidence enable row level security;
create policy "gvte_read_with_site_access" on public.generated_visit_task_evidence
  for select to authenticated
  using (exists (
    select 1 from public.generated_visit_tasks g
    join public.cleaning_visits cv on cv.id = g.cleaning_visit_id
    where g.id = generated_visit_task_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- =====================================================================
-- Rotation maths (reuses the same formula as legacy recommended_rotation_week)
-- =====================================================================
create or replace function tms_internal.v2_active_segment_position(_anchor uuid, _visit_date date)
returns int language sql stable security definer set search_path = pg_catalog, public as
$$
  select case when ra.anchor_start_date is null then null
              else (floor(((_visit_date - ra.anchor_start_date)::int) / 7.0)::int
                    % ra.cycle_length) + 1 end
    from public.rotation_anchors ra
   where ra.id = _anchor;
$$;
revoke all on function tms_internal.v2_active_segment_position(uuid, date) from public, anon;
grant execute on function tms_internal.v2_active_segment_position(uuid, date) to authenticated;

-- =====================================================================
-- Generation RPC — the DATABASE decides what is due for a visit.
-- Idempotent: re-running only adds rows that are not already present for the
-- visit; it never deletes a task that already has a result.
-- =====================================================================
create or replace function public.rpc_generate_visit_tasks(p_cleaning_visit_id uuid)
returns int language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid; v_template uuid; v_date date;
  v_schedule uuid;
  v_anchor record; v_pos int; v_segment uuid;
  v_prior_visit uuid;
  v_count int := 0;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;

  select site_id, visit_template_id, visit_date
    into v_site, v_template, v_date
    from public.cleaning_visits where id = p_cleaning_visit_id;
  if v_site is null then raise exception 'visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['tms_admin','tms_supervisor','tms_operative']) then
    raise exception 'forbidden';
  end if;

  -- Resolve the v2 schedule via the legacy bridge.
  select id into v_schedule from public.service_schedules
    where site_id = v_site and legacy_visit_template_id = v_template and archived_at is null;
  if v_schedule is null then
    raise exception 'no v2 service_schedule bridged to this visit template';
  end if;

  -- 1) Baseline tasks (always due).
  insert into public.generated_visit_tasks(
    cleaning_visit_id, site_id, source, area_id, area_snapshot, sub_area_id,
    task_template_id, task_family_code, task_name_snapshot, acceptance_snapshot,
    is_due, requires_supervisor_verification, display_order)
  select p_cleaning_visit_id, v_site, 'baseline', sbt.area_id, a.name, sbt.sub_area_id,
         sbt.task_template_id, tt.task_family_code, tt.name, tt.acceptance_criteria,
         true, tt.requires_supervisor_verification, sbt.display_order
    from public.schedule_baseline_tasks sbt
    join public.task_templates tt on tt.id = sbt.task_template_id
    left join public.areas a on a.id = sbt.area_id
   where sbt.service_schedule_id = v_schedule and sbt.archived_at is null
     and not exists (
       select 1 from public.generated_visit_tasks g
       where g.cleaning_visit_id = p_cleaning_visit_id and g.source = 'baseline'
         and g.task_template_id = sbt.task_template_id
         and g.area_id is not distinct from sbt.area_id
         and g.sub_area_id is not distinct from sbt.sub_area_id);
  get diagnostics v_count = row_count;

  -- 2) Rotation tasks (only the active segment; non-active segments are never
  --    inserted, so they can never be marked missed).
  for v_anchor in
    select * from public.rotation_anchors
     where service_schedule_id = v_schedule and archived_at is null
       and anchor_start_date is not null
  loop
    v_pos := tms_internal.v2_active_segment_position(v_anchor.id, v_date);
    if v_pos is null then continue; end if;
    select id into v_segment from public.rotation_segments
      where rotation_anchor_id = v_anchor.id and position = v_pos and archived_at is null;
    if v_segment is null then continue; end if;

    insert into public.generated_visit_tasks(
      cleaning_visit_id, site_id, source, rotation_anchor_id, rotation_segment_id,
      area_id, area_snapshot, sub_area_id, task_template_id, task_family_code,
      task_name_snapshot, acceptance_snapshot, is_due,
      requires_supervisor_verification, display_order)
    select p_cleaning_visit_id, v_site, 'rotation', v_anchor.id, v_segment,
           rst.area_id, a.name, rst.sub_area_id, rst.task_template_id, tt.task_family_code,
           tt.name, tt.acceptance_criteria, true,
           tt.requires_supervisor_verification, rst.display_order
      from public.rotation_segment_tasks rst
      join public.task_templates tt on tt.id = rst.task_template_id
      left join public.areas a on a.id = rst.area_id
     where rst.rotation_segment_id = v_segment and rst.archived_at is null
       and not exists (
         select 1 from public.generated_visit_tasks g
         where g.cleaning_visit_id = p_cleaning_visit_id and g.source = 'rotation'
           and g.task_template_id = rst.task_template_id
           and g.area_id is not distinct from rst.area_id
           and g.sub_area_id is not distinct from rst.sub_area_id);
  end loop;

  -- 3) Carry-forward: failed/incomplete DUE tasks from the most recent prior
  --    visit on the same schedule (v1 — validate before relying on it).
  select cv.id into v_prior_visit
    from public.cleaning_visits cv
   where cv.site_id = v_site and cv.visit_template_id = v_template
     and cv.visit_date < v_date and cv.status <> 'cancelled'
   order by cv.visit_date desc limit 1;
  if v_prior_visit is not null then
    insert into public.generated_visit_tasks(
      cleaning_visit_id, site_id, source, area_id, area_snapshot, sub_area_id,
      other_sub_area_text, task_template_id, other_task_text, task_family_code,
      task_name_snapshot, acceptance_snapshot, is_due,
      requires_supervisor_verification, carried_from_task_id, display_order)
    select p_cleaning_visit_id, v_site, 'carry_forward', g.area_id, g.area_snapshot,
           g.sub_area_id, g.other_sub_area_text, g.task_template_id, g.other_task_text,
           g.task_family_code, g.task_name_snapshot, g.acceptance_snapshot, true,
           g.requires_supervisor_verification, g.id, g.display_order
      from public.generated_visit_tasks g
      join public.visit_task_results r on r.generated_visit_task_id = g.id
     where g.cleaning_visit_id = v_prior_visit and g.is_due
       and (r.is_failure or r.status in ('not_completed','partial','inaccessible'))
       and not exists (
         select 1 from public.generated_visit_tasks g2
         where g2.cleaning_visit_id = p_cleaning_visit_id
           and g2.carried_from_task_id = g.id);
  end if;

  insert into public.activity_log(site_id, actor_id, entity_kind, entity_id, action, detail)
    values (v_site, v_uid, 'cleaning_visit', p_cleaning_visit_id, 'v2_tasks_generated',
            jsonb_build_object('schedule', v_schedule));
  return v_count;
end $$;
revoke all on function public.rpc_generate_visit_tasks(uuid) from public, anon;
grant execute on function public.rpc_generate_visit_tasks(uuid) to authenticated;

-- =====================================================================
-- Reporting view — provenance: due / missed / optional / carried / out-of-scope
-- =====================================================================
create or replace view public.v_visit_task_report with (security_invoker = true) as
select
  g.id as generated_visit_task_id,
  g.cleaning_visit_id,
  g.site_id,
  g.source,
  g.is_due,
  coalesce(g.area_snapshot, '(none)') as area,
  coalesce(g.sub_area_id::text, g.other_sub_area_text) as sub_area,
  g.task_name_snapshot as task,
  g.task_family_code,
  g.requires_supervisor_verification,
  r.status,
  r.rating,
  r.is_na,
  r.rating_band_display,
  r.is_failure,
  r.supervisor_verified,
  case
    when r.id is null and g.is_due then 'due_not_recorded'
    when r.is_failure then 'failed'
    when r.status = 'not_completed' then 'missed'
    when r.status = 'partial' then 'partial'
    when r.status = 'not_applicable' then 'n/a'
    when r.status = 'completed' then 'completed'
    else 'recorded'
  end as outcome
from public.generated_visit_tasks g
left join public.visit_task_results r on r.generated_visit_task_id = g.id;
grant select on public.v_visit_task_report to authenticated;
