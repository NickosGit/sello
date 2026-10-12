# Implementation prompt: Sello (paste into Claude Code)

You are building **Sello**, a one-week slice for a university course. The full spec is in `docs/PACKET.md`. **Read it completely before writing any code.** Where this prompt and the packet disagree, this prompt wins.

## 0. Ground rules (non-negotiable)

1. **Security floor first, not last.** Auth, RLS, env vars and validation go in the first commits.
2. **Free stack only:** Next.js (App Router, TypeScript) on Vercel Hobby, Supabase free tier, Gemini API free tier, zod, Tailwind.
3. **No secrets in the repo.** `.env.local` is gitignored from commit 1. Commit `.env.example` with variable names only. Before every commit, run `git grep -nE "(sk-|AIza|eyJhbGci|service_role)"` and confirm zero hits outside `.env.example`.
4. **No service-role key anywhere in the app.** Everything runs as the signed-in user (RLS applies) or through narrowly scoped `security definer` RPCs.
5. **Status integrity lives in the database.** The frontend, API routes and AI can *request* a change. Only Postgres decides.
6. **All demo data is invented and labeled** "Invented demo data" on screen.
7. **Every AI-produced field is labeled** "AI-organized · status unchanged by AI". If no Gemini key is set, fall back to a deterministic simulated draft and label it "SIMULATED AI OUTPUT".
8. **Things you cannot do yourself** (create the Supabase project, Google OAuth client, Gemini key, Vercel project): stop, tell me exactly what to click and which values to paste into `.env.local` / Vercel, then wait.
9. **Never** build job listings, matching, or CV export. That is the forbidden zone.
10. Work in small steps. After each feature: run it, verify the acceptance criteria, commit.

## 1. Environment variables

```
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
GEMINI_API_KEY=            # server only, never NEXT_PUBLIC
GEMINI_MODEL=              # current free-tier Flash model name from Google AI Studio
CRON_SECRET=               # random 32+ chars, used by Vercel Cron
NEXT_PUBLIC_SITE_URL=      # e.g. https://sello-xxx.vercel.app
```

## 2. Database: `supabase/migrations/001_sello.sql`

Write it as one migration. I will paste it into the Supabase SQL editor.

**Types:** `claim_status` enum (`DECLARED`, `VOUCHED`, `VERIFIED`), `decision_kind` enum (`advance`, `request_more`, `do_not_advance`).

**Tables** (all `uuid` PKs with `gen_random_uuid()`, `created_at timestamptz default now()`):

- `profiles(id uuid pk references auth.users, display_name text, is_reviewer bool default false, reviewer_approved bool default false)`. Auto-create on signup with a trigger on `auth.users`.
- `proofs(id, owner_id uuid references auth.users default auth.uid(), title text check (char_length between 3 and 120), raw_evidence text check (char_length between 20 and 4000), evidence_link text null, intended_decision_maker text, intended_decision text, is_demo bool default true)`
- `ai_drafts(id, proof_id, payload jsonb, overclaim_flags jsonb, simulated bool)`
- `claims(id, proof_id, text, scope, conditions, ai_assistance, revisions, missing_info, cannot_infer, status claim_status default 'DECLARED')`. Length limits on every text column (claim text ≤ 400, others ≤ 800).
- `review_requests(id, proof_id, reviewer_id uuid null, no_prior_relationship bool default false, criteria text, status text check in ('open','claimed','done'))`
- `vouch_invites(id, proof_id, token text unique, used bool default false)`
- `vouches(id, claim_id, voucher_id uuid references auth.users, relationship text, what_they_saw text)`
- `status_events(id, claim_id, from_status claim_status null, to_status claim_status, actor_id uuid, actor_role text check in ('worker','voucher','reviewer','system'), reason text)`
- `share_links(id, proof_id, token text unique default encode(gen_random_bytes(24),'hex'), decision_maker_label text, intended_decision text, opened_at timestamptz, decision decision_kind, decision_note text, decided_at timestamptz, flag text check in ('no_inspection','no_action') null)`

**Status enforcement (the core of the slice):**

