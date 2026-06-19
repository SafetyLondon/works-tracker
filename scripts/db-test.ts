#!/usr/bin/env bun
/**
 * scripts/db-test.ts — acceptance-test runner.
 *
 * Reads PG* environment variables (PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE)
 * and runs each `supabase/tests/acceptance/NN_*.sql` file inside a single
 * transaction that is ROLLED BACK at the end. `00_helpers.sql` is loaded as a
 * preamble inside the same transaction.
 *
 * Safety:
 *   * Refuses to run if PGHOST resolves to a production-looking host unless
 *     LOVABLE_DB_TEST_ALLOW_PROD=1 is set (an explicit operator opt-in).
 *   * Wraps every numeric suite in BEGIN ... ROLLBACK so tests never persist
 *     fixtures. Read-only assertions (01_*) don't need the rollback but use
 *     the same wrapper for uniformity.
 *
 * Usage:
 *   bun run db:test                  # run every NN_* file (00 helpers + all)
 *   bun run db:test 01               # run a specific suite
 *   bun run db:test 10 20 30         # run a subset
 */
import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";

const ROOT = resolve(import.meta.dir, "..");
const DIR = join(ROOT, "supabase", "tests", "acceptance");

function fail(msg: string): never {
  process.stderr.write(`db-test: ${msg}\n`);
  process.exit(1);
}

const host = process.env.PGHOST ?? "";
if (!host) fail("PGHOST is not set; configure PG* env vars before running.");

const looksProd =
  /supabase\.co$|prod|production/i.test(host) ||
  /eikuawrkendyfnecrqpk/.test(host); // current live project ref
if (looksProd && process.env.LOVABLE_DB_TEST_ALLOW_PROD !== "1") {
  fail(
    `refusing to run against what looks like a production host (${host}). ` +
      "Set LOVABLE_DB_TEST_ALLOW_PROD=1 to override — only after confirming " +
      "you're pointed at a disposable test database.",
  );
}

const argv = process.argv.slice(2).filter((a) => /^\d+$/.test(a));
const files = readdirSync(DIR)
  .filter((f) => /^\d{2}_.*\.sql$/.test(f))
  .sort();

const preamble = readFileSync(join(DIR, "00_helpers.sql"), "utf8");
const selected = files
  .filter((f) => !f.startsWith("00_"))
  .filter((f) => argv.length === 0 || argv.some((p) => f.startsWith(p + "_")));

if (selected.length === 0) fail("no matching test files");

let totalFail = 0;
for (const f of selected) {
  const body = readFileSync(join(DIR, f), "utf8");
  const script =
    "BEGIN;\n" +
    "SET LOCAL client_min_messages = NOTICE;\n" +
    preamble +
    "\n" +
    body +
    "\nROLLBACK;\n";

  process.stdout.write(`\n=== ${f} ===\n`);
  const r = spawnSync(
    "psql",
    ["-v", "ON_ERROR_STOP=1", "-X", "-q", "-f", "-"],
    { input: script, stdio: ["pipe", "inherit", "inherit"] },
  );
  if (r.status !== 0) {
    totalFail += 1;
    process.stderr.write(`FAIL ${f}\n`);
  }
}

if (totalFail > 0) {
  process.stderr.write(`\n${totalFail} suite(s) failed.\n`);
  process.exit(1);
}
process.stdout.write("\nAll selected suites passed.\n");
