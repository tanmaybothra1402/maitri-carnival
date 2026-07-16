
/**
 * Maitri Carnival 2026 — Supabase two-way data mirror.
 *
 * Supabase is the master database. This workbook lets you PULL every table into
 * tabs, edit values, and PUSH changes back. Only editable columns are written;
 * system columns (ids, versions, timestamps) are shown for reference and ignored
 * on push. `_delete` is intentionally accepted only on the low-risk Lookups tab;
 * use active/status or the admin console for every operational table.
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
const DS_SECRET = '0cbd403785f28e9dde753b8d204827dec84d8b783b767a0417cafa33cf04431d';  // <-- paste your SHEET_SYNC_SECRET here (from supabase/.env.production)

// Tab name -> Supabase table.
const DS_TABS = {
  'Designs': 'designs',
  'BarcodeMappings': 'barcode_mappings',
  'Customers': 'customers',
  'Orders': 'orders',
  'OrderItems': 'order_items',
  'Slots': 'slots',
  'Bookings': 'bookings',
  'Lookups': 'lookup_values',
  'Settings': 'system_settings',
  'Staff': 'staff_profiles'
};

// Columns that are editable and pushed back (everything else is reference-only).
const DS_EDITABLE = {
  designs: ['firm','image_url','category','style','fabric','pcs_per_set','description','active'],
  barcode_mappings: ['design_no','active'],
  customers: ['company_name','contact_name','city','state','gstin','agent','active'],
  orders: ['status','admin_unlocked'],
  order_items: ['qty','line_note'],
  slots: ['starts_at','ends_at','label','capacity','active'],
  bookings: ['party_size','note','status','slot_id'],
  lookup_values: ['kind','value'],
  system_settings: ['event_name','event_start_date','event_end_date','registration_enabled','edit_window_hours'],
  staff_profiles: []
};

function onOpen() {
  SpreadsheetApp.getUi().createMenu('Supabase Sync')
    .addItem('1. Configure connection', 'dsConfigure')
    .addSeparator()
    .addItem('Pull ALL tables', 'dsPullAll')
    .addItem('Pull this tab', 'dsPullActive')
    .addItem('Push this tab', 'dsPushActive')
    .addSeparator()
    .addItem('Test connection', 'dsTest')
    .addToUi();
}

function dsConfigure() {
  const ui = SpreadsheetApp.getUi();
  const props = PropertiesService.getScriptProperties();
  const u = ui.prompt('Supabase project URL', 'e.g. https://ezmtiiftolcaslqfvozu.supabase.co', ui.ButtonSet.OK_CANCEL);
  if (u.getSelectedButton() !== ui.Button.OK) return;
  const url = String(u.getResponseText() || '').trim().replace(/\/$/, '');
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(url)) throw new Error('Enter a valid Supabase project URL.');
  const s = ui.prompt('SHEET_SYNC_SECRET', 'The same secret configured in Supabase.', ui.ButtonSet.OK_CANCEL);
  if (s.getSelectedButton() !== ui.Button.OK) return;
  const secret = String(s.getResponseText() || '').trim();
  if (secret.length < 24) throw new Error('Use the full secret (24+ characters).');
  props.setProperties({ [DS_PROP_URL]: url, [DS_PROP_SECRET]: secret }, false);
  ui.alert('Saved. Now run "Pull ALL tables".');
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

function dsWrite_(tabName, res) {
  const ss = SpreadsheetApp.getActive();
  let sh = ss.getSheetByName(tabName);
  if (!sh) sh = ss.insertSheet(tabName);
  sh.clear();
  const cols = res.columns || [];
  const editable = DS_EDITABLE[res.table] || [];
  const header = cols.concat(['_delete']);
  const values = [header];
  (res.rows || []).forEach(function (r) {
    const line = cols.map(function (c) { const v = r[c]; if (v === null || v === undefined) return ''; if (v && typeof v === 'object') return JSON.stringify(v); return v; });
    line.push('');
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
  const res = dsCall_({ action: 'push', table: table, rows: rows });
  dsAlert_('Pushed ' + sh.getName() + ':\nUpdated: ' + (res.updated || 0) + '\nCreated/Upserted: ' + (res.upserted || 0) + '\nDeleted: ' + (res.deleted || 0));
}
