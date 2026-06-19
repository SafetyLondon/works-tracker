# Acceptance test harness (Slice D)

These files are SQL acceptance tests for the TMS database, RPCs, RLS and
Storage policies. They are designed to run inside a transaction that is
rolled back at the end so they leave no data behind. They MUST NOT be run
against the live production database.

## Files

| File | Mode | Purpose |
| --- | --- | --- |
| `00_helpers.sql` | preamble | Helper functions / fixture builders. Loaded by every test. |
| `01_read_only_assertions.sql` | **read-only** | Pure `SELECT` assertions: catalogues, role definitions, Abbey seed reproducibility, immutability triggers, schema invariants. Safe to run against any environment. |
| `10_auth_roles.sql` | mutating | Role assignment, global tms_admin (site_id NULL), centre site-scoping, cross-site isolation. |
| `20_visit_workflow.sql` | mutating | Visit creation, weekday override, duplicate handling, transition matrix, supervisor handover, recommendation/focus reconciliation, optimistic lock, immutability after submit. |
| `30_review_workflow.sql` | mutating | `rpc_start_review_draft`, save/submit, rating-line + focus-item completeness, urgent-H&S source binding, auto-actions, supersede flow, reopen-with-cancel. |
| `40_actions.sql` | mutating | `rpc_progress_action` transition matrix, scope eligibility, verifier ≠ assignee, role gating. |
| `50_directory_privacy.sql` | mutating | `rpc_site_user_directory` shape and authorisation; `profiles` policy. |
| `60_evidence_storage.sql` | mutating | `rpc_finalise_evidence_upload`, MIME/size validation, cross-site denial, malformed path safety, RLS on `evidence_items`. |
| `70_seed_idempotency.sql` | mutating | Re-applies the Abbey seed and asserts no new rows; verifies snapshot immutability across template edits. |

## How to run

Use a **non-production** Postgres connection (local Supabase, dedicated test
project, or a snapshot of staging). Then:

```bash
bun run db:test                 # runs every file (00 first, then numerically)
bun run db:test -- 01           # only read-only assertions
bun run db:test -- 10 20        # specific suites
```

The runner (`scripts/db-test.ts`) wraps every numeric suite in a `BEGIN ...
ROLLBACK` so test data never persists. The `00_helpers.sql` preamble is
loaded inside the same transaction.

## JWT / role conventions

Each permission scenario sets the request claims and database role
explicitly. Tests must call `tests.assert_uid(...)` before each scenario
to fail fast if the JWT claim is misconfigured. Example:

```sql
SELECT tests.set_user('11111111-1111-1111-1111-111111111111');
SELECT tests.assert_uid('11111111-1111-1111-1111-111111111111');
-- ... call RPCs as that user ...
```

## Live environment

The current sandbox only has read-only PG access to the **live**
production database. Mutating suites (`10`–`70`) are committed to the
repository but are NOT executed in this slice; they are marked
`Generated — Not Executed` in `QA_EXECUTION_REPORT.md`. The read-only
suite (`01`) IS executed against live because it makes no writes.