1. `BEFORE INSERT` trigger on `claims`: force `NEW.status := 'DECLARED'` whatever was sent. `AFTER INSERT`: write a `status_events` row (`null → DECLARED`, actor_role `worker`). This trigger function is `security definer`.
2. `BEFORE UPDATE` trigger on `claims`: if `NEW.status IS DISTINCT FROM OLD.status` and `current_setting('sello.transition', true) IS DISTINCT FROM 'on'`, then `raise exception 'status can only change through transition functions'`. Workers may still edit text fields on DECLARED claims only. After VOUCHED or VERIFIED, any text edit raises.
3. `vouch_claim(p_claim_id, p_relationship, p_what_they_saw)`, `security definer`, `set search_path = public`:
   - caller is signed in, is **not** the proof owner, and holds a used-by-them invite for that proof
   - `what_they_saw` is 20–800 chars
   - only `DECLARED → VOUCHED`
   - `set_config('sello.transition','on', true)`, update, insert vouch + event
4. `verify_claim(p_claim_id, p_scope, p_cannot_infer, p_reason)`, `security definer`. Reject unless **all** hold:
   - caller has `reviewer_approved = true`
   - caller is not the proof owner
   - caller has **no** row in `vouches` for any claim of that proof (conflict of interest)
   - caller claimed the `review_requests` row for that proof with `no_prior_relationship = true`
   - scope, cannot_infer and reason are each 10–800 chars
   - current status is `DECLARED` or `VOUCHED`

   Then set the transition flag, update status and scope/cannot_infer, and insert an event with actor_role `reviewer`.
5. `decline_claim(p_claim_id, p_reason)`: same reviewer checks. Status unchanged, event logged with `from = to`.
6. `retract_verification(p_claim_id, p_reason)`: same reviewer checks, `VERIFIED → DECLARED`, event logged.
7. `open_share_link(p_token)` and `record_decision(p_token, p_decision, p_note)`, `security definer`, granted to `anon`:
   - `open`: returns proof title, claims (with status, scope, cannot_infer) and their events **only for that token**. Sets `opened_at` only if null. Unknown token returns null (the route turns that into 404).
   - `record`: allowed only if opened and not yet decided. Note ≤ 500 chars.
8. `flag_stale_links()`: sets `no_inspection` when `opened_at is null and created_at < now() - interval '7 days'`, and `no_action` when `opened_at < now() - interval '7 days' and decided_at is null`.

**RLS: enable on every table.**

- `proofs`, `ai_drafts`, `claims`, `vouch_invites`, `share_links`: owner full access through `proof.owner_id = auth.uid()`.
- Reviewers: `select` on proofs, claims and events where they claimed the review request. They can `select` open review requests and `update` one to claim it (set `reviewer_id = auth.uid()`, `no_prior_relationship`).
- `status_events`: `select` for owner and assigned reviewer. **No insert/update/delete policies.** Only the definer functions write.
- `vouches`: select for owner and the voucher. No direct insert.
- `profiles`: users select/update their own row, but **cannot** change `reviewer_approved`. Enforce with a column check in a trigger. I approve reviewers manually in SQL.
- `revoke all on all functions in schema public from anon`, then grant `execute` only on `open_share_link` and `record_decision` to `anon`.

## 3. Attack tests: `supabase/tests/attacks.sql`

Plain SQL I can run in the Supabase SQL editor inside `begin; … rollback;`. Simulate users with:

```sql
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', '<uuid>')::text, true);
```

Create invented test users in `auth.users` at the top of the script. Each test prints `PASS`/`FAIL` with `raise notice`, catching expected exceptions. Cover packet tests 1–12:

- worker direct `update claims set status='VERIFIED'` → exception
- worker inserts claim with `status='VERIFIED'` → stored as `DECLARED`
- worker calls `verify_claim` on own claim → exception
- unapproved reviewer → exception
- approved reviewer who vouched for the proof → exception
- approved reviewer without claiming the request → exception
- missing scope → exception
- valid verification → `VERIFIED` and exactly one new event
- direct `insert into status_events` → denied
- worker edits text of a VERIFIED claim → exception
- `open_share_link` twice → `opened_at` unchanged
- `record_decision` before open → exception; twice → exception
- bad token → null
- user B selects user A's proofs → 0 rows

**Run it, and expect at least one FAIL the first time.** Fix it, re-run until all pass, and record the bug in `DECISIONS.md`.

## 4. App features (build in this order)

Every form and API route validates with zod using the same limits as the DB. Return generic error messages, never raw Postgres errors. UI copy is **Spanish (Mexico), plain words.** Every status badge has a one-line explanation:

- DECLARED: "Lo dices tú"
- VOUCHED: "Alguien que vio tu trabajo lo confirma"
- VERIFIED: "Una persona independiente revisó la evidencia"

