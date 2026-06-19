import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { dashboardCounters, listVisits, listActions } from "@/lib/tms/queries";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { visitStatusLabel, actionStatusLabel } from "@/lib/labels";

export const Route = createFileRoute("/_authenticated/")({
  component: Dashboard,
});

function Dashboard() {
  const counters = useQuery({ queryKey: ["dashboard"], queryFn: dashboardCounters });
  const recentVisits = useQuery({
    queryKey: ["visits", "recent"],
    queryFn: () => listVisits(null),
  });
  const openActions = useQuery({ queryKey: ["actions", "list"], queryFn: () => listActions(null) });

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
          <p className="text-sm text-muted-foreground">
            Cleaning quality at a glance across your sites.
          </p>
        </div>
        <Link
          to="/visits/new"
          className="inline-flex items-center px-3 py-2 rounded-md bg-primary text-primary-foreground text-sm font-medium hover:bg-primary/90"
        >
          New visit
        </Link>
      </header>

      <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {(counters.data ?? []).map((c) => (
          <Card key={c.site_id ?? "_"}>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">{c.site_name}</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-muted-foreground">Open visits</span>
                <span className="font-medium">{c.visits_open}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Awaiting review</span>
                <span className="font-medium">{c.visits_awaiting_review}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Open actions</span>
                <span className="font-medium">{c.actions_open}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Urgent H&S</span>
                <span className="font-medium text-destructive">{c.actions_urgent_hs}</span>
              </div>
            </CardContent>
          </Card>
        ))}
        {counters.isSuccess && (counters.data?.length ?? 0) === 0 && (
          <Card className="sm:col-span-2 lg:col-span-4">
            <CardContent className="py-8 text-center text-sm text-muted-foreground">
              No sites accessible. An administrator needs to assign you a site role.
            </CardContent>
          </Card>
        )}
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-2">Recent visits</h2>
        <div className="border rounded-lg divide-y">
          {(recentVisits.data ?? []).slice(0, 10).map((v: any) => (
            <Link
              key={v.id}
              to="/visits/$visitId"
              params={{ visitId: v.id }}
              className="flex items-center justify-between p-3 hover:bg-accent gap-3 text-sm"
            >
              <div className="min-w-0 flex-1">
                <div className="font-medium truncate">{v.visit_templates?.name}</div>
                <div className="text-xs text-muted-foreground">
                  {v.sites?.name} · {v.visit_date}
                </div>
              </div>
              <Badge variant="secondary">{visitStatusLabel[v.status] ?? v.status}</Badge>
            </Link>
          ))}
          {recentVisits.isSuccess && (recentVisits.data?.length ?? 0) === 0 && (
            <div className="p-6 text-sm text-muted-foreground text-center">No visits yet.</div>
          )}
        </div>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-2">Open actions</h2>
        <div className="border rounded-lg divide-y">
          {(openActions.data ?? [])
            .filter((a: any) => a.status !== "closed" && a.status !== "cancelled")
            .slice(0, 10)
            .map((a: any) => (
              <Link
                key={a.id}
                to="/actions/$actionId"
                params={{ actionId: a.id }}
                className="flex items-center justify-between p-3 hover:bg-accent gap-3 text-sm"
              >
                <div className="min-w-0 flex-1">
                  <div className="font-medium truncate">{a.title}</div>
                  <div className="text-xs text-muted-foreground">{a.sites?.name}</div>
                </div>
                {a.urgent_hs_flag && <Badge variant="destructive">Urgent H&S</Badge>}
                <Badge variant="secondary">{actionStatusLabel[a.status] ?? a.status}</Badge>
              </Link>
            ))}
        </div>
      </section>
    </div>
  );
}
