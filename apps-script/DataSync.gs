
/**
 * Maitri Carnival 2026 — Supabase two-way data mirror.
 *
 * Supabase is the master database. This workbook lets you PULL every table into
 * tabs, edit values, and PUSH changes back. Only editable columns are written;
 * system columns (ids, versions, timestamps) are shown for reference and ignored
 * on push. Destructive deletes are not available from the Sheet mirror; use
 * active/status or the admin console for operational changes.
 *
 * Setup:
 *   1. Extensions -> Apps Script, paste this file, Save, reload the sheet.
 *   2. Supabase Sync -> "1. Configure connection" (project URL + SHEET_SYNC_SECRET).
 *   3. Supabase Sync -> "Pull ALL tables" to build the workbook.
 * Requires the `data-sync` Edge Function deployed with the same SHEET_SYNC_SECRET.
 */

const DS_PROP_URL = 'DS_SUPABASE_URL';
const DS_PROP_SECRET = 'DS_SHEET_SYNC_SECRET';
const DS_PATH = '/functions/v1/data-sync';

// ── Fill these two in the Apps Script editor to skip "Configure connection". ──
// SECURITY: only paste the real secret into the Apps Script editor copy.
// Keep the repo copy of this file blank so the secret is never committed to GitHub.
const DS_URL = 'https://ezmtiiftolcaslqfvozu.supabase.co';
const DS_SECRET = '';  // <-- paste your SHEET_SYNC_SECRET here (from supabase/.env.production)

// Tab name -> Supabase table.
const DS_TABS = {
  'Designs': 'designs',
  'BarcodeMappings': 'barcode_mappings',
  'Customers': 'customers',
  'Orders': 'orders',
  'OrderItems': 'order_items',
  'Slots': 'slots',
  'Bookings': 'bookings',
  'Settings': 'system_settings',
  'Staff': 'staff_profiles'
};

// Columns that are editable and pushed back (everything else is reference-only).
const DS_EDITABLE = {
  designs: ['firm','image_url','category','style','fabric','pcs_per_set','description','active'],
  barcode_mappings: ['design_no','active'],
  customers: ['company_name','contact_name','city','state','gstin','agent','active'],
  orders: ['status','admin_unlocked'],
  order_items: [],
  slots: ['starts_at','ends_at','label','capacity','active'],
  bookings: ['party_size','note','status','slot_id'],
  system_settings: ['event_name','event_start_date','event_end_date','registration_enabled','edit_window_hours'],
  staff_profiles: []
};

// Tables where removing a row from the sheet and pushing will DELETE it in
// Supabase. Guarded server-side by a freshness token, a delete ceiling, and a
// protected-row list; guarded here by a named confirmation dialog.
const DS_DIFF_DELETABLE = [
  'designs',
  'barcode_mappings',
  'slots',
  'customers',
  'orders',
  'order_items'
];

function onOpen() {
  SpreadsheetApp.getUi().createMenu('Supabase Sync')
    .addItem('① Configure & test', 'dsConfigure')
    .addItem('② Pull ALL tables', 'dsPullAll')
    .addSeparator()
    .addItem('Push this tab', 'dsPushActive')
    .addToUi();
}

// No prompts. Uses the DS_URL + DS_SECRET embedded at the top of the script,
// saves them to Script Properties (so they survive), and tests the connection.
function dsConfigure() {
  if (!DS_URL || !DS_SECRET) { dsAlert_('Paste your key into DS_SECRET at the top of the script, then run this again.'); return; }
  PropertiesService.getScriptProperties().setProperties({ [DS_PROP_URL]: DS_URL, [DS_PROP_SECRET]: DS_SECRET }, false);
  try {
    const d = dsCall_({ action: 'ping' });
    dsAlert_('Connected ✓\nTables: ' + (d.tables || []).join(', '));
  } catch (e) {
    dsAlert_('Saved, but connection failed:\n' + e.message + '\n\nIf this says SHEET_SYNC_AUTH_REQUIRED, set the same secret on the server:\nnpx supabase secrets set SHEET_SYNC_SECRET=...  then redeploy data-sync.');
  }
}

function dsAlert_(msg) { try { SpreadsheetApp.getUi().alert(msg); } catch (e) { Logger.log(msg); } }

