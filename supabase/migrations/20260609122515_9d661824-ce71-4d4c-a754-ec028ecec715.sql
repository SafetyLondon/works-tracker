
-- ---------- cleaning_visits ----------
create table if not exists public.cleaning_visits (
  id                          uuid primary key default gen_random_uuid(),
  site_id                     uuid not null references public.sites(id) on delete restrict,
  visit_template_id           uuid not null references public.visit_templates(id) on delete restrict,
  rotation_programme_id       uuid references public.rotation_programmes(id) on delete restrict,
  visit_date                  date not null,
  recommended_rotation_week   int,
  rotation_week_override      int,
  rotation_week_override_reason text,
  weekday_override_reason     text,
  status                      public.cleaning_visit_status not null default 'draft',
  version_no                  bigint not null default 1,
  supervisor_id               uuid references auth.users(id) on delete restrict,
  submitted_at                timestamptz,
  submitted_by                uuid references auth.users(id) on delete restrict,
  reviewed_at                 timestamptz,
  closed_at                   timestamptz,
  cancelled_at                timestamptz,
  notes                       text,
  weather                     text,
  headcount                   int,
  created_by                  uuid references auth.users(id) on delete restrict,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  check ( (rotation_week_override is null and rotation_week_override_reason is null)
       or (rotation_week_override is not null and rotation_week_override_reason is not null) )
);
-- Composite uniques used by children
create unique index if not exists cv_id_template_uidx
  on public.cleaning_visits(id, visit_template_id);
create unique index if not exists cv_id_site_uidx
  on public.cleaning_visits(id, site_id);
create index if not exists cv_site_date_idx
  on public.cleaning_visits(site_id, visit_date desc);
create index if not exists cv_status_idx on public.cleaning_visits(status);

grant select on public.cleaning_visits to authenticated;
grant all on public.cleaning_visits to service_role;
alter table public.cleaning_visits enable row level security;
drop trigger if exists trg_cv_updated_at on public.cleaning_visits;
create trigger trg_cv_updated_at before update on public.cleaning_visits
  for each row execute function public.tms_set_updated_at();

create policy "cv_read_with_site_access"
  on public.cleaning_visits for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- Declarative lifecycle trigger
create or replace function public.tms_validate_visit_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  ok boolean := false;
begin
  if old.status = new.status then
    return new;  -- non-status update; allowed (column-level rules handled elsewhere)
  end if;

  -- Explicit allow-list
  ok := case old.status
    when 'draft'::public.cleaning_visit_status then
      new.status in ('planned','in_progress','cancelled')::public.cleaning_visit_status[]
    when 'planned'::public.cleaning_visit_status then
      new.status in ('in_progress','cancelled')::public.cleaning_visit_status[]
    when 'in_progress'::public.cleaning_visit_status then
      new.status in ('submitted_for_review','cancelled')::public.cleaning_visit_status[]
    when 'submitted_for_review'::public.cleaning_visit_status then
      new.status in ('reviewed','in_progress','cancelled')::public.cleaning_visit_status[]
    when 'reviewed'::public.cleaning_visit_status then
      new.status in ('closed','in_progress')::public.cleaning_visit_status[]
    when 'closed'::public.cleaning_visit_status then
      new.status in ('in_progress')::public.cleaning_visit_status[]
    else false
  end;

  if not ok then
    raise exception 'illegal cleaning_visit status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function public.tms_validate_visit_transition() from public, anon, authenticated;

drop trigger if exists trg_cv_transition on public.cleaning_visits;
create trigger trg_cv_transition
  before update of status on public.cleaning_visits
  for each row execute function public.tms_validate_visit_transition();

-- ---------- visit_scope_snapshots ----------
create table if not exists public.visit_scope_snapshots (
  id                  uuid primary key default gen_random_uuid(),
  cleaning_visit_id   uuid not null references public.cleaning_visits(id) on delete restrict,
  item_type           text not null check (item_type in
                        ('primary_area','base_task','secondary_maintenance','limitation')),
  label_snapshot      text not null,
  description_snapshot text,
  display_order       int not null default 0,
  source_template_scope_item_id uuid references public.template_scope_items(id) on delete restrict,
  created_at          timestamptz not null default now()
);
grant select on public.visit_scope_snapshots to authenticated;
grant all on public.visit_scope_snapshots to service_role;
alter table public.visit_scope_snapshots enable row level security;
create index if not exists vss_visit_idx on public.visit_scope_snapshots(cleaning_visit_id);
create policy "vss_read_with_site_access"
  on public.visit_scope_snapshots for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- visit_rating_lines ----------
create table if not exists public.visit_rating_lines (
  id                       uuid primary key default gen_random_uuid(),
  cleaning_visit_id        uuid not null,
  visit_template_id        uuid not null,
  template_rating_line_id  uuid not null,
  label_snapshot           text not null,
  description_snapshot     text,
  display_order            int not null default 0,
  created_at               timestamptz not null default now(),
  foreign key (cleaning_visit_id, visit_template_id)
    references public.cleaning_visits(id, visit_template_id) on delete restrict,
  foreign key (template_rating_line_id, visit_template_id)
    references public.template_rating_lines(id, visit_template_id) on delete restrict
);
grant select on public.visit_rating_lines to authenticated;
grant all on public.visit_rating_lines to service_role;
alter table public.visit_rating_lines enable row level security;
create index if not exists vrl_visit_idx on public.visit_rating_lines(cleaning_visit_id);
create policy "vrl_read_with_site_access"
  on public.visit_rating_lines for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- visit_focus_recommendations ----------
