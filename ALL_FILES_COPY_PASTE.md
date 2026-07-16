# All Files — Copy/Paste Edition

Each block is preceded by its exact repository path. The `.xlsx` workbook is a binary artifact and is linked separately.

## `.github/workflows/pages.yml`

```yaml
name: Deploy static exhibition pages

on:
  push:
    branches: ["main"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Upload web folder
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./web
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

## `.gitignore`

```text
.DS_Store
.env
.env.*
!.env.example
supabase/.temp/
node_modules/
*.log
```

## `FILE_MANIFEST.md`

```markdown
# File Manifest

Generated package contents:

| Path | Bytes | SHA-256 |
|---|---:|---|
| `.github/workflows/pages.yml` | 633 | `79ead1190cf0c5fcf281922a9cbad7c4f6197fc5d5a4e3e0e3eb9412cfed7533` |
| `.gitignore` | 72 | `d08e7f9f0b7f3424ca9fa9182f7d92b82b6f6e5a304fca222d5b7b2329da9199` |
| `README.md` | 1608 | `b52a01b0de951e0093af184416b2e656fe88e1b1b23afd4ac01df0efc1ef357f` |
| `apps-script/Sync.gs` | 11134 | `0c640ad539f0fcfe348a8bbcb87b65401ac0ad40ceeeef200b464dc9fd599824` |
| `docs/CLAUDE_COWORK_HANDOFF.md` | 856 | `f58063cca2ca49f80afcb7567861693394f3b1709444c3211c3f99e30af74c56` |
| `docs/PRODUCT_MASTER_FORMAT.md` | 1442 | `ee9ce35c75fbe1fe83564601635ec957c46ffbbc71282a445a25546f4d3462b5` |
| `docs/SECURITY_NOTES.md` | 1594 | `3b488636d4c3c4203625e01af9b72c83bd066eff0e95cf26108784b52e4f7858` |
| `docs/SETUP.md` | 8445 | `34c003de6d60f1e60b39ec26208c7e6dc89cc7429986f6cc8449b6ae17dcaac8` |
| `docs/TEST_PLAN.md` | 3384 | `ace9f38182b91c25cf8914d683a7ad192408c04b66569f21585b1f66788eb3c3` |
| `scripts/scaffold.sh` | 587 | `a0b6f1c9d025e0c68f6a2ff5655b709d38278a924cedb20a04b4b8184f24ccb3` |
| `supabase/.env.example` | 820 | `8b48a0cdb6298adb2a269d69674e2bec8fc3a0b15086e9d572cc0ca510d9f8d2` |
| `supabase/config.toml` | 677 | `18b5ed5db15e44f516178e334cec54af5188626145ad41c154b300145e760964` |
| `supabase/functions/_shared/auth.ts` | 873 | `e8f4a0064034349f8967685d99425f5945e905d98716141ca760c28bb24cf393` |
| `supabase/functions/_shared/cors.ts` | 951 | `8dca7e07d3a2fa9ffb22e80c1cd614930878d8c38f46d38180571da6362ddaba` |
| `supabase/functions/_shared/http.ts` | 1116 | `f7f3f4218c8c03aa7d54af031d221ad887d96b2c79e110687efa00a685ad7209` |
| `supabase/functions/_shared/secure.ts` | 293 | `c270ad74edb0cd2ee318acd72b24b725029ea5088e41e75126c6ce40202baf26` |
| `supabase/functions/_shared/supabase.ts` | 913 | `35eb2ff18146acbad4d327aefc7441a5fb9dd2a3e3c5ef4d4b93deaae0f3555c` |
| `supabase/functions/admin-api/index.ts` | 12467 | `63ee73908e0bf266e7637bf0f8fee1d321f474d00fcb8f26fdfd9e1f2dfbb293` |
| `supabase/functions/image-proxy/index.ts` | 4553 | `58499eb87e9536218a1d28bb798c5a55909a968370bcc6403d0114f9988cc2a8` |
| `supabase/functions/sheet-sync/index.ts` | 4008 | `783e0e609c10fd4e4fcb83efa3645d778b914b34e5006b513fc132b66f1e26de` |
| `supabase/migrations/202607150001_schema.sql` | 7448 | `295b9b15daa951c4fb0d9e77fe4fd9c580d148ff5b26b2a7ebb1496ddfdcb6e8` |
| `supabase/migrations/202607150002_auth_and_rls.sql` | 5623 | `b52dbadbca77975f9be4e2284032449915fcdad6e4fd24d01416602275d23791` |
| `supabase/migrations/202607150003_customer_functions.sql` | 8332 | `8ad08e4eb138bffd7df3a5cce260fa08fb9df50864eb0da7014c1164130a6048` |
| `supabase/migrations/202607150004_product_sync_functions.sql` | 6708 | `57efaea0bc3456ec5db185686eb8d60a60398ede935631da15a52eb6c3801ae7` |
| `supabase/migrations/202607150005_admin_support.sql` | 2980 | `9811ac16d810cdb6cb3b29c23cd0ff452a5b179f361cc5ae5b66dfb88b29a3c0` |
| `supabase/migrations/202607150006_seed.sql` | 665 | `88e07d2fa7af40cb07bc8b78602e482ae1052d5b31486cd49b52215de7fdadda` |
| `templates/BarcodeMappings_Import.csv` | 75 | `d35784df6e61b353f568fba125a2d4ba1812f3754557650b92a3153cf6027b03` |
| `templates/Maitri_Niharika_Product_Master.xlsx` | 23346 | `3776374a14d8938df2a5e079831e8b0310745fba081037266f70531894b24a0e` |
| `templates/ProductMaster.csv` | 337 | `d0d65049a8d12090545564b8e2d5cbccbcb1025b31e9df39d417c9eca6ab5d61` |
| `web/.nojekyll` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `web/app.html` | 25278 | `d05b3b31cc1ff51068c4d8a8a0e3fb3e281e05b3568bcf1edcc7dd51327b2647` |
| `web/dashboard.html` | 20345 | `48ba77359dfdf7963d82c2b74d9acf68837d658edd333e3b99e15ab1bffcd128` |
| `web/index.html` | 300 | `af71a8301a75dc5608182929bd1a75d1f87b7c3388ab0caf99ab7676b30040a1` |
| `web/mapping.html` | 12320 | `cb06e8946d34d8b45eb2a6ca5b859d92f0a4a2f6ccd8e7336bfd55b750f0ae26` |
```

## `README.md`

```markdown
# Maitri × Niharika Self-Service Exhibition Orders

Disposable, reliability-first order system for the 19–21 July 2026 in-office exhibition.

## Included

- Customer phone + password registration/login through Supabase Auth.
- Exactly one editable Maitri order and one editable Niharika order per customer.
- PostgreSQL RLS and an atomic, versioned save RPC.
- Barcode-to-design lookup and mobile camera scanning.
- Protected low-resolution thumbnails through an authenticated Edge Function proxy.
- Client-side order PDFs with low-resolution thumbnails.
- Separate admin barcode mapping tool and admin dashboard.
- Google Sheets → Supabase product-master synchronization.
- Excel product-master template.
- GitHub Pages workflow.

## Start here

1. Read `docs/SETUP.md`.
2. Work through its numbered checkpoints in order.
3. Use `docs/TEST_PLAN.md` before the exhibition.

## Important security boundary

The public Supabase URL and publishable/anon key belong in the HTML pages. The service-role key, ImageKit private key and Sheet sync secret must never be committed or inserted into a browser file.

## Main files

- `web/app.html` — customer registration, login, scanning, order editing and PDF.
- `web/mapping.html` — admin barcode mapping.
- `web/dashboard.html` — admin analytics, export and password reset.
- `supabase/migrations/` — schema, Auth trigger, RLS and database functions.
- `supabase/functions/` — Sheet sync, admin API and image proxy.
- `apps-script/Sync.gs` — Google Sheets sync.
- `templates/Maitri_Niharika_Product_Master.xlsx` — product-master starter workbook.
```

## `apps-script/Sync.gs`

```javascript
/**
 * Maitri × Niharika ProductMaster -> Supabase one-way synchronization.
 *
 * Google Sheets is the operating master for designs and base ImageKit URLs.
 * Orders and barcode mappings remain authoritative in Supabase.
 */

const EX_SHEET_NAME = 'ProductMaster';
const EX_BUSINESS_HEADERS = [
  'DesignNo', 'Firm', 'ImageURL', 'Category', 'Fabric', 'Color',
  'Description', 'Active'
];
const EX_META_HEADERS = ['SyncStatus', 'LastSyncedAt', 'SyncError', 'SyncVersion'];
const EX_ENDPOINT_PATH = '/functions/v1/sheet-sync';
const EX_PROP_URL = 'EX_SUPABASE_URL';
const EX_PROP_SECRET = 'EX_SHEET_SYNC_SECRET';

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Exhibition Sync')
    .addItem('1. Configure connection', 'configureExhibitionSync')
    .addItem('2. Set up ProductMaster', 'setupProductMasterSheet')
    .addItem('3. Install automatic triggers', 'installExhibitionSyncTriggers')
    .addSeparator()
    .addItem('Test connection', 'testExhibitionSyncConnection')
    .addItem('Sync selected rows', 'syncSelectedProductRows')
    .addItem('Sync complete product snapshot', 'syncCompleteProductSnapshot')
    .addItem('Show sync status', 'showExhibitionSyncStatus')
    .addToUi();
}

function configureExhibitionSync() {
  const ui = SpreadsheetApp.getUi();
  const props = PropertiesService.getScriptProperties();

  const urlPrompt = ui.prompt(
    'New Supabase project URL',
    'Paste the new project URL, for example https://abcxyz.supabase.co',
    ui.ButtonSet.OK_CANCEL
  );
  if (urlPrompt.getSelectedButton() !== ui.Button.OK) return;
  const url = String(urlPrompt.getResponseText() || '').trim().replace(/\/$/, '');
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) {
    throw new Error('Enter a valid Supabase project URL.');
  }

  const secretPrompt = ui.prompt(
    'Sheet sync secret',
    'Paste the exact SHEET_SYNC_SECRET configured in the new Supabase project.',
    ui.ButtonSet.OK_CANCEL
  );
  if (secretPrompt.getSelectedButton() !== ui.Button.OK) return;
  const secret = String(secretPrompt.getResponseText() || '').trim();
  if (secret.length < 24) throw new Error('Use a private secret of at least 24 characters.');

  props.setProperties({ [EX_PROP_URL]: url, [EX_PROP_SECRET]: secret }, false);
  ui.alert('Connection settings were saved in Apps Script Properties.');
}

function setupProductMasterSheet() {
  const ss = SpreadsheetApp.getActive();
  let sh = ss.getSheetByName(EX_SHEET_NAME);
  if (!sh) sh = ss.insertSheet(EX_SHEET_NAME);

  const allHeaders = EX_BUSINESS_HEADERS.concat(EX_META_HEADERS);
  if (sh.getMaxColumns() < allHeaders.length) {
    sh.insertColumnsAfter(sh.getMaxColumns(), allHeaders.length - sh.getMaxColumns());
  }
  sh.getRange(1, 1, 1, allHeaders.length).setValues([allHeaders]);
  sh.setFrozenRows(1);

  sh.getRange(1, 1, 1, EX_BUSINESS_HEADERS.length)
    .setBackground('#225E63').setFontColor('#FFFFFF').setFontWeight('bold');
  sh.getRange(1, EX_BUSINESS_HEADERS.length + 1, 1, EX_META_HEADERS.length)
    .setBackground('#E8F2F1').setFontColor('#225E63').setFontWeight('bold');

  sh.setColumnWidth(1, 150);
  sh.setColumnWidth(2, 115);
  sh.setColumnWidth(3, 300);
  sh.setColumnWidth(4, 140);
  sh.setColumnWidth(5, 140);
  sh.setColumnWidth(6, 110);
  sh.setColumnWidth(7, 300);
  sh.setColumnWidth(8, 85);
  sh.setColumnWidths(9, 4, 125);

  const usableRows = Math.max(sh.getMaxRows() - 1, 1);
  sh.getRange(2, 2, usableRows, 1).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['Maitri', 'Niharika', 'Both'], true)
      .setAllowInvalid(false)
      .build()
  );
  sh.getRange(2, 8, usableRows, 1).setDataValidation(
    SpreadsheetApp.newDataValidation()
      .requireValueInList(['TRUE', 'FALSE'], true)
      .setAllowInvalid(false)
      .build()
  );
  sh.getRange(2, 7, usableRows, 1).setWrap(true);
  sh.getRange(2, 9, usableRows, EX_META_HEADERS.length).setBackground('#F8FAF9');

  SpreadsheetApp.getUi().alert('ProductMaster is ready. Keep the first eight headers unchanged.');
}

function installExhibitionSyncTriggers() {
  const ss = SpreadsheetApp.getActive();
  ['handleExhibitionProductEdit', 'scheduledExhibitionFullSync'].forEach(function(handler) {
    ScriptApp.getProjectTriggers().forEach(function(trigger) {
      if (trigger.getHandlerFunction() === handler) ScriptApp.deleteTrigger(trigger);
    });
  });

  ScriptApp.newTrigger('handleExhibitionProductEdit')
    .forSpreadsheet(ss)
    .onEdit()
    .create();

  ScriptApp.newTrigger('scheduledExhibitionFullSync')
    .timeBased()
    .everyMinutes(5)
    .create();

  SpreadsheetApp.getUi().alert(
    'Triggers installed. Edited rows sync immediately; a full snapshot runs every 5 minutes to detect removed rows.'
  );
}

function testExhibitionSyncConnection() {
  const data = exCall_({ action: 'ping' });
  SpreadsheetApp.getUi().alert(
    'Connected. Supabase currently has ' + Number(data.designCount || 0) + ' designs.\n' + data.at
  );
}

function showExhibitionSyncStatus() {
  const data = exCall_({ action: 'getStatus' });
  const last = data.lastRun || {};
  SpreadsheetApp.getUi().alert(
    'Designs: ' + Number(data.designCount || 0) +
    '\nLast run: ' + (last.created_at || 'None') +
    '\nMode: ' + (last.mode || '-') +
    '\nStatus: ' + (last.status || '-') +
    (last.error ? '\nError: ' + last.error : '')
  );
}

function handleExhibitionProductEdit(e) {
  if (!e || !e.range) return;
  const sh = e.range.getSheet();
  if (sh.getName() !== EX_SHEET_NAME || e.range.getRow() <= 1) return;
  if (e.range.getColumn() > EX_BUSINESS_HEADERS.length) return;

  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) return;
  try {
    const start = Math.max(2, e.range.getRow());
    const end = e.range.getLastRow();
    const rows = [];
    const rowNumbers = [];
    for (let row = start; row <= end; row += 1) {
      const record = exReadRow_(sh, row);
      if (!record) continue;
      rows.push(record);
      rowNumbers.push(row);
      exSetStatus_(sh, row, 'SYNCING', '', '');
    }
    if (!rows.length) return;
    const result = exCall_({ action: 'syncRows', rows: rows });
    rowNumbers.forEach(function(row) {
      exSetStatus_(sh, row, 'SYNCED', new Date(), '');
      sh.getRange(row, EX_BUSINESS_HEADERS.length + 4).setValue(
        Number(sh.getRange(row, EX_BUSINESS_HEADERS.length + 4).getValue() || 0) + 1
      );
    });
    console.log(JSON.stringify(result));
  } catch (error) {
    const message = exError_(error);
    const row = e.range.getRow();
    if (row > 1) exSetStatus_(e.range.getSheet(), row, 'ERROR', '', message);
    console.error(message);
  } finally {
    lock.releaseLock();
  }
}

function syncSelectedProductRows() {
  const range = SpreadsheetApp.getActiveRange();
  if (!range || range.getSheet().getName() !== EX_SHEET_NAME) {
    throw new Error('Select one or more ProductMaster data rows first.');
  }
  const sh = range.getSheet();
  const rows = [];
  const rowNumbers = [];
  for (let row = Math.max(2, range.getRow()); row <= range.getLastRow(); row += 1) {
    const record = exReadRow_(sh, row);
    if (!record) continue;
    rows.push(record);
    rowNumbers.push(row);
    exSetStatus_(sh, row, 'SYNCING', '', '');
  }
  if (!rows.length) throw new Error('No populated ProductMaster rows were selected.');

  try {
    const result = exCall_({ action: 'syncRows', rows: rows });
    rowNumbers.forEach(function(row) { exSetStatus_(sh, row, 'SYNCED', new Date(), ''); });
    SpreadsheetApp.getUi().alert('Synced ' + Number(result.upserted || rows.length) + ' rows.');
  } catch (error) {
    const message = exError_(error);
    rowNumbers.forEach(function(row) { exSetStatus_(sh, row, 'ERROR', '', message); });
    throw error;
  }
}

