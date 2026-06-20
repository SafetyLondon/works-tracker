import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";

// Entity kinds whose evidence is fully wired end-to-end (link table + read
// policy + rpc_finalise_evidence_upload insert). Actions/constraints are not
// wired server-side yet (no link table), so they are intentionally excluded.
type EvidenceEntityKind =
  | "visit_focus_item"
  | "review_line_score"
  | "focus_item_score";

const LINK: Record<EvidenceEntityKind, { table: string; fk: string }> = {
  visit_focus_item: { table: "visit_focus_item_evidence", fk: "visit_focus_item_id" },
  review_line_score: { table: "review_line_score_evidence", fk: "review_line_score_id" },
  focus_item_score: { table: "focus_item_score_evidence", fk: "focus_item_score_id" },
};

// Matches the MIME allow-list and size cap enforced by
// rpc_finalise_evidence_upload.
const ACCEPT = "image/jpeg,image/png,image/webp,image/heic,image/heif,application/pdf";
const MAX_BYTES = 10 * 1024 * 1024;

export function EvidencePanel({
  entityKind,
  entityId,
  siteId,
  canUpload = false,
}: {
  entityKind: EvidenceEntityKind;
  entityId: string;
  siteId: string;
  canUpload?: boolean;
}) {
  const qc = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const link = LINK[entityKind];

  const items = useQuery({
    queryKey: ["evidence", entityKind, entityId],
    queryFn: async () => {
      const { data, error } = await (supabase.from(link.table as any) as any)
        .select("caption, evidence_items(id, storage_path, mime_type)")
        .eq(link.fk, entityId);
      if (error) throw error;
      const rows = (data ?? []) as any[];
      // Private bucket — sign each object for display.
      return Promise.all(
        rows.map(async (r) => {
          const path = r.evidence_items?.storage_path as string | undefined;
          let url: string | null = null;
          if (path) {
            const { data: s } = await supabase.storage
              .from("evidence")
              .createSignedUrl(path, 3600);
            url = s?.signedUrl ?? null;
          }
          return {
            id: r.evidence_items?.id as string,
            caption: (r.caption as string | null) ?? null,
            mime: (r.evidence_items?.mime_type as string | null) ?? null,
            url,
          };
        }),
      );
    },
  });

  const upload = async (file: File) => {
    if (file.size > MAX_BYTES) {
      toast.error("File too large (max 10 MB).");
      return;
    }
    setBusy(true);
    try {
      const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
      // First path segment MUST be the site id (storage RLS + finalise check).
      const path = `${siteId}/${entityKind}/${entityId}/${crypto.randomUUID()}-${safe}`;
      const { error: upErr } = await supabase.storage
        .from("evidence")
        .upload(path, file, { contentType: file.type, upsert: false });
      if (upErr) throw upErr;
      const { error: finErr } = await supabase.rpc("rpc_finalise_evidence_upload", {
        p_storage_path: path,
        p_entity_kind: entityKind,
        p_entity_id: entityId,
      });
      if (finErr) throw finErr;
      toast.success("Photo attached");
      qc.invalidateQueries({ queryKey: ["evidence", entityKind, entityId] });
    } catch (e: any) {
      toast.error(e.message ?? "Upload failed");
    } finally {
      setBusy(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const photos = items.data ?? [];

  return (
    <div className="space-y-2">
      {photos.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {photos.map((p) =>
            !p.url ? null : p.mime === "application/pdf" ? (
              <a
                key={p.id}
                href={p.url}
                target="_blank"
                rel="noreferrer"
                className="text-xs underline"
              >
                PDF{p.caption ? ` · ${p.caption}` : ""}
              </a>
            ) : (
              <a key={p.id} href={p.url} target="_blank" rel="noreferrer">
                <img
                  src={p.url}
                  alt={p.caption ?? "evidence"}
                  className="h-20 w-20 rounded border object-cover"
                />
              </a>
            ),
          )}
        </div>
      )}
      {canUpload && (
        <div>
          <input
            ref={fileRef}
            type="file"
            accept={ACCEPT}
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void upload(f);
            }}
          />
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={busy}
            onClick={() => fileRef.current?.click()}
          >
            {busy ? "Uploading…" : "Add photo"}
          </Button>
        </div>
      )}
      {!canUpload && photos.length === 0 && (
        <p className="text-xs text-muted-foreground">No photos.</p>
      )}
    </div>
  );
}
