BUNDLE 1 of 6 — FRONTEND (static HTML apps). Contains 2 files, separated by FILE markers.


################################################################################
# FILE: web/user.html
################################################################################

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#225E63">
  <title>Maitri Carnival 2026 · Orders</title>
  <link rel="preconnect" href="https://ezmtiiftolcaslqfvozu.supabase.co">
  <link rel="preconnect" href="https://ik.imagekit.io" crossorigin>
  <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <style>
    :root{--teal:#2B7379;--teal-deep:#225E63;--foam:#E8F2F1;--warm:#F7F3EA;--white:#FFFFFF;--border:#E4E8E6;--muted:#7B817F;--slate:#3D3A37;--charcoal:#33271B;--orange:#FF9700;--success:#15803D;--error:#DC2626;--indigo:#2E2A6B;--pink:#E6007E}
    html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
    *{box-sizing:border-box;margin:0;-webkit-tap-highlight-color:transparent}
    html,body{min-height:100%;max-width:100%;overflow-x:hidden;background:var(--warm);color:var(--charcoal);font-family:Inter,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
    button,input,select,textarea{font:inherit}.hidden{display:none!important}img,svg{max-width:100%}
    .appbar{position:sticky;top:0;z-index:50;display:flex;align-items:center;gap:10px;min-height:60px;padding:9px 14px;background:rgba(255,255,255,.97);border-bottom:1px solid var(--border);backdrop-filter:blur(12px)}
    .brandlock{display:flex;align-items:center;gap:9px;min-width:0;overflow:hidden}
    .wordmark{display:flex;align-items:center;gap:7px;color:var(--teal-deep);font-size:15px;font-weight:800;letter-spacing:.12em}
    .logo-dot{width:12px;height:12px;border-radius:50%;background:var(--orange);flex:0 0 auto}
    .brand-sub{display:block;color:var(--muted);font-size:8.5px;font-weight:700;letter-spacing:.13em;text-transform:uppercase;margin-top:1px;white-space:nowrap}
    .bdiv{width:1px;height:24px;background:var(--border);flex:0 0 auto}
    .firmlogos{display:flex;align-items:center;gap:9px}.firm-logo{height:17px;width:auto;display:block}
    .top-actions{margin-left:auto;display:flex;gap:7px}
    .icon-btn{min-height:38px;padding:0 12px;border:1px solid var(--border);border-radius:10px;background:#fff;color:var(--teal-deep);font-size:12px;font-weight:750;cursor:pointer}
    main{width:min(100%,600px);margin:0 auto;padding:16px 13px 40px}
    .brandbar{display:flex;align-items:center;justify-content:center;gap:12px;flex-wrap:wrap;padding:12px;margin-bottom:13px;border:1px solid var(--border);border-radius:14px;background:#fff}
    .brandbar .firm-logo{height:20px}.brandbar .wordmark{font-size:16px}
    .hero{padding:22px;border-radius:18px;background:linear-gradient(135deg,var(--teal-deep),#17494D);color:#fff;box-shadow:0 15px 34px rgba(34,94,99,.18)}
    .hero h1{font-size:23px}.hero p{margin-top:8px;color:rgba(255,255,255,.82);font-size:12.5px;line-height:1.55}.hero .dates{display:inline-block;margin-top:10px;padding:5px 11px;border-radius:20px;background:rgba(255,255,255,.16);font-size:11px;font-weight:700;letter-spacing:.03em}
    .card{margin-top:13px;padding:17px;border:1px solid var(--border);border-radius:15px;background:#fff;box-shadow:0 6px 18px rgba(34,94,99,.06)}
    .card h2{color:var(--teal-deep);font-size:15px}.copy{margin-top:5px;color:var(--muted);font-size:11.5px;line-height:1.55}
    label{display:block;margin:12px 0 5px;color:var(--slate);font-size:10px;font-weight:800;letter-spacing:.05em;text-transform:uppercase}
    .optional{color:var(--muted);font-weight:500;letter-spacing:0;text-transform:none}
    input,select,textarea{width:100%;border:1px solid #D8E1DE;border-radius:10px;background:#fff;color:var(--charcoal);font-size:16px}
    input,select{min-height:47px;padding:0 13px}textarea{min-height:74px;padding:11px 13px;resize:vertical}
    input:focus,select:focus,textarea:focus{outline:2px solid var(--teal);outline-offset:0;border-color:transparent}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px}
    .phone{display:flex;gap:8px}.prefix{width:60px;min-width:60px;display:grid;place-items:center;border:1px solid #D8E1DE;border-radius:10px;background:var(--foam);color:var(--teal-deep);font-weight:800}
    .btn{width:100%;min-height:48px;margin-top:13px;border:0;border-radius:10px;background:var(--teal-deep);color:#fff;font-size:14px;font-weight:800;cursor:pointer}
    .btn.secondary{border:1.5px solid var(--teal-deep);background:#fff;color:var(--teal-deep)}
    .btn.ghost{border:1px solid var(--border);background:#fff;color:var(--slate)}
    .btn:disabled{background:#E7EBE9;color:#949A97;cursor:not-allowed}
    .switch{display:flex;gap:4px;padding:4px;border-radius:13px;background:var(--foam)}
    .switch button{flex:1;min-height:40px;border:0;border-radius:9px;background:transparent;color:var(--teal-deep);font-size:12px;font-weight:800;cursor:pointer}
    .switch button.active{background:#fff;box-shadow:0 2px 8px rgba(34,94,99,.12)}
    .steps{margin-top:12px;display:grid;gap:8px}
    .step{display:flex;gap:11px;align-items:flex-start;padding:10px 12px;border:1px solid var(--border);border-radius:11px;background:#fff}
    .step .n{width:24px;height:24px;flex:0 0 auto;display:grid;place-items:center;border-radius:50%;background:var(--foam);color:var(--teal-deep);font-size:11px;font-weight:800}
    .step.done .n{background:var(--success);color:#fff}.step.active .n{background:var(--orange);color:#fff}
    .step b{font-size:12.5px;color:var(--charcoal)}.step p{margin-top:2px;color:var(--muted);font-size:11px;line-height:1.45}
    .status-banner{display:flex;gap:11px;align-items:center;padding:13px 15px;border-radius:13px;font-size:12.5px;line-height:1.45}
    .status-banner.wait{background:#FFF5DF;color:#8A5A09;border:1px solid #F4D69B}
    .status-banner.ok{background:#DCFCE7;color:#166534;border:1px solid #A7E9BF}
    .status-banner .dot{width:10px;height:10px;border-radius:50%;flex:0 0 auto}
    .status-banner.wait .dot{background:var(--orange);animation:pulse 1.4s ease-in-out infinite}
    .status-banner.ok .dot{background:var(--success)}
    @keyframes pulse{0%,100%{opacity:1}50%{opacity:.3}}
    .booked-summary{display:flex;align-items:center;gap:10px;padding:12px 14px;border:1px solid var(--teal);border-radius:12px;background:var(--foam);margin-top:6px}
    .booked-summary b{color:var(--teal-deep);font-size:13px}.booked-summary .chg{margin-left:auto}
    .slot-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:11px}
    .slot-col{display:flex;flex-direction:column;gap:6px;min-width:0}
    .slot-colhead{font-size:11px;font-weight:800;color:var(--teal-deep);text-align:center;padding:7px 4px;background:var(--foam);border-radius:9px}
    .slot-cell{padding:11px 4px;border:1px solid var(--border);border-radius:10px;background:#fff;color:var(--charcoal);font-size:12px;cursor:pointer;text-align:center;line-height:1.2}
    .slot-cell b{display:block;font-size:12px;font-weight:800}.slot-cell small{display:block;font-size:9px;color:var(--muted);margin-top:2px}
    .slot-cell.picked{border-color:var(--teal);background:var(--foam);box-shadow:0 0 0 2px rgba(43,115,121,.16)}
    .slot-cell.full{opacity:.4;cursor:not-allowed}
    .countdown{position:sticky;top:60px;z-index:30;margin:0 0 12px;padding:11px 14px;border-radius:12px;background:linear-gradient(135deg,#225E63,#2B7379);color:#fff;display:flex;align-items:center;gap:10px;font-size:12px}
    .countdown.closed{background:#4B5563}.countdown b{font-variant-numeric:tabular-nums;font-size:13px}
    .firm-tabs{position:sticky;top:60px;z-index:29;display:grid;grid-template-columns:1fr 1fr;gap:5px;margin:0 -1px 11px;padding:5px;border:1px solid var(--border);border-radius:14px;background:rgba(255,255,255,.97);backdrop-filter:blur(10px)}
    .firm-tab{min-height:46px;border:0;border-radius:10px;background:transparent;color:var(--muted);font-weight:800;cursor:pointer;letter-spacing:.04em}
    .firm-tab.active{background:var(--teal-deep);color:#fff}
    .summary{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:11px}
    .metric{padding:11px;border-radius:11px;background:var(--foam);text-align:center}.metric b{display:block;color:var(--teal-deep);font-size:20px}.metric span{font-size:9px;color:var(--muted);text-transform:uppercase;letter-spacing:.04em}
    .scan-actions{display:grid;grid-template-columns:1fr auto;gap:8px;align-items:end}.scan-actions .btn{width:auto;min-width:104px;margin:0}
    .reader{display:none;margin-top:12px;overflow:hidden;border-radius:13px}.reader.open{display:block}
    .notice{margin-top:10px;padding:10px 12px;border-radius:10px;background:#FFF5DF;color:#8A5A09;font-size:11px;line-height:1.45}.notice.error{background:#FEE2E2;color:#991B1B}.notice.success{background:#DCFCE7;color:#166534}
    .items{display:grid;gap:10px;margin-top:12px}
    .item{display:grid;grid-template-columns:84px minmax(0,1fr);gap:11px;padding:11px;border:1px solid var(--border);border-radius:13px;background:#fff}
    .thumb{width:84px;height:112px;border-radius:10px;background:#EEF2F0 center/cover no-repeat;object-fit:cover;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none}
    .item h3{font-size:14px;color:var(--teal-deep)}.meta{margin-top:4px;color:var(--muted);font-size:10.5px;line-height:1.45}
    .qty{display:flex;align-items:center;gap:5px;margin-top:9px}.qty button{width:36px;height:36px;border:1px solid var(--border);border-radius:9px;background:#fff;color:var(--teal-deep);font-size:18px;font-weight:800;cursor:pointer}
    .qty input{width:58px;min-height:36px;height:36px;padding:0;text-align:center;font-weight:800}.remove{margin-left:auto!important;color:var(--error)!important}
    .savebar{position:sticky;bottom:8px;z-index:25;display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:14px;padding:8px;border:1px solid var(--border);border-radius:14px;background:rgba(255,255,255,.97);box-shadow:0 10px 30px rgba(34,55,52,.14);backdrop-filter:blur(10px)}.savebar .btn{margin:0}
    .empty{padding:26px 12px;border:1px dashed #BCD0CB;border-radius:13px;background:#F8FBFA;color:var(--muted);font-size:12px;text-align:center}
    .toast{position:fixed;left:50%;top:70px;z-index:200;display:none;max-width:90%;padding:10px 16px;border-radius:22px;background:var(--charcoal);color:#fff;font-size:12px;transform:translateX(-50%);box-shadow:0 9px 25px rgba(0,0,0,.18)}.toast.open{display:block}.toast.error{background:#B91C1C}.toast.success{background:#166534}
    .loading{position:fixed;inset:0;z-index:180;display:none;place-items:center;background:rgba(25,31,29,.46)}.loading.open{display:grid}.loader-card{padding:22px 28px;border-radius:15px;background:#fff;color:var(--teal-deep);font-weight:800}.spinner{width:28px;height:28px;margin:0 auto 10px;border:3px solid var(--foam);border-top-color:var(--teal-deep);border-radius:50%;animation:spin .8s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}
    .modal{position:fixed;inset:0;z-index:210;display:none;place-items:center;padding:18px;background:rgba(24,30,28,.55)}.modal.open{display:grid}
    .modal-card{width:min(100%,420px);padding:22px;border-radius:18px;background:#fff;text-align:center}
    .cred{margin-top:14px;padding:14px;border:1px dashed var(--teal);border-radius:12px;background:var(--foam);text-align:left}
    .cred-row{display:flex;justify-content:space-between;gap:10px;padding:6px 0;font-size:13px}.cred-row b{color:var(--teal-deep)}.cred-row span{font-weight:800;color:var(--charcoal);word-break:break-all}
    .config-warning{padding:12px;background:#FEE2E2;color:#991B1B;font-size:12px;text-align:center}
    .account-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    @media(max-width:520px){.firmlogos,.bdiv{display:none}}
    @media(max-width:480px){.grid2,.account-grid{grid-template-columns:1fr}.item{grid-template-columns:76px minmax(0,1fr)}.thumb{width:76px;height:101px}.scan-actions{grid-template-columns:1fr}.scan-actions .btn{width:100%}}
  </style>
</head>
<body oncontextmenu="return false">
  <div id="config-warning" class="config-warning hidden">Replace the Supabase placeholders in this file before publishing.</div>
  <header class="appbar hidden" id="app-top">
    <div class="brandlock">
      <div><div class="wordmark"><i class="logo-dot"></i>EKUM</div><small class="brand-sub">Maitri Carnival 2026</small></div>
      <span class="bdiv"></span>
      <span class="firmlogos">
        <svg class="firm-logo" viewBox="0 0 92 26" role="img" aria-label="Maitri"><text x="1" y="19" font-family="Georgia,'Times New Roman',serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">maitri</text><circle cx="80" cy="8" r="5" fill="#8DC63F"/><circle cx="80" cy="8" r="2.2" fill="#2E2A6B"/></svg>
        <svg class="firm-logo" viewBox="0 0 112 26" role="img" aria-label="Niharika"><text x="1" y="19" font-family="Georgia,'Times New Roman',serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">Niharika</text><path d="M99 5 q9 1 8 11 q-5 -5 -8 -11z" fill="#E6007E"/></svg>
      </span>
    </div>
    <div class="top-actions"><button class="icon-btn" id="account-btn">Account</button><button class="icon-btn" id="logout-btn">Logout</button></div>
  </header>

  <main>
    <!-- AUTH -->
    <section id="auth-screen">
      <div class="brandbar">
        <div class="wordmark"><i class="logo-dot"></i>EKUM</div>
        <svg class="firm-logo" viewBox="0 0 92 26" role="img" aria-label="Maitri"><text x="1" y="19" font-family="Georgia,serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">maitri</text><circle cx="80" cy="8" r="5" fill="#8DC63F"/><circle cx="80" cy="8" r="2.2" fill="#2E2A6B"/></svg>
        <svg class="firm-logo" viewBox="0 0 112 26" role="img" aria-label="Niharika"><text x="1" y="19" font-family="Georgia,serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">Niharika</text><path d="M99 5 q9 1 8 11 q-5 -5 -8 -11z" fill="#E6007E"/></svg>
      </div>
      <div class="hero"><h1>Maitri Carnival 2026</h1><p>Register once and keep your login. Book a visit slot, get checked in at the counter, then build and edit your Maitri and Niharika orders on your phone.</p><span class="dates">19 – 21 July 2026</span></div>
      <div class="card">
        <div class="switch"><button id="login-mode" class="active">Login</button><button id="register-mode">Register</button></div>
        <form id="login-form" style="margin-top:12px">
          <label>Mobile number</label><div class="phone"><div class="prefix">+91</div><input id="login-phone" inputmode="numeric" maxlength="10" required placeholder="10-digit mobile"></div>
          <label>Password</label><input id="login-password" type="password" required minlength="8" autocomplete="current-password">
          <button class="btn" type="submit">Login</button>
        </form>
        <form id="register-form" class="hidden" style="margin-top:12px">
          <label>Company / firm name</label><input id="reg-company" required maxlength="120">
          <label>Contact person</label><input id="reg-contact" required maxlength="100">
          <div class="grid2"><div><label>City</label><input id="reg-city" list="dl-city" autocomplete="off" required placeholder="Type or pick"></div><div><label>State</label><select id="reg-state" required></select></div></div>
          <label>Agent <span class="optional">(type or pick)</span></label><input id="reg-agent" list="dl-agent" autocomplete="off" placeholder="Your agent's name">
          <label>GSTIN <span class="optional">(optional)</span></label><input id="reg-gstin" maxlength="15">
          <label>Mobile number</label><div class="phone"><div class="prefix">+91</div><input id="reg-phone" inputmode="numeric" maxlength="10" required></div>
          <label>Create password <span class="optional">(min 8 characters)</span></label><input id="reg-password" type="password" minlength="8" required autocomplete="new-password">
          <div id="access-code-wrap" class="hidden"><label>Exhibition access code</label><input id="reg-access-code"></div>
          <button class="btn" type="submit">Register</button>
        </form>
        <p class="copy">No OTP is sent. Save your mobile number and password — you will log in with them at the venue.</p>
      </div>
    </section>

    <!-- LOBBY -->
    <section id="lobby-screen" class="hidden">
      <div class="card">
        <h2>Welcome, <span id="lobby-name">there</span></h2>
        <p class="copy">Here is how the carnival ordering works:</p>
        <div class="steps">
          <div class="step done"><div class="n">✓</div><div><b>Registered</b><p>Your account is ready.</p></div></div>
          <div class="step" id="step-slot"><div class="n">2</div><div><b>Book a visit slot</b><p>Optional, helps us manage the crowd. Pick a time below.</p></div></div>
          <div class="step" id="step-entry"><div class="n">3</div><div><b>Get checked in at the counter</b><p>Show your mobile number to our staff when you arrive.</p></div></div>
          <div class="step" id="step-order"><div class="n">4</div><div><b>Build your order</b><p>Scan product barcodes for Maitri and Niharika.</p></div></div>
          <div class="step" id="step-edit"><div class="n">5</div><div><b>Edit for 24 hours</b><p>You can change your order for a day after your first save.</p></div></div>
        </div>
      </div>

      <div class="card" id="entry-card">
        <div id="entry-banner" class="status-banner wait"><span class="dot"></span><div id="entry-text">Checking your entry status…</div></div>
        <button id="enter-order-btn" class="btn hidden">Start / continue my order →</button>
        <button id="refresh-status-btn" class="btn secondary">Refresh status</button>
      </div>

      <div class="card" id="booking-card">
        <h2>Book a visit slot</h2>
        <p class="copy">Pick a time that suits you. You can change it any time before the event.</p>
        <div id="booked-wrap"></div>
        <div id="slot-picker">
          <div class="grid2" style="margin-top:6px">
            <div><label>People in your group</label><input id="party-size" type="number" min="1" max="99" value="1"></div>
            <div><label>Note <span class="optional">(optional)</span></label><input id="booking-note" maxlength="120" placeholder="Anything we should know"></div>
          </div>
          <div id="slot-list" class="slot-list"></div>
          <button id="book-btn" class="btn" disabled>Confirm slot</button>
        </div>
      </div>
    </section>

    <!-- ORDER -->
    <section id="order-screen" class="hidden">
      <div id="countdown" class="countdown hidden"><span>⏱</span><div>Edit window: <b id="countdown-text">—</b></div></div>
      <div class="firm-tabs"><button class="firm-tab active" data-firm="Maitri">Maitri</button><button class="firm-tab" data-firm="Niharika">Niharika</button></div>
      <div class="card">
        <h2 id="order-title">Maitri order</h2><p class="copy" id="order-status">Draft</p>
        <div class="summary"><div class="metric"><b id="design-count">0</b><span>Designs</span></div><div class="metric"><b id="piece-count">0</b><span>Sets</span></div><div class="metric"><b id="version-count">1</b><span>Version</span></div></div>
      </div>
      <div class="card">
        <h2>Scan a barcode</h2><p class="copy">Each design is added once. Change the quantity manually.</p>
        <div class="scan-actions"><div><label>Barcode</label><input id="barcode-input" autocomplete="off" inputmode="text" placeholder="Scan or type barcode"></div><button id="add-barcode" class="btn">Add</button></div>
        <button id="camera-btn" class="btn secondary">Open camera scanner</button>
        <div id="reader" class="reader"></div>
        <div id="scan-note" class="notice hidden"></div>
      </div>
      <div class="card"><h2>Order items</h2><div id="items" class="items"></div></div>
      <div class="savebar"><button id="save-btn" class="btn">Save order</button><button id="pdf-btn" class="btn secondary">Download PDF</button></div>
      <button id="back-lobby-btn" class="btn ghost">← Back to slot & status</button>
    </section>

    <!-- ACCOUNT -->
    <section id="account-screen" class="hidden">
      <div class="card"><h2>Account details</h2><p class="copy">These details appear on your order PDF and to exhibition staff.</p>
        <div class="account-grid"><div><label>Company</label><input id="acc-company"></div><div><label>Contact</label><input id="acc-contact"></div><div><label>City</label><input id="acc-city" list="dl-city" autocomplete="off"></div><div><label>State</label><select id="acc-state"></select></div></div>
        <label>Agent</label><input id="acc-agent" list="dl-agent" autocomplete="off">
        <label>GSTIN</label><input id="acc-gstin"><button id="save-account" class="btn">Save account details</button><button id="back-order" class="btn secondary">Back</button>
      </div>
    </section>
  </main>

  <datalist id="dl-city"></datalist>
  <datalist id="dl-agent"></datalist>

  <!-- Credentials modal -->
  <div id="cred-modal" class="modal">
    <div class="modal-card">
      <div class="wordmark" style="justify-content:center"><i class="logo-dot"></i>EKUM</div>
      <h2 style="margin-top:12px;color:var(--teal-deep)">Save your login</h2>
      <p class="copy">You will need these to log in at the venue. Take a screenshot or copy them now.</p>
      <div class="cred">
        <div class="cred-row"><b>Username (mobile)</b><span id="cred-user">—</span></div>
        <div class="cred-row"><b>Password</b><span id="cred-pass">—</span></div>
      </div>
      <button id="cred-copy" class="btn secondary">Copy my login details</button>
      <button id="cred-done" class="btn">I've saved them — continue</button>
    </div>
  </div>

  <div id="toast" class="toast"></div>
  <div id="loading" class="loading"><div class="loader-card"><div class="spinner"></div><span id="loading-text">Working…</span></div></div>

<script>
const CONFIG={SUPABASE_URL:"https://ezmtiiftolcaslqfvozu.supabase.co",SUPABASE_ANON_KEY:"sb_publishable_QTijSp1pHxiCGga3l722zg_Vjqxj2qG",REQUIRE_ACCESS_CODE:false};
const FIRMS={Maitri:{name:'Maitri Texfab Private Limited',gstin:'24AAGCM4427L2ZB'},Niharika:{name:'Niharika Texfab LLP',gstin:'24AAWFN4840R1ZC'}};
const STATES=["Andhra Pradesh","Arunachal Pradesh","Assam","Bihar","Chhattisgarh","Goa","Gujarat","Haryana","Himachal Pradesh","Jharkhand","Karnataka","Kerala","Madhya Pradesh","Maharashtra","Manipur","Meghalaya","Mizoram","Nagaland","Odisha","Punjab","Rajasthan","Sikkim","Tamil Nadu","Telangana","Tripura","Uttar Pradesh","Uttarakhand","West Bengal","Andaman and Nicobar Islands","Chandigarh","Dadra and Nagar Haveli and Daman and Diu","Delhi","Jammu and Kashmir","Ladakh","Lakshadweep","Puducherry"];
const configured=!CONFIG.SUPABASE_URL.includes('__')&&!CONFIG.SUPABASE_ANON_KEY.includes('__');
if(!configured)document.getElementById('config-warning').classList.remove('hidden');
if(CONFIG.REQUIRE_ACCESS_CODE)document.getElementById('access-code-wrap').classList.remove('hidden');
const sb=configured?supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;

const state={profile:null,status:null,slots:[],pickedSlot:null,orders:{Maitri:null,Niharika:null},carts:{Maitri:[],Niharika:[]},activeFirm:'Maitri',scanner:null,scanning:false,poll:null,tick:null,screen:'auth'};
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
function toast(m,t=''){const el=$('toast');el.textContent=m;el.className='toast open '+t;clearTimeout(window.__t);window.__t=setTimeout(()=>el.className='toast',3200)}
function loading(on,text='Working…'){$('loading-text').textContent=text;$('loading').classList.toggle('open',on)}
function normalizePhone(v){const d=String(v||'').replace(/\D/g,'');if(!/^[6-9]\d{9}$/.test(d))throw new Error('Enter a valid 10-digit Indian mobile number');return '91'+d}
function ik(url,tr){if(!url)return '';return url+(url.includes('?')?'&':'?')+'tr='+tr}
function fmtTime(iso){if(!iso)return '';const d=new Date(iso);return d.toLocaleString('en-IN',{weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})}
function isAuthErr(m){return /INVALID_OR_EXPIRED_SESSION|JWT|expired|AUTH_REQUIRED|Session/i.test(String(m||''))}

// Lazy script loader (jsPDF, camera scanner) for faster initial load.
function loadScript(src){return new Promise((res,rej)=>{if([...document.scripts].some(s=>s.src===src))return res();const el=document.createElement('script');el.src=src;el.onload=()=>res();el.onerror=()=>rej(new Error('Could not load a required file. Check your connection.'));document.head.appendChild(el)})}
async function ensureJsPDF(){if(window.jspdf&&window.jspdf.jsPDF)return;await loadScript('https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js');if(!window.jspdf||!window.jspdf.jsPDF)throw new Error('PDF tool could not load. Try again.')}
async function ensureScanner(){if(window.Html5Qrcode)return;await loadScript('https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js')}

// Populate state selects + lookup datalists.
function fillStates(){const opts='<option value="">Select state</option>'+STATES.map(s=>`<option>${s}</option>`).join('');$('reg-state').innerHTML=opts;$('acc-state').innerHTML=opts}
async function loadLookups(){try{const{data}=await sb.rpc('list_lookups');const L=data||{};$('dl-city').innerHTML=(L.city||[]).map(v=>`<option value="${esc(v)}">`).join('');$('dl-agent').innerHTML=(L.agent||[]).map(v=>`<option value="${esc(v)}">`).join('')}catch(e){/* non-blocking */}}
fillStates();if(sb)loadLookups();

function show(screen){state.screen=screen;['auth-screen','lobby-screen','order-screen','account-screen'].forEach(id=>$(id).classList.toggle('hidden',id!==screen+'-screen'));$('app-top').classList.toggle('hidden',screen==='auth');
  if(screen!=='lobby'&&state.poll){clearInterval(state.poll);state.poll=null}
  if(screen==='order'){startTick()}else{stopTick()}}

/* ---------- Auth ---------- */
function setMode(reg){$('login-form').classList.toggle('hidden',reg);$('register-form').classList.toggle('hidden',!reg);$('login-mode').classList.toggle('active',!reg);$('register-mode').classList.toggle('active',reg)}
$('login-mode').onclick=()=>setMode(false);$('register-mode').onclick=()=>setMode(true);

async function customerAuth(action,payload){
  const res=await fetch(`${CONFIG.SUPABASE_URL}/functions/v1/customer-auth`,{method:'POST',headers:{'Content-Type':'application/json','apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({action,...payload})});
  const out=await res.json().catch(()=>({ok:false,error:'Invalid server response'}));
  if(!res.ok||!out.ok)throw new Error(out.error||`Authentication failed (${res.status})`);
  return out.data;
}
async function applySession(session){if(!session?.access_token||!session?.refresh_token)throw new Error('No session returned');const{error}=await sb.auth.setSession({access_token:session.access_token,refresh_token:session.refresh_token});if(error)throw error}

$('login-form').addEventListener('submit',async e=>{e.preventDefault();if(!sb)return;try{loading(true,'Logging in…');const phone=normalizePhone($('login-phone').value);const data=await customerAuth('login',{phone,password:$('login-password').value});await applySession(data.session)}catch(err){toast(err.message,'error')}finally{loading(false)}});

$('register-form').addEventListener('submit',async e=>{e.preventDefault();if(!sb)return;if(!$('reg-state').value){toast('Please select your state','error');return}try{loading(true,'Creating account…');const phone=normalizePhone($('reg-phone').value);const password=$('reg-password').value;const data=await customerAuth('register',{phone,password,companyName:$('reg-company').value.trim(),contactName:$('reg-contact').value.trim(),city:$('reg-city').value.trim(),state:$('reg-state').value,agent:$('reg-agent').value.trim(),gstin:$('reg-gstin').value.trim().toUpperCase(),accessCode:$('reg-access-code').value.trim()});
  $('cred-user').textContent=phone;$('cred-pass').textContent=password;window.__pendingSession=data.session;$('cred-modal').classList.add('open');
}catch(err){toast(String(err.message||err).replace('Database error saving new user','Registration details were rejected'),'error')}finally{loading(false)}});

$('cred-copy').onclick=async()=>{const text=`Maitri Carnival 2026 login\nUsername (mobile): ${$('cred-user').textContent}\nPassword: ${$('cred-pass').textContent}`;try{await navigator.clipboard.writeText(text);toast('Login details copied','success')}catch{toast('Copy not available — please screenshot','error')}};
$('cred-done').onclick=async()=>{try{loading(true,'Signing you in…');$('cred-modal').classList.remove('open');await applySession(window.__pendingSession);window.__pendingSession=null}catch(err){toast(err.message,'error');show('auth')}finally{loading(false)}};

/* ---------- Lobby / status / slots ---------- */
async function loadProfileAndStatus(){
  const [pr,stt]=await Promise.all([sb.from('customers').select('*').single(),sb.rpc('get_my_status')]);
  if(pr.error)throw pr.error;if(stt.error)throw stt.error;
  state.profile=pr.data;state.status=stt.data;
  fillAccount();$('lobby-name').textContent=state.profile.contact_name||state.profile.company_name||'there';
  renderEntry();applyStatusSteps();
  await loadSlots();
}
async function refreshStatus(){const{data,error}=await sb.rpc('get_my_status');if(error)throw error;state.status=data;renderEntry();applyStatusSteps()}
function applyStatusSteps(){const s=state.status||{};if(s.checkedIn){$('step-entry').className='step done';$('step-order').className='step active'}else{$('step-entry').className='step active';$('step-order').className='step'}if(s.booking){$('step-slot').className='step done'}}
function renderEntry(){
  const s=state.status||{};const banner=$('entry-banner');const text=$('entry-text');
  if(s.active===false){banner.className='status-banner wait';text.innerHTML='<b>Account paused.</b> Please speak to exhibition staff.';$('enter-order-btn').classList.add('hidden');return}
  if(s.checkedIn){banner.className='status-banner ok';text.innerHTML='<b>You are checked in.</b> You can build and edit your order now.';$('enter-order-btn').classList.remove('hidden');if(state.poll){clearInterval(state.poll);state.poll=null}}
  else{banner.className='status-banner wait';text.innerHTML='<b>Entry pending.</b> Please visit the counter and show your mobile number <b>+'+esc(state.profile?.phone_e164||'')+'</b>. This screen updates automatically once staff check you in.';$('enter-order-btn').classList.add('hidden');if(!state.poll)state.poll=setInterval(()=>refreshStatus().catch(()=>{}),15000)}
}
async function loadSlots(){
  const{data,error}=await sb.rpc('list_slots');if(error){console.warn(error);return}
  state.slots=data||[];const booking=state.status?.booking;
  if(booking){state.pickedSlot=booking.slotId;$('party-size').value=booking.partySize||1;$('booking-note').value=booking.note||'';$('book-btn').textContent='Update my slot'}
  else{$('book-btn').textContent='Confirm slot'}
  renderBookingCard();
}
function renderBookingCard(){
  const booking=state.status?.booking;const wrap=$('booked-wrap');const picker=$('slot-picker');
  if(booking){
    wrap.innerHTML=`<div class="booked-summary"><div><b>Your slot: ${esc(fmtTime(booking.startsAt))}</b><div class="copy" style="margin-top:2px">${esc(booking.label||'')}${booking.partySize?' · '+booking.partySize+' people':''}</div></div><button id="change-slot-btn" class="btn secondary chg" style="width:auto;margin:0;min-height:40px">Change your slot</button></div>`;
    picker.classList.add('hidden');
    $('change-slot-btn').onclick=()=>{picker.classList.remove('hidden');renderSlotGrid()};
  }else{wrap.innerHTML='';picker.classList.remove('hidden');renderSlotGrid()}
}
function renderSlotGrid(){
  const host=$('slot-list');host.className='';
  if(!state.slots.length){host.innerHTML='<div class="empty">No slots have been published yet. You can still come during event hours.</div>';$('book-btn').disabled=true;return}
  const byDate=new Map();
  [...state.slots].sort((a,b)=>new Date(a.startsAt)-new Date(b.startsAt)).forEach(s=>{const k=new Date(s.startsAt).toDateString();if(!byDate.has(k))byDate.set(k,[]);byDate.get(k).push(s)});
  host.innerHTML='<div class="slot-grid">'+[...byDate.entries()].map(([date,slots])=>{
    const head=new Date(date).toLocaleDateString('en-IN',{weekday:'short',day:'numeric',month:'short'});
    const cells=slots.map(s=>{const picked=s.id===state.pickedSlot;const full=s.full&&!picked;const t=new Date(s.startsAt).toLocaleTimeString('en-IN',{hour:'numeric',minute:'2-digit'});const meta=s.full?'<small>Full</small>':(s.capacity!=null?`<small>${Math.max(0,s.capacity-s.booked)} left</small>`:'');return `<button type="button" class="slot-cell ${picked?'picked':''} ${full?'full':''}" data-slot="${s.id}" ${full?'disabled':''}><b>${esc(t)}</b>${meta}</button>`}).join('');
    return `<div class="slot-col"><div class="slot-colhead">${esc(head)}</div>${cells}</div>`;
  }).join('')+'</div>';
  $('book-btn').disabled=!state.pickedSlot;
}
$('slot-list').addEventListener('click',e=>{const b=e.target.closest('[data-slot]');if(!b||b.disabled)return;state.pickedSlot=b.dataset.slot;renderSlotGrid()});
$('book-btn').onclick=async()=>{if(!state.pickedSlot)return;try{loading(true,'Saving your slot…');const{error}=await sb.rpc('book_slot',{p_slot_id:state.pickedSlot,p_party_size:Number($('party-size').value)||1,p_note:$('booking-note').value.trim()});if(error)throw error;await refreshStatus();await loadSlots();toast('Slot booked','success')}catch(err){toast(err.message==='SLOT_FULL'?'That slot is full — pick another':err.message,'error')}finally{loading(false)}};
$('refresh-status-btn').onclick=()=>refreshStatus().then(()=>toast('Status updated')).catch(e=>toast(e.message,'error'));
$('enter-order-btn').onclick=async()=>{await loadOrders();show('order');render()};
$('back-lobby-btn').onclick=async()=>{await stopScanner();await refreshStatus().catch(()=>{});await loadSlots().catch(()=>{});show('lobby')};

/* ---------- Orders ---------- */
async function loadOrders(){loading(true,'Loading your orders…');try{const [m,n]=await Promise.all([sb.rpc('get_my_order_state',{p_firm:'Maitri'}),sb.rpc('get_my_order_state',{p_firm:'Niharika'})]);if(m.error)throw m.error;if(n.error)throw n.error;state.orders.Maitri=m.data;state.orders.Niharika=n.data;state.carts.Maitri=(m.data.items||[]).map(x=>({...x}));state.carts.Niharika=(n.data.items||[]).map(x=>({...x}))}catch(err){toast(err.message,'error')}finally{loading(false)}}
function currentCart(){return state.carts[state.activeFirm]}
function windowClosed(){const s=state.status;if(!s||!s.editDeadline)return false;return new Date(s.editDeadline).getTime()<Date.now()}
function fillAccount(){const p=state.profile||{};$('acc-company').value=p.company_name||'';$('acc-contact').value=p.contact_name||'';$('acc-city').value=p.city||'';$('acc-state').value=p.state||'';$('acc-agent').value=p.agent||'';$('acc-gstin').value=p.gstin||''}

function render(){
  document.querySelectorAll('.firm-tab').forEach(b=>b.classList.toggle('active',b.dataset.firm===state.activeFirm));
  const order=state.orders[state.activeFirm]||{version:1,status:'Draft'};const cart=currentCart();
  $('order-title').textContent=state.activeFirm+' order';
  $('order-status').textContent=`${order.status||'Draft'} · Last saved ${order.updatedAt?new Date(order.updatedAt).toLocaleString('en-IN'):'not yet'}`;
  $('design-count').textContent=cart.length;$('piece-count').textContent=cart.reduce((s,x)=>s+(Number(x.qty)||0),0);$('version-count').textContent=order.version||1;
  const host=$('items');
  if(!cart.length){host.innerHTML='<div class="empty">No designs added yet. Scan the first sticker above.</div>'}
  else{host.innerHTML=cart.map((it,i)=>`<article class="item">${it.imageUrl?`<img class="thumb" id="thumb-${i}" src="${esc(ik(it.imageUrl,'w-240,h-320,c-at_max,q-55'))}" alt="${esc(it.designNo)}" loading="lazy" referrerpolicy="no-referrer">`:'<div class="thumb"></div>'}<div><h3>${esc(it.designNo)}</h3><div class="meta">${esc([it.category,it.fabric,it.color].filter(Boolean).join(' · '))}<br>${esc(it.description||'')}</div><div class="qty"><button data-act="minus" data-i="${i}">−</button><input data-act="qty" data-i="${i}" type="number" min="1" max="9999" value="${Number(it.qty)||1}"><button data-act="plus" data-i="${i}">+</button><button class="remove" data-act="remove" data-i="${i}">✕</button></div></div></article>`).join('');
    cart.forEach((it,i)=>{const el=$('thumb-'+i);if(el)protect(el)})}
  renderCountdown();
}
function protect(el){el.draggable=false;el.addEventListener('contextmenu',e=>e.preventDefault());el.addEventListener('dragstart',e=>e.preventDefault())}
function renderCountdown(){const s=state.status;const box=$('countdown');const closed=windowClosed();
  if(!s||!s.editDeadline){box.classList.add('hidden');$('save-btn').disabled=false;return}
  box.classList.remove('hidden');
  if(closed){box.classList.add('closed');$('countdown-text').textContent='closed — ask staff to reopen';$('save-btn').disabled=true;return}
  box.classList.remove('closed');$('save-btn').disabled=false;
  const ms=new Date(s.editDeadline).getTime()-Date.now();const h=Math.floor(ms/3.6e6),m=Math.floor(ms%3.6e6/6e4),sec=Math.floor(ms%6e4/1000);
  $('countdown-text').textContent=`${h}h ${String(m).padStart(2,'0')}m ${String(sec).padStart(2,'0')}s left to edit`;
}
function startTick(){stopTick();state.tick=setInterval(renderCountdown,1000)}
function stopTick(){if(state.tick){clearInterval(state.tick);state.tick=null}}

$('items').addEventListener('click',e=>{const b=e.target.closest('[data-act]');if(!b||b.tagName==='INPUT')return;const i=Number(b.dataset.i),cart=currentCart();if(b.dataset.act==='plus')cart[i].qty=Math.min(9999,(Number(cart[i].qty)||1)+1);if(b.dataset.act==='minus')cart[i].qty=Math.max(1,(Number(cart[i].qty)||1)-1);if(b.dataset.act==='remove')cart.splice(i,1);render()});
$('items').addEventListener('change',e=>{if(e.target.dataset.act!=='qty')return;const i=Number(e.target.dataset.i);currentCart()[i].qty=Math.max(1,Math.min(9999,Number(e.target.value)||1));render()});
document.querySelectorAll('.firm-tab').forEach(b=>b.onclick=async()=>{await stopScanner();state.activeFirm=b.dataset.firm;render()});

async function addBarcode(raw){const barcode=String(raw||'').trim();if(!barcode)return;try{$('scan-note').classList.add('hidden');const{data,error}=await sb.rpc('lookup_barcode',{p_barcode:barcode});if(error)throw error;const row=Array.isArray(data)?data[0]:data;if(!row)throw new Error('Barcode is not mapped to an active design');if(![state.activeFirm,'Both'].includes(row.firm))throw new Error(`${row.design_no} belongs to ${row.firm}. Switch firm tabs first.`);const cart=currentCart();if(cart.some(x=>x.designNo===row.design_no))throw new Error(`${row.design_no} is already in this order`);cart.push({barcode:row.barcode,designNo:row.design_no,imageUrl:row.image_url||'',qty:1,category:row.category,fabric:row.fabric,color:row.color,description:row.description});$('barcode-input').value='';render();note(`Added ${row.design_no}`,'success');navigator.vibrate?.(80)}catch(err){note(err.message,'error');navigator.vibrate?.([100,70,100])}}
function note(t,type=''){$('scan-note').textContent=t;$('scan-note').className='notice '+type}
$('add-barcode').onclick=()=>addBarcode($('barcode-input').value);$('barcode-input').addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();addBarcode(e.target.value)}});
$('camera-btn').onclick=async()=>{if(state.scanning){await stopScanner();return}try{await ensureScanner();state.scanner=new Html5Qrcode('reader');$('reader').classList.add('open');await state.scanner.start({facingMode:'environment'},{fps:10,qrbox:{width:260,height:160}},async d=>{await addBarcode(d);await stopScanner()},()=>{});state.scanning=true;$('camera-btn').textContent='Close camera scanner'}catch(err){toast('Camera could not start: '+err.message,'error');await stopScanner()}};
async function stopScanner(){if(state.scanner){try{if(state.scanning)await state.scanner.stop()}catch{}try{await state.scanner.clear()}catch{}}state.scanner=null;state.scanning=false;$('reader').classList.remove('open');$('camera-btn').textContent='Open camera scanner'}

$('save-btn').onclick=async()=>{try{loading(true,'Saving order…');const firm=state.activeFirm,order=state.orders[firm];const items=currentCart().map(x=>({barcode:x.barcode||'',designNo:x.designNo,qty:Number(x.qty)||1}));const{data,error}=await sb.rpc('save_my_order',{p_firm:firm,p_base_version:order.version,p_items:items,p_request_id:crypto.randomUUID()});if(error)throw error;if(!data.ok){state.orders[firm]=data.order;state.carts[firm]=(data.order.items||[]).map(x=>({...x}));render();throw new Error(data.message)}state.orders[firm]=data.order;state.carts[firm]=(data.order.items||[]).map(x=>({...x}));await refreshStatus();render();toast(`${firm} order saved`,'success')}catch(err){if(isAuthErr(err.message)){toast('Your session expired — please log in again.','error');show('auth')}else toast(friendlySave(err.message),'error')}finally{loading(false)}};
function friendlySave(m){if(/NOT_CHECKED_IN/.test(m))return 'You are not checked in yet. Please visit the counter.';if(/EDIT_WINDOW_CLOSED/.test(m))return 'Your 24-hour edit window has closed. Ask staff to reopen it.';if(/ORDER_LOCKED/.test(m))return 'This order is locked. Ask staff to reopen it.';return m}

/* ---------- PDF (sale order) ---------- */
async function blobToDataUrl(b){return await new Promise((res,rej)=>{const r=new FileReader();r.onload=()=>res(r.result);r.onerror=rej;r.readAsDataURL(b)})}
async function fetchThumb(url){const c=new AbortController();const t=setTimeout(()=>c.abort(),6000);try{const r=await fetch(ik(url,'w-300,h-400,c-at_max,q-45,f-jpg'),{mode:'cors',credentials:'omit',signal:c.signal});if(!r.ok)throw new Error('img');return await blobToDataUrl(await r.blob())}finally{clearTimeout(t)}}
$('pdf-btn').onclick=async()=>{const cart=currentCart();if(!cart.length){toast('Add at least one design before downloading a PDF','error');return}
  try{loading(true,'Preparing PDF…');await ensureJsPDF();const{jsPDF}=window.jspdf;const doc=new jsPDF({unit:'mm',format:'a4'});const p=state.profile,firm=state.activeFirm,f=FIRMS[firm];const W=210;let y=14;
    // Header
    doc.setFillColor(34,94,99);doc.rect(0,0,W,26,'F');
    doc.setTextColor(255,255,255);doc.setFont('helvetica','bold');doc.setFontSize(15);doc.text('EKUM · '+firm,12,12);
    doc.setFont('helvetica','normal');doc.setFontSize(9);doc.text(f.name,12,18);doc.text('GSTIN: '+f.gstin+'    Maitri Carnival 2026',12,22.5);
    doc.setTextColor(51,39,27);y=34;
    doc.setFont('helvetica','bold');doc.setFontSize(13);doc.text('SALE ORDER',12,y);
    doc.setFont('helvetica','normal');doc.setFontSize(9);doc.text('Date: '+new Date().toLocaleDateString('en-IN'),W-12,y,{align:'right'});y+=7;
    // Buyer block
    doc.setDrawColor(220);doc.setFillColor(245,248,247);doc.rect(12,y,W-24,24,'FD');
    doc.setFont('helvetica','bold');doc.setFontSize(9);doc.text('Buyer',15,y+5);
    doc.setFont('helvetica','normal');
    doc.text(`${p.company_name||''}  ·  ${p.contact_name||''}`,15,y+10);
    doc.text(`Phone: +${p.phone_e164||''}    GSTIN: ${p.gstin||'—'}`,15,y+15);
    doc.text(`${[p.city,p.state].filter(Boolean).join(', ')}    Agent: ${p.agent||'—'}`,15,y+20);
    y+=30;
    // Table header
    doc.setFont('helvetica','bold');doc.setFontSize(8.5);doc.setFillColor(232,242,241);doc.rect(12,y,W-24,7,'F');
    doc.text('#',15,y+5);doc.text('Design',33,y+5);doc.text('Details',75,y+5);doc.text('Sets',W-16,y+5,{align:'right'});
    y+=7;doc.setFont('helvetica','normal');
    const thumbs=await Promise.allSettled(cart.map(it=>fetchThumb(it.imageUrl)));
    for(let i=0;i<cart.length;i++){const it=cart[i];if(y>272){doc.addPage();y=16}
      const tv=thumbs[i];if(tv.status==='fulfilled'){try{doc.addImage(tv.value,'JPEG',15,y+1,12,16,undefined,'FAST')}catch{doc.setDrawColor(225);doc.rect(15,y+1,12,16)}}else{doc.setDrawColor(225);doc.rect(15,y+1,12,16)}
      doc.setFont('helvetica','bold');doc.setFontSize(9);doc.text(String(it.designNo||''),33,y+7);
      doc.setFont('helvetica','normal');doc.setFontSize(8);doc.text(doc.splitTextToSize([it.category,it.fabric,it.color].filter(Boolean).join(' · ')+(it.description?'  '+it.description:''),110),75,y+5);
      doc.setFont('helvetica','bold');doc.setFontSize(9.5);doc.text(String(it.qty),W-16,y+8,{align:'right'});
      doc.setDrawColor(235);doc.line(12,y+19,W-12,y+19);y+=20;
    }
    doc.setFont('helvetica','bold');doc.setFontSize(10);
    const totalSets=cart.reduce((s,x)=>s+Number(x.qty||0),0);
    doc.text(`Total designs: ${cart.length}     Total sets: ${totalSets}`,12,Math.min(y+6,289));
    doc.setFont('helvetica','normal');doc.setFontSize(7.5);doc.setTextColor(120);doc.text('Computer-generated sale order · Maitri Carnival 2026',12,293);
    doc.save(`${(p.company_name||'order').replace(/[^a-z0-9]+/gi,'-')}-${firm}-Sale-Order.pdf`);toast('PDF downloaded','success')
  }catch(err){toast(err.message||'Could not generate the PDF','error')}finally{loading(false)}};

/* ---------- Account ---------- */
$('account-btn').onclick=()=>{fillAccount();show('account')};
$('back-order').onclick=()=>show(state.status?.checkedIn?'order':'lobby');
$('save-account').onclick=async()=>{try{loading(true,'Saving account…');const patch={company_name:$('acc-company').value.trim(),contact_name:$('acc-contact').value.trim(),city:$('acc-city').value.trim(),state:$('acc-state').value,agent:$('acc-agent').value.trim(),gstin:$('acc-gstin').value.trim().toUpperCase()};const{data,error}=await sb.from('customers').update(patch).eq('id',state.profile.id).select().single();if(error)throw error;state.profile=data;loadLookups();toast('Account updated','success');show(state.status?.checkedIn?'order':'lobby')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('logout-btn').onclick=async()=>{await stopScanner();if(state.poll){clearInterval(state.poll);state.poll=null}stopTick();await sb.auth.signOut();state.profile=null;show('auth')};

/* ---------- Boot ---------- */
let booted=false;
async function boot(){if(booted)return;booted=true;try{loading(true,'Loading…');await loadProfileAndStatus();show('lobby')}catch(err){booted=false;if(!isAuthErr(err.message))toast(err.message,'error');show('auth')}finally{loading(false)}}
if(sb){
  sb.auth.onAuthStateChange((event,session)=>{if(event==='SIGNED_OUT'||!session){booted=false;show('auth');return}if(event==='SIGNED_IN'){booted=false;setTimeout(boot,0)}});
  sb.auth.getSession().then(({data})=>{data.session?boot():show('auth')});
}else show('auth');
</script>
</body>
</html>


################################################################################
# FILE: web/admin-a106dc80eeabd658.html
################################################################################

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="theme-color" content="#225E63">
  <title>EKUM Admin · Maitri Carnival 2026</title>
  <link rel="preconnect" href="https://ezmtiiftolcaslqfvozu.supabase.co">
  <link rel="preconnect" href="https://ik.imagekit.io" crossorigin>
  <link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <style>
    :root{--teal:#2B7379;--teal-deep:#225E63;--foam:#E8F2F1;--warm:#F7F3EA;--white:#FFFFFF;--border:#E4E8E6;--muted:#7B817F;--slate:#3D3A37;--charcoal:#33271B;--orange:#FF9700;--success:#15803D;--error:#DC2626}
    html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
    *{box-sizing:border-box;margin:0;-webkit-tap-highlight-color:transparent}
    html,body{min-height:100%;max-width:100%;overflow-x:hidden;background:var(--warm);color:var(--charcoal);font-family:Inter,system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
    button,input,select,textarea{font:inherit}.hidden{display:none!important}img,svg{max-width:100%}
    .appbar{position:sticky;top:0;z-index:50;display:flex;align-items:center;gap:10px;min-height:60px;padding:9px 14px;background:rgba(255,255,255,.97);border-bottom:1px solid var(--border);backdrop-filter:blur(12px)}
    .brandlock{display:flex;align-items:center;gap:9px;min-width:0;overflow:hidden}
    .wordmark{display:flex;align-items:center;gap:7px;color:var(--teal-deep);font-size:15px;font-weight:800;letter-spacing:.12em}
    .logo-dot{width:12px;height:12px;border-radius:50%;background:var(--orange);flex:0 0 auto}
    .brand-sub{display:block;color:var(--muted);font-size:8.5px;font-weight:700;letter-spacing:.13em;text-transform:uppercase;margin-top:1px;white-space:nowrap}
    .bdiv{width:1px;height:24px;background:var(--border);flex:0 0 auto}
    .firmlogos{display:flex;align-items:center;gap:9px}.firm-logo{height:17px;width:auto;display:block}
    .top-actions{margin-left:auto;display:flex;gap:7px}.icon-btn{min-height:38px;padding:0 12px;border:1px solid var(--border);border-radius:10px;background:#fff;color:var(--teal-deep);font-size:12px;font-weight:750;cursor:pointer}
    .tabs{position:sticky;top:60px;z-index:40;display:flex;gap:4px;overflow-x:auto;padding:8px 12px;background:rgba(255,255,255,.97);border-bottom:1px solid var(--border);backdrop-filter:blur(10px)}
    .tab{white-space:nowrap;min-height:38px;padding:0 14px;border:1px solid var(--border);border-radius:10px;background:#fff;color:var(--slate);font-size:12.5px;font-weight:750;cursor:pointer}
    .tab.active{background:var(--teal-deep);color:#fff;border-color:var(--teal-deep)}
    main{width:min(100%,1140px);margin:auto;padding:14px 12px 40px}
    .panel{display:none}.panel.active{display:block}
    .card{margin-bottom:12px;padding:16px;border:1px solid var(--border);border-radius:15px;background:#fff;box-shadow:0 6px 18px rgba(34,94,99,.06)}
    h1{font-size:21px;color:var(--teal-deep)}h2{font-size:15px;color:var(--teal-deep)}.copy{margin-top:4px;color:var(--muted);font-size:11.5px;line-height:1.5}
    label{display:block;margin:10px 0 5px;color:var(--slate);font-size:10px;font-weight:800;letter-spacing:.05em;text-transform:uppercase}
    .optional{color:var(--muted);font-weight:500;letter-spacing:0;text-transform:none}
    input,select,textarea{width:100%;min-height:44px;padding:0 12px;border:1px solid #D8E1DE;border-radius:10px;background:#fff;color:var(--charcoal);font-size:14px}
    textarea{min-height:80px;padding:10px 12px;resize:vertical}
    input:focus,select:focus,textarea:focus{outline:2px solid var(--teal);outline-offset:0;border-color:transparent}
    .btn{min-height:44px;padding:0 15px;border:0;border-radius:10px;background:var(--teal-deep);color:#fff;font-size:12.5px;font-weight:800;cursor:pointer}
    .btn.secondary{border:1.5px solid var(--teal-deep);background:#fff;color:var(--teal-deep)}
    .btn.ghost{border:1px solid var(--border);background:#fff;color:var(--slate);width:100%}
    .btn.sm{min-height:36px;padding:0 11px;font-size:11.5px}.btn:disabled{background:#E7EBE9;color:#949A97}
    .row-actions{display:flex;gap:7px;flex-wrap:wrap}
    .kpis{display:grid;grid-template-columns:repeat(6,1fr);gap:9px;margin-bottom:12px}
    .kpi{min-height:84px;padding:13px;border:1px solid var(--border);border-radius:13px;background:#fff}.kpi.primary{background:linear-gradient(135deg,var(--teal-deep),var(--teal));color:#fff}
    .kpi b{display:block;font-size:22px}.kpi span{display:block;margin-top:6px;color:var(--muted);font-size:9px;font-weight:800;letter-spacing:.04em;text-transform:uppercase}.kpi.primary span{color:rgba(255,255,255,.75)}
    .list{display:grid;gap:8px;margin-top:10px}
    .li{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:12px;border:1px solid var(--border);border-radius:12px;background:#fff}
    .li b{font-size:13px;color:var(--teal-deep)}.li p{margin-top:3px;color:var(--muted);font-size:10.5px;line-height:1.45}
    .li.drilldown{cursor:pointer}.li.drilldown:hover{background:#F8FBFA}
    .badge{display:inline-block;padding:2px 8px;border-radius:20px;font-size:10px;font-weight:800}
    .badge.in{background:#DCFCE7;color:#166534}.badge.out{background:#FEF3C7;color:#8A5A09}.badge.off{background:#FEE2E2;color:#991B1B}.badge.slot{background:#E8F2F1;color:#225E63}
    .grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px}.grid3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:9px}.grid4{display:grid;grid-template-columns:repeat(4,1fr);gap:9px}
    .toolbar{display:flex;align-items:center;gap:8px;margin-bottom:9px;flex-wrap:wrap}.toolbar h2,.toolbar h1{margin-right:auto}
    .value{text-align:right}.value strong{display:block;color:var(--teal-deep);font-size:16px}.value span{font-size:9px;color:var(--muted)}
    .empty{padding:24px 10px;color:var(--muted);font-size:12px;text-align:center}
    .dimchips,.statechips,.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
    .dimchip{padding:7px 12px;border:1px solid var(--border);border-radius:20px;background:#fff;color:var(--slate);font-size:11.5px;font-weight:700;cursor:pointer}
    .dimchip.active{background:var(--teal-deep);color:#fff;border-color:var(--teal-deep)}
    .statechip{padding:6px 11px;border:1px solid var(--border);border-radius:18px;background:#fff;color:var(--slate);font-size:11px;font-weight:600;cursor:pointer}
    .statechip.on{background:var(--foam);border-color:var(--teal);color:var(--teal-deep);font-weight:800}
    .chip{padding:6px 11px;border:1px solid var(--teal-deep);border-radius:20px;background:var(--foam);color:var(--teal-deep);font-size:11px;font-weight:700;cursor:pointer}
    .chip.clear{background:#fff;border-color:var(--border);color:var(--slate)}
    .scrollbox{max-height:440px;overflow:auto;display:grid;gap:6px;margin-top:6px}
    .drill{display:grid;grid-template-columns:minmax(84px,150px) 1fr auto;gap:9px;align-items:center;width:100%;text-align:left;border:1px solid var(--border);border-radius:9px;background:#fff;padding:8px 10px;cursor:pointer;font-size:11.5px}
    .drill:hover{background:#F8FBFA}.drill .bl{font-weight:700;color:var(--charcoal);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.drill .bv{color:var(--muted);font-size:10px;white-space:nowrap}
    .drill .fill{height:16px;border-radius:5px;background:linear-gradient(90deg,var(--teal),var(--teal-deep));min-width:3px}
    .grouphdr{display:flex;align-items:center;gap:8px;margin-top:8px;padding:11px;border:1px solid var(--border);border-radius:11px;background:#fff;cursor:pointer;font-weight:700;color:var(--teal-deep);font-size:12.5px}
    .grouphdr:hover{background:#F8FBFA}.grouphdr .cnt{margin-left:auto;color:var(--muted);font-size:11px;font-weight:600}
    .groupbody{display:none;gap:6px;padding:6px 0 4px 10px}.groupbody.open{display:grid}
    .traffic{display:grid;gap:6px;margin-top:10px}.bar{display:grid;grid-template-columns:150px 1fr 44px;gap:8px;align-items:center;font-size:11.5px}.bar .fill{height:22px;border-radius:6px;background:linear-gradient(90deg,var(--teal),var(--teal-deep));min-width:2px}
    .modal{position:fixed;inset:0;z-index:100;display:none;align-items:flex-end;background:rgba(24,30,28,.52)}.modal.open{display:flex}
    .sheet{width:100%;max-height:92vh;overflow:auto;padding:18px 16px calc(22px + env(safe-area-inset-bottom));border-radius:20px 20px 0 0;background:#fff}
    .sheet-head{display:flex;align-items:flex-start;gap:10px}.sheet-head button{margin-left:auto;width:38px;height:38px;border:0;border-radius:10px;background:var(--foam);color:var(--teal-deep);font-weight:850;cursor:pointer}
    .detail-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:12px 0}.detail-metric{padding:10px;border-radius:10px;background:var(--foam);text-align:center}.detail-metric b{display:block;color:var(--teal-deep);font-size:18px}.detail-metric span{font-size:9px;color:var(--muted)}
    .line{display:grid;grid-template-columns:56px minmax(0,1fr) auto;gap:10px;align-items:center;padding:9px 0;border-bottom:1px solid var(--border)}.line img{width:56px;height:74px;border-radius:8px;object-fit:cover;background:#EEF2F0}.line b{font-size:12px;color:var(--teal-deep)}.line p{margin-top:3px;color:var(--muted);font-size:9px}
    .pm-img{width:110px;height:146px;border-radius:10px;object-fit:cover;background:#EEF2F0;flex:0 0 auto}
    .cred-box{margin-top:12px;padding:12px;border:1px dashed var(--teal);border-radius:11px;background:var(--foam);font-size:13px;line-height:1.6}
    .toast{position:fixed;left:50%;top:70px;z-index:130;display:none;max-width:90%;padding:10px 16px;border-radius:22px;background:var(--charcoal);color:#fff;font-size:12px;transform:translateX(-50%)}.toast.open{display:block}.toast.error{background:#B91C1C}.toast.success{background:#166534}
    .loading{position:fixed;inset:0;z-index:120;display:none;place-items:center;background:rgba(25,31,29,.46)}.loading.open{display:grid}.loader{padding:22px 28px;border-radius:15px;background:#fff;color:var(--teal-deep);font-weight:800}
    .config{padding:11px;background:#FEE2E2;color:#991B1B;text-align:center;font-size:12px}
    .reader{display:none;margin-top:10px;border-radius:12px;overflow:hidden}.reader.open{display:block}
    @media(max-width:900px){.kpis{grid-template-columns:repeat(3,1fr)}}
    @media(max-width:600px){.kpis{grid-template-columns:repeat(2,1fr)}.grid2,.grid3,.grid4{grid-template-columns:1fr}.detail-grid{grid-template-columns:repeat(2,1fr)}.bar{grid-template-columns:110px 1fr 40px}}
    @media(max-width:520px){.firmlogos,.bdiv{display:none}}
  </style>
</head>
<body oncontextmenu="return false">
<div id="config" class="config hidden">Replace the Supabase placeholders before publishing.</div>
<header id="top" class="appbar hidden">
  <div class="brandlock">
    <div><div class="wordmark"><i class="logo-dot"></i>EKUM</div><small class="brand-sub">Admin · Maitri Carnival 2026</small></div>
    <span class="bdiv"></span>
    <span class="firmlogos">
      <svg class="firm-logo" viewBox="0 0 92 26" role="img" aria-label="Maitri"><text x="1" y="19" font-family="Georgia,serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">maitri</text><circle cx="80" cy="8" r="5" fill="#8DC63F"/><circle cx="80" cy="8" r="2.2" fill="#2E2A6B"/></svg>
      <svg class="firm-logo" viewBox="0 0 112 26" role="img" aria-label="Niharika"><text x="1" y="19" font-family="Georgia,serif" font-style="italic" font-weight="700" font-size="19" fill="#2E2A6B">Niharika</text><path d="M99 5 q9 1 8 11 q-5 -5 -8 -11z" fill="#E6007E"/></svg>
    </span>
  </div>
  <div class="top-actions"><button id="refresh" class="icon-btn">Refresh</button><button id="logout" class="icon-btn">Logout</button></div>
</header>
<nav id="tabs" class="tabs hidden">
  <button class="tab active" data-tab="dashboard">Dashboard</button>
  <button class="tab" data-tab="entry">Entry</button>
  <button class="tab" data-tab="slots">Slots</button>
  <button class="tab" data-tab="mapping">Mapping</button>
  <button class="tab" data-tab="products">Products</button>
  <button class="tab" data-tab="assisted">Assisted</button>
  <button class="tab" data-tab="staff">Staff</button>
</nav>

<main>
  <section id="login-screen"><div class="card" style="max-width:420px;margin:40px auto">
    <div class="wordmark"><i class="logo-dot"></i>EKUM</div>
    <h1 style="margin-top:10px">Admin login</h1><p class="copy">Cross-customer data is available only after server-side verification of your admin role.</p>
    <form id="login-form"><label>Email</label><input id="email" type="email" required autocomplete="username"><label>Password</label><input id="password" type="password" required autocomplete="current-password"><button class="btn" style="width:100%;margin-top:14px" type="submit">Login</button></form>
  </div></section>

  <!-- DASHBOARD -->
  <div id="panel-dashboard" class="panel">
    <div class="card"><div class="toolbar"><h2>Exhibition orders</h2><p class="copy" id="updated">Not loaded</p></div>
      <label>Search (customer / phone / design)</label><input id="d-search" placeholder="Search">
      <label style="margin-top:10px">Break down by</label><div id="d-dimchips" class="dimchips"></div>
      <label style="margin-top:10px">Filter by state <span class="optional">(tap to include, multiple allowed)</span></label><div id="d-states" class="statechips"></div>
      <div id="d-chips" class="chips"></div>
    </div>
    <div class="kpis"><div class="kpi primary"><b id="k-pieces">0</b><span>Total sets</span></div><div class="kpi"><b id="k-customers">0</b><span>Customers</span></div><div class="kpi"><b id="k-orders">0</b><span>Orders</span></div><div class="kpi"><b id="k-designs">0</b><span>Unique designs</span></div><div class="kpi"><b id="k-maitri">0</b><span>Maitri sets</span></div><div class="kpi"><b id="k-niharika">0</b><span>Niharika sets</span></div></div>
    <div class="card"><div class="toolbar"><h2 id="d-dim-title">Breakdown</h2><p class="copy" id="d-dim-sub"></p></div><div id="d-breakdown" class="scrollbox"></div></div>
    <div class="card"><div class="toolbar"><h2>Orders</h2><p class="copy" id="order-count">0</p><button id="export" class="btn secondary sm">Export Excel</button></div><div id="orders" class="list"></div></div>
    <div class="card"><h2>Reset a customer password</h2><p class="copy">Set a temporary password and share it directly.</p><div class="grid3"><div><label>Mobile</label><input id="reset-phone" inputmode="numeric" maxlength="12"></div><div><label>New password</label><input id="reset-password" type="password" minlength="8"></div><div style="display:flex;align-items:flex-end"><button id="reset-btn" class="btn" style="width:100%">Reset</button></div></div></div>
  </div>

  <!-- ENTRY -->
  <div id="panel-entry" class="panel">
    <div class="card"><h1>Entry check-in</h1><p class="copy">Search a registered customer (mobile, company, contact, city, state, GSTIN) and check them in when they arrive. Only checked-in customers can create orders.</p>
      <label>Search directory</label><input id="e-search" placeholder="Search anything"><div id="e-list" class="list"></div>
    </div>
  </div>

  <!-- SLOTS -->
  <div id="panel-slots" class="panel">
    <div class="card"><h1>Visit slots</h1><p class="copy">Publish time windows customers can book. Booking is for planning only — it does not gate ordering.</p>
      <div class="grid4"><div><label>Start</label><input id="s-start" type="datetime-local"></div><div><label>End</label><input id="s-end" type="datetime-local"></div><div><label>Label <span class="optional">(optional)</span></label><input id="s-label" placeholder="e.g. Morning"></div><div><label>Capacity <span class="optional">(blank = unlimited)</span></label><input id="s-cap" type="number" min="1"></div></div>
      <button id="s-add" class="btn" style="margin-top:12px">Add slot</button><div id="s-list" class="list"></div>
    </div>
    <div class="card"><h2>Expected traffic</h2><p class="copy">Booked customers per slot.</p><div id="traffic" class="traffic"></div></div>
  </div>

  <!-- MAPPING -->
  <div id="panel-mapping" class="panel">
    <div class="card"><h1>Barcode mapping</h1><p class="copy">Scan or type a barcode, then choose the active design it belongs to.</p>
      <div class="grid2"><div><label>Barcode</label><input id="m-barcode" autocomplete="off"></div><div><label>Design number</label><input id="m-design" list="m-designlist" autocomplete="off"><datalist id="m-designlist"></datalist></div></div>
      <div class="row-actions" style="margin-top:12px"><button id="m-map" class="btn">Save mapping</button><button id="m-camera" class="btn secondary">Camera</button></div>
      <div id="m-reader" class="reader"></div><div id="m-note" class="copy"></div>
    </div>
    <div class="card"><h2>Batch mapping</h2><p class="copy">One per line as <b>BARCODE,DESIGNNO</b>. Map many at once.</p><textarea id="m-batch" placeholder="8901234567890,MT-1001&#10;8901234567891,NH-2002"></textarea><button id="m-batchbtn" class="btn" style="margin-top:10px">Save batch</button></div>
    <div class="card"><div class="toolbar"><h2>Recent mappings</h2><input id="m-filter" placeholder="Search" style="max-width:240px"></div><div id="m-list" class="list"></div></div>
  </div>

  <!-- PRODUCTS -->
  <div id="panel-products" class="panel">
    <div class="card"><div class="toolbar"><h1>Products</h1><select id="p-group" style="max-width:180px"><option value="">No grouping</option><option value="category">By category</option><option value="fabric">By fabric</option><option value="color">By color</option><option value="firm">By firm</option></select><input id="p-filter" placeholder="Search" style="max-width:220px"></div><p class="copy" id="p-sub">Images sync from Excel (read-only). Tap a design to edit its details.</p><div id="p-list" class="list"></div></div>
  </div>

  <!-- ASSISTED -->
  <div id="panel-assisted" class="panel">
    <div class="card"><h1>Assisted order</h1><p class="copy">Build an order for a party who can't use the site. Search an existing customer or register a new one — assisted orders bypass the entry gate and edit lock.</p>
      <label>Find a customer</label><input id="a-search" placeholder="Mobile, company, or contact"><div id="a-results" class="list"></div>
    </div>
    <div class="card"><h2>Register a new party</h2><div class="grid2"><div><label>Company</label><input id="a-company"></div><div><label>Contact</label><input id="a-contact"></div><div><label>City</label><input id="a-city" list="dl-city" autocomplete="off"></div><div><label>State</label><select id="a-state"></select></div><div><label>Agent</label><input id="a-agent" list="dl-agent" autocomplete="off"></div><div><label>Mobile</label><input id="a-phone" inputmode="numeric" maxlength="10"></div><div><label>Password <span class="optional">(blank = auto)</span></label><input id="a-pass"></div></div><button id="a-register" class="btn" style="margin-top:12px">Register party</button><div id="a-cred"></div></div>
    <div id="a-builder" class="card hidden">
      <div class="toolbar"><h2 id="a-party">Order for —</h2><button id="a-close" class="btn ghost sm" style="width:auto">Close</button></div>
      <div class="row-actions" style="margin-bottom:10px"><button class="tab a-firm active" data-firm="Maitri">Maitri</button><button class="tab a-firm" data-firm="Niharika">Niharika</button></div>
      <div class="grid2"><div><label>Barcode</label><input id="a-barcode" placeholder="Scan or type"></div><div style="display:flex;align-items:flex-end"><button id="a-add" class="btn" style="width:100%">Add design</button></div></div>
      <div id="a-note" class="copy"></div><div id="a-cart" class="list" style="margin-top:10px"></div>
      <button id="a-save" class="btn" style="margin-top:12px">Save order for party</button>
    </div>
  </div>

  <!-- STAFF -->
  <div id="panel-staff" class="panel">
    <div class="card"><h1>Staff logins</h1><p class="copy">Create a separate login for each device/staff member. Every staff login has full admin access. Using one login per device avoids the sign-out conflicts you get from sharing a single account.</p>
      <div class="grid2"><div><label>Staff email</label><input id="st-email" type="email" placeholder="counter1@yourteam.com"></div><div><label>Password <span class="optional">(blank = auto-generate)</span></label><input id="st-pass"></div></div>
      <button id="st-create" class="btn" style="margin-top:12px">Create staff login</button>
      <div id="st-cred"></div>
    </div>
  </div>
</main>

<!-- Order detail modal -->
<div id="detail-modal" class="modal"><div class="sheet"><div class="sheet-head"><div><h2 id="detail-title">Order</h2><p class="copy" id="detail-sub"></p></div><button id="detail-close">✕</button></div><div id="detail-metrics" class="detail-grid"></div><div id="detail-items"></div><div class="grid2" style="margin-top:14px"><button id="lock-order" class="btn secondary">Lock order</button><button id="customer-toggle" class="btn secondary">Disable customer</button></div></div></div>

<!-- Product edit modal -->
<div id="prod-modal" class="modal"><div class="sheet"><div class="sheet-head"><div><h2 id="pm-title">Design</h2><p class="copy" id="pm-sub"></p></div><button id="pm-close">✕</button></div>
  <div style="display:flex;gap:12px;align-items:flex-start;margin-top:6px"><img id="pm-img" class="pm-img" alt=""><div style="flex:1;min-width:0">
    <label>Firm</label><select id="pm-firm"><option>Maitri</option><option>Niharika</option><option>Both</option></select>
    <div class="grid2"><div><label>Category</label><input id="pm-category" list="dl-category" autocomplete="off"></div><div><label>Fabric</label><input id="pm-fabric" list="dl-fabric" autocomplete="off"></div></div>
    <div class="grid2"><div><label>Color</label><input id="pm-color" list="dl-color" autocomplete="off"></div><div><label>Status</label><select id="pm-active"><option value="true">Active</option><option value="false">Inactive</option></select></div></div>
  </div></div>
  <label>Description</label><textarea id="pm-desc"></textarea>
  <div id="pm-barcodes" class="copy" style="margin-top:8px"></div>
  <button id="pm-save" class="btn" style="margin-top:12px">Save details</button>
</div></div>

<datalist id="dl-city"></datalist><datalist id="dl-agent"></datalist>
<datalist id="dl-category"></datalist><datalist id="dl-fabric"></datalist><datalist id="dl-color"></datalist>

<div id="toast" class="toast"></div><div id="loading" class="loading"><div class="loader" id="loading-text">Working…</div></div>

<script>
const CONFIG={SUPABASE_URL:'https://ezmtiiftolcaslqfvozu.supabase.co',SUPABASE_ANON_KEY:'sb_publishable_QTijSp1pHxiCGga3l722zg_Vjqxj2qG'};
const STATES=["Andhra Pradesh","Arunachal Pradesh","Assam","Bihar","Chhattisgarh","Goa","Gujarat","Haryana","Himachal Pradesh","Jharkhand","Karnataka","Kerala","Madhya Pradesh","Maharashtra","Manipur","Meghalaya","Mizoram","Nagaland","Odisha","Punjab","Rajasthan","Sikkim","Tamil Nadu","Telangana","Tripura","Uttar Pradesh","Uttarakhand","West Bengal","Andaman and Nicobar Islands","Chandigarh","Dadra and Nagar Haveli and Daman and Diu","Delhi","Jammu and Kashmir","Ladakh","Lakshadweep","Puducherry"];
const DIMS={firm:'Firm',category:'Category',fabric:'Fabric',color:'Color',designNo:'Design',companyName:'Customer',state:'State',city:'City'};
const configured=!CONFIG.SUPABASE_URL.includes('__')&&!CONFIG.SUPABASE_ANON_KEY.includes('__');if(!configured)document.getElementById('config').classList.remove('hidden');
const sb=configured?supabase.createClient(CONFIG.SUPABASE_URL,CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true}}):null;
const API=CONFIG.SUPABASE_URL.replace(/\/$/,'')+'/functions/v1/admin-api';
const $=id=>document.getElementById(id);const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const st={designs:[],mappings:[],slots:[],selDetail:null,assisted:{customer:null,firm:'Maitri',carts:{Maitri:[],Niharika:[]}},scanner:null,scanning:false};
const dash={filters:{},breakdown:'firm',search:'',page:0,orders:[],total:0,states:[]};
function toast(m,t=''){const e=$('toast');e.textContent=m;e.className='toast open '+t;clearTimeout(window.t);window.t=setTimeout(()=>e.className='toast',3200)}
function loading(on,text='Working…'){$('loading-text').textContent=text;$('loading').classList.toggle('open',on)}
function ik(url,tr){if(!url)return '';return url+(url.includes('?')?'&':'?')+'tr='+tr}
function fmt(iso){if(!iso)return '—';return new Date(iso).toLocaleString('en-IN',{weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})}
function isAuthErr(m){return /INVALID_OR_EXPIRED_SESSION|JWT|expired|AUTH_REQUIRED|Session/i.test(String(m||''))}
function loadScript(src){return new Promise((res,rej)=>{if([...document.scripts].some(s=>s.src===src))return res();const el=document.createElement('script');el.src=src;el.onload=()=>res();el.onerror=()=>rej(new Error('Could not load a required file.'));document.head.appendChild(el)})}
async function ensureXLSX(){if(window.XLSX)return;await loadScript('https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js')}
async function ensureScanner(){if(window.Html5Qrcode)return;await loadScript('https://cdn.jsdelivr.net/npm/html5-qrcode@2.3.8/html5-qrcode.min.js')}
function fillStates(){const o='<option value="">Select</option>'+STATES.map(s=>`<option>${s}</option>`).join('');$('a-state').innerHTML=o}
fillStates();

async function token(){let{data:{session}}=await sb.auth.getSession();if(!session)throw new Error('NO_SESSION');if(session.expires_at&&(session.expires_at*1000-Date.now()<90000)){const{data,error}=await sb.auth.refreshSession();if(!error&&data.session)session=data.session}return session.access_token}
function goLogin(){try{stopScanner()}catch{}showLogged(false)}
async function admin(action,payload={}){
  const call=async()=>{const res=await fetch(API,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+await token(),'apikey':CONFIG.SUPABASE_ANON_KEY},body:JSON.stringify({action,...payload})});let json={};try{json=await res.json()}catch{}return{res,json}};
  let out;try{out=await call()}catch(e){goLogin();throw new Error('Please log in again.')}
  if(!out.json.ok&&(out.res.status===401||isAuthErr(out.json.error))){const{data,error}=await sb.auth.refreshSession();if(!error&&data.session)out=await call()}
  if(out.res.ok&&out.json.ok)return out.json.data;
  const emsg=out.json.error||`HTTP ${out.res.status}`;
  if(/ADMIN_REQUIRED/i.test(emsg))throw new Error('This account is not authorized as an admin.');
  if(out.res.status===401||isAuthErr(emsg)){goLogin();throw new Error('Your session expired — please log in again.');}
  throw new Error(emsg);
}
async function rpc(fn,args){const{data,error}=await sb.rpc(fn,args);if(error)throw error;return data}

function showLogged(on){$('login-screen').classList.toggle('hidden',on);$('top').classList.toggle('hidden',!on);$('tabs').classList.toggle('hidden',!on);document.querySelectorAll('.panel').forEach(p=>p.classList.toggle('active',on&&p.id==='panel-dashboard'))}
$('login-form').onsubmit=async e=>{e.preventDefault();try{loading(true,'Logging in…');const{error}=await sb.auth.signInWithPassword({email:$('email').value.trim(),password:$('password').value});if(error)throw error;await boot()}catch(err){toast(err.message,'error');await sb.auth.signOut()}finally{loading(false)}};
$('logout').onclick=async()=>{await stopScanner();await sb.auth.signOut();showLogged(false)};$('refresh').onclick=()=>loadTab(currentTab,true);

let currentTab='dashboard';
document.querySelectorAll('#tabs .tab').forEach(t=>t.onclick=()=>{currentTab=t.dataset.tab;document.querySelectorAll('#tabs .tab').forEach(x=>x.classList.toggle('active',x===t));document.querySelectorAll('.panel').forEach(p=>p.classList.toggle('active',p.id==='panel-'+currentTab));loadTab(currentTab)});

async function boot(){await admin('whoami');showLogged(true);currentTab='dashboard';loadLookups();await loadTab('dashboard',true)}
const loaded={};
async function loadTab(tab,force){try{loading(true,'Loading…');
  if(tab==='dashboard'){await loadDashboard(true)}
  else if(tab==='entry'){await searchDirectory()}
  else if(tab==='slots'){await loadSlots()}
  else if(tab==='mapping'){if(force||!loaded.mapping){await loadMapping();loaded.mapping=true}}
  else if(tab==='products'){if(force||!loaded.products){await loadProducts();loaded.products=true}}
}catch(err){toast(err.message,'error')}finally{loading(false)}}

async function loadLookups(){try{const L=await rpc('list_lookups')||{};$('dl-city').innerHTML=(L.city||[]).map(v=>`<option value="${esc(v)}">`).join('');$('dl-agent').innerHTML=(L.agent||[]).map(v=>`<option value="${esc(v)}">`).join('');$('dl-category').innerHTML=(L.category||[]).map(v=>`<option value="${esc(v)}">`).join('');$('dl-fabric').innerHTML=(L.fabric||[]).map(v=>`<option value="${esc(v)}">`).join('');$('dl-color').innerHTML=(L.color||[]).map(v=>`<option value="${esc(v)}">`).join('')}catch(e){}}

/* ---------- Dashboard (server-aggregated, drill-down) ---------- */
async function loadDashboard(reset){if(reset){dash.page=0;dash.orders=[]}
  const d=await rpc('admin_dashboard',{p_filters:dash.filters,p_search:dash.search,p_breakdown:dash.breakdown,p_limit:50,p_offset:dash.page*50});
  dash.states=d.states||dash.states;dash.total=d.totalOrders||0;
  dash.orders=reset?(d.orders||[]):dash.orders.concat(d.orders||[]);
  const k=d.kpis||{};$('k-pieces').textContent=k.totalSets||0;$('k-customers').textContent=k.customers||0;$('k-orders').textContent=k.orders||0;$('k-designs').textContent=k.designs||0;$('k-maitri').textContent=k.maitriSets||0;$('k-niharika').textContent=k.niharikaSets||0;
  $('updated').textContent='Generated '+new Date(d.generatedAt).toLocaleString('en-IN');
  renderDimChips();renderStateChips();renderFilterChips();renderBreakdown(d.breakdown||[]);renderOrders();
}
function renderDimChips(){$('d-dimchips').innerHTML=Object.entries(DIMS).map(([k,v])=>`<button class="dimchip ${k===dash.breakdown?'active':''}" data-dim="${k}">${v}</button>`).join('')}
$('d-dimchips').onclick=e=>{const b=e.target.closest('[data-dim]');if(!b)return;dash.breakdown=b.dataset.dim;loadDashboard(true).catch(er=>toast(er.message,'error'))};
function renderStateChips(){const sel=dash.filters.state||[];$('d-states').innerHTML=dash.states.map(s=>`<button class="statechip ${sel.includes(s)?'on':''}" data-state="${esc(s)}">${esc(s)}</button>`).join('')||'<span class="copy">No states yet.</span>'}
$('d-states').onclick=e=>{const b=e.target.closest('[data-state]');if(!b)return;const s=b.dataset.state;const arr=dash.filters.state||[];const i=arr.indexOf(s);if(i>=0)arr.splice(i,1);else arr.push(s);if(arr.length)dash.filters.state=arr;else delete dash.filters.state;loadDashboard(true).catch(er=>toast(er.message,'error'))};
function renderFilterChips(){const chips=[];Object.entries(dash.filters).forEach(([dim,vals])=>vals.forEach(v=>chips.push({dim,v})));$('d-chips').innerHTML=chips.map(c=>`<button class="chip" data-rmdim="${c.dim}" data-rmval="${esc(c.v)}">${esc(DIMS[c.dim]||c.dim)}: ${esc(c.v)} ✕</button>`).join('')+(chips.length?'<button class="chip clear" data-clear="1">Clear all</button>':'')}
$('d-chips').onclick=e=>{const rm=e.target.closest('[data-rmdim]'),cl=e.target.closest('[data-clear]');if(cl){dash.filters={}}else if(rm){const dim=rm.dataset.rmdim,v=rm.dataset.rmval;const arr=dash.filters[dim]||[];const i=arr.indexOf(v);if(i>=0)arr.splice(i,1);if(!arr.length)delete dash.filters[dim]}else return;loadDashboard(true).catch(er=>toast(er.message,'error'))};
function renderBreakdown(rows){const max=Math.max(1,...rows.map(r=>r.sets));$('d-dim-title').textContent='Breakdown by '+(DIMS[dash.breakdown]||dash.breakdown);$('d-dim-sub').textContent=rows.length+' value'+(rows.length===1?'':'s')+' · top 100 · tap to drill';$('d-breakdown').innerHTML=rows.length?rows.map(r=>`<button class="drill" data-val="${esc(r.label)}"><span class="bl">${esc(r.label)}</span><div class="fill" style="width:${Math.max(3,Math.round(r.sets/max*100))}%"></div><span class="bv">${r.sets} sets · ${r.designs} des · ${r.customers} cust</span></button>`).join(''):'<div class="empty">No data.</div>'}
$('d-breakdown').onclick=e=>{const b=e.target.closest('[data-val]');if(!b)return;const dim=dash.breakdown,v=b.dataset.val;const arr=dash.filters[dim]||[];if(!arr.includes(v))arr.push(v);dash.filters[dim]=arr;loadDashboard(true).catch(er=>toast(er.message,'error'))};
function renderOrders(){$('order-count').textContent=dash.orders.length+' / '+dash.total+' orders';$('orders').innerHTML=(dash.orders.length?dash.orders.map((o,i)=>`<div class="li drilldown" data-i="${i}"><div><b>${esc(o.companyName)} · ${esc(o.firm)}</b><p>${esc(o.contactName)} · +${esc(o.phone)} · ${esc([o.city,o.state].filter(Boolean).join(', '))}${o.agent?' · Agent: '+esc(o.agent):''}<br>${esc(o.status)} · ${new Date(o.updatedAt).toLocaleString('en-IN')}</p></div><div class="value"><strong>${o.sets}</strong><span>${o.designs} designs</span></div></div>`).join(''):'<div class="empty">No orders match.</div>')+(dash.orders.length<dash.total?'<button id="load-more" class="btn ghost" style="margin-top:8px">Load more</button>':'')}
let dTimer;$('d-search').addEventListener('input',()=>{clearTimeout(dTimer);dTimer=setTimeout(()=>{dash.search=$('d-search').value.trim();loadDashboard(true).catch(er=>toast(er.message,'error'))},350)});
$('orders').onclick=async e=>{if(e.target.id==='load-more'){dash.page++;try{loading(true);await loadDashboard(false)}catch(er){toast(er.message,'error')}finally{loading(false)}return}const r=e.target.closest('[data-i]');if(!r)return;openDetail(dash.orders[Number(r.dataset.i)])};

async function openDetail(o){try{loading(true,'Loading order…');const d=await admin('getCustomerOrders',{customerId:o.customerId});const ord=(d.orders||[]).find(x=>x.firm===o.firm)||{items:[],status:o.status};const c=d.customer||{};st.selDetail={orderId:o.orderId,firm:o.firm,customerId:o.customerId,status:ord.status||o.status,customerActive:c.active!==false};
  $('detail-title').textContent=o.companyName+' · '+o.firm;$('detail-sub').textContent=`${c.contactName||o.contactName} · +${c.phone||o.phone} · ${[c.city,c.state].filter(Boolean).join(', ')}${c.agent?' · Agent: '+c.agent:''}`;
  const sets=(ord.items||[]).reduce((s,i)=>s+Number(i.qty||0),0);
  $('detail-metrics').innerHTML=`<div class="detail-metric"><b>${sets}</b><span>Sets</span></div><div class="detail-metric"><b>${(ord.items||[]).length}</b><span>Designs</span></div><div class="detail-metric"><b>${esc(ord.status||o.status)}</b><span>Status</span></div><div class="detail-metric"><b>${c.gstin||'—'}</b><span>GSTIN</span></div>`;
  $('detail-items').innerHTML=(ord.items||[]).length?ord.items.map(i=>`<div class="line">${i.imageUrl?`<img src="${esc(ik(i.imageUrl,'w-160,h-210,c-at_max,q-55'))}" referrerpolicy="no-referrer">`:'<div style="width:56px;height:74px;border-radius:8px;background:#EEF2F0"></div>'}<div><b>${esc(i.designNo)}</b><p>${esc([i.category,i.fabric,i.color].filter(Boolean).join(' · '))}<br>${esc(i.description||'')}</p></div><strong>${i.qty} sets</strong></div>`).join(''):'<div class="empty">No items.</div>';
  $('lock-order').textContent=(ord.status||o.status)==='Locked'?'Unlock order':'Lock order';$('customer-toggle').textContent=st.selDetail.customerActive?'Disable customer':'Enable customer';
  $('detail-modal').classList.add('open');
}catch(err){toast(err.message,'error')}finally{loading(false)}}
$('detail-close').onclick=()=>$('detail-modal').classList.remove('open');$('detail-modal').onclick=e=>{if(e.target===$('detail-modal'))$('detail-modal').classList.remove('open')};
$('lock-order').onclick=async()=>{const o=st.selDetail;if(!o)return;try{loading(true);await admin('setOrderLocked',{orderId:o.orderId,locked:o.status!=='Locked'});$('detail-modal').classList.remove('open');await loadDashboard(true);toast('Order updated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('customer-toggle').onclick=async()=>{const o=st.selDetail;if(!o)return;try{loading(true);await admin('setCustomerActive',{customerId:o.customerId,active:!o.customerActive});$('detail-modal').classList.remove('open');await loadDashboard(true);toast('Customer updated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

function xs(v){const s=String(v??'');return /^[=+\-@]/.test(s)?"'"+s:s}
$('export').onclick=async()=>{try{loading(true,'Building export…');await ensureXLSX();let all=[],off=0;while(true){const d=await rpc('admin_dashboard',{p_filters:dash.filters,p_search:dash.search,p_breakdown:dash.breakdown,p_limit:200,p_offset:off});const os=d.orders||[];all=all.concat(os);off+=200;if(all.length>=(d.totalOrders||0)||os.length<200)break}const rows=all.map(o=>({Company:xs(o.companyName),Contact:xs(o.contactName),Phone:o.phone,City:xs(o.city),State:xs(o.state),Agent:xs(o.agent),Firm:o.firm,Status:o.status,Designs:o.designs,Sets:o.sets,Updated:o.updatedAt}));const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Orders');XLSX.writeFile(wb,'Maitri-Carnival-2026-Orders.xlsx')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('reset-btn').onclick=async()=>{try{const phone=$('reset-phone').value.trim(),newPassword=$('reset-password').value;if(newPassword.length<8)throw new Error('Use at least 8 characters');if(!confirm('Reset password for '+phone+'?'))return;loading(true);const d=await admin('resetPassword',{phone,newPassword});$('reset-phone').value='';$('reset-password').value='';toast('Password reset for '+d.companyName,'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

/* ---------- Entry ---------- */
let eTimer;$('e-search').addEventListener('input',()=>{clearTimeout(eTimer);eTimer=setTimeout(()=>searchDirectory().catch(e=>toast(e.message,'error')),300)});
async function searchDirectory(){const data=await admin('directory',{query:$('e-search').value.trim()});$('e-list').innerHTML=data.length?data.map(c=>{const badge=c.active===false?'<span class="badge off">Paused</span>':c.checkedInAt?`<span class="badge in">Checked in ${fmt(c.checkedInAt)}</span>`:'<span class="badge out">Not entered</span>';const slot=c.booking?`<span class="badge slot">Slot: ${fmt(c.booking.startsAt)}</span>`:'<span class="badge out">No slot</span>';const btn=c.checkedInAt?`<button class="btn ghost sm" style="width:auto" data-revoke="${c.id}">Revoke</button>`:`<button class="btn sm" data-checkin="${c.id}">Check in</button>`;return `<div class="li"><div><b>${esc(c.companyName)}</b><p>${esc(c.contactName)} · +${esc(c.phone)} · ${esc([c.city,c.state].filter(Boolean).join(', '))}${c.agent?' · Agent: '+esc(c.agent):''}<br>${badge} ${slot}${c.editDeadline?' · edits until '+fmt(c.editDeadline):''}</p></div><div class="row-actions">${btn}</div></div>`}).join(''):'<div class="empty">No matching customers.</div>'}
$('e-list').onclick=async e=>{const ci=e.target.closest('[data-checkin]'),rv=e.target.closest('[data-revoke]');if(!ci&&!rv)return;try{if(ci){loading(true,'Checking in…');await admin('checkIn',{customerId:ci.dataset.checkin});toast('Checked in','success')}else{if(!confirm('Revoke entry for this customer?')){loading(false);return}loading(true,'Revoking…');await admin('revokeEntry',{customerId:rv.dataset.revoke})}await searchDirectory()}catch(err){toast(err.message,'error')}finally{loading(false)}};

/* ---------- Slots ---------- */
async function loadSlots(){const[slots]=await Promise.all([admin('listSlots')]);st.slots=slots;
  $('s-list').innerHTML=slots.length?slots.map(s=>`<div class="li"><div><b>${esc(fmt(s.startsAt))} → ${esc(new Date(s.endsAt).toLocaleTimeString('en-IN',{hour:'numeric',minute:'2-digit'}))}</b><p>${esc(s.label||'—')} · ${s.booked} booked${s.capacity!=null?' / '+s.capacity+' cap':''} · ${s.active?'Active':'Inactive'}</p></div><div class="row-actions"><button class="btn ghost sm" style="width:auto" data-del="${s.id}">Delete</button></div></div>`).join(''):'<div class="empty">No slots yet.</div>';
  const max=Math.max(1,...slots.map(s=>s.booked));$('traffic').innerHTML=slots.length?slots.map(s=>`<div class="bar"><span>${esc(new Date(s.startsAt).toLocaleString('en-IN',{day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}))}</span><div class="fill" style="width:${Math.round(s.booked/max*100)}%"></div><span>${s.booked}</span></div>`).join(''):'<div class="empty">No bookings yet.</div>'}
$('s-add').onclick=async()=>{try{const startsAt=$('s-start').value,endsAt=$('s-end').value;if(!startsAt||!endsAt){toast('Start and end are required','error');return}loading(true,'Adding slot…');await admin('upsertSlot',{startsAt:new Date(startsAt).toISOString(),endsAt:new Date(endsAt).toISOString(),label:$('s-label').value.trim(),capacity:$('s-cap').value||null,active:true});$('s-label').value='';$('s-cap').value='';await loadSlots();toast('Slot added','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('s-list').onclick=async e=>{const d=e.target.closest('[data-del]');if(!d)return;if(!confirm('Delete this slot?'))return;try{loading(true);const r=await admin('deleteSlot',{id:d.dataset.del});await loadSlots();toast(r.deactivated?'Slot had bookings — deactivated':'Slot deleted','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

/* ---------- Mapping ---------- */
async function loadMapping(){const[designs,mappings]=await Promise.all([admin('listDesigns'),admin('listMappings')]);st.designs=designs;st.mappings=mappings;$('m-designlist').innerHTML=designs.filter(d=>d.active).map(d=>`<option value="${esc(d.designNo)}">${esc(d.firm+' · '+d.category+' · '+d.color)}</option>`).join('');renderMappings()}
function renderMappings(){const q=$('m-filter').value.trim().toLowerCase();const rows=st.mappings.filter(x=>!q||x.barcode.toLowerCase().includes(q)||x.designNo.toLowerCase().includes(q)).slice(0,200);$('m-list').innerHTML=rows.length?rows.map(x=>`<div class="li"><div><b>${esc(x.barcode)} → ${esc(x.designNo)}</b><p>${esc([x.firm,x.category,x.fabric,x.color].filter(Boolean).join(' · '))} · ${x.active?'Active':'Inactive'}</p></div>${x.active?`<button class="btn ghost sm" style="width:auto" data-off="${esc(x.barcode)}">Deactivate</button>`:''}</div>`).join(''):'<div class="empty">No mappings.</div>'}
$('m-filter').oninput=renderMappings;
$('m-list').onclick=async e=>{const b=e.target.closest('[data-off]');if(!b)return;if(!confirm('Deactivate '+b.dataset.off+'?'))return;try{loading(true);await admin('deactivateBarcode',{barcode:b.dataset.off});st.mappings=await admin('listMappings');renderMappings();toast('Deactivated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
async function saveMapping(){const barcode=$('m-barcode').value.trim(),designNo=$('m-design').value.trim();if(!barcode||!designNo){toast('Barcode and design required','error');return}if(!st.designs.some(d=>d.designNo===designNo&&d.active)){toast('Choose an active design','error');return}try{loading(true);const d=await admin('mapBarcode',{barcode,designNo});$('m-barcode').value='';$('m-barcode').focus();st.mappings=await admin('listMappings');renderMappings();$('m-note').textContent=`${d.barcode} → ${d.designNo}`;navigator.vibrate?.(80)}catch(err){toast(err.message,'error')}finally{loading(false)}}
$('m-map').onclick=saveMapping;$('m-barcode').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();saveMapping()}};
$('m-batchbtn').onclick=async()=>{const lines=$('m-batch').value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);let items;try{items=lines.map((l,i)=>{const p=l.split(/[\t,]/).map(x=>x.trim());if(p.length<2||!p[0]||!p[1])throw new Error(`Line ${i+1} must be BARCODE,DESIGNNO`);return{barcode:p[0],designNo:p[1]}})}catch(err){toast(err.message,'error');return}if(!items.length){toast('Paste at least one mapping','error');return}try{loading(true);const d=await admin('mapBatch',{items});const fails=d.results.filter(x=>!x.ok);st.mappings=await admin('listMappings');renderMappings();$('m-batch').value='';toast(fails.length?`${items.length-fails.length} saved, ${fails.length} failed`:`${items.length} saved`,fails.length?'error':'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
$('m-camera').onclick=async()=>{if(st.scanning){await stopScanner();return}try{await ensureScanner();st.scanner=new Html5Qrcode('m-reader');$('m-reader').classList.add('open');await st.scanner.start({facingMode:'environment'},{fps:10,qrbox:{width:260,height:160}},async code=>{$('m-barcode').value=code;await stopScanner();$('m-design').focus()},()=>{});st.scanning=true;$('m-camera').textContent='Close camera'}catch(err){toast('Camera failed: '+err.message,'error');await stopScanner()}};
async function stopScanner(){if(st.scanner){try{if(st.scanning)await st.scanner.stop()}catch{}try{await st.scanner.clear()}catch{}}st.scanner=null;st.scanning=false;$('m-reader').classList.remove('open');$('m-camera').textContent='Camera'}

/* ---------- Products (edit) ---------- */
async function loadProducts(){st.designs=await admin('listDesigns');loadLookups();renderProducts()}
function pcard(d){return `<div class="li drilldown" data-dn="${esc(d.designNo)}"><div><b>${esc(d.designNo)}</b><p>${esc([d.firm,d.category,d.fabric,d.color].filter(Boolean).join(' · '))}<br>${esc(d.description||'')}</p></div><span class="badge ${d.active?'in':'off'}">${d.active?'Active':'Inactive'}</span></div>`}
function renderProducts(){const q=$('p-filter').value.trim().toLowerCase();const g=$('p-group').value;const rows=st.designs.filter(d=>!q||[d.designNo,d.category,d.color,d.fabric,d.firm,d.description].join(' ').toLowerCase().includes(q));
  $('p-sub').textContent=rows.length+' designs'+(g?' · grouped by '+(DIMS[g]||g):'')+' · tap to edit';
  if(!g){$('p-list').className='list';$('p-list').innerHTML=rows.length?rows.slice(0,1000).map(pcard).join(''):'<div class="empty">No products.</div>';return}
  const m=new Map();rows.forEach(d=>{const k=(d[g]||'—');if(!m.has(k))m.set(k,[]);m.get(k).push(d)});
  const groups=[...m.entries()].sort((a,b)=>b[1].length-a[1].length);
  $('p-list').className='';$('p-list').innerHTML=groups.length?groups.map(([k,ds],gi)=>`<div class="grouphdr" data-g="${gi}">${esc(k)}<span class="cnt">${ds.length} designs · ${ds.filter(x=>x.active).length} active</span></div><div class="groupbody" id="gb-${gi}">${ds.map(pcard).join('')}</div>`).join(''):'<div class="empty">No products.</div>'}
$('p-filter').oninput=renderProducts;$('p-group').onchange=renderProducts;
$('p-list').onclick=e=>{const dn=e.target.closest('[data-dn]');if(dn){openProduct(dn.dataset.dn);return}const h=e.target.closest('[data-g]');if(h){const b=$('gb-'+h.dataset.g);if(b)b.classList.toggle('open')}};
async function openProduct(designNo){try{loading(true,'Loading design…');const d=await admin('getProductDetail',{designNo});const g=d.design;$('pm-title').textContent=g.designNo;$('pm-sub').textContent='Updated '+fmt(g.updatedAt);$('pm-img').src=g.imageUrl?ik(g.imageUrl,'w-240,h-320,c-at_max,q-60'):'';$('pm-firm').value=g.firm;$('pm-category').value=g.category||'';$('pm-fabric').value=g.fabric||'';$('pm-color').value=g.color||'';$('pm-active').value=g.active?'true':'false';$('pm-desc').value=g.description||'';$('pm-barcodes').innerHTML='<b>Barcodes:</b> '+(d.barcodes.length?d.barcodes.map(b=>esc(b.barcode)+(b.active?'':' (inactive)')).join(', '):'none mapped yet');st.editDesign=designNo;$('prod-modal').classList.add('open')}catch(err){toast(err.message,'error')}finally{loading(false)}}
$('pm-close').onclick=()=>$('prod-modal').classList.remove('open');$('prod-modal').onclick=e=>{if(e.target===$('prod-modal'))$('prod-modal').classList.remove('open')};
$('pm-save').onclick=async()=>{try{loading(true,'Saving…');await admin('updateProduct',{designNo:st.editDesign,firm:$('pm-firm').value,category:$('pm-category').value.trim(),fabric:$('pm-fabric').value.trim(),color:$('pm-color').value.trim(),description:$('pm-desc').value.trim(),active:$('pm-active').value==='true'});$('prod-modal').classList.remove('open');st.designs=await admin('listDesigns');loadLookups();renderProducts();toast('Design updated','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

/* ---------- Assisted ---------- */
let aTimer;$('a-search').addEventListener('input',()=>{clearTimeout(aTimer);aTimer=setTimeout(()=>assistedSearch().catch(e=>toast(e.message,'error')),300)});
async function assistedSearch(){const data=await admin('directory',{query:$('a-search').value.trim()});$('a-results').innerHTML=data.length?data.map(c=>`<div class="li"><div><b>${esc(c.companyName)}</b><p>${esc(c.contactName)} · +${esc(c.phone)}</p></div><button class="btn sm" data-pick='${esc(JSON.stringify({id:c.id,companyName:c.companyName,phone:c.phone}))}'>Build order</button></div>`).join(''):'<div class="empty">No customers found.</div>'}
$('a-results').onclick=e=>{const b=e.target.closest('[data-pick]');if(!b)return;openBuilder(JSON.parse(b.dataset.pick))};
$('a-register').onclick=async()=>{try{const phone=$('a-phone').value.trim();if(!/^[6-9]\d{9}$/.test(phone)){toast('Enter a valid 10-digit mobile','error');return}loading(true,'Registering…');const d=await admin('assistedRegister',{phone,companyName:$('a-company').value.trim(),contactName:$('a-contact').value.trim(),city:$('a-city').value.trim(),state:$('a-state').value,agent:$('a-agent').value.trim(),password:$('a-pass').value.trim()});$('a-cred').innerHTML=`<div class="cred-box">Registered <b>${esc(d.companyName)}</b><br>Login: <b>${esc('91'+phone)}</b> · Password: <b>${esc(d.password)}</b><br>Share these with the customer.</div>`;['a-company','a-contact','a-city','a-agent','a-phone','a-pass'].forEach(id=>$(id).value='');loadLookups();openBuilder({id:d.customerId,companyName:d.companyName,phone:'91'+phone});toast('Party registered','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};
async function openBuilder(cust){st.assisted.customer=cust;st.assisted.firm='Maitri';st.assisted.carts={Maitri:[],Niharika:[]};$('a-party').textContent='Order for '+cust.companyName;$('a-builder').classList.remove('hidden');document.querySelectorAll('.a-firm').forEach(t=>t.classList.toggle('active',t.dataset.firm==='Maitri'));
  try{loading(true,'Loading party orders…');const d=await admin('getCustomerOrders',{customerId:cust.id});(d.orders||[]).forEach(o=>{st.assisted.carts[o.firm]=(o.items||[]).map(i=>({...i}))})}catch(err){toast(err.message,'error')}finally{loading(false)}
  renderAssistedCart();$('a-builder').scrollIntoView({behavior:'smooth'})}
$('a-close').onclick=()=>{$('a-builder').classList.add('hidden');st.assisted.customer=null};
document.querySelectorAll('.a-firm').forEach(t=>t.onclick=()=>{st.assisted.firm=t.dataset.firm;document.querySelectorAll('.a-firm').forEach(x=>x.classList.toggle('active',x===t));renderAssistedCart()});
function aCart(){return st.assisted.carts[st.assisted.firm]}
function renderAssistedCart(){const cart=aCart();$('a-cart').innerHTML=cart.length?cart.map((it,i)=>`<div class="li"><div style="display:flex;gap:9px;align-items:center;min-width:0">${it.imageUrl?`<img src="${esc(ik(it.imageUrl,'w-120,h-160,c-at_max,q-55'))}" style="width:44px;height:58px;border-radius:7px;object-fit:cover" referrerpolicy="no-referrer">`:''}<div><b>${esc(it.designNo)}</b><p>${esc([it.category,it.fabric,it.color].filter(Boolean).join(' · '))}</p></div></div><div style="display:flex;align-items:center;gap:4px"><button class="btn ghost sm" style="width:auto" data-a="minus" data-i="${i}">−</button><input data-a="qty" data-i="${i}" type="number" min="1" max="9999" value="${Number(it.qty)||1}" style="width:56px;text-align:center;min-height:36px"><button class="btn ghost sm" style="width:auto" data-a="plus" data-i="${i}">+</button><button class="btn ghost sm" style="width:auto;color:var(--error)" data-a="rm" data-i="${i}">✕</button></div></div>`).join(''):'<div class="empty">No items. Scan or type a barcode.</div>'}
$('a-cart').addEventListener('click',e=>{const b=e.target.closest('[data-a]');if(!b||b.tagName==='INPUT')return;const i=Number(b.dataset.i),cart=aCart();if(b.dataset.a==='plus')cart[i].qty=Math.min(9999,(Number(cart[i].qty)||1)+1);if(b.dataset.a==='minus')cart[i].qty=Math.max(1,(Number(cart[i].qty)||1)-1);if(b.dataset.a==='rm')cart.splice(i,1);renderAssistedCart()});
$('a-cart').addEventListener('change',e=>{if(e.target.dataset.a!=='qty')return;const i=Number(e.target.dataset.i);aCart()[i].qty=Math.max(1,Math.min(9999,Number(e.target.value)||1));renderAssistedCart()});
async function aAdd(raw){const barcode=String(raw||'').trim();if(!barcode)return;try{const data=await rpc('lookup_barcode',{p_barcode:barcode});const row=Array.isArray(data)?data[0]:data;if(!row)throw new Error('Barcode not mapped to an active design');if(![st.assisted.firm,'Both'].includes(row.firm))throw new Error(`${row.design_no} belongs to ${row.firm}. Switch firm.`);const cart=aCart();if(cart.some(x=>x.designNo===row.design_no))throw new Error(`${row.design_no} already added`);cart.push({barcode:row.barcode,designNo:row.design_no,imageUrl:row.image_url||'',qty:1,category:row.category,fabric:row.fabric,color:row.color,description:row.description});$('a-barcode').value='';renderAssistedCart();$('a-note').textContent='Added '+row.design_no}catch(err){$('a-note').textContent=err.message}}
$('a-add').onclick=()=>aAdd($('a-barcode').value);$('a-barcode').onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();aAdd(e.target.value)}};
$('a-save').onclick=async()=>{const c=st.assisted.customer;if(!c)return;try{loading(true,'Saving order…');const firm=st.assisted.firm;const items=aCart().map(x=>({barcode:x.barcode||'',designNo:x.designNo,qty:Number(x.qty)||1}));const d=await admin('assistedSaveOrder',{customerId:c.id,firm,items});if(!d.ok)throw new Error(d.message||'Save failed');toast(`${firm} order saved for ${c.companyName}`,'success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

/* ---------- Staff ---------- */
$('st-create').onclick=async()=>{try{const email=$('st-email').value.trim();if(!email){toast('Enter a staff email','error');return}loading(true,'Creating staff login…');const d=await admin('createStaff',{email,password:$('st-pass').value.trim()});$('st-cred').innerHTML=`<div class="cred-box">Staff login created<br>Email: <b>${esc(d.email)}</b><br>Password: <b>${esc(d.password)}</b><br>Share these with the staff member; they log in on their own device.</div>`;$('st-email').value='';$('st-pass').value='';toast('Staff login created','success')}catch(err){toast(err.message,'error')}finally{loading(false)}};

if(sb){sb.auth.getSession().then(async({data})=>{if(data.session){try{loading(true);await boot()}catch(e){showLogged(false);if(/admin/i.test(e.message))toast(e.message,'error')}finally{loading(false)}}else showLogged(false)})}else showLogged(false);
</script>
</body></html>
