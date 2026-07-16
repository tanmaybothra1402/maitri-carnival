#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-maitri-office-exhibition}"
mkdir -p "$ROOT"/{supabase/migrations,supabase/functions/_shared,supabase/functions/sheet-sync,supabase/functions/admin-api,supabase/functions/image-proxy,web,apps-script,docs,templates,scripts,.github/workflows}
touch "$ROOT"/{README.md,.gitignore}
touch "$ROOT"/supabase/{config.toml,.env.example}
touch "$ROOT"/web/{app.html,mapping.html,dashboard.html,.nojekyll}
touch "$ROOT"/apps-script/Sync.gs
touch "$ROOT"/docs/{SETUP.md,PRODUCT_MASTER_FORMAT.md,TEST_PLAN.md,SECURITY_NOTES.md}
echo "Scaffolded $ROOT"
