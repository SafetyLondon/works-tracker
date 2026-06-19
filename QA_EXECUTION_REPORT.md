# QA Execution Report — Slice D

| Field          | Value |
| -------------- | --- |
| Date           | 2026-06-09 |
| Environment    | Live Lovable Cloud project `eikuawrkendyfnecrqpk` (read-only assertions only). Sandbox PG access cannot create the `tests` schema, so mutating suites are **Not Run** here. |
| Harness        | `supabase/tests/acceptance/{00…70}.sql` + `scripts/db-test.ts` (`bun run db:test`) |
| Safety guard   | Runner refuses to run mutating suites against a production-looking PGHOST unless `LOVABLE_DB_TEST_ALLOW_PROD=1` is set. |
| Typecheck      | `bunx tsc --noEmit` → clean exit, no errors. |

Result codes: **P** = Pass, **F** = Fail, **B** = Blocked (environmental), **NR** = Not Run (no safe environment in this slice), **G** = Generated only.

## Static / build validation

| ID  | Name                                                           | Env       | Result | Evidence |
| --- | -------------------------------------------------------------- | --------- | ------ | --- |
| ST-01 | TypeScript typecheck                                         | sandbox   | P      | `bunx tsc --noEmit` exit 0, no output. |
| ST-02 | Routes: no duplicate `user` declaration in `visits.$visitId.tsx` | sandbox | P  | Re-verified after dev-server restart in the prior pass; typecheck would otherwise fail. |
| ST-03 | `package.json` exposes `db:test`                             | sandbox   | P      | `scripts.db:test = bun scripts/db-test.ts`. |
| ST-04 | Production build (`vite build`)                              | sandbox   | NR     | Not requested in this slice; typecheck already covers route-tree integrity. |
| ST-05 | Lint (`eslint .`)                                            | sandbox   | NR     | Not requested in this slice. |

## Read-only DB assertions (executed against live)

The full block lives in `supabase/tests/acceptance/01_read_only_assertions.sql`. An equivalent inline `DO` block (without the `tests` helper schema) was executed against live and emitted `NOTICE: ALL READ-ONLY ASSERTIONS PASSED`.

| ID  | Name                                                              | Env  | Result |
| --- | ----------------------------------------------------------------- | ---- | ------ |
| RO-01 | Seven canonical role codes present                              | live | P |
| RO-02 | Legacy role codes (`site_supervisor`, `site_operative`, `ops_manager`, `gm`) absent | live | P |
| RO-03 | `tms_admin.is_global` = true                                    | live | P |
| RO-04 | Abbey site exists                                               | live | P |
| RO-05 | Three Abbey templates with expected weekdays 2 / 5 / 0          | live | P |
| RO-06 | Tuesday rating-line count = 7                                    | live | P |
| RO-07 | Friday rating-line count = 11                                    | live | P |
| RO-08 | Sunday rating-line count = 9                                     | live | P |
| RO-09 | All four scope `item_type`s present across Abbey                 | live | P |
| RO-10 | Scope items present for every Abbey template                     | live | P |
| RO-11 | Friday and Sunday rotation programmes exist                      | live | P |
| RO-12 | Rotation anchors are NULL                                        | live | P |
| RO-13 | Tuesday has no rotation programme                                | live | P |
| RO-14 | Each rotation programme has 4 steps                              | live | P |
| RO-15 | Every rotation step has ≥1 focus link                            | live | P |
| RO-16 | `reviews.urgent_source_constraint_id` column exists (Slice A)    | live | P |
| RO-17 | `focus_item_scores.cleaning_visit_id` column exists              | live | P |
| RO-18 | Four `evidence_*` policies on `storage.objects`                  | live | P |
| RO-19 | All 14 workflow RPCs present in `public`                         | live | P |
| RO-20 | `profiles` has `*_self_or_admin*` policy (no broad reads)        | live | P |
| RO-21 | No duplicate stable codes within parent scope (lines, scope items, focus items) | live | P |

## Mutating DB acceptance suites (generated; require disposable DB to execute)

These cover everything in the Slice D test brief. They are committed and ready to run via `bun run db:test` against a local Supabase / disposable test project. They are **not** executed in this slice because no disposable environment is attached to the sandbox.

| ID  | Suite | File | Result |
| --- | ----- | ---- | ------ |
| AR-* | Auth & roles (global admin, site scoping, cross-site denial, no-role lockout) | `10_auth_roles.sql`         | G / NR |
| VW-* | Visit workflow (create, weekday override, duplicate, supervisor handover, recommendation reconciliation, optimistic lock, immutability, illegal transitions) | `20_visit_workflow.sql`     | G / NR |
| RV-* | Review workflow (start draft, owner-only edit, completeness for lines + focus, urgent H&S source, supersede, admin reopen-with-cancel, submitted immutability) | `30_review_workflow.sql`    | G / NR |
| AC-* | Actions (`rpc_progress_action` matrix: role gating, scope eligibility, verifier ≠ assignee, illegal transition rejection) | `40_actions.sql`            | G / NR |
| DP-* | Directory & profile privacy (no email, authorised-site only, profile RLS) | `50_directory_privacy.sql`  | G / NR |
| EV-* | Evidence & storage (bucket private, policies present, malformed path safety, unknown parent rejected) | `60_evidence_storage.sql`   | G / NR |
| SI-* | Seed idempotency (counts stable after re-apply) | `70_seed_idempotency.sql`   | G / NR |

Mutating-test environment blocker: the sandbox has read-only PG access to the live project (`permission denied for database postgres` when creating the `tests` schema). The runner correctly refused to fall back to live for mutating tests.

## Manual UI checks (not executed in this slice; require a logged-in browser session)

| ID    | Check | Status |
| ----- | ----- | ------ |
| UI-01 | Sign-in and `_authenticated` guard redirects unauthenticated users to `/auth`. | Not executed |
| UI-02 | Handover dirty state survives non-material query refetch (Slice A guard). | Not executed |
| UI-03 | Review line and focus scores rehydrate from server on revisit. | Not executed |
| UI-04 | Another reviewer's draft shows "Review currently in progress by [Name]" read-only banner. | Not executed |
| UI-05 | Reviewer context panel loads via `rpc_site_user_directory`. | Not executed |
| UI-06 | Action controls reflect caller permissions (Slice B `decideTransitions`). | Not executed |
| UI-07 | Duplicate visit response (`created=false`) handled correctly in `visits.new.tsx`. | Not executed |
| UI-08 | London-local date used in visit-date pickers. | Not executed |

These must be exercised before pilot sign-off. Code paths are in place; nothing in this slice changed them.

## Live-vs-plan conflicts (Slice C carry-forward)

See `IMPLEMENTATION_REPORT.md` § "Live-vs-plan conflicts" for the dedicated, per-conflict table covering live value, plan value, why live was preserved, operational impact, security impact, release-blocking status and recommendation.
