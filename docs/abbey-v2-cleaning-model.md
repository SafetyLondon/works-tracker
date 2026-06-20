# Abbey v2 Cleaning Model — Design

**Status:** design + staged migration, **not yet applied**. Owner-approved direction (2026-06-20): a clean v2 replacement model, implemented **additively** (no destructive changes to legacy tables).

**Core principle:** the **database** determines baseline tasks, the active rotation segment, the generated visit tasks, and the rating/completion structure. The frontend never decides what is due.

Artifacts in `docs/abbey-v2/`:
- `00_verify_live_db.sql` — read-only pre-flight (run first).
- `01_schema.sql` — additive schema + generation RPC + reporting view.
- `02_abbey_seed.sql` — idempotent Abbey v2 seed.

On sign-off, `01`/`02` move verbatim into `supabase/migrations/<timestamp>_*.sql` and are pushed for Lovable to apply.

---

## 1. Implementation boundary (safety)

- **Additive only.** New tables/types/functions/views in `public`. No `DROP`, no destructive `ALTER` of legacy tables.
- Legacy tables (`visit_templates`, `template_rating_lines`, `focus_items`, `rotation_programmes/steps`, `visit_rating_lines`, `visit_focus_*`, `reviews`, `review_line_scores`, `focus_item_scores`) are left untouched and treated as **legacy/prototype** until a deliberate retire/migrate step.
- v2 **references** shared infra read-only: `sites`, `cleaning_visits`, `evidence_items`, `tms_internal.*` role helpers. No legacy row is mutated.
- A nullable bridge column is **not** added to any legacy table; instead `service_schedules.legacy_visit_template_id` points *from* v2 *to* the legacy template, so generation can run against an existing `cleaning_visits` row during transition.

## 2. Reconciliation map (legacy → v2)

| Legacy | v2 | Notes |
|---|---|---|
| `visit_templates` | `service_schedules` | + `planned_duration_hours`; bridged via `legacy_visit_template_id` |
| `template_rating_lines` (flat baseline lines) | `task_templates` (wired in `schedule_baseline_tasks`) | baseline = always due |
| `rotation_programmes` | `rotation_anchors` | same rotation maths |
| `rotation_steps` | `rotation_segments` | `position` = week number |
| `rotation_step_focus_items` | `rotation_segment_tasks` | now area/sub-area-aware, points at `task_templates` |
| `focus_categories` / `focus_items` | `task_families` / `task_templates` | `acceptance_standard` → `task_templates.acceptance_criteria` |
| *(none)* | `areas`, `sub_areas` | new spatial hierarchy |
| `visit_rating_lines` + `visit_focus_recommendations` + `visit_focus_items` | `generated_visit_tasks` | **unified** per-visit list with `source` provenance |
| `review_line_scores` + `focus_item_scores` | `visit_task_results` | 1–5/N/A rating + completion + supervisor verification |
| evidence link tables | `generated_visit_task_evidence` | reuses `evidence_items` (Slice-3 uploader drops in) |

## 3. Baseline vs rotation vs the rest

`generated_visit_tasks.source` is the provenance, set by the generator, never the UI:

- **baseline** — every service visit, from `schedule_baseline_tasks`.
- **rotation** — only the **active** segment for that visit date. Non-active segments are *never inserted*, so they can never be flagged missed.
- **carry_forward** — failed/incomplete *due* tasks from the most recent prior visit on the same schedule.
- **one_off** — manually added.
- **optional** — done if time/instructed.
- **out_of_scope_observation** — an observation in an out-of-scope area; recorded, never a missed-task failure.

`task_kind` on `task_templates` is **advisory** only; the same template can be baseline on one schedule and rotation on another (e.g. *Descale shower* is Tuesday-baseline but Friday-rotation). What matters is where it's wired.

## 4. Validated list + "Other / not listed"

`generated_visit_tasks` carries both the validated FK and a free-text fallback:
- sub-area: `sub_area_id` **or** `other_sub_area_text`;
- task: `task_template_id` **or** `other_task_text` (CHECK `gvt_task_identified_chk` guarantees one is present).

An "Other" entry can later be promoted to a real `sub_areas`/`task_templates` row. This is the transitional design for the incomplete asset log (cubicles, accessible assets).

## 5. Supervisor verification

`task_templates.requires_supervisor_verification` (set on *Dry floor / leave safe*, *Descale*) flows onto the generated task. `visit_task_results` separates:
- `supervisor_reviewed` — generic QA review;
- `supervisor_verified` — explicit safety/quality sign-off (e.g. floors left dry/safe);
- `supervisor_note`.

So operative tick-off and supervisor verification are distinct records.

