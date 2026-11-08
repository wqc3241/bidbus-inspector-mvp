// ---------- the inspection question list (same source as the inspector app) ----------
var ITEMS = QL.items;
LU.volume = '<path d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"/><path d="M16 9a5 5 0 0 1 0 6"/><path d="M19.364 18.364a9 9 0 0 0 0-12.728"/>';
var SECS = [["Exterior", "car", "side"], ["Paint", "brush", "detail"], ["Tires", "tire", "wheel"], ["Underbody", "layers", "under"],
  ["Mechanicals", "wrench", "engine"], ["Interior", "seat", "interior"], ["OBDII", "scan", "screen"], ["Additionals", "key", "key"], ["Damages", "alert", "detail"]];
var SEC_IC = {}; SECS.forEach(function (s) { SEC_IC[s[0]] = s[1]; });
var LEVEL = { "Ends the visit": "stop", "Not listed until fixed": "stop", "Red": "sev", "Yellow": "yel", "Disclosed": "note", "Not checked": "skip", "Normal": "ok" };
var LV_TXT = { stop: "Not listed", sev: "Red", yel: "Yellow", note: "Disclosed", skip: "Not checked" };
var LIGHT_C = { green: "Green", yellow: "Yellow", red: "Red", stop: "Not listed" };
var LIGHT_D = { green: "Starts and drives, no major faults", yellow: "A named system has a known issue", red: "Structure, title or major changes", stop: "Fix before listing" };
var TIRES = [["lf", "Left front"], ["rf", "Right front"], ["rr", "Right rear"], ["lr", "Left rear"]];

// ---------- two example inspections, fictional cars ----------
var EX = {
  ice: {
    car: { name: "2018 Toyota RAV4", trim: "XLE AWD", year: 2018, vin: "2T3EXAMPLE0000000", miles: 68410, fuel: "Gas or diesel", date: "2026-11-03", keys: 1,
      price: "$18,500",
      make: "Toyota", model: "RAV4", body: "SUV", ext: "Silver", int: "Black cloth", engine: ["Engine", "2.5L 4-cylinder"], trans: "6-speed automatic", drive: "AWD" },
    times: { arrived: "10:02", left: "10:21" },
    tread: { lf: 6, rf: 6, rr: 2, lr: 3 },
    tires: { brand: { lf: "Michelin", rf: "Michelin", rr: "Michelin", lr: "Michelin" },
             size: { lf: "235/65 R17", rf: "235/65 R17", rr: "235/65 R17", lr: "235/65 R17" }, dot: { lf: "2422", rf: "2422", rr: "1820", lr: "1820" } },
    checks: {
      ck_glass: [["Windshield chip under 1 in", ""]],
      ck_paint: [["Panel repainted (the meter reads high)", "Right rear door"]],
      ck_tire: [["Uneven wear", "", ["rr", "lr"]]],
      ck_leaks: [["Seep", "Engine"]],
      ck_lights_dash: [["Check engine", ""]],
      ck_scan: [["Engine codes stored (type the codes)", "P0420"]],
      ck_keys: [["Only one key", ""]],
    },
    damages: [{ z: "Exterior", p: "Front bumper", t: "Chip", v: "Minor", s: "1" }, { z: "Exterior", p: "Left front door", t: "Scratch", v: "Moderate", s: "4" }, { z: "Exterior", p: "Right rear door", t: "Dent", v: "Minor", s: "1" }, { z: "Tires", p: "Left front wheel", t: "Curb rash", v: "Minor", s: "2" }],
    seller: "A. Seller", overall: "Just okay", sunroof: "Works", navigation: "Works",
    note: "Clean, straight car. Rear tires need replacing. Right rear door repainted, good quality. Light seep at the valve cover.",
  },
  ev: {
    car: { name: "2022 Tesla Model Y", trim: "Long Range AWD", year: 2022, vin: "7SAEXAMPLE0000000", miles: 41250, fuel: "Electric (EV)", date: "2026-11-03", keys: 2, soh: 91,
      price: "$26,000",
      make: "Tesla", model: "Model Y", body: "SUV", ext: "White", int: "Black", engine: ["Motor", "Dual motor"], trans: "Single-speed", drive: "AWD" },
    times: { arrived: "14:05", left: "14:22" },
    tread: { lf: 6, rf: 6, rr: 2, lr: 2 },
    tires: { brand: { lf: "Michelin", rf: "Michelin", rr: "Continental", lr: "Continental" },
             size: { lf: "255/45 R19", rf: "255/45 R19", rr: "255/45 R19", lr: "255/45 R19" }, dot: { lf: "3123", rf: "3123", rr: "0821", lr: "0821" } },
    checks: {
      ck_tire: [["Uneven wear", "", ["rr", "lr"]]],
      ck_pack: [["Scraped", ""]],
      ck_account: [["Car not yet removed from the seller's app account", ""]],
    },
    damages: [{ z: "Exterior", p: "Front bumper", t: "Scratch", v: "Minor", s: "2" }, { z: "Exterior", p: "Rear bumper", t: "Scuff", v: "Moderate", s: "3" }, { z: "Exterior", p: "Right rear door", t: "Dent", v: "Minor", s: "1" }],
    seller: "B. Seller", overall: "Pretty great", sunroof: "No sunroof", navigation: "Works",
    note: "Clean car, battery health 91%. Rear tires need replacing; check the alignment. Light scrape on the battery shield.",
  },
};
var UI = { tab: "all", v: "ice", sPage: "report" };
function X() { return EX[UI.v]; }
function carOk(it) { return it.cars === "all" || (UI.v === "ice" && it.cars === "gas") || (UI.v === "ev" && it.cars === "ev"); }
function inSec(sec, kind) { return ITEMS.filter(function (it) { return it.section === sec && carOk(it) && (!kind || it.kind === kind); }); }
function byId(id) { return ITEMS.filter(function (it) { return it.id === id; })[0]; }
function optText(o) { return o.replace(/ \((type the codes|the meter reads high)\)$/, "").replace(/^EV: /, ""); }
function wheelsText(w) { return (w || []).map(function (k) { return TIRES.filter(function (t) { return t[0] === k; })[0][1]; }).join(", "); }
function tclass(m) { return m === null || m === undefined ? "na" : m <= 4 ? "bad" : m <= 8 ? "fair" : "good"; }
function tword(m) { return m === null || m === undefined ? "—" : m <= 4 ? "Replace" : m <= 8 ? "Fair" : "Good"; }
var PANELS = ["Hood", "Roof", "Left front fender", "Left front door", "Left rear door", "Left quarter panel", "Trunk or liftgate",
  "Right quarter panel", "Right rear door", "Right front door", "Right front fender"];
