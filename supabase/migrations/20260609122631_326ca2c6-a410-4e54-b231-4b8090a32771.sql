
-- ---------- reviews ----------
create table if not exists public.reviews (
  id                      uuid primary key default gen_random_uuid(),
  cleaning_visit_id       uuid not null references public.cleaning_visits(id) on delete restrict,
  review_type             public.review_type not null default 'dm_lightweight',
  status                  public.review_status not null default 'draft',
  version_no              bigint not null default 1,
  reviewer_id             uuid references auth.users(id) on delete restrict,
  submitted_at            timestamptz,
  superseded_at           timestamptz,
  superseded_by_review_id uuid references public.reviews(id) on delete restrict,
  supersedes_review_id    uuid references public.reviews(id) on delete restrict,
  general_comment         text,
  urgent_hs_flag          boolean not null default false,
  urgent_hs_detail        text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (supersedes_review_id is null or supersedes_review_id <> id)
);
-- One direct successor per review
create unique index if not exists reviews_supersedes_uidx
  on public.reviews(supersedes_review_id) where supersedes_review_id is not null;
create index if not exists reviews_visit_idx on public.reviews(cleaning_visit_id);

grant select on public.reviews to authenticated;
grant all on public.reviews to service_role;
alter table public.reviews enable row level security;
drop trigger if exists trg_reviews_updated_at on public.reviews;
create trigger trg_reviews_updated_at before update on public.reviews
  for each row execute function public.tms_set_updated_at();
