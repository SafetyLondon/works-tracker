// Display labels for DB enum codes. Single source of UI strings.
export const visitStatusLabel: Record<string, string> = {
  draft: "Draft",
  planned: "Planned",
  in_progress: "In progress",
  submitted_for_review: "Submitted for review",
  reviewed: "Reviewed",
  closed: "Closed",
  cancelled: "Cancelled",
};

export const actionStatusLabel: Record<string, string> = {
  open: "Open",
  assigned: "Assigned",
  in_progress: "In progress",
  blocked: "Blocked",
  awaiting_verification: "Awaiting verification",
  closed: "Closed",
  cancelled: "Cancelled",
};

export const actionPriorityLabel: Record<string, string> = {
  urgent: "Urgent",
  high: "High",
  normal: "Normal",
  low: "Low",
};

export const focusItemStatusLabel: Record<string, string> = {
  selected: "Selected",
  completed: "Completed",
  partially_completed: "Partially completed",
  not_completed: "Not completed",
  inaccessible: "Inaccessible",
  deferred: "Deferred",
  not_applicable: "Not applicable",
};

export const recommendationStatusLabel: Record<string, string> = {
  pending: "Pending decision",
  selected: "Selected",
  skipped: "Skipped",
  inaccessible: "Inaccessible",
  not_applicable: "Not applicable",
};

export const scopeClassificationLabel: Record<string, string> = {
  routine_cleaning: "Routine cleaning failure",
  rotating_focus: "Rotating focus issue",
  maintenance_site_fabric: "Maintenance / site fabric",
  access: "Access",
  equipment_chemical: "Equipment / chemical",
  out_of_scope: "Out of scope",
  additional_resource: "Additional resource needed",
  urgent_hs: "Urgent H&S",
};

export const reviewTypeLabel: Record<string, string> = {
  dm_lightweight: "DM lightweight",
  joint_walk: "Joint walk",
  ops_spot: "Ops spot check",
  gm_spot: "GM spot check",
};

export const reviewStatusLabel: Record<string, string> = {
  draft: "Draft",
  submitted: "Submitted",
  superseded: "Superseded",
};

// 1–5 + N/A rating (display-only band derived in DB from rating).
export const ratingLabel: Record<number, string> = {
  1: "1 — Serious failure",
  2: "2 — Below standard",
  3: "3 — Acceptable",
  4: "4 — Good",
  5: "5 — Excellent",
};

export const ratingBandDisplayLabel: Record<string, string> = {
  red: "Red (1–2)",
  amber: "Amber (3)",
  green: "Green (4–5)",
  na: "Not applicable",
};

// Canonical role catalogue.
export const roleLabel: Record<string, string> = {
  tms_admin: "TMS Admin",
  tms_supervisor: "TMS Supervisor",
  tms_operative: "TMS Operative",
  centre_dm_reviewer: "Centre Duty Manager (Reviewer)",
  centre_operations_manager: "Centre Operations Manager",
  centre_gm: "Centre General Manager",
  read_only_viewer: "Read-only Viewer",
};

export const ROLE_CODES = [
  "tms_admin",
  "tms_supervisor",
  "tms_operative",
  "centre_dm_reviewer",
  "centre_operations_manager",
  "centre_gm",
  "read_only_viewer",
] as const;

export type RoleCode = (typeof ROLE_CODES)[number];

// Role bundles used by frontend guards (mirror server-side helpers).
// TMS owns the supervisor handover. Centre roles must NOT edit it.
export const ROLES_HANDOVER_MANAGE: RoleCode[] = [
  "tms_admin",
  "tms_supervisor",
  "tms_operative",
];

// Visit-date / weekday / rotation-week override (supervisor decision).
export const ROLES_VISIT_OVERRIDE: RoleCode[] = [
  "tms_admin",
  "tms_supervisor",
  "centre_operations_manager",
  "centre_gm",
];

// Centre review of the submitted handover (plus admin).
export const ROLES_REVIEW: RoleCode[] = [
  "centre_dm_reviewer",
  "centre_operations_manager",
  "centre_gm",
  "tms_admin",
];

// Reopen authority — distinct from handover-edit and review.
export const ROLES_REOPEN: RoleCode[] = [
  "centre_operations_manager",
  "centre_gm",
  "tms_admin",
];

// Back-compat alias for the previous bundle name; resolves to handover-edit.
export const ROLES_VISIT_MANAGE = ROLES_HANDOVER_MANAGE;
