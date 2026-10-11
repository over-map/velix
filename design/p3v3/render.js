if(!(window.VX&&window.VX.render))(function(){
const TK=VX.TK, PAL=VX.PAL, W=VX.W, METRO=VX.METRO;
const ORIG={ milan:[9.213,45.479], monza:[9.2835,45.6085] };
const LINES = { 'Porta Venezia':['M1'],'Lima':['M1'],'Loreto':['M1','M2'],'Pasteur':['M1'],'Rovereto':['M1'],'Turro':['M1'],'Gorla':['M1'],'Palestro':['M1'],'San Babila':['M1','M4'],'Duomo':['M1','M3'],'Cordusio':['M1'],
  'Centrale FS':['M2','M3'],'Caiazzo':['M2'],'Piola':['M2'],'Lambrate FS':['M2'],'Udine':['M2'],'Cimiano':['M2'],'Crescenzago':['M2'],'Gioia':['M2'],'Garibaldi FS':['M2','M5'],
  'Sondrio':['M3'],'Repubblica':['M3'],'Turati':['M3'],'Montenapoleone':['M3'],'Zara':['M3','M5'],'Maciachini':['M3'],
  'Dateo':['M4'],'Tricolore':['M4'],'Susa':['M4'],'Argonne':['M4'],'Stazione Forlanini':['M4'],'Repetti':['M4'],'Isola':['M5'],'Marche':['M5'],'Istria':['M5'] };
const LANDMARKS = { milan:[['Unicredit Tower',9.19035,45.48395],['Palazzo Lombardia',9.19555,45.48605],['Grattacielo Pirelli',9.20135,45.48470],['Milano Centrale',9.20470,45.48590],['Bosco Verticale',9.19030,45.48565],['Politecnico di Milano',9.22720,45.47835],['Torre Galfa',9.19865,45.48455]], monza:[['Villa Reale',9.27475,45.59185]] };
const BIKE_STREETS = { 'Corso Buenos Aires':'paint','Corso Venezia':'paint','Viale Monza':'prot','Via Melchiorre Gioia':'prot','Viale Brianza':'paint','Viale Abruzzi':'paint' };
const POI_CAT = { cafe:'food',restaurant:'food',bar:'food',ice_cream:'food',bakery:'food',fast_food:'food',beer:'food', shop:'shop',grocery:'shop',clothing_store:'shop',pharmacy:'health',hospital:'health', school:'edu',college:'edu',library:'edu', museum:'culture',theatre:'culture',cinema:'culture',art_gallery:'culture',attraction:'culture',castle:'culture', place_of_worship:'worship', lodging:'lodging', park:'green',garden:'green',playground:'green',dog_park:'green',pitch:'green',sports_centre:'green',stadium:'green',swimming_pool:'green',picnic_site:'green', bicycle_parking:'bike',bicycle_rental:'bike',bicycle:'bike', drinking_water:'water', toilets:'generic', information:'generic' };
const GL = { // glyphs on a 24 grid
  food:'M8 3v7a2 2 0 0 0 4 0V3M10 10v11M17 3c-2 1-3 3-3 7h3v11',
  shop:'M6 8h12l-1 12H7zM9 8a3 3 0 0 1 6 0',
  edu:'M2 9l10-5 10 5-10 5zM6 11v5c3 2.5 9 2.5 12 0v-5',
  health:'M12 5v14M5 12h14',
  culture:'M3 9l9-5 9 5zM5 11v7M10 11v7M14 11v7M19 11v7M3 20h18',
  worship:'M12 2v6M9 5h6M6 21v-9l6-3 6 3v9z',
  lodging:'M3 18V8M3 13h18v5M21 13a3 3 0 0 0-3-3h-7v3',
  green:'M12 21v-6M12 3a5 5 0 0 0-5 5c0 3 2 6 5 6s5-3 5-6a5 5 0 0 0-5-5z',
  bike:'M5.5 17.5m-3.5 0a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M18.5 17.5m-3.5 0a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0M5.5 17.5L9 9h6l3.5 8.5M9 9l3 8.5 3-8.5M8 6h3',
  water:'M12 21a6 6 0 0 0 6-6c0-2-1-3.5-2.5-5S12.5 6 12 3c-.5 3-2 5-3.5 7S6 13 6 15a6 6 0 0 0 6 6z',
  generic:'M12 12m-3 0a3 3 0 1 0 6 0a3 3 0 1 0-6 0',
  repair:'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94z'
};
const P2D={}; for(const k in GL) P2D[k]=new Path2D(GL[k]);
const HZ = { cobbles:new Path2D('M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z'), tram:new Path2D('M8 2v20M16 2v20M3 9l18 6') };

function interp(st,z){ const ks=Object.keys(st).map(Number).sort((a,b)=>a-b); if(z<=ks[0]) return st[ks[0]]*Math.pow(1.5,(z-ks[0])*1.4); if(z>=ks[ks.length-1]) return st[ks[ks.length-1]]; for(let i=0;i<ks.length-1;i++){ const a=ks[i],b=ks[i+1]; if(z>=a&&z<=b){ const t=(Math.pow(1.5,z-a)-1)/(Math.pow(1.5,b-a)-1); return st[a]+(st[b]-st[a])*t; } } }
function hash(n){ n=(n^61)^(n>>>16); n=n+(n<<3); n=n^(n>>>4); n=Math.imul(n,0x27d4eb2d); n=n^(n>>>15); return (n>>>0)/4294967296; }
function bbOf(rs){ let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9; rs.forEach(r=>{ for(let i=0;i<r.length;i+=2){ const x=r[i],y=r[i+1]; if(x<x0)x0=x; if(x>x1)x1=x; if(y<y0)y0=y; if(y>y1)y1=y; } }); return [x0,y0,x1,y1]; }
function pip(x,y,r){ let ins=false; for(let i=0,j=r.length-2;i<r.length;j=i,i+=2){ const xi=r[i],yi=r[i+1],xj=r[j],yj=r[j+1]; if(((yi>y)!==(yj>y))&&(x<(xj-xi)*(y-yi)/(yj-yi)+xi)) ins=!ins; } return ins; }
function segDist(px,py,ax,ay,bx,by){ const dx=bx-ax,dy=by-ay; const L=dx*dx+dy*dy||1; let t=((px-ax)*dx+(py-ay)*dy)/L; t=Math.max(0,Math.min(1,t)); return Math.hypot(px-ax-t*dx,py-ay-t*dy); }
function polyLen(p){ let l=0; for(let i=2;i<p.length;i+=2) l+=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]); return l; }
function along(p,d){ let acc=0; for(let i=2;i<p.length;i+=2){ const l=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]); if(acc+l>=d){ const t=(d-acc)/l; return [p[i-2]+(p[i]-p[i-2])*t, p[i-1]+(p[i+1]-p[i-1])*t, Math.atan2(p[i+1]-p[i-1],p[i]-p[i-2])]; } acc+=l; } return [p[p.length-2],p[p.length-1],0]; }
function subLine(p,d0,d1){ const o=[]; let acc=0; const a=along(p,d0); o.push(a[0],a[1]); for(let i=2;i<p.length;i+=2){ const l=Math.hypot(p[i]-p[i-2],p[i+1]-p[i-1]); acc+=l; if(acc>d0&&acc<d1) o.push(p[i],p[i+1]); } const b=along(p,d1); o.push(b[0],b[1]); return o; }
function projOnLine(p,x,y){ let best=1e9,bd=0,acc=0; for(let i=2;i<p.length;i+=2){ const ax=p[i-2],ay=p[i-1],bx=p[i],by=p[i+1]; const dx=bx-ax,dy=by-ay,L=Math.hypot(dx,dy)||1; let t=((x-ax)*dx+(y-ay)*dy)/(L*L); t=Math.max(0,Math.min(1,t)); const d=Math.hypot(x-ax-t*dx,y-ay-t*dy); if(d<best){ best=d; bd=acc+t*L; } acc+=L; } return [bd,best]; }

