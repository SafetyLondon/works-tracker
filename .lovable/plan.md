# TMS Cleaning Quality — cumulative final repair plan

Authoritative source of truth. Supersedes all earlier plan versions. All prior business scope, Abbey seed content, exact Tuesday/Friday/Sunday rating lines, rotation content, focus library, RLS architecture, `tms_internal` helpers, least-privilege grants, snapshot/immutability requirements, declarative transition triggers (no session token), composite-FK rules, partial-unique duplicate-action prevention, security_invoker views/RPCs, private `evidence` bucket and `_authenticated` layout remain in force.

The corrections listed below are folded in.

---

## Migration A1 — schema preconditions for idempotent seeding

Add the `code` columns required for parent-scoped conflict targets before any seed:

- `visit_templates`, `template_rating_lines`, `template_scope_items`, `focus_categories`, `focus_items`, `rotation_programmes` each get `code text` (backfilled where rows exist, then `NOT NULL`).
- Composite uniques:
  - `visit_templates (site_id, code)`
  - `template_rating_lines (visit_template_id, code)`
  - `template_scope_items (visit_template_id, code)`
  - `focus_categories (site_id, code)`
  - `focus_items (site_id, code)`
  - `rotation_programmes (site_id, code)`
  - `rotation_steps (rotation_programme_id, week_number)` (natural)
- All seeds use these targets. No `ON CONFLICT (code)` anywhere.

## Migration A2 — transition trigger fix (audit C8)

Rewrite `tms_validate_visit_transition` and `tms_validate_action_transition` to use:

```sql
ok := new.status = any(array['planned','in_progress','cancelled']::public.cleaning_visit_status[]);
```

per branch. No PL/pgSQL "smoke" block — coverage is asserted in the external acceptance suite against real rows.

## Migration A3 — role catalogue migration (conflict-safe)

Canonical codes: `tms_admin, tms_supervisor, tms_operative, centre_dm_reviewer, centre_operations_manager, centre_gm, read_only_viewer`.

Sequence:
1. Upsert canonical rows into `role_definitions` (idempotent on `code`).
2. `insert into user_site_roles (user_id, role_code, site_id, granted_by) select ..., '<new>' ... where role_code='<legacy>' on conflict do nothing` for each mapping `site_supervisor→tms_supervisor`, `ops_manager→centre_operations_manager`, `gm→centre_gm`, `viewer→read_only_viewer`.
3. Delete legacy `user_site_roles`.
4. Delete legacy `role_definitions` only when no FK remains.
5. Update every helper, RPC role array, and frontend label/guard to canonical codes in the same pass.

## Migration A4 — 1–5 + N/A rating model (gated; no data fabrication)

Pre-flight aborts if `review_line_scores` or `focus_item_scores` contains any row:

```sql
do $$ ... if n_rls>0 or n_fis>0 then raise exception 'rating-model migration aborted: ...'; end if; end$$;
```

When empty:
- drop dependent RPCs/protect triggers temporarily;
- drop `score`, `rating_band`, `is_failure` (the client-controlled column) on both tables;
- add `rating smallint check (rating between 1 and 5)`, `is_na boolean not null default false`, `na_reason text`;
- CHECK: `(is_na and rating is null and coalesce(na_reason,'') <> '') or (not is_na and rating is not null)`;
- CHECK: comment required when `rating <= 2` — **on both** `review_line_scores` and `focus_item_scores`;
- add generated columns AFTER source columns exist: `rating_band_display text generated always as (case when is_na then 'na' when rating<=2 then 'red' when rating=3 then 'amber' else 'green' end) stored`, `is_failure boolean generated always as (rating is not null and rating<=2) stored`;
- recreate score-write RPCs against the new shape (`rating`, `is_na`, `na_reason`); action creation derives from the generated `is_failure`;
- recreate immutability triggers;
- regenerate TS types after migration approval.

## Migration A5 — composite visit integrity (audit C4) — strict order

For each of `review_line_scores`, `focus_item_scores`:

