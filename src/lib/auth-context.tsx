import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import type { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";
import { useQueryClient } from "@tanstack/react-query";

type Role = { role_code: string; site_id: string | null };

interface AuthState {
  user: User | null;
  session: Session | null;
  loading: boolean;
  roles: Role[];
  isAdmin: boolean;
  hasSiteRole: (siteId: string | null, roles: string[]) => boolean;
  refreshRoles: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [roles, setRoles] = useState<Role[]>([]);
  const [loading, setLoading] = useState(true);

  // Track real unauthenticated <-> authenticated transitions only.
  // SIGNED_IN can fire repeatedly (tab focus, token refresh races); we ignore
  // duplicates. TOKEN_REFRESHED never triggers router/query invalidation, so
  // dirty form state is preserved across silent token rotations.
  const wasAuthenticated = useRef<boolean>(false);

  const loadRoles = async (uid: string | null) => {
    if (!uid) {
      setRoles([]);
      return;
    }
    const { data } = await supabase
      .from("user_site_roles")
      .select("role_code, site_id")
      .eq("user_id", uid);
    setRoles(data ?? []);
  };

  useEffect(() => {
    // Listener first
    const { data: sub } = supabase.auth.onAuthStateChange((event, sess) => {
      setSession(sess);
      setUser(sess?.user ?? null);

      const nowAuth = !!sess?.user;
      const transitionedIn = nowAuth && !wasAuthenticated.current;
      const transitionedOut = !nowAuth && wasAuthenticated.current;

      if (event === "SIGNED_IN") {
        if (transitionedIn) {
          wasAuthenticated.current = true;
          void loadRoles(sess?.user?.id ?? null);
          // Targeted, not blanket: refetch identity-bound caches only.
          queryClient.invalidateQueries({ queryKey: ["me"] });
          queryClient.invalidateQueries({ queryKey: ["profile"] });
          queryClient.invalidateQueries({ queryKey: ["roles"] });
        }
        // Duplicate SIGNED_IN while already authenticated: ignored.
      } else if (event === "SIGNED_OUT") {
        if (transitionedOut || wasAuthenticated.current) {
          wasAuthenticated.current = false;
          setRoles([]);
          void queryClient.cancelQueries();
          queryClient.clear();
        }
      } else if (event === "USER_UPDATED") {
        void loadRoles(sess?.user?.id ?? null);
        queryClient.invalidateQueries({ queryKey: ["me"] });
        queryClient.invalidateQueries({ queryKey: ["profile"] });
        queryClient.invalidateQueries({ queryKey: ["roles"] });
      }
      // TOKEN_REFRESHED and INITIAL_SESSION: state updated above only.
      // No router invalidation, no broad query invalidation.
    });

    // Initial fetch (mirrors gate behaviour but does not block the tree)
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setUser(data.session?.user ?? null);
      wasAuthenticated.current = !!data.session?.user;
      void loadRoles(data.session?.user?.id ?? null).finally(() => setLoading(false));
    });

    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const isAdmin = roles.some((r) => r.role_code === "tms_admin" && r.site_id === null);

  const hasSiteRole = (siteId: string | null, requested: string[]) => {
    if (isAdmin) return true;
    return roles.some(
      (r) => requested.includes(r.role_code) && (r.site_id === siteId || siteId === null),
    );
  };

  const refreshRoles = async () => loadRoles(user?.id ?? null);

  return (
    <AuthContext.Provider
      value={{ user, session, loading, roles, isAdmin, hasSiteRole, refreshRoles }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be inside AuthProvider");
  return ctx;
}