// ---------- data prep ----------
function prep(raw, area){
  const u=raw.unit, o=ORIG[area], k=Math.cos(o[1]*Math.PI/180);
  const fa=a=>{ const f=new Float32Array(a.length); for(let i=0;i<a.length;i++) f[i]=a[i]*u; return f; };
  const G=g=>{ const rs=g.map(fa); return {rs,bb:bbOf(rs)}; };
  const D={ area, origin:o, lat0:o[1] };
  D.toL=(lon,lat)=>[(lon-o[0])*111320*k,(o[1]-lat)*110574];
  D.landuse=raw.landuse.map(([c,g])=>Object.assign({c},G(g)));
  D.landcover=raw.landcover.map(([c,s,g])=>Object.assign({c,s},G(g)));
  D.water=raw.water.map(([c,b,g])=>Object.assign({c,b},G(g)));
  D.waterway=raw.waterway.map(([c,n,b,g])=>Object.assign({c,n,b},G(g)));
  D.tr=raw.transportation.map(([c,s,b,sf,bi,ly,ow,g])=>Object.assign({c,s,b,sf,bi,ly},G(g)));
  D.tn=raw.transportation_name.map(([c,n,ref,g])=>Object.assign({c,n,ref},G(g)));
  D.poi=raw.poi.map(([x,y,c,s,n,r])=>({x:x*u,y:y*u,c,s,n,r}));
  D.place=raw.place.map(([x,y,c,n,r])=>({x:x*u,y:y*u,c,n,r}));
  D.hn=raw.housenumber.map(([x,y,t])=>({x:x*u,y:y*u,t}));
  D.bld=raw.building.map(([h,mh,c],i)=>{ const p=fa(c); let cx=0,cy=0,n=p.length/2; for(let j=0;j<p.length;j+=2){cx+=p[j];cy+=p[j+1];} const bb=bbOf([p]); let a=0; for(let j=0;j<p.length;j+=2){ const j2=(j+2)%p.length; a+=p[j]*p[j2+1]-p[j2]*p[j+1]; } return {h:Math.max(h,3),mh,p,cx:cx/n,cy:cy/n,bb,area:Math.abs(a)/2,id:i,v:hash(i+7)}; });
  // grid index for buildings
  const cell=80; D.grid=new Map(); D.bld.forEach(b=>{ const key=Math.floor(b.cx/cell)+','+Math.floor(b.cy/cell); if(!D.grid.has(key)) D.grid.set(key,[]); D.grid.get(key).push(b); });
  D.near=(x,y,r)=>{ const out=[]; for(let i=Math.floor((x-r)/cell);i<=Math.floor((x+r)/cell);i++) for(let j=Math.floor((y-r)/cell);j<=Math.floor((y+r)/cell);j++){ const l=D.grid.get(i+','+j); if(l) out.push(...l); } return out; };
  // landmarks
  const LMC=new Set(['attraction','castle','museum','place_of_worship','stadium','theatre']);
  D.poi.forEach(p=>{ const isSt = p.c==='railway' && p.s==='station'; if(!(LMC.has(p.c)||isSt) || !p.n) return; let hit=null; D.near(p.x,p.y,120).forEach(b=>{ if(!hit && b.bb[0]<=p.x&&b.bb[2]>=p.x&&b.bb[1]<=p.y&&b.bb[3]>=p.y && pip(p.x,p.y,b.p)) hit=b; }); if(!hit){ let bd=30; D.near(p.x,p.y,40).forEach(b=>{ const d=Math.hypot(b.cx-p.x,b.cy-p.y); if(d<bd){bd=d;hit=b;} }); }
    if(hit && (hit.area>350 || isSt || hit.h>40)){ hit.lm=true; if(!hit.name || isSt) hit.name=p.n.replace(' (superficie)',''); } });
  (LANDMARKS[area]||[]).forEach(([n,lon,lat])=>{ const [x,y]=D.toL(lon,lat); let hit=null; D.near(x,y,140).forEach(b=>{ if(!hit&&b.bb[0]<=x&&b.bb[2]>=x&&b.bb[1]<=y&&b.bb[3]>=y&&pip(x,y,b.p)) hit=b; }); if(!hit){ let bd=70; D.near(x,y,80).forEach(b=>{ const d=Math.hypot(b.cx-x,b.cy-y)-Math.sqrt(b.area)/2; if(d<bd&&b.area>200){bd=d;hit=b;} }); } if(hit){ hit.lm=true; hit.name=n; hit.cur=true; } });
  D.bld.forEach(b=>{ if(b.h>=85){ b.lm=true; } });
  D.landmarks=D.bld.filter(b=>b.lm);
  // stations
  const st={}; D.poi.filter(p=>p.c==='railway'&&p.s==='subway'&&p.n).forEach(p=>{ (st[p.n]=st[p.n]||[]).push(p); });
  D.stations=Object.keys(st).map(n=>{ const a=st[n]; return {n,x:a.reduce((s,p)=>s+p.x,0)/a.length,y:a.reduce((s,p)=>s+p.y,0)/a.length,lines:LINES[n]||[]}; });
  const rs={}; D.poi.filter(p=>p.c==='railway'&&p.s==='station'&&p.n).forEach(p=>{ rs[p.n]=rs[p.n]||p; }); D.rstations=Object.values(rs);
  // subway line assignment
  D.subway=[]; D.tr.filter(t=>t.c==='transit'&&t.s==='subway').forEach(t=>t.rs.forEach(r=>{ const mx=r[Math.floor(r.length/4)*2], my=r[Math.floor(r.length/4)*2+1];
      const ds=D.stations.filter(s=>s.lines.length).map(s=>{ let d=1e9; for(let i=2;i<r.length;i+=2) d=Math.min(d,segDist(s.x,s.y,r[i-2],r[i-1],r[i],r[i+1])); return [d,s]; }).sort((a,b)=>a[0]-b[0]);
      let line=null; const touch=ds.filter(d=>d[0]<45).map(d=>d[1]);
      if(touch.length>=2){ const c=touch[0].lines.filter(l=>touch[1].lines.includes(l)); line=c[0]||touch[0].lines[0]; }
      else { const near=ds.slice(0,2).map(d=>d[1]); const c=near[0].lines.filter(l=>near[1]&&near[1].lines.includes(l)); line=c[0]||(near[0].lines.length===1?near[0].lines[0]:null); }
      if(line) D.subway.push({line,r,bb:bbOf([r])}); }));
  // bike infra (real cycleways + curated on-road lanes)
  D.bike=[]; D.tr.filter(t=>t.c==='path'&&t.s==='cycleway'&&t.b!=='tunnel').forEach(t=>D.bike.push({k:'prot',rs:t.rs,bb:t.bb}));
  D.tn.filter(t=>BIKE_STREETS[t.n]).forEach(t=>D.bike.push({k:BIKE_STREETS[t.n],rs:t.rs,bb:t.bb}));
  D.tram=D.tr.filter(t=>t.c==='transit'&&t.s==='tram'&&t.b!=='tunnel');
  return D;
}

function prepDem(dem){ const {W:w,H:h,res,ox,oy,v}=dem; const e=new Float32Array(w*h); for(let i=0;i<v.length;i++) e[i]=v[i]/10;
  const sh=new Float32Array(w*h); const az=315*Math.PI/180, alt=45*Math.PI/180, zf=4;
  for(let j=1;j<h-1;j++) for(let i=1;i<w-1;i++){ const dzdx=((e[j*w+i+1]-e[j*w+i-1])/(2*res))*zf, dzdy=((e[(j+1)*w+i]-e[(j-1)*w+i])/(2*res))*zf; const slope=Math.atan(Math.hypot(dzdx,dzdy)); const aspect=Math.atan2(dzdy,-dzdx);
    sh[j*w+i]=Math.cos(alt)*Math.cos(slope)+Math.sin(alt)*Math.sin(slope)*Math.cos(az-Math.PI/2-aspect) - Math.cos(alt); }
  const mn=dem.min, mx=dem.max, step=5; const th=[]; for(let t=Math.ceil(mn/step)*step;t<mx;t+=step) th.push(t);
  const cs=d3.contours().size([w,h]).smooth(true).thresholds(th)(Array.from(e));
  const contours=cs.map(c=>({v:c.value, idx:c.value%25===0, rings:c.coordinates.flatMap(poly=>poly.map(ring=>{ const f=new Float32Array(ring.length*2); ring.forEach((p,i)=>{ f[i*2]=ox+p[0]*res; f[i*2+1]=oy+p[1]*res; }); return f; }))})).map(c=>Object.assign(c,{bb:bbOf(c.rings)}));
  return {w,h,res,ox,oy,sh,contours}; }

function routeL(D,coords){ const f=new Float32Array(coords.length*2); coords.forEach(([lon,lat],i)=>{ const p=D.toL(lon,lat); f[i*2]=p[0]; f[i*2+1]=p[1]; }); return f; }