function syncCompleteProductSnapshot() {
  exFullSync_(true);
}

function scheduledExhibitionFullSync() {
  exFullSync_(false);
}

function exFullSync_(interactive) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(5000)) return;
  try {
    const sh = SpreadsheetApp.getActive().getSheetByName(EX_SHEET_NAME);
    if (!sh) throw new Error('Run setupProductMasterSheet first.');
    const rows = [];
    const rowNumbers = [];
    for (let row = 2; row <= sh.getLastRow(); row += 1) {
      const record = exReadRow_(sh, row);
      if (!record) continue;
      rows.push(record);
      rowNumbers.push(row);
    }
    if (!rows.length) throw new Error('ProductMaster has no populated rows.');

    const result = exCall_({ action: 'fullSnapshot', rows: rows });
    rowNumbers.forEach(function(row) { exSetStatus_(sh, row, 'SYNCED', new Date(), ''); });
    if (interactive) {
      SpreadsheetApp.getUi().alert(
        'Full snapshot complete.\nReceived: ' + Number(result.received || 0) +
        '\nUpserted: ' + Number(result.upserted || 0) +
        '\nDeactivated because absent: ' + Number(result.deactivated || 0)
      );
    }
  } catch (error) {
    console.error(exError_(error));
    if (interactive) throw error;
  } finally {
    lock.releaseLock();
  }
}

function exReadRow_(sh, rowNumber) {
  const values = sh.getRange(rowNumber, 1, 1, EX_BUSINESS_HEADERS.length).getValues()[0];
  const hasData = values.some(function(value) { return String(value == null ? '' : value).trim() !== ''; });
  if (!hasData) return null;

  const record = {};
  EX_BUSINESS_HEADERS.forEach(function(header, index) {
    const value = values[index];
    record[header] = value instanceof Date ? value.toISOString() : value;
  });
  record.DesignNo = String(record.DesignNo || '').trim();
  if (!record.DesignNo) throw new Error('ProductMaster row ' + rowNumber + ': DesignNo is required.');
  record.UpdatedAt = new Date().toISOString();
  return record;
}

function exSetStatus_(sh, rowNumber, status, syncedAt, error) {
  sh.getRange(rowNumber, EX_BUSINESS_HEADERS.length + 1, 1, 3)
    .setValues([[status || '', syncedAt || '', error || '']]);
}

function exCall_(payload) {
  const props = PropertiesService.getScriptProperties();
  const baseUrl = String(props.getProperty(EX_PROP_URL) || '').replace(/\/$/, '');
  const secret = String(props.getProperty(EX_PROP_SECRET) || '');
  if (!baseUrl || !secret) throw new Error('Run “Configure connection” first.');

  const response = UrlFetchApp.fetch(baseUrl + EX_ENDPOINT_PATH, {
    method: 'post',
    contentType: 'application/json',
    headers: { 'x-sheet-sync-secret': secret },
    payload: JSON.stringify(payload || {}),
    muteHttpExceptions: true
  });

  const status = response.getResponseCode();
  const body = response.getContentText();
  let json;
  try { json = JSON.parse(body); }
  catch (_) { throw new Error('Supabase returned non-JSON HTTP ' + status + ': ' + body.slice(0, 300)); }

  if (status < 200 || status >= 300 || !json.ok) {
    throw new Error(exError_(json.error || ('Supabase HTTP ' + status)));
  }
  return json.data;
}

function exError_(error) {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  try { return JSON.stringify(error); }
  catch (_) { return String(error || 'Unknown error'); }
}
```

## `docs/CLAUDE_COWORK_HANDOFF.md`

```markdown
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
```

## `docs/PRODUCT_MASTER_FORMAT.md`

```markdown
# Product Master Format

Use the sheet name **ProductMaster** and keep these eight columns in this exact order.

| Column | Required | Rules |
|---|---:|---|
| DesignNo | Yes | Unique across both firms. Do not reuse a design number. |
| Firm | Yes | `Maitri`, `Niharika`, or `Both`. |
| ImageURL | Recommended | Base ImageKit URL only; no `tr`, `ik-s`, or `ik-t` parameters. |
| Category | No | Display and dashboard grouping. |
| Fabric | No | Display and dashboard grouping. |
| Color | No | Display and dashboard grouping. |
| Description | No | Short customer-facing identification text. |
| Active | Yes | `TRUE` or `FALSE`. Inactive designs cannot be newly scanned or saved. |

Example:

```csv
DesignNo,Firm,ImageURL,Category,Fabric,Color,Description,Active
MT-1001,Maitri,https://ik.imagekit.io/YOUR_ID/exhibition/MT-1001.jpg,Kurta Set,Cotton,Blue,Printed three-piece set,TRUE
NH-2001,Niharika,https://ik.imagekit.io/YOUR_ID/exhibition/NH-2001.jpg,Suit Set,Viscose,Pink,Embroidered suit set,TRUE
SH-3001,Both,https://ik.imagekit.io/YOUR_ID/exhibition/SH-3001.jpg,Co-ord Set,Linen,Beige,Shared design,TRUE
```

## Sheet behavior

`apps-script/Sync.gs` appends four operational columns:

- `SyncStatus`
- `LastSyncedAt`
- `SyncError`
- `SyncVersion`

Do not manually edit those four columns.

An edited row is pushed immediately. A full snapshot runs every five minutes so a row deleted from Google Sheets becomes inactive in Supabase.
```

## `docs/SECURITY_NOTES.md`

```markdown
# Security Notes

## Customer isolation

- Every customer profile uses the same UUID as its Supabase Auth user.
- The database creates both firm orders during registration.
- RLS permits customers to select only their own customer and order rows.
- Direct browser writes to orders and order items are not granted.
- `save_my_order` obtains `auth.uid()`, locks that user's firm order, validates products, replaces the cart atomically and increments the version.

## Admin isolation

- Admins use normal email/password Supabase Auth accounts.
- Their `app_metadata.role` must equal `admin`.
- `admin-api` verifies the Auth access token server-side before using service-role access.
- An unguessable dashboard filename is only an extra obscurity layer; authentication remains mandatory.

## Images

- Base ImageKit URLs live only in `design_assets`, which has no customer grant or RLS policy.
- The browser asks `image-proxy` for a design number and approved variant.
- The proxy fetches a transformed image server-side and streams only the bytes back.
- CSS right-click, drag and long-press blocking is a deterrent, not perfect copy prevention. A user can always photograph or screenshot a displayed image.
- For stronger protection, configure ImageKit named transformations, private files or signed delivery and set `IMAGEKIT_PRIVATE_KEY`.

## Secrets

Never place these in `web/*.html` or GitHub:

- Supabase service-role/secret key
- ImageKit private key
- `SHEET_SYNC_SECRET`
- Admin passwords

The Supabase URL and publishable/anon key are intentionally public; RLS is the protection layer.
```

## `docs/SETUP.md`

```markdown
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
```

## `docs/TEST_PLAN.md`

```markdown
# Test Plan

Run this on a new test project before importing the live product master.

## 1. Migration and provisioning

1. Create customer A using one phone number.
2. In Supabase Table Editor verify:
   - one `customers` row exists;
   - exactly two `orders` rows exist;
   - firms are Maitri and Niharika.
3. Registering the same phone again must not create a second customer.

## 2. Mandatory customer-isolation test

Use two separate browser profiles/incognito windows.

1. Register customer A and add/save one Maitri design.
2. Register customer B and add/save a different Maitri design.
3. While logged in as B, open browser DevTools Console and run queries using the page's `sb` client:

```js
await sb.from('customers').select('*')
await sb.from('orders').select('*')
await sb.from('order_items').select('*')
```

Expected: every returned row belongs only to B.

4. Copy customer A's order UUID from the admin dashboard.
5. As B, run:

```js
await sb.from('orders').select('*').eq('id', 'CUSTOMER_A_ORDER_UUID')
await sb.from('order_items').select('*').eq('order_id', 'CUSTOMER_A_ORDER_UUID')
```

Expected: empty arrays, not A's data.

6. As B, try a direct insert/update/delete on `order_items` and `orders`.
Expected: permission denied.

## 3. Concurrent save test

1. Log in as the same customer on two devices/tabs.
2. Load Maitri order version N in both.
3. Save tab 1.
4. Save tab 2 without reloading.
Expected: tab 2 receives `ORDER_VERSION_CONFLICT` and reloads the saved server copy rather than overwriting it.

## 4. Idempotency test

From DevTools, repeat the same `save_my_order` RPC twice with the exact same request UUID.
Expected: the second response equals the first and the order version increments only once.

## 5. Product sync

1. Add three designs in ProductMaster and run full snapshot.
2. Confirm all three appear in `designs`; their base URLs appear only in `design_assets`.
3. Delete one Sheet row and wait for the scheduled snapshot or run it manually.
Expected: the missing design becomes `active=false`.
4. Edit a design's category and verify it changes in Supabase.

## 6. Barcode mapping

1. Map a new barcode and scan it in the customer app.
2. Try scanning it under the wrong firm.
Expected: a clear firm mismatch message.
3. Remap the barcode and verify a `barcode_mapping_log` row is created.
4. Deactivate it and confirm customer lookup stops working.

## 7. Images

1. Open Network tools while loading a design.
2. Verify the browser calls `image-proxy`, not the base ImageKit URL.
3. Inspect customer table responses and confirm no `base_image_url` is present.
4. Generate a PDF and confirm thumbnails are low-resolution but identifiable.

## 8. Dashboard and password reset

1. A normal customer session calling `admin-api` must receive `ADMIN_REQUIRED`.
2. Admin login must show both customers and both firms.
3. Filter and export to Excel.
4. Reset customer A's password; old password must stop working and the temporary password must work.
5. Disable customer A; saving must fail with `CUSTOMER_ACCESS_DISABLED`.

## 9. Camera/device test

Test on the actual phones and browsers used on the exhibition floor:

- HTTPS GitHub Pages link.
- Rear-camera permission.
- Barcode focus distance and lighting.
- Manual barcode fallback.
- Repeated scans.
- Save on slow mobile data/Wi-Fi.
- PDF download on Android Chrome and iPhone Safari.
```

## `scripts/scaffold.sh`

```bash
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
```

## `supabase/.env.example`

```dotenv
# Public website origin(s), comma-separated. Example:
ALLOWED_ORIGINS=https://YOUR_GITHUB_USERNAME.github.io,http://localhost:8000

# Strong random secret used only by Google Apps Script -> sheet-sync.
SHEET_SYNC_SECRET=replace-with-at-least-32-random-characters

# ImageKit URL endpoint, e.g. https://ik.imagekit.io/your_imagekit_id
IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/your_imagekit_id

# Optional. Required only when ImageKit signed delivery/private files are enabled.
IMAGEKIT_PRIVATE_KEY=private_xxxxxxxxxxxxxxxxx

# Transformation strings used by the proxy. Named transformations are recommended,
# e.g. n-exhibition-thumb and n-exhibition-pdf. Raw transformation strings also work.
IMAGEKIT_THUMB_TRANSFORMATION=w-240,h-320,c-at_max,q-50,f-auto
IMAGEKIT_PDF_TRANSFORMATION=w-320,h-430,c-at_max,q-30,f-jpg
```

## `supabase/config.toml`

```toml
project_id = "maitri-office-exhibition"

[api]
enabled = true
port = 54321
schemas = ["public", "graphql_public"]
extra_search_path = ["public", "extensions"]
max_rows = 1000

[db]
port = 54322
major_version = 17

[studio]
enabled = true
port = 54323

[inbucket]
enabled = true
port = 54324

[auth]
enabled = true
site_url = "http://localhost:8000/app.html"
additional_redirect_urls = ["http://localhost:8000/**"]
jwt_expiry = 3600
enable_signup = true

[auth.email]
enable_signup = true
double_confirm_changes = false
enable_confirmations = false

[functions.sheet-sync]
verify_jwt = false

[functions.admin-api]
verify_jwt = false

[functions.image-proxy]
verify_jwt = false
```

## `supabase/functions/_shared/auth.ts`

```typescript
import type { User } from "npm:@supabase/supabase-js@2";
import { authClient } from "./supabase.ts";

export function bearerToken(request: Request): string {
  const header = request.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Error("AUTH_REQUIRED");
  return match[1].trim();
}

export async function requireUser(request: Request): Promise<User> {
  const token = bearerToken(request);
  const client = authClient();
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("INVALID_OR_EXPIRED_SESSION");
  return data.user;
}

export async function requireAdmin(request: Request): Promise<User> {
  const user = await requireUser(request);
  if (String(user.app_metadata?.role ?? "") !== "admin") {
    throw new Error("ADMIN_REQUIRED");
  }
  return user;
}
```

## `supabase/functions/_shared/cors.ts`

```typescript
function configuredOrigins(): string[] {
  return (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim().replace(/\/$/, ""))
    .filter(Boolean);
}

export function corsHeaders(request: Request): HeadersInit {
  const requestOrigin = (request.headers.get("origin") ?? "").replace(/\/$/, "");
  const allowed = configuredOrigins();
  const allowOrigin = allowed.length === 0
    ? "*"
    : allowed.includes(requestOrigin)
    ? requestOrigin
    : allowed[0];

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-sheet-sync-secret",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Expose-Headers": "content-type, content-length",
    "Vary": "Origin",
  };
}

export function optionsResponse(request: Request): Response {
  return new Response("ok", { headers: corsHeaders(request) });
}
```

## `supabase/functions/_shared/http.ts`

```typescript
import { corsHeaders } from "./cors.ts";

export function jsonResponse(request: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object") {
    const value = error as Record<string, unknown>;
    const parts = [value.message, value.details, value.hint, value.code]
      .filter((part) => part !== undefined && part !== null && String(part).trim() !== "")
      .map((part) => String(part).trim());
    if (parts.length) return Array.from(new Set(parts)).join(" | ");
    try {
      return JSON.stringify(value);
    } catch (_) {
      return "Unknown structured error";
    }
  }
  return String(error ?? "Unknown error");
}

export function clean(value: unknown): string {
  return String(value ?? "").trim();
}
```

## `supabase/functions/_shared/secure.ts`

```typescript
export function secureEqual(a: string, b: string): boolean {
  const aa = new TextEncoder().encode(a);
  const bb = new TextEncoder().encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i += 1) diff |= aa[i] ^ bb[i];
  return diff === 0;
}
```

## `supabase/functions/_shared/supabase.ts`

```typescript
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !key) throw new Error("Supabase service environment variables are missing");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { headers: { "x-application-name": "maitri-office-exhibition" } },
  });
}

export function authClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!url || !key) throw new Error("Supabase auth environment variables are missing");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
```

## `supabase/functions/admin-api/index.ts`

```typescript
import { optionsResponse } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

async function fetchAll(
  db: SupabaseClient,
  table: string,
  columns = "*",
  orderColumn?: string,
): Promise<any[]> {
  const output: any[] = [];
  const pageSize = 1000;
  let from = 0;
  while (true) {
    let query: any = db.from(table).select(columns);
    if (orderColumn) query = query.order(orderColumn, { ascending: true });
    const { data, error } = await query.range(from, from + pageSize - 1);
    if (error) throw error;
    const rows = data ?? [];
    output.push(...rows);
    if (rows.length < pageSize) break;
    from += pageSize;
  }
  return output;
}

function normalizePhone(value: unknown): string {
  let digits = clean(value).replace(/\D/g, "");
  if (digits.length === 10) digits = `91${digits}`;
  if (!/^91[6-9]\d{9}$/.test(digits)) throw new Error("Enter a valid Indian mobile number");
  return digits;
}