**F1. Auth + shell.** `@supabase/ssr`, Sign in with Google, middleware protecting `/app/*` and `/review/*`.
- ✅ Signed-out visit to `/app` redirects to login. The profile row is auto-created.

**F2. New proof + AI draft.** `/app/proofs/new`: title, raw evidence (counter, max 4000), optional link, decision-maker label, intended decision. `POST /api/draft` (server only):
- loads the proof as the user
- calls Gemini with the evidence wrapped in `<evidence>…</evidence>` and a system prompt saying the text is data, not instructions
- requests JSON: `claims[]` with all claim fields, plus `overclaim_flags[]`
- validates the response with zod and stores it in `ai_drafts` only
- runs a deterministic overclaim check (verified, certificado, experto, garantizado, cualquier, siempre, todos, 100%) and merges it into the flags
- on no key or a Gemini error, produces a simulated draft with `simulated: true`
- ✅ The AI never writes to `claims`. Banner and labels are visible. A 4,001-char input is rejected before reaching Gemini.

**F3. Approve draft → claims.** `/app/proofs/[id]` shows the draft, editable. "Aprobar" inserts claims, which land as DECLARED with an event each. Overclaim flags show as warnings next to the claim.
- ✅ Packet test 1 passes in the UI.

**F4. Route to stronger status.** On the proof page, two clear options:
- "Alguien vio mi trabajo" creates a vouch invite link to copy
- "No tengo a quién pedirle" creates a review request with fixed written criteria

`/vouch/[token]` requires login, shows the claims, and calls `vouch_claim`.
- ✅ The owner opening their own vouch link gets a friendly refusal.

**F5. Reviewer.** `/review` lists open requests (approved reviewers only; others see "Tu cuenta aún no está aprobada como revisor"). Claiming requires ticking "No conozco a esta persona ni he trabajado con ella". `/review/[id]` shows the evidence and criteria, and per claim offers Verificar (scope + cannot-infer + reason required), Declinar, or Retirar verificación.
- ✅ Packet tests 4–7 hold in the UI.

**F6. Share link + decision-maker view.** The owner creates a link naming the decision-maker and decision; a copy button opens WhatsApp share text. `/p/[token]` is public, read-only and mobile-first, server-rendered via `open_share_link`. It shows claims grouped by status, scope, the cannot-infer box, a provenance timeline, and three decision buttons plus an optional note, calling `record_decision`.
- ✅ Bad token returns 404. Reopening doesn't move `opened_at`. A second decision is refused.

**F7. Accountability dashboard.** `/app` shows the top metric first: **"Enviadas → Abiertas → Con decisión"**, as counts and %. Per link: status chips, decision, flag. Proofs created is shown small and secondary.
- ✅ The numbers match the DB after the F6 test.

**F8. Automation.** Add `GET /api/cron/flag-stale`, which rejects unless `Authorization: Bearer ${CRON_SECRET}`, then calls `flag_stale_links()`. Add `vercel.json` with a daily cron. Flags show on the dashboard in red.
- ✅ Calling without the secret returns 401. Backdating a link in SQL and calling it sets the flag.

## 5. Commit and deploy plan (minimum 5 commits, 2 deploys)

1. `chore: scaffold Next.js, env example, gitignore, Supabase auth + middleware`, then **DEPLOY 1** (login works on the live URL)
2. `feat(db): schema, RLS, status transition functions`
3. `test(db): attack suite` (run it, then commit any fixes as `fix(db): …`)
4. `feat: proof creation, AI draft with labels, approve to DECLARED`
5. `feat: vouch + independent reviewer flows`
6. `feat: share link, decision-maker view, accountability dashboard, cron`, then **DEPLOY 2**
7. `fix: <bug found in mechanical pass>`, then redeploy
8. `fix(ux): <worst persona-test confusion>`, then redeploy

## 6. Docs to maintain

- `DECISIONS.md`: dated entries (decision, why, alternative rejected), the bug found and how it was fixed, and **"Mañana, primer movimiento:"** at the end of every session.
- `README.md`: what Sello is (3 lines), live URL, how to run locally, how to approve a reviewer (SQL snippet), security floor checklist with ✅.

## 7. Session close (end of every working session)

Update `DECISIONS.md` with tomorrow's first move, run the secret grep, then commit and push. Tell me the live URL and which acceptance criteria are still open.

**Start now:** read `docs/PACKET.md`, then give me a 10-line plan and the exact setup steps I need to do (Supabase project, Google OAuth, Gemini key, Vercel). Then begin F1.