function buildNav(D, routes){
  const N={};
  if(D.area==='milan'){
    N.best=routeL(D,routes.poli[1].coords); N.alt=routeL(D,routes.poli[0].coords);
    const L=polyLen(N.best); N.len=L;
    // tram crossings along best
    const hz=[]; const b=N.best;
    D.tram.forEach(t=>t.rs.forEach(r=>{ for(let i=2;i<b.length;i+=2){ const ax=b[i-2],ay=b[i-1],bx=b[i],by=b[i+1]; for(let j=2;j<r.length;j+=2){ const cx=r[j-2],cy=r[j-1],dx=r[j],dy=r[j+1]; const den=(bx-ax)*(dy-cy)-(by-ay)*(dx-cx); if(Math.abs(den)<1e-6) continue; const ta=((cx-ax)*(dy-cy)-(cy-ay)*(dx-cx))/den, tb=((cx-ax)*(by-ay)-(cy-ay)*(bx-ax))/den; if(ta>=0&&ta<=1&&tb>=0&&tb<=1){ const x=ax+(bx-ax)*ta, y=ay+(by-ay)*ta; const [d]=projOnLine(b,x,y); if(!hz.some(h=>Math.abs(h.d-d)<40)) hz.push({k:'tram',x,y,d}); } } } }));
    hz.sort((a,b)=>a.d-b.d);
    const asc=routes.poli[1].steps.find(s=>/Ascoli/.test(s.n)); if(asc){ const p=D.toL(asc.loc[0],asc.loc[1]); const [d]=projOnLine(b,p[0],p[1]); const q=along(b,d+10); hz.push({k:'cobbles',x:q[0],y:q[1],d:d+10,len:70}); }
    N.hazards=hz.slice(0,4).concat(hz.filter(h=>h.k==='cobbles')).filter((h,i,a)=>a.indexOf(h)===i);
    N.tubes=N.hazards.map(h=>subLine(b,Math.max(0,h.d-(h.len?0:14)),Math.min(L,h.d+(h.len||14))));
    // avoided: nearest long tram run beside the route that the route does not use
    let best=null; D.tram.forEach(t=>t.rs.forEach(r=>{ const l=polyLen(r); if(l<120) return; const m=along(r,l/2); const [,dist]=projOnLine(b,m[0],m[1]); if(dist>35&&dist<260){ const sc=dist-l*0.2; if(!best||sc<best.sc) best={sc,r,m}; } }));
    if(best){ let name=''; let bd=60; D.tn.forEach(t=>{ if(!t.n||t.c==='transit') return; t.rs.forEach(r=>{ for(let i=2;i<r.length;i+=2){ const d=segDist(best.m[0],best.m[1],r[i-2],r[i-1],r[i],r[i+1]); if(d<bd){bd=d;name=t.n;} } }); }); N.avoided={r:best.r,tag:[best.m[0],best.m[1]],text:'Tram rails along',street:name}; }
    const lp=along(b,L*0.18); N.loc=[lp[0],lp[1]]; N.heading=lp[2];
    N.endName='Politecnico'; N.start=[b[0],b[1]]; N.end=[b[b.length-2],b[b.length-1]];
  } else {
    N.best=routeL(D,routes.monzaTries[1].coords); N.len=polyLen(N.best); N.alt=null; N.hazards=[]; N.tubes=[];
    const lp=along(N.best,N.len*0.3); N.loc=[lp[0],lp[1]]; N.heading=lp[2]; N.start=[N.best[0],N.best[1]]; N.end=null; N.endName='Villa Reale'; N.loop=true;
  }
  return N;
}

function metroLeg(D,line,from,to){ const A=D.stations.find(s=>s.n===from), B=D.stations.find(s=>s.n===to); if(!A||!B) return null; const vx=B.x-A.x, vy=B.y-A.y, L2=vx*vx+vy*vy, L=Math.sqrt(L2);
  const pts=[]; D.subway.filter(s=>s.line===line).forEach(s=>{ const r=s.r; for(let i=0;i<r.length;i+=2){ const t=((r[i]-A.x)*vx+(r[i+1]-A.y)*vy)/L2; const off=Math.abs((r[i]-A.x)*vy-(r[i+1]-A.y)*vx)/L; if(t>0&&t<1&&off<220) pts.push([t,r[i],r[i+1]]); } });
  pts.sort((a,b)=>a[0]-b[0]); const bins=[]; const n=Math.max(6,Math.round(L/40)); for(let i=0;i<n;i++){ const sel=pts.filter(p=>p[0]>=i/n&&p[0]<(i+1)/n); if(sel.length) bins.push([sel.reduce((s,p)=>s+p[1],0)/sel.length, sel.reduce((s,p)=>s+p[2],0)/sel.length]); }
  const out=[A.x,A.y]; bins.forEach(b=>out.push(b[0],b[1])); out.push(B.x,B.y); return {r:Float32Array.from(out),line,from:A,to:B}; }

