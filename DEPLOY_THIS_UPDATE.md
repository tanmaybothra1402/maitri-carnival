# Maitri Carnival staff/dashboard update

Copy these files into the same paths in the existing repository.

Then run:

```bash
npx supabase db push --dry-run
npx supabase db push
npx supabase functions deploy admin-api --no-verify-jwt
npx supabase functions deploy data-sync --no-verify-jwt
```

Commit and push the two HTML pages to publish GitHub Pages.

After deployment:
1. Existing real-email admin logs in normally.
2. Admin → Staff creates one Staff ID per team member and selects preset/custom permissions.
3. Test Reception, Sale Order concurrent merge, Products, Slots, Bookings and Dashboard.
4. Run Supabase Sync → Pull ALL tables once; Apps Script code does not need replacement for this update.
