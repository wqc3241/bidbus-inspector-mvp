// ---------- V1 inspected-car screens: CR mark on the run list, Bidbus CR on vehicle details, bid confirm, admin ----------
// Reuses the condition report page's example data (EX.ice, problems(), media()), icons and drawings.
// Web screens copy the live dealer web portal (run list cards and the vehicle details window).
var V1_GROUPS = SECS.map(function (s) { return s[0]; });
var CR_ROWS = V1_GROUPS.filter(function (g) { return g !== "Damages"; });
// Engine sound: its own Bidbus CR row after Mechanicals (Tom 11-05), on gas, hybrid and plug-in hybrid cars only.
// It plays the engine sound and exhaust videos and shows the result of the Engine check, which leaves the Mechanicals row.
CR_ROWS.splice(CR_ROWS.indexOf("Mechanicals") + 1, 0, "Engine sound");
var ENG_CK = "ck_engine";
var ENG_VIDS = [["video_engine", "Engine", "Start, idle, rev", "0:45"], ["video_exhaust", "Exhaust", "Idle and revving", "0:40"]];
LU.volume = LU.volume || '<path d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"/><path d="M16 9a5 5 0 0 1 0 6"/><path d="M19.364 18.364a9 9 0 0 0 0-12.728"/>';
SEC_IC["Engine sound"] = "volume";
function hasEngineRow() { var it = byId(ENG_CK); return !!(it && carOk(it)); }
function rowChecks(g) {
  if (g === "Engine sound") return hasEngineRow() ? 1 : 0;
  return inSec(g, "check").filter(function (it) { return it.id !== ENG_CK; }).length;
}
function grpName(g) { return g === "OBDII" ? "OBD-II" : g; }
LU.heart = '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>';
LU.eyeoff = '<path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.526 13.526 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/><path d="m2 2 20 20"/>';
LU.ext = '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>';
LU.info = '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>';
LU.vshield = '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" fill="currentColor" stroke="none"/><path d="m9 12 2 2 4-4" stroke="#fff"/>';

var NOHL = false;
function hl(n, html, dashed, cls) { if (NOHL) return '<div class="' + (cls || "") + '">' + html + "</div>"; return '<div class="hl' + (dashed ? " dash" : "") + (cls ? " " + cls : "") + '" data-n="' + n + '">' + html + "</div>"; }
function hli(n, html, dashed, cls) { if (NOHL) return '<span class="' + (cls || "") + '">' + html + "</span>"; return '<span class="hl hli' + (dashed ? " dash" : "") + (cls ? " " + cls : "") + '" data-n="' + n + '">' + html + "</span>"; }

// the CR mark: solid Bidbus green with white "CR"
function crMark(cls) { return '<span class="crm ' + (cls || "") + '" title="Bidbus CR" aria-label="Bidbus CR">CR</span>'; }

function probs(g) {
  return problems().filter(function (f) { return g === "Engine sound" ? f.id === ENG_CK : f.sec === g && f.id !== ENG_CK; }).map(function (f) {
    return { t: f.text, s: f.sub || "" };
  });
}
function tireRows() { return [["lf", "Driver Front"], ["rf", "Passenger Front"], ["lr", "Driver Rear"], ["rr", "Passenger Rear"]]; }

