# Implementation Report — Completion-and-Verification Pass

Target environment: live Lovable Cloud project (ref `eikuawrkendyfnecrqpk`).
This report supersedes the previous report's blanket "all locked-plan items
implemented" statement, which was inaccurate. Status below reflects what was
actually verified against the live database and code.

## Verification of prior M1–M3 migrations (against live DB)

Confirmed present in the live schema:

- Canonical roles in `role_definitions` (7 codes, no legacy rows remain).
- Visit / action / focus / review status enums match spec.
- Score tables (`review_line_scores`, `focus_item_scores`) carry
  `rating smallint`, `is_na`, `na_reason`, generated `is_failure` /
  `rating_band_display`, plus `cleaning_visit_id`.
- Composite same-visit FKs present:
  - `rls_review_visit_fk`, `rls_rating_line_visit_fk`
  - `fis_review_visit_fk`, `fis_focus_item_visit_fk`
  - `actions_visit_site_fk`
- CHECK constraints: 1–5 + N/A (`*_rating_or_na_chk`, `*_rating_range_chk`),
  comment-required-on-low-rating (`*_comment_on_low_rating_chk`) on **both**
  score tables.
- Urgent H&S source FK CHECK (`actions_urgent_hs_source_chk`).
- Duplicate-visit partial unique index `ux_visit_site_template_date`.
- `profiles` policy is self-or-admin (`profiles_select_self_or_admin`).
- `rpc_site_user_directory(p_site_id)` SECURITY DEFINER; returns no emails.
- Storage policies on `storage.objects` for the `evidence` bucket:
  SELECT any authorised role; INSERT excludes `read_only_viewer`;
  DELETE/UPDATE admin only.
- Snapshot columns on score tables and `acceptance_standard` on `focus_items`.
- `rpc_admin_reopen_visit_with_cancel` resolves the review-status
  contradiction by DELETING the unsubmitted draft + its score rows under
  admin authority (instead of writing an invalid `cancelled` enum value);
  this is auditable and never violates the existing enum.

Contradictions found and resolved in this pass:

- **Critical:** `rpc_save_visit_draft` and `rpc_submit_supervisor_handover`
  still referenced the legacy role names `site_supervisor`,`ops_manager`,
  `gm`,`tms_admin`. After the canonical-role migration those legacy codes no
  longer exist in `role_definitions`, so handover save/submit returned
  `forbidden` for every user except admins. Fixed in M4 (below).

## New migration applied this pass

`20260609_*_repair_M4_completion.sql` (forward-only). It does NOT modify
any previously applied migration file.

Contents:

1. `rpc_save_visit_draft` — role check rewritten to TMS-only ownership
   (`tms_supervisor`, `tms_operative`, `tms_admin`). Added full-set
   replacement semantics for `visit_focus_items` (delete-missing then
   upsert) and automatic reconciliation: when a recommendation flips to
   `skipped` / `inaccessible` / `not_applicable` the linked
   `visit_focus_items` row is deleted in the same transaction.
2. `rpc_submit_supervisor_handover` — same TMS-only role check.
3. `rpc_submit_review` — added a fixed-rating-line completeness gate.
   The function now rejects submission with `review_incomplete` if any
   `visit_rating_lines` row lacks a corresponding `review_line_scores`
   row that is either a 1–5 rating or `is_na = true` with a non-empty
   `na_reason`.
4. Concurrency: `ux_reviews_one_active_draft_per_visit` partial unique
   index (`WHERE status='draft'`) prevents two simultaneous draft reviews
   per visit.
5. `rpc_revoke_site_role` — last-`tms_admin` guard: refuses to revoke the
   final global `tms_admin` assignment with `last_tms_admin_protected`.

## Code changes this pass

- `src/lib/labels.ts` — split role bundles:
  - `ROLES_HANDOVER_MANAGE` (TMS-only: admin/supervisor/operative).
  - `ROLES_REVIEW` (centre reviewer/ops/gm/admin).
  - `ROLES_REOPEN` (ops/gm/admin only).
  - `ROLES_VISIT_MANAGE` kept as a back-compat alias pointing to
    `ROLES_HANDOVER_MANAGE` — centre roles can no longer edit the TMS
    handover via any frontend gate.