function multiN(it) { return { ph_paint_base: PANELS.length, ph_ev_battery: 2, ph_ev_charging: 1, ph_ev_alerts: 2, ph_under_cats: 2 }[it.id] || 1; }

// every problem the inspection reported, with its report level
function problems() {
  var out = [];
  ITEMS.forEach(function (it) {
    if (it.kind !== "check" || !carOk(it)) return;
    (X().checks[it.id] || []).forEach(function (a) {
      var lv = LEVEL[it.levels[a[0]]] || "note";
      var txt = (it.id === "ck_tire" ? "Tire" : it.id === "ck_wheel" ? "Wheel" : it.label) + ": " + a[0].replace(/\s*\(type[^)]*\)/g, "");
      (a[2] && a[2].length ? a[2] : [null]).forEach(function (w) {
        out.push({ sec: it.section, id: it.id, check: it.label.replace(/, each (tire|wheel)$/, ""), opt: optText(a[0]), note: a[1], wheels: w ? [w] : a[2], lv: lv, text: txt, sub: w ? wheelsText([w]) : a[1] });
      });
    });
  });
  X().damages.forEach(function (d) { out.push({ sec: "Damages", id: "damage", check: d.p, opt: d.t, note: [d.v, d.s ? d.s + " in" : ""].filter(Boolean).join(", "), lv: "note" }); });
  return out;
}
function lightOf(P) {
  var has = function (k) { return P.some(function (f) { return f.lv === k; }); };
  return has("stop") ? "stop" : has("sev") ? "red" : has("yel") ? "yellow" : "green";
}
function fText(f) { return f.text ? f.text + (f.sub ? " · " + f.sub : "") : f.check + ": " + f.opt; }
function fTextOld(f) { return f.check + ": " + f.opt + (f.wheels && f.wheels.length ? " (" + wheelsText(f.wheels) + ")" : "") + (f.note ? ". " + f.note : ""); }
// Purchase Protection for dealers: shown on the dealer report only
function protection(light) {
  var c = X().car, y = c.year, mi = c.miles;
  if (light === "stop") return null;
  if (light === "red") return { limited: true, label: "Title, odometer, legal" };
  if (y < 2011 || mi >= 150000) return null;
  return { label: "Purchase Protection" };
}

