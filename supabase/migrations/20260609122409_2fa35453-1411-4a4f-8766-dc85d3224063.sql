
-- ---------- visit_templates ----------
create table if not exists public.visit_templates (
  id                uuid primary key default gen_random_uuid(),
  site_id           uuid not null references public.sites(id) on delete restrict,
  code              text not null,
  name              text not null,
  expected_weekday  int check (expected_weekday between 0 and 6), -- 0=Sun..6=Sat
  display_summary   text,
  archived_at       timestamptz,
  archived_by       uuid references auth.users(id) on delete restrict,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (site_id, code)
);
-- Composite key support: id+site_id, id+expected used by children
create unique index if not exists visit_templates_id_site_uidx on public.visit_templates(id, site_id);
grant select on public.visit_templates to authenticated;
grant all on public.visit_templates to service_role;
alter table public.visit_templates enable row level security;
drop trigger if exists trg_vt_updated_at on public.visit_templates;
create trigger trg_vt_updated_at before update on public.visit_templates
  for each row execute function public.tms_set_updated_at();
create policy "visit_templates_read_with_site_access"
  on public.visit_templates for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- template_rating_lines ----------
create table if not exists public.template_rating_lines (
  id                 uuid primary key default gen_random_uuid(),
  visit_template_id  uuid not null references public.visit_templates(id) on delete restrict,
  label              text not null,
  description        text,
  display_order      int not null default 0,
  archived_at        timestamptz,
  created_at         timestamptz not null default now()
);
-- Composite unique so children can reference (id, visit_template_id)
create unique index if not exists trl_id_template_uidx on public.template_rating_lines(id, visit_template_id);
grant select on public.template_rating_lines to authenticated;
grant all on public.template_rating_lines to service_role;
alter table public.template_rating_lines enable row level security;
create policy "trl_read_with_site_access"
  on public.template_rating_lines for select to authenticated
  using (exists (
    select 1 from public.visit_templates vt
    where vt.id = visit_template_id
      and tms_internal.has_any_site_access(auth.uid(), vt.site_id)
  ));

-- ---------- template_scope_items ----------
create table if not exists public.template_scope_items (
  id                 uuid primary key default gen_random_uuid(),
  visit_template_id  uuid not null references public.visit_templates(id) on delete restrict,
  item_type          text not null check (item_type in
                        ('primary_area','base_task','secondary_maintenance','limitation')),
  label              text not null,
  description        text,
  display_order      int not null default 0,
  archived_at        timestamptz,
  created_at         timestamptz not null default now()
);
grant select on public.template_scope_items to authenticated;
grant all on public.template_scope_items to service_role;
alter table public.template_scope_items enable row level security;
create policy "tsi_read_with_site_access"
  on public.template_scope_items for select to authenticated
  using (exists (
    select 1 from public.visit_templates vt
    where vt.id = visit_template_id
      and tms_internal.has_any_site_access(auth.uid(), vt.site_id)
  ));

