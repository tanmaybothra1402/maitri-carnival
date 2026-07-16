# Claude Cowork Handoff

Ask Claude Cowork to perform these checks in order without changing architecture unless a check fails:

1. Inspect all SQL migrations for syntax, privilege and RLS issues.
2. Link the folder to the new Supabase project.
3. Apply migrations to the new project only.
4. Deploy all three Edge Functions with `--no-verify-jwt` because each verifies its own credential.
5. Replace only the two public placeholders in each HTML file.
6. Create one admin Auth user and assign `app_metadata.role=admin`.
7. Upload the Excel template to Google Drive, paste `Sync.gs`, configure the secret and sync one test row.
8. Run every scenario in `docs/TEST_PLAN.md`.
9. Do not reuse CMAI project URLs, refs, keys, database rows or GitHub repository settings.
10. Report failures with the exact command, full error and affected file before patching.