1. `add column cleaning_visit_id uuid null`
2. backfill from `reviews.cleaning_visit_id`
3. validate full backfill (raise if any NULL remains)
4. `set not null`
5. parent composite uniques: `reviews(id, cleaning_visit_id)`, `visit_rating_lines(id, cleaning_visit_id)`, `visit_focus_items(id, cleaning_visit_id)`, `cleaning_visits(id, site_id)`
6. composite FKs:
   - `review_line_scores(review_id, cleaning_visit_id) → reviews`
   - `review_line_scores(visit_rating_line_id, cleaning_visit_id) → visit_rating_lines`
   - `focus_item_scores(review_id, cleaning_visit_id) → reviews`
   - `focus_item_scores(visit_focus_item_id, cleaning_visit_id) → visit_focus_items`
   - `actions(cleaning_visit_id, site_id) → cleaning_visits`
7. all score-write RPCs derive `cleaning_visit_id` server-side from the review row.

## Migration A6 — action permission matrix (audit C3)

`rpc_progress_action` is rewritten with an explicit `(current_status, new_status, caller_role, is_assignee)` matrix. `read_only_viewer` and `centre_dm_reviewer` never mutate. Verification (`awaiting_verification → closed`) restricted to `tms_supervisor`, `tms_admin`, `centre_operations_manager`, `centre_gm` and may not be the assignee.

### Assignee eligibility by scope (final correction 7)

Enforced by trigger on `actions`:

| scope_classification | eligible assignee roles |
| --- | --- |
| `routine_cleaning`, `rotating_focus`, `equipment_chemical` | `tms_admin`, `tms_supervisor`, `tms_operative` |
| `maintenance_site_fabric`, `access`, `out_of_scope`, `additional_resource` | `tms_admin`, `tms_supervisor`, `centre_operations_manager`, `centre_gm` |
| `urgent_hs` | `tms_admin`, `tms_supervisor`, `centre_operations_manager`, `centre_gm` |

`read_only_viewer` and `centre_dm_reviewer` are never eligible assignees.

## Migration A7 — review ownership + supersede workflow (audit C7, H5)

- `rpc_save_review_draft` / `rpc_submit_review` reject when `reviews.reviewer_id <> auth.uid()` and caller is not `tms_admin`.
- Replace `rpc_supersede_review` with:
  - **`rpc_create_superseding_review(p_original_review_id, p_reason)`** — locks original (must be `submitted`); creates a new `draft` with `reviewer_id = auth.uid()`, `supersedes_review_id = original.id`; copies scores+snapshots into editable draft children; leaves original `submitted`; returns the new draft id.
  - **`rpc_submit_superseding_review(p_new_review_id, p_expected_version)`** — submits the draft; in the same transaction marks the original `superseded` (column-diff allow-list trigger permits this exact transition). `reviewer_id` is never accepted from client payload.

### Reopen ↔ draft reconciliation (final correction 4)

- `rpc_reopen_visit` rejects when an active `draft` review exists.
- `rpc_admin_reopen_visit_with_cancel(p_visit_id, p_reason, p_cancel_draft_review_id)` — `tms_admin` only; cancels the named draft (`status='cancelled'` via direct UPDATE, allowed because the immutability trigger only blocks submitted/superseded) and reopens in the same transaction with `activity_log`.
- `rpc_submit_review` and `rpc_submit_superseding_review` re-check the visit is `submitted_for_review` or `reviewed` (under `FOR UPDATE` row lock) before submitting; mismatch raises `visit_state_changed`.

## Migration A8 — historic snapshots (audit C5) + acceptance_standard (M1)

- `focus_item_scores`: add `focus_label_snapshot`, `focus_location_snapshot`, `focus_acceptance_snapshot`.
- `review_line_scores`: add `line_label_snapshot`.
- `rpc_submit_review` writes them at submit from current `visit_focus_items` / `visit_rating_lines`.
- `focus_items`: add `acceptance_standard text`, populated by the seed.

## Migration A9 — duplicate visits, profile policy, directory RPC

- `cleaning_visits` unique partial index `(site_id, visit_template_id, visit_date) where status <> 'cancelled'`.
- `rpc_create_cleaning_visit_from_template` returns `jsonb { visit_id, created bool, existing_status }`. On conflict / pre-check finding an existing non-cancelled visit, returns `created=false` (no silent success). UI shows "visit already exists" panel.
- `profiles` policy rewritten to `using (id = auth.uid() or tms_internal.is_tms_admin(auth.uid()))`.

### Directory as hardened RPC (final correction 2)

