import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, useEffect, useMemo } from "react";
import { supabase } from "@/integrations/supabase/client";
import { siteUserDirectory } from "@/lib/tms/queries";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  actionStatusLabel,
  actionPriorityLabel,
  scopeClassificationLabel,
  roleLabel,
} from "@/lib/labels";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-context";
import type { Database } from "@/integrations/supabase/types";

type ActionStatus = Database["public"]["Enums"]["action_status"];
type ScopeClassification = Database["public"]["Enums"]["scope_classification"];

export const Route = createFileRoute("/_authenticated/actions/$actionId")({
  component: ActionDetail,
});

// Mirrors tms_internal.action_assignee_eligible(_user, _site, _scope).
// Source of truth lives in the database — this is the UI shadow used for
// disabling controls. The backend still rejects ineligible assignees.
const ELIGIBLE_ROLES_BY_SCOPE: Record<ScopeClassification, string[]> = {
  routine_cleaning: ["tms_admin", "tms_supervisor", "tms_operative"],
  rotating_focus: ["tms_admin", "tms_supervisor", "tms_operative"],
  equipment_chemical: ["tms_admin", "tms_supervisor", "tms_operative"],
  maintenance_site_fabric: [
    "tms_admin",
    "tms_supervisor",
    "centre_operations_manager",
    "centre_gm",
  ],
  access: [
    "tms_admin",
    "tms_supervisor",
    "centre_operations_manager",
    "centre_gm",
  ],
  out_of_scope: [
    "tms_admin",
    "tms_supervisor",
    "centre_operations_manager",
    "centre_gm",
  ],
  additional_resource: [
    "tms_admin",
    "tms_supervisor",
    "centre_operations_manager",
    "centre_gm",
  ],
  urgent_hs: [
    "tms_admin",
    "tms_supervisor",
    "centre_operations_manager",
    "centre_gm",
  ],
};

type TransitionDecision = {
  status: ActionStatus;
  allowed: boolean;
  reason?: string;
  variant?: "default" | "destructive" | "outline";
};

function decideTransitions(args: {
  status: ActionStatus;
  scope: ScopeClassification;
  isAdmin: boolean;
  isSupervisor: boolean;
  isVerifier: boolean;
  isAssignee: boolean;
  isEligibleByScope: boolean;
}): TransitionDecision[] {
  const { status, isAdmin, isSupervisor, isVerifier, isAssignee, isEligibleByScope } = args;
  const canManage = isAdmin || isSupervisor;

  const block = (s: ActionStatus, reason: string): TransitionDecision => ({
    status: s,
    allowed: false,
    reason,
  });
  const allow = (
    s: ActionStatus,
    variant?: TransitionDecision["variant"],
  ): TransitionDecision => ({ status: s, allowed: true, variant });

  switch (status) {
    case "open":
      return [
        canManage ? allow("assigned") : block("assigned", "Only TMS supervisors can assign."),
        canManage || isAssignee || isEligibleByScope
          ? allow("in_progress")
          : block("in_progress", "Not eligible for this action's scope."),
        canManage
          ? allow("cancelled", "destructive")
          : block("cancelled", "Only TMS supervisors can cancel."),
      ];
    case "assigned":
      return [
        canManage || isAssignee
          ? allow("in_progress")
          : block("in_progress", "Only the assignee or a supervisor can progress this."),
        canManage || isAssignee
          ? allow("blocked")
          : block("blocked", "Only the assignee or a supervisor can mark this blocked."),
        canManage
          ? allow("cancelled", "destructive")
          : block("cancelled", "Only TMS supervisors can cancel."),
      ];
    case "in_progress":
      return [
        canManage || isAssignee
          ? allow("blocked")
          : block("blocked", "Only the assignee or a supervisor can mark this blocked."),
        canManage || isAssignee
          ? allow("awaiting_verification")
          : block(
              "awaiting_verification",
              "Only the assignee or a supervisor can submit for verification.",
            ),
        canManage
          ? allow("cancelled", "destructive")
          : block("cancelled", "Only TMS supervisors can cancel."),
      ];
    case "blocked":
      return [
        canManage || isAssignee
          ? allow("in_progress")
          : block("in_progress", "Only the assignee or a supervisor can resume this."),
        canManage
          ? allow("cancelled", "destructive")
          : block("cancelled", "Only TMS supervisors can cancel."),
      ];
    case "awaiting_verification":
      return [
        isVerifier && !isAssignee
          ? allow("closed", "default")
          : block(
              "closed",
              isAssignee
                ? "Verifier cannot be the current assignee."
                : "Requires TMS Admin / Supervisor / Centre Ops / GM to verify.",
            ),
        isVerifier
          ? allow("in_progress")
          : block("in_progress", "Requires a verifier to reopen this."),
        canManage
          ? allow("cancelled", "destructive")
          : block("cancelled", "Only TMS supervisors can cancel."),
      ];
    case "closed":
    case "cancelled":
      return [];
    default:
      return [];
  }
}

