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
