# DECISIONS — Sello

Format: date · decision · why · alternative rejected.

## 2026-10-11

- **Turn off Cache Components (`cacheComponents: false`).** Next 16.4 scaffolds with it on. Every Sello screen depends on who is asking (RLS) or on a token, and the `/p/[token]` read *writes* `opened_at`. Caching any of that across requests is a data-leak or wrong-metric risk. *Rejected:* keeping it on and wrapping every session read in `<Suspense>`. That is more surface for a one-week slice and gains nothing.
- **Next 16 `proxy.ts` instead of `middleware.ts`.** Same function, new name in Next 16. It protects `/app`, `/review` and `/vouch`. `/p/*` and `/api/cron/*` are excluded on purpose: they authenticate by token or secret. Pages re-check the session (`lib/session.ts`), so the proxy is not the only barrier.
- **Status labels in Spanish on screen, enums in English in the DB.** DECLARADO / RESPALDADO / VERIFICADO, each with its one-line explanation. The DB keeps `DECLARED/VOUCHED/VERIFIED` as the packet defines. *Rejected:* English badges as in the mockup, because the Lupita persona leaves when she sees unexplained words like "verify".
- **Secret grep runs as `npm run secrets`.** Same regex as the prompt, written with character classes (`s[k]-`) so the script does not match itself. It skips `.env.example`, `package-lock.json` (`queue-microtask` matches `sk-`, a false positive), `docs/IMPLEMENTATION_PROMPT.md` and this file (both quote the pattern itself). Exit code 1 if anything else matches.
- **No `SUPABASE_SERVICE_ROLE_KEY` variable at all**, not even for scripts. Attack tests run in the SQL editor with `set local role authenticated`.

## Bugs found

_(none yet)_

## Mañana, primer movimiento:

Finish docs/SETUP.md steps 1–4, confirm Google login on localhost:3700, then DEPLOY 1 and commit 2 (`001_sello.sql`).
