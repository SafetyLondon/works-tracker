-- =====================================================================
-- Abbey v2 cleaning model — SELF-CONTAINED schema (forward-only, additive)
-- =====================================================================
-- Prepared on branch `abbey-v2`. NOT applied to the live DB until the branch
-- is merged to main (Lovable applies on merge). No DROP / destructive ALTER /
-- DELETE / UPDATE of any legacy table or row.
--
-- ARCHITECTURE (owner decision 2026-06-20): v2 is the operational source of
-- truth. The DATABASE decides what is due, generated, completed, failed and
-- reported. The frontend never invents due tasks.
--
-- v2 OWNS its operational tables (v2_* prefix). It reuses ONLY the stable
-- auth/identity layer:
--   * auth.users / public.profiles      (identity)
--   * public.sites                       (clean basic site identity)
--   * public.user_site_roles + tms_internal.{is_tms_admin,has_site_role,
--     has_any_site_access}               (access control)
--   * public.tms_set_updated_at()        (generic updated_at trigger)
-- v2 does NOT depend on any legacy OPERATIONAL table (cleaning_visits,
-- visit_templates, template_rating_lines, focus_items, rotation_programmes,
-- reviews, review_line_scores, focus_item_scores, evidence_items, actions,
-- activity_log). Those stay as legacy/archive, untouched.
-- =====================================================================

-- ---------- Enums ----------
do $$ begin create type public.v2_task_source as enum
  ('baseline','rotation','carry_forward','one_off','optional','out_of_scope_observation');
exception when duplicate_object then null; end $$;

do $$ begin create type public.v2_result_status as enum
  ('completed','partial','not_completed','inaccessible','not_applicable');
exception when duplicate_object then null; end $$;

do $$ begin create type public.v2_visit_status as enum
  ('planned','in_progress','submitted','reviewed','closed','cancelled');
exception when duplicate_object then null; end $$;

