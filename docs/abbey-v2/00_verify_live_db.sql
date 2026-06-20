-- =====================================================================
-- Abbey v2 — READ-ONLY pre-flight verification
-- =====================================================================
-- Run this in the Lovable / Supabase SQL editor and paste the output back.
-- It performs NO writes. Goal: confirm whether the live DB holds real
-- operational history (which must be preserved) or only seed/demo/test data,
-- before any v2 migration is applied.
-- =====================================================================

-- 1) Row counts for the legacy operational tables.
select 'cleaning_visits'              as table, count(*) from public.cleaning_visits
union all select 'visit_rating_lines',          count(*) from public.visit_rating_lines
union all select 'visit_focus_recommendations',  count(*) from public.visit_focus_recommendations
union all select 'visit_focus_items',            count(*) from public.visit_focus_items
union all select 'visit_constraints',            count(*) from public.visit_constraints
union all select 'visit_team_members',           count(*) from public.visit_team_members
union all select 'reviews',                       count(*) from public.reviews
union all select 'review_line_scores',           count(*) from public.review_line_scores
union all select 'focus_item_scores',            count(*) from public.focus_item_scores
union all select 'actions',                       count(*) from public.actions
union all select 'evidence_items',               count(*) from public.evidence_items
union all select 'activity_log',                  count(*) from public.activity_log
order by 1;

-- 2) Does the visit data look like real operational history?
--    (distinct supervisors, date span, how many progressed past 'planned',
--     how many reviews were actually submitted, how much evidence exists.)
select
  (select count(distinct supervisor_id) from public.cleaning_visits)          as distinct_supervisors,
  (select min(visit_date) from public.cleaning_visits)                         as earliest_visit,
  (select max(visit_date) from public.cleaning_visits)                         as latest_visit,
  (select count(*) from public.cleaning_visits
     where status not in ('draft','planned','cancelled'))                      as visits_progressed,
  (select count(*) from public.reviews where status = 'submitted')             as submitted_reviews,
  (select count(*) from public.review_line_scores)                             as line_scores,
  (select count(*) from public.focus_item_scores)                              as focus_scores,
  (select count(*) from public.actions where status not in ('open','cancelled')) as actions_worked,
  (select count(*) from public.evidence_items)                                 as evidence_files;

-- 3) Would any v2 table name collide with something already present?
--    (v2 is additive — these should all be 'absent'.)
select t as v2_table,
       case when to_regclass('public.' || t) is null then 'absent (ok)' else 'ALREADY EXISTS' end as state
from unnest(array[
  'areas','sub_areas','task_families','task_templates','service_schedules',
  'schedule_baseline_tasks','rotation_anchors','rotation_segments',
  'rotation_segment_tasks','generated_visit_tasks','visit_task_results',
  'generated_visit_task_evidence'
]) as t
order by t;

-- 4) Confirm the shared infra v2 will reference is present and as expected.
select 'sites'           as dependency, count(*) from public.sites
union all select 'visit_templates (legacy bridge)', count(*) from public.visit_templates
union all select 'evidence_items',                  count(*) from public.evidence_items;

-- Interpretation guide:
--   * If section 2 shows 0 submitted_reviews / 0 scores / 0 evidence and only a
--     handful of recent same-supervisor visits, it is seed/demo/test -> safe to
--     proceed with a fresh Abbey v2 seed.
--   * If there are submitted reviews, scores, worked actions or evidence files,
--     that is real history: keep it as legacy, build v2 alongside (no deletes).
