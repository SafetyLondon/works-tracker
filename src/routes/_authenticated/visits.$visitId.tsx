import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useState, useEffect, useRef, type ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";
import { getVisitDetail, listOpenReviewForVisit, getReviewDetail, siteUserDirectory } from "@/lib/tms/queries";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EvidencePanel } from "@/components/evidence-panel";
import {
  visitStatusLabel,
  focusItemStatusLabel,
  recommendationStatusLabel,
  reviewStatusLabel,
  ratingLabel,
  scopeClassificationLabel,
  ROLES_HANDOVER_MANAGE,
  ROLES_REVIEW,
  ROLES_REOPEN,
} from "@/lib/labels";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-context";

export const Route = createFileRoute("/_authenticated/visits/$visitId")({
  component: VisitDetail,
});

function VisitDetail() {
  const { visitId } = Route.useParams();
  const { hasSiteRole, isAdmin } = useAuth();
  const qc = useQueryClient();
  const detail = useQuery({
    queryKey: ["visit", visitId],
    queryFn: () => getVisitDetail(visitId),
    refetchOnWindowFocus: false,
  });

  const v = detail.data?.visit;
  const isDraft =
    v?.status === "draft" || v?.status === "planned" || v?.status === "in_progress";

  if (detail.isLoading) return <div>Loading…</div>;
  if (!v) return <div>Visit not found.</div>;

  const canManage = isAdmin || hasSiteRole(v.site_id, ROLES_HANDOVER_MANAGE);
  const canReopen = isAdmin || hasSiteRole(v.site_id, ROLES_REOPEN);

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            {(v as any).visit_templates?.name}
          </h1>
          <div className="text-sm text-muted-foreground">
            {(v as any).sites?.name} · {v.visit_date}
            {v.recommended_rotation_week
              ? ` · Week ${v.rotation_week_override ?? v.recommended_rotation_week}`
              : ""}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant="secondary">{visitStatusLabel[v.status] ?? v.status}</Badge>
          <span className="text-xs text-muted-foreground">v{v.version_no}</span>
        </div>
      </header>

      {isDraft && canManage && <HandoverForm detail={detail.data!} onSaved={() => detail.refetch()} />}
      {!isDraft && <SubmittedView detail={detail.data!} />}

      <ReviewSection visitId={visitId} visit={v} detail={detail.data!} />

      {(v.status === "submitted_for_review" || v.status === "reviewed" || v.status === "closed") && canReopen && (
        <ReopenBlock
          visitId={visitId}
          onReopened={() => {
            qc.invalidateQueries({ queryKey: ["visit", visitId] });
          }}
        />
      )}
    </div>
  );
}

