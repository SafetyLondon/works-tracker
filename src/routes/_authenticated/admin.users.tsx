import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useMutation } from "@tanstack/react-query";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { listSites } from "@/lib/tms/queries";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth-context";

export const Route = createFileRoute("/_authenticated/admin/users")({
  component: UsersAdmin,
});

function UsersAdmin() {
  const { isAdmin } = useAuth();
  const sites = useQuery({ queryKey: ["sites"], queryFn: listSites });
  const profiles = useQuery({
    queryKey: ["admin", "profiles"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, email, display_name, disabled_at")
        .order("email");
      if (error) throw error;
      return data ?? [];
    },
  });
  const roles = useQuery({
    queryKey: ["admin", "roles"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("user_site_roles")
        .select("id, user_id, role_code, site_id, sites(name)")
        .order("granted_at", { ascending: false });
      if (error) throw error;
      return data ?? [];
    },
  });
  const roleDefs = useQuery({
    queryKey: ["role_defs"],
    queryFn: async () => {
      const { data } = await supabase
        .from("role_definitions")
        .select("code, label, is_global, is_active")
        .eq("is_active", true)
        .order("sort_order");
      return data ?? [];
    },
  });

  const [userId, setUserId] = useState("");
  const [roleCode, setRoleCode] = useState("");
  const [siteId, setSiteId] = useState("");

  const assign = useMutation({
    mutationFn: async () => {
      const def = roleDefs.data?.find((r) => r.code === roleCode);
      // Global roles MUST send a SQL NULL for p_site_id, not undefined.
      const { error } = await supabase.rpc("rpc_assign_site_role", {
        p_user_id: userId,
        p_role_code: roleCode,
        p_site_id: def?.is_global ? (null as unknown as string) : siteId,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Role assigned");
      roles.refetch();
    },
    onError: (e: any) => toast.error(e.message),
  });

  const revoke = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc("rpc_revoke_site_role", { p_assignment_id: id });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Role revoked");
      roles.refetch();
    },
    onError: (e: any) => toast.error(e.message),
  });

  if (!isAdmin) {
    return (
      <div className="text-sm text-muted-foreground">
        You need the TMS Administrator role to manage users.
      </div>
    );
  }

  const selectedDef = roleDefs.data?.find((r) => r.code === roleCode);

  return (
    <div className="space-y-6 max-w-3xl">
      <h1 className="text-2xl font-semibold">User & role administration</h1>

      <section className="border rounded-md p-3 space-y-3">
        <h2 className="font-semibold text-sm">Assign role</h2>
        <div className="grid sm:grid-cols-3 gap-2">
          <select
            className="border rounded-md px-2 py-1.5 bg-background text-sm"
            value={userId}
            onChange={(e) => setUserId(e.target.value)}
          >
            <option value="">User…</option>
            {(profiles.data ?? []).map((p) => (
              <option key={p.id} value={p.id}>
                {p.email}
              </option>
            ))}
          </select>
          <select
            className="border rounded-md px-2 py-1.5 bg-background text-sm"
            value={roleCode}
            onChange={(e) => setRoleCode(e.target.value)}
          >
            <option value="">Role…</option>
            {(roleDefs.data ?? []).map((r) => (
              <option key={r.code} value={r.code}>
                {r.label}
                {r.is_global ? " (global)" : ""}
              </option>
            ))}
          </select>
          <select
            className="border rounded-md px-2 py-1.5 bg-background text-sm"
            value={siteId}
            onChange={(e) => setSiteId(e.target.value)}
            disabled={selectedDef?.is_global}
          >
            <option value="">{selectedDef?.is_global ? "— Global —" : "Site…"}</option>
            {(sites.data ?? []).map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>
        <Button
          onClick={() => assign.mutate()}
          disabled={!userId || !roleCode || (!selectedDef?.is_global && !siteId)}
        >
          Assign
        </Button>
        <p className="text-xs text-muted-foreground">
          Create user accounts from the backend Auth dashboard (Users → Add user).
        </p>
      </section>

      <section>
        <h2 className="font-semibold text-sm mb-2">Existing assignments</h2>
        <div className="border rounded-md divide-y">
          {(roles.data ?? []).map((r: any) => {
            const p = profiles.data?.find((x) => x.id === r.user_id);
            return (
              <div key={r.id} className="flex items-center justify-between p-3 text-sm gap-3">
                <div>
                  <div className="font-medium">{p?.email ?? r.user_id}</div>
                  <div className="text-xs text-muted-foreground">
                    {r.role_code} {r.site_id ? `· ${(r as any).sites?.name}` : "· Global"}
                  </div>
                </div>
                <Button variant="ghost" size="sm" onClick={() => revoke.mutate(r.id)}>
                  Revoke
                </Button>
              </div>
            );
          })}
        </div>
      </section>

      <section>
        <h2 className="font-semibold text-sm mb-2">Profiles</h2>
        <div className="border rounded-md divide-y text-sm">
          {(profiles.data ?? []).map((p) => (
            <div key={p.id} className="p-3 flex items-center justify-between">
              <span>{p.email}</span>
              {p.disabled_at && <Badge variant="destructive">Disabled</Badge>}
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
