import { Link, useRouter } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { useAuth } from "@/lib/auth-context";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import type { ReactNode } from "react";

export function AppShell({ children }: { children: ReactNode }) {
  const { user, isAdmin } = useAuth();
  const router = useRouter();
  const qc = useQueryClient();

  const signOut = async () => {
    await qc.cancelQueries();
    qc.clear();
    await supabase.auth.signOut();
    router.navigate({ to: "/auth", replace: true });
  };

  return (
    <div className="min-h-screen bg-background text-foreground flex flex-col">
      <header className="border-b sticky top-0 bg-background/95 backdrop-blur z-40">
        <div className="container mx-auto px-4 py-3 flex items-center justify-between gap-4">
          <Link to="/" className="font-semibold tracking-tight">
            TMS Cleaning Quality
          </Link>
          <nav className="hidden md:flex items-center gap-1 text-sm">
            <Link
              to="/"
              className="px-3 py-1.5 rounded hover:bg-accent"
              activeProps={{ className: "px-3 py-1.5 rounded bg-accent font-medium" }}
              activeOptions={{ exact: true }}
            >
              Dashboard
            </Link>
            <Link
              to="/visits"
              className="px-3 py-1.5 rounded hover:bg-accent"
              activeProps={{ className: "px-3 py-1.5 rounded bg-accent font-medium" }}
            >
              Visits
            </Link>
            <Link
              to="/actions"
              className="px-3 py-1.5 rounded hover:bg-accent"
              activeProps={{ className: "px-3 py-1.5 rounded bg-accent font-medium" }}
            >
              Actions
            </Link>
            <Link
              to="/field-guide"
              className="px-3 py-1.5 rounded hover:bg-accent"
              activeProps={{ className: "px-3 py-1.5 rounded bg-accent font-medium" }}
            >
              Field Guide
            </Link>
            {isAdmin && (
              <Link
                to="/admin/users"
                className="px-3 py-1.5 rounded hover:bg-accent"
                activeProps={{ className: "px-3 py-1.5 rounded bg-accent font-medium" }}
              >
                Admin
              </Link>
            )}
          </nav>
          <div className="flex items-center gap-2 text-sm">
            <span className="hidden md:inline text-muted-foreground">{user?.email}</span>
            <Button variant="outline" size="sm" onClick={signOut}>
              Sign out
            </Button>
          </div>
        </div>
        {/* Mobile nav */}
        <nav className="md:hidden border-t flex overflow-x-auto text-sm">
          <Link to="/" className="px-3 py-2 whitespace-nowrap" activeOptions={{ exact: true }}>
            Dashboard
          </Link>
          <Link to="/visits" className="px-3 py-2 whitespace-nowrap">
            Visits
          </Link>
          <Link to="/actions" className="px-3 py-2 whitespace-nowrap">
            Actions
          </Link>
          <Link to="/field-guide" className="px-3 py-2 whitespace-nowrap">
            Guide
          </Link>
          {isAdmin && (
            <Link to="/admin/users" className="px-3 py-2 whitespace-nowrap">
              Admin
            </Link>
          )}
        </nav>
      </header>
      <main className="flex-1 container mx-auto px-4 py-6 max-w-5xl">{children}</main>
    </div>
  );
}