create table if not exists public.visit_focus_recommendations (
  id                       uuid primary key default gen_random_uuid(),
  cleaning_visit_id        uuid not null references public.cleaning_visits(id) on delete restrict,
  focus_item_id            uuid references public.focus_items(id) on delete restrict,
  focus_label_snapshot     text not null,
  focus_description_snapshot text,
  recommendation_status    text not null default 'pending'
    check (recommendation_status in ('pending','selected','skipped','inaccessible','not_applicable')),
  resolution_reason        text,
  display_order            int not null default 0,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
grant select on public.visit_focus_recommendations to authenticated;
grant all on public.visit_focus_recommendations to service_role;
alter table public.visit_focus_recommendations enable row level security;
create index if not exists vfr_visit_idx on public.visit_focus_recommendations(cleaning_visit_id);
drop trigger if exists trg_vfr_updated_at on public.visit_focus_recommendations;
create trigger trg_vfr_updated_at before update on public.visit_focus_recommendations
  for each row execute function public.tms_set_updated_at();
create policy "vfr_read_with_site_access"
  on public.visit_focus_recommendations for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- visit_focus_items ----------
create table if not exists public.visit_focus_items (
  id                          uuid primary key default gen_random_uuid(),
  cleaning_visit_id           uuid not null references public.cleaning_visits(id) on delete restrict,
  focus_item_id               uuid references public.focus_items(id) on delete restrict,
  source_recommendation_id    uuid references public.visit_focus_recommendations(id) on delete restrict,
  focus_name_snapshot         text not null,
  description_snapshot        text,
  exact_location              text,
  status                      public.focus_item_status not null default 'selected',
  completion_note             text,
  completed_at                timestamptz,
  display_order               int not null default 0,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);
grant select on public.visit_focus_items to authenticated;
grant all on public.visit_focus_items to service_role;
alter table public.visit_focus_items enable row level security;
create index if not exists vfi_visit_idx on public.visit_focus_items(cleaning_visit_id);
drop trigger if exists trg_vfi_updated_at on public.visit_focus_items;
create trigger trg_vfi_updated_at before update on public.visit_focus_items
  for each row execute function public.tms_set_updated_at();
create policy "vfi_read_with_site_access"
  on public.visit_focus_items for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- Focus item state trigger
create or replace function public.tms_validate_focus_item()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status in ('completed','partially_completed') and new.completed_at is null then
    raise exception 'completed_at required for status %', new.status;
  end if;
  if new.status not in ('completed','partially_completed') and new.completed_at is not null then
    raise exception 'completed_at must be null when status is %', new.status;
  end if;
  -- Ad-hoc rows (no focus_item_id) require an exact_location and completion_note
  if new.focus_item_id is null
     and (coalesce(new.exact_location, '') = '' or coalesce(new.focus_name_snapshot, '') = '') then
    raise exception 'ad-hoc focus item requires focus_name_snapshot and exact_location';
  end if;
  return new;
end;
$$;
revoke execute on function public.tms_validate_focus_item() from public, anon, authenticated;
drop trigger if exists trg_vfi_validate on public.visit_focus_items;
create trigger trg_vfi_validate before insert or update on public.visit_focus_items
  for each row execute function public.tms_validate_focus_item();

-- ---------- visit_constraints ----------
create table if not exists public.visit_constraints (
  id                  uuid primary key default gen_random_uuid(),
  cleaning_visit_id   uuid not null references public.cleaning_visits(id) on delete restrict,
  constraint_type     text not null references public.constraint_types(code) on delete restrict,
  description         text not null,
  affected_area       text,
  created_at          timestamptz not null default now()
);
grant select on public.visit_constraints to authenticated;
grant all on public.visit_constraints to service_role;
alter table public.visit_constraints enable row level security;
create index if not exists vc_visit_idx on public.visit_constraints(cleaning_visit_id);
create policy "vc_read_with_site_access"
  on public.visit_constraints for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- visit_team_members ----------
create table if not exists public.visit_team_members (
  id                  uuid primary key default gen_random_uuid(),
  cleaning_visit_id   uuid not null references public.cleaning_visits(id) on delete restrict,
  user_id             uuid references auth.users(id) on delete restrict,
  full_name           text,
  role_on_visit       text not null references public.visit_team_role_options(code) on delete restrict,
  created_at          timestamptz not null default now()
);
grant select on public.visit_team_members to authenticated;
grant all on public.visit_team_members to service_role;
alter table public.visit_team_members enable row level security;
create index if not exists vtm_visit_idx on public.visit_team_members(cleaning_visit_id);
create policy "vtm_read_with_site_access"
  on public.visit_team_members for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));