function dsCall_(payload) {
  const props = PropertiesService.getScriptProperties();
  const base = String(DS_URL || props.getProperty(DS_PROP_URL) || '').replace(/\/$/, '');
  const secret = String(DS_SECRET || props.getProperty(DS_PROP_SECRET) || '');
  if (!base || !secret) throw new Error('Set DS_URL and DS_SECRET at the top of the script (or run "1. Configure connection").');
  const resp = UrlFetchApp.fetch(base + DS_PATH, {
    method: 'post', contentType: 'application/json',
    headers: { 'x-sheet-sync-secret': secret },
    payload: JSON.stringify(payload || {}), muteHttpExceptions: true
  });
  const code = resp.getResponseCode();
  const text = resp.getContentText();
  let json; try { json = JSON.parse(text); } catch (e) { throw new Error('Non-JSON HTTP ' + code + ': ' + text.slice(0, 300)); }
  if (code < 200 || code >= 300 || !json.ok) throw new Error(json.error || ('HTTP ' + code));
  return json.data;
}

function dsTest() {
  const d = dsCall_({ action: 'ping' });
  dsAlert_('Connected.\nTables: ' + (d.tables || []).join(', ') + '\n' + d.at);
}

function dsTableForTab_(name) { return DS_TABS[name] || null; }

function dsRemoveObsoleteTabs_() {
  const ss = SpreadsheetApp.getActive();
  ['Lookups'].forEach(function (name) {
    const sh = ss.getSheetByName(name);
    if (sh && ss.getSheets().length > 1) ss.deleteSheet(sh);
  });
}

// Freshness tokens. A push is only allowed to delete rows if the tab was
// pulled from the current state of the table. This is what stops the classic
// "pulled at 10am, pushed at 2pm, wiped everyone who registered in between".
function dsTokenKey_(tabName) { return 'DS_TOKEN_' + tabName; }

function dsSetToken_(tabName, token) {
  PropertiesService.getDocumentProperties().setProperty(dsTokenKey_(tabName), String(token || ''));
}

function dsGetToken_(tabName) {
  return PropertiesService.getDocumentProperties().getProperty(dsTokenKey_(tabName)) || '';
}

function dsWrite_(tabName, res) {
  const ss = SpreadsheetApp.getActive();
  let sh = ss.getSheetByName(tabName);
  if (!sh) sh = ss.insertSheet(tabName);
  dsSetToken_(tabName, res.token);
  sh.clear();
  const cols = res.columns || [];
  const editable = DS_EDITABLE[res.table] || [];
  const header = cols.slice();
  const values = [header];
  (res.rows || []).forEach(function (r) {
    const line = cols.map(function (c) { const v = r[c]; if (v === null || v === undefined) return ''; if (v && typeof v === 'object') return JSON.stringify(v); return v; });
    values.push(line);
  });
  sh.getRange(1, 1, values.length, header.length).setValues(values);
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, header.length).setFontWeight('bold').setBackground('#225E63').setFontColor('#FFFFFF');
  // Tint editable columns so it's clear what can be changed.
  cols.forEach(function (c, i) {
    if (editable.indexOf(c) >= 0 && sh.getMaxRows() > 1) {
      sh.getRange(2, i + 1, Math.max(1, values.length - 1), 1).setBackground('#F3FAF8');
    }
  });
  sh.autoResizeColumns(1, Math.min(header.length, 12));
}

function dsPullAll() {
  const all = dsCall_({ action: 'pullAll' });
  dsRemoveObsoleteTabs_();
  Object.keys(DS_TABS).forEach(function (tab) {
    const table = DS_TABS[tab];
    if (all[table]) dsWrite_(tab, all[table]);
  });
  dsAlert_('Pulled all tables. Editable columns are tinted. Edit, then use "Push this tab".');
}

function dsPullActive() {
  const sh = SpreadsheetApp.getActiveSheet();
  const table = dsTableForTab_(sh.getName());
  if (!table) { dsAlert_('This tab is not a synced table. Use one of: ' + Object.keys(DS_TABS).join(', ')); return; }
  dsWrite_(sh.getName(), dsCall_({ action: 'pull', table: table }));
  dsAlert_('Pulled ' + sh.getName() + '.');
}