create policy "reviews_read_with_site_access"
  on public.reviews for select to authenticated
  using (exists (
    select 1 from public.cleaning_visits cv
    where cv.id = cleaning_visit_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- Review immutability trigger: blocks all non-supersede edits once status in (submitted, superseded)
create or replace function public.tms_protect_submitted_review()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'DELETE' then
    if old.status in ('submitted','superseded') then
      raise exception 'submitted reviews are immutable (id=%)', old.id;
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.status in ('submitted','superseded') then
    -- Allow exactly: submitted -> superseded, changing only status/superseded_at/superseded_by_review_id
    if old.status = 'submitted' and new.status = 'superseded' then
      if new.id <> old.id
         or new.cleaning_visit_id <> old.cleaning_visit_id
         or new.review_type <> old.review_type
         or new.reviewer_id is distinct from old.reviewer_id
         or new.submitted_at is distinct from old.submitted_at
         or new.general_comment is distinct from old.general_comment
         or new.urgent_hs_flag is distinct from old.urgent_hs_flag
         or new.urgent_hs_detail is distinct from old.urgent_hs_detail
         or new.supersedes_review_id is distinct from old.supersedes_review_id
         or new.version_no <> old.version_no then
        raise exception 'only status/superseded_at/superseded_by_review_id may change in supersede transition';
      end if;
      return new;
    end if;
    raise exception 'submitted reviews are immutable (id=%, % -> %)', old.id, old.status, new.status;
  end if;
  return new;
end;
$$;
revoke execute on function public.tms_protect_submitted_review() from public, anon, authenticated;
drop trigger if exists trg_reviews_immutable on public.reviews;
create trigger trg_reviews_immutable
  before update or delete on public.reviews
  for each row execute function public.tms_protect_submitted_review();

-- ---------- review_line_scores ----------
create table if not exists public.review_line_scores (
  id                      uuid primary key default gen_random_uuid(),
  review_id               uuid not null references public.reviews(id) on delete restrict,
  visit_rating_line_id    uuid not null references public.visit_rating_lines(id) on delete restrict,
  score                   int check (score between 0 and 10),
  rating_band             text check (rating_band in ('green','amber','red','na')),
  comment                 text,
  is_failure              boolean not null default false,
  scope_classification    public.scope_classification,
  issue_type_code         text references public.issue_types(code) on delete restrict,
  urgent_hs_flag          boolean not null default false,
  created_at              timestamptz not null default now(),
  unique (review_id, visit_rating_line_id)
);
grant select on public.review_line_scores to authenticated;
grant all on public.review_line_scores to service_role;
alter table public.review_line_scores enable row level security;
create policy "rls_read_with_site_access"
  on public.review_line_scores for select to authenticated
  using (exists (
    select 1 from public.reviews r
    join public.cleaning_visits cv on cv.id = r.cleaning_visit_id
    where r.id = review_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- Protect child rows of submitted reviews
create or replace function public.tms_protect_review_children()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  v_status public.review_status;
  v_review_id uuid;
begin
  v_review_id := coalesce((case when tg_op='DELETE' then old.review_id else new.review_id end), null);
  select status into v_status from public.reviews where id = v_review_id;
  if v_status in ('submitted','superseded') then
    raise exception 'cannot modify scores of a submitted/superseded review (review %)', v_review_id;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke execute on function public.tms_protect_review_children() from public, anon, authenticated;
drop trigger if exists trg_rls_immutable on public.review_line_scores;
create trigger trg_rls_immutable
  before insert or update or delete on public.review_line_scores
  for each row execute function public.tms_protect_review_children();

-- ---------- focus_item_scores ----------
create table if not exists public.focus_item_scores (
  id                      uuid primary key default gen_random_uuid(),
  review_id               uuid not null references public.reviews(id) on delete restrict,
  visit_focus_item_id     uuid not null references public.visit_focus_items(id) on delete restrict,
  rating_band             text check (rating_band in ('green','amber','red','na')),
  comment                 text,
  is_failure              boolean not null default false,
  scope_classification    public.scope_classification,
  issue_type_code         text references public.issue_types(code) on delete restrict,
  urgent_hs_flag          boolean not null default false,
  created_at              timestamptz not null default now(),
  unique (review_id, visit_focus_item_id)
);
grant select on public.focus_item_scores to authenticated;
grant all on public.focus_item_scores to service_role;
alter table public.focus_item_scores enable row level security;
create policy "fis_read_with_site_access"
  on public.focus_item_scores for select to authenticated
  using (exists (
    select 1 from public.reviews r
    join public.cleaning_visits cv on cv.id = r.cleaning_visit_id
    where r.id = review_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));
drop trigger if exists trg_fis_immutable on public.focus_item_scores;
create trigger trg_fis_immutable
  before insert or update or delete on public.focus_item_scores
  for each row execute function public.tms_protect_review_children();

-- ---------- evidence_items ----------
create table if not exists public.evidence_items (
  id            uuid primary key default gen_random_uuid(),
  site_id       uuid not null references public.sites(id) on delete restrict,
  bucket        text not null default 'evidence',
  storage_path  text not null,
  mime_type     text,
  byte_size     bigint,
  uploaded_by   uuid references auth.users(id) on delete restrict,
  created_at    timestamptz not null default now(),
  unique (bucket, storage_path)
);
grant select on public.evidence_items to authenticated;
grant all on public.evidence_items to service_role;
alter table public.evidence_items enable row level security;
create policy "ev_read_with_site_access"
  on public.evidence_items for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- Link tables
create table if not exists public.visit_focus_item_evidence (
  visit_focus_item_id  uuid not null references public.visit_focus_items(id) on delete restrict,
  evidence_item_id     uuid not null references public.evidence_items(id) on delete restrict,
  caption              text,
  created_at           timestamptz not null default now(),
  primary key (visit_focus_item_id, evidence_item_id)
);
grant select on public.visit_focus_item_evidence to authenticated;
grant all on public.visit_focus_item_evidence to service_role;
alter table public.visit_focus_item_evidence enable row level security;
create policy "vfie_read" on public.visit_focus_item_evidence for select to authenticated
  using (exists (
    select 1 from public.visit_focus_items vfi
    join public.cleaning_visits cv on cv.id = vfi.cleaning_visit_id
    where vfi.id = visit_focus_item_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

create table if not exists public.review_line_score_evidence (
  review_line_score_id uuid not null references public.review_line_scores(id) on delete restrict,
  evidence_item_id     uuid not null references public.evidence_items(id) on delete restrict,
  caption              text,
  created_at           timestamptz not null default now(),
  primary key (review_line_score_id, evidence_item_id)
);
grant select on public.review_line_score_evidence to authenticated;
grant all on public.review_line_score_evidence to service_role;
alter table public.review_line_score_evidence enable row level security;
create policy "rlse_read" on public.review_line_score_evidence for select to authenticated
  using (exists (
    select 1 from public.review_line_scores rls
    join public.reviews r on r.id = rls.review_id
    join public.cleaning_visits cv on cv.id = r.cleaning_visit_id
    where rls.id = review_line_score_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

create table if not exists public.focus_item_score_evidence (
  focus_item_score_id uuid not null references public.focus_item_scores(id) on delete restrict,
  evidence_item_id    uuid not null references public.evidence_items(id) on delete restrict,
  caption             text,
  created_at          timestamptz not null default now(),
  primary key (focus_item_score_id, evidence_item_id)
);
grant select on public.focus_item_score_evidence to authenticated;
grant all on public.focus_item_score_evidence to service_role;
alter table public.focus_item_score_evidence enable row level security;
create policy "fise_read" on public.focus_item_score_evidence for select to authenticated
  using (exists (
    select 1 from public.focus_item_scores fis
    join public.reviews r on r.id = fis.review_id
    join public.cleaning_visits cv on cv.id = r.cleaning_visit_id
    where fis.id = focus_item_score_id
      and tms_internal.has_any_site_access(auth.uid(), cv.site_id)
  ));

-- ---------- actions ----------
create table if not exists public.actions (
  id                          uuid primary key default gen_random_uuid(),
  site_id                     uuid not null references public.sites(id) on delete restrict,
  cleaning_visit_id           uuid references public.cleaning_visits(id) on delete restrict,
  title                       text not null,
  description                 text,
  scope_classification        public.scope_classification not null,
  priority                    public.action_priority not null default 'normal',
  status                      public.action_status not null default 'open',
  version_no                  bigint not null default 1,
  due_date                    date,
  assignee_id                 uuid references auth.users(id) on delete restrict,
  source_review_line_score_id uuid references public.review_line_scores(id) on delete restrict,
  source_focus_item_score_id  uuid references public.focus_item_scores(id) on delete restrict,
  source_constraint_id        uuid references public.visit_constraints(id) on delete restrict,
  urgent_hs_flag              boolean not null default false,
  created_by                  uuid references auth.users(id) on delete restrict,
  closed_at                   timestamptz,
  cancelled_at                timestamptz,
  verification_note           text,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);
-- Duplicate-action prevention while live
create unique index if not exists actions_src_rls_uidx on public.actions(source_review_line_score_id)
  where source_review_line_score_id is not null and status not in ('closed','cancelled');
create unique index if not exists actions_src_fis_uidx on public.actions(source_focus_item_score_id)
  where source_focus_item_score_id is not null and status not in ('closed','cancelled');
create unique index if not exists actions_src_constraint_uidx on public.actions(source_constraint_id)
  where source_constraint_id is not null and status not in ('closed','cancelled');
create index if not exists actions_site_status_idx on public.actions(site_id, status);

grant select on public.actions to authenticated;
grant all on public.actions to service_role;
alter table public.actions enable row level security;
drop trigger if exists trg_actions_updated_at on public.actions;
create trigger trg_actions_updated_at before update on public.actions
  for each row execute function public.tms_set_updated_at();
create policy "actions_read_with_site_access"
  on public.actions for select to authenticated
  using (tms_internal.has_any_site_access(auth.uid(), site_id));

-- Action lifecycle trigger
create or replace function public.tms_validate_action_transition()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
declare
  ok boolean := false;
begin
  if old.status = new.status then return new; end if;

  ok := case old.status
    when 'open'::public.action_status then
      new.status in ('assigned','in_progress','cancelled')::public.action_status[]
    when 'assigned'::public.action_status then
      new.status in ('in_progress','blocked','cancelled')::public.action_status[]
    when 'in_progress'::public.action_status then
      new.status in ('blocked','awaiting_verification','cancelled')::public.action_status[]
    when 'blocked'::public.action_status then
      new.status in ('in_progress','cancelled')::public.action_status[]
    when 'awaiting_verification'::public.action_status then
      new.status in ('closed','in_progress','cancelled')::public.action_status[]
    else false
  end;
  if not ok then
    raise exception 'illegal action status transition: % -> %', old.status, new.status
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function public.tms_validate_action_transition() from public, anon, authenticated;
drop trigger if exists trg_actions_transition on public.actions;
create trigger trg_actions_transition
  before update of status on public.actions
  for each row execute function public.tms_validate_action_transition();

-- ---------- activity_log ----------
create table if not exists public.activity_log (
  id            bigserial primary key,
  site_id       uuid references public.sites(id) on delete restrict,
  actor_id      uuid references auth.users(id) on delete restrict,
  entity_kind   text not null,
  entity_id     uuid not null,
  action        text not null,
  detail        jsonb,
  created_at    timestamptz not null default now()
);
grant select on public.activity_log to authenticated;
grant all on public.activity_log to service_role;
alter table public.activity_log enable row level security;
create index if not exists al_entity_idx on public.activity_log(entity_kind, entity_id, created_at desc);
create index if not exists al_site_idx on public.activity_log(site_id, created_at desc);
create policy "al_read_with_site_access"
  on public.activity_log for select to authenticated
  using (site_id is null and tms_internal.is_tms_admin(auth.uid())
      or tms_internal.has_any_site_access(auth.uid(), site_id));
