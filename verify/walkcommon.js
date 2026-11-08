const fs=require('fs');const {chromium}=require('playwright');
exports.setup=async(OUTDIR,name)=>{
  const html='<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1"><style>body{margin:0;font:14px system-ui}[hidden]{display:none!important}</style></head><body>'+fs.readFileSync(require('path').join(__dirname,'..','reference','mockup','internal-mvp.html'),'utf8')+'</body></html>';
  fs.writeFileSync(name+'.html',html); fs.mkdirSync(OUTDIR,{recursive:true});
  const b=await chromium.launch(); const p=await b.newPage({viewport:{width:1280,height:1100}}); const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  p.setDefaultTimeout(4000);
  await p.goto('file://'+process.cwd()+'/'+name+'.html');
  let n=0; const issues=[];
  const E=(f,a)=>p.evaluate(f,a);
  const audit=async(nm)=>E(nm=>{
    const out=[]; const scr=document.querySelector('.scr'); if(!scr) return ['no .scr']; const R=scr.getBoundingClientRect();
    const txt=scr.innerText; const bad=txt.match(/undefined|NaN|\bnull\b|\[object|' \+|\+ '|data-[a-z]+=/g); if(bad) out.push('bad text: '+[...new Set(bad)].join(','));
    const body=scr.querySelector('.body'); if(body && body.scrollWidth>body.clientWidth+1) out.push('body scrolls sideways');
    const scrollerOf=el=>{for(let a=el.parentElement;a&&a!==scr;a=a.parentElement){const o=getComputedStyle(a).overflowX; if(o==='auto'||o==='scroll'||o==='hidden') return a;} return null;};
    scr.querySelectorAll('*').forEach(el=>{ const r=el.getBoundingClientRect(); if(!r.width||!r.height) return; const cs=getComputedStyle(el); if(cs.visibility==='hidden'||cs.position==='fixed') return;
      if((r.right>R.right+1||r.left<R.left-1) && !scrollerOf(el)) out.push('outside screen: '+el.tagName+'.'+String(el.className&&el.className.baseVal!==undefined?el.className.baseVal:el.className).slice(0,30)+' "'+(el.innerText||'').slice(0,30)+'"');
      if((el.tagName==='BUTTON'||el.tagName==='SPAN'||el.tagName==='B'||el.tagName==='SMALL'||el.tagName==='EM') && el.children.length<3 && el.scrollWidth>el.clientWidth+2 && el.clientWidth>0 && cs.overflow!=='visible' && cs.textOverflow!=='ellipsis' && !/sstrip|strip|jumpto/.test(el.className)) out.push('clipped: '+el.tagName+' "'+(el.innerText||'').slice(0,40)+'" '+el.scrollWidth+'>'+el.clientWidth);
    });
    return [...new Set(out)].slice(0,12);
  },nm);
  const shot=async(nm,opt={})=>{ n++; await p.waitForTimeout(opt.wait||320); const sc=await E(()=>{const s=document.querySelector('.scr'),d=document.querySelector('.dev'); return [scrollX,scrollY,s.scrollLeft,s.scrollTop,d.scrollLeft,d.scrollTop].join(',');}); if(sc!=='0,0,0,0,0,0') issues.push([String(n).padStart(3,'0')+'-'+nm,['scrolled win/scr/dev: '+sc]]); await E(()=>{window.scrollTo(0,0); document.scrollingElement.scrollTop=0; document.querySelectorAll('.scr,.dev').forEach(x=>{x.scrollTop=0;x.scrollLeft=0;});}); const a=await audit(nm); if(a.length) issues.push([String(n).padStart(3,'0')+'-'+nm,a]);
    const bx=await p.locator('.dev').boundingBox(); await p.screenshot({path:`${OUTDIR}/${String(n).padStart(3,'0')}-${nm}.png`,clip:bx});
    if(opt.full){ const H=await E(()=>{const b=document.querySelector('.scr .body'); return b?b.scrollHeight-b.clientHeight:0;}); let k=1; for(let y=600;y<H+600 && k<6;y+=600,k++){ await E(y=>{document.querySelector('.scr .body').scrollTop=y;},y); await p.waitForTimeout(80); const a2=await audit(nm); if(a2.length) issues.push([String(n).padStart(3,'0')+'-'+nm+'-'+k,a2]); await p.screenshot({path:`${OUTDIR}/${String(n).padStart(3,'0')}-${nm}-${k}.png`,clip:bx}); } await E(()=>{const b=document.querySelector('.scr .body'); if(b) b.scrollTop=0;}); } };
  const step=async(nm,fn)=>{ try{ await fn(); }catch(e){ issues.push(['STEP '+nm, [String(e.message).split('\n')[0]]]); } };
  const where=()=>E(()=>({cap:S.cap&&{k:S.cap.k,i:S.cap.i,mode:S.cap.mode||'',rec:!!S.cap.rec,sel:S.cap.sel||null}, screen:S.screen, phase:S.car&&cur().phase, sheet:!!S.sheet, ldrw:!!S.ldrw, choice:!!S.choice}));
  return {b,p,E,shot,step,where,issues,errs,audit};
};