function dsPushActive() {
  const sh = SpreadsheetApp.getActiveSheet();
  const table = dsTableForTab_(sh.getName());
  if (!table) { dsAlert_('This tab is not a synced table.'); return; }
  const editable = (DS_EDITABLE[table] || []).length > 0;
  const canDelete = DS_DIFF_DELETABLE.indexOf(table) >= 0;
  if (!editable && !canDelete) {
    dsAlert_(sh.getName() + ' is read-only. Make changes in the admin console, then pull again.');
    return;
  }

  const grid = sh.getDataRange().getValues();
  if (grid.length < 2) { dsAlert_('No data rows to push.'); return; }
  const header = grid[0].map(String);
  const rows = [];
  for (var i = 1; i < grid.length; i++) {
    const row = grid[i];
    if (row.every(function (c) { return String(c).trim() === ''; })) continue;
    const obj = {};
    header.forEach(function (h, j) {
      var v = row[j];
      if (v instanceof Date) v = v.toISOString();
      obj[h] = v;
    });
    rows.push(obj);
  }

  // No token check here: a push that only adds or edits rows must always be
  // allowed. The server decides whether freshness matters, because only it
  // knows whether any row would actually be deleted.
  const token = dsGetToken_(sh.getName());

  // Dry run first: find out exactly what would be deleted, and let the
  // operator see the rows by name before anything is touched.
  var plan;
  try {
    plan = dsCall_({ action: 'push', table: table, rows: rows, token: token, dryRun: true });
  } catch (e) {
    dsAlert_(dsExplain_(e.message));
    return;
  }

  const willDelete = plan.willDelete || [];
  if (willDelete.length) {
    const shown = willDelete.slice(0, 20).join('\n  ');
    const more = willDelete.length > 20 ? '\n  ...and ' + (willDelete.length - 20) + ' more' : '';
    const ui = SpreadsheetApp.getUi();
    const answer = ui.alert(
      'Delete ' + willDelete.length + ' row' + (willDelete.length === 1 ? '' : 's') + ' from ' + sh.getName() + '?',
      'These rows are in Supabase but not in your sheet, so they will be PERMANENTLY DELETED:\n\n  ' +
        shown + more + '\n\nThis cannot be undone. Continue?',
      ui.ButtonSet.YES_NO
    );
    if (answer !== ui.Button.YES) { dsAlert_('Cancelled. Nothing was changed.'); return; }
  }

  try {
    const res = dsCall_({ action: 'push', table: table, rows: rows, token: token });
    // The table has moved, so the old token is spent. Force a fresh pull
    // before any further deletion.
    dsSetToken_(sh.getName(), '');
    dsAlert_(
      'Pushed ' + sh.getName() + ':\n' +
      'Updated: ' + (res.updated || 0) + '\n' +
      'Created/Upserted: ' + (res.upserted || 0) + '\n' +
      'Deleted: ' + (res.deleted || 0) +
      (res.deleted ? '\n\nPull again before your next push.' : '')
    );
  } catch (e) {
    dsAlert_(dsExplain_(e.message));
  }
}

// Turns the Edge Function's error codes into something an operator can act on.
function dsExplain_(msg) {
  const m = String(msg || '');
  if (m.indexOf('SHEET_IS_STALE') >= 0) {
    return 'This tab is out of date.\n\nSomeone changed the data in the app since you last pulled, so deleting now could remove records you cannot see. Pull this tab again, redo your edits, then push.';
  }
  if (m.indexOf('TOO_MANY_DELETES') >= 0) {
    return 'Too many rows would be deleted.\n\n' + m + '\n\nThis almost always means the sheet is incomplete, filtered, or was pulled a while ago. Pull again and check before retrying.';
  }
  if (m.indexOf('PROTECTED_ROWS') >= 0) {
    return 'Some rows are protected and cannot be deleted from the sheet.\n\n' + m;
  }
  if (m.indexOf('DUPLICATE_') >= 0 && m.indexOf('_IN_SHEET') >= 0) {
    return 'Duplicate keys in your sheet.\n\n' + m + '\n\nUse a helper column with =IF(COUNTIF(A:A,A2)>1,"DUP","") to find them, remove the extra rows, then push again.';
  }
  if (m.indexOf('cannot affect row a second time') >= 0) {
    return 'Your sheet has two rows with the same key (for Designs, the same design_no).\n\nUse =IF(COUNTIF(A:A,A2)>1,"DUP","") in a helper column to find them. Nothing was saved.';
  }
  if (m.indexOf('PULL_REQUIRED') >= 0) {
    return 'Pull this tab before pushing. Deleting rows requires a fresh pull.';
  }
  return m;
}
