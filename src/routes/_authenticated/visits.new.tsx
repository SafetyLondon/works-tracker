import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState, useMemo } from "react";
import { useQuery, useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { listSites, listTemplates, listRotationProgrammes } from "@/lib/tms/queries";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-context";
import { ROLES_VISIT_OVERRIDE } from "@/lib/labels";

// Europe/London local date (avoids UTC-rollover bug near midnight/DST).
function todayInLondon(): string {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/London",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return fmt.format(new Date()); // en-CA yields YYYY-MM-DD
}

export const Route = createFileRoute("/_authenticated/visits/new")({
  component: NewVisit,
});

function NewVisit() {
  const navigate = useNavigate();
  const { hasSiteRole, isAdmin } = useAuth();
  const sites = useQuery({ queryKey: ["sites"], queryFn: listSites });

  const [siteId, setSiteId] = useState<string>("");
  const [templateId, setTemplateId] = useState<string>("");
  const [visitDate, setVisitDate] = useState<string>(todayInLondon());
  const [weekdayReason, setWeekdayReason] = useState("");
  const [overrideWeek, setOverrideWeek] = useState<string>("");
  const [overrideReason, setOverrideReason] = useState("");

  const templates = useQuery({
    queryKey: ["templates", siteId],
    queryFn: () => listTemplates(siteId),
    enabled: !!siteId,
  });
  const programmes = useQuery({
    queryKey: ["programmes", siteId],
    queryFn: () => listRotationProgrammes(siteId),
    enabled: !!siteId,
  });

  const selectedTemplate = templates.data?.find((t) => t.id === templateId);
  const programmeForTemplate = programmes.data?.find((p) => p.visit_template_id === templateId);

  const visitWeekday = useMemo(() => {
    if (!visitDate) return null;
    return new Date(visitDate + "T00:00:00").getDay();
  }, [visitDate]);

  const weekdayMismatch =
    selectedTemplate?.expected_weekday != null &&
    visitWeekday != null &&
    selectedTemplate.expected_weekday !== visitWeekday;

  const canOverride = isAdmin || hasSiteRole(siteId, ROLES_VISIT_OVERRIDE);

  const create = useMutation({
    mutationFn: async () => {
      const args: any = {
        p_site_id: siteId,
        p_visit_template_id: templateId,
        p_visit_date: visitDate,
        p_rotation_programme_id: programmeForTemplate?.id ?? null,
        p_rotation_week_override: overrideWeek ? parseInt(overrideWeek, 10) : null,
        p_rotation_week_override_reason: overrideWeek ? overrideReason : null,
        p_weekday_override_reason: weekdayMismatch ? weekdayReason : null,
      };
      const { data, error } = await supabase.rpc(
        "rpc_create_cleaning_visit_from_template",
        args,
      );
      if (error) throw error;
      // RPC now returns jsonb { visit_id, created, existing_status? }
      return data as unknown as { visit_id: string; created: boolean; existing_status?: string };
    },
    onSuccess: (res) => {
      if (res.created) {
        toast.success("Visit created");
      } else {
        toast.message(`Visit already exists (${res.existing_status ?? "—"}). Opening it.`);
      }
      navigate({ to: "/visits/$visitId", params: { visitId: res.visit_id } });
    },
    onError: (e: any) => toast.error(e.message),
  });

  return (
    <div className="space-y-4 max-w-xl">
      <h1 className="text-2xl font-semibold">Create cleaning visit</h1>

      <div className="space-y-1.5">
        <Label>Site</Label>
        <select
          className="w-full border rounded-md px-3 py-2 bg-background"
          value={siteId}
          onChange={(e) => {
            setSiteId(e.target.value);
            setTemplateId("");
          }}
        >
          <option value="">Select site…</option>
          {(sites.data ?? []).map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </div>

      <div className="space-y-1.5">
        <Label>Template</Label>
        <select
          className="w-full border rounded-md px-3 py-2 bg-background"
          value={templateId}
          onChange={(e) => setTemplateId(e.target.value)}
          disabled={!siteId}
        >
          <option value="">Select template…</option>
          {(templates.data ?? []).map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>
        {selectedTemplate?.display_summary && (
          <p className="text-xs text-muted-foreground">{selectedTemplate.display_summary}</p>
        )}
      </div>

      <div className="space-y-1.5">
        <Label>Visit date</Label>
        <Input type="date" value={visitDate} onChange={(e) => setVisitDate(e.target.value)} />
        {weekdayMismatch && (
          <div className="rounded-md border border-amber-500 bg-amber-50 dark:bg-amber-950/30 p-2 text-xs space-y-1">
            <div>
              This template normally runs on weekday {selectedTemplate?.expected_weekday}; selected
              date is weekday {visitWeekday}.
            </div>
            {canOverride ? (
              <Textarea
                placeholder="Reason for off-schedule visit (required)"
                value={weekdayReason}
                onChange={(e) => setWeekdayReason(e.target.value)}
              />
            ) : (
              <div className="text-amber-700 dark:text-amber-300">
                Only a supervisor / admin can run this template off-schedule.
              </div>
            )}
          </div>
        )}
      </div>

      {programmeForTemplate && (
        <details className="border rounded-md p-3 text-sm">
          <summary className="cursor-pointer font-medium">
            Rotation week override (optional)
          </summary>
          <div className="space-y-2 mt-2">
            <Input
              type="number"
              min={1}
              max={programmeForTemplate.cycle_length_weeks}
              placeholder={`1–${programmeForTemplate.cycle_length_weeks}`}
              value={overrideWeek}
              onChange={(e) => setOverrideWeek(e.target.value)}
            />
            {overrideWeek && (
              <Textarea
                placeholder="Reason for week override (required)"
                value={overrideReason}
                onChange={(e) => setOverrideReason(e.target.value)}
              />
            )}
          </div>
        </details>
      )}

      <Button
        onClick={() => create.mutate()}
        disabled={
          !siteId ||
          !templateId ||
          !visitDate ||
          (weekdayMismatch && (!canOverride || !weekdayReason)) ||
          (!!overrideWeek && !overrideReason) ||
          create.isPending
        }
      >
        {create.isPending ? "Creating…" : "Create visit"}
      </Button>
    </div>
  );
}
