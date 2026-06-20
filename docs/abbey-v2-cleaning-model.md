# Abbey v2 Cleaning Model — Design (self-contained, database-first)

**Status:** implemented on branch `abbey-v2` as forward-only migrations, **not yet applied** to the live DB (applies only when the branch is merged to main, which awaits owner approval).

**Architecture (owner decision 2026-06-20):** Abbey v2 is the **operational source of truth**. The **database** decides what is due, what was generated, what was completed, what failed, and what is reported. The frontend never invents due tasks. v2 is **self-contained**: it owns all its operational tables (`v2_*`) and depends on **no legacy operational table**. Legacy tables are kept physically but quarantined architecturally.

## Files

- `supabase/migrations/20260620090000_abbey_v2_schema.sql` — schema, rotation maths, RPCs, reporting view.
- `supabase/migrations/20260620090100_abbey_v2_seed.sql` — idempotent Abbey seed.
- `docs/abbey-v2/00_verify_live_db.sql` — read-only legacy pre-flight (unchanged).
- `docs/abbey-v2/03_v2_smoke_test.sql` — `BEGIN…ROLLBACK` smoke test of the whole flow.
- Frontend: `src/routes/_authenticated/v2.visits.tsx` (+ queries in `src/lib/tms/v2.ts`).

## What v2 reuses vs owns

**Reused (stable auth/identity only):** `auth.users` / `public.profiles` (identity); `public.sites` (clean basic site identity); `public.user_site_roles` + `tms_internal.{is_tms_admin,has_site_role,has_any_site_access}` (access control); `public.tms_set_updated_at()` (generic trigger).

**NOT reused (legacy operational — quarantined):** `cleaning_visits`, `visit_templates`, `template_rating_lines`, `focus_items`, `focus_categories`, `rotation_programmes/steps`, `visit_rating_lines`, `visit_focus_*`, `reviews`, `review_line_scores`, `focus_item_scores`, `evidence_items`, `actions`, `activity_log`. v2 owns clean equivalents instead.

## Tables (all `public.v2_*`)

Catalogue: `v2_areas`, `v2_sub_areas`, `v2_task_families`, `v2_task_templates`.
Schedule/rotation: `v2_service_schedules`, `v2_schedule_baseline_tasks`, `v2_rotation_anchors`, `v2_rotation_segments`, `v2_rotation_segment_tasks`.
Operational: `v2_visit_instances` (v2 owns its visit lifecycle), `v2_generated_visit_tasks` (materialised, knows why it exists), `v2_visit_task_results` (completion + 1–5/N/A + supervisor verification), `v2_visit_task_evidence` (reuses only the storage bucket).

Enums: `v2_task_source` (baseline/rotation/carry_forward/one_off/optional/out_of_scope_observation), `v2_result_status`, `v2_visit_status`.

## Baseline vs rotation vs the rest

`v2_generated_visit_tasks.task_source` records provenance, set by the generator:
- **baseline** — every visit, from `v2_schedule_baseline_tasks`.
- **rotation** — only the **active** segment; non-active segments are never materialised, so they can never become a false failure.
- **carry_forward** — failed/incomplete *due* tasks from the most recent prior visit on the same schedule (`carried_from_task_id`).
- **one_off / optional** — manual.
- **out_of_scope_observation** — recorded, never a routine failure. Out-of-scope **areas** (`v2_areas.is_out_of_scope`) generate nothing.

## Generation (DB-driven) — `rpc_v2_generate_visit_tasks(visit_instance_id)`

Idempotent. Inserts baseline tasks; computes the active segment per anchor and inserts that segment's tasks; pulls carry-forwards from the prior visit. `rpc_v2_create_visit(site, schedule, date)` creates a visit instance (dup-guarded) and generates in one call.

## Rotation maths — `tms_internal.v2_active_segment_position(anchor, visit_date)`

`position = floor((visit_date − anchor_start_date)/7) mod cycle_length + 1`. `anchor_start_date` NULL ⇒ inactive (no rotation generated; needs setup). Settable via `rpc_v2_set_rotation_anchor` (admin/supervisor). Abbey: Friday `RA_FRI_DRY` cycle 2 (pos1 male / pos2 female); Sunday `RA_SUN_WET` cycle 4; Tuesday none (schema supports adding one later).

## Results / supervisor verification

`rpc_v2_record_result` (operative: status, 1–5/N/A rating, note, follow-up). `rpc_v2_supervisor_verify` (supervisor/admin: separate `supervisor_verified` + reviewer + timestamp + note). Generated columns `rating_band_display` (red/amber/green/na) and `is_failure` (rating ≤ 2).

## Validated lists + "Other / not listed"

`v2_sub_areas` holds validated assets, with `is_unconfirmed` for provisional rows (open showers 1–8, cubicles 1–6 — `@UNCONFIRMED`). Generated tasks accept either a `task_template_id`/`sub_area_id` or an `other_task_text`/`other_sub_area_text` fallback; a CHECK forbids a blank/vague task target.

## Reporting — `v_v2_visit_task_report`

Per generated task: source, is_due, area, sub-area, task, status, band, is_failure, supervisor_verified, follow_up, and a derived `outcome` (due_not_recorded / failed / missed / partial / n/a / completed).

## Migration safety

Additive only. No `DROP`/destructive `ALTER`/`DELETE`/`UPDATE` of any legacy table. The only legacy reads are `public.sites` (identity) in the seed and the `tms_internal` auth helpers in RLS/RPCs. Prepared on a branch; applies on merge to main only.

## Open / @UNCONFIRMED

Cubicle numbering & grouping; exact toilet/accessible asset names; open-shower count (assumed 8); Friday 2-week vs fuller cycle; whether Tuesday gets a rotation; baseline wording vs paper sheets. "Other / not listed" covers launch.

## Rollout

1. Owner runs `00_verify_live_db.sql` (legacy history sizing) — informational; v2 is additive regardless.
2. Approve → merge branch to main → Lovable applies both migrations → `types.ts` regenerates.
3. Run `03_v2_smoke_test.sql` against the applied DB.
4. Use the `/v2/visits` route to create a visit, generate tasks, rate, verify, and view the report.
5. Later: action generation from `v2_visit_task_results.is_failure`, evidence upload UI, and a deliberate legacy retirement once parity is confirmed.
