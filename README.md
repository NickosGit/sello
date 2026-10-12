# Sello

Sello turns a beginner's existing work into claims with an honest trust level: **DECLARED** (you say it), **VOUCHED** (someone who saw it confirms it), **VERIFIED** (an independent reviewer inspected the evidence).
The AI only organizes text. Postgres alone decides status.
Its top metric is whether the proof you sent was **opened and acted on**, not how many proofs were created.

- **Live URL:** _pending DEPLOY 1_
- **Spec:** [`docs/PACKET.md`](docs/PACKET.md) · build prompt: [`docs/IMPLEMENTATION_PROMPT.md`](docs/IMPLEMENTATION_PROMPT.md) · decision log: [`DECISIONS.md`](DECISIONS.md)

## Run locally

```bash
cp .env.example .env.local   # fill in the values (see docs/SETUP.md)
npm install
npm run dev   # http://localhost:3700
```

Database: paste `supabase/migrations/001_sello.sql` into the Supabase SQL editor and run it. Attack tests: paste `supabase/tests/attacks.sql` and run it (it rolls back).

## Approve a reviewer (manual, in the SQL editor)

```sql
update public.profiles
set is_reviewer = true, reviewer_approved = true
where id = (select id from auth.users where email = 'reviewer@example.com');
```

## Security floor

| | Item |
|---|---|
| ✅ | `.env.local` gitignored from commit 1; `.env.example` holds names only |
| ✅ | No service-role key anywhere in the app |
| ✅ | Google sign-in (tested locally); `proxy.ts` protects `/app`, `/review`, `/vouch`, and each page checks again |
| ⬜ | RLS on every table |
| ⬜ | Status changes only through `security definer` transition functions |
| ⬜ | Append-only `status_events` (no insert/update/delete policies) |
| ⬜ | zod on every form and API route, same limits as the DB |
| ⬜ | Gemini key server-only; AI writes only to `ai_drafts` |
| ⬜ | Attack suite passes |
| ⬜ | Secret grep returns zero hits |