// ---------- shared sections of vehicle details (web and app use the same parts) ----------
function secTires() {
  var T = X().tread;
  return '<div class="vs"><div class="vs-h">' + I("gauge", 18) + '<b>Tire Condition</b></div><div class="tgrid">' +
    tireRows().map(function (t) {
      var m = T[t[0]], c = tclass(m);
      return '<div class="trow"><small>' + t[1] + '</small><div class="tval"><i class="tdot ' + c + '"></i><span>' + tword(m) + "<small>Tread: " + m + '/32" measured</small></span></div></div>';
    }).join("") + "</div></div>";
}
function secCR() {
  var x = X(), c = x.car;
  var h = '<div class="vs crs"><div class="vs-h">' + crMark("sm") + "<b>Bidbus CR</b><small class=\"vs-r\">Inspected " + esc(fmtDate(c.date)) + " · at the seller's home</small></div>";
  h += highlights(problems(), "d v1hl");
  h += '<div class="crgrid">' + CR_ROWS.filter(function (g) { return g !== "Engine sound" || hasEngineRow(); }).map(function (g) {
    // every issue in the words of the inspector app, then every damage the inspector recorded in this section, with its photo (Tom 11-07 07:43, 07:53)
    var l = probs(g), dl = g === "Engine sound" ? [] : dmgIn(g), n = rowChecks(g), ni = l.length + dl.length;
    var v = ni ? l.map(function (p) {
      return '<div class="cri"><span class="crth">' + art("detail") + '</span><span class="crtx"><span class="bad">' + esc(p.t) + "</span>" + (p.s ? "<small>" + esc(p.s) + "</small>" : "") + "</span></div>";
    }).join("") + dl.map(function (d) {
      return '<div class="cri"><span class="crth">' + art("detail") + '</span><span class="crtx"><span class="bad">' + esc(dmgLine(d)) + "</span></span></div>";
    }).join("") : '<span class="ok">No issues</span>';
    // the Engine sound row plays its videos above the result (a car that won't start has no video)
    var vids = g !== "Engine sound" ? "" : ENG_VIDS.filter(function (e) { var it = byId(e[0]); return it && carOk(it); }).map(function (e) {
      return '<span class="crv"><span class="crth">' + art(e[0] === "video_engine" ? "engine" : "rear") + '<i class="crpl">' + I("play", 16) + '</i></span><span class="crtx"><b>' + esc(e[1]) + "</b><small>" + esc(e[2]) + " · " + e[3] + "</small></span></span>";
    }).join("");
    return '<div class="crr' + (vids ? " cre" : "") + '"><div class="crl">' + I(SEC_IC[g], 15) + "<b>" + esc(grpName(g)) + "</b><small>" + n + (n === 1 ? " check" : " checks") + (ni ? " · " + ni + (ni > 1 ? " issues" : " issue") : "") + "</small></div>" +
      (vids ? '<div class="crvs">' + vids + "</div>" : "") + v + "</div>";
  }).join("") + "</div>";
  return h + "</div>";
}

// ---------- web: the dealer portal run list ----------
function wCard(c, first) {
  var tags = '<span class="tag ' + c.tag.toLowerCase() + '">' + c.tag + "</span>" + (c.own ? '<span class="tag own">' + I("info", 12) + "1-Owner</span>" : "");
  var mark = c.cr ? (first ? hli("1.1", crMark()) : crMark()) : "";
  return '<div class="rc"><div class="rc-img">' + art(c.art) + '<span class="rc-tags">' + tags + '</span><span class="rc-ic r1">' + I("heart", 15) + '</span><span class="rc-ic r2">' + I("eyeoff", 15) + "</span></div>" +
    '<div class="rc-b"><div class="rc-t"><h3>' + esc(c.name) + "</h3>" + mark + "</div>" +
    '<div class="rc-m"><span>' + c.miles + ' Miles</span><span class="vsh">' + I("vshield", 15) + '</span><span class="loc">' + I("pin", 13) + c.loc + '</span><span class="gv">' + I("copy", 13) + "Get VIN</span></div>" +
    '<div class="rc-s"><div><small>Status</small><b>Upcoming</b></div><div class="r"><small>Starting Bid</small><b>' + c.price + "</b></div></div>" +
    '<div class="rc-d">' + I("calendar", 14) + "Begins: <b>2026-11-05 14:00 PST</b></div><div class=\"rc-d\">" + I("clock", 14) + "Ends: <b>2026-11-05 16:00 PST</b></div>" +
    '<span class="rc-ab">' + I("zap", 15) + "Auto Bid</span><small class=\"rc-np\">Not set bid proxy yet</small>" +
    '<div class="rc-note">' + I("pen", 15) + "Enter note here</div></div></div>";
}
function wRunList() {
  var cars = [
    { tag: "LOAN", name: "2018 Toyota RAV4", miles: "68,410", loc: "LA", price: "$18,500", cr: true, art: "side" },
    { tag: "TITLE", name: "2019 Honda Accord", miles: "52,110", loc: "LA", price: "$14,500", cr: false, art: "side" },
    { tag: "LEASE", own: true, name: "2022 Tesla Model Y", miles: "41,250", loc: "LA", price: "$26,000", cr: true, art: "front" },
    { tag: "LOAN", own: true, name: "2024 Toyota Sienna", miles: "23,771", loc: "LA", price: "$43,000", cr: false, art: "side" }];
  return '<div class="rl-w"><div class="rl-bar"><span>View: <b>All (31)</b></span><span>Workbook (0)</span><span>Hidden (0)</span></div><div class="rgrid">' +
    cars.map(function (c, i) { return wCard(c, i === 0); }).join("") + "</div></div>";
}