function HandoverForm({ detail, onSaved }: { detail: any; onSaved: () => void }) {
  const v = detail.visit;
  const [notes, setNotes] = useState<string>(v.notes ?? "");
  const [weather, setWeather] = useState<string>(v.weather ?? "");
  const [headcount, setHeadcount] = useState<string>(v.headcount?.toString() ?? "");
  const [recs, setRecs] = useState(detail.recommendations);
  const [focus, setFocus] = useState(detail.focus_items);
  const [constraints, setConstraints] = useState(detail.constraints);
  const [version, setVersion] = useState<number>(v.version_no);
  const [isDirty, setIsDirty] = useState(false);

  // Re-seed form ONLY when we are not dirty AND the server version actually
  // advanced (e.g. after our own save). Token refresh / background refetch
  // must never wipe in-progress edits.
  const initKey = useRef<string>(`${v.id}:${v.version_no}`);
  useEffect(() => {
    const key = `${v.id}:${v.version_no}`;
    if (key === initKey.current || isDirty) return;
    initKey.current = key;
    setNotes(v.notes ?? "");
    setWeather(v.weather ?? "");
    setHeadcount(v.headcount?.toString() ?? "");
    setRecs(detail.recommendations);
    setFocus(detail.focus_items);
    setConstraints(detail.constraints);
    setVersion(v.version_no);
  }, [v.id, v.version_no, detail, isDirty]);

  const markDirty = () => setIsDirty(true);

  const constraintTypes = useQuery({
    queryKey: ["constraint_types"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("constraint_types")
        .select("code, label, is_active")
        .eq("is_active", true)
        .order("sort_order");
      if (error) throw error;
      return data ?? [];
    },
  });

  const buildPayload = () => ({
    notes,
    weather,
    headcount: headcount ? parseInt(headcount, 10) : null,
    recommendations: recs.map((r: any) => ({
      id: r.id,
      recommendation_status: r.recommendation_status,
      resolution_reason: r.resolution_reason,
    })),
    focus_items: focus.map((f: any) => ({
      id: f.id,
      focus_name_snapshot: f.focus_name_snapshot,
      description_snapshot: f.description_snapshot,
      exact_location: f.exact_location,
      status: f.status,
      completion_note: f.completion_note,
      source_recommendation_id: f.source_recommendation_id,
      focus_item_id: f.focus_item_id,
    })),
    constraints: constraints.map((c: any) => ({
      constraint_type: c.constraint_type,
      description: c.description,
      affected_area: c.affected_area,
    })),
  });

  const saveDraft = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc("rpc_save_visit_draft", {
        p_visit_id: v.id,
        p_expected_version: version,
        p_payload: buildPayload(),
      });
      if (error) throw error;
      return data as number;
    },
    onSuccess: (newVersion) => {
      toast.success("Draft saved");
      setVersion(newVersion);
      setIsDirty(false);
      onSaved();
    },
    onError: (e: any) => toast.error(`Save failed: ${e.message}`),
  });

  const submit = useMutation({
    mutationFn: async () => {
      const { data: vNew, error: e1 } = await supabase.rpc("rpc_save_visit_draft", {
        p_visit_id: v.id,
        p_expected_version: version,
        p_payload: buildPayload(),
      });
      if (e1) throw e1;
      const { error: e2 } = await supabase.rpc("rpc_submit_supervisor_handover", {
        p_visit_id: v.id,
        p_expected_version: vNew as number,
      });
      if (e2) throw e2;
    },
    onSuccess: () => {
      toast.success("Visit submitted for review");
      setIsDirty(false);
      onSaved();
    },
    onError: (e: any) => toast.error(`Submit failed: ${e.message}`),
  });

  const addAdHocFocus = () => {
    markDirty();
    setFocus([
      ...focus,
      {
        id: null,
        focus_name_snapshot: "",
        description_snapshot: "",
        exact_location: "",
        status: "selected",
        completion_note: "",
        source_recommendation_id: null,
        focus_item_id: null,
        _adhoc: true,
      },
    ]);
  };

  const addConstraint = () => {
    markDirty();
    setConstraints([...constraints, { constraint_type: "other", description: "", affected_area: "" }]);
  };

  const pendingRec = recs.filter((r: any) => r.recommendation_status === "pending").length;

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Visit details</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-3">
          <div className="space-y-1">
            <Label>Weather</Label>
            <Input value={weather} onChange={(e) => { markDirty(); setWeather(e.target.value); }} />
          </div>
          <div className="space-y-1">
            <Label>Headcount</Label>
            <Input
              type="number"
              value={headcount}
              onChange={(e) => { markDirty(); setHeadcount(e.target.value); }}
            />
          </div>
          <div className="space-y-1 sm:col-span-3">
            <Label>Notes</Label>
            <Textarea rows={3} value={notes} onChange={(e) => { markDirty(); setNotes(e.target.value); }} />
          </div>
        </CardContent>
      </Card>

      {detail.scope_items.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Scope (snapshot at visit creation)</CardTitle>
          </CardHeader>
          <CardContent>
            {["primary_area", "base_task", "secondary_maintenance", "limitation"].map((type) => {
              const items = detail.scope_items.filter((s: any) => s.item_type === type);
              if (!items.length) return null;
              return (
                <div key={type} className="mb-3">
                  <h4 className="text-sm font-medium capitalize mb-1">
                    {type.replaceAll("_", " ")}
                  </h4>
                  <ul className="text-sm list-disc pl-5 space-y-0.5 text-muted-foreground">
                    {items.map((i: any) => (
                      <li key={i.id}>{i.label_snapshot}</li>
                    ))}
                  </ul>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}

      {recs.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">
              Rotation recommendations
              {pendingRec > 0 && (
                <Badge variant="destructive" className="ml-2">
                  {pendingRec} pending
                </Badge>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {recs.map((r: any, idx: number) => (
              <div key={r.id} className="border rounded-md p-3 space-y-2">
                <div className="font-medium text-sm">{r.focus_label_snapshot}</div>
                <div className="flex flex-wrap gap-2 text-sm">
                  {(["selected", "skipped", "inaccessible", "not_applicable"] as const).map((s) => (
                    <Button
                      key={s}
                      size="sm"
                      variant={r.recommendation_status === s ? "default" : "outline"}
                      onClick={() => {
                        markDirty();
                        const next = [...recs];
                        next[idx] = { ...next[idx], recommendation_status: s };
                        setRecs(next);
                        if (s === "selected") {
                          if (!focus.find((f: any) => f.source_recommendation_id === r.id)) {
                            setFocus([
                              ...focus,
                              {
                                id: null,
                                focus_name_snapshot: r.focus_label_snapshot,
                                description_snapshot: r.focus_description_snapshot,
                                exact_location: "",
                                status: "selected",
                                completion_note: "",
                                source_recommendation_id: r.id,
                                focus_item_id: r.focus_item_id,
                              },
                            ]);
                          }
                        } else {
                          // Reconcile: drop any actual focus item linked to this recommendation.
                          setFocus(focus.filter((f: any) => f.source_recommendation_id !== r.id));
                        }
                      }}
                    >
                      {recommendationStatusLabel[s]}
                    </Button>
                  ))}
                </div>
                {(r.recommendation_status === "skipped" ||
                  r.recommendation_status === "inaccessible") && (
                  <Textarea
                    placeholder="Reason (required)"
                    value={r.resolution_reason ?? ""}
                    onChange={(e) => {
                      markDirty();
                      const next = [...recs];
                      next[idx] = { ...next[idx], resolution_reason: e.target.value };
                      setRecs(next);
                    }}
                  />
                )}
              </div>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">Actual focus items</CardTitle>
          <Button size="sm" variant="outline" onClick={addAdHocFocus}>
            Add ad-hoc item
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {focus.length === 0 && (
            <p className="text-sm text-muted-foreground">
              Resolve recommendations or add ad-hoc items.
            </p>
          )}
          {focus.map((f: any, idx: number) => (
            <div key={f.id ?? `new-${idx}`} className="border rounded-md p-3 space-y-2">
              <div className="flex justify-end">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => { markDirty(); setFocus(focus.filter((_: any, i: number) => i !== idx)); }}
                >
                  Remove
                </Button>
              </div>
              <Input
                placeholder="Focus name"
                value={f.focus_name_snapshot ?? ""}
                onChange={(e) => {
                  markDirty();
                  const next = [...focus];
                  next[idx] = { ...next[idx], focus_name_snapshot: e.target.value };
                  setFocus(next);
                }}
              />
              <Input
                placeholder="Exact location (required)"
                value={f.exact_location ?? ""}
                onChange={(e) => {
                  markDirty();
                  const next = [...focus];
                  next[idx] = { ...next[idx], exact_location: e.target.value };
                  setFocus(next);
                }}
              />
              <select
                className="w-full border rounded-md px-3 py-2 bg-background text-sm"
                value={f.status}
                onChange={(e) => {
                  markDirty();
                  const next = [...focus];
                  next[idx] = { ...next[idx], status: e.target.value };
                  setFocus(next);
                }}
              >
                {Object.entries(focusItemStatusLabel).map(([code, label]) => (
                  <option key={code} value={code}>
                    {label}
                  </option>
                ))}
              </select>
              <Textarea
                placeholder="Completion note (required if completed/partial)"
                value={f.completion_note ?? ""}
                onChange={(e) => {
                  markDirty();
                  const next = [...focus];
                  next[idx] = { ...next[idx], completion_note: e.target.value };
                  setFocus(next);
                }}
              />
              {f.id ? (
                <EvidencePanel
                  entityKind="visit_focus_item"
                  entityId={f.id}
                  siteId={v.site_id}
                  canUpload
                />
              ) : (
                <p className="text-xs text-muted-foreground">
                  Save the draft to attach photos.
                </p>
              )}
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">Constraints</CardTitle>
          <Button size="sm" variant="outline" onClick={addConstraint}>
            Add constraint
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {constraints.length === 0 && (
            <p className="text-sm text-muted-foreground">No constraints recorded.</p>
          )}
          {constraints.map((c: any, idx: number) => (
            <div key={idx} className="border rounded-md p-3 space-y-2">
              <div className="flex justify-end">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => { markDirty(); setConstraints(constraints.filter((_: any, i: number) => i !== idx)); }}
                >
                  Remove
                </Button>
              </div>
              <select
                className="w-full border rounded-md px-3 py-2 bg-background text-sm"
                value={c.constraint_type}
                onChange={(e) => {
                  markDirty();
                  const next = [...constraints];
                  next[idx] = { ...next[idx], constraint_type: e.target.value };
                  setConstraints(next);
                }}
              >
                {(constraintTypes.data ?? []).map((t) => (
                  <option key={t.code} value={t.code}>
                    {t.label}
                  </option>
                ))}
              </select>
              <Textarea
                placeholder="Description"
                value={c.description ?? ""}
                onChange={(e) => {
                  markDirty();
                  const next = [...constraints];
                  next[idx] = { ...next[idx], description: e.target.value };
                  setConstraints(next);
                }}
              />
              <Input
                placeholder="Affected area"
                value={c.affected_area ?? ""}
                onChange={(e) => {
                  markDirty();
                  const next = [...constraints];
                  next[idx] = { ...next[idx], affected_area: e.target.value };
                  setConstraints(next);
                }}
              />
            </div>
          ))}
        </CardContent>
      </Card>

      <div className="flex flex-wrap gap-2 pt-2 sticky bottom-0 bg-background py-3 border-t">
        <Button onClick={() => saveDraft.mutate()} disabled={saveDraft.isPending} variant="outline">
          {saveDraft.isPending ? "Saving…" : "Save draft"}
        </Button>
        <Button onClick={() => submit.mutate()} disabled={submit.isPending || pendingRec > 0}>
          {submit.isPending ? "Submitting…" : "Submit for review"}
        </Button>
        {pendingRec > 0 && (
          <span className="text-xs text-amber-600 self-center">
            Resolve all rotation recommendations before submitting.
          </span>
        )}
      </div>
    </div>
  );
}

function SubmittedView({ detail }: { detail: any }) {
  const v = detail.visit;
  return (
    <div className="space-y-4">
      {v.notes && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Notes</CardTitle>
          </CardHeader>
          <CardContent className="text-sm whitespace-pre-wrap">{v.notes}</CardContent>
        </Card>
      )}
      {detail.focus_items.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Focus items</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {detail.focus_items.map((f: any) => (
              <div key={f.id} className="border rounded-md p-3 text-sm">
                <div className="font-medium">{f.focus_name_snapshot}</div>
                <div className="text-xs text-muted-foreground">{f.exact_location}</div>
                <Badge variant="secondary" className="mt-1">
                  {focusItemStatusLabel[f.status] ?? f.status}
                </Badge>
                {f.completion_note && (
                  <div className="text-xs mt-1 text-muted-foreground">{f.completion_note}</div>
                )}
                <div className="mt-2">
                  <EvidencePanel
                    entityKind="visit_focus_item"
                    entityId={f.id}
                    siteId={v.site_id}
                  />
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function ReviewSection({
  visitId,
  visit,
  detail,
}: {
  visitId: string;
  visit: any;
  detail: any;
}) {
  const { hasSiteRole, isAdmin, user } = useAuth();
  const qc = useQueryClient();
  const reviews = useQuery({
    queryKey: ["reviews", visitId],
    queryFn: () => listOpenReviewForVisit(visitId),
  });
  const canReview = isAdmin || hasSiteRole(visit.site_id, ROLES_REVIEW);
  const canSupersede = isAdmin || hasSiteRole(visit.site_id, ROLES_REOPEN);

  // Permitted user directory (display names + role codes) for this site.
  // Used for the supervisor name, team-member names, and any otherDraft owner.
  // Restricted profiles table is never queried directly.
  const directory = useQuery({
    queryKey: ["site-directory", visit.site_id],
    queryFn: () => siteUserDirectory(visit.site_id),
    enabled: !!visit.site_id,
  });
  const nameByUserId = new Map<string, string>();
  for (const e of directory.data ?? []) {
    if (e.user_id && e.display_name) nameByUserId.set(e.user_id, e.display_name);
  }

  const reviewContext = useQuery({
    queryKey: ["visit", visitId, "review-context"],
    queryFn: async () => {
      const [ratings, focusItems, constraints] = await Promise.all([
        supabase
          .from("visit_rating_lines")
          .select("*")
          .eq("cleaning_visit_id", visitId)
          .order("display_order"),
        supabase
          .from("visit_focus_items")
          .select("*")
          .eq("cleaning_visit_id", visitId)
          .order("display_order"),
        supabase
          .from("visit_constraints")
          .select("id, description, constraint_type, affected_area, constraint_types(label)")
          .eq("cleaning_visit_id", visitId),
      ]);
      if (ratings.error) throw ratings.error;
      if (focusItems.error) throw focusItems.error;
      if (constraints.error) throw constraints.error;
      return {
        ratings: ratings.data ?? [],
        focusItems: focusItems.data ?? [],
        constraints: constraints.data ?? [],
      };
    },
    enabled:
      visit.status === "submitted_for_review" ||
      visit.status === "reviewed" ||
      visit.status === "closed",
  });

  const startReview = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.rpc("rpc_start_review_draft", {
        p_visit_id: visitId,
        p_review_type: "dm_lightweight",
      });
      if (error) throw error;
      return data as string;
    },
    onSuccess: () => {
      toast.success("Review started");
      reviews.refetch();
    },
    onError: (e: any) => toast.error(e.message),
  });

  if (
    visit.status !== "submitted_for_review" &&
    visit.status !== "reviewed" &&
    visit.status !== "closed"
  )
    return null;

  // Ownership-only edit: an in-progress draft belongs to its reviewer alone.
  // Admins do NOT silently take over — there is no audited takeover RPC yet,
  // so any non-owner sees the draft read-only as "in progress by [name]".
  const myDraft = reviews.data?.find(
    (r: any) => r.status === "draft" && r.reviewer_id === user?.id,
  );
  const otherDraft = reviews.data?.find(
    (r: any) => r.status === "draft" && r.reviewer_id !== user?.id,
  );
  const submittedReviews = reviews.data?.filter((r: any) => r.status !== "draft") ?? [];

  // Id → label maps for rendering submitted scores read-only.
  const lineLabelById = new Map<string, string>();
  for (const r of reviewContext.data?.ratings ?? [])
    lineLabelById.set(r.id, r.label_snapshot);
  const focusLabelById = new Map<string, string>();
  for (const f of reviewContext.data?.focusItems ?? [])
    focusLabelById.set(f.id, f.focus_name_snapshot);

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-base">Next-morning review</CardTitle>
        {canReview && !myDraft && !otherDraft && visit.status === "submitted_for_review" && (
          <Button size="sm" onClick={() => startReview.mutate()}>
            Start review
          </Button>
        )}
      </CardHeader>
      <CardContent className="space-y-3">
        <ReviewerContextPanel detail={detail} nameByUserId={nameByUserId} />

        {otherDraft && (
          <div className="text-sm border rounded-md p-3 bg-muted/30">
            Review currently in progress by{" "}
            <span className="font-medium">
              {(otherDraft.reviewer_id && nameByUserId.get(otherDraft.reviewer_id)) ??
                "another reviewer"}
            </span>
            .
          </div>
        )}
        {submittedReviews.map((r: any) => (
          <div key={r.id} className="border rounded-md p-3 text-sm">
            <div className="flex items-center justify-between">
              <div className="font-medium">
                {reviewStatusLabel[r.status] ?? r.status} ·{" "}
                {(r.reviewer_id && nameByUserId.get(r.reviewer_id)) ?? "reviewer"}
              </div>
              <span className="text-xs text-muted-foreground">
                {r.submitted_at && new Date(r.submitted_at).toLocaleString()}
              </span>
            </div>
            {r.general_comment && <p className="mt-1 text-xs">{r.general_comment}</p>}
            <SubmittedReviewScores
              reviewId={r.id}
              lineLabels={lineLabelById}
              focusLabels={focusLabelById}
            />
            {canSupersede && r.status === "submitted" && !myDraft && !otherDraft && (
              <SupersedeControl reviewId={r.id} onCreated={() => reviews.refetch()} />
            )}
          </div>
        ))}
        {myDraft && canReview && (
          <ReviewDraftForm
            review={myDraft}
            ratings={reviewContext.data?.ratings ?? []}
            focusItems={reviewContext.data?.focusItems ?? []}
            constraints={reviewContext.data?.constraints ?? []}
            onSubmitted={() => {
              qc.invalidateQueries({ queryKey: ["reviews", visitId] });
              qc.invalidateQueries({ queryKey: ["visit", visitId] });
              qc.invalidateQueries({ queryKey: ["actions"] });
              qc.invalidateQueries({ queryKey: ["dashboard"] });
            }}
          />
        )}
      </CardContent>
    </Card>
  );
}

function ReviewerContextPanel({
  detail,
  nameByUserId,
}: {
  detail: any;
  nameByUserId: Map<string, string>;
}) {
  const v = detail.visit;
  const tpl = v.visit_templates;
  const rot = v.rotation_programmes;
  const supervisorName = v.supervisor_id ? nameByUserId.get(v.supervisor_id) : null;

  const recsByStatus = (status: string) =>
    (detail.recommendations as any[]).filter((r) => r.recommendation_status === status);
  const focusByStatus = (statuses: string[]) =>
    (detail.focus_items as any[]).filter((f) => statuses.includes(f.status));
  const scopeBy = (t: string) =>
    (detail.scope_items as any[]).filter((s) => s.item_type === t);

  const Section = ({
    title,
    count,
    children,
    defaultOpen = false,
  }: {
    title: string;
    count?: number;
    children: ReactNode;
    defaultOpen?: boolean;
  }) => (
    <details className="border rounded-md p-2" open={defaultOpen}>
      <summary className="cursor-pointer text-sm font-medium select-none">
        {title}
        {typeof count === "number" && count > 0 && (
          <Badge variant="secondary" className="ml-2">
            {count}
          </Badge>
        )}
      </summary>
      <div className="pt-2 text-sm space-y-2">{children}</div>
    </details>
  );

  return (
    <div className="space-y-2">
      <div className="border rounded-md p-3 text-sm space-y-1 bg-muted/20">
        <div className="font-medium">{tpl?.name ?? "Visit"}</div>
        <div className="text-xs text-muted-foreground">
          {v.visit_date}
          {tpl?.expected_weekday !== undefined && tpl?.expected_weekday !== null
            ? ` · weekday ${tpl.expected_weekday}`
            : ""}
          {rot?.name ? ` · ${rot.name}` : ""}
          {v.recommended_rotation_week
            ? ` · planned wk ${v.recommended_rotation_week}`
            : ""}
          {v.rotation_week_override
            ? ` · actual wk ${v.rotation_week_override}`
            : ""}
        </div>
        <div className="text-xs text-muted-foreground">
          Supervisor:{" "}
          <span className="font-medium text-foreground">
            {supervisorName ?? "—"}
          </span>
          {v.headcount !== null && v.headcount !== undefined
            ? ` · team of ${v.headcount}`
            : ""}
          {v.weather ? ` · ${v.weather}` : ""}
        </div>
        {v.rotation_week_override_reason && (
          <div className="text-xs">
            <span className="text-muted-foreground">Rotation override: </span>
            {v.rotation_week_override_reason}
          </div>
        )}
        {v.weekday_override_reason && (
          <div className="text-xs">
            <span className="text-muted-foreground">Weekday override: </span>
            {v.weekday_override_reason}
          </div>
        )}
      </div>

      <Section title="Supervisor handover note" defaultOpen={!!v.notes}>
        {v.notes ? (
          <p className="whitespace-pre-wrap">{v.notes}</p>
        ) : (
          <p className="text-muted-foreground">No handover note recorded.</p>
        )}
      </Section>

      {detail.scope_items.length > 0 && (
        <Section title="Scheduled scope" count={detail.scope_items.length}>
          {(["primary_area", "base_task", "secondary_maintenance", "limitation"] as const).map(
            (t) => {
              const items = scopeBy(t);
              if (!items.length) return null;
              const label =
                t === "primary_area"
                  ? "Primary areas"
                  : t === "base_task"
                    ? "Base tasks"
                    : t === "secondary_maintenance"
                      ? "Secondary maintenance"
                      : "Limitations";
              return (
                <div key={t}>
                  <div className="text-xs uppercase tracking-wide text-muted-foreground">
                    {label}
                  </div>
                  <ul className="list-disc pl-5 space-y-0.5">
                    {items.map((i: any) => (
                      <li key={i.id}>{i.label_snapshot}</li>
                    ))}
                  </ul>
                </div>
              );
            },
          )}
        </Section>
      )}

      {detail.recommendations.length > 0 && (
        <Section
          title="Planned rotation recommendations"
          count={detail.recommendations.length}
        >
          {(["selected", "skipped", "inaccessible", "not_applicable"] as const).map((s) => {
            const items = recsByStatus(s);
            if (!items.length) return null;
            return (
              <div key={s}>
                <div className="text-xs uppercase tracking-wide text-muted-foreground">
                  {recommendationStatusLabel[s]}
                </div>
                <ul className="list-disc pl-5 space-y-0.5">
                  {items.map((r: any) => (
                    <li key={r.id}>
                      {r.focus_label_snapshot}
                      {r.resolution_reason ? (
                        <span className="text-muted-foreground">
                          {" "}
                          — {r.resolution_reason}
                        </span>
                      ) : null}
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </Section>
      )}

      {detail.focus_items.length > 0 && (
        <Section
          title="Actual focus items & completion"
          count={detail.focus_items.length}
          defaultOpen
        >
          {(detail.focus_items as any[]).map((f) => (
            <div key={f.id} className="border rounded-md p-2">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <div className="font-medium">{f.focus_name_snapshot}</div>
                  {f.exact_location && (
                    <div className="text-xs text-muted-foreground">
                      {f.exact_location}
                    </div>
                  )}
                </div>
                <Badge variant="secondary">
                  {focusItemStatusLabel[f.status] ?? f.status}
                </Badge>
              </div>
              {f.completion_note && (
                <p className="text-xs mt-1 whitespace-pre-wrap">{f.completion_note}</p>
              )}
              <div className="mt-2">
                <EvidencePanel
                  entityKind="visit_focus_item"
                  entityId={f.id}
                  siteId={v.site_id}
                />
              </div>
            </div>
          ))}
          {focusByStatus(["inaccessible", "deferred", "not_completed"]).length > 0 && (
            <p className="text-xs text-muted-foreground">
              Includes inaccessible, deferred and not-completed items above.
            </p>
          )}
        </Section>
      )}

      {detail.constraints.length > 0 && (
        <Section title="Visit constraints" count={detail.constraints.length} defaultOpen>
          {(detail.constraints as any[]).map((c) => (
            <div key={c.id} className="border rounded-md p-2">
              <div className="text-xs uppercase tracking-wide text-muted-foreground">
                {c.constraint_types?.label ?? c.constraint_type}
                {c.affected_area ? ` · ${c.affected_area}` : ""}
              </div>
              <p className="text-sm whitespace-pre-wrap">{c.description}</p>
            </div>
          ))}
        </Section>
      )}

      {detail.team_members.length > 0 && (
        <Section title="Team on visit" count={detail.team_members.length}>
          <ul className="list-disc pl-5 space-y-0.5">
            {(detail.team_members as any[]).map((m) => {
              const name = m.user_id ? nameByUserId.get(m.user_id) : null;
              const display = name ?? m.full_name ?? "—";
              return (
                <li key={m.id}>
                  {display}
                  {m.role_on_visit ? (
                    <span className="text-muted-foreground"> — {m.role_on_visit}</span>
                  ) : null}
                </li>
              );
            })}
          </ul>
        </Section>
      )}
    </div>
  );
}

type LineScoreState = {
  rating: number | null;
  is_na: boolean;
  na_reason: string;
  comment: string;
  scope_classification: string;
  issue_type_code: string;
  urgent_hs_flag: boolean;
};

const emptyScore: LineScoreState = {
  rating: null,
  is_na: false,
  na_reason: "",
  comment: "",
  scope_classification: "",
  issue_type_code: "",
  urgent_hs_flag: false,
};

// Urgent source picker: one of these three (or null), enforced by the
// review-submit RPC. The selected source is the foreign key the resulting
// urgent action will be wired to.
type UrgentSource =
  | { kind: "line"; id: string }
  | { kind: "focus"; id: string }
  | { kind: "constraint"; id: string }
  | null;

function encodeUrgentSource(s: UrgentSource): string {
  if (!s) return "";
  return `${s.kind}:${s.id}`;
}
function decodeUrgentSource(v: string): UrgentSource {
  if (!v) return null;
  const [kind, id] = v.split(":");
  if (kind !== "line" && kind !== "focus" && kind !== "constraint") return null;
  if (!id) return null;
  return { kind, id } as UrgentSource;
}

function ReviewDraftForm({
  review,
  ratings,
  focusItems,
  constraints,
  onSubmitted,
}: {
  review: any;
  ratings: any[];
  focusItems: any[];
  constraints: any[];
  onSubmitted: () => void;
}) {
  const [comment, setComment] = useState(review.general_comment ?? "");
  const [urgent, setUrgent] = useState(!!review.urgent_hs_flag);
  const [urgentSource, setUrgentSource] = useState<UrgentSource>(null);
  const [scores, setScores] = useState<Record<string, LineScoreState>>({});
  const [focusScores, setFocusScores] = useState<Record<string, LineScoreState>>({});
  const [version, setVersion] = useState<number>(review.version_no);
  const [hydrated, setHydrated] = useState(false);
  const [isDirty, setIsDirty] = useState(false);

  // C6: Rehydrate the draft on mount. Keyed off review.id + version_no so a
  // server-side version bump (e.g. after our own save) does not stomp dirty
  // edits; we only re-seed from server data when nothing local has changed.
  useEffect(() => {
    let cancelled = false;
    void getReviewDetail(review.id).then((detail) => {
      if (cancelled) return;
      const nextLines: Record<string, LineScoreState> = {};
      for (const ls of detail.line_scores as any[]) {
        nextLines[ls.visit_rating_line_id] = {
          rating: ls.rating ?? null,
          is_na: !!ls.is_na,
          na_reason: ls.na_reason ?? "",
          comment: ls.comment ?? "",
          scope_classification: ls.scope_classification ?? "",
          issue_type_code: ls.issue_type_code ?? "",
          urgent_hs_flag: !!ls.urgent_hs_flag,
        };
      }
      const nextFocus: Record<string, LineScoreState> = {};
      for (const fs of detail.focus_scores as any[]) {
        nextFocus[fs.visit_focus_item_id] = {
          rating: fs.rating ?? null,
          is_na: !!fs.is_na,
          na_reason: fs.na_reason ?? "",
          comment: fs.comment ?? "",
          scope_classification: fs.scope_classification ?? "",
          issue_type_code: fs.issue_type_code ?? "",
          urgent_hs_flag: !!fs.urgent_hs_flag,
        };
      }
      // Recover urgent source from server state (review + score flags).
      let src: UrgentSource = null;
      const r = detail.review as any;
      if (r?.urgent_source_constraint_id) {
        src = { kind: "constraint", id: r.urgent_source_constraint_id };
      } else {
        const urgLine = (detail.line_scores as any[]).find((x) => x.urgent_hs_flag);
        if (urgLine) src = { kind: "line", id: urgLine.visit_rating_line_id };
        else {
          const urgFocus = (detail.focus_scores as any[]).find((x) => x.urgent_hs_flag);
          if (urgFocus) src = { kind: "focus", id: urgFocus.visit_focus_item_id };
        }
      }
      // Only seed when not dirty (H11): never overwrite an in-progress edit.
      if (!isDirty) {
        setScores(nextLines);
        setFocusScores(nextFocus);
        setUrgentSource(src);
      }
      setHydrated(true);
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [review.id, review.version_no]);

  const setScore = (lineId: string, patch: Partial<LineScoreState>) => {
    setIsDirty(true);
    setScores((prev) => ({
      ...prev,
      [lineId]: { ...(prev[lineId] ?? emptyScore), ...patch },
    }));
  };
  const setFocusScore = (focusId: string, patch: Partial<LineScoreState>) => {
    setIsDirty(true);
    setFocusScores((prev) => ({
      ...prev,
      [focusId]: { ...(prev[focusId] ?? emptyScore), ...patch },
    }));
  };

  const issueTypes = useQuery({
    queryKey: ["issue_types"],
    queryFn: async () => {
      const { data } = await supabase
        .from("issue_types")
        .select("code, label, is_active")
        .eq("is_active", true)
        .order("sort_order");
      return data ?? [];
    },
  });

  // Build payload + client-side validation (H3 mirrors server completeness rules).
  const buildPayload = (forSubmit: boolean) => {
    // Determine effective urgent flags. Exactly one source if urgent on.
    const urgLineId = urgent && urgentSource?.kind === "line" ? urgentSource.id : null;
    const urgFocusId = urgent && urgentSource?.kind === "focus" ? urgentSource.id : null;
    const urgConstraintId = urgent && urgentSource?.kind === "constraint" ? urgentSource.id : null;

    if (forSubmit && urgent && !urgentSource) {
      throw new Error("Urgent H&S: pick a rating line, focus item, or constraint as the source.");
    }

    const lineScores: any[] = [];
    for (const r of ratings) {
      const sBase = scores[r.id];
      const isUrg = urgLineId === r.id;
      const s: LineScoreState = { ...(sBase ?? emptyScore), urgent_hs_flag: isUrg };

      if (forSubmit) {
        if (!s.is_na && s.rating === null) {
          throw new Error(`Line "${r.label_snapshot}" needs a 1–5 rating or N/A`);
        }
        if (s.is_na && !s.na_reason.trim()) {
          throw new Error(`Line "${r.label_snapshot}" marked N/A requires a reason`);
        }
        if (!s.is_na && s.rating !== null && s.rating <= 2 && !s.comment.trim()) {
          throw new Error(`Line "${r.label_snapshot}" rated ${s.rating} requires a comment`);
        }
        if (isUrg && (s.is_na || (s.rating ?? 9) > 2)) {
          throw new Error(
            `Urgent H&S source "${r.label_snapshot}" must be rated 1 or 2 (failing).`,
          );
        }
      } else if (!sBase && !isUrg) {
        continue;
      }
      lineScores.push({
        visit_rating_line_id: r.id,
        rating: s.is_na ? null : s.rating,
        is_na: s.is_na,
        na_reason: s.is_na ? s.na_reason : null,
        comment: s.comment || null,
        scope_classification: s.scope_classification || null,
        issue_type_code: s.issue_type_code || null,
        urgent_hs_flag: isUrg,
      });
    }

    const fScores: any[] = [];
    for (const f of focusItems) {
      const sBase = focusScores[f.id];
      const isUrg = urgFocusId === f.id;
      const s: LineScoreState = { ...(sBase ?? emptyScore), urgent_hs_flag: isUrg };

      if (forSubmit) {
        if (!s.is_na && s.rating === null) {
          throw new Error(`Focus item "${f.focus_name_snapshot}" needs a 1–5 rating or N/A`);
        }
        if (s.is_na && !s.na_reason.trim()) {
          throw new Error(`Focus item "${f.focus_name_snapshot}" marked N/A requires a reason`);
        }
        if (!s.is_na && s.rating !== null && s.rating <= 2 && !s.comment.trim()) {
          throw new Error(`Focus item "${f.focus_name_snapshot}" rated ${s.rating} requires a comment`);
        }
        if (isUrg && (s.is_na || (s.rating ?? 9) > 2)) {
          throw new Error(
            `Urgent H&S source focus "${f.focus_name_snapshot}" must be rated 1 or 2 (failing).`,
          );
        }
      } else if (!sBase && !isUrg) {
        continue;
      }
      fScores.push({
        visit_focus_item_id: f.id,
        rating: s.is_na ? null : s.rating,
        is_na: s.is_na,
        na_reason: s.is_na ? s.na_reason : null,
        comment: s.comment || null,
        scope_classification: s.scope_classification || null,
        issue_type_code: s.issue_type_code || null,
        urgent_hs_flag: isUrg,
      });
    }

    return {
      general_comment: comment,
      urgent_hs_flag: urgent,
      urgent_hs_detail: null,
      urgent_source_constraint_id: urgConstraintId,
      line_scores: lineScores,
      focus_scores: fScores,
    };
  };

  const save = useMutation({
    mutationFn: async () => {
      const payload = buildPayload(false);
      const { data, error } = await supabase.rpc("rpc_save_review_draft", {
        p_review_id: review.id,
        p_expected_version: version,
        p_payload: payload,
      });
      if (error) throw error;
      return data as number;
    },
    onSuccess: (v) => {
      toast.success("Review saved");
      setVersion(v);
      setIsDirty(false);
    },
    onError: (e: any) => toast.error(e.message),
  });

  const submit = useMutation({
    mutationFn: async () => {
      const payload = buildPayload(true);
      const { data: vNew, error: e1 } = await supabase.rpc("rpc_save_review_draft", {
        p_review_id: review.id,
        p_expected_version: version,
        p_payload: payload,
      });
      if (e1) throw e1;
      // A superseding draft (supersedes_review_id set) must go through the
      // dedicated RPC, which also marks the original review superseded.
      if (review.supersedes_review_id) {
        const { error: e2 } = await supabase.rpc("rpc_submit_superseding_review", {
          p_new_review_id: review.id,
          p_expected_version: vNew as number,
        });
        if (e2) throw e2;
      } else {
        const { error: e2 } = await supabase.rpc("rpc_submit_review", {
          p_review_id: review.id,
          p_expected_version: vNew as number,
        });
        if (e2) throw e2;
      }
    },
    onSuccess: () => {
      toast.success("Review submitted");
      setIsDirty(false);
      onSubmitted();
    },
    onError: (e: any) => toast.error(e.message),
  });

  const renderScoreRow = (
    label: string,
    s: LineScoreState,
    onSet: (patch: Partial<LineScoreState>) => void,
  ) => {
    const needsComment = !s.is_na && s.rating !== null && s.rating <= 2;
    return (
      <div className="space-y-2">
        <div className="text-sm font-medium">{label}</div>
        <div className="flex flex-wrap gap-2">
          {[1, 2, 3, 4, 5].map((n) => (
            <Button
              key={n}
              size="sm"
              variant={!s.is_na && s.rating === n ? "default" : "outline"}
              onClick={() => onSet({ rating: n, is_na: false })}
              title={ratingLabel[n]}
            >
              {n}
            </Button>
          ))}
          <Button
            size="sm"
            variant={s.is_na ? "default" : "outline"}
            onClick={() => onSet({ rating: null, is_na: true })}
          >
            N/A
          </Button>
        </div>
        {s.is_na && (
          <Input
            placeholder="Reason for N/A (required)"
            value={s.na_reason}
            onChange={(e) => onSet({ na_reason: e.target.value })}
          />
        )}
        {(needsComment || s.rating === 3) && (
          <Textarea
            placeholder={needsComment ? "Comment (required for ratings 1–2)" : "Comment (optional)"}
            value={s.comment}
            onChange={(e) => onSet({ comment: e.target.value })}
          />
        )}
        {needsComment && (
          <div className="grid grid-cols-2 gap-2">
            <select
              className="border rounded-md px-2 py-1.5 bg-background text-sm"
              value={s.scope_classification}
              onChange={(e) => onSet({ scope_classification: e.target.value })}
            >
              <option value="">Scope…</option>
              {Object.entries(scopeClassificationLabel).map(([code, lab]) => (
                <option key={code} value={code}>
                  {lab}
                </option>
              ))}
            </select>
            <select
              className="border rounded-md px-2 py-1.5 bg-background text-sm"
              value={s.issue_type_code}
              onChange={(e) => onSet({ issue_type_code: e.target.value })}
            >
              <option value="">Issue type…</option>
              {(issueTypes.data ?? []).map((t: any) => (
                <option key={t.code} value={t.code}>
                  {t.label}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="border rounded-md p-3 space-y-3">
      {review.supersedes_review_id && (
        <div className="rounded-md border border-amber-500 bg-amber-50 p-2 text-xs dark:bg-amber-950/30">
          This is a <span className="font-medium">superseding review</span>. Submitting
          it replaces the previous submitted review (kept on record) and marks it
          superseded.
        </div>
      )}
      <div className="space-y-1">
        <Label>General comment</Label>
        <Textarea
          value={comment}
          onChange={(e) => {
            setComment(e.target.value);
            setIsDirty(true);
          }}
        />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input
          type="checkbox"
          checked={urgent}
          onChange={(e) => {
            setUrgent(e.target.checked);
            setIsDirty(true);
            if (!e.target.checked) setUrgentSource(null);
          }}
        />
        Urgent H&S issue
      </label>
      {urgent && (
        <div className="space-y-1">
          <Label className="text-xs">Urgent H&S source (required)</Label>
          <select
            className="w-full border rounded-md px-2 py-1.5 bg-background text-sm"
            value={encodeUrgentSource(urgentSource)}
            onChange={(e) => {
              setUrgentSource(decodeUrgentSource(e.target.value));
              setIsDirty(true);
            }}
          >
            <option value="">Select source…</option>
            {ratings.length > 0 && (
              <optgroup label="Rating lines">
                {ratings.map((r) => (
                  <option key={r.id} value={`line:${r.id}`}>
                    {r.label_snapshot}
                  </option>
                ))}
              </optgroup>
            )}
            {focusItems.length > 0 && (
              <optgroup label="Focus items">
                {focusItems.map((f) => (
                  <option key={f.id} value={`focus:${f.id}`}>
                    {f.focus_name_snapshot}
                    {f.exact_location ? ` — ${f.exact_location}` : ""}
                  </option>
                ))}
              </optgroup>
            )}
            {constraints.length > 0 && (
              <optgroup label="Visit constraints">
                {constraints.map((c) => (
                  <option key={c.id} value={`constraint:${c.id}`}>
                    {c.description}
                  </option>
                ))}
              </optgroup>
            )}
          </select>
          <p className="text-xs text-muted-foreground">
            A rating-line or focus-item source must be rated 1 or 2 (failing). The resulting
            action will reference the selected source.
          </p>
        </div>
      )}

      <div className="space-y-2">
        <h4 className="font-medium text-sm">Rating-line scores (1–5 or N/A)</h4>
        {!hydrated && <p className="text-xs text-muted-foreground">Loading existing scores…</p>}
        {ratings.map((r) => {
          const s = scores[r.id] ?? emptyScore;
          return (
            <div key={r.id} className="border rounded-md p-2">
              {renderScoreRow(r.label_snapshot, s, (p) => setScore(r.id, p))}
            </div>
          );
        })}
      </div>

      {focusItems.length > 0 && (
        <div className="space-y-2">
          <h4 className="font-medium text-sm">Focus-item scores (1–5 or N/A)</h4>
          {focusItems.map((f) => {
            const s = focusScores[f.id] ?? emptyScore;
            const title = f.exact_location
              ? `${f.focus_name_snapshot} — ${f.exact_location}`
              : f.focus_name_snapshot;
            return (
              <div key={f.id} className="border rounded-md p-2">
                {renderScoreRow(title, s, (p) => setFocusScore(f.id, p))}
              </div>
            );
          })}
        </div>
      )}

      <div className="flex gap-2 pt-2">
        <Button
          variant="outline"
          onClick={() => save.mutate()}
          disabled={save.isPending || !hydrated}
        >
          Save draft
        </Button>
        <Button
          onClick={() => submit.mutate()}
          disabled={submit.isPending || !hydrated}
        >
          Submit review
        </Button>
      </div>
    </div>
  );
}


function ReopenBlock({ visitId, onReopened }: { visitId: string; onReopened: () => void }) {
  const { isAdmin } = useAuth();
  const [reason, setReason] = useState("");
  const reviews = useQuery({
    queryKey: ["reviews", visitId],
    queryFn: () => listOpenReviewForVisit(visitId),
  });
  // A plain reopen is rejected by the server while any draft review is open.
  const activeDraft = reviews.data?.find((r: any) => r.status === "draft");

  const reopen = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("rpc_reopen_visit", {
        p_visit_id: visitId,
        p_reason: reason,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Visit reopened");
      setReason("");
      onReopened();
    },
    onError: (e: any) => toast.error(e.message),
  });

  const reopenCancel = useMutation({
    mutationFn: async () => {
      if (!activeDraft) return;
      const { error } = await supabase.rpc("rpc_admin_reopen_visit_with_cancel", {
        p_visit_id: visitId,
        p_reason: reason,
        p_cancel_draft_review_id: activeDraft.id,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Draft review cancelled and visit reopened");
      setReason("");
      onReopened();
    },
    onError: (e: any) => toast.error(e.message),
  });

  return (
    <details className="border rounded-md p-3 text-sm">
      <summary className="cursor-pointer font-medium">Reopen visit</summary>
      <div className="space-y-2 mt-2">
        <Textarea
          placeholder="Reason (required)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        {activeDraft ? (
          isAdmin ? (
            <div className="space-y-2">
              <p className="text-xs text-amber-600">
                An in-progress review draft is blocking a normal reopen. As an admin you
                can cancel that draft and reopen in one step — the draft and its scores
                are discarded.
              </p>
              <Button
                variant="destructive"
                size="sm"
                disabled={!reason || reopenCancel.isPending}
                onClick={() => reopenCancel.mutate()}
              >
                Cancel draft review &amp; reopen
              </Button>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">
              An in-progress review must be cancelled by a TMS admin before this visit
              can be reopened.
            </p>
          )
        ) : (
          <Button
            variant="destructive"
            size="sm"
            disabled={!reason || reopen.isPending}
            onClick={() => reopen.mutate()}
          >
            Reopen
          </Button>
        )}
      </div>
    </details>
  );
}

// Read-only colour band for a submitted score row (mirrors the DB-generated
// rating_band_display: 1–2 red, 3 amber, 4–5 green, N/A neutral).
function bandFor(s: any): { label: string; cls: string } {
  if (s.is_na) return { label: "N/A", cls: "bg-muted text-muted-foreground" };
  const r = s.rating as number | null;
  if (r === null) return { label: "—", cls: "bg-muted text-muted-foreground" };
  if (r <= 2)
    return {
      label: String(r),
      cls: "bg-red-100 text-red-800 dark:bg-red-950/50 dark:text-red-300",
    };
  if (r === 3)
    return {
      label: String(r),
      cls: "bg-amber-100 text-amber-800 dark:bg-amber-950/50 dark:text-amber-300",
    };
  return {
    label: String(r),
    cls: "bg-green-100 text-green-800 dark:bg-green-950/50 dark:text-green-300",
  };
}

function SubmittedReviewScores({
  reviewId,
  lineLabels,
  focusLabels,
}: {
  reviewId: string;
  lineLabels: Map<string, string>;
  focusLabels: Map<string, string>;
}) {
  const detail = useQuery({
    queryKey: ["review-detail", reviewId],
    queryFn: () => getReviewDetail(reviewId),
  });
  if (detail.isLoading)
    return <p className="mt-2 text-xs text-muted-foreground">Loading scores…</p>;
  const lineScores = detail.data?.line_scores ?? [];
  const focusScores = detail.data?.focus_scores ?? [];
  if (lineScores.length === 0 && focusScores.length === 0)
    return <p className="mt-2 text-xs text-muted-foreground">No scores recorded.</p>;

  const Row = ({ label, s }: { label: string; s: any }) => {
    const band = bandFor(s);
    return (
      <div className="flex items-start gap-2 py-1 text-xs">
        <span
          className={`inline-flex h-5 min-w-5 items-center justify-center rounded px-1 font-medium ${band.cls}`}
        >
          {band.label}
        </span>
        <div className="min-w-0">
          <div className="font-medium">{label}</div>
          {s.is_na && s.na_reason && (
            <div className="text-muted-foreground">N/A — {s.na_reason}</div>
          )}
          {s.comment && <div className="text-muted-foreground">{s.comment}</div>}
          {s.urgent_hs_flag && (
            <Badge variant="destructive" className="mt-0.5">
              Urgent H&S
            </Badge>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="mt-2 space-y-2">
      {lineScores.length > 0 && (
        <div>
          <div className="mb-1 text-xs uppercase tracking-wide text-muted-foreground">
            Rating lines
          </div>
          {lineScores.map((s: any) => (
            <Row
              key={s.id}
              label={lineLabels.get(s.visit_rating_line_id) ?? "Rating line"}
              s={s}
            />
          ))}
        </div>
      )}
      {focusScores.length > 0 && (
        <div>
          <div className="mb-1 text-xs uppercase tracking-wide text-muted-foreground">
            Focus items
          </div>
          {focusScores.map((s: any) => (
            <Row
              key={s.id}
              label={focusLabels.get(s.visit_focus_item_id) ?? "Focus item"}
              s={s}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// Ops/GM/Admin control to start a superseding review off a submitted one.
// The new draft is owned by the caller and appears in the review section for
// them to edit and submit (via rpc_submit_superseding_review).
function SupersedeControl({
  reviewId,
  onCreated,
}: {
  reviewId: string;
  onCreated: () => void;
}) {
  const [reason, setReason] = useState("");
  const mut = useMutation({
    mutationFn: async () => {
      const { error } = await supabase.rpc("rpc_create_superseding_review", {
        p_original_review_id: reviewId,
        p_reason: reason,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Superseding review started — edit and submit it below.");
      setReason("");
      onCreated();
    },
    onError: (e: any) => toast.error(e.message),
  });
  return (
    <details className="mt-2 text-xs">
      <summary className="cursor-pointer text-muted-foreground">
        Supersede this review
      </summary>
      <div className="mt-2 space-y-2">
        <Textarea
          placeholder="Reason for superseding (required)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
        />
        <Button
          size="sm"
          variant="outline"
          disabled={!reason || mut.isPending}
          onClick={() => mut.mutate()}
        >
          Create superseding review
        </Button>
      </div>
    </details>
  );
}