// ---------- renderer ----------
function render(cv, F, A){
  const D=A.D, N=A.N, dem=A.dem;
  const P=PAL[F.style][F.mode], T=TK[F.mode], sat=!!P.sat, od=F.style==='outdoor';
  const w=F.w, h=F.h, dpr=2; cv.width=w*dpr; cv.height=h*dpr; cv.style.width=w+'px'; cv.style.height=h+'px';
  const ctx=cv.getContext('2d'); ctx.setTransform(dpr,0,0,dpr,0,0);
  const z=F.z, pitch=(F.pitch||0)*Math.PI/180, bear=(F.bearing||0)*Math.PI/180;
  const mpp=78271.517*Math.cos(D.lat0*Math.PI/180)/Math.pow(2,z), s=1/mpp;
  const f=1.5*h, cxs=w/2, cys=h*(F.anchor||0.5);
  const c=F.c, cb=Math.cos(bear), sb=Math.sin(bear), cp=Math.cos(pitch), sp=Math.sin(pitch);
  const pr=(x,y,zz)=>{ const dx=(x-c[0])*s, dy=(y-c[1])*s; const X=dx*cb+dy*sb, Y=-dx*sb+dy*cb, Z=(zz||0)*s; let d=f-Y*sp-Z*cp; if(d<f*0.08) d=f*0.08; const k=f/d; return [cxs+X*k, cys+(Y*cp-Z*sp)*k, k, Y]; };
  const unpr=(sx,sy)=>{ const xp=sx-cxs, yp=sy-cys; let den=f*cp+yp*sp; if(den<f*0.12) den=f*0.12; const Y=yp*f/den; const X=xp*(f-Y*sp)/f; const dx=X*cb-Y*sb, dy=X*sb+Y*cb; return [c[0]+dx/s,c[1]+dy/s]; };
  const corners=[unpr(0,0),unpr(w,0),unpr(0,h),unpr(w,h),unpr(w/2,0)]; const mg=(pitch>0?140:40)+30/s;
  const vb=[Math.min(...corners.map(p=>p[0]))-mg, Math.min(...corners.map(p=>p[1]))-mg, Math.max(...corners.map(p=>p[0]))+mg, Math.max(...corners.map(p=>p[1]))+mg];
  const vis=bb=>!(bb[2]<vb[0]||bb[0]>vb[2]||bb[3]<vb[1]||bb[1]>vb[3]);
  const kAt=(x,y)=>pr(x,y)[2];
  const wz=st=>interp(st,z);
  const addRing=(r,close)=>{ for(let i=0;i<r.length;i+=2){ const p=pr(r[i],r[i+1]); i?ctx.lineTo(p[0],p[1]):ctx.moveTo(p[0],p[1]); } if(close) ctx.closePath(); };
  const fillSet=(list,color,alpha)=>{ if(!list.length||!color) return; ctx.beginPath(); list.forEach(o=>o.rs.forEach(r=>addRing(r,true))); ctx.globalAlpha=alpha==null?1:alpha; ctx.fillStyle=color; ctx.fill('evenodd'); ctx.globalAlpha=1; };
  const strokeSet=(list,color,width,opt)=>{ if(!list.length||!color||width<=0.05) return; opt=opt||{}; const buckets=new Map();
    list.forEach(o=>{ const kk=pitch>0?Math.round(Math.log2(kAt((o.bb[0]+o.bb[2])/2,(o.bb[1]+o.bb[3])/2))*5)/5:0; if(!buckets.has(kk)) buckets.set(kk,[]); buckets.get(kk).push(o); });
    ctx.strokeStyle=color; ctx.lineCap=opt.cap||'round'; ctx.lineJoin='round'; ctx.globalAlpha=opt.alpha==null?1:opt.alpha;
    buckets.forEach((arr,kk)=>{ const m=Math.pow(2,kk); ctx.lineWidth=width*m; ctx.setLineDash(opt.dash?opt.dash.map(d=>d*Math.max(.6,m)):[]); ctx.beginPath(); arr.forEach(o=>(o.rs||[o.r]).forEach(r=>addRing(r,false))); ctx.stroke(); });
    ctx.setLineDash([]); ctx.globalAlpha=1; };
  const strokeVar=(r,color,width,opt)=>{ opt=opt||{}; ctx.strokeStyle=color; ctx.lineCap=opt.cap||'round'; ctx.lineJoin='round'; ctx.globalAlpha=opt.alpha==null?1:opt.alpha; ctx.setLineDash(opt.dash||[]);
    if(pitch===0){ ctx.lineWidth=width; ctx.beginPath(); addRing(r,false); ctx.stroke(); }
    else { // split into chunks so width follows perspective
      let i=0; while(i<r.length-2){ const j=Math.min(r.length-2,i+8); const k=kAt((r[i]+r[j])/2,(r[i+1]+r[j+1])/2); ctx.lineWidth=width*k; ctx.beginPath(); for(let q=i;q<=j;q+=2){ const p=pr(r[q],r[q+1]); q===i?ctx.moveTo(p[0],p[1]):ctx.lineTo(p[0],p[1]); } ctx.stroke(); i=j; } }
    ctx.setLineDash([]); ctx.globalAlpha=1; };
  const boxes=[]; const fits=(b)=>{ if(b[0]<4||b[1]<4||b[2]>w-4||b[3]>h-4) return false; for(const o of boxes) if(!(b[2]<o[0]||b[0]>o[2]||b[3]<o[1]||b[1]>o[3])) return false; return true; };
  const reserve=b=>boxes.push(b);
  const only=F.only?new Set(F.only):null; const show=k=>!only||only.has(k);
  const routeOn=F.route!==false && N && N.best;

  // ---- background ----
  ctx.fillStyle=P.land; ctx.fillRect(0,0,w,h);
  if(sat){ const r=Math.max(6,22*s); const g=P.ground; const step=Math.max(10,30); ctx.save(); for(let i=0;i<4;i++){ ctx.fillStyle=g[i]; ctx.beginPath(); for(let y=Math.floor(vb[1]/step)*step;y<vb[3];y+=step) for(let x=Math.floor(vb[0]/step)*step;x<vb[2];x+=step){ if(Math.floor(hash((x*7919)^(y*104729))*4)!==i) continue; const a=pr(x,y),b=pr(x+step,y),cc=pr(x+step,y+step),d=pr(x,y+step); ctx.moveTo(a[0],a[1]);ctx.lineTo(b[0],b[1]);ctx.lineTo(cc[0],cc[1]);ctx.lineTo(d[0],d[1]);ctx.closePath(); } ctx.fill(); } ctx.restore(); }
  // landuse
  const LU={residential:'residential',neighbourhood:'residential',quarter:null,commercial:'commercial',retail:'retail',industrial:'industrial',railway:'railway',school:'education',college:'education',university:'education',kindergarten:'education',education:'education',library:'education',hospital:'hospital',cemetery:'cemetery',military:'military',pitch:'pitch',playground:'playground',track:'pitch',bus_station:'railway'};
  if(!sat){ const groups={}; D.landuse.forEach(l=>{ const k=LU[l.c]; if(!k||!vis(l.bb)) return; (groups[k]=groups[k]||[]).push(l); }); ['residential','commercial','retail','industrial','railway','military','education','hospital','cemetery','playground','pitch'].forEach(k=>groups[k]&&fillSet(groups[k],P[k])); if(groups.pitch&&z>=15.5) strokeSet(groups.pitch,P.pitchLine,1); }
  // landcover
  const LC=(l)=>{ if(l.c==='wood') return 'wood'; if(l.c==='farmland') return 'farmland'; if(l.c==='sand') return 'sand'; if(l.s==='scrub'||l.s==='shrubbery'||l.s==='heath') return 'scrub'; if(l.s==='meadow'||l.s==='grassland') return od?'meadow':'grass'; if(l.s==='golf_course') return od?'golf':'grass'; if(l.s==='park'||l.s==='garden'||l.s==='recreation_ground'||l.s==='village_green') return 'park'; return 'grass'; };
  { const groups={}; D.landcover.forEach(l=>{ if(!vis(l.bb)) return; const k=LC(l); (groups[k]=groups[k]||[]).push(l); }); ['farmland','grass','meadow','golf','park','scrub','sand','wood'].forEach(k=>groups[k]&&fillSet(groups[k],P[k]||P.grass));
    // tree texture inside woods and parks
    if(groups.wood||groups.park){ const trees=[]; const sp2=z>=16?9:z>=14?18:36; (groups.wood||[]).concat(z>=15?(groups.park||[]):[]).forEach(l=>{ const r=l.rs[0]; if(!r) return; const bb=l.bb; for(let y=Math.ceil(bb[1]/sp2)*sp2;y<bb[3];y+=sp2) for(let x=Math.ceil(bb[0]/sp2)*sp2;x<bb[2];x+=sp2){ const jx=x+(hash(x*31+y)-.5)*sp2*.8, jy=y+(hash(y*17+x)-.5)*sp2*.8; if(jx<vb[0]||jx>vb[2]||jy<vb[1]||jy>vb[3]) continue; if(pip(jx,jy,r)) trees.push([jx,jy,l.c==='wood']); } });
      ctx.fillStyle=P.woodDot; ctx.beginPath(); trees.forEach(([x,y,wd])=>{ const p=pr(x,y); const rr=(z>=16?2.2:z>=14?1.5:1)*p[2]*(wd?1:.8); ctx.moveTo(p[0]+rr,p[1]); ctx.arc(p[0],p[1],rr,0,Math.PI*2); }); ctx.globalAlpha=sat?.9:.55; ctx.fill(); ctx.globalAlpha=1; } }
  // hillshade + contours (outdoor)
  if(od && dem){ const {w:gw,h:gh,res,ox,oy,sh}=dem; const nb=10; const paths=[]; for(let b=0;b<nb;b++) paths.push(new Path2D());
    const i0=Math.max(1,Math.floor((vb[0]-ox)/res)), i1=Math.min(gw-2,Math.ceil((vb[2]-ox)/res)), j0=Math.max(1,Math.floor((vb[1]-oy)/res)), j1=Math.min(gh-2,Math.ceil((vb[3]-oy)/res));
    for(let j=j0;j<j1;j++) for(let i=i0;i<i1;i++){ const v=sh[j*gw+i]; const b=Math.max(0,Math.min(nb-1,Math.floor((v+0.25)/0.5*nb))); const x=ox+i*res, y=oy+j*res; const a=pr(x,y),bq=pr(x+res,y),cq=pr(x+res,y+res),d=pr(x,y+res); const P2=paths[b]; P2.moveTo(a[0],a[1]);P2.lineTo(bq[0],bq[1]);P2.lineTo(cq[0],cq[1]);P2.lineTo(d[0],d[1]);P2.closePath(); }
    paths.forEach((p2,b)=>{ const t=(b+.5)/nb-0.5; ctx.fillStyle=t<0?`rgba(${P.shadeDark},${(-t*0.55).toFixed(3)})`:`rgba(${P.shadeLight},${(t*0.5).toFixed(3)})`; ctx.fill(p2); });
    const cw=z>=15?.9:.7; dem.contours.forEach(cn=>{ if(!vis(cn.bb)) return; strokeSet([{rs:cn.rings,bb:cn.bb}],cn.idx?P.contourIdx:P.contour,cn.idx?cw*1.5:cw); }); }
  // water
  { const wl=D.water.filter(x=>vis(x.bb)&&x.b!=='tunnel'); fillSet(wl,P.water); if(!sat) strokeSet(wl,P.waterLine,z>=15?1:.6,{alpha:.7}); strokeSet(D.waterway.filter(x=>vis(x.bb)&&x.b!=='tunnel'),P.water,wz(W.water)); }
  // roads
  const ROAD={motorway:'motor',trunk:'motor',primary:'primary',secondary:'secondary',tertiary:'tertiary',minor:'minor',busway:'minor',service:'service',raceway:'service'};
  const trv=D.tr.filter(t=>vis(t.bb));
  const order=['service','minor','tertiary','secondary','primary','motor'];
  const byCls=(b)=>{ const g={}; trv.forEach(t=>{ const k=ROAD[t.c]; if(!k) return; if((t.b==='bridge')!==(b==='bridge')) return; if((t.b==='tunnel')!==(b==='tunnel')) return; (g[k]=g[k]||[]).push(t); }); return g; };
  const roadCol=k=>sat?P.road:k==='tertiary'?P.secondary:P[k]; const caseCol=k=>sat?P.roadEdge:k==='tertiary'?P.secondaryCase:P[k+'Case'];
  const wRoad=k=>wz(W[k==='motor'?'motor':k]);
  if(z>=14.5 && !sat){ const g=byCls('tunnel'); order.forEach(k=>g[k]&&strokeSet(g[k],P.tunnel,wRoad(k),{alpha:.8})); }
  // pedestrian streets + paths below roads
  const ped=trv.filter(t=>t.c==='path'&&t.s==='pedestrian'&&t.b!=='tunnel');
  if(z>=14&&!sat){ strokeSet(ped,P.pedCase,wz(W.ped)+wz(W.caseAdd)); strokeSet(ped,P.pedFill,wz(W.ped)); }
  const surf=byCls('');
  const chartLow=!!P.chartLine && z<P.fillFrom;
  if(chartLow){ const fade=Math.max(0,Math.min(1,(P.fillFrom-z)/0.5)); order.forEach(k=>{ if(surf[k]) strokeSet(surf[k],P.chartLine,wRoad(k)*P.chartW+wz(W.caseAdd),{alpha:(P.chartAlpha[k]||.6)}); }); }
  else { order.forEach(k=>{ const cc=caseCol(k); if(surf[k]&&cc && (z>=13.5||k==='primary'||k==='motor')) strokeSet(surf[k],cc,wRoad(k)+wz(W.caseAdd)*(k==='primary'||k==='motor'?1.3:1)); }); order.forEach(k=>surf[k]&&strokeSet(surf[k],roadCol(k),wRoad(k))); }
  if(z>=15&&!sat){ const fw=trv.filter(t=>t.c==='path'&&(t.s==='footway'||t.s==='path')&&t.b!=='tunnel'); strokeSet(fw,P.path,wz(W.path),{dash:[1,2.4],alpha:P.chartLine?.7:1}); const stp=trv.filter(t=>t.c==='path'&&t.s==='steps'&&t.b!=='tunnel'); strokeSet(stp,P.steps,wz(W.steps)*2.2,{dash:[1,1.6],cap:'butt'}); }
  const cons=trv.filter(t=>/_construction/.test(t.c)); if(z>=15&&!sat) strokeSet(cons,P.construction,wz(W.minor),{dash:[4,3]});
  // outdoor tracks & paths
  if(od){ const tk=trv.filter(t=>t.c==='track'); const paved=tk.filter(t=>t.sf==='paved'), unp=tk.filter(t=>t.sf!=='paved'); strokeSet(tk,P.trackCase,wz(W.track)+1.6,{alpha:.9}); strokeSet(paved,P.track,wz(W.track)); strokeSet(unp,P.track,wz(W.track),{dash:[5,3],cap:'butt'});
    const pth=trv.filter(t=>t.c==='path'&&(t.s==='path'||t.s==='footway'||t.s==='bridleway')); strokeSet(pth,P.track,wz(W.mpath),{dash:[.1,3.6]}); }
  // rail + tram
  const rail=trv.filter(t=>t.c==='rail'&&t.b!=='tunnel'); strokeSet(rail,P.rail,wz(W.rail)); if(z>=14) strokeSet(rail,P.rail,wz(W.rail)*3,{dash:[1,6],cap:'butt'});
  if(z>=14){ const tr=D.tram.filter(t=>vis(t.bb)); const tw=wz(W.tram); strokeSet(tr,P.tram,tw); if(tw>2.2) strokeSet(tr,sat?P.road:P.minor,tw-1.6); }
  // bridges
  { const g=byCls('bridge'); order.forEach(k=>{ if(g[k]&&chartLow){ strokeSet(g[k],P.chartLine,wRoad(k)*P.chartW+wz(W.caseAdd)*2,{alpha:P.chartAlpha[k]||.6}); return; } if(g[k]){ strokeSet(g[k],sat?P.roadEdge:(P[k+'Case']||P.secondaryCase||P.edge),wRoad(k)+wz(W.caseAdd)*2); strokeSet(g[k],roadCol(k),wRoad(k)); } }); }
  // cycling infra
  const bikeOn=F.bike || (!sat && z>=14);
  if(bikeOn && D.bike){ const bw=wz(W.bike)*(F.bike?1:0.7); const ba=F.bike?1:0.8; const bl=D.bike.filter(b=>vis(b.bb)); if(sat) strokeSet(bl,'#FFFFFF',bw+3); strokeSet(bl.filter(b=>b.k==='prot'),T.prot,bw,{alpha:ba}); const pl=bl.filter(b=>b.k==='paint'); strokeSet(pl,T.paint,bw); if(bw>=2) strokeSet(pl,T.tick,bw*.8,{dash:[2,7],cap:'butt'}); }
  // transit overlay
  const tOp=(routeOn&&show('best'))?0.6:1;
  if(F.transit){ const mw=wz(W.metro); const sub=D.subway.filter(s=>vis(s.bb));
    const pass=trv.filter(t=>t.c==='rail'&&t.b==='tunnel');
    strokeSet(pass,F.mode==='day'?'#FFFFFF':'#000000',mw+1.5,{alpha:tOp}); strokeSet(pass,T.train,mw,{dash:[6,4],cap:'butt',alpha:tOp});
    strokeSet(rail,T.train,mw+.4,{alpha:tOp});
    strokeSet(sub.map(s=>({r:s.r,bb:s.bb})),T.metroCase,mw+1.5,{alpha:tOp}); Object.keys(METRO).forEach(l=>strokeSet(sub.filter(s=>s.line===l).map(s=>({r:s.r,bb:s.bb})),METRO[l],mw,{alpha:tOp})); }
  // ---- buildings (2.5D) ----
  const bShow = z>=13.6;
  if(bShow){ const bl=D.bld.filter(b=>vis(b.bb)); const ex = (pitch>0 || z>=15) ; const hs=Math.min(1,Math.max(0,(z-14.6)/1.2));
    // cast shadows
    if(z>=15 && P.shadow){ const sx=0.55, sy=0.75; ctx.beginPath(); bl.forEach(b=>{ const L=(b.h-b.mh)*hs; if(L<2) return; [0.33,0.66,1].forEach(t=>{ const r=b.p; for(let i=0;i<r.length;i+=2){ const p=pr(r[i]+sx*L*t,r[i+1]+sy*L*t); i?ctx.lineTo(p[0],p[1]):ctx.moveTo(p[0],p[1]); } ctx.closePath(); }); }); ctx.fillStyle=P.shadow; ctx.fill('nonzero'); }
    const keyed=bl.map(b=>{ const q=pr(b.cx,b.cy); return [pitch>0?q[3]:b.h, b]; }).sort((a,b2)=>a[0]-b2[0]);
    if(!ex){ // flat roofs batched
      const groups=[[],[],[],[]], lm=[]; keyed.forEach(([,b])=>{ (b.lm?lm:groups[Math.floor(b.v*4)]).push({rs:[b.p],bb:b.bb}); }); groups.forEach((g,i)=>fillSet(g,P.roof[i])); fillSet(lm,P.lmRoof); if(z>=14.2) strokeSet(groups.flat().concat(lm),P.wallD,.4,{alpha:.5}); }
    else { const lx=-0.55, ly=-0.83; ctx.lineJoin='round';
      keyed.forEach(([,b])=>{ const H=b.mh+(b.h-b.mh)*(b.lm?1:hs); const r=b.p, n=r.length/2; const base=new Array(n), top=new Array(n); for(let i=0;i<n;i++){ base[i]=pr(r[i*2],r[i*2+1],b.mh*hs); top[i]=pr(r[i*2],r[i*2+1],H); }
        const wl=b.lm?[P.lmWallL,P.lmWallM,P.lmWallD]:[P.wallL,P.wallM,P.wallD]; const wp=[new Path2D(),new Path2D(),new Path2D()]; let any=false;
        if(H-b.mh*hs>0.5) for(let i=0;i<n;i++){ const j=(i+1)%n; const a=base[i],bb=base[j],tb=top[j],ta=top[i]; const ar=(bb[0]-a[0])*(ta[1]-a[1])-(bb[1]-a[1])*(ta[0]-a[0]); if(ar>=0) continue; const ex2=r[j*2]-r[i*2], ey2=r[j*2+1]-r[i*2+1]; const L=Math.hypot(ex2,ey2)||1; const nx=ey2/L, ny=-ex2/L; const d=-(nx*lx+ny*ly); const bi=d>0.35?0:d>-0.35?1:2; const p2=wp[bi]; p2.moveTo(a[0],a[1]); p2.lineTo(bb[0],bb[1]); p2.lineTo(tb[0],tb[1]); p2.lineTo(ta[0],ta[1]); p2.closePath(); any=true; }
        if(any){ for(let i=0;i<3;i++){ ctx.fillStyle=wl[i]; ctx.fill(wp[i]); } }
        ctx.beginPath(); for(let i=0;i<n;i++){ i?ctx.lineTo(top[i][0],top[i][1]):ctx.moveTo(top[i][0],top[i][1]); } ctx.closePath(); ctx.fillStyle=b.lm?P.lmRoof:P.roof[Math.floor(b.v*P.roof.length)]; ctx.fill(); if(z>=15.2||b.lm){ ctx.strokeStyle=b.lm?P.lmEdge:P.edge; ctx.lineWidth=b.lm?1.1:.6; ctx.stroke(); } }); } }
  if(sat && P.dim){ ctx.fillStyle=`rgba(5,8,12,${P.dim})`; ctx.fillRect(0,0,w,h); }
  if(pitch>0){ const g=ctx.createLinearGradient(0,0,0,h*0.2); const sky=F.mode==='day'?(sat?'200,210,220':'236,238,228'):'2,22,36'; g.addColorStop(0,`rgba(${sky},.95)`); g.addColorStop(0.4,`rgba(${sky},.5)`); g.addColorStop(1,`rgba(${sky},0)`); ctx.fillStyle=g; ctx.fillRect(0,0,w,h*0.2); }
  // ---- road labels (below route) ----
  const font=(wt,sz)=>`${wt} ${sz}px "Atkinson Hyperlegible", sans-serif`;
  const lineLabel=(r,text,sz,fill,halo,wt)=>{ const pts=[]; for(let i=0;i<r.length;i+=2){ const p=pr(r[i],r[i+1]); pts.push(p); } let best=null,cur=[]; pts.forEach(p=>{ if(p[0]>8&&p[0]<w-8&&p[1]>8&&p[1]<h-8){ cur.push(p); } else { if(!best||cur.length>best.length) best=cur; cur=[]; } }); if(!best||cur.length>best.length) best=cur; if(!best||best.length<2) return false;
    let P2=best; if(P2[P2.length-1][0]<P2[0][0]) P2=P2.slice().reverse(); const seg=[]; let tot=0; for(let i=1;i<P2.length;i++){ const l=Math.hypot(P2[i][0]-P2[i-1][0],P2[i][1]-P2[i-1][1]); seg.push(l); tot+=l; }
    ctx.font=font(wt||400,sz); const tw=ctx.measureText(text).width; if(tot<tw+30) return false; let s0=(tot-tw)/2; const chars=[]; let acc=0,si=0; const posAt=d=>{ while(si<seg.length-1&&acc+seg[si]<d){ acc+=seg[si]; si++; } const t=(d-acc)/seg[si]; const a=P2[si],b=P2[si+1]; return [a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t,Math.atan2(b[1]-a[1],b[0]-a[0])]; };
    let x=s0, prevA=null, ok=true; const bx=[]; for(const ch of text){ const cw=ctx.measureText(ch).width; const p=posAt(x+cw/2); if(prevA!=null && Math.abs(((p[2]-prevA+Math.PI*3)%(Math.PI*2))-Math.PI)<Math.PI*0.78) { ok=false; break; } prevA=p[2]; chars.push([ch,p,cw]); bx.push([p[0]-sz*.55,p[1]-sz*.55,p[0]+sz*.55,p[1]+sz*.55]); x+=cw; }
    if(!ok) return false; const all=[Math.min(...bx.map(b=>b[0])),Math.min(...bx.map(b=>b[1])),Math.max(...bx.map(b=>b[2])),Math.max(...bx.map(b=>b[3]))]; if(!bx.every(b=>fits(b))) return false; bx.forEach(reserve);
    ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.lineJoin='round'; chars.forEach(([ch,p])=>{ ctx.save(); ctx.translate(p[0],p[1]); ctx.rotate(p[2]); ctx.strokeStyle=halo; ctx.lineWidth=3; ctx.strokeText(ch,0,0); ctx.fillStyle=fill; ctx.fillText(ch,0,0); ctx.restore(); }); return true; };
  const roadLabels=()=>{ if(z<14.6||F.labels===false) return; const allow=z>=16?['primary','secondary','tertiary','minor','path','trunk']:z>=15.2?['primary','secondary','tertiary','minor','trunk']:['primary','secondary','trunk'];
    const cand=D.tn.filter(t=>t.n&&allow.includes(t.c)&&vis(t.bb)).sort((a,b)=>allow.indexOf(a.c)-allow.indexOf(b.c)); const done=new Set();
    const sz=z>=17?13:z>=16?12:11; cand.forEach(t=>{ if(done.has(t.n)&&z<16.5) return; const r=t.rs.reduce((a,b)=>b.length>a.length?b:a); if(lineLabel(r,t.n,sz,t.c==='minor'||t.c==='path'?P.labelMinor:P.label,P.halo,t.c==='primary'?700:400)) done.add(t.n); }); };
  roadLabels();
  // ---- route stack ----
  const hp=(()=>{ const sz=Math.max(8,10*Math.max(.8,s/0.6)); const c2=document.createElement('canvas'); c2.width=c2.height=20; const g=c2.getContext('2d'); g.fillStyle=T.hazardRing; g.fillRect(0,0,20,20); g.fillStyle=T.hazard; g.beginPath(); g.moveTo(0,0); g.lineTo(10,0); g.lineTo(0,10); g.closePath(); g.moveTo(20,0); g.lineTo(20,10); g.lineTo(10,20); g.lineTo(0,20); g.closePath(); g.fill(); return ctx.createPattern(c2,'repeat'); })();
  if(routeOn){
    if(N.avoided && show('avoided') && F.avoided!==false){ if(sat) strokeVar(N.avoided.r,'#FFFFFF',wz(W.avoided)+3); strokeVar(N.avoided.r,T.avoided,wz(W.avoided),{dash:[7,6],cap:'butt'}); }
    if(N.alts && show('alt') && F.altsAccent){ const rw=Math.max(wz(W.route),F.minRoute||0); const ord=N.alts.map((x,i)=>i).filter(i=>i!==N.altSel); if(N.altSel!=null) ord.push(N.altSel); ord.forEach(i=>{ const a=N.alts[i]; if(i===N.altSel){ strokeVar(a,sat?'#FFFFFF':T.surface,rw+9); strokeVar(a,T.casing,rw+5); strokeVar(a,T.accent,rw+2); } else if(N.altSel!=null){ strokeVar(a,T.casing,rw*.6+2); strokeVar(a,T.accent,rw*.6); } else { if(sat) strokeVar(a,'#FFFFFF',rw+6); strokeVar(a,T.casing,rw+3); strokeVar(a,T.accent,rw); } }); }
    else if(N.alts && show('alt')) N.alts.forEach(a=>{ if(false){ } else { strokeVar(a,sat?'#FFFFFF':T.altCase,Math.max(wz(W.altCase),F.minRoute?F.minRoute+1:0)); strokeVar(a,T.routeAlt,Math.max(wz(W.alt),F.minRoute?F.minRoute-2:0)); } });
    if(N.alt && show('alt') && F.alt!==false){ strokeVar(N.alt,sat?'#FFFFFF':T.altCase,wz(W.altCase)+(sat?1:0)); strokeVar(N.alt,T.routeAlt,wz(W.alt)); }
    if(show('best')&&!F.noLine){ [N.best].concat(N.more||[]).forEach(bl=>{ if(sat) strokeVar(bl,'#FFFFFF',wz(W.routeCase)+3); strokeVar(bl,T.casing,Math.max(wz(W.routeCase),F.minRoute?F.minRoute+3:0)); strokeVar(bl,T.accent,Math.max(wz(W.route),F.minRoute||0)); }); }
    if(show('hazard') && F.hazards!==false) N.tubes.forEach(t=>strokeVar(t,hp,wz(W.tube),{cap:'butt'}));
    if(z>=15.8 && show('best') && !F.noLine){ const b=N.best; const L=polyLen(b); ctx.strokeStyle=T.accentInk; ctx.lineWidth=2; ctx.lineCap='round'; ctx.lineJoin='round'; const stepM=70/s; for(let d=stepM*0.6; d<L; d+=stepM){ const a=along(b,d), a2=along(b,d+0.5/s); const p=pr(a[0],a[1]), q=pr(a2[0],a2[1]); if(p[0]<0||p[0]>w||p[1]<0||p[1]>h) continue; const ang=Math.atan2(q[1]-p[1],q[0]-p[0]); const k=p[2]; ctx.save(); ctx.translate(p[0],p[1]); ctx.rotate(ang); ctx.scale(k,k); ctx.beginPath(); ctx.moveTo(-3,-3.6); ctx.lineTo(1.6,0); ctx.lineTo(-3,3.6); ctx.stroke(); ctx.restore(); } }
  }
  if(F.leg){ const lg=F.leg; if(lg.asRoute){ const rw=Math.max(wz(W.route),F.minRoute||0), cw=Math.max(wz(W.routeCase),F.minRoute?F.minRoute+3:0); if(sat) strokeVar(lg.r,'#FFFFFF',cw+3); strokeVar(lg.r,T.casing,cw); strokeVar(lg.r,T.accent,rw); strokeVar(lg.r,T.casing,Math.max(1.6,rw*.34),{dash:[rw*1.1,rw*.9],cap:'butt'}); } else { const lw=wz(W.leg); strokeVar(lg.r,T.metroCase,lw+2); strokeVar(lg.r,F.mode==='day'?'#FFFFFF':'#1E2125',lw); strokeVar(lg.r,lg.color||METRO[lg.line],lw,{dash:[10,4],cap:'butt'}); } }
  // ---- stations, POIs, places, landmark labels ----
  const label=(x,y,text,sz,wt,fill,align,dy,caps,prio)=>{ ctx.font=font(wt,sz); if(caps){ try{ ctx.letterSpacing='0.08em'; }catch(e){} } const tw=ctx.measureText(text).width; let bx0=align==='left'?x:align==='right'?x-tw:x-tw/2; const by=y+(dy||0); const b=[bx0-2,by-sz*.7,bx0+tw+2,by+sz*.45]; if(!fits(b)){ if(caps) try{ctx.letterSpacing='0px';}catch(e){} return false; } reserve(b); ctx.textAlign=align||'center'; ctx.textBaseline='alphabetic'; ctx.lineJoin='round'; ctx.strokeStyle=P.halo; ctx.lineWidth=sat?3.5:3; ctx.strokeText(text,x,by); ctx.fillStyle=fill; ctx.fillText(text,x,by); if(caps) try{ctx.letterSpacing='0px';}catch(e){} return true; };
  const icon=(x,y,cat,r)=>{ ctx.globalAlpha=P.poiAlpha||1; const col=cat==='bike'?T.prot:cat==='water'?P.poi.water:P.poi[cat]||P.poi.generic; ctx.beginPath(); ctx.arc(x,y,r,0,Math.PI*2); ctx.fillStyle=col; ctx.fill(); ctx.lineWidth=1.2; ctx.strokeStyle=sat?'#FFFFFF':P.halo; ctx.stroke(); const g=cat==='bike'?null:P2D[cat]; ctx.save(); ctx.translate(x-r*.62,y-r*.62); ctx.scale(r*1.24/24,r*1.24/24); if(cat==='bike'){ ctx.fillStyle='#FFFFFF'; ctx.font='700 19px "Atkinson Hyperlegible",sans-serif'; ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText('P',12,13); } else if(g){ ctx.strokeStyle=P.glyph; ctx.lineWidth=2.6; ctx.lineCap='round'; ctx.lineJoin='round'; ctx.stroke(g); } ctx.restore(); ctx.globalAlpha=1; };
  const markers=[]; const keyB=[]; if(routeOn && N.keys) N.keys.forEach(k=>{ const p=pr(k.x,k.y); reserve([p[0]-14,p[1]-14,p[0]+14,p[1]+14]); keyB.push([p,k]); });
  // hazard + endpoints reserve first (priority)
  if(routeOn && show('hazard') && F.hazards!==false) N.hazards.forEach(hz=>{ const p=pr(hz.x,hz.y); const m=(z>=16.5?28:z>=14.5?22:16); markers.push(['hz',p,m,hz.k]); reserve([p[0]-m/2,p[1]-m-8,p[0]+m/2,p[1]]); });
  if(routeOn && show('best')){ const sp0=pr(N.start[0],N.start[1]); reserve([sp0[0]-10,sp0[1]-10,sp0[0]+10,sp0[1]+10]); if(N.end){ const ep=pr(N.end[0],N.end[1]); reserve([ep[0]-12,ep[1]-12,ep[0]+12,ep[1]+12]); } }
  if(routeOn && N.avoided && show('avoided') && F.avoided!==false && z>=14){ const p=pr(N.avoided.tag[0],N.avoided.tag[1]); ctx.font=font(700,12); const tw=ctx.measureText(N.avoided.text).width+34; reserve([p[0]-tw/2,p[1]-13,p[0]+tw/2,p[1]+13]); markers.push(['av',p,tw]); }
  if(F.labels!==false){
    // landmarks
    if(z>=14.4) D.landmarks.filter(b=>b.name&&vis(b.bb)).sort((a,b)=>b.h-a.h).forEach(b=>{ const H=b.mh+(b.h-b.mh)*(pitch>0||z>=15?Math.max(0.6,Math.min(1,(z-14.6)/1.2)):0); const p=pr(b.cx,b.cy,H); label(p[0],p[1]-6,b.name,12,700,P.lmInk,'center'); });
    // metro stations
    const stOn = F.transit ? z>=12.5 : z>=14.6;
    if(stOn){ const rr=z>=16?6:z>=15?5:4; D.stations.filter(s=>s.x>vb[0]&&s.x<vb[2]&&s.y>vb[1]&&s.y<vb[3]).forEach(st=>{ const p=pr(st.x,st.y); if(p[0]<0||p[0]>w||p[1]<0||p[1]>h) return; const lines=st.lines.length?st.lines:['M1']; 
        const bw=lines.length*(rr*2.6)+2; const b=[p[0]-bw/2,p[1]-rr-2,p[0]+bw/2,p[1]+rr+2]; if(!fits(b)) return; reserve(b);
        ctx.globalAlpha=F.transit?Math.max(tOp,.85):1; lines.forEach((l,i)=>{ const x=p[0]-bw/2+1+i*rr*2.6+rr*1.3; ctx.beginPath(); ctx.roundRect(x-rr*1.15,p[1]-rr*1.15,rr*2.3,rr*2.3,rr*.55); ctx.fillStyle=METRO[l]; ctx.fill(); ctx.lineWidth=1.4; ctx.strokeStyle=l==='M3'?'#16181B':(sat?'#FFFFFF':P.halo); ctx.stroke(); if(rr>=5){ ctx.fillStyle=VX.METRO_INK[l]; ctx.font=font(700,rr*1.25); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText(l.slice(1),x,p[1]+.5); } }); ctx.globalAlpha=1;
        if(z>=(F.transit?14:15.2)) label(p[0]+bw/2+3,p[1]+4,st.n,z>=16?12:11,700,P.placeMajor,'left'); }); }
    // rail stations
    if(z>=13.5) D.rstations.filter(s=>s.x>vb[0]&&s.x<vb[2]&&s.y>vb[1]&&s.y<vb[3]&&!/passante/.test(s.n)).forEach(st=>{ const p=pr(st.x,st.y); const b=[p[0]-8,p[1]-8,p[0]+8,p[1]+8]; if(!fits(b)) return; reserve(b); ctx.beginPath(); ctx.roundRect(p[0]-7,p[1]-7,14,14,3.5); ctx.fillStyle=T.train; ctx.fill(); ctx.strokeStyle=P.halo; ctx.lineWidth=1.4; ctx.stroke(); ctx.fillStyle='#FFFFFF'; ctx.font=font(700,9); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText('FS',p[0],p[1]+.5); label(p[0]+11,p[1]+4,st.n.replace('Milano ',''),11,700,P.placeMajor,'left'); });
    // places
    D.place.filter(pl=>pl.n&&pl.x>vb[0]&&pl.x<vb[2]&&pl.y>vb[1]&&pl.y<vb[3]).sort((a,b)=>(a.c==='suburb'?0:1)-(b.c==='suburb'?0:1)).forEach(pl=>{ const big=pl.c==='suburb'||pl.c==='city'; const lo=big?11.5:13.8, hi=big?15.6:16.4; if(z<lo||z>hi||pl.c==='city'||pl.c==='island') return; const p=pr(pl.x,pl.y); label(p[0],p[1],pl.n.toUpperCase(),big?12:10.5,700,big?P.place:P.labelMinor,'center',0,true); });
    // park / water names
    if(z>=14.5) D.poi.filter(p=>(p.c==='park')&&p.n&&p.x>vb[0]&&p.x<vb[2]&&p.y>vb[1]&&p.y<vb[3]).forEach(p0=>{ const p=pr(p0.x,p0.y); label(p[0],p[1],p0.n,11.5,400,P.parkInk,'center'); });
    // POIs
    if(z>=15.6){ const r=z>=17?8:6.5; const cand=D.poi.filter(p=>p.x>vb[0]&&p.x<vb[2]&&p.y>vb[1]&&p.y<vb[3]&&POI_CAT[p.c]&&(p.n||['bike','water'].includes(POI_CAT[p.c]))).sort((a,b)=>a.r-b.r);
      cand.forEach(p0=>{ const cat=POI_CAT[p0.c]; if(z<16.4 && !['bike','water','culture','worship','edu','health'].includes(cat)) return; const p=pr(p0.x,p0.y); const b=[p[0]-r-1,p[1]-r-1,p[0]+r+1,p[1]+r+1]; if(!fits(b)) return; reserve(b); icon(p[0],p[1],cat,r); if(z>=16.8 && p0.n) label(p[0]+r+3,p[1]+4,p0.n,11,400,P.poiInk,'left'); }); }
    if(z>=17.6) D.hn.filter(n=>n.x>vb[0]&&n.x<vb[2]&&n.y>vb[1]&&n.y<vb[3]).forEach(n=>{ const p=pr(n.x,n.y); label(p[0],p[1]+3,n.t,9.5,400,P.hn,'center'); });
  }
  // ---- nav markers on top ----
  if(routeOn && show('best') && F.endpoints!==false){ const sp0=pr(N.start[0],N.start[1]); const r=z>=16?8:z>=14?6.5:5.5; ctx.beginPath(); ctx.arc(sp0[0],sp0[1],r,0,Math.PI*2); ctx.fillStyle='#FFFFFF'; ctx.fill(); ctx.lineWidth=3; ctx.strokeStyle=T.casing; ctx.stroke();
    if(N.loop && F.labels!==false){ label(sp0[0]+r+5,sp0[1]+4,N.endName,13,700,P.lmInk||P.label,'left'); }
    if(N.end){ const ep=pr(N.end[0],N.end[1]); const R=z>=16?11:z>=14?9.5:8; ctx.beginPath(); ctx.arc(ep[0],ep[1],R,0,Math.PI*2); ctx.fillStyle=T.casing; ctx.fill(); ctx.lineWidth=2; ctx.strokeStyle='#FFFFFF'; ctx.stroke(); ctx.beginPath(); ctx.arc(ep[0],ep[1],R*.42,0,Math.PI*2); ctx.fillStyle=T.accent; ctx.fill(); if(F.labels!==false){ ctx.font=font(700,13); ctx.textAlign='center'; ctx.lineJoin='round'; ctx.strokeStyle=P.halo; ctx.lineWidth=3.5; ctx.strokeText(N.endName,ep[0],ep[1]-R-7); ctx.fillStyle=sat?'#FFFFFF':P.lmInk; ctx.fillText(N.endName,ep[0],ep[1]-R-7); } } }
  if(F.leg){ const lg=F.leg; [lg.from,lg.to].forEach(st=>{ const p=pr(st.x,st.y); (lg.asRoute?[[9.5,T.casing],[7,T.accent],[3,T.casing]]:[[9,T.casing],[7,lg.color||METRO[lg.line]],[4,'#FFFFFF']]).forEach(([rr,c])=>{ ctx.beginPath(); ctx.arc(p[0],p[1],rr,0,Math.PI*2); ctx.fillStyle=c; ctx.fill(); }); }); const m=along(lg.r,polyLen(lg.r)/2); const p=pr(m[0],m[1]); ctx.beginPath(); ctx.roundRect(p[0]-16,p[1]-11,32,22,6); ctx.fillStyle=lg.color||METRO[lg.line]; ctx.fill(); ctx.lineWidth=lg.asRoute?2.2:1.6; ctx.strokeStyle=lg.asRoute?T.casing:T.metroCase; ctx.stroke(); ctx.fillStyle=lg.ink||VX.METRO_INK[lg.line]; ctx.font=font(700,13); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText(lg.label||lg.line,p[0],p[1]+.5); }
  keyB.forEach(([p,k])=>{ ctx.beginPath(); ctx.roundRect(p[0]-12,p[1]-12,24,24,7); ctx.fillStyle=k.sel?T.accent:T.surface; ctx.fill(); ctx.lineWidth=2; ctx.strokeStyle=k.sel?T.casing:T.ink; ctx.stroke(); ctx.fillStyle=k.sel?T.accentInk:T.ink; ctx.font=font(700,14); ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText(String(k.n),p[0],p[1]+.5); });
  markers.forEach(mk=>{ if(mk[0]==='hz'){ const [,p,m,k]=mk; const x=p[0]-m/2, y=p[1]-m-6; ctx.beginPath(); ctx.moveTo(p[0]-4.5,y+m); ctx.lineTo(p[0],y+m+5.5); ctx.lineTo(p[0]+4.5,y+m); ctx.closePath(); ctx.fillStyle=T.hazardRing; ctx.fill(); ctx.beginPath(); ctx.roundRect(x,y,m,m,5); ctx.fillStyle=T.hazard; ctx.fill(); ctx.lineWidth=2; ctx.strokeStyle=sat?'#FFFFFF':T.hazardRing; ctx.stroke(); ctx.save(); ctx.translate(x+m*.16,y+m*.16); ctx.scale(m*.68/24,m*.68/24); ctx.strokeStyle=T.hazardInk; ctx.lineWidth=2.4; ctx.lineCap='round'; ctx.lineJoin='round'; ctx.stroke(HZ[k]); ctx.restore(); }
    else if(mk[0]==='av'){ const [,p,tw]=mk; ctx.beginPath(); ctx.roundRect(p[0]-tw/2,p[1]-12,tw,24,12); ctx.fillStyle=T.surface; ctx.fill(); ctx.lineWidth=1.6; ctx.strokeStyle=T.avoided; ctx.stroke(); const x0=p[0]-tw/2; ctx.strokeStyle=T.avoidedInk; ctx.lineWidth=2; ctx.lineCap='round'; ctx.beginPath(); ctx.moveTo(x0+11,p[1]-4); ctx.lineTo(x0+19,p[1]+4); ctx.moveTo(x0+19,p[1]-4); ctx.lineTo(x0+11,p[1]+4); ctx.stroke(); ctx.fillStyle=T.avoidedInk; ctx.font=font(700,12); ctx.textAlign='left'; ctx.textBaseline='middle'; ctx.fillText(N.avoided.text,x0+25,p[1]+.5); } });
  if(routeOn && show('loc') && F.puck!==false){ const q=pr(N.loc[0],N.loc[1]); const hd=N.heading; const ah=pr(N.loc[0]+Math.cos(hd)*5,N.loc[1]+Math.sin(hd)*5); const sa=Math.atan2(ah[1]-q[1],ah[0]-q[0]);
    if(F.follow){ ctx.save(); ctx.translate(q[0],q[1]); ctx.beginPath(); ctx.ellipse(0,6,17,6,0,0,Math.PI*2); ctx.fillStyle='rgba(0,0,0,.25)'; ctx.fill(); ctx.rotate(sa+Math.PI/2); ctx.beginPath(); ctx.moveTo(0,-24); ctx.lineTo(18,16); ctx.lineTo(0,7); ctx.lineTo(-18,16); ctx.closePath(); ctx.lineJoin='round'; ctx.lineWidth=7; ctx.strokeStyle='#FFFFFF'; ctx.stroke(); ctx.lineWidth=3.5; ctx.strokeStyle='#16181B'; ctx.stroke(); ctx.fillStyle=T.accent; ctx.fill(); ctx.restore(); }
    else { const rr=z>=16?46:z>=14?34:22; ctx.beginPath(); ctx.moveTo(q[0],q[1]); ctx.arc(q[0],q[1],rr,sa-.5,sa+.5); ctx.closePath(); ctx.fillStyle=T.accent; ctx.globalAlpha=.42; ctx.fill(); ctx.globalAlpha=1; ctx.beginPath(); ctx.arc(q[0],q[1],12,0,Math.PI*2); ctx.fillStyle='#FFFFFF'; ctx.fill(); ctx.beginPath(); ctx.arc(q[0],q[1],10,0,Math.PI*2); ctx.fillStyle=T.accent; ctx.fill(); ctx.lineWidth=3; ctx.strokeStyle='#16181B'; ctx.stroke(); ctx.save(); ctx.translate(q[0],q[1]); ctx.rotate(sa+Math.PI/2); ctx.beginPath(); ctx.moveTo(0,-5); ctx.lineTo(4,4); ctx.lineTo(0,2); ctx.lineTo(-4,4); ctx.closePath(); ctx.fillStyle=T.accentInk; ctx.fill(); ctx.restore(); } }
  // ---- atmosphere / dim / chrome ----
  if(F.chrome!==false){ ctx.font='700 11px ui-monospace,Menlo,monospace'; const tag='z'+z+(F.pitch?(' · '+F.pitch+'°'):''); const tw=ctx.measureText(tag).width+14; ctx.beginPath(); ctx.roundRect(w-tw-10,10,tw,22,6); ctx.fillStyle=P.chrome; ctx.fill(); ctx.fillStyle=P.chromeInk; ctx.textAlign='left'; ctx.textBaseline='middle'; ctx.fillText(tag,w-tw-3,21.5);
    ctx.font='400 9px "Atkinson Hyperlegible",sans-serif'; ctx.textAlign='right'; ctx.textBaseline='alphabetic'; ctx.fillStyle=P.attr; ctx.fillText('© OpenMapTiles © OpenStreetMap',w-10,h-9);
    if(!F.pitch){ const nice=[10,20,50,100,200,500,1000,2000]; const m=nice.find(n=>n*s>=50)||2000; const px=m*s; ctx.beginPath(); ctx.roundRect(10,h-28,px+48,20,6); ctx.fillStyle=P.scaleBg; ctx.fill(); ctx.strokeStyle=P.chrome; ctx.lineWidth=1.5; ctx.beginPath(); ctx.moveTo(16,h-22); ctx.lineTo(16,h-15); ctx.lineTo(16+px,h-15); ctx.lineTo(16+px,h-22); ctx.stroke(); ctx.fillStyle=P.chrome; ctx.font='700 10px "Atkinson Hyperlegible",sans-serif'; ctx.textAlign='left'; ctx.fillText(m>=1000?(m/1000)+' km':m+' m',21+px,h-14); } }
}

VX.render=render;
VX.along=along; VX.polyLen=polyLen; VX.prep=prep; VX.prepDem=prepDem; VX.buildNav=buildNav; VX.metroLeg=metroLeg; VX.ORIG=ORIG; VX.interp=interp;
})();
