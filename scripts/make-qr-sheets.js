/**
 * Maitri Carnival 2026 — printable A3 QR sticker sheets (Karwa Chauth theme).
 *
 * One unified run of 1000 codes on 4 cm tags carrying BOTH firm logos
 * (Maitri + Niharika), a deep-red festive ground with a gold crescent moon and
 * hairline frame, and a maximised ~26 mm QR on a clean ivory panel so it scans
 * first-try. A tag is brand-neutral — it is mapped to whatever design it lands on.
 *
 * Layout: A3 portrait, 8 x 9 = 72 tags/page -> 14 pages for 1000. Rounded cut
 * guides for a normal sticker sheet (trim to taste).
 *
 * Run:  node scripts/make-qr-sheets.js
 * Needs: npm install qrcode pdfkit
 * Out:   barcodes/Maitri-Carnival-QR-A3.pdf  +  barcodes/barcode-list.csv
 */

const fs = require("fs");
const path = require("path");
const QRCode = require("qrcode");
const PDFDocument = require("pdfkit");

// ── Config ────────────────────────────────────────────────────────────────
const CODE_PREFIX = "MC";   // Maitri Carnival. MT/EK are already mapped — keep this distinct.
// The block to emit. START is the ONLY line to change for the next block; COUNT is
// its size. The printed run was START=1, COUNT=1000 (MC-0001..MC-1000); this block is
// START=1001, COUNT=500 (MC-1001..MC-1500). NEVER start at or below the highest number
// already printed — MC-0907..MC-1000 are unused stock, so reprinting <1001 would put
// two identical stickers on two garments.
const START = 1001;
const COUNT = 500;
const FIRST = START, LAST = START + COUNT - 1;
const RANGE = `${CODE_PREFIX}${FIRST}-${CODE_PREFIX}${LAST}`;   // e.g. MC1001-MC1500 — drives the output filenames
const codeFor = (n) => `${CODE_PREFIX}-${String(n).padStart(4, "0")}`;

// Karwa Chauth palette
const RED = "#8E1A2E";      // festive ground
const GOLD = "#B8922F";     // moon + hairline
const IVORY = "#F9F3E6";    // logo + QR panels (keeps the red from shouting)
const INK = "#2A1C1E";      // QR modules + logo legibility
const CREAM = "#F6E6C9";    // code text on red

const mm = (v) => v * 2.834645669291339;         // mm -> pt
const PAGE_W = mm(297), PAGE_H = mm(420);         // A3 portrait
const M_SIDE = mm(8), M_TOP = mm(8), M_BOT = mm(12);

const COLS = 8, ROWS = 9;                          // 72 tags/page
const GRID_W = PAGE_W - M_SIDE * 2;
const GRID_H = PAGE_H - M_TOP - M_BOT;
const CELL_W = GRID_W / COLS;
const CELL_H = GRID_H / ROWS;

// Tag geometry (within a cell) — 31 x 40 mm, QR maximised to the vertical space.
const TAG_W = mm(31), TAG_H = mm(40), TAG_R = mm(2.2);
const PAD = mm(1.5);
const CHIP_H = mm(5.4);                             // both logos
const CODE_H = mm(4.6);                             // code band (red)
const QR_PANEL_Y = PAD + CHIP_H + mm(0.9);
const QR_PANEL_H = TAG_H - QR_PANEL_Y - CODE_H - mm(0.4);
const QR_SIZE = Math.min(TAG_W - PAD * 2 - mm(1.6), QR_PANEL_H - mm(1.6)); // ~26 mm

const ASSETS = path.join(__dirname, "..", "web", "assets");
const LOGOS = [path.join(ASSETS, "maitri-logo.png"), path.join(ASSETS, "niharika-logo.png")];
const OUT_DIR = path.join(__dirname, "..", "barcodes");

async function qrPng(text) {
  return QRCode.toBuffer(text, {
    type: "png", errorCorrectionLevel: "M", margin: 1, width: 520,
    color: { dark: INK, light: IVORY },
  });
}