function groupSum<T>(rows: T[], keyFn: (row: T) => string, valueFn: (row: T) => number) {
  const map = new Map<string, number>();
  for (const row of rows) {
    const key = clean(keyFn(row)) || "Not specified";
    map.set(key, (map.get(key) ?? 0) + Number(valueFn(row) || 0));
  }
  return Array.from(map, ([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));
}

async function dashboard(db: SupabaseClient) {
  const [customers, orders, items] = await Promise.all([
    fetchAll(db, "customers", "id,phone_e164,company_name,contact_name,city,state,gstin,active,created_at,updated_at", "created_at"),
    fetchAll(db, "orders", "id,customer_id,firm,status,total_designs,total_pieces,version,created_at,updated_at", "created_at"),
    fetchAll(db, "order_items", "id,order_id,barcode,design_no,qty,category_snapshot,fabric_snapshot,color_snapshot,description_snapshot,created_at,updated_at", "created_at"),
  ]);

  const customerById = new Map(customers.map((row) => [row.id, row]));
  const orderById = new Map(orders.map((row) => [row.id, row]));
  const itemsByOrder = new Map<string, any[]>();
  for (const item of items) {
    const list = itemsByOrder.get(item.order_id) ?? [];
    list.push({
      id: item.id,
      barcode: item.barcode,
      designNo: item.design_no,
      qty: Number(item.qty) || 0,
      category: item.category_snapshot,
      fabric: item.fabric_snapshot,
      color: item.color_snapshot,
      description: item.description_snapshot,
    });
    itemsByOrder.set(item.order_id, list);
  }

  const orderRows = orders.map((order) => {
    const customer = customerById.get(order.customer_id) ?? {};
    return {
      id: order.id,
      customerId: order.customer_id,
      companyName: customer.company_name ?? "",
      contactName: customer.contact_name ?? "",
      phone: customer.phone_e164 ?? "",
      city: customer.city ?? "",
      state: customer.state ?? "",
      customerActive: customer.active !== false,
      firm: order.firm,
      status: order.status,
      totalDesigns: Number(order.total_designs) || 0,
      totalPieces: Number(order.total_pieces) || 0,
      version: Number(order.version) || 0,
      createdAt: order.created_at,
      updatedAt: order.updated_at,
      items: itemsByOrder.get(order.id) ?? [],
    };
  });

  const savedOrders = orderRows.filter((row) => row.totalDesigns > 0 || row.status === "Saved");
  const itemFacts = items.map((item) => {
    const order = orderById.get(item.order_id) ?? {};
    const customer = customerById.get(order.customer_id) ?? {};
    return {
      designNo: item.design_no,
      qty: Number(item.qty) || 0,
      category: item.category_snapshot,
      fabric: item.fabric_snapshot,
      color: item.color_snapshot,
      firm: order.firm ?? "",
      customerId: order.customer_id ?? "",
      companyName: customer.company_name ?? "",
      city: customer.city ?? "",
      state: customer.state ?? "",
    };
  });

  const customerTotals = new Map<string, { label: string; value: number; designs: Set<string> }>();
  const designCustomers = new Map<string, Set<string>>();
  for (const fact of itemFacts) {
    const current = customerTotals.get(fact.customerId) ?? {
      label: fact.companyName || "Unknown customer",
      value: 0,
      designs: new Set<string>(),
    };
    current.value += fact.qty;
    current.designs.add(fact.designNo);
    customerTotals.set(fact.customerId, current);

    const set = designCustomers.get(fact.designNo) ?? new Set<string>();
    set.add(fact.customerId);
    designCustomers.set(fact.designNo, set);
  }

  const topCustomers = Array.from(customerTotals.entries()).map(([customerId, value]) => ({
    customerId,
    label: value.label,
    value: value.value,
    designs: value.designs.size,
  })).sort((a, b) => b.value - a.value || a.label.localeCompare(b.label));

  const topDesigns = groupSum(itemFacts, (row) => row.designNo, (row) => row.qty)
    .map((row) => ({ ...row, customers: designCustomers.get(row.label)?.size ?? 0 }));

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      totalCustomers: customers.length,
      activeCustomers: customers.filter((row) => row.active).length,
      customersWithOrders: new Set(savedOrders.map((row) => row.customerId)).size,
      savedOrders: savedOrders.length,
      totalPieces: itemFacts.reduce((sum, row) => sum + row.qty, 0),
      uniqueDesigns: new Set(itemFacts.map((row) => row.designNo)).size,
      maitriPieces: itemFacts.filter((row) => row.firm === "Maitri").reduce((sum, row) => sum + row.qty, 0),
      niharikaPieces: itemFacts.filter((row) => row.firm === "Niharika").reduce((sum, row) => sum + row.qty, 0),
    },
    charts: {
      firmPieces: groupSum(itemFacts, (row) => row.firm, (row) => row.qty),
      statePieces: groupSum(itemFacts, (row) => row.state, (row) => row.qty),
      cityPieces: groupSum(itemFacts, (row) => row.city, (row) => row.qty),
      categoryPieces: groupSum(itemFacts, (row) => row.category, (row) => row.qty),
      fabricPieces: groupSum(itemFacts, (row) => row.fabric, (row) => row.qty),
      topDesigns: topDesigns.slice(0, 20),
      topCustomers: topCustomers.slice(0, 20),
    },
    customers: customers.map((row) => ({
      id: row.id,
      phone: row.phone_e164,
      companyName: row.company_name,
      contactName: row.contact_name,
      city: row.city,
      state: row.state,
      gstin: row.gstin,
      active: row.active,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })),
    orders: orderRows.sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt))),
  };
}

async function listDesigns(db: SupabaseClient) {
  const { data, error } = await db
    .from("designs")
    .select("design_no,firm,category,fabric,color,description,active,sync_version,updated_at")
    .order("design_no", { ascending: true });
  if (error) throw error;
  return (data ?? []).map((row) => ({
    designNo: row.design_no,
    firm: row.firm,
    category: row.category,
    fabric: row.fabric,
    color: row.color,
    description: row.description,
    active: row.active,
    syncVersion: row.sync_version,
    updatedAt: row.updated_at,
  }));
}

async function listMappings(db: SupabaseClient) {
  const { data, error } = await db
    .from("barcode_mappings")
    .select("barcode,design_no,active,mapped_at,updated_at,designs(firm,category,fabric,color)")
    .order("updated_at", { ascending: false })
    .limit(1000);
  if (error) throw error;
  return (data ?? []).map((row: any) => ({
    barcode: row.barcode,
    designNo: row.design_no,
    active: row.active,
    mappedAt: row.mapped_at,
    updatedAt: row.updated_at,
    firm: row.designs?.firm ?? "",
    category: row.designs?.category ?? "",
    fabric: row.designs?.fabric ?? "",
    color: row.designs?.color ?? "",
  }));
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    const admin = await requireAdmin(request);
    const db = serviceClient();
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action);

    if (action === "whoami") {
      return jsonResponse(request, { ok: true, data: { id: admin.id, email: admin.email, role: "admin" } });
    }

    if (action === "dashboard") {
      return jsonResponse(request, { ok: true, data: await dashboard(db) });
    }

    if (action === "listDesigns") {
      return jsonResponse(request, { ok: true, data: await listDesigns(db) });
    }

    if (action === "listMappings") {
      return jsonResponse(request, { ok: true, data: await listMappings(db) });
    }

    if (action === "mapBarcode") {
      const { data, error } = await db.rpc("admin_map_barcode", {
        p_barcode: clean(body.barcode),
        p_design_no: clean(body.designNo),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "mapBatch") {
      if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 300) {
        throw new Error("Provide 1 to 300 mapping rows");
      }
      const results = [];
      for (const raw of body.items) {
        const item = raw as Record<string, unknown>;
        try {
          const { data, error } = await db.rpc("admin_map_barcode", {
            p_barcode: clean(item.barcode),
            p_design_no: clean(item.designNo),
            p_admin_user_id: admin.id,
          });
          if (error) throw error;
          results.push({ ok: true, data });
        } catch (error) {
          results.push({ ok: false, barcode: clean(item.barcode), error: errorMessage(error) });
        }
      }
      return jsonResponse(request, { ok: true, data: { results } });
    }

    if (action === "deactivateBarcode") {
      const { data, error } = await db.rpc("admin_deactivate_barcode", {
        p_barcode: clean(body.barcode),
        p_admin_user_id: admin.id,
      });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "resetPassword") {
      const phone = normalizePhone(body.phone);
      const password = clean(body.newPassword);
      if (password.length < 8) throw new Error("New password must be at least 8 characters");
      const { data: customer, error: customerError } = await db
        .from("customers")
        .select("id,company_name,phone_e164")
        .eq("phone_e164", phone)
        .maybeSingle();
      if (customerError) throw customerError;
      if (!customer) throw new Error("Customer not found");
      const { error } = await db.auth.admin.updateUserById(customer.id, { password });
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: { customerId: customer.id, companyName: customer.company_name, phone: customer.phone_e164 },
      });
    }

    if (action === "setCustomerActive") {
      const customerId = clean(body.customerId);
      const active = Boolean(body.active);
      const { data, error } = await db
        .from("customers")
        .update({ active })
        .eq("id", customerId)
        .select("id,company_name,phone_e164,active")
        .single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "setOrderLocked") {
      const orderId = clean(body.orderId);
      const locked = Boolean(body.locked);
      const { data, error } = await db
        .from("orders")
        .update({ status: locked ? "Locked" : "Saved" })
        .eq("id", orderId)
        .select("id,firm,status,updated_at")
        .single();
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    return jsonResponse(request, { ok: false, error: `UNKNOWN_ACTION_${action}` }, 400);
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message === "ADMIN_REQUIRED" ? 403 : message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
```

## `supabase/functions/image-proxy/index.ts`

```typescript
import { corsHeaders, optionsResponse } from "../_shared/cors.ts";
import { requireUser } from "../_shared/auth.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

function bytesToHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha1Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  return bytesToHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message))).toLowerCase();
}