// ---------- shared pieces ----------
function areaIcons(P, cls) {
  return '<div class="xareas ' + (cls || "") + '">' + SECS.map(function (s) {
    var l = P.filter(function (f) { return f.sec === s[0] && f.lv !== "skip"; });
    var has = function (k) { return l.some(function (f) { return f.lv === k; }); };
    var st = !l.length ? "ok" : has("stop") ? "stop" : has("sev") ? "sev" : has("yel") ? "yel" : "note";
    return '<div class="ar ' + st + '"><span class="ari">' + I(s[1], 26) + "<em>" + (st === "ok" ? "✓" : l.length) + "</em></span><span>" + esc(s[0] === "OBDII" ? "OBD-II" : s[0]) + "</span></div>";
  }).join("") + "</div>";
}
// Highlight (Tom 11-07 07:43): structural damage yes or no, number of keys (read from the keys photo, confirmed by the inspector), odor, mechanical issue or not
function highlights(P, cls) {
  var c = X().car;
  var st = P.filter(function (f) { return f.id === "ck_structure"; }), stDmg = st.filter(function (f) { return !/could not be photographed/.test(f.opt); });
  var od = P.filter(function (f) { return f.id === "ck_odor"; }), me = P.filter(function (f) { return f.sec === "Mechanicals" && f.lv !== "skip"; });
  // damage photos count too: a Structure damage is structural damage, a damage recorded in Mechanicals is a mechanical issue
  stDmg = stDmg.concat(X().damages.filter(function (d) { return d.t === "Structure"; })); me = me.concat(X().damages.filter(function (d) { return d.z === "Mechanicals"; }));
  var T = [["car", stDmg.length ? "bad" : st.length ? "na" : "ok", "Structural damage", stDmg.length ? "Yes" : st.length ? "Not checked" : "No"],
    ["key", c.keys ? "num" : "bad", "Keys", String(c.keys)],
    ["wind", od.length ? "bad" : "ok", "Odor", od.length ? od.map(function (f) { return f.opt; }).join(", ") : "OK"],
    ["wrench", me.length ? "bad" : "ok", "Mechanical", me.length ? "Issue" : "No issue"]];
  return '<div class="hls ' + (cls || "") + '">' + T.map(function (t) {
    var b = t[1] === "ok" ? "✓" : t[1] === "na" ? "–" : t[0] === "key" ? t[3] : "×";
    return '<div class="hl2 ' + t[1] + (t[0] === "key" ? " k" : "") + '"><span class="hli">' + I(t[0], 30) + "<em>" + b + '</em></span><span class="hll">' + esc(t[2]) + "</span><b>" + esc(t[3]) + "</b></div>";
  }).join("") + "</div>";
}
// every damage the inspector recorded, with its photo, in the section it was recorded in (Tom 11-07 07:43: no separate Damages section)
function dmgLine(d) { return d.p + ": " + d.t + ", " + d.v + (d.s ? ", " + d.s + " in" : ""); }
function dmgIn(sec) { return X().damages.filter(function (d) { return d.z === sec; }); }
function dmgDd(l) { return l.map(function (d) { return '<dd class="dmg"><div class="dth">' + art("detail") + '</div><div class="dtxt">' + esc(dmgLine(d)) + "</div></dd>"; }).join(""); }
function issueDd(f, tags) { return '<dd class="neg"><span>×</span><div class="dtxt">' + esc(f.text) + (tags && LV_TXT[f.lv] && f.lv !== "note" ? ' <em class="lvt ' + f.lv + '">' + LV_TXT[f.lv] + "</em>" : "") + (f.sub ? "<small>" + esc(f.sub) + "</small>" : "") + "</div></dd>"; }
function findingRows(P) {
  return P.filter(function (f) { return f.sec !== "Damages" && f.lv !== "skip"; }).map(function (f) {
    return '<div class="fnd ' + f.lv + '">' + I(SEC_IC[f.sec] || "alert", 18) + "<span>" + esc(fText(f)) + "</span></div>";
  }).join("");
}
function mapView() {
  var s = '<svg class="cmap" viewBox="0 -6 200 430" role="img" aria-label="Damage map">' + CAR_OUTLINE;
  X().damages.forEach(function (d, i) {
    var xy = POS2[d.p]; if (!xy) return;
    s += '<g><circle cx="' + xy[0] + '" cy="' + xy[1] + '" r="11" class="xmk"/><text x="' + xy[0] + '" y="' + (xy[1] + 4) + '" text-anchor="middle" class="mt">' + (i + 1) + "</text></g>";
  });
  return s + "</svg>";
}
function dmgRows() {
  return X().damages.map(function (d, i) {
    return '<div class="dr"><span class="xnum">' + (i + 1) + '</span><span class="dth">' + art("detail") + '</span><span class="dtx"><b>' + esc(d.p) + "</b><small>" + esc(d.t) + (d.s ? " · " + d.s + " in" : "") + "</small></span>" +
      "</div>";
  }).join("");
}
// ---------- photo and video viewer: photos and videos in one list, grouped by inspection section ----------
// videos sit in the section they show; the seller's ID photos are private and never shown
var VID = { video_360: ["Exterior", "top", "Walk-around, 360°", "2:10"], video_engine: ["Mechanicals", "engine", "Engine sound at the first start", "0:45"],
  video_exhaust: ["Mechanicals", "rear", "Exhaust at idle and revving", "0:40"] };
var PH_ART = { ph_int_screen: "screen", ph_ext_front: "front", ph_ext_rear: "rear", ph_ext_roof: "top", ph_vin_door: "doc", ph_vin_dash: "doc", ph_odo: "screen", ph_emission_label: "doc", ph_int_dash: "screen" };
var PH_SHORT = { ph_paint_base: "Paint meter", ph_int_screen: "Infotainment screen", ph_obd_current: "OBD-II current codes", ph_obd_past: "OBD-II past codes", ph_obd_emission: "OBD-II emission codes", ph_obd_other: "OBD-II other",
  ph_under_lf: "Underbody, left front", ph_under_lr: "Underbody, left rear", ph_under_rear: "Underbody, rear", ph_under_rr: "Underbody, right rear", ph_under_rf: "Underbody, right front", ph_under_front: "Underbody, front", ph_under_cats: "Catalytic converter", ph_under_pack: "Battery pack",
  ph_mod_ext: "Exterior modification", ph_mod_int: "Interior modification", ph_mod_mech: "Mechanicals modification", ph_odo: "Odometer and warning lights",
  ph_keys: "Keys", tire_photo: "Tire sidewall", wheel_photo: "Whole tire and wheel", tread_photo: "Tread gauge", dot_photo: "DOT date", ph_ev_battery: "Battery health", ph_ev_charging: "Charging rate", ph_ev_alerts: "Service-mode alerts", ph_engine_oil: "Engine oil" };