// Draw one tag with its top-left at (ox, oy).
function drawTag(doc, ox, oy, qrBuf, code) {
  // red ground + gold hairline frame
  doc.save();
  doc.roundedRect(ox, oy, TAG_W, TAG_H, TAG_R).fill(RED);
  doc.lineWidth(0.5).strokeColor(GOLD)
    .roundedRect(ox + mm(0.9), oy + mm(0.9), TAG_W - mm(1.8), TAG_H - mm(1.8), TAG_R - mm(0.7)).stroke();

  // logo chip (ivory) with both firm marks side by side
  const chipX = ox + PAD, chipY = oy + PAD, chipW = TAG_W - PAD * 2;
  doc.roundedRect(chipX, chipY, chipW, CHIP_H, mm(0.9)).fill(IVORY);
  const half = (chipW - mm(2)) / 2;
  LOGOS.forEach((logo, i) => {
    if (!fs.existsSync(logo)) return;
    try {
      doc.image(logo, chipX + mm(1) + i * half + (i === 1 ? mm(1) : 0), chipY + mm(0.7),
        { fit: [half - mm(1), CHIP_H - mm(1.4)], align: "center", valign: "center" });
    } catch (_) { /* ignore */ }
  });
  // slim gold divider between the two logos
  doc.lineWidth(0.4).strokeColor(GOLD).opacity(0.6)
    .moveTo(chipX + chipW / 2, chipY + mm(1)).lineTo(chipX + chipW / 2, chipY + CHIP_H - mm(1)).stroke().opacity(1);

  // QR panel (ivory) + QR, centered and maximised
  const panelX = ox + PAD, panelW = TAG_W - PAD * 2;
  doc.roundedRect(panelX, oy + QR_PANEL_Y, panelW, QR_PANEL_H, mm(0.9)).fill(IVORY);
  doc.image(qrBuf, ox + (TAG_W - QR_SIZE) / 2, oy + QR_PANEL_Y + (QR_PANEL_H - QR_SIZE) / 2,
    { width: QR_SIZE, height: QR_SIZE });

  // code band (on red): gold crescent moon + human-readable code
  const bandCy = oy + TAG_H - CODE_H / 2;
  const mr = mm(1.15), mx = ox + TAG_W / 2 - mm(9);
  doc.fillColor(GOLD).circle(mx, bandCy, mr).fill();
  doc.fillColor(RED).circle(mx + mr * 0.6, bandCy - mr * 0.18, mr).fill(); // carve crescent
  doc.fillColor(CREAM).font("Helvetica-Bold").fontSize(8.2)
    .text(code, ox, bandCy - mm(1.5), { width: TAG_W, align: "center" });
  doc.restore();
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const codes = Array.from({ length: COUNT }, (_, i) => codeFor(i + START));
  const perPage = COLS * ROWS, pages = Math.ceil(COUNT / perPage);
  console.log(`A3 ${COLS}x${ROWS} = ${perPage}/page · tag ${(TAG_W / 2.834645669).toFixed(0)}x${(TAG_H / 2.834645669).toFixed(0)}mm · QR ${(QR_SIZE / 2.834645669).toFixed(1)}mm · ${COUNT} codes ${codes[0]}..${codes[codes.length - 1]} -> ${pages} pages`);

  process.stdout.write(`Rendering ${COUNT} QR codes… `);
  const pngs = [];
  for (const c of codes) pngs.push(await qrPng(c));
  console.log("done");

  const outFile = path.join(OUT_DIR, `Maitri-Carnival-QR-${RANGE}-A3.pdf`);
  const doc = new PDFDocument({ size: [PAGE_W, PAGE_H], margin: 0, autoFirstPage: false });
  doc.pipe(fs.createWriteStream(outFile));

  for (let p = 0; p < pages; p++) {
    doc.addPage();
    doc.rect(0, 0, PAGE_W, PAGE_H).fill("#FFFFFF"); // explicit white paper in every viewer
    const slice = codes.slice(p * perPage, p * perPage + perPage);
    for (let i = 0; i < slice.length; i++) {
      const col = i % COLS, row = Math.floor(i / COLS);
      const cx = M_SIDE + col * CELL_W + (CELL_W - TAG_W) / 2;
      const cy = M_TOP + row * CELL_H + (CELL_H - TAG_H) / 2;
      drawTag(doc, cx, cy, pngs[p * perPage + i], slice[i]);
    }
    doc.fillColor("#8A6A55").font("Helvetica").fontSize(7)
      .text(`Maitri Carnival 2026 · Karwa Chauth · Sheet ${p + 1}/${pages} · ${slice[0]}–${slice[slice.length - 1]}`,
        M_SIDE, PAGE_H - M_BOT + mm(3.4), { width: GRID_W, align: "center" });
  }
  doc.end();
  await new Promise((r) => doc.on("end", r));

  const csv = ["barcode,designNo"].concat(codes.map((c) => `${c},`));
  // Range-named to match the PDF, so a new block never clobbers a prior block's list
  // (nor the original barcode-list.csv). Rename to barcode-list.csv when bulk-importing.
  const csvFile = path.join(OUT_DIR, `Maitri-Carnival-QR-${RANGE}.csv`);
  fs.writeFileSync(csvFile, csv.join("\n") + "\n");
  console.log(`  → ${path.basename(outFile)} (${pages} pages)`);
  console.log(`  → ${path.basename(csvFile)} (${COUNT} codes, designNo blank — fill in to bulk-import)`);
})();