function ActionDetail() {
  const { actionId } = Route.useParams();
  const qc = useQueryClient();
  const { user, hasSiteRole, isAdmin, roles } = useAuth();

  const action = useQuery({
    queryKey: ["action", actionId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("actions")
        .select("*, sites(name), cleaning_visits(visit_date)")
        .eq("id", actionId)
        .maybeSingle();
      if (error) throw error;
      return data;
    },
  });

  const log = useQuery({
    queryKey: ["action", actionId, "log"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity_log")
        .select("*")
        .eq("entity_kind", "action")
        .eq("entity_id", actionId)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });

  const a = action.data;
  const siteId = a?.site_id ?? null;

  // Directory: drives the assignee picker and any name display. Restricted
  // profiles table is never queried directly.
  const directory = useQuery({
    queryKey: ["site-directory", siteId],
    queryFn: () => siteUserDirectory(siteId!),
    enabled: !!siteId,
  });

  const [note, setNote] = useState("");
  const [version, setVersion] = useState<number>(0);
  const [assignDraft, setAssignDraft] = useState<string>("");

  useEffect(() => {
    if (a?.version_no) setVersion(a.version_no);
    setAssignDraft(a?.assignee_id ?? "");
  }, [a?.version_no, a?.assignee_id]);

  // Permission matrix derived from auth context + action shape.
  const matrix = useMemo(() => {
    if (!a || !user) return null;
    const isMyOwnRole = (codes: string[]) =>
      isAdmin || hasSiteRole(a.site_id, codes);
    const isAssignee = a.assignee_id === user.id;
    const isSupervisor = isMyOwnRole(["tms_supervisor"]);
    const isVerifier = isMyOwnRole([
      "tms_admin",
      "tms_supervisor",
      "centre_operations_manager",
      "centre_gm",
    ]);
    const eligibleRoles =
      ELIGIBLE_ROLES_BY_SCOPE[a.scope_classification as ScopeClassification] ?? [];
    const isEligibleByScope = isMyOwnRole(eligibleRoles);

    // Exclusions: these roles must never see action mutation controls here.
    // We compute "has only excluded role(s)" against this site.
    const siteRoles = roles
      .filter((r) => r.site_id === a.site_id || r.site_id === null)
      .map((r) => r.role_code);
    const onlyExcluded =
      !isAdmin &&
      siteRoles.length > 0 &&
      siteRoles.every((c) =>
        ["read_only_viewer", "centre_dm_reviewer"].includes(c),
      );

    const transitions = onlyExcluded
      ? []
      : decideTransitions({
          status: a.status as ActionStatus,
          scope: a.scope_classification as ScopeClassification,
          isAdmin,
          isSupervisor,
          isVerifier,
          isAssignee,
          isEligibleByScope,
        });

    const canAssign = !onlyExcluded && (isAdmin || isSupervisor);

    return {
      transitions,
      canAssign,
      isAssignee,
      onlyExcluded,
    };
  }, [a, user, isAdmin, hasSiteRole, roles]);

  const progress = useMutation({
    mutationFn: async (newStatus: ActionStatus) => {
      const { data, error } = await supabase.rpc("rpc_progress_action", {
        p_action_id: actionId,
        p_expected_version: version,
        p_new_status: newStatus,
        p_note: note || undefined,
        p_assignee_id: undefined,
      });
      if (error) throw error;
      return data as number;
    },
    onSuccess: () => {
      toast.success("Action updated");
      setNote("");
      qc.invalidateQueries({ queryKey: ["action", actionId] });
      qc.invalidateQueries({ queryKey: ["action", actionId, "log"] });
      qc.invalidateQueries({ queryKey: ["actions"] });
    },
    onError: (e: any) => toast.error(e.message ?? "Action rejected by server"),
  });

  const reassign = useMutation({
    mutationFn: async () => {
      if (!a) return 0;
      const target = assignDraft || null;
      // rpc_progress_action accepts assignment without a real status change
      // when p_new_status matches the current status (and p_assignee_id differs).
      // Use the current status to drive the assignment-only path.
      const { data, error } = await supabase.rpc("rpc_progress_action", {
        p_action_id: actionId,
        p_expected_version: version,
        p_new_status: a.status as ActionStatus,
        p_note: note || undefined,
        p_assignee_id: target ?? undefined,
      });
      if (error) throw error;
      return data as number;
    },
    onSuccess: () => {
      toast.success("Assignment updated");
      setNote("");
      qc.invalidateQueries({ queryKey: ["action", actionId] });
      qc.invalidateQueries({ queryKey: ["actions"] });
    },
    onError: (e: any) => toast.error(e.message ?? "Reassignment rejected by server"),
  });

  if (action.isLoading) return <div>Loading…</div>;
  if (!a) return <div>Action not found.</div>;

  // Eligible-assignee subset of the directory for this scope.
  const eligibleRoles =
    ELIGIBLE_ROLES_BY_SCOPE[a.scope_classification as ScopeClassification] ?? [];
  const eligibleAssignees = (directory.data ?? [])
    .filter((d) => eligibleRoles.includes(d.role_code))
    // Dedupe per user_id (a user may have several role rows).
    .reduce<Array<{ user_id: string; display_name: string | null; role_code: string }>>(
      (acc, d) => {
        if (!acc.find((x) => x.user_id === d.user_id))
          acc.push({
            user_id: d.user_id,
            display_name: d.display_name,
            role_code: d.role_code,
          });
        return acc;
      },
      [],
    );

  const assigneeName =
    (a.assignee_id &&
      (directory.data ?? []).find((d) => d.user_id === a.assignee_id)?.display_name) ||
    null;

  const transitions = matrix?.transitions ?? [];
  const visibleTransitions = transitions.filter((t) => t.allowed || t.reason);
  const showControls = !matrix?.onlyExcluded && (visibleTransitions.length > 0 || matrix?.canAssign);

  return (
    <div className="space-y-4 max-w-2xl">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">{a.title}</h1>
        <div className="text-sm text-muted-foreground">
          {(a as any).sites?.name}
          {(a as any).cleaning_visits?.visit_date
            ? ` · Visit ${(a as any).cleaning_visits.visit_date}`
            : ""}
        </div>
        <div className="flex flex-wrap gap-2 mt-2">
          <Badge variant="secondary">{actionStatusLabel[a.status] ?? a.status}</Badge>
          <Badge variant="outline">{actionPriorityLabel[a.priority] ?? a.priority}</Badge>
          <Badge variant="outline">
            {scopeClassificationLabel[a.scope_classification] ?? a.scope_classification}
          </Badge>
          {a.urgent_hs_flag && <Badge variant="destructive">Urgent H&S</Badge>}
          {a.assignee_id && (
            <Badge variant="outline">
              Assignee: {assigneeName ?? a.assignee_id.slice(0, 8)}
            </Badge>
          )}
        </div>
      </header>

      {a.description && (
        <p className="text-sm whitespace-pre-wrap border rounded-md p-3 bg-muted/30">
          {a.description}
        </p>
      )}

      {matrix?.onlyExcluded && (
        <div className="text-sm border rounded-md p-3 bg-muted/30 text-muted-foreground">
          Your role on this site is read-only for actions. Contact a TMS
          supervisor or centre manager to progress this item.
        </div>
      )}

      {showControls && (
        <div className="space-y-3 border rounded-md p-3">
          <Textarea
            placeholder="Note (optional, recorded in history)"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />

          {matrix?.canAssign && (
            <div className="space-y-1">
              <div className="text-xs font-medium">Assignment</div>
              <div className="flex flex-wrap gap-2 items-center">
                <select
                  className="border rounded-md px-2 py-1.5 bg-background text-sm flex-1 min-w-[12rem]"
                  value={assignDraft}
                  onChange={(e) => setAssignDraft(e.target.value)}
                >
                  <option value="">— Unassigned —</option>
                  {eligibleAssignees.map((d) => (
                    <option key={d.user_id} value={d.user_id}>
                      {d.display_name ?? d.user_id.slice(0, 8)} ·{" "}
                      {roleLabel[d.role_code] ?? d.role_code}
                    </option>
                  ))}
                </select>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={reassign.isPending || assignDraft === (a.assignee_id ?? "")}
                  onClick={() => reassign.mutate()}
                >
                  {a.assignee_id ? "Reassign" : "Assign"}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground">
                Only users eligible for this action's scope (
                {scopeClassificationLabel[a.scope_classification] ?? a.scope_classification}
                ) are listed.
              </p>
            </div>
          )}

          {visibleTransitions.length > 0 && (
            <div className="space-y-1">
              <div className="text-xs font-medium">Status transitions</div>
              <div className="flex flex-wrap gap-2">
                {visibleTransitions.map((t) => (
                  <Button
                    key={t.status}
                    size="sm"
                    variant={t.variant ?? "outline"}
                    disabled={!t.allowed || progress.isPending}
                    title={t.reason}
                    onClick={() => t.allowed && progress.mutate(t.status)}
                  >
                    {actionStatusLabel[t.status]}
                  </Button>
                ))}
              </div>
              {visibleTransitions.some((t) => !t.allowed) && (
                <p className="text-xs text-muted-foreground">
                  Disabled buttons show why hovering over them.
                </p>
              )}
            </div>
          )}
        </div>
      )}

      <div className="space-y-2">
        <h2 className="text-sm font-semibold">History</h2>
        <ul className="text-xs space-y-1 border rounded-md p-3">
          {(log.data ?? []).map((e: any) => (
            <li key={e.id}>
              <span className="text-muted-foreground">
                {new Date(e.created_at).toLocaleString()}
              </span>{" "}
              — {e.action}
              {e.detail?.note ? `: ${e.detail.note}` : ""}
            </li>
          ))}
          {(log.data?.length ?? 0) === 0 && (
            <li className="text-muted-foreground">No history.</li>
          )}
        </ul>
      </div>
    </div>
  );
}