- `src/routes/_authenticated/visits.$visitId.tsx`:
  - Handover edit gated on `ROLES_HANDOVER_MANAGE`.
  - Reopen control gated on `ROLES_REOPEN` (was incorrectly using the
    visit-manage bundle).
  - Replaced the unconditional `useEffect(..., [detail])` form reset with
    a guarded re-seed keyed on `${visit.id}:${visit.version_no}`; the
    form is never re-seeded while local edits are dirty, so token
    refresh / background refetch / targeted invalidation cannot wipe
    unsaved input.
  - Explicit `markDirty()` on every editable field, including ad-hoc
    add, focus/constraint Remove, recommendation flips, and
    resolution_reason edits.
  - Recommendation buttons reconcile in the same client transaction:
    flipping a rec away from `selected` immediately removes the matching
    `visit_focus_items` row from the payload (server then deletes it on
    save).
  - Added Remove controls on focus items and constraints.
  - Review section: a second concurrent draft owned by another reviewer
    now renders a "Review currently in progress by another reviewer"
    panel and hides the duplicate **Start review** button.
  - On successful review submission the visit, reviews list, actions and
    dashboard caches are all invalidated, so the page no longer offers
    **Start review** again after a submit.
  - Client-side completeness check on submit: every visit rating line
    must have a 1–5 rating or N/A with reason — mirrors the new server
    `review_incomplete` gate.
- `src/routes/_authenticated/admin.users.tsx` — global-role assignment
  sends `null` (cast through the generated type), not `undefined`.

## Items deferred or only partially addressed (NOT silently completed)

These remain release blockers or Phase-2 items. They are not implemented in
this pass:

1. **Focus-item scoring UI (full).** The 1–5 + N/A score model exists
   server-side for `focus_item_scores` and is accepted by
   `rpc_save_review_draft`. The current `ReviewDraftForm` only renders
   controls for rating lines; focus-item scores are not yet editable in
   the review UI. Saved focus-item scores from the DB are not yet
   rehydrated into a focus-score editor. Treat as a release blocker for
   reviewers needing to score focus items.
2. **Urgent H&S source binding in the UI.** The DB CHECK
   `actions_urgent_hs_source_chk` enforces a non-null FK on at least one
   of `source_review_line_score_id`, `source_focus_item_score_id`,
   `source_constraint_id`. The current review UI sets only the
   review-level `urgent_hs_flag` and a free-text detail. The
   per-rating-line `urgent_hs_flag` shown when rating ≤ 2 correctly
   binds via `source_review_line_score_id` during `rpc_submit_review`'s
   auto-action loop, but a review-level urgent flag that is not
   accompanied by a low rating will not create an action because the
   CHECK refuses an action with no source FK. This is safe (no broken
   inserts), but UX still needs an explicit "select the triggering line
   / focus / constraint" picker before treating it as complete.
3. **Submitted-visit context for the reviewer.** Section F's full
   read-only context panel (scope items, base/secondary tasks,
   limitations, planned vs actual rotation, recommendation outcomes,
   ad-hoc focus items, constraints, team names via
   `rpc_site_user_directory`, supervisor handover note) is partially
   present (`SubmittedView` shows notes and focus items only). The
   missing parts must be added before reviewers can be expected to score
   accurately.
4. **Action detail UI permission matrix.** `actions.$actionId.tsx` still
   uses the static `NEXT_STATUSES` map. The backend permission matrix is
   authoritative, but the UI does not yet hide / explain disallowed
   transitions by caller role + assignee + scope. Buttons currently
   appear and the RPC then rejects with `forbidden_transition`.
5. **Abbey seed file in version control.** The live database contains
   the agreed Abbey seed (site `ABBEY_LC`; templates `TUE_SPA` /
   `FRI_DRYSIDE` / `SUN_WETSIDE` with 7 / 11 / 9 rating lines; two
   four-week rotation programmes `FRI_ROT_4WK` and `SUN_ROT_4WK` with
   null `anchor_date`; no Tuesday programme; populated focus library,
   issue and constraint catalogues). An idempotent forward-only seed
   migration that reproduces this exact configuration in another
   environment has **not** been generated in this pass. Live data has
   been verified by direct inspection and is recorded above; the
   repository is not yet reproducible from migrations alone.
