// Every question of the MVP question list, start to finish, for each fuel type (Tom 11-07 02:31)
const C=require('./walkcommon.js'); const fs=require('fs');
const RUNS=process.argv[2]?[[process.argv[2],process.argv[3]||null]]:[['BMW X3',null],['Tesla Model Y',null],['Honda Accord','Hybrid'],['Toyota RAV4','Plug-in hybrid']];
(async()=>{ const {b,p,E,errs}=await C.setup('walk/ALLQ','allq'); p.setDefaultTimeout(3000);
 const REPORT={runs:[]}; let fails=[]; const F=(run,m)=>{fails.push(run+': '+m);};
 for(const [CAR,FUEL] of RUNS){
  const R={car:CAR,fuel:'',items:{},options:0,optFails:[],damage:0,dmgFails:[],pages:{},seller:[],sent:false};
  await E(n=>{ const c=CARS.find(x=>x.ymmt.indexOf(n)>=0); S.cars[c.id]=newCar(Object.assign({},c,{preset:null})); S.screen='cars'; S.car=null; render(); },CAR);
  await p.locator('.car',{hasText:CAR}).click(); await p.locator('[data-go="idcheck"]').click();
  // seller documents and owner, through the screen
  while(await p.locator('button.shoot[data-docshot]').count()){ await p.locator('button.shoot[data-docshot]').first().click(); await p.waitForTimeout(40); }
  await p.locator('[data-owner="Yes"]').click();
  if(FUEL) await E(f=>{ cur().fuel=f; },FUEL);
  await p.locator('.ff [data-go="start"]').click(); await p.waitForTimeout(80);
  R.fuel=await E(()=>cur().fuel);
  // camera, damages and review filled with the demo helper (the camera itself is walked by walkA/walkB)
  await E(()=>{ S.cap=null; const st=cur(); st.phase='capture'; fillStep(); });
  await E(()=>{ fillStep(); }); await E(()=>{ fillStep(); });
  // 1. every question of the list has its place in the app
  R.items=await E(()=>{ const st=cur(), fuel=st.fuel, out={};
    const cap=new Set(); CAPSEQ.forEach(k=>{ capList(k,st).forEach(x=>cap.add(x.it?x.it.id:x.id)); });
    const media=new Set(); ['Exterior','Interior','OBDII','Mechanicals'].forEach(k=>stepItems(k,st).media.forEach(m=>media.add(m.id)));
    const checks={}; CAPSEQ.forEach(k=>{ if(k==='start') return; if(k==='Tires'){ checks.ck_tire='Tires'; checks.ck_wheel='Tires'; return; } if(k==='Paint'){ checks.ck_paint='Paint'; return; } stepItems(k,st).checks.forEach(c=>checks[c.id]=k); });
    const SPECIAL={ fuel:'VIN decode: '+fuel, ph_license:'Check ID: seller upload', ph_reg:'Check ID: seller upload', id_owner:'Check ID: owner = '+st.owner,
      ph_ext_front_left_corner:'360 frame', ph_ext_left_side:'360 frame', ph_ext_rear_left_corner:'360 frame', ph_ext_rear:'360 frame', ph_ext_rear_right_corner:'360 frame', ph_ext_right_side:'360 frame', ph_ext_front_right_corner:'360 frame', ph_ext_front:'360 frame',
      ph_mod_ext:'Mod shutter', ph_mod_int:'Mod shutter', ph_mod_mech:'Mod shutter', ph_paint_base:'Paint meter photos, one per panel ('+PAINT_PANELS.length+')', 'damage.photo':'Damage shutter ('+st.manual.length+' taken)',
      tire_brand:'Review Tires picker', tire_size:'Review Tires picker', tread:'Review Tires picker: '+WHEELS.map(w=>st.tires[w[0]].tread).join('/'), tires_match:'Review Tires: '+st.vals.tires_match,
      sunroof:'Review Interior: '+(featOf(st).sunroof||''), navigation:'Review Interior: '+(featOf(st).navigation||''), ev_soh:'OBDII entry', vin_scan:'Interior: read from door-jamb photo',
      seller_name:'Seller signs', seller_sign:'Seller signs', summary:'Seller signs: findings', overall_condition:'Summary: '+st.overall, mileage_confirm:'Summary VIN and mileage card', vin_confirm:'Summary VIN and mileage card' };
    QL.items.forEach(it=>{ const on=fuelOk(it.cars,fuel); let where='';
      if(it.kind==='check') where=checks[it.id]?'Review '+checks[it.id]+' row':'';
      else if(cap.has(it.id)) where='Camera '+[...CAPSEQ].find(k=>capList(k,st).some(x=>(x.it?x.it.id:x.id)===it.id));
      else if(media.has(it.id)) where='Section media';
      if(!where && SPECIAL[it.id]!==undefined) where=SPECIAL[it.id];
      if(it.kind==='entry' && it.id==='ev_soh' && on) where=stepItems('OBDII',st).entries.some(e=>e.id==='ev_soh')?'OBDII entry':'';
      out[it.id]={on, kind:it.kind, where}; });
    return out; });
  Object.entries(R.items).forEach(([id,x])=>{ if(x.on && !x.where) F(CAR,'question '+id+' not found in the app'); if(!x.on && x.kind==='check' && x.where) F(CAR,'question '+id+' shows for '+R.fuel+' but is not for this fuel'); });
  // damage photos of the demo fill would lock their options: clear them for the option rounds
  await E(()=>{ const st=cur(); st.manual=[]; syncDamages(st); st.probs={}; st.extra={}; WHEELS.forEach(w=>{ st.tires[w[0]].probs={}; st.tires[w[0]].extra={}; }); st.dprev=[]; render(); });
  // 2. every option of every check, picked on its Review page through the drawer
  const CK=await E(()=>{ const st=cur(), out=[]; CAPSEQ.forEach(k=>{ if(k==='start') return; let ids=k==='Tires'?['ck_tire','ck_wheel']:k==='Paint'?['ck_paint']:stepItems(k,st).checks.map(c=>c.id);
    ids.forEach(id=>{ const it=BYID[id]; const base=ckBase(it); const opts=optsFor(it,st.fuel).filter(o=>base.indexOf(o)<0); (k==='Tires'?WHEELS.map(w=>w[0]):['']).forEach(w=>out.push({k,id,w,opts,base:base[0],label:it.label,levels:it.levels||{}})); }); }); return out; });
  const maxR=Math.max(...CK.map(c=>c.opts.length));
  const goPage=async(k)=>{ await E(k=>{ const st=cur(); st.phase='summary'; S.choice=null; st.sp=sumPages().indexOf(k); render(); },k); };
  const openRow=async(c)=>{ if(c.w){ await p.locator(`[data-wsel="${c.w}"]`).first().click(); } const sel=`#sc-${c.k} [data-chopen="ck"][data-id="${c.id}"]`+(c.w?`[data-w="${c.w}"]`:''); await p.locator(sel).first().click(); };
  for(let r=0;r<maxR;r++){
    const picked=[];
    for(const c of CK){
      await goPage(c.k);
      const o=c.opts[r]; await openRow(c);
      if(o===undefined){ await p.locator(`.sheet.ch [data-chpick="${c.base.replace(/"/g,'\\"')}"]`).click(); continue; }
      const btn=p.locator('.sheet.ch [data-chpick]').filter({hasText:new RegExp('^'+o.replace(/\s*\(type[^)]*\)/g,'').replace(/[.*+?^${}()|[\]\\]/g,'\\$&').slice(0,40))});
      if(!(await btn.count())){ R.optFails.push(c.id+(c.w?'@'+c.w:'')+': option not in drawer: '+o); continue; }
      await btn.first().click(); await p.waitForTimeout(20);
      // second step: which panel / wheel / where, or the engine codes
      if(await E(()=>!!S.choice && S.choice.step==='extra')){ await p.locator('.sheet.ch [data-chpick]').first().click(); }
      if(await E(()=>!!S.choice && S.choice.step==='codes')){ await p.fill('#codes','P0420'); await p.locator('.sheet.ch [data-chx]').click(); }
      R.options++;
      const ok=await E(c=>{ const st=cur(), src=c.w?st.tires[c.w]:st; return (src.probs[c.id]||[]).indexOf(c.o)>=0; },{...c,o});
      if(!ok) R.optFails.push(c.id+(c.w?'@'+c.w:'')+': not saved: '+o);
      const row=await p.locator(`#sc-${c.k} [data-chopen="ck"][data-id="${c.id}"]`+(c.w?`[data-w="${c.w}"]`:'')).first().innerText().catch(()=>'');
      const plain=o.replace(/\s*\(type[^)]*\)/g,'');
      if(row.replace(/\s+/g,' ').indexOf(plain.slice(0,30))<0) R.optFails.push(c.id+(c.w?'@'+c.w:'')+': row does not show: '+plain);
      if(!c.w || c.w==='lf') picked.push({c,o:plain,lv:c.levels[o]||'Disclosed'});
    }
    // Summary (What you found) and the seller page show every problem of this round
    await E(()=>{ const st=cur(); st.phase='final'; S.choice=null; render(); });
    const sumTxt=(await p.locator('.scr .body').innerText()).replace(/\s+/g,' ');
    await E(()=>{ const st=cur(); st.phase='sign'; render(); });
    const sellTxt=(await p.locator('.scr .body').innerText()).replace(/\s+/g,' ');
    const pl=await E(()=>problemsList(cur()).map(x=>x.text+' | '+x.level));
    for(const x of picked){ const t=(x.c.k==='Tires'?(x.c.id==='ck_tire'?'Tire: ':'Wheel: '):x.c.label+': ')+x.o;
      if(sumTxt.indexOf(t.slice(0,60))<0) R.optFails.push('Summary misses: '+t);
      if(sellTxt.indexOf(t.slice(0,60))<0) R.optFails.push('Seller page misses: '+t);
      if(!pl.some(s=>s.indexOf(t)===0 && s.endsWith('| '+x.lv))) R.optFails.push('Level wrong or missing: '+t+' ('+x.lv+')');
    }
  }
  // back to all OK
  await E(()=>{ const st=cur(); st.probs={}; st.extra={}; WHEELS.forEach(w=>{ st.tires[w[0]].probs={}; st.tires[w[0]].extra={}; }); st.codes=''; render(); });
  // 3. every damage place and type, in every damage section
  const D=await E(()=>{ const st=cur(), fails=[]; let n=0; st.manual=[]; st.dprev=[]; syncDamages(st);
    DZ.forEach(z=>{ placesFor(z).forEach(pl=>{ placeOpts(pl).forEach(t=>{
      const m={zone:z,panel:'',type:'',sev:'',size:'',shot:true,src:'camera'}; st.manual.push(m);
      setLabel(m,'panel',pl.p); setLabel(m,'type',t); if(pl.ex && !m.ex) m.ex=pl.exo[0]; setLabel(m,'sev','Moderate'); syncDamages(st); n++;
      if(!labelled(m)) fails.push(z+'/'+pl.p+'/'+t+': not labelled');
      else if(dmgOwn(st,m)){ if(totals(st).dlist.every(d=>d.indexOf(dmgLine(m))<0)) fails.push(z+'/'+pl.p+'/'+t+': damage line missing'); }
      else { const d=dmgDerived(st)[0]; const list=problemsList(st).map(x=>x.text); if(!d) fails.push(z+'/'+pl.p+'/'+t+': no check answer');
        else if(d.t==='p' && !list.some(x=>x.indexOf(plain(d.v))>=0)) fails.push(z+'/'+pl.p+'/'+t+': check answer not listed: '+d.id+' '+d.v);
        else if(d.t==='f' && featOf(st)[d.id]!=='Not working') fails.push(z+'/'+pl.p+'/'+t+': feature not set'); }
      st.manual.pop(); syncDamages(st);
      if(dmgDerived(st).length) fails.push(z+'/'+pl.p+'/'+t+': answer left behind');
    }); }); });
    return {n,fails}; });
  R.damage=D.n; R.dmgFails=D.fails;
  // 4. the real ending: Summary, seller signs, send
  await E(()=>{ const st=cur(); st.phase='summary'; st.sp=0; fillStep(); }); await E(()=>{ fillStep(); });
  await E(()=>{ const st=cur(); st.phase='final'; render(); });
  R.pages.summary=(await p.locator('.scr .body').innerText()).replace(/\s+/g,' ').slice(0,200);
  await p.locator('.ff [data-tosign]').click();
  const sell=(await p.locator('.scr .body').innerText());
  R.seller=(sell.match(/guarantee|protection|buyback|buy back|Purchase Protection|arbitration/ig)||[]);
  if(R.seller.length) F(CAR,'seller page says: '+R.seller.join(','));
  await p.locator('[data-agree]').click(); await p.fill('#sname','Test Seller'); await p.locator('#sname').dispatchEvent('input');
  const cv=p.locator('#sig'); await cv.scrollIntoViewIfNeeded(); const bb=await cv.boundingBox(); await p.mouse.move(bb.x+20,bb.y+40); await p.mouse.down(); await p.mouse.move(bb.x+120,bb.y+60,{steps:5}); await p.mouse.up();
  await p.locator('.ff [data-sign]').click(); await p.waitForTimeout(100);
  R.sent=await E(()=>S.screen==='upload' && cur().status==='done');
  if(!R.sent) F(CAR,'did not reach the upload screen');
  // the stored inspection: what the app would send
  const rec=await E(()=>{ const st=cur(); return {car:car().vin, fuel:st.fuel, owner:st.owner, shots:Object.keys(st.shots).filter(k=>st.shots[k]).length, tires:WHEELS.map(w=>st.tires[w[0]].tread), paint:Object.keys(st.paint).length, overall:st.overall, note:!!st.note, sign:!!st.signName, start:st.start, end:st.end}; });
  R.record=rec; fs.writeFileSync('walk/ALLQ/state-'+CAR.replace(/\W/g,'')+'.json',JSON.stringify(await E(()=>cur()),null,1));
  R.optFails.forEach(x=>F(CAR,x)); R.dmgFails.forEach(x=>F(CAR,x));
  REPORT.runs.push(R);
  console.log(CAR,R.fuel,'questions on:',Object.values(R.items).filter(x=>x.on).length,'options picked:',R.options,'damage combos:',R.damage,'optFails',R.optFails.length,'dmgFails',R.dmgFails.length,'sent',R.sent);
 }
 REPORT.fails=fails; REPORT.errs=errs; fs.writeFileSync('walk/ALLQ/report.json',JSON.stringify(REPORT,null,1));
 console.log('FAILS',fails.length); fails.slice(0,60).forEach(x=>console.log(' ',x)); console.log('errs',JSON.stringify(errs.slice(0,5))); await b.close(); })();
