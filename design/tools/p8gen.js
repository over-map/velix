// Velix P8 Accessibility pass. Run: (new Function('A','B',src))(A,B).build()
// A = p4gen+p7gen internals {phone,S3,S8,lu,svg,AH,FG}; B = p5gen internals {phone,VIEWS,STATES}
const AH="'Atkinson Hyperlegible',sans-serif", FG="'Familjen Grotesk',sans-serif";
const xl=(h,k,keep)=>h.replace(/font:(\d{3}) (\d+(?:\.\d+)?)px/g,(m,w,s)=>{ s=+s; return `font:${w} ${s>=keep?s:Math.round(s*k)}px`; }).replace(/font-size:(\d+(?:\.\d+)?)px/g,(m,s)=>{ s=+s; return `font-size:${s>=keep?s:Math.round(s*k)}px`; }).replace(/font:(\d+(?:\.\d+)?)px/g,(m,s)=>{ s=+s; return `font:${s>=keep?s:Math.round(s*k)}px`; })
  .split('white-space:nowrap;overflow:hidden;text-overflow:ellipsis').join('');
const pick=(arr,id)=>arr.find(f=>f.id===id);
const fr=(P,f,o)=>P.phone(Object.assign({},f,o));
const row=inner=>`<div style="display:flex;flex-wrap:wrap;gap:44px 36px;align-items:flex-start">${inner}</div>`;
const sect=(id,eyebrow,title,sub,inner)=>`<section id="${id}" style="padding:44px 48px;border-top:1px solid #D3D2BF;display:flex;flex-direction:column;gap:24px"><div style="display:flex;flex-direction:column;gap:8px;max-width:960px"><div style="font:700 11px/1 ui-monospace,Menlo,monospace;letter-spacing:.08em;color:#4F6570">${eyebrow}</div><h2 style="margin:0;font:700 28px/1.15 ${FG}">${title}</h2>${sub?`<p style="margin:0;font:15px/1.5 ${AH};color:#2E4A5A;text-wrap:pretty">${sub}</p>`:''}</div>${inner}</section>`;
const tag=(t,c)=>`<span style="font:700 12px/1 ui-monospace,Menlo,monospace;padding:5px 7px;border-radius:6px;background:${c||'#2C5870'};color:#FFFFFF;white-space:nowrap">${t}</span>`;

// ---- XL ----
const K=1.35, KR=1.15;
const XL3=[['S3a',640],['S3d',705]].map(([id,b])=>{ const f=pick(A.S3,id); return xl(fr(A,f,{id:id+'-XL',title:'XL · '+f.title,note:'',bottom:b}),K,40); }).join('');
const S8f=A.S8[0];
const XL8=xl(fr(A,S8f,{id:'S8a-XL',title:'XL · You',h:2860,note:''}),K,40);
const s4a=pick(B.VIEWS,'S4a'), s4e=pick(B.STATES,'S4e');
const XL4=[fr(B,s4a,{id:'S4a-L',title:'Default size',note:''}),xl(fr(B,s4a,{id:'S4a-XL',title:'XL · capped at 115%',note:''}),KR,30),xl(fr(B,s4e,{id:'S4e-XL',title:'XL · approaching, capped',note:''}),KR,30)].join('');

