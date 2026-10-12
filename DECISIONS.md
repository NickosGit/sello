# DECISIONS — Sello

Format: date · decision · why · alternative rejected.

## 2026-10-11

- **Turn off Cache Components (`cacheComponents: false`).** Next 16.4 scaffolds with it on. Every Sello screen depends on who is asking (RLS) or on a token, and the `/p/[token]` read *writes* `opened_at`. Caching any of that across requests is a data-leak or wrong-metric risk. *Rejected:* keeping it on and wrapping every session read in `<Suspense>`. That is more surface for a one-week slice and gains nothing.
- **Next 16 `proxy.ts` instead of `middleware.ts`.** Same function, new name in Next 16. It protects `/app`, `/review` and `/vouch`. `/p/*` and `/api/cron/*` are excluded on purpose: they authenticate by token or secret. Pages re-check the session (`lib/session.ts`), so the proxy is not the only barrier.
- **Status labels in Spanish on screen, enums in English in the DB.** DECLARADO / RESPALDADO / VERIFICADO, each with its one-line explanation. The DB keeps `DECLARED/VOUCHED/VERIFIED` as the packet defines. *Rejected:* English badges as in the mockup, because the Lupita persona leaves when she sees unexplained words like "verify".
- **Secret grep runs as `npm run secrets`.** Same regex as the prompt, written with character classes (`s[k]-`) so the script does not match itself. It skips `.env.example`, `package-lock.json` (`queue-microtask` matches `sk-`, a false positive), `docs/IMPLEMENTATION_PROMPT.md` and this file (both quote the pattern itself). Exit code 1 if anything else matches.
- **No `SUPABASE_SERVICE_ROLE_KEY` variable at all**, not even for scripts. Attack tests run in the SQL editor with `set local role authenticated`.
- **Status integrity has two locks, not one.** The prompt's `sello.transition` flag is a GUC, and any session can `set_config` it. So the claims trigger also requires that the UPDATE is *not* running as an API role (`authenticated`/`anon`). Only a security-definer function (running as the table owner) passes both. Each function also turns the flag back off before returning, so it cannot leak into a later statement in the same transaction.
- **Extra guards beyond the prompt, all found by asking "how would Lupita or a friend cheat?":** evidence on a proof freezes once any claim is VOUCHED/VERIFIED (otherwise the evidence could be swapped after inspection). Share-link and vouch-invite tokens, `opened_at`, decisions and `used` are forced on insert. The owner has no UPDATE on `share_links` (cannot fake opens or decisions). The owner previewing their own `/p/[token]` does not count as an open and cannot record a decision. Review-request criteria are fixed by the DB. A reviewer who vouched (or holds an invite) cannot claim the request, and a reviewer who claimed cannot accept a vouch invite.
- **RLS helpers are `security definer` boolean functions** (`is_proof_owner`, `is_assigned_reviewer`, `has_vouch_access`, `is_approved_reviewer`). Policies on `proofs` and `review_requests` reference each other, and plain subqueries would recurse.
- **Review-request claim = plain UPDATE under RLS (as the prompt says) + a guard trigger.** Postgres ORs the WITH CHECK of all permissive UPDATE policies, so the "done" policy's check (`reviewer_id = auth.uid()`) would have let a claim through with `no_prior_relationship = false`. The trigger enforces the transition regardless.
- **`flag_stale_links()` is also granted to anon (deviation).** The cron route has no service-role key by design, so it can only call the DB as anon. The function is idempotent and only records facts that are already true (7 days without open / without decision), so calling it early or often changes nothing. The route still rejects requests without `CRON_SECRET`. *Rejected:* a service-role key in Vercel (breaks rule 4), and a secret check inside the DB (one more secret to paste into SQL for no real gain).
- **`revoke … from public` as well as anon.** Postgres grants EXECUTE on new functions to PUBLIC by default, so revoking only from anon would leave `verify_claim` callable by anyone. Attack test T10d checks this.
- **The attack suite is one PL/pgSQL function that returns a PASS/FAIL table** and rolls itself back (forced SQLSTATE `SLRBK`). The Supabase SQL editor shows only the last statement's result, so a literal `begin; … rollback;` would end on ROLLBACK and show nothing. Users are still simulated with `role = authenticated` + `request.jwt.claims`.
- **SQL syntax was checked locally with libpg_query (the real Postgres parser, WASM)** before the first run, so syntax errors are ruled out. Semantics are what the attack run tests.

## Bugs found

_(none yet)_

## Mañana, primer movimiento:

Run `001_sello.sql` then `attacks.sql` in the Supabase SQL editor, fix any FAIL, then DEPLOY 1 (GitHub repo + Vercel).