- **`rpc_site_user_directory(p_site_id uuid)`** — SECURITY DEFINER, locked `search_path`, caller site-access check, returns `(user_id, display_name, role_code, site_id)`. **No email.** `GRANT EXECUTE ... TO authenticated`. No view is used (a `security_invoker` view cannot bypass the self/admin-only `profiles` policy).
- Used in UI wherever supervisor/reviewer/team/assignee names are shown.

## Migration A10 — evidence finalisation hardened (audit H6, H7)

`rpc_finalise_evidence_upload`:
- whitelists `p_entity_kind` (`visit_focus_item, review_line_score, focus_item_score, action, visit_constraint`);
- resolves the parent row server-side; derives `site_id` and parent `cleaning_visit_id` from it;
- reads `storage.objects` via `tms_internal.storage_object_metadata(text)` (SECURITY DEFINER, restricted to bucket `evidence`) to confirm the object exists and read MIME and byte size from `metadata`; rejects mismatch / over-size;
- adds immutability triggers on `review_line_score_evidence`, `focus_item_score_evidence` mirroring `tms_protect_review_children` (block writes when parent review is `submitted`/`superseded`).

## Migration A11 — Storage policies (audit C10) + final correction 6

Bucket `evidence` already exists. RLS on `storage.objects` filtered by `bucket_id = 'evidence'`:
- **SELECT**: any authorised site role (including `read_only_viewer`).
- **INSERT**: `tms_admin, tms_supervisor, tms_operative, centre_dm_reviewer, centre_operations_manager, centre_gm` only. `read_only_viewer` cannot upload.
- **DELETE**: `tms_admin` only.
- Helper `tms_internal.evidence_site_from_path(text) returns uuid` — SECURITY DEFINER, immutable, returns NULL on malformed/non-UUID prefix (does not raise). Policies fall through to deny when NULL.
- MIME allowlist (in `rpc_finalise_evidence_upload`): `image/jpeg, image/png, image/webp, image/heic, image/heif, application/pdf`.

## Migration A12 — Abbey seed (idempotent, final correction 1)

All upserts use the parent-scoped composite targets from A1.

- Site `ABBEY_LC`.
- Templates: `(ABBEY, 'TUE'|'FRI'|'SUN')`, `expected_weekday` 2/5/0.
- `template_rating_lines` codes `LINE_01…` per template: Tuesday 7 lines, Friday 11 lines (male+female base), Sunday 9 lines.
- `template_scope_items` codes `AREA_*`, `BASE_*`, `SECONDARY_*`, `LIMIT_*` — actual structured schedule (primary areas, base tasks, secondary maintenance, limitations). **Not** duplicates of rating lines (final correction 5).
- `focus_categories` and `focus_items` with site-scoped codes; `acceptance_standard` populated.
- **Two** rotation programmes (final correction 1):
  - `ABBEY_FRIDAY_4WK` linked to FRI template — 4 male/female dryside steps.
  - `ABBEY_SUNDAY_4WK` linked to SUN template — 4 cubicle/detail steps.
  - Both `anchor_date = NULL`. **No** `is_active` column (final correction 10) — readiness is `anchor_date IS NOT NULL`, lifecycle is `archived_at`. Tuesday has no programme.
- `rotation_steps (rotation_programme_id, week_number)` 1–4 each, plus `rotation_step_focus_items`.
- `issue_types`, `constraint_types`, `visit_team_role_options` catalogues.
- `rpc_set_rotation_anchor(p_programme_id uuid, p_anchor_date date)` — `tms_admin` only, sets the anchor and writes `activity_log`.

## Migration A13 — Urgent H&S action source (final correction 8)

- `actions` adds `source_visit_constraint_id uuid null references public.visit_constraints(id)`.
- CHECK: when `urgent_hs_flag = true` then at least one of `source_review_line_score_id`, `source_focus_item_score_id`, `source_visit_constraint_id` must be NOT NULL.
- `rpc_submit_review` only creates an urgent action when the review-level urgent flag is bound to a specific source row (line/focus/constraint). Floating urgent actions are rejected.

## UI / TypeScript surgical edits

Only files implicated by the audit; the 800-line `visits.$visitId.tsx` is edited in place.

- `src/lib/auth-context.tsx` — `onAuthStateChange`:
  - Track `wasAuthenticated` ref. Only on transition `false → true` invalidate the auth-gate route; otherwise no action on `SIGNED_IN`.
  - `TOKEN_REFRESHED`: session updated internally; no router/query invalidation.
  - Duplicate `SIGNED_IN`: ignored.
  - `USER_UPDATED`: targeted invalidate of `['me','profile','roles']`.
  - `SIGNED_OUT`: `cancelQueries` + `qc.clear()` + `router.invalidate()`. Dirty forms never reset because of any auth event (final correction 9).
