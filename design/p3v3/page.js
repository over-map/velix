(async function(){
const $=s=>document.querySelector(s);
const el=(tag,attrs,html)=>{ const e=document.createElement(tag); if(attrs) for(const k in attrs) e.setAttribute(k,attrs[k]); if(html!=null) e.innerHTML=html; return e; };
const [mi,mz,dm,dz,rt]=await Promise.all(['data/milan.json','data/monza.json','data/dem-milan.json','data/dem-monza.json','data/routes-raw.json'].map(u=>fetch(u).then(r=>r.json())));
await Promise.all([document.fonts.load('400 12px "Atkinson Hyperlegible"'),document.fonts.load('700 12px "Atkinson Hyperlegible"')]);
const DM=VX.prep(mi,'milan'), DZ=VX.prep(mz,'monza');
const AM={D:DM,N:VX.buildNav(DM,rt),dem:VX.prepDem(dm)}, AZ={D:DZ,N:VX.buildNav(DZ,rt),dem:VX.prepDem(dz)};
const L=(D,lon,lat)=>D.toL(lon,lat);
const N=AM.N, mid0=(()=>{ let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9; const b=AM.N.best; for(let i=0;i<b.length;i+=2){ x0=Math.min(x0,b[i]); x1=Math.max(x1,b[i]); y0=Math.min(y0,b[i+1]); y1=Math.max(y1,b[i+1]); } return [(x0+x1)/2,(y0+y1)/2]; })(), loc=N.loc, brg=N.heading*180/Math.PI+90;
const mid=(()=>{ const a=VX.along(N.best,VX.polyLen(N.best)*0.5); return [a[0],a[1]]; })();
const hz0=N.hazards.find(h=>h.k==='tram')||N.hazards[0], cob=N.hazards.find(h=>h.k==='cobbles');
const legM2=VX.metroLeg(DM,'M2','Loreto','Piola'), legM3=VX.metroLeg(DM,'M3','Centrale FS','Repubblica');
const FR=[];
const add=(g,id,title,note,F,A,cls)=>FR.push({g,id,title,note,F:Object.assign({w:360,h:520,style:'standard',mode:'day'},F),A:A||AM,cls});
// Standard
[['day','a'],['night','e']].forEach(([m,l0],mi2)=>{ const L2=c=>String.fromCharCode(l0.charCodeAt(0)+c);
  add('g-std','1'+L2(0),`Standard · ${m} · z13`, mi2?'The reference mood: khaki hairlines on navy, with lime parks and labels.':'Paper chart: slate hairlines, lime-tinted parks and teal water.',{mode:m,z:13,c:mid});
  add('g-std','1'+L2(1),`Standard · ${m} · z15`, mi2?'':'Route options zoom. Streets still read as hairlines, buildings begin to rise and cycle lanes show at 0.7× width.',{mode:m,z:15,c:mid});
  add('g-std','1'+L2(2),`Standard · ${m} · z16.5 · 50°`, mi2?'':'Streets have opened into outlined bands. The tram rails are twin hairlines, with the hazard tube and marker on the crossing.',{mode:m,z:16.5,pitch:50,bearing:brg-25,c:[(hz0.x+loc[0])/2,(hz0.y+loc[1])/2]});
  add('g-std','1'+L2(3),`3D follow · ${m} · z17.5 · 55°`, mi2?'':'Riding: heading up, rider at 72% of the height, upright chevron, POIs and house numbers.',{mode:m,z:17.5,pitch:55,bearing:brg,anchor:.72,c:loc,follow:true}); });
add('g-std','1i','Landmarks · Porta Nuova skyline · day','Landmarks get a khaki-pale roof and their names by day. Everything else keeps the slate roof tone.',{w:744,h:420,z:15.4,pitch:60,bearing:-35,c:L(DM,9.2000,45.4818),route:false},AM,'wide');
add('g-std','1j','Landmarks · Porta Nuova skyline · night','At night landmarks get a lime edge. The city stays slate on navy.',{w:744,h:420,mode:'night',z:15.4,pitch:60,bearing:-35,c:L(DM,9.2000,45.4818),route:false},AM,'wide');
add('g-std','1k','Squint test · 1b blurred','With the basemap blurred to texture, only the route, hazards and puck remain. That is the hierarchy working.',{z:15,c:mid,squint:true});
// Overlays
const lor=L(DM,9.2160,45.4840);
add('g-ov','2a','Bike lanes · day · z14','Protected in mix.protected, painted in mix.painted with ticks. Full overlay width from z11.',{z:14,c:lor,bike:true,route:false});
add('g-ov','2b','Train & metro · day · z14','M1, M2, M3 and M4 with stations. The Passante is dashed slate because it runs in tunnel.',{z:14,c:lor,transit:true,route:false});
add('g-ov','2c','Both + route · day · z14','With a route active the overlays recede and the route stays the brightest line.',{z:14,c:mid,bike:true,transit:true});
add('g-ov','2d','Train & metro · night · z14','',{z:14,c:lor,transit:true,route:false,mode:'night'});
// Outdoor
const mzc=L(DZ,9.2760,45.6010), vr=L(DZ,9.2750,45.5915);
add('g-od','3a','Outdoor · day · Parco di Monza z14','Gravel loop on tracks, with woods, meadows and Lambro. Hillshade shows the slight rise north of the Villa.',{style:'outdoor',z:14,c:mzc},AZ);
add('g-od','3b','Outdoor · night · Parco di Monza z14','At night tracks turn khaki, the hillshade uses navy tones and contour lines are dim teal.',{style:'outdoor',mode:'night',z:14,c:mzc},AZ);
add('g-od','3c','Outdoor · day · Villa Reale z16 · 45°','Villa Reale extruded as a landmark. Tree texture, footpaths and the paved avenue are all visible.',{style:'outdoor',z:16,pitch:45,bearing:20,c:L(DZ,9.2752,45.5935)},AZ);
add('g-od','3d','Outdoor · day · Milan z15','Same Politecnico trip on Outdoor (E-bike). Milan is flat, so contours are sparse.',{style:'outdoor',z:15,c:mid});
// Satellite
add('g-sat','4a','Satellite · day · z15','Every Velix line gets a white halo. Without it, the alt route and avoided line would fail on imagery.',{style:'satellite',z:15,c:mid});
add('g-sat','4b','Satellite · night · z15','Imagery dimmed by 55%. Labels switch to a black halo.',{style:'satellite',mode:'night',z:15,c:mid});
add('g-sat','4c','Satellite · day · z17 · 50° + bike lanes','Bike overlay on imagery, for checking cycle infra.',{style:'satellite',z:17,pitch:50,bearing:brg,c:loc,bike:true});
// Kit
const kitDefs=[
  ['Selected + alt',{z:15.4,c:L(DM,9.2120,45.4790),only:['best','alt']},'Accent 9 pt on a 13 pt ink casing. Alt 5 pt on a white 8 pt casing.'],
  ['Transit leg',{z:15.2,c:legM2?[(legM2.from.x+legM2.to.x)/2,(legM2.from.y+legM2.to.y)/2]:mid,only:[],transit:true,leg:legM2,route:false},'Dashed in the line colour on a white core with an ink casing, plus a mid-leg badge.'],
  ['Hazard tube + marker',{z:17,c:[hz0.x,hz0.y+12],only:['best','hazard']},'Striped tube over the route. The marker sits at the hazard.'],
  ['Avoided + tag',{z:15.8,c:N.avoided?N.avoided.tag:mid,only:['avoided','best']},'Dashed avoided line with a pill tag "✕ reason". Never red.'],
  ['Start · End',{z:15.6,c:[N.end[0]-60,N.end[1]+20],only:['best']},'Start: white dot with an ink ring. End: ink disc with an accent core.'],
  ['Location + heading',{z:16.6,c:loc,only:['best','loc']},'Accent puck with a 3 pt ink ring, white halo and 42% heading cone.']];
['day','night'].forEach((m,mi2)=>kitDefs.forEach(([t,o,n],i)=>add('g-kit','5'+String.fromCharCode(97+mi2*6+i),t+(mi2?' · night':''),mi2?'':n,Object.assign({w:244,h:200,mode:m},o))));
// Metro
add('g-metro','6a','Route start next to M1, M3, Passante · z14.6','',{w:744,h:360,z:14.6,c:L(DM,9.2050,45.4790),transit:true,only:['best','loc']},AM,'wide');
add('g-metro','6b','M3 as a ridden leg · z15','',{w:744,h:360,z:15,c:legM3?[(legM3.from.x+legM3.to.x)/2,(legM3.from.y+legM3.to.y)/2]:mid,transit:true,route:false,leg:legM3},AM,'wide');

const canv={};
FR.forEach(fr=>{ const host=$('#'+fr.g); const d=el('div',{class:'frame'+(fr.cls?' '+fr.cls:''),id:fr.id,'data-screen-label':fr.id+' '+fr.title});
  d.appendChild(el('div',{class:'ft'},`<span class="id">${fr.id}</span><span class="ttl">${fr.title}</span>`));
  const box=el('div',{class:'cv',style:`width:${fr.F.w}px;height:${fr.F.h}px`},'<div class="ld">RENDERING…</div>'); const cv=document.createElement('canvas'); box.appendChild(cv); d.appendChild(box); canv[fr.id]=cv;
  if(fr.note) d.appendChild(el('div',{class:'note'},fr.note)); host.appendChild(d); fr.cv=cv; fr.box=box; });
const queue=[]; let busy=false;
const pump=()=>{ if(busy||!queue.length) return; busy=true; const fr=queue.shift(); setTimeout(()=>{ try{ if(fr.F.squint){ const src=FR.find(x=>x.id==='1b'); if(!src.done){ VX.render(src.cv,src.F,src.A); src.done=true; src.box.querySelector('.ld')?.remove(); } const c=fr.cv; c.width=src.cv.width; c.height=src.cv.height; c.style.width=fr.F.w+'px'; c.style.height=fr.F.h+'px'; const g=c.getContext('2d'); g.filter='blur(7px) saturate(1)'; g.drawImage(src.cv,0,0); } else VX.render(fr.cv,fr.F,fr.A); }catch(e){ console.error(fr.id,e); } fr.done=true; fr.box.querySelector('.ld')?.remove(); busy=false; pump(); },0); };
const io=new IntersectionObserver(es=>es.forEach(e=>{ if(e.isIntersecting){ const fr=FR.find(x=>x.box===e.target); if(fr&&!fr.done&&!fr.q){ fr.q=true; queue.push(fr); pump(); } io.unobserve(e.target); } }),{rootMargin:'800px'});
FR.forEach(fr=>io.observe(fr.box));
window.VX_renderAll=()=>{ FR.forEach(fr=>{ if(!fr.done&&!fr.q){ fr.q=true; queue.push(fr); } }); pump(); };

const core=el('div',{class:'rampbox',style:'grid-column:span 2'},`<div style="font:700 15px 'Familjen Grotesk',sans-serif">Core palette · 9 base colours + 3 signals</div>`); const cc=el('div',{class:'chips'}); Object.entries(VX.CORE).forEach(([k,v])=>cc.appendChild(el('div',{class:'chip'},`<i style="background:${v}"></i><span>${k}<br><span class="mono" style="font-size:10.5px">${v}</span></span>`))); core.appendChild(cc); document.querySelector('#ramps').appendChild(core);
// ramps
const P=VX.PAL; const rampKeys=[['land','Land'],['residential','Residential'],['education','Education'],['park','Park'],['wood','Wood'],['water','Water'],['minor','Minor road'],['chartLine','Hairline street'],['primaryCase','Street outline'],['roof','Roof'],['wallL','Wall lit'],['wallD','Wall shade'],['lmRoof','Landmark roof'],['label','Road label'],['place','Place']];
[['Standard · day',P.standard.day],['Standard · night',P.standard.night],['Outdoor · day',P.outdoor.day],['Outdoor · night',P.outdoor.night]].forEach(([t,pal])=>{ const b=el('div',{class:'rampbox'},`<div style="font:700 15px 'Familjen Grotesk',sans-serif">${t}</div>`); const ch=el('div',{class:'chips'}); rampKeys.concat(t.startsWith('Outdoor')?[['contour','Contour'],['track','Track']]:[]).forEach(([k,n])=>{ let v=pal[k]; if(Array.isArray(v)) v=v[0]; if(!v) v=pal.minor; ch.appendChild(el('div',{class:'chip'},`<i style="background:${v}"></i><span>${n}<br><span class="mono" style="font-size:10.5px">${v}</span></span>`)); }); b.appendChild(ch); $('#ramps').appendChild(b); });

// contrast
const lum=hex=>{ const c=hex.replace('#',''); const v=[0,2,4].map(i=>{ let x=parseInt(c.substr(i,2),16)/255; return x<=0.03928?x/12.92:Math.pow((x+0.055)/1.055,2.4); }); return .2126*v[0]+.7152*v[1]+.0722*v[2]; };
const ratio=(a,b)=>{ const A=lum(a),B=lum(b); return (Math.max(A,B)+.05)/(Math.min(A,B)+.05); };
const cols=[['Standard day','standard','day'],['Standard night','standard','night'],['Outdoor day','outdoor','day'],['Outdoor night','outdoor','night'],['Satellite day','satellite','day'],['Satellite night','satellite','night']];
const bgOf=(st,m)=>st==='satellite'?(m==='day'?'#5F625B':'#2A2C29'):P[st][m].land;
const roadOf=(st,m)=>st==='satellite'?(m==='day'?'#77766F':'#35352F'):(m==='day'?'#FFFFFF':P[st][m].primary);
const T=VX.TK, M=VX.METRO;
const lines=[['Selected route',m=>T[m].accent,(st,m)=>st==='satellite'?'#FFFFFF':T[m].casing,'#DBF227'],['Alternative',m=>T[m].routeAlt,(st,m)=>st==='satellite'?'#FFFFFF':T[m].altCase,'#6A808B'],['Hazard tube',m=>T[m].hazard,(st,m)=>st==='satellite'?'#FFFFFF':T[m].hazardRing,'#E0532A'],['Avoided',m=>T[m].avoided,(st,m)=>st==='satellite'?'#FFFFFF':null,'#7A4FD6'],['Protected lane',m=>T[m].prot,(st,m)=>st==='satellite'?'#FFFFFF':null,'#4E8A12'],['Painted lane',m=>T[m].paint,(st,m)=>st==='satellite'?'#FFFFFF':null,'#0A7F73'],['Train',m=>T[m].train,(st,m)=>st==='satellite'?'#FFFFFF':null,'#415C70'],['Track (Outdoor)',m=>P.outdoor[m].track,(st,m)=>st==='satellite'?'#FFFFFF':P.outdoor[m].trackCase,'#6E5A1E']].concat(Object.entries(VX.METRO_FAM).map(([k,f])=>['Metro · '+k,()=>f.main,(st,m)=>st==='satellite'?'#FFFFFF':T[m].metroCase,f.main]));
const gtc='grid-template-columns:190px repeat(6,minmax(0,1fr))';
const hd=el('div',{class:'tr hd',style:gtc}); hd.appendChild(el('div',{style:'padding:12px 16px'},'Line')); cols.forEach(([n,st,m])=>hd.appendChild(el('div',{class:'sw',style:'padding:12px 8px'},`<i style="background:${bgOf(st,m)}"></i><span>${n}</span>`))); $('#ctab').appendChild(hd);
lines.forEach(([n,fill,edge,sw])=>{ const r=el('div',{class:'tr',style:gtc}); r.appendChild(el('div',{style:'padding:10px 16px;display:flex;align-items:center;gap:10px;font-weight:700'},`<span style="width:22px;height:6px;border-radius:3px;background:${sw}"></span>${n}`));
  cols.forEach(([cn,st,m])=>{ const bg=bgOf(st,m), rd=roadOf(st,m); const fv=fill(m), ev=edge(st,m); const best=(b)=>{ const a=ratio(fv,b), e=ev?ratio(ev,b):0; return e>a?[e,ev===fill(m)?'fill':(st==='satellite'?'halo':'casing')]:[a,'fill']; }; const [rl,by]=best(bg), [rr]=best(rd); const ok=rl>=3&&rr>=3;
    r.appendChild(el('div',{style:`display:flex;flex-direction:column;gap:2px;background:${ok?'transparent':'#FBE4E1'}`},`<span style="font:700 15px 'Familjen Grotesk',sans-serif;font-variant-numeric:tabular-nums;color:${ok?'#16181B':'#B3261E'}">${rl.toFixed(1)} · ${rr.toFixed(1)}</span><span style="font-size:11.5px;color:#62676E">land · street fill, by ${by}${ok?'':' · fails'}</span>`)); });
  $('#ctab').appendChild(r); });

// metro families
const FAM=VX.METRO_FAM;
const tile=(ref,k,alt)=>{ const f=FAM[k]; const bg=alt?f.alt:f.main, ink=alt?f.altInk:f.ink; return `<span title="${k}${alt?' · alt':''}" style="display:inline-flex;align-items:center;justify-content:center;min-width:28px;height:28px;padding:0 6px;border-radius:7px;background:${bg};color:${ink};font:700 13px 'Atkinson Hyperlegible',sans-serif;box-shadow:inset 0 0 0 1px rgba(2,22,36,.18)">${ref}</span>`; };
Object.entries(FAM).forEach(([k,f])=>$('#mfam').appendChild(el('div',{style:'display:flex;flex-direction:column;gap:6px;background:#fff;border-radius:14px;padding:12px'},`<div style="display:flex;gap:4px"><i style="flex:1;height:40px;border-radius:8px 0 0 8px;background:${f.main}"></i><i style="flex:1;height:40px;border-radius:0 8px 8px 0;background:${f.alt}"></i></div><b style="font:700 14px 'Familjen Grotesk',sans-serif">${k}</b><span class="mono" style="font-size:11px">${f.main} · alt ${f.alt}</span>`)));
VX.METRO_CITIES.forEach(([c,ls])=>$('#mcity').appendChild(el('div',{style:'display:grid;grid-template-columns:120px minmax(0,1fr);gap:12px;align-items:center;padding:8px 16px;border-top:1px solid #DEDDCB'},`<b style="font:700 14px 'Familjen Grotesk',sans-serif">${c}</b><div style="display:flex;flex-wrap:wrap;gap:6px">${ls.map(([r,k,a])=>tile(r,k,a)).join('')}</div>`)));
[['#E2001A','Milan M1 (ATM)'],['#EE2E26','Milan M1 (Wikipedia)'],['#FFCD00','Paris 1'],['#CF009E','Paris 4'],['#0098D4','London Victoria'],['#B36305','London Bakerloo'],['#9B2E8F','Barcelona L2'],['#95CDBA','London W&C'],['#000000','London Northern']].forEach(([h,n])=>{ const k=VX.metroFamily(h); $('#msnap').appendChild(el('div',{style:'display:flex;align-items:center;gap:10px;font:13px "Atkinson Hyperlegible",sans-serif;color:#2E4A5A'},`<i style="width:22px;height:22px;border-radius:6px;background:${h};box-shadow:inset 0 0 0 1px rgba(0,0,0,.18)"></i><span class="mono" style="width:66px">${h}</span><span style="width:150px">${n}</span><span>→</span><i style="width:22px;height:22px;border-radius:6px;background:${FAM[k].main}"></i><b style="color:#021624">${k}</b>`)); });

// EuroVelo badges
const bikeSvg=(s,c)=>`<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><circle cx="18.5" cy="17.5" r="3.5"/><circle cx="5.5" cy="17.5" r="3.5"/><circle cx="15" cy="5" r="1"/><path d="M12 17.5V14l-3-3 4-3 2 3h2"/></svg>`;
const evb=(n,sz)=>{ const s=sz||1; return `<span style="display:inline-flex;align-items:center;gap:${3*s}px;height:${22*s}px;padding:0 ${7*s}px 0 ${5*s}px;border-radius:${6*s}px;background:#042940;box-shadow:inset 0 0 0 ${1.5*s}px #D6D58E;white-space:nowrap">${bikeSvg(11*s,'#D6D58E')}<span style="font:700 ${8.5*s}px 'Atkinson Hyperlegible',sans-serif;letter-spacing:.06em;color:#D6D58E">EV</span><span style="font:700 ${13*s}px 'Atkinson Hyperlegible',sans-serif;color:#EFEEE2;font-variant-numeric:tabular-nums">${n}</span></span>`; };
VX.EUROVELO.forEach(([n,name])=>$('#evall').appendChild(el('div',{style:'display:flex;flex-direction:column;gap:8px;align-items:flex-start;background:#fff;border-radius:14px;padding:12px'},`${evb(n,1.3)}<span style="font:13px/1.35 'Atkinson Hyperlegible',sans-serif;color:#2E4A5A">${name}</span>`)));
$('#evuse').innerHTML=[['Day map','#EFEEE2',evb(5)],['Night map','#042940',evb(5)],['Satellite','#5F625B',evb(5)],['Shared section','#EFEEE2',evb(5)+evb(8)],['Route card line','#FFFFFF',`<span style="display:inline-flex;align-items:center;gap:8px;font:700 14px 'Atkinson Hyperlegible',sans-serif;color:#021624">${evb(5)}<span style="font-weight:400;color:#2E4A5A">12.4 km on EuroVelo 5</span></span>`]].map(([t,bg,h])=>`<div style="display:flex;flex-direction:column;gap:8px"><div style="height:84px;border-radius:14px;background:${bg};box-shadow:0 0 0 1px rgba(2,22,36,.12);display:flex;align-items:center;justify-content:center;gap:4px;padding:0 12px">${h}</div><span style="font:700 13px 'Familjen Grotesk',sans-serif">${t}</span></div>`).join('');

// spec
const sd=P.standard.day, sn=P.standard.night, odd=P.outdoor.day, odn=P.outdoor.night, tk=T;
const wv=k=>{ const s=VX.W[k]; return [13,15,17].map(z=>{ const v=VX.interp(s,z); return v<1?v.toFixed(1):(Math.round(v*10)/10).toString(); }).join(' · '); };
const R=(id,type,src,day,night,w,minz,notes)=>({id,type,src,day,night,w,minz,notes});
const SPEC=[
 ['Base: land and water','Standard (Outdoor overrides listed below)',[
  R('background','bg','—',sd.land,sn.land,'—','0','Paper by day, navy at night'),
  R('landuse-residential','fill','omt · landuse · class in residential, neighbourhood',sd.residential,sn.residential,'—','10',''),
  R('landuse-commercial','fill','omt · landuse · class = commercial',sd.commercial,sn.commercial,'—','12',''),
  R('landuse-retail','fill','omt · landuse · class = retail',sd.retail,sn.retail,'—','12',''),
  R('landuse-industrial','fill','omt · landuse · class in industrial, railway, bus_station',sd.industrial,sn.industrial,'—','11','railway uses '+sd.railway),
  R('landuse-education','fill','omt · landuse · class in school, college, university, kindergarten, library',sd.education,sn.education,'—','12','Politecnico campus reads as warm sand'),
  R('landuse-hospital','fill','omt · landuse · class = hospital',sd.hospital,sn.hospital,'—','12',''),
  R('landuse-cemetery','fill','omt · landuse · class = cemetery',sd.cemetery,sn.cemetery,'—','12',''),
  R('landuse-pitch','fill + line','omt · landuse · class in pitch, track, playground',sd.pitch,sn.pitch,'—','14','Outline '+sd.pitchLine+' 1 pt from z15.5'),
  R('landcover-grass','fill','omt · landcover · class = grass (default)',sd.grass,sn.grass,'—','9',''),
  R('landcover-park','fill','omt · landcover · subclass in park, garden, recreation_ground',sd.park,sn.park,'—','10',''),
  R('landcover-wood','fill','omt · landcover · class = wood',sd.wood,sn.wood,'—','8','Tree texture: fill-pattern sprite (dots '+sd.woodDot+' at 55%) from z14'),
  R('landcover-farmland / scrub / sand','fill','omt · landcover',sd.farmland,sn.farmland,'—','9','scrub '+sd.scrub+', sand '+sd.sand),
  R('water','fill','omt · water · brunnel ≠ tunnel',sd.water,sn.water,'—','0','Shore line '+sd.waterLine+' 0.6–1 pt, 70%'),
  R('waterway','line','omt · waterway · brunnel ≠ tunnel',sd.water,sn.water,wv('water'),'11','Name along line, water-ink '+sd.waterInk)]],
 ['Roads and paths','Never coloured. Below z15.2: one hairline colour (slate by day, khaki at night), alpha by class. From z15.2: outlined streets.',[
  R('road-tunnel','line','omt · transportation · brunnel = tunnel',sd.tunnel,sn.tunnel,'as class','14.5','80% opacity, no casing'),
  R('road-pedestrian','line','omt · transportation · class = path, subclass = pedestrian',sd.pedFill,sn.pedFill,wv('ped'),'14','Casing '+sd.pedCase),
  R('road-service','line','omt · transportation · class = service',sd.service,sn.service,wv('service'),'14','Casing '+sd.serviceCase),
  R('road-minor','line','omt · transportation · class in minor, busway',sd.minor,sn.minor,wv('minor'),'13','Casing '+sd.minorCase+' (+'+wv('caseAdd')+')'),
  R('road-tertiary / secondary','line','omt · transportation · class in tertiary, secondary',sd.secondary,sn.secondary,wv('secondary'),'11','Casing '+sd.secondaryCase),
  R('road-primary','line','omt · transportation · class = primary',sd.primary,sn.primary,wv('primary'),'9','Casing '+sd.primaryCase+' × 1.3'),
  R('road-motorway','line','omt · transportation · class in motorway, trunk',sd.motor,sn.motor,wv('motor'),'6','Casing '+sd.motorCase+'. No special hue.'),
  R('road-bridge-*','line','omt · transportation · brunnel = bridge',sd.primary,sn.primary,'as class','13','Casing doubled so bridges lift off'),
  R('path-footway','line','omt · transportation · subclass in footway, path',sd.path,sn.path,wv('path'),'15','Dash 1 / 2.4'),
  R('path-steps','line','omt · transportation · subclass = steps',sd.steps,sn.steps,wv('steps')+' × 2.2','15','Dash 1 / 1.6 butt (treads)'),
  R('road-construction','line','omt · transportation · class like *_construction',sd.construction,sn.construction,wv('minor'),'15','Dash 4 / 3')]],
 ['Rail and tram','Tram rails matter for riders: drawn as twin rails',[
  R('rail','line','omt · transportation · class = rail, brunnel ≠ tunnel',sd.rail,sn.rail,wv('rail'),'11','Ties: same colour, width × 3, dash 1 / 6 from z14'),
  R('tram','line ×2','omt · transportation · class = transit, subclass = tram',sd.tram,sn.tram,wv('tram'),'14','Inner line in road colour, width − 1.6, gives twin rails')]],
 ['Buildings and landmarks','2.5D. MapLibre fill-extrusion, light anchor map, position [1.15, 300°, 40°]',[
  R('building-shadow','fill','velix_shadows (precomputed, sun NW)',sd.shadow.replace(/rgba\((.*)\)/,'rgba $1'),'rgba 0,0,0,.38','—','15','Height × 0.9 offset to SE. Optional: drop if the source isn\u2019t built'),
  R('building-flat','fill','omt · building',sd.roof[0],sn.roof[0],'—','13.6','Below z15 and at pitch 0 only. Roof jitter ±2% by id. Edge '+sd.wallD+' 0.4 pt, 50%'),
  R('building-3d','fill-extrusion','omt · building · hide_3d ≠ true',sd.roof[0],sn.roof[0],'—','15','height = render_height, ramped 0→1 over z14.6–15.8. Walls lit '+sd.wallL+', mid '+sd.wallM+', shade '+sd.wallD),
  R('landmark-3d','fill-extrusion','velix_landmarks ∪ omt building h ≥ 85 m',sd.lmRoof,sn.lmRoof,'—','14.4','Extrude at ≥ 60% from z14.4. Walls '+sd.lmWallL+' / '+sd.lmWallD+'. Night edge '+sn.lmEdge),
  R('landmark-label','symbol','velix_landmarks · name',sd.lmInk,sn.lmInk,'12 pt','14.4','Bold, anchored at roof height')]],
 ['Cycling infrastructure','Visible on every style, never louder than the route',[
  R('cycle-path','line','omt · transportation · subclass = cycleway',tk.day.prot,tk.night.prot,wv('bike')+' × 0.7','14','Overlay on: full width from z11'),
  R('cycle-lane-protected','line','velix_cycling · kind in track, separated',tk.day.prot,tk.night.prot,wv('bike')+' × 0.7','14','line-offset to the kerb side at z17+'),
  R('cycle-lane-painted','line ×2','velix_cycling · kind in lane, busway',tk.day.paint,tk.night.paint,wv('bike')+' × 0.7','14','Ticks '+tk.day.tick+' / '+tk.night.tick+', dash 2 / 7')]],
 ['Overlays','Toggled in MapStyleSheet, any style',[
  R('overlay-metro-casing','line','velix_transit · mode = metro',tk.day.metroCase,tk.night.metroCase,'metro + 1.5','10','Always, both modes. M3 needs it.'),
  R('overlay-metro','line','velix_transit · mode = metro · colour by ref',M.M3,M.M3,wv('metro'),'10','60% while a route or ride is active'),
  R('overlay-train','line','omt rail + velix_transit tunnel',tk.day.train,tk.night.train,wv('metro'),'10','Tunnel (Passante): dash 6 / 4 on halo'),
  R('station-metro','symbol','velix_transit · stations',M.M1,M.M1,'8–12 pt tiles','12.5','One rounded tile per line with its number. Name z14+ (z15.2 without the overlay)'),
  R('station-rail','symbol','omt · poi · class = railway, subclass = station',tk.day.train,tk.night.train,'14 pt','13.5','"FS" tile + name'),
   R('eurovelo-ribbon','line','osm route=bicycle · network = icn · ref = EV*','rgba(44,88,112,.35)','rgba(176,173,173,.30)','7 · 10 · 14','8','Under cycle infra and the route. Fades out z15–16 once real lanes show'),
   R('eurovelo-badge','symbol','same, symbol-placement line, spacing 280 px','#042940','#042940','20 → 24 px','9','Navy tile, khaki ring + EV, paper number. Shared sections stack badges in ref order. Priority 4.5')]],
 ['Route stack','GeoJSON, all styles, above buildings and road labels',[
  R('route-avoided','line','geojson avoided',tk.day.avoided,tk.night.avoided,wv('avoided'),'11','Dash 7 / 6, butt'),
  R('route-alt-casing','line','geojson routes · selected = false',tk.day.altCase,tk.night.altCase,wv('altCase'),'0',''),
  R('route-alt','line','geojson routes · selected = false',tk.day.routeAlt,tk.night.routeAlt,wv('alt'),'0','44 pt invisible tap line'),
  R('route-casing','line','geojson routes · selected = true',tk.day.casing,tk.night.casing,wv('routeCase'),'0',''),
  R('route','line','geojson routes · selected = true',tk.day.accent,tk.night.accent,wv('route'),'0','Draw-in 600 ms'),
  R('hazard-tube','line','geojson hazards · LineString',tk.day.hazard,tk.night.hazard,wv('tube'),'0','line-pattern 45° stripes hazard / near-black'),
  R('transit-leg','line ×3','geojson legs',M.M2,M.M2,wv('leg'),'0','Ink casing, white core, line colour dash 10 / 4, badge'),
  R('route-arrows','symbol','geojson routes · selected',tk.day.accentInk,tk.night.accentInk,'8 pt','15.8','symbol-spacing 70'),
  R('marker-hazard','symbol','geojson hazards · Point',tk.day.hazard,tk.night.hazard,'16 · 22 · 28','0','Sort key 1, pointer 5 pt'),
  R('tag-avoided','symbol','geojson avoided · label point',tk.day.surface,tk.night.surface,'24 pt','14','Avoided ring, avoided-ink text'),
  R('marker-start / end','symbol','geojson endpoints',tk.day.casing,tk.night.casing,'r 5.5 · 6.5 · 8','0','End name Bold 13 pt'),
  R('location','custom','device',tk.day.accent,tk.night.accent,'r 10','0','3D follow: upright chevron')]],
 ['Labels and POIs','Atkinson Hyperlegible SDF',[
  R('label-road','symbol','omt · transportation_name',sd.label,sn.label,'11 · 12 · 13','14.6','Halo '+sd.halo+' / '+sn.halo+' 3 pt. Minor '+sd.labelMinor),
  R('label-place','symbol','omt · place · suburb / neighbourhood',sd.place,sn.place,'12 / 10.5','11.5','Caps +0.08 em'),
  R('poi-*','symbol','omt · poi · 40 classes → 10 categories',sd.poi.food,sn.poi.food,'13 pt disc','15.6','Category tones: shop '+sd.poi.shop+', edu '+sd.poi.edu+', health '+sd.poi.health+', culture '+sd.poi.culture),
  R('poi-bike / water','symbol','omt · poi · bicycle_parking, bicycle_rental, drinking_water',tk.day.prot,tk.night.prot,'13 pt disc','15.6','Water '+sd.poi.water),
  R('housenumber','symbol','omt · housenumber',sd.hn,sn.hn,'9.5 pt','17.6','Lowest priority')]],
 ['Outdoor additions','Gravel, MTB, E-bike',[
  R('hillshade','hillshade','velix_dem · Copernicus GLO-30 (terrarium)','rgb('+odd.shadeDark+')','rgb('+odn.shadeDark+')','—','8','exaggeration 0.6 (4× visual), highlight '+odd.shadeLight),
  R('contour','line','velix_contours · 5 m',odd.contour,odn.contour,'0.7 · 0.9','12','Index every 25 m: '+odd.contourIdx+' × 1.5'),
  R('landcover-meadow / golf','fill','omt · landcover',odd.meadow,odn.meadow,'—','9','golf '+odd.golf),
  R('track','line ×2','omt · transportation · class = track',odd.track,odn.track,wv('track'),'12','Casing '+odd.trackCase+'. Unpaved dash 5 / 3'),
  R('path','line','omt · transportation · subclass in path, footway, bridleway',odd.track,odn.track,wv('mpath'),'13','Dotted 0.1 / 3.6, round')]],
 ['Satellite differences','Imagery placeholder',[
  R('satellite','raster','velix_imagery · z0–13 Copernicus Sentinel-2 mosaic, z14+ open national orthophotos',P.satellite.day.land,'#2A2C29','—','0','Night: brightness-max 0.45. No open ortho: overzoom to z14, then crossfade to Standard by z14.6'),
  R('halo-*','line','every Velix line','#FFFFFF','#FFFFFF','line + 3','—','Under route, alt, avoided, bike'),
  R('label-*','symbol','as Standard','#FFFFFF','#F2F2EF','as Standard','—','Halo #101210 / #000000, 3.5 pt')]]
];
const gcls='tr spec-grid';
SPEC.forEach(([title,sub,rows])=>{ const g=el('div',{style:'display:flex;flex-direction:column;gap:10px'},`<div style="display:flex;flex-direction:column;gap:4px"><div style="font:700 19px 'Familjen Grotesk',sans-serif">${title}</div><div style="font:14px 'Atkinson Hyperlegible',sans-serif;color:#62676E">${sub}</div></div>`);
  const t=el('div',{class:'tbl'}); t.appendChild(el('div',{class:'tr hd spec-grid'},'<div style="padding:10px 12px">#</div><div>Layer id</div><div>Type</div><div>Source · layer · filter</div><div>Day</div><div>Night</div><div style="white-space:nowrap">z13 · z15 · z17</div><div style="white-space:nowrap">Min z</div><div>Notes</div>'));
  rows.forEach((r,i)=>{ const sw=v=>`<div class="sw"><i style="background:${/^#|^rgb/.test(v)?v.replace('rgba ','rgba(').replace(/rgba\(([^)]*)$/,'rgba($1)'):'transparent'}"></i><span style="font:12px/1.45 ui-monospace,Menlo,monospace;color:#16181B;white-space:nowrap;word-break:normal">${v}</span></div>`; t.appendChild(el('div',{class:gcls},`<div style="padding:9px 12px;color:#62676E">${i+1}</div><div class="mono" style="color:#16181B;font-weight:600">${r.id}</div><div style="color:#4A4F55">${r.type}</div><div class="mono">${r.src}</div>${sw(r.day)}${sw(r.night)}<div style="font-variant-numeric:tabular-nums">${r.w}</div><div>${r.minz}</div><div style="color:#4A4F55;text-wrap:pretty">${r.notes}</div>`)); });
  g.appendChild(t); $('#specs').appendChild(g); });
})();