## 6. Rotation calculation (§12)

Reuses the existing formula (`tms_internal.v2_active_segment_position`):

```
position = floor((visit_date − anchor_start_date) / 7) mod cycle_length + 1
```

- Friday `RA_FRI_DRY` `cycle_length = 2` → pos1 male, pos2 female.
- Sunday `RA_SUN_WET` `cycle_length = 4` → pos1..4.
- Tuesday: no anchor (schema allows adding one later).
- `anchor_start_date` is **NULL** until an admin sets it (the Slice-1 admin screen pattern applies to `rotation_anchors`). NULL → no rotation tasks generated yet.

## 7. Generation flow (§10) — `rpc_generate_visit_tasks(cleaning_visit_id)`

DB-driven, idempotent (re-run adds only missing rows; never deletes a task that has a result):
1. resolve `service_schedule` via the legacy bridge;
2. insert all `schedule_baseline_tasks` as `source=baseline, is_due=true`;
3. for each anchor with a set start date, compute the active segment and insert its `rotation_segment_tasks` as `source=rotation`;
4. pull failed/incomplete due tasks from the prior visit as `source=carry_forward`;
5. snapshot task name/acceptance/area onto each row; log to `activity_log`.

## 8. Ratings / completions (§11)

`visit_task_results` (one per generated task): `status` (completed/partial/not_completed/inaccessible/not_applicable), `rating` 1–5 or `is_na`+reason, generated `rating_band_display` and `is_failure`, operative/supervisor notes, `supervisor_reviewed`/`supervisor_verified`, `completed_at`. Evidence via `generated_visit_task_evidence`.

## 9. Reporting / provenance (§6, §14.11) — `v_visit_task_report`

One row per generated task with `source`, `is_due`, area/sub-area, family, status, band, `is_failure`, `supervisor_verified` and a derived `outcome` (`due_not_recorded` / `failed` / `missed` / `partial` / `n/a` / `completed`). Answers "was this due, missed, optional, carried-forward, or out of scope" directly.

## 10. Worked examples

- **Tuesday** — `SS_TUE` (6h). Areas: spa reception, foyer/relaxation, pool-side floor/drains, shower; sauna/steam/pool-body `is_out_of_scope`. Baseline: floor buffer, jet wash, drain grate, **descale shower**, reception floor+edges, fixtures, **dry/leave safe (verify)**. No rotation.
- **Friday** — `SS_FRI` (5h). Areas: foyer-after-gates, dry male, dry female (main reception pre-gates = out of scope). Baseline every Friday: foyer floor + under fixtures + fixtures wipe; male & female floor buffer + jet wash + **dry/leave safe** + **mirrors/vanity clean ← owner edit**. Rotation `cycle=2`: pos1 male intensive (descale, drains, cubicle deep, vanity deep, locker base, bench, edge, high-impact), pos2 female intensive. Off-week room = not due.
- **Sunday** — `SS_SUN` (6h). Areas: cubicles, open showers (1–8 validated + Other), male/female/accessible toilets, corridor, group rooms 1&2, accessible. Baseline: village floor clean/buffer/jet wash, dry/leave safe, open-shower clean, toilet clean ×3, corridor mop + drain grate, cubicle presentation, group-room clean ×2. Rotation `cycle=4`: pos1 cubicles 1–2 + vanity + edges, pos2 cubicles 4–6 + bases/lockers, pos3 accessible, pos4 high-impact/limescale/drains.

## 11. Still needs confirming (§13.13)

- Wet-village **cubicle numbering/grouping** (seeded `CUBICLE_1..6` as `@UNCONFIRMED` placeholders).
- Exact **toilet names** and **accessible asset names**.
- Confirm **open-shower count = 8**.
- Friday rotation = **2-week** (current) vs a fuller 4-week.
- Whether **Tuesday** ever gets a rotation.
- Baseline wording alignment with current paper rating sheets.

The "Other / not listed" fallback lets the pilot run before these are finalised.

## 12. Rollout plan

1. **Verify** (`00_verify_live_db.sql`) — seed/demo vs real history.
2. Apply `01_schema.sql` then `02_abbey_seed.sql` (move into `supabase/migrations/`, push).
3. Lovable regenerates `types.ts`; build a thin v2 read-only preview (generated tasks + report) behind the existing rotation-anchor admin.
4. Wire `rpc_generate_visit_tasks` into the visit-create path (alongside, not replacing, legacy generation).
5. Build the v2 task-completion UI; run both models in parallel for a pilot window.
6. Deliberate cutover; retire legacy tables only once parity is confirmed.

Frontend changes are **out of scope until the schema is signed off and applied**.