- `src/routes/_authenticated/visits.$visitId.tsx`:
  - C6: rehydrate the review form via `getReviewDetail`; switch to `react-hook-form` `useForm` + `reset(serverValues)` keyed on `review.id`+`review.version_no`; full-replacement save semantics.
  - C1 UI: 1–5 + N/A control on rating lines **and** focus items; require comment when `rating ≤ 2` on both (final correction 3); require `na_reason` when `is_na`.
  - C7: draft selection filtered to `r.status==='draft' && r.reviewer_id===user.id`.
  - H1: skipped/inaccessible recommendation flips remove matching `visit_focus_items` rows in the same save payload.
  - H2: full id-set replacement of focus items; explicit remove control.
  - H3: client guard mirrors server completeness.
  - H4 / final correction 8: urgent H&S binds to a specific source row (line/focus/constraint); UI requires picking one.
  - H11: `formState.isDirty` blocks `reset(serverValues)` while dirty; `useQuery` uses `refetchOnWindowFocus:false`, `refetchOnMount:false`.
  - Visit-already-exists handling.
- `src/routes/_authenticated/visits.new.tsx`: Europe/London local date default via `Intl.DateTimeFormat`; canonical role label set.
- `src/routes/_authenticated/actions.$actionId.tsx`: allowed transitions derived from new permission matrix + assignee scope eligibility; disabled buttons explain why.
- `src/routes/_authenticated/admin.users.tsx`: explicit `null` for global role; refuses last-admin revoke (server-side); admin invite via `inviteUserByEmail` server function — **the server function independently validates `auth.uid()` is `tms_admin` server-side** (final correction 11), route protection treated as defence-in-depth only.
- `src/lib/tms/queries.ts`: switch supervisor/reviewer/team/assignee name lookups from `profiles` to `rpc_site_user_directory`. Remove `any` casts only on touched paths.

## Tests — outside migrations (final correction 9)

- Location: `supabase/tests/acceptance/*.sql`. Not under `supabase/migrations/`; never applied to production.
- Driver: `bun scripts/db-test.ts` runs each file in a single transaction (rolled back).
- RLS simulation per scenario:
  ```sql
  select set_config('request.jwt.claims',
                    '{"sub":"<uuid>","role":"authenticated"}'::text, true);
  set local role authenticated;
  select auth.uid();  -- sanity
  ```
- Coverage: legal+illegal visit and action transitions (real rows), no-role denial, two-site isolation, cross-visit score rejection (A5), review ownership (A7), reopen blocked by active draft (correction 4), submit-after-reopen rejected, submitted/score/evidence immutability, duplicate-visit guard, 1–5/N/A and comment-on-low-rating validation (both score tables), recommendation/focus reconciliation, action permission matrix + assignee scope eligibility, evidence finalisation parent/site/MIME/size, profile read scoping, `rpc_site_user_directory` access control, storage policies INSERT/SELECT/DELETE per role, malformed path returning NULL safely, urgent H&S source FK requirement.
- `IMPLEMENTATION_REPORT.md` records: target environment (live Cloud project), generated/executed/passed/failed/manual-only test counts, migration list, manual Cloud steps (disable public signup; set rotation anchors via `rpc_set_rotation_anchor`; email auth config), known limitations, Phase 2 backlog.

## Out of scope this pass

Monolith decomposition of `visits.$visitId.tsx`; full action UI (assignee picker, due date, evidence upload UI); server-side pagination; joint-walk UI; catalogue CRUD; trend reporting; scaffold pruning; branding metadata.

## Execution order

```text
A1  schema preconditions
A2  transition trigger fix
A3  role catalogue migration
A4  rating model (gated)
A5  composite visit integrity
A6  action permission matrix + assignee scope
A7  review ownership + new supersede pair + reopen reconciliation
A8  historic snapshots + acceptance_standard
A9  duplicate visit guard + profile policy + rpc_site_user_directory
A10 evidence finalisation hardened
A11 storage policies
A12 Abbey seed
A13 urgent H&S source FK
UI  surgical edits
TST supabase/tests/acceptance/; IMPLEMENTATION_REPORT.md
```