// ---------- web: the vehicle details window ----------
function wGallery() {
  var M = media(), groups = V1_GROUPS.filter(function (g) { return M.some(function (m) { return m.g === g; }); });
  var L = M.filter(function (m) { return m.g === "Exterior"; });
  var big = L[0], sm = L.slice(1, 5);
  var h = '<div class="pg"><div class="pg-big">' + art(big.art) + (big.v ? '<span class="g-play">' + I("play", 26) + "</span>" : "") + '<span class="pg-cap">' + esc(big.lbl + (big.v ? " · " + big.v : "")) + "</span></div><div class=\"pg-sm\">" +
    sm.map(function (m) { return "<span>" + art(m.art, m.flip ? "flip" : "") + "</span>"; }).join("") + "</div></div>";
  var nav = '<div class="pgnav"><span class="pgb">' + I("left", 14) + "Previous Group</span><div class=\"pgchips\">" +
    groups.map(function (g) { var n = M.filter(function (m) { return m.g === g; }).length, on = g === "Exterior"; return '<span class="' + (on ? "on" : "") + '" title="' + esc(grpName(g)) + '">' + I(SEC_IC[g], 14) + (on ? "<b>" + esc(grpName(g)) + "</b>" : "") + "<em>" + n + "</em></span>"; }).join("") +
    '</div><span class="pgb">Next Group' + I("right", 14) + "</span></div>";
  return h + hl("1.2", nav, true, "pgnav-hl");
}
function wDetails() {
  var x = X(), c = x.car;
  var h = '<div class="vm"><div class="vm-h"><div><div class="vm-t"><h1>' + esc(c.name + " " + c.trim) + "</h1>" + hli("1.2", crMark("lg")) + '</div><small>' + c.miles.toLocaleString() + " Miles • A • AWD</small></div>" +
    '<span class="vm-x">' + I("x", 18) + '</span><span class="vm-od">' + I("ext", 15) + "Open Details</span></div>";
  h += wGallery();
  h += '<div class="vm-bid"><div><b>2026-11-05 14:00 PST</b><small>Begins</small></div><div><b class="pr">' + c.price + '</b><small>Starting bid</small></div><div class="ab"><span class="rc-ab">' + I("zap", 15) + "Auto Bid</span><small>Not set bid proxy yet</small></div></div>";
  h += '<div class="vm-loc"><div><small>Seller location</small><b>' + I("pin", 15) + "Los Angeles, CA 90034</b></div><div><small>Send to store</small><b>" + I("store", 15) + 'Delta Ridge Toyota</b></div><div class="dist"><small>Distance</small><b>' + I("route", 15) + "14 miles</b></div></div>";
  h += '<div class="vm-spec"><div><p><span>Mileage</span><b>' + c.miles.toLocaleString() + '</b></p><p><span>Vin</span><b>' + c.vin + ' <em>' + I("copy", 13) + "Copy</em></b></p><p><span>Wholesale Value</span><b>$19,400</b></p><p><span>Lending Value</span><b>$20,900</b></p></div>" +
    '<div><p><span>Title Status</span><b><i class="tst">LOAN</i></b></p><p><span>Lienholder</span><b>Toyota Financial Services</b></p><p><span>Location</span><b>' + I("pin", 15) + '90034 (Los Angeles)</b></p><p><span>Black Book</span><b>$20,100</b></p></div></div>';
  h += hl("1.2", secTires(), true) + hl("1.2", secCR());
  return h + "</div>";
}

