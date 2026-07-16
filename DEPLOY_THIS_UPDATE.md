# Maitri Carnival — floor UX and speed update

Copy the included files into the same paths in the existing repository.

## 1. Apply the new migration

```bash
npx supabase db push --dry-run
```

The dry run should list only:

```text
202607170008_speed_and_floor_ux.sql
```

Then apply it:

```bash
npx supabase db push
```

## 2. Redeploy the updated Edge Function

```bash
npx supabase functions deploy admin-api --no-verify-jwt
```

## 3. Publish the frontend and logo assets

```bash
git add -A
git commit -m "Improve Carnival speed and floor UX"
git push origin main
```

Publish/copy these exact paths:

- `web/user.html`
- `web/admin-a106dc80eeabd658.html`
- `web/assets/maitri-logo.png`
- `web/assets/niharika-logo.png`
- `supabase/functions/admin-api/index.ts`
- `supabase/migrations/202607170008_speed_and_floor_ux.sql`

## Requirements

- Database migration: **Yes**
- Edge Function redeploy: **Yes — `admin-api` only**
- Frontend publish: **Yes**
- Google Apps Script change: **No**
- `data-sync` redeploy: **No**

After GitHub Pages finishes, hard-refresh both applications and test one login, one customer search, and one order save.