function media() {
  var x = X(), out = [];
  SECS.forEach(function (s) {
    var g = s[0];
    Object.keys(VID).forEach(function (id) { var it = byId(id); if (it && carOk(it) && VID[id][0] === g) out.push({ g: g, art: VID[id][1], lbl: VID[id][2], v: VID[id][3] }); });
    var wh = [];  // tire photos: tire by tire, in the order taken
    inSec(g, "photo").forEach(function (it) {
      if (it.id === "damage.photo") { x.damages.forEach(function (d, i) { out.push({ g: d.z || g, art: "detail", lbl: dmgLine(d) }); }); return; }
      var lbl = PH_SHORT[it.id] || it.label.replace(/,? each wheel \(4\)/, "").replace(/ \(.*\)$/, "").replace(/, with .*$/, "");
      if (/each wheel \(4\)/.test(it.label)) { wh.push(lbl); return; }
      if (it.id === "ph_paint_base") { PANELS.forEach(function (pn) { out.push({ g: g, art: "detail", lbl: lbl + " · " + pn }); }); return; }
      var n = multiN(it);
      for (var k = 0; k < n; k++) out.push({ g: g, art: PH_ART[it.id] || s[2], flip: /right/.test(it.id), lbl: lbl + (n > 1 ? " " + (k + 1) + "/" + n : "") });
    });
    TIRES.forEach(function (t) { wh.forEach(function (l) { out.push({ g: g, art: s[2], lbl: l + " · " + t[1] }); }); });
    inSec(g, "check").forEach(function (it) {
      (x.checks[it.id] || []).forEach(function (a) { out.push({ g: g, art: "detail", lbl: (it.id === "ck_tire" ? "Tire" : it.id === "ck_wheel" ? "Wheel" : it.label) + ": " + a[0].replace(/\s*\(type[^)]*\)/g, "") + (a[2] ? " · " + wheelsText(a[2]) : "") }); });
    });
  });
  return out;
}
function galState(app) { UI.gal = UI.gal || {}; return UI.gal[app] || (UI.gal[app] = { g: "all", i: 0 }); }
function galList(app) { var M = media(), st = galState(app); return st.g === "all" ? M : M.filter(function (m) { return m.g === st.g; }); }
function gallery(app) {
  var M = media(), st = galState(app);
  var groups = SECS.map(function (s) { return s[0]; }).filter(function (g) { return M.some(function (m) { return m.g === g; }); });
  if (st.g !== "all" && groups.indexOf(st.g) < 0) st.g = "all";
  var L = galList(app);
  if (st.i >= L.length) st.i = 0;
  var cur = L[st.i], at = ' data-app="' + app + '"';
  var h = '<div class="gal ' + app + '" data-gal="' + app + '"><div class="' + app + '-hero g-hero' + (cur.v ? " vd" : "") + '">' + art(cur.art, cur.flip ? "flip" : "") +
    (cur.v ? '<span class="g-play">' + I("play", 24) + "</span>" : "") +
    '<button type="button" class="g-nav prev" data-act="g-step"' + at + ' data-v="-1" aria-label="Previous">' + I("left", 18) + "</button>" +
    '<button type="button" class="g-nav next" data-act="g-step"' + at + ' data-v="1" aria-label="Next">' + I("right", 18) + "</button>" +
    '<span class="g-cap">' + I(cur.v ? "video" : SEC_IC[cur.g], 12) + "<span>" + esc(cur.lbl + (cur.v ? " · " + cur.v : "")) + "</span></span>" +
    '<span class="pc">' + (st.i + 1) + " / " + L.length + "</span></div>";
  h += '<div class="pstrip g-strip ' + app + '">' + L.map(function (m, i) {
    return '<button type="button" class="pt' + (m.v ? " vd" : "") + (i === st.i ? " on" : "") + '" data-act="g-pick"' + at + ' data-v="' + i + '" aria-label="' + esc(m.lbl) + '"' + (i === st.i ? ' aria-current="true"' : "") + ">" +
      art(m.art, m.flip ? "flip" : "") + (m.v ? "<i>" + I("play", 9) + m.v + "</i>" : "") + "</button>";
  }).join("") + "</div>";
  h += '<div class="g-grps ' + app + '" role="group" aria-label="Photo and video groups">' + [["all", "grid", "All", M.length]].concat(groups.map(function (g) {
    return [g, SEC_IC[g], g === "OBDII" ? "OBD-II" : g, M.filter(function (m) { return m.g === g; }).length];
  })).map(function (c) {
    return '<button type="button" data-act="g-grp"' + at + ' data-v="' + c[0] + '" aria-pressed="' + (st.g === c[0]) + '">' + I(c[1], 14) + esc(c[2]) + "<em>" + c[3] + "</em></button>";
  }).join("") + "</div>";
  return h + "</div>";
}
function redrawGal(app, focusSel) {
  var el = appsRoot.querySelector('[data-gal="' + app + '"]'); if (!el) return;
  var gx = el.querySelector(".g-grps").scrollLeft, tmp = document.createElement("div");
  tmp.innerHTML = gallery(app);
  var n = tmp.firstChild; el.parentNode.replaceChild(n, el);
  n.querySelector(".g-grps").scrollLeft = gx;
  var sp = n.querySelector(".g-strip"), on = sp.querySelector(".on");
  if (on) sp.scrollLeft = Math.max(0, on.offsetLeft - (sp.clientWidth - on.offsetWidth) / 2);
  var f = focusSel && n.querySelector(focusSel); if (f) f.focus({ preventScroll: true });
  edges(n.querySelector(".g-grps")); edges(sp);
}
function tireOf(k, id) { return (X().checks[id] || []).filter(function (a) { return (a[2] || []).indexOf(k) >= 0; }).map(function (a) { return optText(a[0]); }); }
function tireCells() {
  return '<div class="tcells">' + TIRES.map(function (t) {
    var m = X().tread[t[0]], bad = tireOf(t[0], "ck_tire").length + tireOf(t[0], "ck_wheel").length;
    return '<div class="tc ' + tclass(m) + '"><small>' + esc(t[1]) + "</small><b>" + m + '/32</b><span class="bar"><i style="width:' + Math.min(100, m / 10 * 100) + '%"></i></span>' + (bad ? "<em>" + I("alert", 12) + "</em>" : "") + "</div>";
  }).join("") + "</div>";
}
function phoneShell(body, cls) {
  return '<div class="dev ' + (cls || "") + '"><div class="cam" aria-hidden="true"></div><div class="scr"><div class="sbar"><span>9:41</span><span class="sb-r"><i></i><i></i><i></i><em></em></span></div>' + body + '<div class="home"></div></div></div>';
}

