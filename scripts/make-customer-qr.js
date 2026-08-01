/**
 * Maitri Carnival 2026 — customer QR table tents.
 *
 * Produces A5 table tents (2-up on A4 portrait, with a cut line) carrying the
 * Maitri logo and a QR code pointing at the customer ordering page.
 *
 * Run:  node scripts/make-customer-qr.js <exhibition-slug> ["Event Name"] ["Dates"]
 *   e.g. node scripts/make-customer-qr.js carnival-2026 "Maitri Carnival 2026" "19 – 21 July 2026"
 * Needs: npm install qrcode pdfkit
 */

const fs = require("fs");
const path = require("path");
const QRCode = require("qrcode");
const PDFDocument = require("pdfkit");

// ── Config ────────────────────────────────────────────────────────────────
// The exhibition slug is required; it becomes ?e=<slug> so the customer app
// resolves the right event. Name/dates are optional label text for the card.
const SLUG = (process.argv[2] || "").trim().toLowerCase();
if (!SLUG) {
  console.error('Usage: node scripts/make-customer-qr.js <exhibition-slug> ["Event Name"] ["Dates"]');
  process.exit(1);
}
const EVENT_NAME = (process.argv[3] || "").trim();
const EVENT_DATES = (process.argv[4] || "").trim();
const BASE = "https://tanmaybothra1402.github.io/maitri-carnival/user.html";
const LINK = `${BASE}?e=${encodeURIComponent(SLUG)}`;

const TEAL_DEEP = "#225E63";
const TEAL = "#2B7379";
const MUTED = "#7A8280";
const INDIGO = "#2E2A6B"; // Maitri
const WARM = "#F7F3EA";

const mm = (v) => v * 2.834645669291339;
const PAGE_W = mm(210), PAGE_H = mm(297); // A4 portrait
const CARD_W = PAGE_W, CARD_H = PAGE_H / 2; // two A5 landscape cards

const ASSETS = path.join(__dirname, "..", "web", "assets");
const OUT_DIR = path.join(__dirname, "..", "barcodes");

// Error correction H so the card survives being creased, smudged or
// partially covered on a busy table.
async function qrPng(text) {
  return QRCode.toBuffer(text, {
    type: "png",
    errorCorrectionLevel: "H",
    margin: 1,
    width: 1200,
    color: { dark: "#101615", light: "#FFFFFF" },
  });
}

function drawCard(doc, qr, logoPath, x, y) {
  const hasLogo = fs.existsSync(logoPath);

  // Warm background panel with a hairline border.
  doc.save()
    .rect(x + mm(6), y + mm(6), CARD_W - mm(12), CARD_H - mm(12))
    .fillOpacity(1).fill(WARM)
    .restore();
  doc.save()
    .lineWidth(0.6).strokeColor("#E4DCC8")
    .rect(x + mm(6), y + mm(6), CARD_W - mm(12), CARD_H - mm(12))
    .stroke()
    .restore();

  const cx = x + CARD_W / 2;

  // Maitri logo, centred.
  if (hasLogo) {
    const lw = mm(46), lh = mm(15);
    try {
      doc.image(logoPath, cx - lw / 2, y + mm(13), {
        fit: [lw, lh], align: "center", valign: "center",
      });
    } catch (_) { /* fall through to wordmark */ }
  } else {
    doc.save().fillColor(INDIGO).font("Helvetica-Bold").fontSize(20)
      .text("MAITRI", x, y + mm(15), { width: CARD_W, align: "center" })
      .restore();
  }

  // Headline
  doc.save().fillColor(TEAL_DEEP).font("Helvetica-Bold").fontSize(15)
    .text("Scan to place your order", x, y + mm(32), { width: CARD_W, align: "center" })
    .restore();

  doc.save().fillColor(MUTED).font("Helvetica").fontSize(8.6)
    .text([EVENT_NAME || SLUG, EVENT_DATES].filter(Boolean).join("  ·  "), x, y + mm(39.5), { width: CARD_W, align: "center" })
    .restore();

  // QR with a white plate behind it for scan contrast against the warm panel.
  const q = mm(46);
  const qx = cx - q / 2, qy = y + mm(46);
  doc.save().fillColor("#FFFFFF")
    .roundedRect(qx - mm(3), qy - mm(3), q + mm(6), q + mm(6), mm(3)).fill()
    .restore();
  doc.image(qr, qx, qy, { width: q, height: q });

  // Steps
  const stepsY = qy + q + mm(6);
  doc.save().fillColor(TEAL).font("Helvetica-Bold").fontSize(8.4)
    .text(
      "Open the camera  ·  Scan  ·  Register with your mobile number",
      x, stepsY, { width: CARD_W, align: "center" }
    )
    .restore();

  doc.save().fillColor(MUTED).font("Helvetica").fontSize(7)
    .text("Or type:  " + LINK.replace(/^https:\/\//, ""), x, stepsY + mm(5.5), {
      width: CARD_W, align: "center",
    })
    .restore();
}

(async () => {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const qr = await qrPng(LINK);
  const logoPath = path.join(ASSETS, "maitri-logo.png");

  const outFile = path.join(OUT_DIR, `Customer-QR-${SLUG}-TableTent-A5.pdf`);
  const doc = new PDFDocument({ size: [PAGE_W, PAGE_H], margin: 0, autoFirstPage: false });
  doc.pipe(fs.createWriteStream(outFile));

  doc.addPage();
  drawCard(doc, qr, logoPath, 0, 0);
  drawCard(doc, qr, logoPath, 0, CARD_H);

  // Cut line between the two cards.
  doc.save().lineWidth(0.4).strokeColor("#C9D2CF").dash(4, { space: 3 })
    .moveTo(mm(4), CARD_H).lineTo(PAGE_W - mm(4), CARD_H).stroke()
    .undash().restore();

  doc.end();

  // Plain PNG of the QR alone, for WhatsApp / invites.
  const pngName = `Customer-QR-${SLUG}.png`;
  fs.writeFileSync(path.join(OUT_DIR, pngName), qr);

  console.log("Link:", LINK);
  console.log("  →", path.basename(outFile), "(A5 table tents, 2-up on A4)");
  console.log("  →", pngName, "(plain QR)");
})();