-- ---------- v2_areas ----------
create table if not exists public.v2_areas (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references public.sites(id) on delete restrict,
  code            text not null,
  name            text not null,
  display_order   int not null default 0,
  is_out_of_scope boolean not null default false,  -- excluded from routine generation
  archived_at     timestamptz,
  created_at      timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.v2_areas to authenticated;
grant all on public.v2_areas to service_role;
alter table public.v2_areas enable row level security;
create policy "v2_areas_read" on public.v2_areas for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_sub_areas (validated asset list + @UNCONFIRMED rows) ----------
create table if not exists public.v2_sub_areas (
  id             uuid primary key default gen_random_uuid(),
  area_id        uuid not null references public.v2_areas(id) on delete restrict,
  code           text not null,
  name           text not null,
  is_unconfirmed boolean not null default false,  -- provisional asset, refine later
  display_order  int not null default 0,
  archived_at    timestamptz,
  created_at     timestamptz not null default now(),
  unique (area_id, code)
);
grant select on public.v2_sub_areas to authenticated;
grant all on public.v2_sub_areas to service_role;
alter table public.v2_sub_areas enable row level security;
create policy "v2_sub_areas_read" on public.v2_sub_areas for select to authenticated
  using (exists (select 1 from public.v2_areas a
                 where a.id = area_id and tms_internal.has_any_site_access(auth.uid(), a.site_id)));

-- ---------- v2_task_families (global catalogue) ----------
create table if not exists public.v2_task_families (
  code       text primary key,
  label      text not null,
  sort_order int not null default 100,
  is_active  boolean not null default true
);
grant select on public.v2_task_families to authenticated;
grant all on public.v2_task_families to service_role;
alter table public.v2_task_families enable row level security;
create policy "v2_task_families_read" on public.v2_task_families for select to authenticated using (true);

-- ---------- v2_task_templates ----------
create table if not exists public.v2_task_templates (
  id                               uuid primary key default gen_random_uuid(),
  site_id                          uuid not null references public.sites(id) on delete restrict,
  code                             text not null,
  name                             text not null,
  task_family_code                 text references public.v2_task_families(code) on delete restrict,
  task_kind                        text not null default 'baseline'
                                     check (task_kind in ('baseline','rotation','optional')),
  acceptance_criteria              text,
  requires_supervisor_verification boolean not null default false,
  display_order                    int not null default 0,
  archived_at                      timestamptz,
  created_at                       timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.v2_task_templates to authenticated;
grant all on public.v2_task_templates to service_role;
alter table public.v2_task_templates enable row level security;
create policy "v2_task_templates_read" on public.v2_task_templates for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_service_schedules (Tue/Fri/Sun) ----------
create table if not exists public.v2_service_schedules (
  id                     uuid primary key default gen_random_uuid(),
  site_id                uuid not null references public.sites(id) on delete restrict,
  code                   text not null,
  name                   text not null,
  expected_weekday       int check (expected_weekday between 0 and 6),  -- 0=Sun..6=Sat
  planned_duration_hours numeric(4,1),
  display_summary        text,
  archived_at            timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.v2_service_schedules to authenticated;
grant all on public.v2_service_schedules to service_role;
alter table public.v2_service_schedules enable row level security;
drop trigger if exists trg_v2ss_updated_at on public.v2_service_schedules;
create trigger trg_v2ss_updated_at before update on public.v2_service_schedules
  for each row execute function public.tms_set_updated_at();
create policy "v2_service_schedules_read" on public.v2_service_schedules for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_schedule_baseline_tasks (always-due layer) ----------
create table if not exists public.v2_schedule_baseline_tasks (
  id                   uuid primary key default gen_random_uuid(),
  service_schedule_id  uuid not null references public.v2_service_schedules(id) on delete restrict,
  task_template_id     uuid not null references public.v2_task_templates(id) on delete restrict,
  area_id              uuid references public.v2_areas(id) on delete restrict,
  sub_area_id          uuid references public.v2_sub_areas(id) on delete restrict,
  display_order        int not null default 0,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  unique (service_schedule_id, task_template_id, area_id, sub_area_id)
);
grant select on public.v2_schedule_baseline_tasks to authenticated;
grant all on public.v2_schedule_baseline_tasks to service_role;
alter table public.v2_schedule_baseline_tasks enable row level security;
create policy "v2_sbt_read" on public.v2_schedule_baseline_tasks for select to authenticated
  using (exists (select 1 from public.v2_service_schedules ss
                 where ss.id = service_schedule_id
                   and tms_internal.has_any_site_access(auth.uid(), ss.site_id)));

-- ---------- v2_rotation_anchors ----------
create table if not exists public.v2_rotation_anchors (
  id                  uuid primary key default gen_random_uuid(),
  site_id             uuid not null references public.sites(id) on delete restrict,
  service_schedule_id uuid not null references public.v2_service_schedules(id) on delete restrict,
  code                text not null,
  name                text not null,
  cycle_length        int not null check (cycle_length between 1 and 52),
  cycle_unit          text not null default 'week' check (cycle_unit in ('week')),
  anchor_start_date   date,    -- NULL => inactive / needs setup (no rotation generated)
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.v2_rotation_anchors to authenticated;
grant all on public.v2_rotation_anchors to service_role;
alter table public.v2_rotation_anchors enable row level security;
drop trigger if exists trg_v2ra_updated_at on public.v2_rotation_anchors;
create trigger trg_v2ra_updated_at before update on public.v2_rotation_anchors
  for each row execute function public.tms_set_updated_at();
create policy "v2_rotation_anchors_read" on public.v2_rotation_anchors for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_rotation_segments ----------
create table if not exists public.v2_rotation_segments (
  id                 uuid primary key default gen_random_uuid(),
  rotation_anchor_id uuid not null references public.v2_rotation_anchors(id) on delete restrict,
  position           int not null check (position >= 1),
  title              text not null,
  description        text,
  display_order      int not null default 0,
  archived_at        timestamptz,
  created_at         timestamptz not null default now(),
  unique (rotation_anchor_id, position)
);
grant select on public.v2_rotation_segments to authenticated;
grant all on public.v2_rotation_segments to service_role;
alter table public.v2_rotation_segments enable row level security;
create policy "v2_rotation_segments_read" on public.v2_rotation_segments for select to authenticated
  using (exists (select 1 from public.v2_rotation_anchors ra
                 where ra.id = rotation_anchor_id
                   and tms_internal.has_any_site_access(auth.uid(), ra.site_id)));

-- ---------- v2_rotation_segment_tasks (tasks due when a segment is active) ----------
create table if not exists public.v2_rotation_segment_tasks (
  id                  uuid primary key default gen_random_uuid(),
  rotation_segment_id uuid not null references public.v2_rotation_segments(id) on delete restrict,
  task_template_id    uuid not null references public.v2_task_templates(id) on delete restrict,
  area_id             uuid references public.v2_areas(id) on delete restrict,
  sub_area_id         uuid references public.v2_sub_areas(id) on delete restrict,
  display_order       int not null default 0,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  unique (rotation_segment_id, task_template_id, area_id, sub_area_id)
);
grant select on public.v2_rotation_segment_tasks to authenticated;
grant all on public.v2_rotation_segment_tasks to service_role;
alter table public.v2_rotation_segment_tasks enable row level security;
create policy "v2_rst_read" on public.v2_rotation_segment_tasks for select to authenticated
  using (exists (select 1 from public.v2_rotation_segments rs
                 join public.v2_rotation_anchors ra on ra.id = rs.rotation_anchor_id
                 where rs.id = rotation_segment_id
                   and tms_internal.has_any_site_access(auth.uid(), ra.site_id)));

-- ---------- v2_visit_instances (v2 owns its visit lifecycle) ----------
create table if not exists public.v2_visit_instances (
  id                  uuid primary key default gen_random_uuid(),
  site_id             uuid not null references public.sites(id) on delete restrict,
  service_schedule_id uuid not null references public.v2_service_schedules(id) on delete restrict,
  visit_date          date not null,
  status              public.v2_visit_status not null default 'planned',
  version_no          bigint not null default 1,
  supervisor_id       uuid references auth.users(id) on delete restrict,
  notes               text,
  created_by          uuid references auth.users(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create unique index if not exists v2vi_id_site_uidx on public.v2_visit_instances(id, site_id);
-- one live visit per (site, schedule, date)
create unique index if not exists v2vi_dup_uidx
  on public.v2_visit_instances(site_id, service_schedule_id, visit_date)
  where status <> 'cancelled';
create index if not exists v2vi_site_date_idx on public.v2_visit_instances(site_id, visit_date desc);
grant select on public.v2_visit_instances to authenticated;
grant all on public.v2_visit_instances to service_role;
alter table public.v2_visit_instances enable row level security;
drop trigger if exists trg_v2vi_updated_at on public.v2_visit_instances;
create trigger trg_v2vi_updated_at before update on public.v2_visit_instances
  for each row execute function public.tms_set_updated_at();
create policy "v2_visit_instances_read" on public.v2_visit_instances for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_generated_visit_tasks (materialised per visit; knows why it exists) ----------
create table if not exists public.v2_generated_visit_tasks (
  id                       uuid primary key default gen_random_uuid(),
  visit_instance_id        uuid not null references public.v2_visit_instances(id) on delete restrict,
  site_id                  uuid not null references public.sites(id) on delete restrict,
  service_schedule_id      uuid not null references public.v2_service_schedules(id) on delete restrict,
  task_source              public.v2_task_source not null,
  rotation_anchor_id       uuid references public.v2_rotation_anchors(id) on delete restrict,
  rotation_segment_id      uuid references public.v2_rotation_segments(id) on delete restrict,
  area_id                  uuid references public.v2_areas(id) on delete restrict,
  area_snapshot            text,
  sub_area_id              uuid references public.v2_sub_areas(id) on delete restrict,
  other_sub_area_text      text,                       -- "Other / not listed" fallback
  task_template_id         uuid references public.v2_task_templates(id) on delete restrict,
  other_task_text          text,                       -- "Other / not listed" fallback
  task_family_code         text references public.v2_task_families(code) on delete restrict,
  task_name_snapshot       text not null,
  acceptance_snapshot      text,
  is_due                   boolean not null default true,
  requires_supervisor_verification boolean not null default false,
  carried_from_task_id     uuid references public.v2_generated_visit_tasks(id) on delete restrict,
  display_order            int not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  -- a task must be identified by a template OR free text (no blank/vague targets)
  constraint v2gvt_task_identified_chk
    check (task_template_id is not null or coalesce(other_task_text,'') <> '')
);
create unique index if not exists v2gvt_id_visit_uidx
  on public.v2_generated_visit_tasks(id, visit_instance_id);
create index if not exists v2gvt_visit_idx on public.v2_generated_visit_tasks(visit_instance_id);
grant select on public.v2_generated_visit_tasks to authenticated;
grant all on public.v2_generated_visit_tasks to service_role;
alter table public.v2_generated_visit_tasks enable row level security;
drop trigger if exists trg_v2gvt_updated_at on public.v2_generated_visit_tasks;
create trigger trg_v2gvt_updated_at before update on public.v2_generated_visit_tasks
  for each row execute function public.tms_set_updated_at();
create policy "v2_gvt_read" on public.v2_generated_visit_tasks for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- v2_visit_task_results (completion + 1-5/N/A rating + verification) ----------
create table if not exists public.v2_visit_task_results (
  id                      uuid primary key default gen_random_uuid(),
  generated_visit_task_id uuid not null references public.v2_generated_visit_tasks(id) on delete restrict,
  visit_instance_id       uuid not null,
  status                  public.v2_result_status,
  rating                  smallint check (rating between 1 and 5),
  is_na                   boolean not null default false,
  na_reason               text,
  operative_note          text,
  supervisor_note         text,
  supervisor_reviewed_by  uuid references auth.users(id) on delete restrict,
  supervisor_reviewed_at  timestamptz,
  supervisor_verified     boolean not null default false,
  follow_up_required      boolean not null default false,   -- "needs review" / carry-forward
  completed_at            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (generated_visit_task_id),
  foreign key (generated_visit_task_id, visit_instance_id)
    references public.v2_generated_visit_tasks(id, visit_instance_id) on delete restrict,
  constraint v2vtr_rating_or_na_chk
    check ((is_na = true and rating is null and coalesce(na_reason,'') <> '') or (is_na = false)),
  rating_band_display text generated always as (
    case when is_na then 'na' when rating is null then null
         when rating <= 2 then 'red' when rating = 3 then 'amber' else 'green' end) stored,
  is_failure boolean generated always as (rating is not null and rating <= 2) stored
);
create index if not exists v2vtr_visit_idx on public.v2_visit_task_results(visit_instance_id);
grant select on public.v2_visit_task_results to authenticated;
grant all on public.v2_visit_task_results to service_role;
alter table public.v2_visit_task_results enable row level security;
drop trigger if exists trg_v2vtr_updated_at on public.v2_visit_task_results;
create trigger trg_v2vtr_updated_at before update on public.v2_visit_task_results
  for each row execute function public.tms_set_updated_at();
create policy "v2_vtr_read" on public.v2_visit_task_results for select to authenticated
  using (exists (select 1 from public.v2_visit_instances vi
                 where vi.id = visit_instance_id
                   and tms_internal.has_any_site_access(auth.uid(), vi.site_id)));

-- ---------- v2_visit_task_evidence (v2 owns evidence; reuses the storage bucket only) ----------
create table if not exists public.v2_visit_task_evidence (
  id                      uuid primary key default gen_random_uuid(),
  generated_visit_task_id uuid not null references public.v2_generated_visit_tasks(id) on delete restrict,
  bucket                  text not null default 'evidence',
  storage_path            text not null,
  mime_type               text,
  byte_size               bigint,
  caption                 text,
  uploaded_by             uuid references auth.users(id) on delete restrict,
  created_at              timestamptz not null default now(),
  unique (bucket, storage_path)
);
create index if not exists v2vte_task_idx on public.v2_visit_task_evidence(generated_visit_task_id);
grant select on public.v2_visit_task_evidence to authenticated;
grant all on public.v2_visit_task_evidence to service_role;
alter table public.v2_visit_task_evidence enable row level security;
create policy "v2_vte_read" on public.v2_visit_task_evidence for select to authenticated
  using (exists (select 1 from public.v2_generated_visit_tasks g
                 where g.id = generated_visit_task_id
                   and tms_internal.has_any_site_access(auth.uid(), g.site_id)));

-- =====================================================================
-- Rotation maths — database-calculated. NULL anchor => inactive (no rotation).
--   cycle_position = floor((visit_date - anchor_start_date)/7) % cycle_length + 1
-- =====================================================================
create or replace function tms_internal.v2_active_segment_position(_anchor uuid, _visit_date date)
returns int language sql stable security definer set search_path = pg_catalog, public as $$
  select case when ra.anchor_start_date is null then null
              else (floor(((_visit_date - ra.anchor_start_date)::int) / 7.0)::int
                    % ra.cycle_length) + 1 end
    from public.v2_rotation_anchors ra where ra.id = _anchor;
$$;
revoke all on function tms_internal.v2_active_segment_position(uuid, date) from public, anon;
grant execute on function tms_internal.v2_active_segment_position(uuid, date) to authenticated;

-- =====================================================================
-- Generation — the DATABASE decides what is due. Idempotent.
-- =====================================================================
create or replace function public.rpc_v2_generate_visit_tasks(p_visit_instance_id uuid)
returns int language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_uid uuid := auth.uid();
  v_site uuid; v_schedule uuid; v_date date;
  v_anchor record; v_pos int; v_segment uuid;
  v_prior uuid; v_count int := 0;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  select site_id, service_schedule_id, visit_date into v_site, v_schedule, v_date
    from public.v2_visit_instances where id = p_visit_instance_id;
  if v_site is null then raise exception 'v2 visit not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['tms_admin','tms_supervisor','tms_operative']) then raise exception 'forbidden'; end if;

  -- 1) Baseline (always due). Out-of-scope areas excluded.
  insert into public.v2_generated_visit_tasks(
    visit_instance_id, site_id, service_schedule_id, task_source, area_id, area_snapshot,
    sub_area_id, task_template_id, task_family_code, task_name_snapshot, acceptance_snapshot,
    is_due, requires_supervisor_verification, display_order)
  select p_visit_instance_id, v_site, v_schedule, 'baseline', sbt.area_id, a.name,
         sbt.sub_area_id, sbt.task_template_id, tt.task_family_code, tt.name, tt.acceptance_criteria,
         true, tt.requires_supervisor_verification, sbt.display_order
    from public.v2_schedule_baseline_tasks sbt
    join public.v2_task_templates tt on tt.id = sbt.task_template_id
    left join public.v2_areas a on a.id = sbt.area_id
   where sbt.service_schedule_id = v_schedule and sbt.archived_at is null
     and (a.id is null or a.is_out_of_scope = false)
     and not exists (select 1 from public.v2_generated_visit_tasks g
                     where g.visit_instance_id = p_visit_instance_id and g.task_source='baseline'
                       and g.task_template_id = sbt.task_template_id
                       and g.area_id is not distinct from sbt.area_id
                       and g.sub_area_id is not distinct from sbt.sub_area_id);
  get diagnostics v_count = row_count;

  -- 2) Rotation (only the active segment; non-active segments are never inserted,
  --    so they can never become a false failure).
  for v_anchor in
    select * from public.v2_rotation_anchors
     where service_schedule_id = v_schedule and archived_at is null and anchor_start_date is not null
  loop
    v_pos := tms_internal.v2_active_segment_position(v_anchor.id, v_date);
    if v_pos is null then continue; end if;
    select id into v_segment from public.v2_rotation_segments
      where rotation_anchor_id = v_anchor.id and position = v_pos and archived_at is null;
    if v_segment is null then continue; end if;
    insert into public.v2_generated_visit_tasks(
      visit_instance_id, site_id, service_schedule_id, task_source, rotation_anchor_id,
      rotation_segment_id, area_id, area_snapshot, sub_area_id, task_template_id, task_family_code,
      task_name_snapshot, acceptance_snapshot, is_due, requires_supervisor_verification, display_order)
    select p_visit_instance_id, v_site, v_schedule, 'rotation', v_anchor.id, v_segment,
           rst.area_id, a.name, rst.sub_area_id, rst.task_template_id, tt.task_family_code,
           tt.name, tt.acceptance_criteria, true, tt.requires_supervisor_verification, rst.display_order
      from public.v2_rotation_segment_tasks rst
      join public.v2_task_templates tt on tt.id = rst.task_template_id
      left join public.v2_areas a on a.id = rst.area_id
     where rst.rotation_segment_id = v_segment and rst.archived_at is null
       and (a.id is null or a.is_out_of_scope = false)
       and not exists (select 1 from public.v2_generated_visit_tasks g
                       where g.visit_instance_id = p_visit_instance_id and g.task_source='rotation'
                         and g.task_template_id = rst.task_template_id
                         and g.area_id is not distinct from rst.area_id
                         and g.sub_area_id is not distinct from rst.sub_area_id);
  end loop;

  -- 3) Carry-forward: failed/incomplete DUE tasks from the most recent prior visit.
  select id into v_prior from public.v2_visit_instances
   where site_id = v_site and service_schedule_id = v_schedule
     and visit_date < v_date and status <> 'cancelled'
   order by visit_date desc limit 1;
  if v_prior is not null then
    insert into public.v2_generated_visit_tasks(
      visit_instance_id, site_id, service_schedule_id, task_source, area_id, area_snapshot,
      sub_area_id, other_sub_area_text, task_template_id, other_task_text, task_family_code,
      task_name_snapshot, acceptance_snapshot, is_due, requires_supervisor_verification,
      carried_from_task_id, display_order)
    select p_visit_instance_id, v_site, v_schedule, 'carry_forward', g.area_id, g.area_snapshot,
           g.sub_area_id, g.other_sub_area_text, g.task_template_id, g.other_task_text, g.task_family_code,
           g.task_name_snapshot, g.acceptance_snapshot, true, g.requires_supervisor_verification,
           g.id, g.display_order
      from public.v2_generated_visit_tasks g
      join public.v2_visit_task_results r on r.generated_visit_task_id = g.id
     where g.visit_instance_id = v_prior and g.is_due
       and (r.is_failure or r.status in ('not_completed','partial','inaccessible') or r.follow_up_required)
       and not exists (select 1 from public.v2_generated_visit_tasks g2
                       where g2.visit_instance_id = p_visit_instance_id and g2.carried_from_task_id = g.id);
  end if;

  return v_count;
end $$;
revoke all on function public.rpc_v2_generate_visit_tasks(uuid) from public, anon;
grant execute on function public.rpc_v2_generate_visit_tasks(uuid) to authenticated;

-- =====================================================================
-- Create a visit and generate its tasks in one call.
-- =====================================================================
create or replace function public.rpc_v2_create_visit(
  p_site_id uuid, p_service_schedule_id uuid, p_visit_date date)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_existing uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if not tms_internal.has_site_role(v_uid, p_site_id,
       array['tms_admin','tms_supervisor','tms_operative']) then raise exception 'forbidden'; end if;
  if not exists (select 1 from public.v2_service_schedules
                 where id = p_service_schedule_id and site_id = p_site_id and archived_at is null) then
    raise exception 'invalid service_schedule for site';
  end if;

  select id into v_existing from public.v2_visit_instances
   where site_id = p_site_id and service_schedule_id = p_service_schedule_id
     and visit_date = p_visit_date and status <> 'cancelled' limit 1;
  if v_existing is not null then
    perform public.rpc_v2_generate_visit_tasks(v_existing);  -- idempotent top-up
    return v_existing;
  end if;

  insert into public.v2_visit_instances(site_id, service_schedule_id, visit_date, status,
    supervisor_id, created_by)
  values (p_site_id, p_service_schedule_id, p_visit_date, 'planned', v_uid, v_uid)
  returning id into v_id;
  perform public.rpc_v2_generate_visit_tasks(v_id);
  return v_id;
end $$;
revoke all on function public.rpc_v2_create_visit(uuid, uuid, date) from public, anon;
grant execute on function public.rpc_v2_create_visit(uuid, uuid, date) to authenticated;

-- =====================================================================
-- Record a task result/rating (operative). Upsert; one result per task.
-- =====================================================================
create or replace function public.rpc_v2_record_result(
  p_generated_visit_task_id uuid, p_status text, p_rating int default null,
  p_is_na boolean default false, p_na_reason text default null,
  p_operative_note text default null, p_follow_up_required boolean default false)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_uid uuid := auth.uid(); v_site uuid; v_visit uuid; v_result uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  select g.site_id, g.visit_instance_id into v_site, v_visit
    from public.v2_generated_visit_tasks g where g.id = p_generated_visit_task_id;
  if v_site is null then raise exception 'task not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site,
       array['tms_admin','tms_supervisor','tms_operative']) then raise exception 'forbidden'; end if;

  insert into public.v2_visit_task_results(
    generated_visit_task_id, visit_instance_id, status, rating, is_na, na_reason,
    operative_note, follow_up_required,
    completed_at)
  values (p_generated_visit_task_id, v_visit, nullif(p_status,'')::public.v2_result_status,
          case when p_is_na then null else p_rating end::smallint, coalesce(p_is_na,false), p_na_reason,
          p_operative_note, coalesce(p_follow_up_required,false),
          case when p_status in ('completed','partial') then now() else null end)
  on conflict (generated_visit_task_id) do update set
    status = excluded.status, rating = excluded.rating, is_na = excluded.is_na,
    na_reason = excluded.na_reason, operative_note = excluded.operative_note,
    follow_up_required = excluded.follow_up_required, completed_at = excluded.completed_at
  returning id into v_result;
  return v_result;
end $$;
revoke all on function public.rpc_v2_record_result(uuid, text, int, boolean, text, text, boolean) from public, anon;
grant execute on function public.rpc_v2_record_result(uuid, text, int, boolean, text, text, boolean) to authenticated;

-- =====================================================================
-- Supervisor verification (supervisor/admin only). Attaches to the result row.
-- =====================================================================
create or replace function public.rpc_v2_supervisor_verify(
  p_generated_visit_task_id uuid, p_verified boolean, p_supervisor_note text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_uid uuid := auth.uid(); v_site uuid; v_visit uuid; v_result uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  select g.site_id, g.visit_instance_id into v_site, v_visit
    from public.v2_generated_visit_tasks g where g.id = p_generated_visit_task_id;
  if v_site is null then raise exception 'task not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site, array['tms_admin','tms_supervisor']) then
    raise exception 'forbidden';
  end if;

  insert into public.v2_visit_task_results(generated_visit_task_id, visit_instance_id,
    supervisor_reviewed_by, supervisor_reviewed_at, supervisor_verified, supervisor_note)
  values (p_generated_visit_task_id, v_visit, v_uid, now(), coalesce(p_verified,false), p_supervisor_note)
  on conflict (generated_visit_task_id) do update set
    supervisor_reviewed_by = v_uid, supervisor_reviewed_at = now(),
    supervisor_verified = coalesce(p_verified,false), supervisor_note = p_supervisor_note
  returning id into v_result;
  return v_result;
end $$;
revoke all on function public.rpc_v2_supervisor_verify(uuid, boolean, text) from public, anon;
grant execute on function public.rpc_v2_supervisor_verify(uuid, boolean, text) to authenticated;

-- =====================================================================
-- Set / change a rotation anchor start date (admin or supervisor on the site).
-- =====================================================================
create or replace function public.rpc_v2_set_rotation_anchor(p_anchor_id uuid, p_anchor_start_date date)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_uid uuid := auth.uid(); v_site uuid;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode='28000'; end if;
  select site_id into v_site from public.v2_rotation_anchors where id = p_anchor_id;
  if v_site is null then raise exception 'anchor not found'; end if;
  if not tms_internal.has_site_role(v_uid, v_site, array['tms_admin','tms_supervisor']) then
    raise exception 'forbidden';
  end if;
  update public.v2_rotation_anchors set anchor_start_date = p_anchor_start_date where id = p_anchor_id;
end $$;
revoke all on function public.rpc_v2_set_rotation_anchor(uuid, date) from public, anon;
grant execute on function public.rpc_v2_set_rotation_anchor(uuid, date) to authenticated;

-- =====================================================================
-- Reporting — provenance + outcome per generated task.
-- =====================================================================
create or replace view public.v_v2_visit_task_report with (security_invoker = true) as
select
  g.id as generated_visit_task_id,
  g.visit_instance_id,
  g.site_id,
  g.service_schedule_id,
  g.task_source,
  g.is_due,
  coalesce(g.area_snapshot, '(none)') as area,
  coalesce(sa.name, g.other_sub_area_text) as sub_area,
  g.task_name_snapshot as task,
  g.task_family_code,
  g.requires_supervisor_verification,
  r.status,
  r.rating,
  r.is_na,
  r.rating_band_display,
  r.is_failure,
  r.supervisor_verified,
  r.follow_up_required,
  case
    when r.id is null and g.is_due then 'due_not_recorded'
    when r.is_failure then 'failed'
    when r.status = 'not_completed' then 'missed'
    when r.status = 'partial' then 'partial'
    when r.status = 'not_applicable' then 'n/a'
    when r.status = 'completed' then 'completed'
    else 'recorded'
  end as outcome
from public.v2_generated_visit_tasks g
left join public.v2_sub_areas sa on sa.id = g.sub_area_id
left join public.v2_visit_task_results r on r.generated_visit_task_id = g.id;
grant select on public.v_v2_visit_task_report to authenticated;