// ---------- inspection answers, as the inspector submitted them ----------
function okRow(label) { return '<div class="fr ok1"><div class="fl">' + esc(label) + '</div><span class="okp">' + I("check", 14) + "OK</span></div>"; }
function probRow(it, list) {
  return '<div class="fr pb"><div class="fl">' + esc(it.label) + '</div><div class="pbl">' + list.map(function (a) {
    var lv = LEVEL[it.levels[a[0]]] || "note";
    return '<div class="pbi ' + lv + '">' + I("alert", 14) + "<span><b>" + esc(optText(a[0])) + "</b>" + (a[2] || a[1] ? "<small>" + esc([wheelsText(a[2]), a[1]].filter(Boolean).join(" · ")) + "</small>" : "") + "</span>" + I("camera", 14, "pcam") + "</div>";
  }).join("") + "</div></div>";
}
function photoGrid(sec) {
  var ph = inSec(sec, "photo"); if (!ph.length) return "";
  return '<div class="phg">' + ph.map(function (it) {
    var n4 = /each wheel \(4\)/.test(it.label), lbl = it.id === "ph_paint_base" ? "Paint meter, by panel" : it.id === "damage.photo" ? "Damage close-ups" : it.label.replace(/,? each wheel \(4\)/, "").replace(/ \(only when.*\)$/, "").replace(/, with the panel named/, "").replace(/ readings, one photo per panel measured.*$/, ", by panel").replace(/, every screen or page$/, "");
    var c = n4 ? 4 : it.id === "damage.photo" ? X().damages.length : multiN(it);
    return '<span class="phc">' + art((SECS.filter(function (s) { return s[0] === sec; })[0] || [0, 0, "detail"])[2]) + '<i>' + I("check", 11) + (c > 1 ? c : "") + "</i><small>" + esc(lbl) + "</small></span>";
  }).join("") + "</div>";
}
function entryRow(label, val) { return '<div class="fr inl"><div class="fl">' + esc(label) + "</div><b class=\"ev2\">" + esc(val) + "</b></div>"; }
function inspHTML() {
  var x = X(), c = x.car;
  var h = '<header class="fh"><span class="tb-btn"></span><div class="fh-t">' + I("clip", 18) + "Inspection</div>" + '<span class="tb-btn"></span></header><div class="scroller f-body" data-scroll="insp"><div class="f-pad">';
  h += '<div class="fcard"><div class="gh">' + I("pin", 13) + "Start</div>" +
    entryRow("Fuel", c.fuel) + entryRow("License and registration uploaded by the seller", "Yes") + entryRow("Seller's license matches a registered owner", "Yes") +
    '<div class="fr inl"><div class="fl">' + I("clock", 14) + "Arrived · " + I("pin", 14) + 'GPS</div><b class="ev2">' + esc(fmtDate(c.date)) + " " + esc(x.times.arrived) + "</b></div></div>";
  SECS.forEach(function (s) {
    var sec = s[0], checks = inSec(sec, "check"), entries = inSec(sec, "entry").concat(inSec(sec, "choice"));
    h += '<div class="fcard"><div class="gh">' + I(s[1], 13) + esc(sec) + "</div>" + photoGrid(sec);
    entries.forEach(function (it) {
      if (it.id === "tread") h += '<div class="fr"><div class="fl">Tread (/32 in)</div><span class="trd">' + TIRES.map(function (t) { return '<b class="' + tclass(x.tread[t[0]]) + '"><small>' + esc(t[1]) + "</small>" + x.tread[t[0]] + "</b>"; }).join("") + "</span></div>";
      else if (it.id === "ev_soh") h += entryRow("Battery health", c.soh + "%");
      else if (it.id === "vin_scan") h += entryRow("VIN, scanned", c.vin);
      else if (it.id === "tire_brand") h += TIRES.map(function (t) { var T = x.tires || {}; return '<div class="fr"><div class="fl">' + esc(t[1]) + '</div><b class="ev2">' + esc([(T.brand || {})[t[0]], (T.size || {})[t[0]]].filter(Boolean).join(" · ") || "—") + "</b></div>"; }).join("");
      else if (it.id === "tire_size") return;  // shown with the brand, one row per tire
      else if (it.id === "tires_match") h += entryRow("The 4 tires match (brand, model, size)", x.tiresMatch || "Match");
      else if (it.id === "sunroof") h += entryRow("Sunroof", x.sunroof || "Works");
      else if (it.id === "navigation") h += entryRow("Navigation", x.navigation || "Works");
    });
    if (sec === "Damages") h += x.damages.map(function (d, i) { return '<div class="fr inl"><div class="fl"><span class="xnum">' + (i + 1) + "</span>" + esc(d.p) + '</div><b class="ev2">' + esc(d.t) + (d.v ? " · " + d.v : "") + (d.s ? " · " + d.s + " in" : "") + "</b></div>"; }).join("");
    checks.forEach(function (it) { var a = x.checks[it.id]; h += a && a.length ? probRow(it, a) : okRow(it.label); });
    h += "</div>";
  });
  var vids = inSec("Videos", "video");
  h += '<div class="fcard"><div class="gh">' + I("video", 13) + 'Videos</div><div class="phg">' + vids.map(function (it) { return '<span class="phc vd">' + art(it.id === "video_360" ? "top" : it.id === "video_engine" ? "engine" : "video") + "<i>" + I("check", 11) + "</i><small>" + esc(it.label.replace(/ \(up to.*\)$/, "").replace(/:.*$/, "").replace(/, with sound$/, "")) + "</small></span>"; }).join("") + "</div></div>";
  h += '<div class="fcard sig"><div class="gh">' + I("pen", 13) + "Seller signature</div>" +
    '<p class="sigt">I have seen the inspection findings for this car.</p><div class="sigbox"><span>' + esc(x.seller) + '</span></div><div class="sigb"><span>' + esc(x.seller) + " · " + esc(fmtDate(c.date)) + " " + esc(x.times.left) + "</span><span>" + I("pin", 13) + "GPS</span></div>" +
    '<div class="nt2"><small>Overall condition</small>' + esc(x.overall) + "</div>" +
    (x.note ? '<div class="nt2"><small>Inspector\'s note for dealers</small>' + esc(x.note) + "</div>" : "") + "</div>";
  return h + "</div></div>";
}

