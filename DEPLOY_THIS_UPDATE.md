# Final floor-interface polish

This release changes only:

- `web/admin-a106dc80eeabd658.html`

No database migration, Edge Function, Apps Script, or Sheet change is required.

## Copy

```bash
cp "$UPDATE/web/admin-a106dc80eeabd658.html" \
  "web/admin-a106dc80eeabd658.html"
```

## Publish

```bash
git add web/admin-a106dc80eeabd658.html
git commit -m "Polish entry, sale order, products and slots"
git push origin main
```

After GitHub Pages deploys, hard-refresh the admin page with `Command + Shift + R`.
