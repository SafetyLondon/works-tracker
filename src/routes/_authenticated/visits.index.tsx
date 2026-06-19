import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { listVisits } from "@/lib/tms/queries";
import { Badge } from "@/components/ui/badge";
import { visitStatusLabel } from "@/lib/labels";

export const Route = createFileRoute("/_authenticated/visits/")({
  component: VisitsList,
});

function VisitsList() {
  const { data, isLoading } = useQuery({
    queryKey: ["visits", "all"],
    queryFn: () => listVisits(null),
  });

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Visits</h1>
        <Link
          to="/visits/new"
          className="inline-flex items-center px-3 py-2 rounded-md bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90"
        >
          New visit
        </Link>
      </header>

      {isLoading && <div className="text-sm text-muted-foreground">Loading…</div>}

      <div className="border rounded-lg divide-y">
        {(data ?? []).map((v: any) => (
          <Link
            key={v.id}
            to="/visits/$visitId"
            params={{ visitId: v.id }}
            className="flex items-center justify-between p-3 hover:bg-accent gap-3"
          >
            <div className="min-w-0 flex-1">
              <div className="font-medium truncate">{v.visit_templates?.name}</div>
              <div className="text-xs text-muted-foreground">
                {v.sites?.name} · {v.visit_date}
                {v.recommended_rotation_week
                  ? ` · Week ${v.rotation_week_override ?? v.recommended_rotation_week}`
                  : ""}
              </div>
            </div>
            <Badge variant="secondary">{visitStatusLabel[v.status] ?? v.status}</Badge>
          </Link>
        ))}
        {data && data.length === 0 && (
          <div className="p-6 text-sm text-muted-foreground text-center">No visits found.</div>
        )}
      </div>
    </div>
  );
}
