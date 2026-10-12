# Setup: the steps only a human can do

`.env.local` already exists (gitignored) with `CRON_SECRET` generated and `NEXT_PUBLIC_SITE_URL=http://localhost:3700`. Fill in the rest as you go.

Replace `<ref>` with your Supabase project ref and `<vercel-url>` with the deployed host (e.g. `sello-xxx.vercel.app`).

## 1. Supabase (≈5 min)

1. https://supabase.com/dashboard → **New project**. Name `sello`, free plan, region **East US** or **West US** (the closest to CDMX). Save the DB password in your password manager. You won't paste it anywhere.
2. **Project Settings → API Keys**: copy
   - **Project URL** → `NEXT_PUBLIC_SUPABASE_URL`
   - **anon / publishable** key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - ⚠️ Do **not** copy the service-role / secret key. The app never uses it.
3. **Authentication → URL Configuration**
   - Site URL: `http://localhost:3700` (switch it to `https://<vercel-url>` after DEPLOY 1)
   - Redirect URLs: add `http://localhost:3700/auth/callback` and `https://<vercel-url>/auth/callback`
4. **Authentication → Sign In / Providers → Google**: leave the tab open. Copy the **Callback URL** it shows (`https://<ref>.supabase.co/auth/v1/callback`). You'll need it in step 2.3.

## 2. Google OAuth client (≈7 min)

1. https://console.cloud.google.com → project picker → **New project** → `sello`.
2. **Google Auth Platform → Branding / Audience**: app name `Sello`, your email as support and developer contact, Audience **External**, publishing status **Testing**. Under **Test users**, add your Gmail and every account that will log in (the reviewer accounts, persona testers).
3. **Clients → Create client → Web application**
   - Authorized JavaScript origins: `http://localhost:3700` and `https://<vercel-url>`
   - Authorized redirect URIs: `https://<ref>.supabase.co/auth/v1/callback` (from 1.4)
4. Copy the **Client ID** and **Client secret** into the Supabase Google provider (1.4), toggle **Enable**, then **Save**. These two values go into Supabase only, not into `.env.local`.

## 3. Gemini key (≈2 min)

1. https://aistudio.google.com → **Get API key → Create API key** (in the `sello` Cloud project) → `GEMINI_API_KEY`.
2. In AI Studio's model picker, copy the exact ID of the current **free-tier Flash** model → `GEMINI_MODEL`.
3. Leaving both blank is fine. The app then produces a draft labeled **SIMULATED AI OUTPUT**.

## 4. GitHub + Vercel (DEPLOY 1)

1. https://github.com/new → repo `sello`, **no** README/.gitignore/license → send me the repo URL and I'll push.
2. https://vercel.com/new → **Import** the `sello` repo. Framework: Next.js (auto). Root directory: `./`.
3. **Environment Variables** (Production + Preview): add all six from `.env.local`, with `NEXT_PUBLIC_SITE_URL=https://<vercel-url>`. Use the same `CRON_SECRET` value as in `.env.local`. Never put a key behind a `NEXT_PUBLIC_` name except the two Supabase ones.
4. **Deploy**. Once you know `<vercel-url>`, go back to: Supabase Site URL + Redirect URLs (1.3), Google JS origins (2.3), and `NEXT_PUBLIC_SITE_URL` in Vercel. Then **Redeploy**.

## 5. Database (after commit 2)

SQL editor → paste `supabase/migrations/001_sello.sql` → Run. Then paste `supabase/tests/attacks.sql` → Run, and read the `PASS`/`FAIL` notices.
