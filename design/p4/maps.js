// Velix P4: real-map rendering for phone frames (uses p3v3 palettes + renderer).
(function(){ if(window.VXP4) return;
const P4={}; let ready=null;
const cumLen=b=>{ const c=[0]; for(let i=2;i<b.length;i+=2) c.push(c[c.length-1]+Math.hypot(b[i]-b[i-2],b[i+1]-b[i-1])); return c; };
const sub=(b,d0,d1)=>{ const c=cumLen(b), out=[]; const at=d=>VX.along(b,d); const a=at(d0); out.push(a[0],a[1]); for(let i=0;i<c.length;i++) if(c[i]>d0&&c[i]<d1) out.push(b[i*2],b[i*2+1]); const e=at(d1); out.push(e[0],e[1]); return Float32Array.from(out); };
const line=(D,co)=>{ const f=new Float32Array(co.length*2); co.forEach(([lo,la],i)=>{ const p=D.toL(lo,la); f[i*2]=p[0]; f[i*2+1]=p[1]; }); return f; };
const proj=(b,x,y)=>{ const c=cumLen(b); let best=[0,1e12]; for(let i=2;i<b.length;i+=2){ const ax=b[i-2],ay=b[i-1],vx=b[i]-ax,vy=b[i+1]-ay,L2=vx*vx+vy*vy||1; let t=((x-ax)*vx+(y-ay)*vy)/L2; t=Math.max(0,Math.min(1,t)); const d=Math.hypot(ax+vx*t-x,ay+vy*t-y); if(d<best[1]) best=[c[i/2-1]+t*Math.sqrt(L2),d]; } return best; };
function tramX(D,b){ const hz=[]; (D.tram||[]).forEach(t=>t.rs.forEach(r=>{ for(let i=2;i<b.length;i+=2){ const ax=b[i-2],ay=b[i-1],bx=b[i],by=b[i+1]; for(let j=2;j<r.length;j+=2){ const cx=r[j-2],cy=r[j-1],dx=r[j],dy=r[j+1]; const den=(bx-ax)*(dy-cy)-(by-ay)*(dx-cx); if(Math.abs(den)<1e-6) continue; const ta=((cx-ax)*(dy-cy)-(cy-ay)*(dx-cx))/den, tb=((cx-ax)*(by-ay)-(cy-ay)*(bx-ax))/den; if(ta>=0&&ta<=1&&tb>=0&&tb<=1){ const x=ax+(bx-ax)*ta,y=ay+(by-ay)*ta; const [d]=proj(b,x,y); if(!hz.some(h=>Math.abs(h.d-d)<40)) hz.push({k:'tram',x,y,d}); } } } })); return hz.sort((a,b)=>a.d-b.d); }
function nav(o){ const b=o.best, L=VX.polyLen(b); const hz=o.hazards||[]; const lp=VX.along(b,L*(o.locAt||0));
  return { best:b, alt:o.alt||null, more:o.more||null, len:L, hazards:hz, tubes:hz.map(h=>sub(b,Math.max(0,h.d-(h.len?0:14)),Math.min(L,h.d+(h.len||14)))), avoided:o.avoided||null, loc:o.loc||[lp[0],lp[1]], heading:o.heading!=null?o.heading:lp[2], start:[b[0],b[1]], end:o.noEnd?null:(o.end||[b[b.length-2],b[b.length-1]]), endName:o.endName||'' }; }
function snapRail(D,wps){ const rails=D.tr.filter(t=>t.c==='rail'); const out=[]; for(let s=1;s<wps.length;s++){ const A=wps[s-1],B=wps[s]; const vx=B[0]-A[0],vy=B[1]-A[1],L2=vx*vx+vy*vy,L=Math.sqrt(L2); const pts=[]; rails.forEach(t=>t.rs.forEach(r=>{ for(let i=0;i<r.length;i+=2){ const tt=((r[i]-A[0])*vx+(r[i+1]-A[1])*vy)/L2; const off=Math.abs((r[i]-A[0])*vy-(r[i+1]-A[1])*vx)/L; if(tt>0&&tt<1&&off<160) pts.push([tt,r[i],r[i+1]]); } })); pts.sort((a,b)=>a[0]-b[0]); const n=Math.max(4,Math.round(L/120)); if(!out.length) out.push(A[0],A[1]); for(let i=0;i<n;i++){ const sel=pts.filter(p=>p[0]>=i/n&&p[0]<(i+1)/n); if(sel.length) out.push(sel.reduce((q,p)=>q+p[1],0)/sel.length, sel.reduce((q,p)=>q+p[2],0)/sel.length); } out.push(B[0],B[1]); } return Float32Array.from(out); }
function bbox(ls){ let x0=1e12,y0=1e12,x1=-1e12,y1=-1e12; ls.forEach(b=>{ if(!b) return; for(let i=0;i<b.length;i+=2){ x0=Math.min(x0,b[i]); x1=Math.max(x1,b[i]); y0=Math.min(y0,b[i+1]); y1=Math.max(y1,b[i+1]); } }); return [x0,y0,x1,y1]; }
function fit(D,ls,w,h,top,bottom,pad,zmax){ const [x0,y0,x1,y1]=bbox(ls); const vw=w-2*pad, vh=h-top-bottom-2*pad; const mpp=Math.max((x1-x0)/vw,(y1-y0)/vh); let z=Math.log2(78271.517*Math.cos(D.lat0*Math.PI/180)/mpp); z=Math.min(zmax||17,Math.floor(z*10)/10); return { z, c:[(x0+x1)/2,(y0+y1)/2], anchor:(top+pad+vh/2)/h }; }

P4.load=function(){ if(ready) return ready; ready=(async()=>{
  const get=u=>fetch(u).then(r=>r.json());
  const [mi,dm,no,rt,r4]=await Promise.all(['data/milan.json','data/dem-milan.json','data/north.json','data/routes-raw.json','data/routes-p4.json'].map(get));
  await Promise.all([document.fonts.load('400 12px "Atkinson Hyperlegible"'),document.fonts.load('700 12px "Atkinson Hyperlegible"')]);
  VX.ORIG.north=[9.24,45.535];
  const DM=VX.prep(mi,'milan'), DN=VX.prep(no,'north'), dem=VX.prepDem(dm);
  const NP=VX.buildNav(DM,rt);
  const T={};
  T.poli={D:DM,dem,N:NP};
  const keep=NP.hazards.map((h,i)=>h.k!=='cobbles'?i:-1).filter(i=>i>=0); T.poliCargo={D:DM,dem,N:Object.assign({},NP,{hazards:keep.map(i=>NP.hazards[i]),tubes:keep.map(i=>NP.tubes[i])})};
  const pv=NP.start;
  T.home={D:DM,dem,N:Object.assign({},NP,{loc:[pv[0],pv[1]-30],heading:-Math.PI/2+0.35})};
  // Centrale: single route
  const cb=line(DM,r4.centrale[1].coords); T.cent={D:DM,dem,N:nav({best:cb,hazards:tramX(DM,cb).slice(0,2),endName:'Milano Centrale'})};
  // Duomo, Cargo / kids: nothing meets "No cobbles"
  const du=DM.toL(9.1900,45.4641); let av=null,bd=1e9; DM.tr.forEach(t=>{ if(!['minor','tertiary','secondary','primary','pedestrian'].includes(t.c)&&t.s!=='pedestrian') return; t.rs.forEach(r=>{ const m=VX.along(r,VX.polyLen(r)/2); const d=Math.hypot(m[0]-du[0],m[1]-du[1]); const l=VX.polyLen(r); if(l>90&&d>60&&d<bd){ bd=d; av={r,tag:[m[0],m[1]],text:'Cobbles'}; } }); });
  T.duomo={D:DM,dem,N:Object.assign(nav({best:Float32Array.from([pv[0],pv[1],du[0],du[1]]),endName:'Piazza del Duomo'}),{avoided:av})};
  // Monza: two bike routes, then bike + train
  const mb=line(DN,r4.monzaBike[1].coords), ma=line(DN,r4.monzaBike[0].coords);
  T.monza={D:DN,N:nav({best:mb,alt:ma,endName:'Villa Reale'})};
  const r1=line(DN,r4.toCentrale[1].coords), r2=line(DN,r4.mzToVR[0].coords);
  const W=[[9.2040,45.4862],[9.2135,45.5130],[9.2380,45.5410],[9.2705,45.5785]].map(p=>DN.toL(p[0],p[1]));
  const tr=snapRail(DN,W);
  T.monzaT={D:DN,N:nav({best:r1,more:[r2],end:[r2[r2.length-2],r2[r2.length-1]],endName:'Villa Reale'}),leg:{r:tr,from:{x:W[0][0],y:W[0][1]},to:{x:W[3][0],y:W[3][1]},label:'R'}};
  T.north={D:DN,N:T.monza.N};
  const c0=line(DM,r4.centrale[0].coords), c1=line(DM,r4.centrale[1].coords);
  const cobAt=(b,d,len)=>{ const a=VX.along(b,d); return {k:'cobbles',x:a[0],y:a[1],d,len}; };
  T.s5calm={D:DM,dem,N:nav({best:c0,hazards:tramX(DM,c0).slice(0,3),endName:'Milano Centrale'})};
  T.s5fast={D:DM,dem,N:nav({best:c1,hazards:[cobAt(c1,1230,120)].concat(tramX(DM,c1).filter(h=>h.d>300).slice(0,2)).sort((a,b)=>a.d-b.d),endName:'Milano Centrale'})};
  T.s5train={D:DN,N:Object.assign({},T.monzaT.N,{best:T.monzaT.leg.r,more:null}),leg:T.monzaT.leg};
  P4.T=T; return T; })(); return ready; };
let readyP7=null;
P4.loadP7=function(){ if(readyP7) return readyP7; readyP7=(async()=>{ const T=await P4.load(); const [wd,co,r7]=await Promise.all(['data/wide.json','data/como.json','data/routes-p7.json'].map(u=>fetch(u).then(r=>r.json())));
  VX.ORIG.wide=wd.origin; VX.ORIG.como=co.origin; const D=VX.prep(wd,'wide'), DC=VX.prep(co,'como');
  const L={}; ['pavese','martesana','parconord','groane','approach'].forEach(k=>L[k]=line(D,r7[k].coords));
  const key=(b,n,sel,f)=>{ const a=VX.along(b,VX.polyLen(b)*(f||.5)); return {x:a[0],y:a[1],n,sel}; };
  T.rtList={D,N:Object.assign(nav({best:L.pavese}),{alts:[L.pavese,L.martesana,L.groane],altSel:0,keys:[key(L.pavese,1,1,.22),key(L.martesana,2,0,.3),key(L.groane,3,0,.35)]})};
  T.rtAll={D,N:Object.assign(nav({best:L.pavese}),{alts:[L.pavese,L.martesana,L.parconord,L.groane],altSel:2,keys:[key(L.pavese,1,0,.22),key(L.martesana,2,0,.3),key(L.parconord,3,1,.15),key(L.groane,4,0,.35)]})};
  T.rtSel={D,N:Object.assign(nav({best:L.pavese,endName:'Pavia'}),{alts:[L.martesana,L.groane],keys:[key(L.pavese,1,1,.55),key(L.martesana,2,0,.45),key(L.groane,3,0,.5)]})};
  T.rideRoute={D,N:nav({best:L.approach,more:[L.pavese],end:[L.pavese[L.pavese.length-2],L.pavese[L.pavese.length-1]],endName:'Pavia'})};
  T.como={D:DC,N:null};
  return T; })(); return readyP7; };
let readyS5=null;
P4.loadS5=function(){ if(readyS5) return readyS5; readyS5=(async()=>{ const T=await P4.load(); const [mz,r4]=await Promise.all(['data/monza-s5.json','data/routes-p4.json'].map(u=>fetch(u).then(r=>r.json())));
  VX.ORIG.monzaS5=mz.origin; const D=VX.prep(mz,'monzaS5'); const b=line(D,r4.mzToVR[0].coords);
  T.s5monza={D,N:nav({best:b,hazards:tramX(D,b),endName:'Villa Reale'})}; return T; })(); return readyS5; };

// frame configs: trip, fit lines, style, extras
P4.CFG={
  home:{t:'home',z:15.3,center:'loc',dy:-60,only:['loc']},
  homePan:{t:'home',z:15.3,center:'loc',dx:520,dy:-380,only:['loc']},
  homeNoGps:{t:'home',z:15.3,center:'loc',dy:-60,only:['loc'],puck:false},
  homeOut:{t:'north',z:10.4,cAt:[9.24,45.53],route:false},
  thumbStd:{t:'home',z:15,center:'loc',only:['loc'],labels:false},
  thumbSat:{t:'home',z:15,center:'loc',only:['loc'],labels:false,style:'satellite'},
  thumbOut:{t:'home',z:15,center:'loc',only:['loc'],labels:false,style:'outdoor'},
  poli:{t:'poli',fit:['best','alt']},
  poliCargo:{t:'poliCargo',fit:['best','alt']},
  poliGravel:{t:'poli',fit:['best','alt'],style:'outdoor'},
  poliWait:{t:'poli',fit:['best','alt'],only:['best'],noLine:true},
  cent:{t:'cent',fit:['best']},
  monza:{t:'monza',fit:['best','alt']},
  monzaT:{t:'monzaT',fit:['best','more'],leg:true,alt:false,minRoute:6},
  r2d:{t:'poli',d:420,z:16.6,anchor:.62},
  r3d:{t:'poli',d:420,z:17,pitch:52,anchor:.70},
  rNorth:{t:'poli',d:420,z:16.2,north:1,anchor:.55},
  rOver:{t:'poli',d:420,overview:1},
  rHaz:{t:'poli',d:545,z:17.2,anchor:.62},
  rAvoid:{t:'poli',d:62,z:16.8,anchor:.62,avoided:'Skipping Viale Piave: rails'},
  rRe:{t:'poli',d:720,z:16.6,anchor:.62,off:42},
  rGps:{t:'poli',d:1100,z:16.6,anchor:.62},
  rArr:{t:'poli',d:2215,z:17.2,anchor:.62},
  rPan:{t:'poli',d:420,z:16.2,north:1,anchor:.36},
  s5a:{t:'s5calm',d:200,z:16.6,anchor:.66},
  s5late:{t:'s5fast',d:230,z:16.4,anchor:.66},
  s5miss:{t:'s5calm',d:700,z:16.6,anchor:.66},
  s5train:{t:'monzaT',fit:['best','more'],leg:true,alt:false,trainAt:.62,minRoute:6},
  s5c:{t:'s5monza',d:330,z:16.6,anchor:.66},
  rtList:{t:'rtList',fit:['focus'],zmax:10.4,style:'outdoor',only:['alt'],noLine:true,minRoute:6,altsAccent:1},
  rtAll:{t:'rtAll',z:9.9,cAt:[9.22,45.50],style:'outdoor',only:['alt'],noLine:true,minRoute:6,altsAccent:1},
  rtSel:{t:'rtSel',fit:['best'],style:'outdoor',only:['best','alt'],minRoute:5},
  rtRide:{t:'rideRoute',fit:['best','more'],style:'outdoor',only:['best'],minRoute:5},
  rtComo:{t:'como',z:11.8,cAt:[9.15,45.85],style:'outdoor',route:false},
  rtOut:{t:'north',z:10.4,cAt:[9.24,45.53],style:'outdoor',route:false},
  summ:{t:'poli',fit:['best'],only:['best'],alt:false},
  duomo:{t:'duomo',z:14.9,cAt:[9.1915,45.4648],only:['best','avoided'],noLine:true}
};
P4.draw=async function(cv){ try{ return await P4._draw(cv); }catch(e){ console.error('map',cv.dataset.map,e); } };
P4._draw=async function(cv){ const id=cv.dataset.map, cfg=P4.CFG[id]; if(!cfg) return; const T=cfg.t==='s5monza'?await P4.loadS5():['rtList','rtAll','rtSel','rideRoute','como'].includes(cfg.t)?await P4.loadP7():await P4.load(); const A=T[cfg.t];
  const w=+cv.dataset.w||393, h=+cv.dataset.h||852, top=+cv.dataset.top||0, bottom=+cv.dataset.bottom||0, mode=cv.dataset.mode||'day';
  const F={w,h,style:cfg.style||cv.dataset.style||'standard',mode,chrome:false,route:cfg.route,only:cfg.only,labels:cfg.labels,puck:cfg.puck,alt:cfg.alt,noLine:cfg.noLine,minRoute:cfg.minRoute,altsAccent:cfg.altsAccent};
  if(cfg.fit){ const ls=[]; cfg.fit.forEach(k=>{ if(k==='more') (A.N.more||[]).forEach(x=>ls.push(x)); else if(k==='alts') (A.N.alts||[]).forEach(x=>ls.push(x)); else if(k==='focus') ls.push(A.N.alts[A.N.altSel]); else ls.push(A.N[k]); }); if(A.leg&&cfg.leg) ls.push(A.leg.r); const f=fit(A.D,ls,w,h,top,bottom,+cv.dataset.pad||28,+cv.dataset.zmax||16.4); Object.assign(F,f); }
  else { F.z=cfg.z; const c=cfg.cAt?A.D.toL(cfg.cAt[0],cfg.cAt[1]):[A.N.loc[0],A.N.loc[1]]; F.c=[c[0]+(cfg.dx||0),c[1]+(cfg.dy||0)]; F.anchor=(top+(h-top-bottom)/2)/h; }
  if(cv.dataset.z) F.z=+cv.dataset.z;
  let N=A.N; if(cfg.hideLine){ N=Object.assign({},N,{best:N.best}); }
  if(cfg.d!=null){ const b0=A.N.best, L=VX.polyLen(b0); const a=VX.along(b0,cfg.d); const hd=a[2]; let loc=[a[0],a[1]]; if(cfg.off) loc=[a[0]-Math.sin(hd)*cfg.off,a[1]+Math.cos(hd)*cfg.off];
    const keep=A.N.hazards.map((h,i)=>h.d>cfg.d-4?i:-1).filter(i=>i>=0);
    N=Object.assign({},A.N,{best:sub(b0,Math.min(cfg.d,L-5),L),loc,heading:hd,hazards:keep.map(i=>A.N.hazards[i]),tubes:keep.map(i=>A.N.tubes[i]),avoided:cfg.avoided?Object.assign({},A.N.avoided,{text:cfg.avoided}):null,alt:null});
    if(cfg.overview){ Object.assign(F,fit(A.D,[b0],w,h,top,bottom,+cv.dataset.pad||28,16.4)); N.best=b0; }
    else { F.z=cfg.z; F.c=loc; F.anchor=cfg.anchor||0.66; F.pitch=cfg.pitch||0; F.bearing=cfg.north?0:hd*180/Math.PI+90; F.follow=!cfg.north; }
  }
  if(cfg.trainAt!=null&&A.leg){ const a=VX.along(A.leg.r,VX.polyLen(A.leg.r)*cfg.trainAt); N=Object.assign({},N,{loc:[a[0],a[1]],heading:a[2]}); }
  if(cfg.leg&&A.leg){ F.leg=Object.assign({},A.leg,{asRoute:1,color:VX.TK[mode].accent,ink:'#021624'}); }
  try{ VX.render(cv,F,{D:A.D,N,dem:A.dem}); }catch(e){ console.error('map',id,e); }
  if(cfg.hideLine){ /* duomo: no route exists; repaint start/end only is handled by only[] */ }
};
const seen=new WeakSet(); const q=[]; let busy=false, mo=null;
const pump=()=>{ if(busy||!q.length) return; busy=true; const c=q.shift(); (async()=>{ await null; try{ if(c.isConnected&&!c.dataset.done){ c.dataset.done=1; await P4.draw(c); } }catch(e){ console.error('map',c.dataset.map,e); } finally{ busy=false; pump(); } })(); };
const scan=()=>{ document.querySelectorAll('canvas[data-map]').forEach(c=>{ if(!c.dataset.done&&!seen.has(c)){ seen.add(c); q.push(c); } }); pump(); };
P4.mount=function(){ scan(); if(!mo){ let t=null; mo=new MutationObserver(()=>{ if(t) return; t=setTimeout(()=>{ t=null; scan(); },150); }); mo.observe(document.body,{childList:true,subtree:true}); } };
window.VXP4=P4;
})();