// ---- colour blindness ----
const filt=`<svg width="0" height="0" style="position:absolute"><defs><filter id="cvd-deu" color-interpolation-filters="linearRGB"><feColorMatrix type="matrix" values="0.367322 0.860646 -0.227968 0 0 0.280085 0.672501 0.047413 0 0 -0.011820 0.042940 0.968881 0 0 0 0 0 1 0"></feColorMatrix></filter><filter id="cvd-pro" color-interpolation-filters="linearRGB"><feColorMatrix type="matrix" values="0.152286 1.052583 -0.204868 0 0 0.114503 0.786281 0.099216 0 0 -0.003882 -0.048116 1.051998 0 0 0 0 0 1 0"></feColorMatrix></filter></defs></svg>`;
const CVDF=[['S3a',A,A.S3],['S3b',A,A.S3],['S4e',B,B.STATES]];
const cvdRow=(key,lab)=>`<div style="display:flex;flex-direction:column;gap:14px"><div style="display:flex;align-items:center;gap:10px">${tag(lab,key?'#021624':'#4F6570')}</div><div style="display:flex;flex-wrap:wrap;gap:44px 36px;align-items:flex-start;${key?`filter:url(#cvd-${key})`:''}">${CVDF.map(([id,P,arr])=>fr(P,pick(arr,id),{id:id+'-'+(key||'n'),note:''})).join('')}</div></div>`;
const swatches=key=>{ const S=[['Route','#DBF227'],['Hazard','#E0532A'],['Avoided','#7A4FD6'],['Protected','#4E8A12'],['Painted','#0A7F73'],['Quiet','#A9C7A0'],['Mixed','#B0ADAD'],['Cobbles','#8A5A3C'],['Train','#415C70'],['Danger','#C82C45'],['Success','#005C53']]; return `<div style="display:flex;flex-direction:column;gap:6px"><div style="font:700 12px ${AH};color:#4F6570">${key?key==='deu'?'Deuteranopia':'Protanopia':'Normal'}</div><div style="display:flex;gap:6px;${key?`filter:url(#cvd-${key})`:''}">${S.map(([n,c])=>`<div style="display:flex;flex-direction:column;gap:4px;align-items:center;width:60px"><span style="width:60px;height:36px;border-radius:8px;background:${c}"></span></div>`).join('')}</div><div style="display:flex;gap:6px">${S.map(([n])=>`<span style="width:60px;text-align:center;font:11px/1.2 ${AH};color:#2E4A5A">${n}</span>`).join('')}</div></div>`; };

// ---- VoiceOver ----
const VO=[
 ['S1 Ride','Search bar','Where to?','Search field','Double-tap to search for a place.'],
 ['S1 Ride','Home / Work in search bar','Home, 0.3 kilometres · Work, Politecnico, 5.4 kilometres','Button','Double-tap for route options.'],
 ['S1 Ride','Set Home (unset)','Set Home','Button','Double-tap to pick your home address.'],
 ['S1 Ride','Ride-type chip','Ride type: City','Button, pop-up','Double-tap to change.'],
 ['S1 Ride','Map button','Map style and overlays','Button',''],
 ['S1 Ride','Recenter','Recenter on your location','Button',''],
 ['S1 Ride','Weather notice','Severe weather in Milan. Thunderstorms until 18:00. Take care if you ride.','Static text, alert','Dismiss action: Close.'],
 ['S1 Ride','Download progress','Downloading Lombardy, 132 of 220 megabytes','Progress, 60%','Updates every 10%.'],
 ['S1 sheets','Ride-type tile','City. Calmest for city.','Button, selected',''],
 ['S1 sheets','Map style tile','Standard map','Button, selected',''],
 ['S1 sheets','Overlay switch','Bike lanes','Switch, on',''],
 ['S2 Search','Result row','Milano Centrale, railway station, 3.1 kilometres','Button',''],
 ['S2 Search','Metro result','Centrale, metro station, lines M2 and M3','Button','Line tiles are read as text, not colour.'],
 ['S3 Route options','Route card (Best)','Calmest for city. 23 minutes, 5.4 kilometres. 5 minutes slower than fastest: avoids 300 metres of cobbles and busy Corso Buenos Aires. Mostly protected lanes.','Button, selected','Mix bar summarised as the largest two segments.'],
 ['S3 Route options','Route card (Fastest)','Fastest. 18 minutes, 4.6 kilometres. 5 minutes quicker: 300 metres of cobbles on Via Morgagni, busy Corso Buenos Aires.','Button',''],
 ['S3 Route options','Why this route','Why this route','Button, collapsed','Expanded state announced.'],
 ['S3 Route options','Hazard row','Tram rails crossing, 4 on your route: Piazza Oberdan, Via Melzo, Piazza Adelaide di Savoia, Piazza Ascoli','Static text',''],
 ['S3 Route options','Avoided row','Avoided: Viale Piave, rails along the lane','Static text',''],
 ['S3 Route options','Transit row','Long ride? Hop on the train with your bike. 21 minutes faster.','Button',''],
 ['S3 Route options','Next-train chip','Train at 08:16, selected','Button, selected',''],
 ['S3 Route options','Start','Start riding to Politecnico','Button','Disabled state reads “Start, dimmed, routes start when the download is done”.'],
 ['S3 Route options','No route card','No route meets your Cargo / kids rules. No cobbles is on.','Static text','Link: Change rules in You.'],
 ['S4 Riding','Maneuver banner','Turn left in 160 metres onto Via Nino Bixio. Then turn right onto Piazza Adelaide. Quiet street.','Static text, updates frequently','Re-announced at 100 m and 30 m only.'],
 ['S4 Riding','Next hazard card','Tram rails in 160 metres. Cross straight, at a right angle.','Static text, updates frequently','Approaching state: alert, plus haptic.'],
 ['S4 Riding','Voice control','Voice: all prompts','Button','Double-tap cycles: alerts only, mute.'],
 ['S4 Riding','View control','View: 2D follow','Button','Double-tap cycles: 3D, north up.'],
 ['S4 Riding','Overview','Route overview','Button, toggle',''],
 ['S4 Riding','ETA bar','Arrive 08:42, 18 minutes, 4.4 kilometres','Static text',''],
 ['S4 Riding','End','End ride','Button','Asks to confirm.'],
 ['S5 Transit','Stage strip','Stage 1 of 3, ride to station. Next: on the train.','Static text','Not a button.'],
 ['S5 Transit','Late notice','Running late. Switched to the fastest route to catch the 08:16. It adds 120 metres of cobbles.','Alert',''],
 ['S5 Transit','On-train card','Get off at Monza in 6 minutes. Next stop Sesto San Giovanni. Bike carriage at the front.','Static text, updates frequently',''],
 ['Live Activity','Lock screen activity','Turn left in 160 metres, Via Nino Bixio. Tram rails in 160 metres. Arrive 08:42.','Static text',''],
 ['S6 Summary','Stats','5.4 kilometres, 21 minutes moving, 8 metres climb','Static text','Grouped as one element.'],
 ['S6 Summary','Data issue','Via Pascoli felt different. Report','Button',''],
 ['S6 Summary','Share GPX','Share ride as GPX file','Button',''],
 ['S7 Routes','Filter chip','Fits Gravel','Button, selected',''],
 ['S7 Routes','Route list card','Route 1, Alzaia Naviglio Pavese, EuroVelo 5, 33 kilometres. Flat towpath along the canal to Pavia. Mostly car-free paved, 30% gravel.','Button, in focus',''],
 ['S7 Routes','Map route key','Route 1, Alzaia Naviglio Pavese','Button','Map lines themselves are hidden from VoiceOver; keys are the targets.'],
 ['S7 Routes','Search this area','Search routes in this area','Button',''],
 ['S8 You','Ride type header','City, your ride type now, expanded','Button, expanded',''],
 ['S8 You','Rule switch','No cobbles','Switch, on','Hint: Changes which route is Best for City.'],
 ['S8 You','Lit streets only','Lit streets only, for the next ride','Switch, off',''],
 ['S8 You','Connection','Strava, connected','Static text','Action: Disconnect.'],
 ['S8 You','Offline map','Lombardy, 220 megabytes, updated 2 October','Button',''],
 ['S0 First launch','Allow location','Allow location','Button',''],
 ['S0 First launch','Page dots','Step 1 of 3','Page indicator',''],
];
const voTable=()=>`<div style="background:#FFFFFF;border-radius:16px;overflow:hidden;max-width:1400px"><div style="display:grid;grid-template-columns:150px 190px minmax(0,2.2fr) 170px minmax(0,1.3fr);font:700 12px ${AH};letter-spacing:.04em;text-transform:uppercase;color:#4F6570;background:#F1F1E6">${['Screen','Element','Label (read aloud)','Trait / value','Hint / note'].map(t=>`<div style="padding:10px 12px">${t}</div>`).join('')}</div>${VO.map((r,i)=>`<div style="display:grid;grid-template-columns:150px 190px minmax(0,2.2fr) 170px minmax(0,1.3fr);font:14px/1.4 ${AH};color:#021624;border-top:1px solid #DEDDCB">${r.map((c,j)=>`<div style="padding:9px 12px;${j===0?'color:#4F6570;':''}${j===1?'font-weight:700;':''}${j===2?'text-wrap:pretty;':''}">${c}</div>`).join('')}</div>`).join('')}</div>`;

// ---- findings + fixes ----
const FIX=[
 ['Fixed','S4 · maneuver banner','At 115% “Then ↱ P.za Adelaide” was cut off by the road-type pill. The row now wraps: the pill drops to its own line instead of truncating the street. Applied to every riding screen (P5, P6).'],
 ['Fixed','S3 · map above the sheet','At 135% the sheet rises by about 150 pt. The map now refits the route into the space left above it, so start, end and hazards stay visible.'],
 ['Checked','S3 · route cards','Names, times and difference lines reflow; times ≥ 30 pt don’t scale. Nothing truncates on the Politecnico and Monza cases.'],
 ['Checked','S8 · rows','Rule rows grow to two lines and switches stay centred. The full page scrolls; no row truncates.'],
 ['Checked','CVD · route vs hazard','In deuteranopia and protanopia the coral hazard and the chartreuse route both read as yellow. They stay apart by lightness, the ink casing on the route, the dark ring and glyph on hazard markers and the striped tube. No colour change.'],
 ['Checked','CVD · mix bar','Protected, quiet and mixed come close in protanopia. Painted (ticks), cobbles (hatch) and unpaved (dots) carry patterns, and the difference line names the surface in words, so the bar is never the only signal.'],
 ['Checked','CVD · avoided and End','Lilac avoided roads turn blue but stay dashed with a ✕ tag and the reason. The red End button turns olive, near the hazard card: different place, label and shape, so it stays clear.'],
 ['Spec','VoiceOver · map','Map lines are not focusable. Every line has an accessible twin: route cards, hazard rows, numbered route keys (table below).'],
 ['Spec','Reduce Motion','No animated tilt into 3D, recenter jumps instead of flying, the rerouting spinner becomes a static icon.'],
 ['Open','Haptics','The two-tap hazard buzz is the only cue that is neither visual nor audio. Engineering to confirm it stays distinct on a handlebar mount.'],
];
const fixList=()=>`<div style="display:flex;flex-direction:column;gap:10px;max-width:1100px">${FIX.map(([s,t,b])=>`<div style="background:#FFFFFF;border-radius:14px;padding:14px 16px;display:grid;grid-template-columns:90px 220px minmax(0,1fr);gap:12px;align-items:baseline"><span>${tag(s,{Open:'#8A5A3C',Fixed:'#005C53',Checked:'#2C5870',Spec:'#4F6570'}[s])}</span><b style="font:700 15px ${FG}">${t}</b><span style="font:14px/1.45 ${AH};color:#2E4A5A;text-wrap:pretty">${b}</span></div>`).join('')}</div>`;

function build(){
  const css=`body{margin:0;background:#EFEEE2;color:#021624;font-family:${AH}}a{color:#021624}a:hover{color:#2E4A5A}`;
  const V='?v=20261011h';
  const helmet=`<helmet><meta name="design_doc_mode" content="canvas"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=Familjen+Grotesk:wght@500;600;700&display=swap"><script src="https://unpkg.com/lucide@0.460.0/dist/umd/lucide.min.js"></script><script src="https://unpkg.com/d3@7.9.0/dist/d3.min.js"></script><script src="p3v3/palettes.js${V}"></script><script src="p3v3/render.js${V}"></script><script src="p4/maps.js${V}"></script><style>${css}</style></helmet>`;
  const header=`<header style="padding:48px 48px 32px;display:flex;flex-direction:column;gap:14px"><div style="display:flex;align-items:center;gap:14px"><span style="width:44px;height:44px;border-radius:12px;background:#DBF227;box-shadow:inset 0 0 0 2px #021624;display:flex;align-items:center;justify-content:center;font:700 22px ${FG}">V</span><div style="font:700 11px/1 ui-monospace,Menlo,monospace;letter-spacing:.08em;color:#4F6570;white-space:nowrap">VELIX · P8 · ACCESSIBILITY AND EDGE STATES · 11 OCT 2026</div></div><h1 style="margin:0;font:700 44px/1.05 ${FG};max-width:1100px;text-wrap:balance">Readable large, legible without colour, spoken clearly.</h1><p style="margin:0;max-width:900px;font:17px/1.5 ${AH};color:#2E4A5A;text-wrap:pretty">Dynamic Type XL for S3, S4 and S8; colour-blind simulation of S3 and the riding map; VoiceOver labels for every control and card; the fixes applied. Frames are the real P4, P5 and P7 screens re-rendered at the larger size or through the filter.</p></header>`;
  const body=`${helmet}${filt}<div style="max-width:2800px">${header}${sect('fixes','01 · RESULT','Findings and fixes','',fixList())}${sect('xl3','02 · DYNAMIC TYPE XL','S3 Route options at XL (135%)','Text grows; cards reflow and the sheet rises. Big numbers ≥ 30 pt stay as they are.',row(XL3))}${sect('xl4','03 · DYNAMIC TYPE XL','S4 Riding, capped','Riding is capped at 115% so the map keeps its space (decision 13). Default size first, then the capped XL.',row(XL4))}${sect('xl8','04 · DYNAMIC TYPE XL','S8 You at XL (135%)','Rows grow to two lines; nothing truncates.',row(XL8))}${sect('cvd','05 · COLOUR BLINDNESS','S3 and the map, simulated','Machado 2009 matrices, full severity. Each row is the same three frames: route options, Why this route, approaching a hazard.',`<div style="display:flex;flex-direction:column;gap:36px">${cvdRow('','Normal vision')}${cvdRow('deu','Deuteranopia')}${cvdRow('pro','Protanopia')}</div><div style="display:flex;flex-direction:column;gap:14px;background:#FFFFFF;border-radius:16px;padding:20px;max-width:900px">${swatches('')}${swatches('deu')}${swatches('pro')}</div>`)}${sect('vo','06 · VOICEOVER','VoiceOver labels','Labels are written to be heard: units spelled out, no symbols, the decision first. Map lines are not focusable; their twins are.',voTable())}</div>`;
  const js=`class Component extends DCLogic {
  componentDidMount() { this.paint(); }
  componentDidUpdate() { this.paint(); }
  paint() { const run = () => { if (window.lucide && window.VXP4 && window.VX && window.VX.render && window.d3) { window.lucide.createIcons(); window.VXP4.mount(document); } else setTimeout(run, 150); }; run(); }
  renderVals() { return { showDark: true, showNotes: this.props.showNotes ?? true }; }
}`;
  const props={showNotes:{editor:'boolean',default:true,tsType:'boolean',section:'Canvas'}};
  const esc=s=>s.replace(/&/g,'&amp;').replace(/"/g,'&quot;');
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="./support.js"></script>
</head>
<body>
<x-dc>
${body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props="${esc(JSON.stringify(props))}">
${js}
</script>
</body>
</html>`; }
return {build};
