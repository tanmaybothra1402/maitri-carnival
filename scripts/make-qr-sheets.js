/**
 * Maitri Carnival 2026 — printable A3 QR sheets.
 *
 * Generates one PDF per brand with 700 unique scannable codes, laid out
 * 10 x 12 = 120 labels per A3 page (6 pages per brand), plus a CSV of every
 * code for barcode mapping.
 *
 * Run:  node scripts/make-qr-sheets.js
 * Needs: npm install qrcode pdfkit
 */

const fs = require("fs");
const path = require("path");
const QRCode = require("qrcode");
const PDFDocument = require("pdfkit");

// ── Config ────────────────────────────────────────────────────────────────
const PER_BRAND = 700;
const BRANDS = [
  { key: "Maitri",   prefix: "MT", logo: "maitri-logo.png",   accent: "#2E2A6B" },
  { key: "Niharika", prefix: "NH", logo: "niharika-logo.png", accent: "#2E2A6B" },
];

const mm = (v) => v * 2.834645669291339;      // mm -> pt
const PAGE_W = mm(297), PAGE_H = mm(420);      // A3 portrait
const M_SIDE = mm(6), M_TOP = mm(6), M_BOT = mm(11); // minimal waste; bottom holds footer

const COLS = 10, ROWS = 12;                    // 120 labels per page
const GRID_W = PAGE_W - M_SIDE * 2;
const GRID_H = PAGE_H - M_TOP - M_BOT;
const CELL_W = GRID_W / COLS;
const CELL_H = GRID_H / ROWS;

const QR_SIZE = mm(21);      // 21mm — comfortably scannable by phone cameras
const LOGO_W = mm(20), LOGO_H = mm(5);
const CUT_GUIDE = "#E3E7E6";

const ASSETS = path.join(__dirname, "..", "web", "assets");
const OUT_DIR = path.join(__dirname, "..", "barcodes");

// ── Helpers ───────────────────────────────────────────────────────────────
const codeFor = (prefix, n) => `${prefix}-${String(n).padStart(4, "0")}`;

async function qrPng(text) {
  return QRCode.toBuffer(text, {
    type: "png",
    errorCorrectionLevel: "M",
    margin: 2,          // quiet zone (plus generous white space in the cell)
    width: 420,         // high-res so print stays crisp
    color: { dark: "#000000", light: "#FFFFFF" },
  });
}

async function buildBrand(brand) {
  const logoPath = path.join(ASSETS, brand.logo);
  const hasLogo = fs.existsSync(logoPath);
  const codes = Array.from({ length: PER_BRAND }, (_, i) => codeFor(brand.prefix, i + 1));

  // Pre-render every QR once.
  process.stdout.write(`  ${brand.key}: rendering ${codes.length} QR codes… `);
  const pngs = [];
  for (const c of codes) pngs.push(await qrPng(c));
  console.log("done");

  const perPage = COLS * ROWS;
  const pages = Math.ceil(codes.length / perPage);
  const outFile = path.join(OUT_DIR, `${brand.key}-QR-A3.pdf`);

  const doc = new PDFDocument({ size: [PAGE_W, PAGE_H], margin: 0, autoFirstPage: false });
  doc.pipe(fs.createWriteStream(outFile));

  for (let p = 0; p < pages; p++) {
    doc.addPage();
    const start = p * perPage;
    const slice = codes.slice(start, start + perPage);

    for (let i = 0; i < slice.length; i++) {
      const col = i % COLS, row = Math.floor(i / COLS);
      const x = M_SIDE + col * CELL_W;
      const y = M_TOP + row * CELL_H;

      // faint cut guide
      doc.save().lineWidth(0.3).strokeColor(CUT_GUIDE).rect(x, y, CELL_W, CELL_H).stroke().restore();

      // brand logo
      if (hasLogo) {
        try {
          doc.image(logoPath, x + (CELL_W - LOGO_W) / 2, y + mm(1.6), {
            fit: [LOGO_W, LOGO_H], align: "center", valign: "center",
          });
        } catch (_) { /* ignore */ }
      }

      // QR
      doc.image(pngs[start + i], x + (CELL_W - QR_SIZE) / 2, y + mm(7.4), {
        width: QR_SIZE, height: QR_SIZE,
      });

      // code text
      doc.save()
        .fillColor(brand.accent)
        .font("Helvetica-Bold")
        .fontSize(7.6)
        .text(slice[i], x, y + mm(29.6), { width: CELL_W, align: "center" })
        .restore();
    }

    // footer
    doc.save()
      .fillColor("#8A918F").font("Helvetica").fontSize(6.4)
      .text(
        `${brand.key.toUpperCase()}  ·  Maitri Carnival 2026  ·  Sheet ${p + 1}/${pages}  ·  ${slice[0]} – ${slice[slice.length - 1]}`,
        M_SIDE, PAGE_H - M_BOT + mm(3.2),
        { width: GRID_W, align: "center" }
      )
      .restore();
  }

  doc.end();
  return { outFile, pages, codes };
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  console.log(`A3 ${COLS}x${ROWS} = ${COLS * ROWS} labels/page · QR ${(QR_SIZE / 2.834645669).toFixed(1)}mm`);

  const csv = ["barcode,brand"];
  for (const brand of BRANDS) {
    const { outFile, pages, codes } = await buildBrand(brand);
    codes.forEach((c) => csv.push(`${c},${brand.key}`));
    console.log(`  → ${path.basename(outFile)}  (${codes.length} codes, ${pages} pages)`);
  }

  const csvPath = path.join(OUT_DIR, "barcode-list.csv");
  fs.writeFileSync(csvPath, csv.join("\n") + "\n");
  console.log(`  → ${path.basename(csvPath)}  (${csv.length - 1} codes)`);
})();
