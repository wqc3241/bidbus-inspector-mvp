// Writes data/issue-catalog.json: the backend list of every issue the inspector app can report,
// read from the built app (dist/internal-mvp.html) so it always matches what inspectors can pick.
// Run: node verify/issue-catalog.js   (needs Playwright)
const fs = require('fs'), path = require('path'), crypto = require('crypto'), { chromium } = require('playwright');
const ROOT = path.join(__dirname, '..');
(async () => {
  const html = '<!doctype html><html><head><meta charset=utf8></head><body>' + fs.readFileSync(ROOT + '/reference/mockup/internal-mvp.html', 'utf8') + '</body></html>';
  const tmp = path.join(require('os').tmpdir(), 'issue-catalog-page.html'); fs.writeFileSync(tmp, html);
  const b = await chromium.launch(), p = await b.newPage(), errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + tmp);
  const cat = await p.evaluate(() => {
    const FUELS = ['Gas or diesel', 'Hybrid', 'Plug-in hybrid', 'Electric (EV)'];
    const CR_ROW = { OBDII: 'OBD-II' };
    const DMG = { Scratch: 'scratches', Scuff: 'scratches', Dent: 'dents', Hail: 'dents', Chip: 'paintwork', 'Crack/break': 'broken_or_missing_parts', 'Rust': 'additional_damage', Structure: 'additional_damage' };
    const CK_DMG = { ck_paint: 'previous_paint_work', ck_wheel: 'wheel_damage', ck_lights_dash: 'warning_lights', ck_lights: 'broken_or_missing_parts', ck_wipers: 'broken_or_missing_parts', ck_fuel_cap: 'broken_or_missing_parts' };
    const dmgType = (ck, t) => ck === 'ck_glass' ? (/^Mirror/.test(t) ? 'broken_or_missing_parts' : 'windshield_damage') : ck ? (CK_DMG[ck] || 'additional_damage') : (DMG[t] || 'additional_damage');
    const fuelsOf = f => FUELS.filter(x => f(x));
    const car0 = Object.keys(S.cars)[0] || (CARS[0] && CARS[0].id); const keep = { car: S.car, fuel: S.cars[car0] && S.cars[car0].fuel };
    if (!S.cars[car0]) S.cars[car0] = newCar(CARS[0]); S.car = car0;
    const withFuel = (f, fn) => { S.cars[car0].fuel = f; try { return fn(); } finally { S.cars[car0].fuel = keep.fuel; } };
    // checks: every option with its report level and the fuels it shows for
    const checks = QL.items.filter(it => it.kind === 'check').map(it => {
      const o = { id: it.id, no: it.no, label: it.label, section: it.section, app_section: secOf(it), cr_row: CR_ROW[it.section] || it.section, cars: it.cars, default: it.default || 'OK',
        per_wheel: it.id === 'ck_tire' || it.id === 'ck_wheel',
        options: it.options.filter(x => !(it.id === 'ck_features' && FEAT_DROP[x])).map(x => ({ option: x, level: (it.levels || {})[x] || 'Disclosed', fuels: fuelsOf(f => fuelOk(it.cars, f) && optsFor(it, f).indexOf(x) >= 0) })) };
      if (EXTRA[it.id]) o.where = { label: EXTRA[it.id].label, options: EXTRA[it.id].opts.slice() };
      if (it.id === 'ck_scan') o.codes = 'typed engine codes, e.g. P0420';
      return o; });
    // damage places: per section, every place with the types it allows for each fuel
    const places = [], issues = [];
    Object.keys(DPLACES).forEach(z => DPLACES[z].forEach(pl => {
      const allT = []; FUELS.forEach(f => withFuel(f, () => { if (placesFor(z).indexOf(pl) < 0) return; placeOpts(pl).forEach(t => { if (allT.indexOf(t) < 0 && !twinOf(pl, t)) allT.push(t); }); }));
      // a paint problem picked at an Exterior body panel is stored at the Paint place, so it is listed there only
      const types = allT.map(t => {
        const fu = fuelsOf(f => withFuel(f, () => placesFor(z).indexOf(pl) >= 0 && placeOpts(pl).indexOf(t) >= 0));
        let e;
        if (isStruct(pl, t)) e = { type: t, answers: { check: 'ck_structure', option: pl.st }, level: BYID.ck_structure.levels[pl.st] || 'Disclosed', bidbus_damage_type: 'additional_damage', frame_damage: 'yes' };
        else if (pl.ck) e = { type: t, answers: { check: pl.ck, option: t }, level: (BYID[pl.ck].levels || {})[t] || 'Disclosed', bidbus_damage_type: dmgType(pl.ck, t) };
        else if (pl.feat) e = { type: t, answers: { feature: pl.feat, answer: 'Not working' }, level: 'Disclosed', bidbus_damage_type: 'additional_damage' };
        else e = { type: t, answers: null, level: 'Disclosed', bidbus_damage_type: dmgType(null, t) };
        if (fu.length < FUELS.length) e.fuels = fu;
        return e; });
      const o = { section: dmgSec(z, pl.p), place: pl.p };
      if (pl.w) o.wheel = pl.w; if (pl.ck) o.check = pl.ck; if (pl.feat) o.feature = pl.feat;
      if (pl.ex) o.where = { label: pl.exl, options: pl.exo.slice(), fixed: !!pl.fix };
      o.types = types; places.push(o);
      types.forEach(t => issues.push(Object.assign({ section: o.section, place: pl.p }, t)));
    }));
    // check options no damage place gives: reported on the check row only (no photo); place = the check's section, or its Which wheel / Where answer
    const viaPlace = {}; issues.forEach(i => { if (i.answers && i.answers.check) viaPlace[i.answers.check + '|' + i.answers.option] = 1; });
    const check_only = []; checks.forEach(c => c.options.forEach(o => { if (!viaPlace[c.id + '|' + o.option]) check_only.push({ check: c.id, section: c.section, cr_row: c.cr_row, option: o.option, level: o.level, fuels: o.fuels.length < FUELS.length ? o.fuels : undefined, where: c.where ? c.where.label : (c.per_wheel ? 'Which wheel' : undefined) }); }));
    S.car = keep.car;
    return { fuels: FUELS, severities: QL.damage_places.severity, size_in: { min: 1, max: 36, step: 1, required: false },
      levels: [{ level: 'Ends the visit', report: 'Not listed' }, { level: 'Not listed until fixed', report: 'Not listed' }, { level: 'Red', report: 'Red light' }, { level: 'Yellow', report: 'Yellow light' }, { level: 'Disclosed', report: 'Listed, light unchanged' }],
      cr_rows: ['Exterior', 'Paint', 'Tires', 'Underbody', 'Mechanicals', 'Engine sound', 'Interior', 'OBD-II', 'Additionals'],
      paint_panels: PAINT_PANELS.map(x => x.panel === 'Hood' ? 'Hood or frunk lid' : x.panel), paint_high_mils: PAINT_HIGH,
      wheels: WHEELS.map(w => ({ wheel: w[0], name: w[2] })),
      checks, places, issues, check_only };
  });
  const ql = fs.readFileSync(ROOT + '/data/question-list.json');
  const out = Object.assign({ title: 'Inspector app issue catalog', made_by: 'verify/issue-catalog.js from dist/internal-mvp.html', question_list_md5: crypto.createHash('md5').update(ql).digest('hex').slice(0, 8) }, cat);
  fs.writeFileSync(ROOT + '/data/issue-catalog.json', JSON.stringify(out, null, 1));
  console.log('checks', cat.checks.length, 'options', cat.checks.reduce((a, c) => a + c.options.length, 0), 'places', cat.places.length, 'place+type issues', cat.issues.length, 'check-only options', cat.check_only.length, 'errors', JSON.stringify(errs));
  await b.close();
})();