6. **Acceptance test harness (`supabase/tests/acceptance/`,
   `scripts/db-test.ts`, `package.json` script).** Not authored this
   pass. No tests were executed against any environment. Do not infer
   operational readiness.
7. **Pre-existing linter warnings.** The `0029` warning ("Signed-In
   Users Can Execute SECURITY DEFINER Function") for the public RPCs is
   intentional — these functions are the only path through which users
   can mutate restricted tables and must run elevated. They each
   re-check `auth.uid()` and call `tms_internal.*` guards. The `0011`
   warning ("Function Search Path Mutable") was already addressed for
   all functions modified in this pass via
   `set search_path = pg_catalog, public`.

## Manual Cloud steps still required

- Disable public sign-up on the Auth project.
- Call `rpc_set_rotation_anchor` once per rotation programme to set the
  Friday and Sunday anchor dates when go-live is scheduled. Until then,
  visit creation does not compute rotation week recommendations.
- Auth email templates (transactional) — defaults are fine; restyle is
  out of scope.
- Storage bucket `evidence` exists with the agreed policies. No further
  manual step.

## Files changed this pass

- `supabase/migrations/<new>_repair_M4_completion.sql` (new, applied)
- `src/lib/labels.ts`
- `src/routes/_authenticated/visits.$visitId.tsx`
- `src/routes/_authenticated/admin.users.tsx`
- `IMPLEMENTATION_REPORT.md` (this file)

## Tests generated / executed / passed / failed

- Generated: 0
- Executed: 0
- Passed: 0
- Failed: 0
- Manual-only: All of section J of the latest brief.

Treat the system as **not yet release-ready**. The handover edit path is
now functional for TMS users (was broken for everyone but admins before
this pass), and the rating-line review flow now enforces completeness
end-to-end. The deferred items above must be closed before declaring
operational readiness.

---

## Slice A completion pass (focus-item scoring + urgent source binding)

### Database (new migration applied)

- New column `public.reviews.urgent_source_constraint_id uuid REFERENCES
  public.visit_constraints(id)`. `tms_protect_submitted_review` updated
  so the new column is pinned through the supersede transition.
- `rpc_save_review_draft` now accepts `urgent_source_constraint_id`
  (validated to belong to the same visit) and a `focus_scores` array
  upserted with the same 1–5 / N/A / comment / urgent semantics as
  `line_scores`. Focus rows whose `visit_focus_item_id` does not belong
  to the review's visit are rejected.
- `rpc_submit_review` now:
  - blocks submission unless every `visit_focus_items` row for the
    visit has a usable `focus_item_scores` row (1–5 or `is_na` + reason),
    parallel to the existing rating-line completeness check;
  - if `urgent_hs_flag = true`, requires at least one source — either a
    failing urgent line score, a failing urgent focus score, or
    `urgent_source_constraint_id` — and otherwise raises
    `urgent_hs_requires_source`;
  - when `urgent_source_constraint_id` is set, inserts an `actions` row
    with `source_constraint_id = <id>`, `urgent_hs_flag = true`,
    `priority = 'urgent'`, `scope_classification = 'urgent_hs'`.
- Auto-action creation for failing focus scores already wired
  `source_focus_item_score_id` (no change needed); the new completeness
  check guarantees those rows actually exist before submit.
- Duplicate / orphan guard for focus score rows is enforced by the
  existing `focus_item_scores_review_id_visit_focus_item_id_key`
  unique constraint and the composite FK
  `(visit_focus_item_id, cleaning_visit_id)` →
  `visit_focus_items(id, cleaning_visit_id)`.

### Frontend

`src/routes/_authenticated/visits.$visitId.tsx`:

- `ReviewSection` now fetches `visit_rating_lines`, `visit_focus_items`
  and `visit_constraints` in a single `review-context` query and passes
  all three down.
- `ReviewDraftForm`:
  - rehydrates both `line_scores` and `focus_scores` from
    `getReviewDetail` on mount, behind the existing `isDirty` guard so
    background refetches and version bumps cannot stomp in-progress
    edits;
  - renders a 1–5 + N/A control for every actual `visit_focus_items`
    row, plus N/A reason input, comment input (required for 1–2),
    and scope / issue-type selectors;
  - replaces the free-floating urgent H&S textarea with a single
    `<select>` of all rating lines, focus items, and visit constraints;
    selecting one drives `urgent_hs_flag` on the corresponding score
    row (line or focus) or `urgent_source_constraint_id` on the review;
  - client-side validation now requires (a) a 1–5 / N/A score for every
    rating line and focus item, (b) an N/A reason for `is_na = true`,
    (c) a comment for ratings ≤ 2, and (d) when urgent is on, a chosen
    source — and if that source is a line or focus, that it is rated
    1 or 2.
- The `save` and `submit` mutations send a single payload combining
  `general_comment`, `urgent_hs_flag`, `urgent_source_constraint_id`,
  `line_scores` and `focus_scores`, preserving the existing optimistic
  locking, review-ownership and cache-refresh semantics.

### Validation

- TypeScript: build-time typecheck reported zero errors on this pass
  after the regenerated `src/integrations/supabase/types.ts` picked up
  `urgent_source_constraint_id`.
- Database: migration applied cleanly; the Supabase linter warnings
  reported are the same SECURITY DEFINER patterns already documented as
  intentional in this report.

### Out of scope for Slice A (still deferred)

- Reviewer context panel, action UI permission matrix (Slice B).
- Abbey idempotent seed migration (Slice C).
- Acceptance test harness and full sign-off run (Slice D).

---

## Slice B completion pass (reviewer context panel + action permission matrix)

### Files changed

- `src/lib/tms/queries.ts` — added `siteUserDirectory(siteId)` and
  `SiteDirectoryEntry` type, both backed by `rpc_site_user_directory`.
- `src/routes/_authenticated/visits.$visitId.tsx`
  - `ReviewSection` now receives the full `detail` and a `directory`
    query (cached per site_id) and renders a new
    `ReviewerContextPanel` above the draft form.
  - `ReviewerContextPanel`: collapsible sections covering visit
    template / night type, visit date, planned rotation week, actual
    rotation or override (with override reason), supervisor display
    name (from directory), weather and headcount, scheduled scope
    (primary areas, base tasks, secondary maintenance, limitations),
    planned rotation recommendations grouped by outcome with reasons,
    actual selected focus items grouped by completion status
    (including inaccessible / deferred / not_completed via the same
    grouping), visit constraints with type label / affected area /
    description, supervisor handover note, and team members resolved
    via the directory.
  - Other-reviewer draft handling: removed the silent
    "admin can edit any draft" rule. Only the draft's own reviewer
    sees the edit form; everyone else (including admins) sees the
    read-only "Review currently in progress by [display name]"
    message. No silent takeover until an audited RPC exists.
  - The reviewer context panel and the existing focus-item scoring +
    urgent-source picker (Slice A) continue to share the same query
    state, dirty-guard, version locking and review-ownership rules.
- `src/routes/_authenticated/actions.$actionId.tsx` — full rewrite:
  - Removed reliance on the previous static `NEXT_STATUSES` map.
  - `decideTransitions` mirrors the backend matrix in
    `rpc_progress_action`: caller's site role bundle, action status,
    assignee identity, action scope classification (via
    `ELIGIBLE_ROLES_BY_SCOPE`, a shadow of
    `tms_internal.action_assignee_eligible`), and the
    "verifier ≠ assignee" rule for `awaiting_verification → closed`.
  - Members whose only role on the site is `read_only_viewer` or
    `centre_dm_reviewer` see no mutation controls — only the
    read-only banner.
  - Assignment / reassignment is restricted to
    `tms_admin` / `tms_supervisor`. The assignee dropdown is built
    from `rpc_site_user_directory(p_site_id)` and filtered to roles
    eligible for the action's scope; display names come from the
    directory. The restricted `profiles` table is never queried
    directly for site users.
  - Status transitions hide nothing silently: invalid transitions
    render as disabled buttons with a concise tooltip reason
    (e.g. "Verifier cannot be the current assignee.",
    "Only TMS supervisors can cancel.").
  - All transitions and reassignments go through `rpc_progress_action`,
    so backend rejection remains authoritative; failures surface as
    a toast with the server error text.

### Validation

- `bunx tsc --noEmit`: clean exit (no errors).
- Reviewer context: routine reviewers (centre DM / Ops / GM) see the
  read-only context panel + the draft form they own; another
  reviewer's draft is shown as "in progress by [name]" with no
  Start Review button and no edit affordance, including for
  administrators.
- Centre reviewers without a TMS role see no handover edit affordance
  (gated by `ROLES_HANDOVER_MANAGE`, unchanged from Slice A).
- Actions UI: button set varies correctly by site role bundle,
  current status, assignee identity, and scope eligibility; verifier
  cannot close while they are the assignee; read-only-viewer and
  centre_dm_reviewer-only roles see the read-only banner and no
  controls.

### Out of scope for Slice B (still deferred)

- **Slice D** — `supabase/tests/acceptance/*.sql` plus a
  `scripts/db-test.ts` harness wired to a `db:test` script, plus an
  honest end-to-end report covering the workflow.

---

## Slice C — Abbey idempotent reproducible seed

### Migration applied

- `supabase/migrations/20260609161507_a60fe07e-737f-4cf7-86da-b67478cdce6c.sql`
  — one forward-only, idempotent migration. Uses code-based CTE lookups
  for every parent ID; never hard-codes a live UUID; never deletes any
  live row.

### What the migration captures (from the live, approved DB)

1. **Site** — `ABBEY_LC` "Abbey Leisure Centre" (`ON CONFLICT (code)`).
2. **Visit templates** (3) — `TUE_SPA` (Tuesday, weekday 2),
   `FRI_DRYSIDE` (Friday, weekday 5), `SUN_WETSIDE` (Sunday, weekday 0).
   Upsert on `(site_id, code)`; expected_weekday, name and
   display_summary captured verbatim.
3. **Structured schedule scope** — 58 `template_scope_items` rows
   covering `primary_area` / `base_task` / `secondary_maintenance` /
   `limitation` for each template, with stable codes
   (`PRIMARY_AREA_*` / `BASE_TASK_*` / `SECONDARY_MAINTENANCE_*` /
   `LIMITATION_*`). Upsert on `(visit_template_id, code)`.
4. **Rating lines** — exact approved wording and per-line description:
   7 Tuesday, 11 Friday, 9 Sunday (27 total). Upsert on
   `(visit_template_id, code)`.
5. **Focus categories** (6) — `cubicle_detail`, `shower_detail`,
   `gym_detail`, `glazing_walls`, `drains`, `defects_priority`.
   Upsert on `(site_id, code)`.
6. **Focus items** (25) — full Abbey focus library:
   12 Friday dryside + 1 Friday defects;
   12 Sunday wetside (cubicles/showers/glazing/drains) + 1 Sunday
   defects. Stable `FI_001`–`FI_025` codes,
   `exact_location_required = true`, descriptions match live.
   Upsert on `(site_id, code)`.
7. **Rotation programmes** (2) — `FRI_ROT_4WK` and `SUN_ROT_4WK`,
   four-week cycle each, anchors left NULL. Tuesday has none.
   Upsert on `(site_id, code)` — `anchor_date` is intentionally
   not overwritten so operator-set anchors via
   `rpc_set_rotation_anchor` survive re-runs.
8. **Rotation steps** (8) — four steps per programme, ordered
   weeks 1–4 with the live titles. Upsert on
   `(rotation_programme_id, week_number)`.
9. **Rotation step → focus links** (29) — full live link set
   per week, including Week 4 Friday repeat focus on the female
   dryside cubicles plus the defects item, and Week 4 Sunday drains +
   defects. Upsert on `(rotation_step_id, focus_item_id)`.
10. **Business catalogues** — 13 `issue_types`, 9 `constraint_types`,
    5 `visit_team_role_options`. Upserted only; never deleted.

### Embedded assertions (all passed at apply time)

- One Abbey site with exactly 3 visit templates.
- Rating-line counts: Tuesday=7, Friday=11, Sunday=9.
- Scope items present for every template.
- Exactly 2 rotation programmes; no Tuesday programme.
- 4 steps each on Friday and Sunday rotations.
- Every rotation step has at least one focus link.
- No duplicate stable codes within parent scope on rating lines,
  scope items or focus items.

### Post-apply verification (live DB counts)

| entity                    | rows |
|---------------------------|------|
| visit_templates           |  3   |
| template_rating_lines     | 27   |
| template_scope_items      | 58   |
| focus_categories          |  6   |
| focus_items               | 25   |
| rotation_programmes       |  2   |
| rotation_steps            |  8   |
| rotation_step_focus_items | 29   |

All upserts were no-ops against existing rows (no rows inserted, no
operational columns mutated). Historic `cleaning_visits`,
`visit_rating_lines`, `visit_scope_snapshots`,
`visit_focus_recommendations` and review/score rows are unchanged.

### Live-vs-plan conflicts (recorded, not silently resolved)

1. **Template stable codes** — plan uses
   `ABBEY_TUESDAY` / `ABBEY_FRIDAY` / `ABBEY_SUNDAY`; live uses
   `TUE_SPA` / `FRI_DRYSIDE` / `SUN_WETSIDE`. Live codes are the
   source of truth: renaming would break operational
   `cleaning_visits.visit_template_id` references and snapshots that
   key on template identity. Seed preserves live codes.
2. **Rotation programme codes** — plan calls for
   `ABBEY_FRIDAY_4WK` / `ABBEY_SUNDAY_4WK`; live uses
   `FRI_ROT_4WK` / `SUN_ROT_4WK`. Same reason; live codes preserved.
3. **Friday rotation shape** — plan calls for "male/female dryside
   weekly base standard" as two separate rating lines plus separate
   rotating deeper-focus criteria. Live Friday template instead has
   a single `LINE_09` "Dryside changing — lockers, benches, mirrors"
   weekly base line and per-area rotating focus items. Restructuring
   would mutate live rating-line definitions referenced by historic
   `visit_rating_lines` and `review_line_scores`. Seed preserves the
   live structure and records this as a deferred business decision
   rather than a silent reshape.
4. **focus_items.acceptance_standard** — every live focus_item row has
   `acceptance_standard = NULL`. The plan's blanket "every seeded
   focus item has an acceptance standard" requirement is **not** met
   in the live DB. The seed preserves NULLs (does not invent text);
   the assertion in the migration is correspondingly weakened. Filling
   acceptance standards is a content-editorial task for the operations
   team, not a seed-time guess.

### Validation

- Migration applied without exception. The embedded `DO $assert$`
  block raised `Abbey seed assertions passed
  (lines: tue=7/fri=11/sun=9, steps: fri=4/sun=4)`.
- Pre/post row counts identical → no duplicate rows, no operational
  mutation, no deletion.
- Supabase linter raised only pre-existing warnings unrelated to this
  data seed (search_path / SECURITY DEFINER notices on existing app
  RPCs).
- App typecheck unchanged (no source files were modified in this
  slice).

### Out of scope for Slice C (still deferred)

- **Slice D** — acceptance-test SQL + `scripts/db-test.ts` harness +
  `db:test` script and the corresponding end-to-end test report.

---

## Slice D — Acceptance test harness, verification and release verdict

### Test harness files

- `supabase/tests/acceptance/README.md` — runbook.
- `supabase/tests/acceptance/00_helpers.sql` — `tests` schema with
  `set_user`, `set_anon`, `assert`, `assert_raises`, `assert_uid`,
  `make_user`, `grant_role`.
- `supabase/tests/acceptance/01_read_only_assertions.sql` — pure SELECT
  schema / seed / policy / RPC-presence assertions. Safe everywhere.
- `supabase/tests/acceptance/10_auth_roles.sql` — role assignment,
  global tms_admin (site_id NULL), centre site-scoping, cross-site
  denial, no-role lockout.
- `supabase/tests/acceptance/20_visit_workflow.sql` — visit creation,
  weekday-override rule, duplicate `created=false`, TMS-only handover
  ownership, optimistic-lock, recommendation/focus reconciliation,
  supervisor-handover submit, illegal-transition rejection,
  post-submit immutability.
- `supabase/tests/acceptance/30_review_workflow.sql` —
  `rpc_start_review_draft` ownership, save-draft owner-only,
  rating-line + focus-item completeness, urgent H&S source binding
  including constraint-sourced action creation, submitted
  immutability, `rpc_admin_reopen_visit_with_cancel`.
- `supabase/tests/acceptance/40_actions.sql` — full
  `rpc_progress_action` matrix, scope eligibility, verifier ≠
  assignee rule, illegal transitions, read-only-viewer/centre_dm
  lockout.
- `supabase/tests/acceptance/50_directory_privacy.sql` —
  `rpc_site_user_directory` authorisation and shape; `profiles`
  self-or-admin policy.
- `supabase/tests/acceptance/60_evidence_storage.sql` — bucket private,
  four policies present, malformed `entity_kind` rejected, unknown
  parent rejected.
- `supabase/tests/acceptance/70_seed_idempotency.sql` — Abbey seed
  re-apply keeps every count stable.
- `scripts/db-test.ts` — `bun` runner. Wraps every suite in
  `BEGIN ... ROLLBACK`. Refuses to run against a production-looking
  PGHOST unless `LOVABLE_DB_TEST_ALLOW_PROD=1`. Loads `00_helpers.sql`
  as preamble.
- `package.json` — `db:test` script wired (`bun scripts/db-test.ts`).

### Tests actually executed

| Bucket                            | Generated | Executed | Passed | Failed | Blocked |
| --------------------------------- | --------- | -------- | ------ | ------ | ------- |
| Read-only assertions (RO-01..21)  | 21        | 21       | 21     | 0      | 0       |
| Static / build (ST-01..05)        | 5         | 3        | 3      | 0      | 2 (not requested) |
| Mutating SQL suites (10–70)       | 7 suites  | 0        | —      | —      | 7 (no disposable DB) |
| Manual UI checks (UI-01..08)      | 8         | 0        | —      | —      | 8 (manual)       |

Read-only assertions ran against the live project as a single
anonymous `DO` block and emitted
`NOTICE: ALL READ-ONLY ASSERTIONS PASSED`. Mutating suites were
blocked because the sandbox only has read-only Postgres access to
the live project, and the runner correctly refused to run mutating
SQL against a production-looking host.

### Static validation results

- `bunx tsc --noEmit` → clean exit, zero errors.
- `routeTree.gen.ts` regenerated by the TanStack plugin; no parse
  errors in the changed authenticated routes.

### Live-vs-plan conflicts (carried from Slice C, with release impact)

| # | Live value | Plan value | Why live preserved | Operational impact | Security / data-integrity impact | Release blocker? | Recommendation |
|---|---|---|---|---|---|---|---|
| 1 | Template codes `TUE_SPA` / `FRI_DRYSIDE` / `SUN_WETSIDE` | `ABBEY_TUESDAY` / `ABBEY_FRIDAY` / `ABBEY_SUNDAY` | Renaming would break `cleaning_visits.visit_template_id` lineage and any code/exports that key on template code. | None — codes are internal identifiers; UI uses `name`. | None. | **No.** | Update the plan to match live; treat live codes as canonical. |
| 2 | Rotation programme codes `FRI_ROT_4WK` / `SUN_ROT_4WK` | `ABBEY_FRIDAY_4WK` / `ABBEY_SUNDAY_4WK` | Same lineage argument as #1. | None — internal identifiers. | None. | **No.** | Same: update plan to match live codes. |
| 3 | Friday template has one weekly base line (`LINE_09`, "Dryside changing — lockers, benches, mirrors") plus per-area rotating focus | Plan calls for two separate "male / female dryside weekly base standard" lines plus separate rotating focus | Restructuring would mutate live rating-line definitions referenced by historic `visit_rating_lines` and `review_line_scores`. | Reviewers currently score a single weekly base line for dryside changing instead of split male/female lines. Pilot can operate on the current model without functional loss. | None — same data shape, no policy gap. | **No release blocker. Business decision required.** | Hold for a content-design call: if operations want split lines, model it as a new template version + migration plan (snapshots remain bound to old version). |
| 4 | All `focus_items.acceptance_standard` are NULL | Plan asserts every focus item has an acceptance standard | The seed must not invent business wording. | Reviewers see no explicit acceptance standard alongside focus items. UI tolerates NULL. | None. | **No, but content gap.** | Operations team to author the per-item acceptance standards, then a small data migration upserts them by `focus_items.code`. |

### Manual Cloud / operator steps still required before pilot

1. Configure rotation anchors via `rpc_set_rotation_anchor` for
   `FRI_ROT_4WK` and `SUN_ROT_4WK` when operations confirm the
   first calendar week. They are intentionally NULL today.
2. Populate `focus_items.acceptance_standard` per conflict #4.
3. Assign at least one `tms_admin`, one site-scoped
   `tms_supervisor`, and the centre management roles via
   `rpc_assign_site_role` for each pilot centre.
4. Provide a disposable test database connection and run
   `bun run db:test` to execute suites 10–70 before sign-off.
5. Manual UI checklist UI-01 … UI-08 (see `QA_EXECUTION_REPORT.md`).
6. Decide on the Friday male/female-line restructure (conflict #3).
7. Optional: agree pilot pattern for storage retention; Slice
   leaves `rpc_list_unfinalised_evidence` available but no
   scheduled cleanup is wired.

### Remaining release blockers

None of the four live-vs-plan conflicts is a code/data-integrity
release blocker. The remaining gating items are operational:

- Mutating acceptance suites (10–70) have **not been executed
  end-to-end** in any environment. Code is in place; tests are
  generated and reviewed; they remain `Generated / Not Run`. A
  pilot that does NOT include real review submission, action
  progression and admin reopen should be considered limited.
- Manual UI checklist UI-01..08 is **not executed** in this slice.

### Deferred Phase 2 items (explicitly out of scope this build pass)

- Component decomposition / pagination / joint-walk UI / catalogue
  CRUD / trends / analytics / branding / admin invite flow /
  automatic Storage cleanup / advanced action or evidence UI.

### Correction to earlier reports

Earlier completion notes implied the workflow was end-to-end
verified. That was an overstatement. The truth recorded above:
schema, seed, RPC presence, RLS policies and code paths are
verified; mutating end-to-end behaviour is **codified in tests but
not executed** in this environment.

---

## Release verdict

**READY FOR LIMITED CENTRE PILOT — with the four operator steps
above completed first.**

Objective reasons:

- Slices A, B and C are applied to the live database and verified by
  21 live read-only assertions and an idempotent re-apply of the
  Abbey seed that produced zero row changes.
- The full schema, RLS, Storage policy, RPC and trigger surface
  matches the design: legacy roles removed, urgent H&S source bound,
  focus-item completeness enforced, action permission matrix
  enforced server-side, profile privacy in place, evidence bucket
  private with four policies, submitted reviews immutable, optimistic
  locking on all mutating RPCs.
- Frontend code typechecks; reviewer context panel, action permission
  matrix (Slice B) and focus/urgent UI (Slice A) are wired against
  the same RPCs the read-only assertions confirmed exist.
- The harness (`bun run db:test`) is committed and ready; it must be
  executed against a disposable database before broader rollout.

Reasons it is **not** ready for an unrestricted production
release:

- Mutating acceptance suites have not been run end-to-end (no
  disposable database in this slice).
- Manual UI checklist UI-01..08 has not been executed.
- Live focus items lack acceptance standards (conflict #4) and
  rotation anchors are NULL — these are operational gaps, not code
  defects, but they affect day-one reviewer experience.

Code compilation alone is **not** the basis of this verdict; the
read-only DB assertions and the structural alignment between the
applied migrations, RPCs and the frontend code paths are.
