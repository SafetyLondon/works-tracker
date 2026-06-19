import { supabase } from "@/integrations/supabase/client";
import type { Database } from "@/integrations/supabase/types";

export type VisitStatus = Database["public"]["Enums"]["cleaning_visit_status"];
export type ActionStatus = Database["public"]["Enums"]["action_status"];
export type FocusItemStatus = Database["public"]["Enums"]["focus_item_status"];
export type ScopeClassification = Database["public"]["Enums"]["scope_classification"];

export async function listSites() {
  const { data, error } = await supabase
    .from("sites")
    .select("id, code, name, archived_at")
    .order("name");
  if (error) throw error;
  return data ?? [];
}

export async function listTemplates(siteId: string) {
  const { data, error } = await supabase
    .from("visit_templates")
    .select("id, code, name, expected_weekday, display_summary")
    .eq("site_id", siteId)
    .is("archived_at", null)
    .order("code");
  if (error) throw error;
  return data ?? [];
}

export async function listRotationProgrammes(siteId: string) {
  const { data, error } = await supabase
    .from("rotation_programmes")
    .select("id, code, name, visit_template_id, cycle_length_weeks, anchor_date")
    .eq("site_id", siteId)
    .is("archived_at", null);
  if (error) throw error;
  return data ?? [];
}

export async function listVisits(siteId?: string | null) {
  let q = supabase
    .from("cleaning_visits")
    .select(
      "id, site_id, visit_template_id, visit_date, status, version_no, supervisor_id, recommended_rotation_week, rotation_week_override, sites(name), visit_templates(name)",
    )
    .order("visit_date", { ascending: false })
    .limit(100);
  if (siteId) q = q.eq("site_id", siteId);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
}

export async function getVisitDetail(visitId: string) {
  const [visit, ratings, recs, focus, constraints, team, scope] = await Promise.all([
    supabase
      .from("cleaning_visits")
      .select(
        "*, sites(name), visit_templates(name, expected_weekday), rotation_programmes(name, cycle_length_weeks, anchor_date)",
      )
      .eq("id", visitId)
      .maybeSingle(),
    supabase
      .from("visit_rating_lines")
      .select("*")
      .eq("cleaning_visit_id", visitId)
      .order("display_order"),
    supabase
      .from("visit_focus_recommendations")
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
      .select("*, constraint_types(label)")
      .eq("cleaning_visit_id", visitId),
    supabase
      .from("visit_team_members")
      .select("*")
      .eq("cleaning_visit_id", visitId),
    supabase
      .from("visit_scope_snapshots")
      .select("*")
      .eq("cleaning_visit_id", visitId)
      .order("display_order"),
  ]);
  if (visit.error) throw visit.error;
  return {
    visit: visit.data,
    rating_lines: ratings.data ?? [],
    recommendations: recs.data ?? [],
    focus_items: focus.data ?? [],
    constraints: constraints.data ?? [],
    team_members: team.data ?? [],
    scope_items: scope.data ?? [],
  };
}

export async function listActions(siteId?: string | null) {
  let q = supabase
    .from("actions")
    .select(
      "id, site_id, title, scope_classification, priority, status, due_date, urgent_hs_flag, sites(name), version_no",
    )
    .order("created_at", { ascending: false })
    .limit(200);
  if (siteId) q = q.eq("site_id", siteId);
  const { data, error } = await q;
  if (error) throw error;
  return data ?? [];
}

export async function dashboardCounters() {
  const { data, error } = await supabase
    .from("v_dashboard_counters")
    .select("*");
  if (error) throw error;
  return data ?? [];
}

export type SiteDirectoryEntry = {
  user_id: string;
  display_name: string | null;
  role_code: string;
  site_id: string | null;
};

export async function siteUserDirectory(siteId: string): Promise<SiteDirectoryEntry[]> {
  const { data, error } = await supabase.rpc("rpc_site_user_directory", {
    p_site_id: siteId,
  });
  if (error) throw error;
  return (data ?? []) as SiteDirectoryEntry[];
}

export async function listOpenReviewForVisit(visitId: string) {
  const { data, error } = await supabase
    .from("reviews")
    .select("*")
    .eq("cleaning_visit_id", visitId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function getReviewDetail(reviewId: string) {
  const [r, lines, focusScores] = await Promise.all([
    supabase.from("reviews").select("*").eq("id", reviewId).maybeSingle(),
    supabase.from("review_line_scores").select("*").eq("review_id", reviewId),
    supabase.from("focus_item_scores").select("*").eq("review_id", reviewId),
  ]);
  if (r.error) throw r.error;
  return { review: r.data, line_scores: lines.data ?? [], focus_scores: focusScores.data ?? [] };
}