async function buildImageUrl(baseUrl: string, transformation: string): Promise<string> {
  const url = new URL(baseUrl);
  url.searchParams.delete("ik-s");
  url.searchParams.delete("ik-t");
  url.searchParams.set("tr", transformation);

  const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY") ?? "";
  if (!privateKey) return url.toString();

  const endpoint = (Deno.env.get("IMAGEKIT_URL_ENDPOINT") ?? "").replace(/\/$/, "");
  if (!endpoint) throw new Error("IMAGEKIT_URL_ENDPOINT_REQUIRED_FOR_SIGNING");

  const transformedUrl = url.toString();
  const endpointWithSlash = `${endpoint}/`;
  if (!transformedUrl.startsWith(endpointWithSlash)) {
    throw new Error("IMAGE_URL_DOES_NOT_MATCH_CONFIGURED_IMAGEKIT_ENDPOINT");
  }

  const expiry = Math.floor(Date.now() / 1000) + 300;
  const stringToSign = transformedUrl.slice(endpointWithSlash.length) + expiry;
  const signature = await hmacSha1Hex(privateKey, stringToSign);
  url.searchParams.set("ik-t", String(expiry));
  url.searchParams.set("ik-s", signature);
  return url.toString();
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    const user = await requireUser(request);
    const db = serviceClient();
    const body = await request.json().catch(() => ({}));
    const designNo = clean(body.designNo);
    const variant = clean(body.variant || "thumb").toLowerCase();
    if (!designNo) throw new Error("DESIGN_NO_REQUIRED");
    if (!['thumb', 'pdf'].includes(variant)) throw new Error("INVALID_IMAGE_VARIANT");

    const isAdmin = String(user.app_metadata?.role ?? "") === "admin";
    if (!isAdmin) {
      const { data: customer, error: customerError } = await db
        .from("customers")
        .select("active")
        .eq("id", user.id)
        .maybeSingle();
      if (customerError) throw customerError;
      if (!customer?.active) throw new Error("CUSTOMER_ACCESS_DISABLED");
    }

    const { data, error } = await db
      .from("designs")
      .select("design_no,active,design_assets(base_image_url)")
      .eq("design_no", designNo)
      .maybeSingle();
    if (error) throw error;
    if (!data || !data.active) throw new Error("ACTIVE_DESIGN_NOT_FOUND");

    const asset = Array.isArray((data as any).design_assets)
      ? (data as any).design_assets[0]
      : (data as any).design_assets;
    const baseUrl = clean(asset?.base_image_url);
    if (!baseUrl) throw new Error("IMAGE_NOT_AVAILABLE");

    const transformation = variant === "pdf"
      ? Deno.env.get("IMAGEKIT_PDF_TRANSFORMATION") ?? "w-320,h-430,c-at_max,q-30,f-jpg"
      : Deno.env.get("IMAGEKIT_THUMB_TRANSFORMATION") ?? "w-240,h-320,c-at_max,q-50,f-auto";

    const upstreamUrl = await buildImageUrl(baseUrl, transformation);
    const upstream = await fetch(upstreamUrl, {
      headers: { "User-Agent": "MaitriOfficeExhibitionImageProxy/1.0" },
      redirect: "follow",
    });
    if (!upstream.ok || !upstream.body) {
      throw new Error(`IMAGEKIT_FETCH_FAILED_${upstream.status}`);
    }

    return new Response(upstream.body, {
      status: 200,
      headers: {
        ...corsHeaders(request),
        "Content-Type": upstream.headers.get("content-type") ?? "image/jpeg",
        "Cache-Control": "private, max-age=300",
        "Content-Disposition": "inline",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message.includes("SESSION") || message === "AUTH_REQUIRED" ? 401 : message.includes("NOT_FOUND") ? 404 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
```

## `supabase/functions/sheet-sync/index.ts`

```typescript
import { optionsResponse } from "../_shared/cors.ts";
import { clean, errorMessage, jsonResponse } from "../_shared/http.ts";
import { secureEqual } from "../_shared/secure.ts";
import { serviceClient } from "../_shared/supabase.ts";

type ProductRow = {
  DesignNo: string;
  Firm: string;
  ImageURL: string;
  Category: string;
  Fabric: string;
  Color: string;
  Description: string;
  Active: boolean | string;
  UpdatedAt?: string;
};

function requireSecret(request: Request): void {
  const expected = Deno.env.get("SHEET_SYNC_SECRET") ?? "";
  const supplied = request.headers.get("x-sheet-sync-secret") ?? "";
  if (!expected || !secureEqual(expected, supplied)) throw new Error("SHEET_SYNC_AUTH_REQUIRED");
}

function normalizeRows(input: unknown): ProductRow[] {
  if (!Array.isArray(input)) throw new Error("ROWS_MUST_BE_AN_ARRAY");
  if (input.length > 5000) throw new Error("TOO_MANY_ROWS");

  const seen = new Set<string>();
  return input.map((raw, index) => {
    const row = (raw ?? {}) as Record<string, unknown>;
    const designNo = clean(row.DesignNo ?? row.design_no);
    const firm = clean(row.Firm ?? row.firm);
    if (!designNo) throw new Error(`Row ${index + 2}: DesignNo is required`);
    const key = designNo.toLowerCase();
    if (seen.has(key)) throw new Error(`Duplicate DesignNo in request: ${designNo}`);
    seen.add(key);

    return {
      DesignNo: designNo,
      Firm: firm,
      ImageURL: clean(row.ImageURL ?? row.image_url),
      Category: clean(row.Category ?? row.category),
      Fabric: clean(row.Fabric ?? row.fabric),
      Color: clean(row.Color ?? row.color),
      Description: clean(row.Description ?? row.description),
      Active: row.Active ?? row.active ?? true,
      UpdatedAt: clean(row.UpdatedAt ?? row.updated_at) || new Date().toISOString(),
    };
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return optionsResponse(request);
  if (request.method !== "POST") return jsonResponse(request, { ok: false, error: "POST_REQUIRED" }, 405);

  try {
    requireSecret(request);
    const body = await request.json().catch(() => ({}));
    const action = clean(body.action);
    const db = serviceClient();

    if (action === "ping") {
      const { count, error } = await db.from("designs").select("design_no", { count: "exact", head: true });
      if (error) throw error;
      return jsonResponse(request, {
        ok: true,
        data: { connected: true, designCount: count ?? 0, at: new Date().toISOString() },
      });
    }

    if (action === "syncRows") {
      const rows = normalizeRows(body.rows ?? []);
      const { data, error } = await db.rpc("upsert_product_rows", { p_rows: rows });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "fullSnapshot") {
      const rows = normalizeRows(body.rows ?? []);
      const { data, error } = await db.rpc("apply_product_snapshot", { p_rows: rows });
      if (error) throw error;
      return jsonResponse(request, { ok: true, data });
    }

    if (action === "getStatus") {
      const [{ count: designCount, error: designError }, { data: lastRun, error: runError }] = await Promise.all([
        db.from("designs").select("design_no", { count: "exact", head: true }),
        db.from("product_sync_runs").select("*").order("created_at", { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (designError) throw designError;
      if (runError) throw runError;
      return jsonResponse(request, {
        ok: true,
        data: { designCount: designCount ?? 0, lastRun: lastRun ?? null, at: new Date().toISOString() },
      });
    }

    return jsonResponse(request, { ok: false, error: `UNKNOWN_ACTION_${action}` }, 400);
  } catch (error) {
    console.error(error);
    const message = errorMessage(error);
    const status = message.includes("AUTH_REQUIRED") ? 401 : 500;
    return jsonResponse(request, { ok: false, error: message }, status);
  }
});
```

## `supabase/migrations/202607150001_schema.sql`

```sql
-- Maitri × Niharika self-service exhibition system
-- Core relational schema. Apply before the remaining numbered migrations.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.system_settings (
  singleton boolean primary key default true check (singleton),
  event_name text not null default 'Maitri × Niharika Office Exhibition',
  event_start_date date not null default date '2026-07-19',
  event_end_date date not null default date '2026-07-21',
  registration_enabled boolean not null default true,
  registration_access_code_hash text,
  customer_email_domain text not null default 'customers.maitri.local',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.system_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table public.customers (
  id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null unique check (phone_e164 ~ '^91[6-9][0-9]{9}$'),
  company_name text not null check (length(btrim(company_name)) between 2 and 120),
  contact_name text not null check (length(btrim(contact_name)) between 2 and 100),
  city text not null default '',
  state text not null default '',
  gstin text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.designs (
  design_no text primary key,
  firm text not null check (firm in ('Maitri', 'Niharika', 'Both')),
  category text not null default '',
  fabric text not null default '',
  color text not null default '',
  description text not null default '',
  active boolean not null default true,
  source_updated_at timestamptz,
  sync_version bigint not null default 1 check (sync_version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(design_no)) between 1 and 80)
);

-- Kept separate so customer-facing SELECT access never exposes the base image URL.
create table public.design_assets (
  design_no text primary key references public.designs(design_no) on update cascade on delete cascade,
  base_image_url text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.barcode_mappings (
  barcode text primary key,
  design_no text not null references public.designs(design_no) on update cascade on delete restrict,
  active boolean not null default true,
  mapped_by uuid references auth.users(id) on delete set null,
  mapped_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(barcode)) between 1 and 160)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  firm text not null check (firm in ('Maitri', 'Niharika')),
  status text not null default 'Draft' check (status in ('Draft', 'Saved', 'Locked')),
  total_designs integer not null default 0 check (total_designs >= 0),
  total_pieces integer not null default 0 check (total_pieces >= 0),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, firm)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  barcode text not null default '',
  design_no text not null references public.designs(design_no) on update cascade on delete restrict,
  qty integer not null check (qty between 1 and 9999),
  category_snapshot text not null default '',
  fabric_snapshot text not null default '',
  color_snapshot text not null default '',
  description_snapshot text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id, design_no)
);

create table public.order_save_requests (
  request_id uuid primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  previous_version integer not null,
  new_version integer not null,
  design_count integer not null default 0,
  total_pieces integer not null default 0,
  result text not null check (result in ('Success', 'Conflict', 'Failed')),
  response_json jsonb,
  error text not null default '',
  created_at timestamptz not null default now()
);

create table public.barcode_mapping_log (
  id bigint generated always as identity primary key,
  barcode text not null,
  previous_design_no text,
  new_design_no text,
  action text not null check (action in ('Created', 'Remapped', 'Deactivated', 'Reactivated')),
  admin_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.product_sync_runs (
  id bigint generated always as identity primary key,
  source text not null default 'GOOGLE_SHEETS',
  mode text not null check (mode in ('ROWS', 'FULL_SNAPSHOT')),
  received_count integer not null default 0,
  upserted_count integer not null default 0,
  deactivated_count integer not null default 0,
  status text not null check (status in ('Success', 'Failed')),
  error text not null default '',
  created_at timestamptz not null default now()
);

create index orders_customer_idx on public.orders(customer_id, firm);
create index orders_updated_idx on public.orders(updated_at desc);
create index order_items_order_idx on public.order_items(order_id);
create index order_items_design_idx on public.order_items(design_no);
create index designs_active_firm_idx on public.designs(active, firm);
create index barcode_mappings_design_idx on public.barcode_mappings(design_no) where active;
create index customers_company_idx on public.customers(lower(company_name));
create index customers_phone_idx on public.customers(phone_e164);
create index save_requests_customer_idx on public.order_save_requests(customer_id, created_at desc);

create trigger system_settings_updated_at
before update on public.system_settings
for each row execute function public.set_updated_at();

create trigger customers_updated_at
before update on public.customers
for each row execute function public.set_updated_at();

create trigger designs_updated_at
before update on public.designs
for each row execute function public.set_updated_at();

create trigger design_assets_updated_at
before update on public.design_assets
for each row execute function public.set_updated_at();

create trigger barcode_mappings_updated_at
before update on public.barcode_mappings
for each row execute function public.set_updated_at();

create trigger orders_updated_at
before update on public.orders
for each row execute function public.set_updated_at();

create trigger order_items_updated_at
before update on public.order_items
for each row execute function public.set_updated_at();

comment on table public.design_assets is
'Private base ImageKit URLs. Never grant anon/authenticated SELECT; image-proxy reads with service_role.';
```

## `supabase/migrations/202607150002_auth_and_rls.sql`

```sql
-- Customer provisioning, admin helpers, grants and Row-Level Security.

create or replace function public.is_admin_user(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = p_user_id
      and coalesce(u.raw_app_meta_data ->> 'role', '') = 'admin'
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_settings public.system_settings%rowtype;
  v_phone text;
  v_company text;
  v_contact text;
  v_city text;
  v_state text;
  v_gstin text;
  v_access_code text;
begin
  select * into v_settings from public.system_settings where singleton = true;

  -- Real-email admin users are intentionally not customer profiles.
  if split_part(lower(coalesce(new.email, '')), '@', 2) <> lower(v_settings.customer_email_domain) then
    return new;
  end if;

  if not v_settings.registration_enabled then
    raise exception 'REGISTRATION_CLOSED';
  end if;

  v_phone := regexp_replace(coalesce(new.raw_user_meta_data ->> 'phone_e164', ''), '\D', '', 'g');
  if v_phone !~ '^91[6-9][0-9]{9}$' then
    raise exception 'INVALID_CUSTOMER_PHONE';
  end if;

  if split_part(lower(new.email), '@', 1) <> v_phone then
    raise exception 'PHONE_EMAIL_MISMATCH';
  end if;

  if v_settings.registration_access_code_hash is not null then
    v_access_code := coalesce(new.raw_user_meta_data ->> 'access_code', '');
    if encode(extensions.digest(v_access_code, 'sha256'), 'hex') <> v_settings.registration_access_code_hash then
      raise exception 'INVALID_EXHIBITION_ACCESS_CODE';
    end if;
  end if;

  v_company := btrim(coalesce(new.raw_user_meta_data ->> 'company_name', ''));
  v_contact := btrim(coalesce(new.raw_user_meta_data ->> 'contact_name', ''));
  v_city := btrim(coalesce(new.raw_user_meta_data ->> 'city', ''));
  v_state := btrim(coalesce(new.raw_user_meta_data ->> 'state', ''));
  v_gstin := upper(btrim(coalesce(new.raw_user_meta_data ->> 'gstin', '')));

  if length(v_company) < 2 then raise exception 'COMPANY_NAME_REQUIRED'; end if;
  if length(v_contact) < 2 then raise exception 'CONTACT_NAME_REQUIRED'; end if;

  insert into public.customers(id, phone_e164, company_name, contact_name, city, state, gstin)
  values (new.id, v_phone, v_company, v_contact, v_city, v_state, v_gstin);

  insert into public.orders(customer_id, firm, status)
  values
    (new.id, 'Maitri', 'Draft'),
    (new.id, 'Niharika', 'Draft');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.system_settings enable row level security;
alter table public.customers enable row level security;
alter table public.designs enable row level security;
alter table public.design_assets enable row level security;
alter table public.barcode_mappings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_save_requests enable row level security;
alter table public.barcode_mapping_log enable row level security;
alter table public.product_sync_runs enable row level security;

create policy customers_select_own
on public.customers for select
to authenticated
using (id = auth.uid());

create policy customers_update_own
on public.customers for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy designs_read_active
on public.designs for select
to authenticated
using (active = true);

create policy barcode_mappings_read_active
on public.barcode_mappings for select
to authenticated
using (
  active = true
  and exists (
    select 1 from public.designs d
    where d.design_no = barcode_mappings.design_no
      and d.active = true
  )
);

create policy orders_select_own
on public.orders for select
to authenticated
using (customer_id = auth.uid());

create policy order_items_select_own
on public.order_items for select
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.customer_id = auth.uid()
  )
);

-- Start from least privilege. Customer writes happen only through audited RPCs.
revoke all on public.system_settings from anon, authenticated;
revoke all on public.customers from anon, authenticated;
revoke all on public.designs from anon, authenticated;
revoke all on public.design_assets from anon, authenticated;
revoke all on public.barcode_mappings from anon, authenticated;
revoke all on public.orders from anon, authenticated;
revoke all on public.order_items from anon, authenticated;
revoke all on public.order_save_requests from anon, authenticated;
revoke all on public.barcode_mapping_log from anon, authenticated;
revoke all on public.product_sync_runs from anon, authenticated;

-- RLS still applies to every granted read.
grant select on public.customers to authenticated;
grant update (company_name, contact_name, city, state, gstin) on public.customers to authenticated;
grant select on public.designs to authenticated;
grant select on public.barcode_mappings to authenticated;
grant select on public.orders to authenticated;
grant select on public.order_items to authenticated;

revoke all on function public.is_admin_user(uuid) from public, anon, authenticated;
grant execute on function public.is_admin_user(uuid) to authenticated, service_role;
```

## `supabase/migrations/202607150003_customer_functions.sql`

```sql
-- Customer-facing PostgreSQL RPCs. These are called directly by supabase-js.

create or replace function public.lookup_barcode(p_barcode text)
returns table (
  barcode text,
  design_no text,
  firm text,
  category text,
  fabric text,
  color text,
  description text
)
language sql
stable
set search_path = public
as $$
  select
    bm.barcode,
    d.design_no,
    d.firm,
    d.category,
    d.fabric,
    d.color,
    d.description
  from public.barcode_mappings bm
  join public.designs d on d.design_no = bm.design_no
  where bm.barcode = btrim(p_barcode)
    and bm.active = true
    and d.active = true
  limit 1;
$$;

create or replace function public.order_state_json(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', o.id,
    'firm', o.firm,
    'status', o.status,
    'version', o.version,
    'totalDesigns', o.total_designs,
    'totalPieces', o.total_pieces,
    'createdAt', o.created_at,
    'updatedAt', o.updated_at,
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'barcode', i.barcode,
          'designNo', i.design_no,
          'qty', i.qty,
          'category', i.category_snapshot,
          'fabric', i.fabric_snapshot,
          'color', i.color_snapshot,
          'description', i.description_snapshot
        ) order by i.created_at, i.design_no
      )
      from public.order_items i
      where i.order_id = o.id
    ), '[]'::jsonb)
  )
  from public.orders o
  where o.id = p_order_id;
$$;

create or replace function public.get_my_order_state(p_firm text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;

  select id into v_order_id
  from public.orders
  where customer_id = auth.uid() and firm = p_firm;

  if v_order_id is null then raise exception 'ORDER_NOT_FOUND'; end if;
  return public.order_state_json(v_order_id);
end;
$$;

create or replace function public.save_my_order(
  p_firm text,
  p_base_version integer,
  p_items jsonb,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_customer public.customers%rowtype;
  v_order public.orders%rowtype;
  v_existing public.order_save_requests%rowtype;
  v_item jsonb;
  v_design public.designs%rowtype;
  v_design_no text;
  v_barcode text;
  v_qty integer;
  v_seen text[] := array[]::text[];
  v_normalized jsonb := '[]'::jsonb;
  v_design_count integer := 0;
  v_total_pieces integer := 0;
  v_new_version integer;
  v_response jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_firm not in ('Maitri', 'Niharika') then raise exception 'INVALID_FIRM'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'ITEMS_MUST_BE_AN_ARRAY';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 500 then
    raise exception 'TOO_MANY_ORDER_ITEMS';
  end if;

  select * into v_existing
  from public.order_save_requests
  where request_id = p_request_id;

  if found then
    if v_existing.customer_id <> v_user_id then raise exception 'REQUEST_ID_OWNERSHIP_ERROR'; end if;
    return v_existing.response_json;
  end if;

  select * into v_customer
  from public.customers
  where id = v_user_id;

  if not found or not v_customer.active then raise exception 'CUSTOMER_ACCESS_DISABLED'; end if;

  select * into v_order
  from public.orders
  where customer_id = v_user_id and firm = p_firm
  for update;

  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.status = 'Locked' then raise exception 'ORDER_LOCKED'; end if;

  if coalesce(p_base_version, 0) <> v_order.version then
    v_response := jsonb_build_object(
      'ok', false,
      'code', 'ORDER_VERSION_CONFLICT',
      'message', 'This order changed in another tab or device. Reload the latest version before saving.',
      'order', public.order_state_json(v_order.id)
    );

    insert into public.order_save_requests(
      request_id, order_id, customer_id, previous_version, new_version,
      design_count, total_pieces, result, response_json, error
    ) values (
      p_request_id, v_order.id, v_user_id, coalesce(p_base_version, 0), v_order.version,
      v_order.total_designs, v_order.total_pieces, 'Conflict', v_response, 'ORDER_VERSION_CONFLICT'
    );
    return v_response;
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_item ->> 'designNo', v_item ->> 'design_no', ''));
    v_barcode := btrim(coalesce(v_item ->> 'barcode', ''));

    begin
      v_qty := (v_item ->> 'qty')::integer;
    exception when others then
      raise exception 'INVALID_QUANTITY_FOR_%', coalesce(nullif(v_design_no, ''), 'ITEM');
    end;

    if v_design_no = '' then raise exception 'DESIGN_NUMBER_REQUIRED'; end if;
    if v_qty < 1 or v_qty > 9999 then raise exception 'INVALID_QUANTITY_FOR_%', v_design_no; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_%', v_design_no; end if;

    select * into v_design
    from public.designs
    where design_no = v_design_no and active = true;

    if not found then raise exception 'INACTIVE_OR_UNKNOWN_DESIGN_%', v_design_no; end if;
    if v_design.firm not in (p_firm, 'Both') then
      raise exception 'DESIGN_%_DOES_NOT_BELONG_TO_%', v_design_no, p_firm;
    end if;

    v_seen := array_append(v_seen, v_design_no);
    v_design_count := v_design_count + 1;
    v_total_pieces := v_total_pieces + v_qty;
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'barcode', v_barcode,
      'designNo', v_design.design_no,
      'qty', v_qty,
      'category', v_design.category,
      'fabric', v_design.fabric,
      'color', v_design.color,
      'description', v_design.description
    ));
  end loop;

  delete from public.order_items where order_id = v_order.id;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into public.order_items(
      order_id, barcode, design_no, qty,
      category_snapshot, fabric_snapshot, color_snapshot, description_snapshot
    ) values (
      v_order.id,
      coalesce(v_item ->> 'barcode', ''),
      v_item ->> 'designNo',
      (v_item ->> 'qty')::integer,
      coalesce(v_item ->> 'category', ''),
      coalesce(v_item ->> 'fabric', ''),
      coalesce(v_item ->> 'color', ''),
      coalesce(v_item ->> 'description', '')
    );
  end loop;

  v_new_version := v_order.version + 1;
  update public.orders
  set
    status = case when v_design_count = 0 then 'Draft' else 'Saved' end,
    total_designs = v_design_count,
    total_pieces = v_total_pieces,
    version = v_new_version,
    updated_at = now()
  where id = v_order.id;

  v_response := jsonb_build_object(
    'ok', true,
    'code', 'SAVED',
    'message', 'Order saved.',
    'order', public.order_state_json(v_order.id)
  );

  insert into public.order_save_requests(
    request_id, order_id, customer_id, previous_version, new_version,
    design_count, total_pieces, result, response_json
  ) values (
    p_request_id, v_order.id, v_user_id, v_order.version, v_new_version,
    v_design_count, v_total_pieces, 'Success', v_response
  );

  return v_response;
end;
$$;

revoke all on function public.lookup_barcode(text) from public, anon, authenticated;
revoke all on function public.order_state_json(uuid) from public, anon, authenticated;
revoke all on function public.get_my_order_state(text) from public, anon, authenticated;
revoke all on function public.save_my_order(text, integer, jsonb, uuid) from public, anon, authenticated;

grant execute on function public.lookup_barcode(text) to authenticated;
grant execute on function public.get_my_order_state(text) to authenticated;
grant execute on function public.save_my_order(text, integer, jsonb, uuid) to authenticated;
grant execute on function public.order_state_json(uuid) to service_role;
```

## `supabase/migrations/202607150004_product_sync_functions.sql`

```sql
-- Service-role-only product master synchronization functions.

create or replace function public.normalize_product_firm(p_value text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare v text := lower(btrim(coalesce(p_value, '')));
begin
  if v = 'maitri' then return 'Maitri'; end if;
  if v = 'niharika' then return 'Niharika'; end if;
  if v in ('both', 'maitri/niharika', 'maitri & niharika', 'maitri and niharika') then return 'Both'; end if;
  raise exception 'INVALID_PRODUCT_FIRM_%', p_value;
end;
$$;

create or replace function public.parse_sheet_boolean(p_value text, p_default boolean default true)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when btrim(coalesce(p_value, '')) = '' then p_default
    when lower(btrim(p_value)) in ('true','yes','y','1','active') then true
    when lower(btrim(p_value)) in ('false','no','n','0','inactive') then false
    else p_default
  end;
$$;

create or replace function public.upsert_product_rows(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row jsonb;
  v_design_no text;
  v_count integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;

    insert into public.designs(
      design_no, firm, category, fabric, color, description, active, source_updated_at
    ) values (
      v_design_no,
      public.normalize_product_firm(coalesce(v_row ->> 'Firm', v_row ->> 'firm')),
      btrim(coalesce(v_row ->> 'Category', v_row ->> 'category', '')),
      btrim(coalesce(v_row ->> 'Fabric', v_row ->> 'fabric', '')),
      btrim(coalesce(v_row ->> 'Color', v_row ->> 'color', '')),
      btrim(coalesce(v_row ->> 'Description', v_row ->> 'description', '')),
      public.parse_sheet_boolean(coalesce(v_row ->> 'Active', v_row ->> 'active'), true),
      coalesce(nullif(coalesce(v_row ->> 'UpdatedAt', v_row ->> 'updated_at', ''), '')::timestamptz, now())
    )
    on conflict (design_no) do update set
      firm = excluded.firm,
      category = excluded.category,
      fabric = excluded.fabric,
      color = excluded.color,
      description = excluded.description,
      active = excluded.active,
      source_updated_at = excluded.source_updated_at,
      sync_version = public.designs.sync_version + 1,
      updated_at = now()
    where (
      public.designs.firm, public.designs.category, public.designs.fabric,
      public.designs.color, public.designs.description, public.designs.active,
      public.designs.source_updated_at
    ) is distinct from (
      excluded.firm, excluded.category, excluded.fabric, excluded.color,
      excluded.description, excluded.active, excluded.source_updated_at
    );

    insert into public.design_assets(design_no, base_image_url)
    values (
      v_design_no,
      btrim(coalesce(v_row ->> 'ImageURL', v_row ->> 'image_url', ''))
    )
    on conflict (design_no) do update set
      base_image_url = excluded.base_image_url,
      updated_at = now()
    where public.design_assets.base_image_url is distinct from excluded.base_image_url;

    v_count := v_count + 1;
  end loop;

  insert into public.product_sync_runs(mode, received_count, upserted_count, status)
  values ('ROWS', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), v_count, 'Success');

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', v_count,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('ROWS', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

create or replace function public.apply_product_snapshot(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_seen text[] := array[]::text[];
  v_row jsonb;
  v_design_no text;
  v_deactivated integer := 0;
  v_started timestamptz := clock_timestamp();
begin
  if jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) <> 'array' then
    raise exception 'ROWS_MUST_BE_AN_ARRAY';
  end if;

  -- Validate duplicate/blank keys before changing the master.
  for v_row in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_design_no := btrim(coalesce(v_row ->> 'DesignNo', v_row ->> 'design_no', ''));
    if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
    if v_design_no = any(v_seen) then raise exception 'DUPLICATE_DESIGN_NO_%', v_design_no; end if;
    v_seen := array_append(v_seen, v_design_no);
  end loop;

  v_result := public.upsert_product_rows(p_rows);

  update public.designs
  set active = false, sync_version = sync_version + 1, updated_at = now()
  where active = true
    and not (design_no = any(v_seen));
  get diagnostics v_deactivated = row_count;

  insert into public.product_sync_runs(mode, received_count, upserted_count, deactivated_count, status)
  values (
    'FULL_SNAPSHOT',
    jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    coalesce((v_result ->> 'upserted')::integer, 0),
    v_deactivated,
    'Success'
  );

  return jsonb_build_object(
    'received', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'upserted', coalesce((v_result ->> 'upserted')::integer, 0),
    'deactivated', v_deactivated,
    'durationMs', floor(extract(epoch from (clock_timestamp() - v_started)) * 1000),
    'at', now()
  );
exception when others then
  insert into public.product_sync_runs(mode, received_count, status, error)
  values ('FULL_SNAPSHOT', case when jsonb_typeof(p_rows) = 'array' then jsonb_array_length(p_rows) else 0 end, 'Failed', sqlerrm);
  raise;
end;
$$;

revoke all on function public.normalize_product_firm(text) from public, anon, authenticated;
revoke all on function public.parse_sheet_boolean(text, boolean) from public, anon, authenticated;
revoke all on function public.upsert_product_rows(jsonb) from public, anon, authenticated;
revoke all on function public.apply_product_snapshot(jsonb) from public, anon, authenticated;

grant execute on function public.upsert_product_rows(jsonb) to service_role;
grant execute on function public.apply_product_snapshot(jsonb) to service_role;
```

## `supabase/migrations/202607150005_admin_support.sql`

```sql
-- Server-side helpers used by admin-api. Browser customers receive no grants.

create or replace function public.admin_map_barcode(
  p_barcode text,
  p_design_no text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barcode text := btrim(coalesce(p_barcode, ''));
  v_design_no text := btrim(coalesce(p_design_no, ''));
  v_existing public.barcode_mappings%rowtype;
  v_action text;
begin
  if v_barcode = '' then raise exception 'BARCODE_REQUIRED'; end if;
  if v_design_no = '' then raise exception 'DESIGN_NO_REQUIRED'; end if;
  if not exists (select 1 from public.designs where design_no = v_design_no and active = true) then
    raise exception 'ACTIVE_DESIGN_NOT_FOUND';
  end if;

  select * into v_existing from public.barcode_mappings where barcode = v_barcode for update;

  if found then
    v_action := case
      when v_existing.design_no <> v_design_no then 'Remapped'
      when not v_existing.active then 'Reactivated'
      else 'Remapped'
    end;

    update public.barcode_mappings
    set design_no = v_design_no, active = true, mapped_by = p_admin_user_id, updated_at = now()
    where barcode = v_barcode;
  else
    v_action := 'Created';
    insert into public.barcode_mappings(barcode, design_no, mapped_by)
    values (v_barcode, v_design_no, p_admin_user_id);
  end if;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (
    v_barcode,
    case when v_existing.barcode is null then null else v_existing.design_no end,
    v_design_no,
    v_action,
    p_admin_user_id
  );

  return jsonb_build_object('barcode', v_barcode, 'designNo', v_design_no, 'action', v_action);
end;
$$;

create or replace function public.admin_deactivate_barcode(
  p_barcode text,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.barcode_mappings%rowtype;
begin
  select * into v_row from public.barcode_mappings where barcode = btrim(p_barcode) for update;
  if not found then raise exception 'BARCODE_NOT_FOUND'; end if;

  update public.barcode_mappings set active = false, mapped_by = p_admin_user_id, updated_at = now()
  where barcode = v_row.barcode;

  insert into public.barcode_mapping_log(
    barcode, previous_design_no, new_design_no, action, admin_user_id
  ) values (v_row.barcode, v_row.design_no, v_row.design_no, 'Deactivated', p_admin_user_id);

  return jsonb_build_object('barcode', v_row.barcode, 'designNo', v_row.design_no, 'active', false);
end;
$$;

revoke all on function public.admin_map_barcode(text, text, uuid) from public, anon, authenticated;
revoke all on function public.admin_deactivate_barcode(text, uuid) from public, anon, authenticated;
grant execute on function public.admin_map_barcode(text, text, uuid) to service_role;
grant execute on function public.admin_deactivate_barcode(text, uuid) to service_role;
```

## `supabase/migrations/202607150006_seed.sql`

```sql
-- Safe seed/configuration defaults. No demo customer or order data is inserted.

update public.system_settings
set
  event_name = 'Maitri × Niharika Office Exhibition',
  event_start_date = date '2026-07-19',
  event_end_date = date '2026-07-21',
  registration_enabled = true,
  customer_email_domain = 'customers.maitri.local'
where singleton = true;

-- Optional sample products are deliberately commented out.
-- Add real products through the ProductMaster Google Sheet instead.
-- insert into public.designs(design_no, firm, category, fabric, color, description, active)
-- values ('MT-DEMO-001', 'Maitri', 'Kurta Set', 'Cotton', 'Blue', 'Demo only', true);
```

## `templates/BarcodeMappings_Import.csv`

```csv
Barcode,DesignNo
8900000000001,MT-EXAMPLE-001
8900000000002,NH-EXAMPLE-001
```

## `templates/Maitri_Niharika_Product_Master.xlsx`

Binary Excel workbook. Use the supplied file rather than copying text.

## `templates/ProductMaster.csv`

```csv
DesignNo,Firm,ImageURL,Category,Fabric,Color,Description,Active
MT-EXAMPLE-001,Maitri,https://ik.imagekit.io/YOUR_ID/path/example.jpg,Kurta Set,Cotton,Blue,Delete this example before live sync,TRUE
NH-EXAMPLE-001,Niharika,https://ik.imagekit.io/YOUR_ID/path/example-2.jpg,Suit Set,Viscose,Pink,Delete this example before live sync,FALSE
```

## `web/.nojekyll`

```text

```

## `web/app.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#225E63">
  <title>Maitri × Niharika Exhibition Orders</title>
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/html5-qrcode/2.3.8/html5-qrcode.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.2/jspdf.umd.min.js"></script>
  <style>
    :root{--teal:#225E63;--teal2:#2B7379;--foam:#E8F2F1;--warm:#F7F3EA;--ink:#33271B;--muted:#747B78;--line:#DFE6E3;--orange:#FF9700;--red:#C81E1E;--green:#15803D;--white:#fff}
    *{box-sizing:border-box;margin:0;-webkit-tap-highlight-color:transparent}html,body{min-height:100%;background:linear-gradient(#FAF8F2,#F7F3EA);color:var(--ink);font-family:Inter,system-ui,-apple-system,sans-serif}button,input,select,textarea{font:inherit}.hidden{display:none!important}
    .top{position:sticky;top:0;z-index:50;min-height:62px;display:flex;align-items:center;gap:10px;padding:9px 14px;background:rgba(255,255,255,.96);border-bottom:1px solid var(--line);backdrop-filter:blur(12px)}.brand{font-weight:850;color:var(--teal);letter-spacing:.02em}.brand small{display:block;color:var(--muted);font-size:9px;font-weight:650;letter-spacing:.12em;text-transform:uppercase}.top-actions{margin-left:auto;display:flex;gap:7px}.icon-btn{min-height:38px;padding:0 11px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--teal);font-size:12px;font-weight:750}
    main{width:min(100%,680px);margin:0 auto;padding:16px 12px 34px}.hero{padding:20px;border-radius:18px;background:linear-gradient(135deg,var(--teal),#17494D);color:#fff;box-shadow:0 15px 34px rgba(34,94,99,.18)}.hero h1{font-size:23px}.hero p{margin-top:7px;color:rgba(255,255,255,.8);font-size:12px;line-height:1.55}
    .card{margin-top:13px;padding:16px;border:1px solid var(--line);border-radius:15px;background:#fff;box-shadow:0 6px 18px rgba(34,94,99,.06)}.card h2{color:var(--teal);font-size:15px}.copy{margin-top:4px;color:var(--muted);font-size:11px;line-height:1.5}label{display:block;margin:12px 0 5px;color:#4D5552;font-size:10px;font-weight:800;letter-spacing:.045em;text-transform:uppercase}input,select,textarea{width:100%;border:1px solid #D8E1DE;border-radius:10px;background:#fff;color:var(--ink);font-size:16px}input,select{min-height:47px;padding:0 13px}textarea{min-height:80px;padding:11px 13px}input:focus,select:focus,textarea:focus{outline:none;border-color:var(--teal2);box-shadow:0 0 0 3px rgba(43,115,121,.13)}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px}.phone{display:flex;gap:8px}.prefix{width:62px;min-width:62px;display:grid;place-items:center;border:1px solid #D8E1DE;border-radius:10px;background:var(--foam);color:var(--teal);font-weight:800}.btn{width:100%;min-height:48px;margin-top:13px;border:0;border-radius:10px;background:var(--teal);color:#fff;font-size:14px;font-weight:800;cursor:pointer}.btn.secondary{border:1px solid var(--teal);background:#fff;color:var(--teal)}.btn.danger{background:var(--red)}.btn:disabled{background:#E7EBE9;color:#949A97;cursor:not-allowed}.switch{display:flex;gap:4px;margin-top:12px;padding:4px;border-radius:13px;background:var(--foam)}.switch button{flex:1;min-height:40px;border:0;border-radius:9px;background:transparent;color:var(--teal);font-size:12px;font-weight:800}.switch button.active{background:#fff;box-shadow:0 2px 8px rgba(34,94,99,.12)}
    .firm-tabs{position:sticky;top:63px;z-index:30;display:grid;grid-template-columns:1fr 1fr;gap:5px;margin:0 -2px 11px;padding:5px;border:1px solid var(--line);border-radius:14px;background:rgba(255,255,255,.96);backdrop-filter:blur(10px)}.firm-tab{min-height:48px;border:0;border-radius:10px;background:transparent;color:var(--muted);font-weight:800}.firm-tab.active{background:var(--teal);color:#fff}.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:11px}.metric{padding:11px;border-radius:11px;background:var(--foam);text-align:center}.metric b{display:block;color:var(--teal);font-size:20px}.metric span{font-size:9px;color:var(--muted);text-transform:uppercase}
    .scan-actions{display:grid;grid-template-columns:1fr auto;gap:8px;align-items:end}.scan-actions .btn{width:auto;min-width:110px;margin:0}.reader{display:none;margin-top:12px;overflow:hidden;border-radius:13px}.reader.open{display:block}.notice{margin-top:10px;padding:10px 12px;border-radius:10px;background:#FFF5DF;color:#8A5A09;font-size:11px;line-height:1.45}.notice.error{background:#FEE2E2;color:#991B1B}.notice.success{background:#DCFCE7;color:#166534}
    .items{display:grid;gap:10px;margin-top:12px}.item{display:grid;grid-template-columns:88px minmax(0,1fr);gap:11px;padding:11px;border:1px solid var(--line);border-radius:13px;background:#fff}.thumb{width:88px;height:116px;border-radius:10px;background:#EEF2F0 center/cover no-repeat;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;pointer-events:auto}.item h3{font-size:14px;color:var(--teal)}.meta{margin-top:4px;color:var(--muted);font-size:10px;line-height:1.45}.qty{display:flex;align-items:center;gap:5px;margin-top:9px}.qty button{width:36px;height:36px;border:1px solid var(--line);border-radius:9px;background:#fff;color:var(--teal);font-size:18px;font-weight:800}.qty input{width:58px;min-height:36px;height:36px;padding:0;text-align:center;font-weight:800}.remove{margin-left:auto!important;color:var(--red)!important}.savebar{position:sticky;bottom:8px;z-index:25;display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:14px;padding:8px;border:1px solid var(--line);border-radius:14px;background:rgba(255,255,255,.96);box-shadow:0 10px 30px rgba(34,55,52,.14);backdrop-filter:blur(10px)}.savebar .btn{margin:0}.empty{padding:28px 12px;border:1px dashed #BCD0CB;border-radius:13px;background:#F8FBFA;color:var(--muted);font-size:12px;text-align:center}
    .toast{position:fixed;left:50%;top:72px;z-index:200;display:none;max-width:90%;padding:10px 16px;border-radius:22px;background:var(--ink);color:#fff;font-size:12px;transform:translateX(-50%);box-shadow:0 9px 25px rgba(0,0,0,.18)}.toast.open{display:block}.toast.error{background:#B91C1C}.toast.success{background:#166534}.loading{position:fixed;inset:0;z-index:180;display:none;place-items:center;background:rgba(25,31,29,.46)}.loading.open{display:grid}.loader-card{padding:22px 28px;border-radius:15px;background:#fff;color:var(--teal);font-weight:800}.spinner{width:28px;height:28px;margin:0 auto 10px;border:3px solid var(--foam);border-top-color:var(--teal);border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
    .config-warning{padding:12px;background:#FEE2E2;color:#991B1B;font-size:12px;text-align:center}.account-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.small{font-size:11px}.auth-link{margin-top:12px;color:var(--teal);font-size:12px;text-align:center;cursor:pointer;font-weight:750}
    @media(max-width:480px){.grid2,.account-grid{grid-template-columns:1fr}.item{grid-template-columns:78px minmax(0,1fr)}.thumb{width:78px;height:104px}.scan-actions{grid-template-columns:1fr}.scan-actions .btn{width:100%}}
  </style>
</head>
<body oncontextmenu="return false">
  <div id="config-warning" class="config-warning hidden">Replace the Supabase placeholders in this file before publishing.</div>
  <header class="top hidden" id="app-top">
    <div class="brand">Maitri × Niharika<small>Self-service exhibition orders</small></div>
    <div class="top-actions"><button class="icon-btn" id="account-btn">Account</button><button class="icon-btn" id="logout-btn">Logout</button></div>
  </header>

  <main>
    <section id="auth-screen">
      <div class="hero"><h1>Build your exhibition order</h1><p>Register once, scan the design stickers, and save one editable order for Maitri and one for Niharika.</p></div>
      <div class="card">
        <div class="switch"><button id="login-mode" class="active">Login</button><button id="register-mode">Register</button></div>
        <form id="login-form">
          <label>Mobile number</label><div class="phone"><div class="prefix">+91</div><input id="login-phone" inputmode="numeric" maxlength="10" required placeholder="10-digit mobile"></div>
          <label>Password</label><input id="login-password" type="password" required minlength="6" autocomplete="current-password">
          <button class="btn" type="submit">Login</button>
        </form>
        <form id="register-form" class="hidden">
          <label>Company / firm name</label><input id="reg-company" required maxlength="120">
          <label>Contact person</label><input id="reg-contact" required maxlength="100">
          <div class="grid2"><div><label>City</label><input id="reg-city" required></div><div><label>State</label><input id="reg-state" required></div></div>
          <label>GSTIN <span style="text-transform:none;color:var(--muted);font-weight:500">(optional)</span></label><input id="reg-gstin" maxlength="15">
          <label>Mobile number</label><div class="phone"><div class="prefix">+91</div><input id="reg-phone" inputmode="numeric" maxlength="10" required></div>
          <label>Create password</label><input id="reg-password" type="password" minlength="6" required autocomplete="new-password">
          <div id="access-code-wrap" class="hidden"><label>Exhibition access code</label><input id="reg-access-code"></div>
          <button class="btn" type="submit">Register and start</button>
        </form>
        <p class="copy">No OTP is sent. Keep your password safe; exhibition staff can reset it from the admin dashboard.</p>
      </div>
    </section>

    <section id="app-screen" class="hidden">
      <div class="firm-tabs"><button class="firm-tab active" data-firm="Maitri">Maitri</button><button class="firm-tab" data-firm="Niharika">Niharika</button></div>
      <div class="card">
        <h2 id="order-title">Maitri order</h2><p class="copy" id="order-status">Draft</p>
        <div class="summary"><div class="metric"><b id="design-count">0</b><span>Designs</span></div><div class="metric"><b id="piece-count">0</b><span>Pieces</span></div><div class="metric"><b id="version-count">1</b><span>Version</span></div></div>
      </div>
      <div class="card">
        <h2>Scan a barcode</h2><p class="copy">Each design is added once. Change the quantity manually.</p>
        <div class="scan-actions"><div><label>Barcode</label><input id="barcode-input" autocomplete="off" inputmode="text" placeholder="Scan or type barcode"></div><button id="add-barcode" class="btn">Add design</button></div>
        <button id="camera-btn" class="btn secondary">Open camera scanner</button>
        <div id="reader" class="reader"></div>
        <div id="scan-note" class="notice hidden"></div>
      </div>
      <div class="card"><h2>Order items</h2><div id="items" class="items"></div></div>
      <div class="savebar"><button id="save-btn" class="btn">Save order</button><button id="pdf-btn" class="btn secondary">Download PDF</button></div>
    </section>

    <section id="account-screen" class="hidden">
      <div class="card"><h2>Account details</h2><p class="copy">These details appear on the order PDF and admin dashboard.</p>
        <div class="account-grid"><div><label>Company</label><input id="acc-company"></div><div><label>Contact</label><input id="acc-contact"></div><div><label>City</label><input id="acc-city"></div><div><label>State</label><input id="acc-state"></div></div>
        <label>GSTIN</label><input id="acc-gstin"><button id="save-account" class="btn">Save account details</button><button id="back-order" class="btn secondary">Back to orders</button>
      </div>
    </section>
  </main>

  <div id="toast" class="toast"></div><div id="loading" class="loading"><div class="loader-card"><div class="spinner"></div><span id="loading-text">Working…</span></div></div>

<script>
const CONFIG={
  SUPABASE_URL:"__SUPABASE_URL__",
  SUPABASE_ANON_KEY:"__SUPABASE_ANON_KEY__",
  REQUIRE_ACCESS_CODE:false
};
const configured=!CONFIG.SUPABASE_URL.includes('__')&&!CONFIG.SUPABASE_ANON_KEY.includes('__');
if(!configured)document.getElementById('config-warning').classList.remove('hidden');
if(CONFIG.REQUIRE_ACCESS_CODE)document.getElementById('access-code-wrap').classList.remove('hidden');
const sb=configured?supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
const FUNCTIONS_BASE=CONFIG.SUPABASE_URL.replace(/\/$/,'')+'/functions/v1';
const state={profile:null,orders:{Maitri:null,Niharika:null},carts:{Maitri:[],Niharika:[]},activeFirm:'Maitri',scanner:null,scanning:false,imageUrls:new Map()};
const $=id=>document.getElementById(id);const escapeHtml=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
function toast(message,type=''){const el=$('toast');el.textContent=message;el.className='toast open '+type;clearTimeout(window.__toast);window.__toast=setTimeout(()=>el.className='toast',3200)}
function loading(on,text='Working…'){$('loading-text').textContent=text;$('loading').classList.toggle('open',on)}
function normalizePhone(v){const d=String(v||'').replace(/\D/g,'');if(!/^[6-9]\d{9}$/.test(d))throw new Error('Enter a valid 10-digit Indian mobile number');return '91'+d}
function internalEmail(phoneE164){return phoneE164+'@customers.maitri.local'}
function currentCart(){return state.carts[state.activeFirm]}
function show(screen){['auth-screen','app-screen','account-screen'].forEach(id=>$(id).classList.toggle('hidden',id!==screen));$('app-top').classList.toggle('hidden',screen==='auth-screen')}
function setMode(register){$('login-form').classList.toggle('hidden',register);$('register-form').classList.toggle('hidden',!register);$('login-mode').classList.toggle('active',!register);$('register-mode').classList.toggle('active',register)}
$('login-mode').onclick=()=>setMode(false);$('register-mode').onclick=()=>setMode(true);

async function sessionToken(){const{data}=await sb.auth.getSession();const token=data.session?.access_token;if(!token)throw new Error('Session expired. Please log in again.');return token}
async function functionFetch(name,body){const token=await sessionToken();const res=await fetch(`${FUNCTIONS_BASE}/${name}`,{method:'POST',headers:{'Content-Type':'application/json','Authorization':`Bearer ${token}`,'apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify(body)});if(!res.ok){let msg=`HTTP ${res.status}`;try{msg=(await res.json()).error||msg}catch{}throw new Error(msg)}return res}
async function imageBlob(designNo,variant='thumb'){const key=designNo+':'+variant;if(state.imageUrls.has(key))return state.imageUrls.get(key);const res=await functionFetch('image-proxy',{designNo,variant});const blob=await res.blob();const url=URL.createObjectURL(blob);state.imageUrls.set(key,url);return url}

$('login-form').addEventListener('submit',async e=>{e.preventDefault();if(!sb)return;try{loading(true,'Logging in…');const phone=normalizePhone($('login-phone').value);const{error}=await sb.auth.signInWithPassword({email:internalEmail(phone),password:$('login-password').value});if(error)throw error}catch(err){toast(err.message,'error')}finally{loading(false)}});
$('register-form').addEventListener('submit',async e=>{e.preventDefault();if(!sb)return;try{loading(true,'Creating account…');const phone=normalizePhone($('reg-phone').value);const metadata={phone_e164:phone,company_name:$('reg-company').value.trim(),contact_name:$('reg-contact').value.trim(),city:$('reg-city').value.trim(),state:$('reg-state').value.trim(),gstin:$('reg-gstin').value.trim().toUpperCase(),access_code:$('reg-access-code').value.trim()};const{data,error}=await sb.auth.signUp({email:internalEmail(phone),password:$('reg-password').value,options:{data:metadata}});if(error)throw error;if(!data.session)throw new Error('Registration succeeded but no session was created. Disable Confirm Email in Supabase Auth settings.');toast('Registration complete','success')}catch(err){toast(String(err.message||err).replace('Database error saving new user','Registration details were rejected'),'error')}finally{loading(false)}});

async function loadApp(){loading(true,'Loading your orders…');try{const{data:profile,error:pErr}=await sb.from('customers').select('*').single();if(pErr)throw pErr;state.profile=profile;for(const firm of ['Maitri','Niharika']){const{data,error}=await sb.rpc('get_my_order_state',{p_firm:firm});if(error)throw error;state.orders[firm]=data;state.carts[firm]=(data.items||[]).map(x=>({...x}));}fillAccount();show('app-screen');render()}catch(err){toast(err.message,'error');await sb.auth.signOut();show('auth-screen')}finally{loading(false)}}
function fillAccount(){const p=state.profile||{};$('acc-company').value=p.company_name||'';$('acc-contact').value=p.contact_name||'';$('acc-city').value=p.city||'';$('acc-state').value=p.state||'';$('acc-gstin').value=p.gstin||''}

function render(){document.querySelectorAll('.firm-tab').forEach(b=>b.classList.toggle('active',b.dataset.firm===state.activeFirm));const order=state.orders[state.activeFirm]||{version:1,status:'Draft'};const cart=currentCart();$('order-title').textContent=state.activeFirm+' order';$('order-status').textContent=`${order.status||'Draft'} · Last saved ${order.updatedAt?new Date(order.updatedAt).toLocaleString('en-IN'):'not yet'}`;$('design-count').textContent=cart.length;$('piece-count').textContent=cart.reduce((s,x)=>s+(Number(x.qty)||0),0);$('version-count').textContent=order.version||1;const host=$('items');if(!cart.length){host.innerHTML='<div class="empty">No designs added yet. Scan the first sticker above.</div>';return}host.innerHTML=cart.map((item,i)=>`<article class="item"><div class="thumb" id="thumb-${i}" aria-label="Protected design thumbnail"></div><div><h3>${escapeHtml(item.designNo)}</h3><div class="meta">${escapeHtml([item.category,item.fabric,item.color].filter(Boolean).join(' · '))}<br>${escapeHtml(item.description||'')}</div><div class="qty"><button data-act="minus" data-i="${i}">−</button><input data-act="qty" data-i="${i}" type="number" min="1" max="9999" value="${Number(item.qty)||1}"><button data-act="plus" data-i="${i}">+</button><button class="remove" data-act="remove" data-i="${i}">✕</button></div></div></article>`).join('');cart.forEach((item,i)=>imageBlob(item.designNo).then(url=>{const el=$('thumb-'+i);if(el){el.style.backgroundImage=`url("${url}")`;protect(el)}}).catch(()=>{}))}
function protect(el){el.draggable=false;el.addEventListener('contextmenu',e=>e.preventDefault());el.addEventListener('dragstart',e=>e.preventDefault());el.addEventListener('selectstart',e=>e.preventDefault())}
$('items').addEventListener('click',e=>{const b=e.target.closest('[data-act]');if(!b||b.tagName==='INPUT')return;const i=Number(b.dataset.i),cart=currentCart();if(b.dataset.act==='plus')cart[i].qty=Math.min(9999,(Number(cart[i].qty)||1)+1);if(b.dataset.act==='minus')cart[i].qty=Math.max(1,(Number(cart[i].qty)||1)-1);if(b.dataset.act==='remove')cart.splice(i,1);render()});
$('items').addEventListener('change',e=>{if(e.target.dataset.act!=='qty')return;const i=Number(e.target.dataset.i);currentCart()[i].qty=Math.max(1,Math.min(9999,Number(e.target.value)||1));render()});
document.querySelectorAll('.firm-tab').forEach(b=>b.onclick=async()=>{await stopScanner();state.activeFirm=b.dataset.firm;render()});

async function addBarcode(raw){const barcode=String(raw||'').trim();if(!barcode)return;try{$('scan-note').classList.add('hidden');const{data,error}=await sb.rpc('lookup_barcode',{p_barcode:barcode});if(error)throw error;const row=Array.isArray(data)?data[0]:data;if(!row)throw new Error('Barcode is not mapped to an active design');if(![state.activeFirm,'Both'].includes(row.firm))throw new Error(`${row.design_no} belongs to ${row.firm}. Switch firm tabs first.`);const cart=currentCart();if(cart.some(x=>x.designNo===row.design_no)){throw new Error(`${row.design_no} is already in this order`)}cart.push({barcode:row.barcode,designNo:row.design_no,qty:1,category:row.category,fabric:row.fabric,color:row.color,description:row.description});$('barcode-input').value='';render();note(`Added ${row.design_no}`,'success');navigator.vibrate?.(80)}catch(err){note(err.message,'error');navigator.vibrate?.([100,70,100])}}
function note(text,type=''){$('scan-note').textContent=text;$('scan-note').className='notice '+type}
$('add-barcode').onclick=()=>addBarcode($('barcode-input').value);$('barcode-input').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();addBarcode(e.target.value)}});
$('camera-btn').onclick=async()=>{if(state.scanning){await stopScanner();return}try{state.scanner=new Html5Qrcode('reader');$('reader').classList.add('open');await state.scanner.start({facingMode:'environment'},{fps:10,qrbox:{width:260,height:160}},async decoded=>{await addBarcode(decoded);await stopScanner()},()=>{});state.scanning=true;$('camera-btn').textContent='Close camera scanner'}catch(err){toast('Camera could not start: '+err,'error');await stopScanner()}};
async function stopScanner(){if(state.scanner){try{if(state.scanning)await state.scanner.stop()}catch{}try{await state.scanner.clear()}catch{}}state.scanner=null;state.scanning=false;$('reader').classList.remove('open');$('camera-btn').textContent='Open camera scanner'}

$('save-btn').onclick=async()=>{try{loading(true,'Saving order…');const firm=state.activeFirm,order=state.orders[firm];const items=currentCart().map(x=>({barcode:x.barcode||'',designNo:x.designNo,qty:Number(x.qty)||1}));const{data,error}=await sb.rpc('save_my_order',{p_firm:firm,p_base_version:order.version,p_items:items,p_request_id:crypto.randomUUID()});if(error)throw error;if(!data.ok){state.orders[firm]=data.order;state.carts[firm]=(data.order.items||[]).map(x=>({...x}));render();throw new Error(data.message)}state.orders[firm]=data.order;state.carts[firm]=(data.order.items||[]).map(x=>({...x}));render();toast(`${firm} order saved`,'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

async function blobToDataUrl(blob){return await new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(r.result);r.onerror=reject;r.readAsDataURL(blob)})}
$('pdf-btn').onclick=async()=>{const cart=currentCart();if(!cart.length){toast('Add at least one design before downloading a PDF','error');return}try{loading(true,'Building low-resolution PDF…');const{jsPDF}=window.jspdf;const doc=new jsPDF({unit:'mm',format:'a4'});const p=state.profile,firm=state.activeFirm;doc.setFont('helvetica','bold');doc.setFontSize(18);doc.text(`${firm} Exhibition Order`,14,16);doc.setFontSize(10);doc.setFont('helvetica','normal');doc.text(`${p.company_name} · ${p.contact_name}`,14,23);doc.text(`Phone: +${p.phone_e164}   City: ${p.city}, ${p.state}`,14,29);doc.text(`Generated: ${new Date().toLocaleString('en-IN')}`,14,35);let y=43;for(let i=0;i<cart.length;i++){const item=cart[i];if(y>260){doc.addPage();y=16}try{const res=await functionFetch('image-proxy',{designNo:item.designNo,variant:'pdf'});const dataUrl=await blobToDataUrl(await res.blob());doc.addImage(dataUrl,'JPEG',14,y,28,38,undefined,'FAST')}catch{doc.setDrawColor(220);doc.rect(14,y,28,38)}doc.setFont('helvetica','bold');doc.setFontSize(12);doc.text(item.designNo,48,y+7);doc.setFont('helvetica','normal');doc.setFontSize(9);const details=[item.category,item.fabric,item.color].filter(Boolean).join(' · ');doc.text(doc.splitTextToSize(details,130),48,y+14);doc.text(doc.splitTextToSize(item.description||'',130),48,y+20);doc.setFont('helvetica','bold');doc.text(`Qty: ${item.qty} pcs`,48,y+34);doc.setDrawColor(225);doc.line(14,y+41,196,y+41);y+=46}doc.setFontSize(11);doc.text(`Total designs: ${cart.length}    Total pieces: ${cart.reduce((s,x)=>s+Number(x.qty||0),0)}`,14,Math.min(y+3,285));doc.save(`${p.company_name.replace(/[^a-z0-9]+/gi,'-')}-${firm}-order.pdf`);toast('PDF downloaded','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

$('account-btn').onclick=()=>{fillAccount();show('account-screen')};$('back-order').onclick=()=>show('app-screen');$('save-account').onclick=async()=>{try{loading(true,'Saving account…');const patch={company_name:$('acc-company').value.trim(),contact_name:$('acc-contact').value.trim(),city:$('acc-city').value.trim(),state:$('acc-state').value.trim(),gstin:$('acc-gstin').value.trim().toUpperCase()};const{data,error}=await sb.from('customers').update(patch).eq('id',state.profile.id).select().single();if(error)throw error;state.profile=data;toast('Account updated','success');show('app-screen')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('logout-btn').onclick=async()=>{await stopScanner();await sb.auth.signOut();state.profile=null;show('auth-screen')};

if(sb){sb.auth.onAuthStateChange((event,session)=>{setTimeout(()=>{if(session)loadApp();else show('auth-screen')},0)});sb.auth.getSession().then(({data})=>{if(data.session)loadApp();else show('auth-screen')})}else show('auth-screen');
</script>
</body>
</html>
```

## `web/dashboard.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover"><meta name="theme-color" content="#225E63">
  <title>Exhibition Admin Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>
  <style>
    :root{--teal:#225E63;--teal2:#2B7379;--foam:#E8F2F1;--warm:#F7F3EA;--ink:#33271B;--muted:#747B78;--line:#DFE6E3;--orange:#FF9700;--red:#C81E1E;--green:#15803D;--white:#fff}*{box-sizing:border-box;margin:0}html,body{min-height:100%;background:linear-gradient(#FAF8F2,#F7F3EA);color:var(--ink);font-family:Inter,system-ui,sans-serif}button,input,select{font:inherit}.hidden{display:none!important}.top{position:sticky;top:0;z-index:40;display:flex;align-items:center;gap:9px;min-height:62px;padding:9px 14px;background:rgba(255,255,255,.96);border-bottom:1px solid var(--line);backdrop-filter:blur(10px)}.brand{color:var(--teal);font-weight:850}.brand small{display:block;color:var(--muted);font-size:9px;letter-spacing:.11em;text-transform:uppercase}.top-actions{margin-left:auto;display:flex;gap:6px}.top button{min-height:38px;padding:0 11px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--teal);font-size:11px;font-weight:750}main{width:min(100%,1120px);margin:auto;padding:14px 11px 35px}.card{margin-bottom:12px;padding:15px;border:1px solid var(--line);border-radius:15px;background:#fff;box-shadow:0 6px 18px rgba(34,94,99,.06)}h1{font-size:21px;color:var(--teal)}h2{font-size:15px;color:var(--teal)}.copy{margin-top:4px;color:var(--muted);font-size:11px;line-height:1.5}label{display:block;margin:10px 0 5px;color:#4D5552;font-size:10px;font-weight:800;letter-spacing:.045em;text-transform:uppercase}input,select{width:100%;min-height:44px;padding:0 12px;border:1px solid #D8E1DE;border-radius:10px;background:#fff;color:var(--ink);font-size:14px}input:focus,select:focus{outline:none;border-color:var(--teal2);box-shadow:0 0 0 3px rgba(43,115,121,.13)}.btn{min-height:44px;padding:0 14px;border:0;border-radius:10px;background:var(--teal);color:#fff;font-size:12px;font-weight:800}.btn.secondary{border:1px solid var(--teal);background:#fff;color:var(--teal)}.btn.danger{background:var(--red)}.filters{display:grid;grid-template-columns:1.2fr repeat(3,1fr) auto;gap:8px;align-items:end}.filters .btn{margin-bottom:0}.kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:9px;margin-bottom:12px}.kpi{min-height:90px;padding:13px;border:1px solid var(--line);border-radius:13px;background:#fff;box-shadow:0 5px 15px rgba(34,94,99,.05)}.kpi.primary{background:linear-gradient(135deg,var(--teal),var(--teal2));color:#fff}.kpi b{display:block;font-size:23px}.kpi span{display:block;margin-top:6px;color:var(--muted);font-size:9px;font-weight:800;letter-spacing:.04em;text-transform:uppercase}.kpi.primary span{color:rgba(255,255,255,.75)}.charts{display:grid;grid-template-columns:repeat(2,1fr);gap:10px;margin-bottom:12px}.chart-card{min-height:310px;padding:14px;border:1px solid var(--line);border-radius:15px;background:#fff}.chart-wrap{position:relative;height:250px;margin-top:8px}.toolbar{display:flex;align-items:center;gap:8px;margin-bottom:9px}.toolbar input{max-width:280px;margin-left:auto}.orders{display:grid;gap:8px}.order{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;padding:12px;border:1px solid var(--line);border-radius:12px;background:#fff;cursor:pointer}.order:hover{background:#F8FBFA}.order b{font-size:13px;color:var(--teal)}.order p{margin-top:3px;color:var(--muted);font-size:10px;line-height:1.45}.value{text-align:right}.value strong{display:block;color:var(--teal);font-size:16px}.value span{font-size:9px;color:var(--muted)}.empty{padding:26px 10px;color:var(--muted);font-size:12px;text-align:center}.modal{position:fixed;inset:0;z-index:100;display:none;align-items:flex-end;background:rgba(24,30,28,.52)}.modal.open{display:flex}.sheet{width:100%;max-height:90vh;overflow:auto;padding:18px 16px calc(22px + env(safe-area-inset-bottom));border-radius:20px 20px 0 0;background:#fff}.sheet-head{display:flex;align-items:flex-start;gap:10px}.sheet-head button{margin-left:auto;width:38px;height:38px;border:0;border-radius:10px;background:var(--foam);color:var(--teal);font-weight:850}.detail-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:12px 0}.detail-metric{padding:10px;border-radius:10px;background:var(--foam);text-align:center}.detail-metric b{display:block;color:var(--teal);font-size:18px}.detail-metric span{font-size:9px;color:var(--muted)}.line{display:grid;grid-template-columns:62px minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 0;border-bottom:1px solid var(--line)}.thumb{width:62px;height:82px;border-radius:8px;background:#EEF2F0 center/cover no-repeat;-webkit-touch-callout:none;user-select:none}.line b{font-size:12px;color:var(--teal)}.line p{margin-top:3px;color:var(--muted);font-size:9px;line-height:1.4}.line strong{color:var(--teal);font-size:12px}.reset-grid{display:grid;grid-template-columns:1fr 1fr auto;gap:8px;align-items:end}.toast{position:fixed;left:50%;top:70px;z-index:130;display:none;max-width:90%;padding:10px 16px;border-radius:22px;background:var(--ink);color:#fff;font-size:12px;transform:translateX(-50%)}.toast.open{display:block}.toast.error{background:#B91C1C}.toast.success{background:#166534}.loading{position:fixed;inset:0;z-index:120;display:none;place-items:center;background:rgba(25,31,29,.46)}.loading.open{display:grid}.loader{padding:22px 28px;border-radius:15px;background:#fff;color:var(--teal);font-weight:800}.config{padding:11px;background:#FEE2E2;color:#991B1B;text-align:center;font-size:12px}@media(max-width:850px){.kpis{grid-template-columns:repeat(3,1fr)}.filters{grid-template-columns:1fr 1fr}.filters>div:first-child{grid-column:1/-1}.charts{grid-template-columns:1fr}}@media(max-width:500px){.kpis{grid-template-columns:repeat(2,1fr)}.filters,.reset-grid{grid-template-columns:1fr}.toolbar{align-items:flex-start;flex-direction:column}.toolbar input{max-width:none}.detail-grid{grid-template-columns:repeat(2,1fr)}}
  </style>
</head>
<body oncontextmenu="return false">
<div id="config" class="config hidden">Replace the Supabase placeholders before publishing.</div>
<header id="top" class="top hidden"><div class="brand">Exhibition Dashboard<small>Maitri × Niharika admin</small></div><div class="top-actions"><button id="refresh">Refresh</button><button id="logout">Logout</button></div></header>
<main>
  <section id="login-screen"><div class="card"><h1>Admin dashboard login</h1><p class="copy">Cross-customer data is available only after server-side verification of your admin role.</p><form id="login-form"><label>Email</label><input id="email" type="email" required><label>Password</label><input id="password" type="password" required><button class="btn" style="width:100%;margin-top:12px" type="submit">Login</button></form></div></section>
  <section id="dashboard-screen" class="hidden">
    <div class="card"><h1>Exhibition orders</h1><p class="copy" id="updated">Not loaded</p><div class="filters"><div><label>Search customer / phone / design</label><input id="search" placeholder="Search"></div><div><label>Firm</label><select id="firm"><option value="">All firms</option><option>Maitri</option><option>Niharika</option></select></div><div><label>State</label><select id="state"><option value="">All states</option></select></div><div><label>City</label><select id="city"><option value="">All cities</option></select></div><button id="clear" class="btn secondary">Clear</button></div></div>
    <div class="kpis"><div class="kpi primary"><b id="k-pieces">0</b><span>Total pieces</span></div><div class="kpi"><b id="k-customers">0</b><span>Customers with orders</span></div><div class="kpi"><b id="k-orders">0</b><span>Saved orders</span></div><div class="kpi"><b id="k-designs">0</b><span>Unique designs</span></div><div class="kpi"><b id="k-maitri">0</b><span>Maitri pieces</span></div><div class="kpi"><b id="k-niharika">0</b><span>Niharika pieces</span></div></div>
    <div class="charts"><div class="chart-card"><h2>Pieces by firm</h2><div class="chart-wrap"><canvas id="firm-chart"></canvas></div></div><div class="chart-card"><h2>Top designs</h2><div class="chart-wrap"><canvas id="design-chart"></canvas></div></div><div class="chart-card"><h2>Top customers</h2><div class="chart-wrap"><canvas id="customer-chart"></canvas></div></div><div class="chart-card"><h2>Pieces by state</h2><div class="chart-wrap"><canvas id="state-chart"></canvas></div></div></div>
    <div class="card"><div class="toolbar"><div><h2>Orders</h2><p class="copy" id="order-count">0 orders</p></div><button id="export" class="btn secondary">Export Excel</button></div><div id="orders" class="orders"></div></div>
    <div class="card"><h2>Reset a customer password</h2><p class="copy">Set a temporary password and share it directly with the customer.</p><div class="reset-grid"><div><label>Mobile</label><input id="reset-phone" inputmode="numeric" maxlength="12"></div><div><label>New temporary password</label><input id="reset-password" type="password" minlength="8"></div><button id="reset-btn" class="btn">Reset</button></div></div>
  </section>
</main>
<div id="detail-modal" class="modal"><div class="sheet"><div class="sheet-head"><div><h2 id="detail-title">Order</h2><p class="copy" id="detail-sub"></p></div><button id="detail-close">✕</button></div><div id="detail-metrics" class="detail-grid"></div><div id="detail-items"></div><div class="grid" style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:14px"><button id="lock-order" class="btn secondary">Lock order</button><button id="customer-toggle" class="btn secondary">Disable customer</button></div></div></div>
<div id="toast" class="toast"></div><div id="loading" class="loading"><div class="loader" id="loading-text">Working…</div></div>
<script>
const CONFIG={SUPABASE_URL:'__SUPABASE_URL__',SUPABASE_ANON_KEY:'__SUPABASE_ANON_KEY__'};const configured=!CONFIG.SUPABASE_URL.includes('__')&&!CONFIG.SUPABASE_ANON_KEY.includes('__');if(!configured)document.getElementById('config').classList.remove('hidden');const sb=configured?supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true}}):null;const API=CONFIG.SUPABASE_URL.replace(/\/$/,'')+'/functions/v1/admin-api';const IMG=CONFIG.SUPABASE_URL.replace(/\/$/,'')+'/functions/v1/image-proxy';const $=id=>document.getElementById(id);const state={data:null,orders:[],charts:{},selected:null,imageUrls:new Map()};const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
function toast(m,t=''){const e=$('toast');e.textContent=m;e.className='toast open '+t;clearTimeout(window.t);window.t=setTimeout(()=>e.className='toast',3200)}function loading(on,text='Working…'){$('loading-text').textContent=text;$('loading').classList.toggle('open',on)}function show(logged){$('login-screen').classList.toggle('hidden',logged);$('dashboard-screen').classList.toggle('hidden',!logged);$('top').classList.toggle('hidden',!logged)}async function token(){const{data}=await sb.auth.getSession();if(!data.session)throw new Error('Session expired');return data.session.access_token}async function admin(action,payload={}){const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+await token(),'apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({action,...payload})});const json=await res.json().catch(()=>({}));if(!res.ok||!json.ok)throw new Error(json.error||`HTTP ${res.status}`);return json.data}
$('login-form').onsubmit=async e=>{e.preventDefault();try{loading(true,'Logging in…');const{error}=await sb.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});if(error)throw error;await load()}catch(err){toast(err.message,'error');await sb.auth.signOut()}finally{loading(false)}};$('logout').onclick=async()=>{await sb.auth.signOut();show(false)};$('refresh').onclick=load;
async function load(){try{loading(true,'Loading dashboard…');await admin('whoami');state.data=await admin('dashboard');populateFilters();applyFilters();$('updated').textContent='Generated '+new Date(state.data.generatedAt).toLocaleString('en-IN');show(true)}catch(err){toast(err.message,'error');throw err}finally{loading(false)}}
function populateFilters(){const states=[...new Set(state.data.customers.map(x=>x.state).filter(Boolean))].sort();const cities=[...new Set(state.data.customers.map(x=>x.city).filter(Boolean))].sort();$('state').innerHTML='<option value="">All states</option>'+states.map(x=>`<option>${esc(x)}</option>`).join('');$('city').innerHTML='<option value="">All cities</option>'+cities.map(x=>`<option>${esc(x)}</option>`).join('')}
function applyFilters(){const q=$('search').value.trim().toLowerCase(),firm=$('firm').value,st=$('state').value,city=$('city').value;state.orders=state.data.orders.filter(o=>{if(firm&&o.firm!==firm)return false;if(st&&o.state!==st)return false;if(city&&o.city!==city)return false;if(q){const hay=[o.companyName,o.contactName,o.phone,o.city,o.state,...o.items.map(i=>i.designNo)].join(' ').toLowerCase();if(!hay.includes(q))return false}return true});render()}
['search','firm','state','city'].forEach(id=>$(id).addEventListener(id==='search'?'input':'change',applyFilters));$('clear').onclick=()=>{$('search').value='';$('firm').value='';$('state').value='';$('city').value='';applyFilters()};
function facts(){return state.orders.flatMap(o=>o.items.map(i=>({...i,firm:o.firm,customerId:o.customerId,companyName:o.companyName,state:o.state,city:o.city})))}function group(rows,key){const m=new Map;rows.forEach(r=>m.set(r[key]||'Not specified',(m.get(r[key]||'Not specified')||0)+Number(r.qty||0)));return[...m].map(([label,value])=>({label,value})).sort((a,b)=>b.value-a.value)}
function render(){const f=facts(),saved=state.orders.filter(o=>o.totalDesigns>0||o.status==='Saved');$('k-pieces').textContent=f.reduce((s,x)=>s+Number(x.qty||0),0);$('k-customers').textContent=new Set(saved.map(x=>x.customerId)).size;$('k-orders').textContent=saved.length;$('k-designs').textContent=new Set(f.map(x=>x.designNo)).size;$('k-maitri').textContent=f.filter(x=>x.firm==='Maitri').reduce((s,x)=>s+Number(x.qty||0),0);$('k-niharika').textContent=f.filter(x=>x.firm==='Niharika').reduce((s,x)=>s+Number(x.qty||0),0);renderCharts(f);renderOrders()}
function chart(id,type,rows){state.charts[id]?.destroy();const ctx=$(id);state.charts[id]=new Chart(ctx,{type,data:{labels:rows.map(x=>x.label),datasets:[{data:rows.map(x=>x.value)}]},options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:type==='doughnut',position:'bottom'}},scales:type==='doughnut'?{}:{y:{beginAtZero:true},x:{ticks:{maxRotation:45,minRotation:0}}}}})}
function renderCharts(f){chart('firm-chart','doughnut',group(f,'firm'));chart('design-chart','bar',group(f,'designNo').slice(0,10));const c=new Map;f.forEach(x=>c.set(x.companyName,(c.get(x.companyName)||0)+Number(x.qty||0)));chart('customer-chart','bar',[...c].map(([label,value])=>({label,value})).sort((a,b)=>b.value-a.value).slice(0,10));chart('state-chart','doughnut',group(f,'state').slice(0,10))}
function renderOrders(){$('order-count').textContent=state.orders.length+' orders';$('orders').innerHTML=state.orders.length?state.orders.map((o,i)=>`<div class="order" data-i="${i}"><div><b>${esc(o.companyName)} · ${esc(o.firm)}</b><p>${esc(o.contactName)} · +${esc(o.phone)} · ${esc([o.city,o.state].filter(Boolean).join(', '))}<br>${esc(o.status)} · Updated ${new Date(o.updatedAt).toLocaleString('en-IN')}</p></div><div class="value"><strong>${o.totalPieces}</strong><span>${o.totalDesigns} designs</span></div></div>`).join(''):'<div class="empty">No orders match these filters.</div>'}
$('orders').onclick=e=>{const row=e.target.closest('[data-i]');if(!row)return;openDetail(state.orders[Number(row.dataset.i)])};async function image(designNo){if(state.imageUrls.has(designNo))return state.imageUrls.get(designNo);const res=await fetch(IMG,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+await token(),'apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({designNo,variant:'thumb'})});if(!res.ok)throw new Error('Image unavailable');const url=URL.createObjectURL(await res.blob());state.imageUrls.set(designNo,url);return url}
function openDetail(o){state.selected=o;$('detail-title').textContent=o.companyName+' · '+o.firm;$('detail-sub').textContent=`${o.contactName} · +${o.phone} · ${o.city}, ${o.state}`;$('detail-metrics').innerHTML=`<div class="detail-metric"><b>${o.totalPieces}</b><span>Pieces</span></div><div class="detail-metric"><b>${o.totalDesigns}</b><span>Designs</span></div><div class="detail-metric"><b>${o.version}</b><span>Version</span></div><div class="detail-metric"><b>${esc(o.status)}</b><span>Status</span></div>`;$('detail-items').innerHTML=o.items.length?o.items.map((i,n)=>`<div class="line"><div class="thumb" id="dthumb-${n}"></div><div><b>${esc(i.designNo)}</b><p>${esc([i.category,i.fabric,i.color].filter(Boolean).join(' · '))}<br>${esc(i.description||'')}</p></div><strong>${i.qty} pcs</strong></div>`).join(''):'<div class="empty">No items.</div>';$('lock-order').textContent=o.status==='Locked'?'Unlock order':'Lock order';$('customer-toggle').textContent=o.customerActive?'Disable customer':'Enable customer';$('detail-modal').classList.add('open');o.items.forEach((i,n)=>image(i.designNo).then(url=>{const el=$('dthumb-'+n);if(el)el.style.backgroundImage=`url("${url}")`}).catch(()=>{}))}
$('detail-close').onclick=()=>$('detail-modal').classList.remove('open');$('detail-modal').onclick=e=>{if(e.target===$('detail-modal'))$('detail-modal').classList.remove('open')};
$('lock-order').onclick=async()=>{const o=state.selected;if(!o)return;try{loading(true,'Updating order…');await admin('setOrderLocked',{orderId:o.id,locked:o.status!=='Locked'});$('detail-modal').classList.remove('open');await load();toast('Order status updated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};$('customer-toggle').onclick=async()=>{const o=state.selected;if(!o)return;try{loading(true,'Updating customer…');await admin('setCustomerActive',{customerId:o.customerId,active:!o.customerActive});$('detail-modal').classList.remove('open');await load();toast('Customer access updated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
function excelSafe(v){const s=String(v??'');return /^[=+\-@]/.test(s)?"'"+s:s}$('export').onclick=()=>{const rows=[];state.orders.forEach(o=>{if(!o.items.length)rows.push({Company:o.companyName,Contact:o.contactName,Phone:o.phone,City:o.city,State:o.state,Firm:o.firm,Status:o.status,DesignNo:'',Qty:0,Category:'',Fabric:'',Color:'',UpdatedAt:o.updatedAt});else o.items.forEach(i=>rows.push({Company:excelSafe(o.companyName),Contact:excelSafe(o.contactName),Phone:o.phone,City:excelSafe(o.city),State:excelSafe(o.state),Firm:o.firm,Status:o.status,DesignNo:excelSafe(i.designNo),Qty:i.qty,Category:excelSafe(i.category),Fabric:excelSafe(i.fabric),Color:excelSafe(i.color),UpdatedAt:o.updatedAt}))});const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Orders');XLSX.writeFile(wb,'Maitri-Niharika-Exhibition-Orders.xlsx')};
$('reset-btn').onclick=async()=>{try{const phone=$('reset-phone').value.trim(),newPassword=$('reset-password').value;if(newPassword.length<8)throw new Error('Use at least 8 characters');if(!confirm('Reset the password for '+phone+'?'))return;loading(true,'Resetting password…');const data=await admin('resetPassword',{phone,newPassword});$('reset-phone').value='';$('reset-password').value='';toast('Password reset for '+data.companyName,'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
if(sb){sb.auth.getSession().then(async({data})=>{if(data.session){try{await load()}catch{await sb.auth.signOut();show(false)}}else show(false)})}else show(false);
</script>
</body></html>
```

## `web/index.html`

```html
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="0; url=app.html"><title>Exhibition Orders</title></head><body><p><a href="app.html">Open the exhibition order form</a></p></body></html>
```

## `web/mapping.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover"><meta name="theme-color" content="#225E63">
  <title>Exhibition Barcode Mapping</title>
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/html5-qrcode/2.3.8/html5-qrcode.min.js"></script>
  <style>
    :root{--teal:#225E63;--teal2:#2B7379;--foam:#E8F2F1;--warm:#F7F3EA;--ink:#33271B;--muted:#747B78;--line:#DFE6E3;--orange:#FF9700;--red:#C81E1E;--green:#15803D;--white:#fff}*{box-sizing:border-box;margin:0}html,body{min-height:100%;background:linear-gradient(#FAF8F2,#F7F3EA);color:var(--ink);font-family:Inter,system-ui,sans-serif}button,input,select,textarea{font:inherit}.hidden{display:none!important}.top{position:sticky;top:0;z-index:40;display:flex;align-items:center;gap:9px;min-height:62px;padding:9px 14px;background:rgba(255,255,255,.96);border-bottom:1px solid var(--line);backdrop-filter:blur(10px)}.brand{color:var(--teal);font-weight:850}.brand small{display:block;color:var(--muted);font-size:9px;letter-spacing:.11em;text-transform:uppercase}.top button{margin-left:auto;min-height:38px;padding:0 11px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--teal);font-weight:750}main{width:min(100%,720px);margin:auto;padding:15px 12px 35px}.card{margin-bottom:13px;padding:16px;border:1px solid var(--line);border-radius:15px;background:#fff;box-shadow:0 6px 18px rgba(34,94,99,.06)}h1{font-size:21px;color:var(--teal)}h2{font-size:15px;color:var(--teal)}.copy{margin-top:4px;color:var(--muted);font-size:11px;line-height:1.5}label{display:block;margin:12px 0 5px;color:#4D5552;font-size:10px;font-weight:800;letter-spacing:.045em;text-transform:uppercase}input,select,textarea{width:100%;border:1px solid #D8E1DE;border-radius:10px;background:#fff;color:var(--ink);font-size:16px}input,select{min-height:47px;padding:0 13px}textarea{min-height:120px;padding:11px 13px;resize:vertical}input:focus,select:focus,textarea:focus{outline:none;border-color:var(--teal2);box-shadow:0 0 0 3px rgba(43,115,121,.13)}.btn{width:100%;min-height:48px;margin-top:12px;border:0;border-radius:10px;background:var(--teal);color:#fff;font-size:14px;font-weight:800}.btn.secondary{border:1px solid var(--teal);background:#fff;color:var(--teal)}.btn.danger{background:var(--red)}.btn:disabled{background:#E7EBE9;color:#939A97}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px}.reader{display:none;margin-top:12px;overflow:hidden;border-radius:13px}.reader.open{display:block}.notice{margin-top:10px;padding:10px 12px;border-radius:10px;background:var(--foam);color:var(--teal);font-size:11px}.notice.error{background:#FEE2E2;color:#991B1B}.notice.success{background:#DCFCE7;color:#166534}.mapping-list{display:grid;gap:8px;margin-top:10px}.row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:11px;border:1px solid var(--line);border-radius:11px}.row b{font-size:13px;color:var(--teal)}.row p{margin-top:3px;color:var(--muted);font-size:10px}.row button{min-height:36px;padding:0 10px;border:1px solid #F3B9BD;border-radius:9px;background:#fff;color:var(--red);font-size:11px;font-weight:750}.search{margin-top:10px}.empty{padding:25px 10px;color:var(--muted);font-size:12px;text-align:center}.toast{position:fixed;left:50%;top:70px;z-index:100;display:none;max-width:90%;padding:10px 16px;border-radius:22px;background:var(--ink);color:#fff;font-size:12px;transform:translateX(-50%)}.toast.open{display:block}.toast.error{background:#B91C1C}.toast.success{background:#166534}.loading{position:fixed;inset:0;z-index:90;display:none;place-items:center;background:rgba(25,31,29,.46)}.loading.open{display:grid}.loader{padding:22px 28px;border-radius:15px;background:#fff;color:var(--teal);font-weight:800}.config{padding:11px;background:#FEE2E2;color:#991B1B;text-align:center;font-size:12px}@media(max-width:500px){.grid2{grid-template-columns:1fr}}
  </style>
</head>
<body>
<div id="config" class="config hidden">Replace the Supabase placeholders before publishing.</div>
<header id="top" class="top hidden"><div class="brand">Barcode Mapping<small>Maitri × Niharika admin</small></div><button id="logout">Logout</button></header>
<main>
  <section id="login-screen"><div class="card"><h1>Admin login</h1><p class="copy">Use the separate Supabase admin email account created during setup.</p><form id="login-form"><label>Email</label><input id="email" type="email" required autocomplete="username"><label>Password</label><input id="password" type="password" required autocomplete="current-password"><button class="btn" type="submit">Login</button></form></div></section>
  <section id="tool-screen" class="hidden">
    <div class="card"><h1>Map physical stickers</h1><p class="copy">Scan or type a barcode, then choose the active design it belongs to.</p>
      <div class="grid2"><div><label>Barcode</label><input id="barcode" autocomplete="off"></div><div><label>Design number</label><input id="design-search" list="design-list" autocomplete="off"><datalist id="design-list"></datalist></div></div>
      <button id="map" class="btn">Save mapping</button><button id="camera" class="btn secondary">Open camera scanner</button><div id="reader" class="reader"></div><div id="note" class="notice hidden"></div>
    </div>
    <div class="card"><h2>Batch mapping</h2><p class="copy">Paste one mapping per line as <b>BARCODE,DESIGNNO</b>. Existing barcodes are safely remapped with an audit log.</p><textarea id="batch" placeholder="8901234567890,MT-1001&#10;8901234567891,NH-2002"></textarea><button id="batch-map" class="btn">Save batch</button></div>
    <div class="card"><h2>Recent mappings</h2><input id="filter" class="search" placeholder="Search barcode or design"><div id="mappings" class="mapping-list"></div></div>
  </section>
</main>
<div id="toast" class="toast"></div><div id="loading" class="loading"><div class="loader" id="loading-text">Working…</div></div>
<script>
const CONFIG={SUPABASE_URL:'__SUPABASE_URL__',SUPABASE_ANON_KEY:'__SUPABASE_ANON_KEY__'};const configured=!CONFIG.SUPABASE_URL.includes('__')&&!CONFIG.SUPABASE_ANON_KEY.includes('__');if(!configured)document.getElementById('config').classList.remove('hidden');const sb=configured?supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true}}):null;const API=CONFIG.SUPABASE_URL.replace(/\/$/,'')+'/functions/v1/admin-api';const $=id=>document.getElementById(id);const state={designs:[],mappings:[],scanner:null,scanning:false};const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
function toast(m,t=''){const e=$('toast');e.textContent=m;e.className='toast open '+t;clearTimeout(window.t);window.t=setTimeout(()=>e.className='toast',3000)}function loading(on,text='Working…'){$('loading-text').textContent=text;$('loading').classList.toggle('open',on)}function show(logged){$('login-screen').classList.toggle('hidden',logged);$('tool-screen').classList.toggle('hidden',!logged);$('top').classList.toggle('hidden',!logged)}
async function token(){const{data}=await sb.auth.getSession();if(!data.session)throw new Error('Session expired');return data.session.access_token}async function admin(action,payload={}){const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+await token(),'apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({action,...payload})});const json=await res.json().catch(()=>({}));if(!res.ok||!json.ok)throw new Error(json.error||`HTTP ${res.status}`);return json.data}
$('login-form').onsubmit=async e=>{e.preventDefault();try{loading(true,'Logging in…');const{error}=await sb.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});if(error)throw error;await loadTool()}catch(err){toast(err.message,'error');await sb.auth.signOut()}finally{loading(false)}};$('logout').onclick=async()=>{await stopScanner();await sb.auth.signOut();show(false)};
async function loadTool(){await admin('whoami');const [designs,mappings]=await Promise.all([admin('listDesigns'),admin('listMappings')]);state.designs=designs.filter(x=>x.active);state.mappings=mappings;renderDesigns();renderMappings();show(true)}function renderDesigns(){$('design-list').innerHTML=state.designs.map(d=>`<option value="${esc(d.designNo)}">${esc(d.firm+' · '+d.category+' · '+d.color)}</option>`).join('')}
function renderMappings(){const q=$('filter').value.trim().toLowerCase();const rows=state.mappings.filter(x=>!q||x.barcode.toLowerCase().includes(q)||x.designNo.toLowerCase().includes(q)).slice(0,200);$('mappings').innerHTML=rows.length?rows.map(x=>`<div class="row"><div><b>${esc(x.barcode)} → ${esc(x.designNo)}</b><p>${esc([x.firm,x.category,x.fabric,x.color].filter(Boolean).join(' · '))} · ${x.active?'Active':'Inactive'}</p></div>${x.active?`<button data-off="${esc(x.barcode)}">Deactivate</button>`:''}</div>`).join(''):'<div class="empty">No mappings found.</div>'}
$('filter').oninput=renderMappings;$('mappings').onclick=async e=>{const b=e.target.closest('[data-off]');if(!b)return;if(!confirm('Deactivate barcode '+b.dataset.off+'?'))return;try{loading(true,'Deactivating…');await admin('deactivateBarcode',{barcode:b.dataset.off});state.mappings=await admin('listMappings');renderMappings();toast('Barcode deactivated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
async function saveMapping(){const barcode=$('barcode').value.trim(),designNo=$('design-search').value.trim();if(!barcode||!designNo){toast('Barcode and design number are required','error');return}if(!state.designs.some(d=>d.designNo===designNo)){toast('Choose an active design from the list','error');return}try{loading(true,'Saving mapping…');const data=await admin('mapBarcode',{barcode,designNo});$('barcode').value='';$('barcode').focus();state.mappings=await admin('listMappings');renderMappings();note(`${data.barcode} mapped to ${data.designNo}`,'success');navigator.vibrate?.(80)}catch(err){note(err.message,'error')}finally{loading(false)}}$('map').onclick=saveMapping;$('barcode').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();saveMapping()}};function note(m,t=''){$('note').textContent=m;$('note').className='notice '+t}
$('batch-map').onclick=async()=>{const lines=$('batch').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);const items=lines.map((line,i)=>{const parts=line.split(/[\t,]/).map(x=>x.trim());if(parts.length<2||!parts[0]||!parts[1])throw new Error(`Line ${i+1} must be BARCODE,DESIGNNO`);return{barcode:parts[0],designNo:parts[1]}});if(!items.length){toast('Paste at least one mapping','error');return}try{loading(true,'Saving batch…');const data=await admin('mapBatch',{items});const failures=data.results.filter(x=>!x.ok);state.mappings=await admin('listMappings');renderMappings();$('batch').value='';toast(failures.length?`${items.length-failures.length} saved; ${failures.length} failed`:`${items.length} mappings saved`,failures.length?'error':'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('camera').onclick=async()=>{if(state.scanning){await stopScanner();return}try{state.scanner=new Html5Qrcode('reader');$('reader').classList.add('open');await state.scanner.start({facingMode:'environment'},{fps:10,qrbox:{width:260,height:160}},async code=>{$('barcode').value=code;await stopScanner();$('design-search').focus()},()=>{});state.scanning=true;$('camera').textContent='Close camera scanner'}catch(err){toast('Camera could not start: '+err,'error');await stopScanner()}};async function stopScanner(){if(state.scanner){try{if(state.scanning)await state.scanner.stop()}catch{}try{await state.scanner.clear()}catch{}}state.scanner=null;state.scanning=false;$('reader').classList.remove('open');$('camera').textContent='Open camera scanner'}
if(sb){sb.auth.getSession().then(async({data})=>{if(data.session){try{loading(true,'Loading mapping tool…');await loadTool()}catch(e){await sb.auth.signOut();toast(e.message,'error');show(false)}finally{loading(false)}}else show(false)})}else show(false);
</script>
</body></html>
```

