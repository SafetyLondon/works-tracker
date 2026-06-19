import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_authenticated/field-guide")({
  component: FieldGuide,
});

function FieldGuide() {
  return (
    <div className="prose prose-sm dark:prose-invert max-w-2xl space-y-4">
      <h1 className="text-2xl font-semibold">Field Guide</h1>

      <h2 className="text-lg font-semibold">Visit lifecycle</h2>
      <ol className="list-decimal pl-5 text-sm space-y-1">
        <li>Create a visit from the appropriate Tuesday / Friday / Sunday template for the visit date.</li>
        <li>The supervisor edits the handover while the visit is <em>draft</em>, <em>planned</em> or <em>in&nbsp;progress</em>.</li>
        <li>Every rotation recommendation must be resolved as <strong>selected</strong>, <strong>skipped</strong>, <strong>inaccessible</strong> or <strong>not applicable</strong> before the visit can be submitted. Skipped and inaccessible items require a reason.</li>
        <li>On submit, the visit moves to <strong>submitted for review</strong>.</li>
        <li>The next-morning reviewer (Centre DM by default) starts a review, scores the rating lines, marks failures with scope + issue type, and submits. Submitted reviews are immutable.</li>
        <li>Failures automatically create open <strong>actions</strong> with priority and scope classification preserved.</li>
        <li>Submitted reviews can be <strong>superseded</strong> by Ops/GM/Admin — the original is preserved verbatim and linked to the replacement.</li>
        <li>A visit can be <strong>reopened</strong> by Ops/GM/Admin with an audited reason. This returns it to <em>in&nbsp;progress</em>.</li>
      </ol>

      <h2 className="text-lg font-semibold">Scope classifications</h2>
      <ul className="list-disc pl-5 text-sm space-y-1">
        <li><strong>Routine cleaning</strong> — base-clean failure; the visit should have handled it.</li>
        <li><strong>Rotating focus</strong> — failure on a rotation focus item.</li>
        <li><strong>Maintenance / site fabric</strong> — building defect, not cleaning.</li>
        <li><strong>Access</strong> — area was inaccessible.</li>
        <li><strong>Equipment / chemical</strong> — equipment or chemical shortfall.</li>
        <li><strong>Out of scope</strong> — outside contracted scope.</li>
        <li><strong>Additional resource</strong> — needs extra labour or specialist resource.</li>
        <li><strong>Urgent H&amp;S</strong> — auto-applied to anything flagged as urgent health and safety.</li>
      </ul>

      <h2 className="text-lg font-semibold">Rotation week</h2>
      <p className="text-sm">
        Recommended week = <code>((visit_date − anchor_date) / 7) mod cycle_length + 1</code>.
        Supervisors and admins can override the week with a reason; the override is logged.
      </p>

      <h2 className="text-lg font-semibold">Abbey Leisure Centre — schedule</h2>
      <ul className="list-disc pl-5 text-sm space-y-1">
        <li><strong>Tuesday</strong> — Spa deep clean (7 rating lines, no rotation).</li>
        <li><strong>Friday</strong> — Dryside deep clean (11 rating lines, 4-week dryside rotation).</li>
        <li><strong>Sunday</strong> — Wetside deep clean (9 rating lines, 4-week wetside rotation).</li>
        <li>The plant-room interior is <strong>out of scope</strong> for cleaning.</li>
      </ul>

      <h2 className="text-lg font-semibold">User accounts</h2>
      <p className="text-sm">
        Public signup is disabled. Administrators create accounts in the backend Users
        dashboard. A new profile is auto-created on first sign-in, with no role attached;
        a TMS Administrator then assigns site roles in <code>/admin/users</code>.
        To remove access, disable the user in the backend rather than deleting the profile —
        this preserves the audit history.
      </p>
    </div>
  );
}