// ---------- agree before Bid or Auto Bid ----------
function confirmSheet(web) {
  var rows = [["camera", "Bidbus inspected this car before the sale. Every issue our inspector found is in the Bidbus CR, with photos."],
    ["ban", "<b>Disclosed issues are in your bid.</b> You can't lower the price at delivery for an issue the CR shows."],
    ["store", "<b>Found an issue the CR didn't show?</b> Contact Bidbus. Don't adjust the price with the seller."]];
  return '<div class="sht' + (web ? " web" : "") + '">' + (web ? "" : '<span class="grab2"></span>') + '<div class="sht-h">' + crMark("xl") + "<b>This car has a Bidbus CR</b></div>" +
    rows.map(function (r) { return '<div class="sht-r"><span>' + I(r[0], 18) + "</span><p>" + r[1] + "</p></div>"; }).join("") +
    '<label class="sht-ck"><i class="cbox"></i>Don\'t show me again</label>' +
    '<div class="sht-b"><span class="sb2">View Bidbus CR</span><span class="sb1">I agree, place my bid</span></div></div>';
}

// ---------- mobile app ----------
function mRunList() {
  var h = '<header class="dh rl"><span class="rl-logo">' + LOGO + '</span><b class="dh-t">Run List ⌄</b><span class="dmenu">' + I("menu", 22) + "</span></header>";
  h += '<div class="rl-tabs"><span class="on">All (5)</span><span>Workbook (1)</span><span>Hidden (1)</span></div>';
  h += '<div class="scroller rl-page"><div class="rl-meta"><span class="vc">' + I("car", 14) + "Vehicles: 49</span><span>Area: <b>Los Angeles</b></span></div>" +
    '<div class="rl-beg"><div><small>Begins</small><b>2026-11-05 14:00 PST</b></div><span class="cd">30:50:59</span></div>';
  var cars = [["2018 Toyota RAV4", "68,410 Miles", "$18,500", true, "side"], ["2019 Honda Accord", "52,110 Miles", "$14,500", false, "side"], ["2022 Tesla Model Y", "41,250 Miles", "$26,000", true, "front"]];
  h += cars.map(function (c, i) {
    var mark = c[3] ? (i === 0 ? hli("1.1", crMark()) : crMark()) : "";
    return '<div class="rlc"><div class="rlc-l"><span class="rlimg">' + art(c[4]) + '</span><span class="rlb">' + I("bookmark", 16) + "</span></div>" +
      '<div class="rlc-r"><div class="rlt"><h3>' + esc(c[0]) + "</h3>" + mark + '</div><div class="rlm">' + esc(c[1]) + "</div>" +
      '<div class="rlp"><span>11/05/26<br>9am–1pm</span><span><small>Starting Bid</small><b>' + c[2] + '</b></span></div><span class="rlbtn">' + I("zap", 16) + "Auto Bid</span></div></div>";
  }).join("");
  return h + "</div>";
}
function mHeader() { return '<header class="dh"><span class="tb-btn">' + I("left", 22) + '</span><b class="dh-t">Vehicle details</b><span class="call">Call</span><span class="dmenu">' + I("menu", 22) + "</span></header>"; }
function mFooter() { return '<footer class="df"><div class="ps"><small>Starting bid</small><b>' + X().car.price + '</b></div><span class="abid">⚡ Auto Bid</span><span class="circ2">' + I("bookmark", 18) + "</span></footer>"; }
function mDetails() {
  var c = X().car;
  var h = mHeader() + '<div class="scroller d-page">';
  h += '<div class="d-head"><div class="eyebrow">Upcoming auction</div><div class="mt"><h1>' + esc(c.name) + "</h1>" + hli("1.2", crMark("lg")) + '</div><p class="trim">' + esc(c.trim) + '</p><p class="ml">' + c.miles.toLocaleString() + " Miles</p></div>";
  h += hl("1.2", gallery("d"), true, "mgal");
  h += '<div class="d-sum"><div><small>Begins</small><b>2026-11-05<br>14:00 PST</b></div><div><small>Starting bid</small><b class="sp">' + c.price + "</b></div></div>";
  return h + "</div>" + mFooter();
}
function mDetailsLower() {
  var h = mHeader() + '<div class="scroller d-page m-low">';
  h += hl("1.2", secTires(), true);
  return h + "</div>" + mFooter();
}
function mDetailsCR() {
  return mHeader() + '<div class="scroller d-page m-low">' + hl("1.2", secCR()) + "</div>" + mFooter();
}
function mConfirm() {
  NOHL = true; var bg = mDetails(); NOHL = false;
  return '<div class="ovl-wrap">' + bg + '<div class="ovl"></div>' + hl("1.3", confirmSheet(false), false, "shpos") + "</div>";
}
function wConfirm() {
  NOHL = true; var bg = wDetails(); NOHL = false;
  return '<div class="ovl-wrap web">' + bg + '<div class="ovl"></div>' + hl("1.3", confirmSheet(true), false, "mdpos") + "</div>";
}