// ---------- seller app ----------
function sellerHTML() {
  var x = X(), c = x.car, P = problems(), lt = lightOf(P);
  var h = '<header class="sh2"><span class="s-logo">bidbus</span><span class="s-r"><span>EN</span><span class="s-menu">Menu</span></span></header>';
  h += '<div class="scroller s-page" data-scroll="seller-report"><span class="s-crumb">Dashboard <b>› Condition report</b></span>';
  h += '<div class="s-card pad"><div class="s-car">' + esc(c.name + " " + c.trim) + '</div><div class="s-meta">' + I("gauge", 14) + c.miles.toLocaleString() + " mi  " + I("calendar", 14) + esc(fmtDate(c.date)) + "</div>" +
    '<div class="s-score"><div class="lt big ' + lt + '"><i></i>' + LIGHT_C[lt] + "</div></div></div>";
  h += '<div class="s-card">' + gallery("s") + "</div>";
  h += '<div class="s-card pad">' + highlights(P, "s") + "</div>";
  h += '<div class="s-card pad"><div class="s-ch">' + I("tire", 18) + "</div>" + tireCells() + "</div>";
  h += '<div class="s-card pad"><div class="s-ch">' + I("clip", 18) + "<b>Bidbus Inspection</b></div><dl class=\"insp s\">" + SECS.filter(function (s) { return s[0] !== "Damages"; }).map(function (s) {
    var l = P.filter(function (f) { return f.sec === s[0] && f.lv !== "skip"; }), dl = dmgIn(s[0]);
    return '<div class="ir"><dt>' + I(s[1], 16) + esc(s[0] === "OBDII" ? "OBD-II" : s[0]) + "</dt>" + (l.length || dl.length ? l.map(function (f) { return issueDd(f, false); }).join("") + dmgDd(dl) : '<dd class="pos"><span>✓</span>No issues</dd>') + "</div>";
  }).join("") + "</dl></div>";
  h += '<div class="s-card pad why"><div class="s-row">' + I("dollar", 20, "c-green") + "<div><b>More accurate price</b></div></div>" +
    '<div class="s-row">' + I("clock", 20, "c-green") + "<div><b>Same-day payment</b></div></div>" +
    '<div class="s-row">' + I("swap", 20, "c-green") + "<div><b>Less back-and-forth with dealers</b></div></div></div>";
  return h + '<div class="s-foot">' + LOGO + "</div></div>";
}

