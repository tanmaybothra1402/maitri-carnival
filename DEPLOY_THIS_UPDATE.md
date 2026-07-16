# Reception, Team and Customer Welcome update

Copy these files into the same paths in the repository:

- `web/admin-a106dc80eeabd658.html`
- `web/user.html`
- `web/assets/maitri-logo.png`
- `web/assets/niharika-logo.png`
- `supabase/functions/admin-api/index.ts`

Deploy:

```bash
npx supabase functions deploy admin-api --no-verify-jwt

git add -A
git commit -m "Refine Reception, Team and customer welcome flow"
git push origin main
```

No database migration is required. No Apps Script change is required.