// ---------- page ----------
function frameM(id, title, body) { return '<figure class="scrn" id="' + id + '"><div class="zm">' + phoneShell(body, "dealer") + '</div><figcaption>' + title + "</figcaption></figure>"; }
function frameW(id, title, body, cls) { return '<figure class="scrn w ' + (cls || "") + '" id="' + id + '"><div class="wz"><div class="wscr">' + body + '</div></div><figcaption>' + title + "</figcaption></figure>"; }
var V1 = document.getElementById("v1");
V1.innerHTML = '<header class="pg-h"><span class="lg">' + LOGO + "<span>Inspected cars · V1 dealer and admin screens</span></span></header>" +
  '<div class="legend"><span><i class="k1"></i>New</span><span><i class="k2"></i>Changed</span><span>Numbers match the ticket\'s UI items</span><span class="lg-cr">' + crMark() + "Bidbus CR mark</span></div>" +
  '<section id="ui-1-1"><h2><em>1.1</em>Run list · CR mark next to the car name</h2><div class="row">' + frameW("w-runlist", "Web · Run list", wRunList(), "rl") + frameM("m-runlist", "Mobile app · Run list", mRunList()) + "</div></section>" +
  '<section id="ui-1-2"><h2><em>1.2</em>Vehicle details · Bidbus CR with its highlight and damage photos, photo groups</h2><div class="row">' + frameW("w-details", "Web · Vehicle details", wDetails(), "vd") +
  '<div class="col">' + frameM("m-details", "Mobile app · Vehicle details, top", mDetails()) + frameM("m-details-low", "Mobile app · Tire Condition", mDetailsLower()) + frameM("m-details-cr", "Mobile app · Bidbus CR, further down", mDetailsCR()) + "</div></div></section>" +
  '<section id="ui-1-3"><h2><em>1.3</em>Bid or Auto Bid on an inspected car · agree first</h2><div class="row">' + frameW("w-confirm", "Web · Agree before Auto Bid", wConfirm(), "cf") + frameM("m-confirm", "Mobile app · Agree before Auto Bid", mConfirm()) + "</div></section>" +
  '<section id="ui-1-4"><h2><em>1.4</em>Admin · vehicle Inspection tab</h2><div class="row"><figure class="scrn w img" id="a-inspection"><img src="img/a1.jpg" alt="Admin vehicle Inspection tab with Open report"><figcaption>Admin · Vehicle · Inspection tab · V1 hides the light and grade</figcaption></figure></div></section>';
