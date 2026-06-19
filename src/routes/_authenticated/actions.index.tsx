import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { listActions } from "@/lib/tms/queries";
import { Badge } from "@/components/ui/badge";
import {
  actionStatusLabel,
  actionPriorityLabel,
  scopeClassificationLabel,
} from "@/lib/labels";
import { useState } from "react";

export const Route = createFileRoute("/_authenticated/actions/")({
  component: ActionsList,
});

function ActionsList() {
  const [showClosed, setShowClosed] = useState(false);
  const { data, isLoading } = useQuery({
    queryKey: ["actions", "list"],
    queryFn: () => listActions(null),
  });

  const filtered = (data ?? []).filter((a: any) =>
    showClosed ? true : a.status !== "closed" && a.status !== "cancelled",
  );

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">Actions</h1>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={showClosed}
            onChange={(e) => setShowClosed(e.target.checked)}
          />
          Show closed
        </label>
      </header>
      {isLoading && <div className="text-sm text-muted-foreground">Loading…</div>}
      <div className="border rounded-lg divide-y">
        {filtered.map((a: any) => (
          <Link
            key={a.id}
            to="/actions/$actionId"
            params={{ actionId: a.id }}
            className="flex items-center justify-between p-3 hover:bg-accent gap-3"
          >
            <div className="min-w-0 flex-1">
              <div className="font-medium truncate">{a.title}</div>
              <div className="text-xs text-muted-foreground">
                {a.sites?.name} · {scopeClassificationLabel[a.scope_classification] ?? a.scope_classification}
              </div>
            </div>
            {a.urgent_hs_flag && <Badge variant="destructive">Urgent H&S</Badge>}
            <Badge variant="outline">{actionPriorityLabel[a.priority] ?? a.priority}</Badge>
            <Badge variant="secondary">{actionStatusLabel[a.status] ?? a.status}</Badge>
          </Link>
        ))}
        {filtered.length === 0 && (
          <div className="p-6 text-sm text-muted-foreground text-center">No actions.</div>
        )}
      </div>
    </div>
  );
}