// ---------- dealer app ----------
function dealerHTML() {
  var x = X(), c = x.car, P = problems(), lt = lightOf(P), pr = protection(lt);
  var h = '<header class="dh"><span class="tb-btn">' + I("left", 22) + '</span><b class="dh-t">Vehicle details</b><span class="call">Call</span><span class="dmenu">' + I("menu", 22) + "</span></header>";
  h += '<div class="scroller d-page" data-scroll="dealer">';
  h += '<div class="d-head"><div class="eyebrow">Upcoming auction</div><h1>' + esc(c.name) + '</h1><p class="trim">' + esc(c.trim) + '</p><p class="ml">' + c.miles.toLocaleString() + " Miles</p></div>";
  h += gallery("d");
  h += '<div class="d-sum"><div><small>Begins</small><b>2026-11-05<br>14:00 PST</b></div><div><small>Starting bid</small><b class="sp">' + c.price + "</b></div></div>";
  h += '<nav class="d-tabs">' + [["condition", "Condition"], ["tires", "Tires"], ["inspection", "Inspection"], ["specs", "Specs"]].map(function (t, i) { return '<button type="button" class="' + (i === 0 ? "on" : "") + '" data-act="d-tab" data-v="' + t[0] + '">' + t[1] + "</button>"; }).join("") + "</nav>";
  h += '<section class="d-sec" id="d-condition"><h2>Condition</h2><div class="d-score"><div class="lt big ' + lt + '"><i></i>' + LIGHT_C[lt] + "</div><small class=\"ltd\">" + esc(LIGHT_D[lt]) + "</small>" + '<div class="ovc"><small>Overall condition</small><b>' + esc(x.overall) + "</b></div>" +
    (pr ? '<div class="bbg' + (pr.limited ? " lim" : "") + '">' + I("shield", 18) + esc(pr.label) + "</div>" : "") + "</div>";
  var ORD = { stop: 0, sev: 1, yel: 2 };
  var ann = P.filter(function (f) { return ORD[f.lv] !== undefined; }).sort(function (a, b) { return ORD[a.lv] - ORD[b.lv]; });
  if (ann.length) h += '<div class="danns">' + ann.map(function (f) { return '<div class="dann ' + f.lv + '">' + I("alert", 16) + "<span>" + esc(fText(f)) + "</span></div>"; }).join("") + "</div>";
  h += '<h3 class="d-h3">Highlight</h3>' + highlights(P, "d") + "</section>";
  h += '<section class="d-sec" id="d-tires"><h2>Tire Condition</h2><div class="tires2">' + TIRES.map(function (t) {
    var m = x.tread[t[0]], more = tireOf(t[0], "ck_tire").concat(tireOf(t[0], "ck_wheel"), tireOf(t[0], "ck_brakes"));
    return '<div class="tire2"><h3>' + esc(t[1]) + '</h3><div class="ts ' + tclass(m) + '">' + tword(m) + "</div><p>Tread: " + m + '/32"' + (x.tires ? "<br>" + esc(x.tires.brand[t[0]] + " · " + x.tires.size[t[0]]) : "") + "<br>" + I("camera", 12) + " Tire sidewall" + (more.length ? "<br>" + esc(more.join(", ")) : "") + "</p></div>";
  }).join("") + "</div></section>";
  // Engine sound is its own row after Mechanicals (Tom 11-05), on gas, hybrid and plug-in hybrid cars: the engine sound and
  // exhaust videos to play, and the result of the Engine check (which leaves the Mechanicals row)
  var ENG = byId("ck_engine"), engRow = !!(ENG && carOk(ENG)), ENG_V = ["video_engine", "video_exhaust"];
  var irRows = function (l, n0, dl) {
    dl = dl || [];
    return l.length || dl.length ? l.map(function (f) { return f.lv === "skip" ? '<dd class="neu"><span>–</span><div class="dtxt">' + esc(f.text) + "</div></dd>" : issueDd(f, true); }).join("") + dmgDd(dl)
      : '<dd class="pos"><span>✓</span>No issues' + (n0 ? " · " + n0 + (n0 > 1 ? " checks" : " check") : "") + "</dd>";
  };
  var vidName = function (it) { return it.label.replace(/ \(up to.*\)$/, "").replace(/:.*$/, "").replace(/, with sound$/, ""); };
  h += '<section class="d-sec" id="d-inspection"><h2>Bidbus Inspection</h2><dl class="insp">' + SECS.filter(function (s) { return s[0] !== "Damages"; }).map(function (s) {
    var l = P.filter(function (f) { return f.sec === s[0] && f.id !== "ck_engine"; });
    var n0 = inSec(s[0], "check").filter(function (it) { return it.id !== "ck_engine"; }).length;
    var row = '<div class="ir"><dt>' + I(s[1], 16) + esc(s[0] === "OBDII" ? "OBD-II" : s[0]) + "</dt>" + irRows(l, n0, dmgIn(s[0])) + "</div>";
    if (s[0] === "Mechanicals" && engRow) {
      row += '<div class="ir"><dt>' + I("volume", 16) + "Engine sound</dt>" + inSec("Videos", "video").filter(function (it) { return ENG_V.indexOf(it.id) >= 0; }).map(function (it) {
        return '<dd class="vid"><span>' + I("play", 12) + "</span>" + esc(vidName(it)) + "</dd>";
      }).join("") + irRows(P.filter(function (f) { return f.id === "ck_engine"; }), 1) + "</div>";
    }
    return row;
  }).join("") + '<div class="ir"><dt>' + I("video", 16) + "Videos</dt>" + inSec("Videos", "video").filter(function (it) { return !engRow || ENG_V.indexOf(it.id) < 0; }).map(function (it) { return '<dd class="pos"><span>' + I("play", 12) + "</span>" + esc(vidName(it)) + "</dd>"; }).join("") + "</div>" +
    (x.note ? '<div class="ir"><dt>' + I("clip", 16) + "Inspector's note</dt><dd class=\"neu\"><span>–</span><div class=\"dtxt\">" + esc(x.note) + "</div></dd></div>" : "") + "</dl></section>";
  var fuelW = { "Gas or diesel": "Gas", "Hybrid": "Hybrid", "Plug-in hybrid": "Plug-in hybrid", "Electric (EV)": "Electric" }[c.fuel] || c.fuel;
  var spec = [["VIN", c.vin], ["Year", c.year], ["Make", c.make], ["Model", c.model], ["Trim", c.trim], ["Body style", c.body], ["Odometer", c.miles.toLocaleString() + " mi"],
    ["Exterior color", c.ext], ["Interior", c.int], [c.engine[0], c.engine[1]], ["Transmission", c.trans], ["Drivetrain", c.drive], ["Fuel", fuelW], ["Keys", c.keys]];
  if (c.soh) spec.push(["Battery health", c.soh + "%"]);
  h += '<section class="d-sec" id="d-specs"><h2>Vehicle Details</h2><dl class="spec2">' + spec.map(function (r) { return "<div><dt>" + esc(r[0]) + "</dt><dd>" + esc(String(r[1])) + "</dd></div>"; }).join("") + "</dl></section>";
  h += "</div>";
  h += '<footer class="df"><div class="ps"><small>Starting bid</small><b>' + c.price + '</b></div><span class="abid">⚡ Auto Bid</span><span class="circ2">' + I("bookmark", 18) + "</span></footer>";
  return h;
}