-- ---------- rotation_programmes ----------
create table if not exists public.rotation_programmes (
  id                   uuid primary key default gen_random_uuid(),
  site_id              uuid not null references public.sites(id) on delete restrict,
  visit_template_id    uuid not null references public.visit_templates(id) on delete restrict,
  code                 text not null,
  name                 text not null,
  cycle_length_weeks   int not null check (cycle_length_weeks between 1 and 12),
  anchor_date          date not null,
  archived_at          timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.rotation_programmes to authenticated;
grant all on public.rotation_programmes to service_role;
alter table public.rotation_programmes enable row level security;
drop trigger if exists trg_rp_updated_at on public.rotation_programmes;
create trigger trg_rp_updated_at before update on public.rotation_programmes
  for each row execute function public.tms_set_updated_at();
create policy "rp_read_with_site_access"
  on public.rotation_programmes for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- rotation_steps ----------
create table if not exists public.rotation_steps (
  id                       uuid primary key default gen_random_uuid(),
  rotation_programme_id    uuid not null references public.rotation_programmes(id) on delete restrict,
  week_number              int not null check (week_number >= 1),
  title                    text not null,
  description              text,
  display_order            int not null default 0,
  archived_at              timestamptz,
  created_at               timestamptz not null default now(),
  unique (rotation_programme_id, week_number)
);
grant select on public.rotation_steps to authenticated;
grant all on public.rotation_steps to service_role;
alter table public.rotation_steps enable row level security;
create policy "rs_read_with_site_access"
  on public.rotation_steps for select to authenticated
  using (exists (
    select 1 from public.rotation_programmes rp
    where rp.id = rotation_programme_id
      and tms_internal.has_any_site_access(auth.uid(), rp.site_id)
  ));

-- ---------- focus_categories ----------
create table if not exists public.focus_categories (
  id            uuid primary key default gen_random_uuid(),
  site_id       uuid not null references public.sites(id) on delete restrict,
  code          text not null,
  label         text not null,
  display_order int not null default 0,
  archived_at   timestamptz,
  created_at    timestamptz not null default now(),
  unique (site_id, code)
);
grant select on public.focus_categories to authenticated;
grant all on public.focus_categories to service_role;
alter table public.focus_categories enable row level security;
create policy "fc_read_with_site_access"
  on public.focus_categories for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- focus_items ----------
create table if not exists public.focus_items (
  id                       uuid primary key default gen_random_uuid(),
  site_id                  uuid not null references public.sites(id) on delete restrict,
  visit_template_id        uuid references public.visit_templates(id) on delete restrict,
  category_id              uuid references public.focus_categories(id) on delete restrict,
  label                    text not null,
  description              text,
  exact_location_required  boolean not null default true,
  display_order            int not null default 0,
  archived_at              timestamptz,
  created_at               timestamptz not null default now()
);
-- composite unique (id, visit_template_id) used by rotation_step_focus_items FK
create unique index if not exists focus_items_id_template_uidx
  on public.focus_items(id, visit_template_id) where visit_template_id is not null;
grant select on public.focus_items to authenticated;
grant all on public.focus_items to service_role;
alter table public.focus_items enable row level security;
create policy "fi_read_with_site_access"
  on public.focus_items for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- ---------- rotation_step_focus_items ----------
create table if not exists public.rotation_step_focus_items (
  id                  uuid primary key default gen_random_uuid(),
  rotation_step_id    uuid not null references public.rotation_steps(id) on delete restrict,
  focus_item_id       uuid not null references public.focus_items(id) on delete restrict,
  display_order       int not null default 0,
  created_at          timestamptz not null default now(),
  unique (rotation_step_id, focus_item_id)
);
grant select on public.rotation_step_focus_items to authenticated;
grant all on public.rotation_step_focus_items to service_role;
alter table public.rotation_step_focus_items enable row level security;
create policy "rsfi_read_with_site_access"
  on public.rotation_step_focus_items for select to authenticated
  using (exists (
    select 1
    from public.rotation_steps rs
    join public.rotation_programmes rp on rp.id = rs.rotation_programme_id
    where rs.id = rotation_step_id
      and tms_internal.has_any_site_access(auth.uid(), rp.site_id)
  ));

-- ---------- issue_types ----------
create table if not exists public.issue_types (
  code         text primary key,
  label        text not null,
  description  text,
  is_active    boolean not null default true,
  sort_order   int not null default 100,
  created_at   timestamptz not null default now()
);
grant select on public.issue_types to authenticated;
grant all on public.issue_types to service_role;
alter table public.issue_types enable row level security;
create policy "issue_types_read_all" on public.issue_types
  for select to authenticated using (true);

-- ---------- constraint_types ----------
create table if not exists public.constraint_types (
  code         text primary key,
  label        text not null,
  description  text,
  is_active    boolean not null default true,
  sort_order   int not null default 100,
  created_at   timestamptz not null default now()
);
grant select on public.constraint_types to authenticated;
grant all on public.constraint_types to service_role;
alter table public.constraint_types enable row level security;
create policy "constraint_types_read_all" on public.constraint_types
  for select to authenticated using (true);

-- ---------- visit_team_role_options ----------
create table if not exists public.visit_team_role_options (
  code         text primary key,
  label        text not null,
  is_active    boolean not null default true,
  sort_order   int not null default 100
);
grant select on public.visit_team_role_options to authenticated;
grant all on public.visit_team_role_options to service_role;
alter table public.visit_team_role_options enable row level security;
create policy "vtro_read_all" on public.visit_team_role_options
  for select to authenticated using (true);
