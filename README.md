# Site Shine — Works Tracker

A health & safety works tracking platform built with TanStack Start, React, and Supabase.

## Tech Stack

- **Framework:** TanStack Start (React + TanStack Router)
- **Database:** Supabase (PostgreSQL)
- **Styling:** Tailwind CSS v4
- **UI Components:** Radix UI + shadcn/ui
- **Forms:** React Hook Form + Zod validation
- **Charts:** Recharts
- **Build Tool:** Vite

## Getting Started

```bash
# Install dependencies
bun install

# Start dev server
bun run dev

# Build for production
bun run build
```

## Scripts

| Command | Description |
|---------|-------------|
| `bun run dev` | Start development server |
| `bun run build` | Production build |
| `bun run preview` | Preview production build |
| `bun run lint` | Run ESLint |
| `bun run format` | Format code with Prettier |
| `bun run db:test` | Run database tests |

## Project Structure

```
src/
├── components/     # UI components (shadcn/ui)
├── hooks/          # Custom React hooks
├── integrations/   # Supabase client & types
├── lib/            # Utilities, auth, API functions
├── routes/         # TanStack Router file-based routes
└── styles.css      # Global styles
supabase/
├── migrations/     # Database migrations
└── tests/          # Acceptance tests
```
