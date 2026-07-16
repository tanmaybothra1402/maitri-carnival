# Exact Implementation Process

Complete each checkpoint and stop if it fails. Replace every `YOUR_...` placeholder with the new project values, never CMAI values.

Official references:

- Supabase CLI: https://supabase.com/docs/guides/local-development/cli/getting-started
- Supabase password Auth: https://supabase.com/docs/guides/auth/passwords
- Supabase Auth configuration: https://supabase.com/docs/guides/auth/general-configuration
- ImageKit security: https://imagekit.io/docs/media-delivery-basic-security
- GitHub Pages: https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site

## Checkpoint 0 — prepare the folder

```bash
cd /path/to/maitri-office-exhibition
node --version
npx supabase --help
```

Use Node.js 20 or later for the CLI.

## Checkpoint 1 — create the new Supabase project

1. Create a completely new Supabase project.
2. Record:
   - project ref;
   - project URL;
   - publishable/anon key;
   - database password.
3. Do not copy any CMAI project ref, URL, key or secret.

Link this folder:

```bash
npx supabase login
npx supabase link --project-ref YOUR_NEW_PROJECT_REF
```

## Checkpoint 2 — configure Auth

In Supabase Dashboard → Authentication → Providers → Email:

1. Enable Email provider.
2. Enable new-user signups.
3. Disable **Confirm email**.
4. Keep anonymous sign-ins disabled.

The customer app converts `9876543210` to `919876543210@customers.maitri.local`. No email is sent.

Optional access code:

```sql
update public.system_settings
set registration_access_code_hash = encode(extensions.digest('YOUR_ACCESS_CODE', 'sha256'), 'hex')
where singleton = true;
```

Then change `REQUIRE_ACCESS_CODE:false` to `true` in `web/app.html`.

## Checkpoint 3 — apply database migrations

From the repository root:

```bash
npx supabase db push
```

Then inspect the migration history and tables in Supabase Dashboard. Required tables include:

```text
customers
designs
design_assets
barcode_mappings
orders
order_items
order_save_requests
barcode_mapping_log
product_sync_runs
system_settings
```

## Checkpoint 4 — create the first admin account

1. Supabase Dashboard → Authentication → Users → Add user.
2. Use a real admin email and a strong password.
3. In SQL Editor run:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
where email = 'YOUR_ADMIN_EMAIL';
```

Verify:

```sql
select email, raw_app_meta_data from auth.users where email = 'YOUR_ADMIN_EMAIL';
```

Do not register an admin through the customer page.

## Checkpoint 5 — prepare Edge Function secrets

Copy the example:

```bash
cp supabase/.env.example supabase/.env.production
```

Edit `supabase/.env.production` and set:

```dotenv
ALLOWED_ORIGINS=https://YOUR_GITHUB_USERNAME.github.io,http://localhost:8000
SHEET_SYNC_SECRET=YOUR_LONG_RANDOM_SECRET
IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/YOUR_IMAGEKIT_ID
IMAGEKIT_PRIVATE_KEY=YOUR_PRIVATE_KEY_IF_SIGNING_IS_ENABLED
IMAGEKIT_THUMB_TRANSFORMATION=w-240,h-320,c-at_max,q-50,f-auto
IMAGEKIT_PDF_TRANSFORMATION=w-320,h-430,c-at_max,q-30,f-jpg
```

Generate a Sheet secret on macOS/Linux:

```bash
openssl rand -hex 32
```

Upload secrets:

```bash
npx supabase secrets set --env-file supabase/.env.production
npx supabase secrets list
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are supplied automatically to hosted Edge Functions.

## Checkpoint 6 — deploy Edge Functions

Each function performs its own Auth/secret verification, so deploy with platform JWT verification disabled:

```bash
npx supabase functions deploy sheet-sync --no-verify-jwt
npx supabase functions deploy admin-api --no-verify-jwt
npx supabase functions deploy image-proxy --no-verify-jwt
npx supabase functions list
```

## Checkpoint 7 — configure ImageKit

1. Create or identify the URL endpoint used by every ProductMaster `ImageURL`.
2. Create two named transformations if your ImageKit plan/settings require them:
   - exhibition thumbnail: around 240 px wide, quality 50;
   - exhibition PDF: around 320 px wide, quality 30, JPEG.
3. For stronger protection, use private files and/or enforce signed URLs.
4. If signed URLs are enabled, set both `IMAGEKIT_URL_ENDPOINT` and `IMAGEKIT_PRIVATE_KEY` in Supabase secrets.
5. Keep ProductMaster URLs free of transformation/signature query parameters.

