// V71 (Tom 11-07 07:43): number of keys read by the AI from the keys photo, confirmed on Review Interior, kept in step with C35 Keys, sent in the payload
const fs=require('fs');const {chromium}=require('playwright');
const html='<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1"><style>body{margin:0;font:14px system-ui}[hidden]{display:none!important}</style></head><body>'+fs.readFileSync(require('path').join(__dirname,'..','reference','mockup','internal-mvp.html'),'utf8')+'</body></html>';
fs.writeFileSync('keys.html',html); fs.mkdirSync('keys',{recursive:true});
const START=async(p)=>{ if(await p.locator('[data-go="idcheck"]').count()){ await p.locator('[data-go="idcheck"]').click(); await p.evaluate(()=>{const st=cur(); docsMissing(st).forEach(x=>st.docs[x[0]]='today 9:00 AM'); render();}); if(!(await p.evaluate(()=>cur().owner))) await p.locator('[data-owner="Yes"]').click(); } await p.locator('.ff [data-go="start"]').click(); await p.waitForTimeout(60); };
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1280,height:950}});const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.goto('file://'+process.cwd()+'/keys.html');
const E=(f,a)=>p.evaluate(f,a); const ok=(c,m)=>console.log((c?'PASS ':'FAIL ')+m);
let n=0; const shot=async(nm)=>{n++; const bx=await p.locator('.dev').boundingBox(); await p.screenshot({path:`keys/${String(n).padStart(2,'0')}-${nm}.png`,clip:bx});};
const pick=async(sel,v)=>{ await p.locator(sel).first().click(); await p.locator('.sheet.ch [data-chpick="'+v+'"]').click(); await p.waitForTimeout(80); };
const K=()=>E(()=>({n:cur().vals.keys_n, auto:cur().vals.keys_auto, p:(cur().probs.ck_keys||[]).slice()}));
await p.locator('.car',{hasText:'BMW X3'}).click(); await START(p);
await p.locator('[data-cclose]').first().click();
ok((await K()).n==null,'no number of keys before the keys photo');
await E(()=>{ const st=cur(); autoRead(st,'ph_keys'); });
let k=await K(); ok(k.n==='2' && k.auto===1 && !k.p.includes('Only one key'),'keys photo: AI reads 2, no Only one key '+JSON.stringify(k));
await E(()=>{ car().keys=1; const st=cur(); st.vals.keys_n=null; autoRead(st,'ph_keys'); });
k=await K(); ok(k.n==='1' && k.auto===1 && k.p[0]==='Only one key','AI reads 1: ticks Only one key '+JSON.stringify(k));
await E(()=>{ const st=cur(); autoRead(st,'ph_keys'); }); ok((await K()).n==='1','a second keys photo keeps the number');
await p.locator('[data-fill]').click(); await p.waitForTimeout(200); await E(()=>{if(cur().phase==='label'){fillStep();}}); await p.waitForTimeout(60);
ok(await E(()=>cur().phase)==='summary','summary');
await p.locator('.sstrip [data-spk="Interior"]').click(); await p.waitForTimeout(80);
const row=p.locator('#sc-Interior [data-chopen="keys"]');
ok(await row.count()===1 && /Keys[\s\S]*1/.test(await row.innerText()) && /Read from photo/.test(await row.innerText()),'Interior: Keys row first with 1, Read from photo: '+(await row.innerText()).replace(/\n/g,' | '));
ok(await E(()=>{ const r=document.querySelector('#sc-Interior .rlist [data-chopen]'); return r && r.dataset.chopen==='keys'; }),'Keys is the first row of the Interior list');
await row.scrollIntoViewIfNeeded(); await shot('interior-keys-1');
await row.click(); await p.waitForTimeout(80);
ok(await p.locator('.sheet.ch [data-chpick]').count()===3,'drawer offers 0, 1, 2');
await shot('keys-drawer');
await p.locator('.sheet.ch [data-chpick="2"]').click(); await p.waitForTimeout(80);
k=await K(); ok(k.n==='2' && k.auto===0 && !k.p.includes('Only one key'),'pick 2: Only one key cleared, no longer from photo '+JSON.stringify(k));
ok(!/Read from photo/.test(await row.innerText()),'row no longer says Read from photo');
await pick('#sc-Interior [data-chopen="keys"]','0'); k=await K(); ok(k.n==='0' && !k.p.includes('Only one key'),'pick 0 '+JSON.stringify(k));
await pick('#sc-Interior [data-chopen="keys"]','1'); k=await K(); ok(k.n==='1' && k.p.includes('Only one key'),'pick 1 ticks Only one key '+JSON.stringify(k));
ok((await E(()=>problemsList(cur()).map(x=>x.text))).includes('Keys: Only one key'),'Keys: Only one key is a finding');
// C35 Keys drawer keeps the number in step
await pick('#sc-Interior [data-chopen="ck"][data-id="ck_keys"]','Two or more work'); k=await K(); ok(k.n==='2' && !k.p.length,'C35 back to Two or more work sets 2 '+JSON.stringify(k));
await pick('#sc-Interior [data-chopen="ck"][data-id="ck_keys"]','Only one key'); k=await K(); ok(k.n==='1' && k.p.includes('Only one key'),'C35 Only one key sets 1 '+JSON.stringify(k));
await pick('#sc-Interior [data-chopen="keys"]','2'); k=await K(); ok(k.n==='2' && !k.p.includes('Only one key'),'then pick 2 clears it '+JSON.stringify(k));
await pick('#sc-Interior [data-chopen="ck"][data-id="ck_keys"]','No key works'); k=await K(); ok(k.n==='2' && k.p.includes('No key works'),'No key works leaves the number '+JSON.stringify(k));
// required
await E(()=>{ cur().vals.keys_n=null; render(); });
ok(/Pick the number of keys/.test(await p.locator('.ff button').first().innerText()),'no number: Interior Next says Pick the number of keys');
const gi=await E(()=>{ const r=pageBlock(cur(),'Interior'); return [SC_INFO.Interior, r, featMissing(cur())]; }); console.log(JSON.stringify(gi)); ok(gi[0].fqm===1+gi[2] && gi[1]==='Pick the number of keys','Interior: 1 to answer, page gate Pick the number of keys');
await E(()=>{ const st=cur(); st.vals.tires_match='Match'; WHEELS.forEach(w=>{ if(st.tires[w[0]].tread==='') st.tires[w[0]].tread='6'; }); st.manual.forEach(fillDmg); });
ok(await E(()=>sumBlock(cur()))==='Pick the number of keys','Show the seller blocked: '+await E(()=>sumBlock(cur())));
await row.scrollIntoViewIfNeeded(); await shot('interior-keys-missing');
await pick('#sc-Interior [data-chopen="keys"]','2');
ok(!/Pick the number of keys/.test(await p.locator('.ff button').first().innerText()),'picked: gate gone');
// payload
let pay=await E(()=>inspectionPayload(cur())); ok(pay.vehicle.keys_count===2 && pay.vehicle.keys_count_read_from_photo===false,'payload keys_count 2, not from photo');
await E(()=>{ const st=cur(); st.vals.keys_n=null; car().keys=1; autoRead(st,'ph_keys'); });
pay=await E(()=>inspectionPayload(cur())); ok(pay.vehicle.keys_count===1 && pay.vehicle.keys_count_read_from_photo===true && pay.checks.find(c=>c.id==='ck_keys').problems.some(x=>x.option==='Only one key'),'payload keys_count 1 from photo, C35 Only one key');
// demo fill sets a number when missing
await E(()=>{ const st=cur(); st.vals.keys_n=null; st.phase='summary'; fillStep(); });
ok((await K()).n==='2','demo fill sets 2 when missing');
console.log('errors',errs); await b.close();})();