// ---------- page ----------
var appsRoot;
function skeleton() {
  var tabs = [["all", "grid", "All"], ["field", "clip", "Inspection"], ["seller", "user", "Seller"], ["dealer", "store", "Dealer"]];
  var cards = [["field", "clip", "Inspection answers"], ["seller", "user", "Seller app"], ["dealer", "store", "Dealer app"]];
  return '<header class="pg-h"><span class="lg">' + LOGO + "<span>Condition report</span></span>" +
    '<div class="tabs2" role="group" aria-label="View">' + tabs.map(function (t) { return '<button type="button" data-act="tab" data-v="' + t[0] + '">' + I(t[1], 16) + t[2] + "</button>"; }).join("") + "</div>" +
    '<span class="sp"></span><div class="fuel" role="group" aria-label="Vehicle"><button type="button" data-act="ver" data-v="ice" aria-label="Gas, diesel or hybrid">' + I("fuel", 16) + '</button><button type="button" data-act="ver" data-v="ev" aria-label="Electric">' + I("plug", 16) + "</button></div></header>" +
    '<div class="devs">' + cards.map(function (c) { return '<div class="dcard" id="ap-' + c[0] + '-c"><div class="zoom" id="ap-' + c[0] + '"></div><div class="dlab">' + I(c[1], 16) + c[2] + "</div></div>"; }).join("") + "</div>";
}
function render() {
  var keep = {};
  Array.prototype.forEach.call(appsRoot.querySelectorAll("[data-scroll]"), function (s) { keep[s.getAttribute("data-scroll") + UI.v] = s.scrollTop; });
  appsRoot.querySelector("#ap-field").innerHTML = phoneShell(inspHTML(), "field");
  appsRoot.querySelector("#ap-seller").innerHTML = phoneShell(sellerHTML(), "seller");
  appsRoot.querySelector("#ap-dealer").innerHTML = phoneShell(dealerHTML(), "dealer");
  Array.prototype.forEach.call(appsRoot.querySelectorAll(".tabs2 button"), function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-v") === UI.tab)); });
  Array.prototype.forEach.call(appsRoot.querySelectorAll(".fuel button"), function (b) { b.setAttribute("aria-pressed", String(b.getAttribute("data-v") === UI.v)); });
  appsRoot.setAttribute("data-tab", UI.tab);
  if (typeof allEdges === "function") allEdges();
}
function onAct(e) {
  var b = e.target.closest("[data-act]"); if (!b) return;
  var a = b.getAttribute("data-act"), v = b.getAttribute("data-v");
  if (a === "tab") { UI.tab = v; try { localStorage.setItem("bidbus-cr-tab", v); } catch (er) {} render(); }
  else if (a === "ver") { UI.v = v; UI.gal = {}; render(); }
  else if (a === "g-grp" || a === "g-pick" || a === "g-step") {
    var ap = b.getAttribute("data-app"), st = galState(ap);
    if (a === "g-grp") { st.g = v; st.i = 0; }
    else if (a === "g-pick") st.i = +v;
    else { var n = galList(ap).length; st.i = (st.i + (+v) + n) % n; }
    redrawGal(ap, a === "g-pick" ? ".g-strip .on" : '[data-act="' + a + '"][data-v="' + v + '"]');
  }
  else if (a === "d-tab") {
    var sc = appsRoot.querySelector("#ap-dealer .d-page"), t = appsRoot.querySelector("#d-" + v);
    Array.prototype.forEach.call(appsRoot.querySelectorAll(".d-tabs button"), function (x) { x.classList.toggle("on", x === b); });
    if (sc && t) sc.scrollTo({ top: t.offsetTop - 50, behavior: "smooth" });
  }
}
appsRoot = document.getElementById("apps");
appsRoot.innerHTML = skeleton();
try { var st = localStorage.getItem("bidbus-cr-tab"); if (st) UI.tab = st; } catch (er) {}
if (window.matchMedia("(max-width: 900px)").matches && UI.tab === "all") UI.tab = "dealer";
appsRoot.addEventListener("click", onAct);
// rows that scroll sideways (photo groups, thumbnails): drag with the mouse; touch and trackpads scroll natively
var drag = null, dragged = false;
function edges(r) { r.classList.toggle("ml", r.scrollLeft > 2); r.classList.toggle("mr", r.scrollLeft < r.scrollWidth - r.clientWidth - 2); }
function allEdges() { Array.prototype.forEach.call(appsRoot.querySelectorAll(".g-grps, .g-strip"), edges); }
appsRoot.addEventListener("pointerdown", function (e) {
  var r = e.target.closest(".g-grps, .g-strip");
  if (!r || e.pointerType !== "mouse" || e.button !== 0 || r.scrollWidth <= r.clientWidth) return;
  drag = { r: r, x: e.clientX, l: r.scrollLeft, z: r.getBoundingClientRect().width / r.clientWidth || 1 }; dragged = false;
});
window.addEventListener("pointermove", function (e) {
  if (!drag) return;
  var dx = e.clientX - drag.x;
  if (!dragged && Math.abs(dx) < 5) return;
  if (!dragged) { dragged = true; drag.r.classList.add("drag"); }
  drag.r.scrollLeft = drag.l - dx / drag.z; e.preventDefault();
});
window.addEventListener("pointerup", function () { if (drag) drag.r.classList.remove("drag"); drag = null; });
appsRoot.addEventListener("click", function (e) { if (dragged) { dragged = false; e.stopPropagation(); e.preventDefault(); } }, true);
appsRoot.addEventListener("scroll", function (e) { var r = e.target; if (r.classList && (r.classList.contains("g-grps") || r.classList.contains("g-strip"))) edges(r); }, true);
window.addEventListener("resize", allEdges);
render();