## Checkpoint 8 — create the Google product master

1. Upload `templates/Maitri_Niharika_Product_Master.xlsx` to Google Drive.
2. Open it with Google Sheets.
3. Delete the two example rows.
4. Confirm the tab is named `ProductMaster`.
5. Extensions → Apps Script.
6. Replace the editor contents with `apps-script/Sync.gs`.
7. Save.
8. Reload the Sheet.
9. Exhibition Sync menu → `1. Configure connection`.
10. Paste the new Supabase project URL and the same `SHEET_SYNC_SECRET`.
11. Run `2. Set up ProductMaster`.
12. Run `3. Install automatic triggers` and approve permissions.
13. Run `Test connection`.
14. Add one test design and run `Sync complete product snapshot`.
15. Verify the row in Supabase `designs` and its URL in `design_assets`.

## Checkpoint 9 — replace public frontend configuration

Find these placeholders in all three HTML files:

```js
SUPABASE_URL:'__SUPABASE_URL__'
SUPABASE_ANON_KEY:'__SUPABASE_ANON_KEY__'
```

Replace them in:

```text
web/app.html
web/mapping.html
web/dashboard.html
```

Example command from the repo root:

```bash
python3 - <<'PY'
from pathlib import Path
url = 'https://YOUR_PROJECT_REF.supabase.co'
key = 'YOUR_PUBLISHABLE_OR_ANON_KEY'
for name in ['app.html', 'mapping.html', 'dashboard.html']:
    path = Path('web') / name
    text = path.read_text()
    text = text.replace('__SUPABASE_URL__', url)
    text = text.replace('__SUPABASE_ANON_KEY__', key)
    path.write_text(text)
PY
```

Never insert the service-role key.

For an unguessable dashboard path, rename it before commit:

```bash
mv web/dashboard.html web/admin-$(openssl rand -hex 8).html
```

Record the resulting filename privately. Authentication is still required even if the URL leaks.

## Checkpoint 10 — local static-page check

This only serves the static HTML; it does not deploy anything:

```bash
cd web
python3 -m http.server 8000
```

Open:

```text
http://localhost:8000/app.html
http://localhost:8000/mapping.html
http://localhost:8000/YOUR_RENAMED_DASHBOARD.html
```

Add `http://localhost:8000` to `ALLOWED_ORIGINS` while checking locally.

## Checkpoint 11 — create the new GitHub repository

Create an empty, separate repository. Then:

```bash
cd /path/to/maitri-office-exhibition
git init
git branch -M main
git add .
git commit -m "Initial Maitri Niharika exhibition order system"
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/YOUR_NEW_REPO.git
git push -u origin main
```

Do not commit `supabase/.env.production`.

## Checkpoint 12 — enable GitHub Pages

The included `.github/workflows/pages.yml` publishes only `web/`.

1. GitHub repository → Settings → Pages.
2. Under Build and deployment choose **GitHub Actions**.
3. Open Actions and confirm the Pages workflow completes.
4. Your links will be similar to:

```text
https://YOUR_GITHUB_USERNAME.github.io/YOUR_NEW_REPO/app.html
https://YOUR_GITHUB_USERNAME.github.io/YOUR_NEW_REPO/mapping.html
https://YOUR_GITHUB_USERNAME.github.io/YOUR_NEW_REPO/YOUR_RENAMED_DASHBOARD.html
```

Update `ALLOWED_ORIGINS` if the final origin differs, then redeploy secrets/functions if needed.

## Checkpoint 13 — run the complete test plan

Follow `docs/TEST_PLAN.md`, especially:

- customer A/B isolation;
- stale-version conflict;
- duplicate request ID;
- base image URL not exposed;
- admin rejection for a normal customer;
- phone-password reset;
- camera and PDF behavior on actual phones.

## Checkpoint 14 — exhibition-day operating checklist

1. Freeze ProductMaster headers.
2. Confirm all active designs and barcode mappings.
3. Keep one admin logged into mapping and one into dashboard.
4. Print/share only `app.html` with customers.
5. Keep mapping and dashboard URLs private.
6. Export dashboard Excel backups periodically.
7. After 21 July, set registration off:

```sql
update public.system_settings set registration_enabled = false where singleton = true;
```

Optionally lock all orders:

```sql
update public.orders set status = 'Locked' where status <> 'Locked';
```
