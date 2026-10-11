// Velix P9 clickable prototype. Run: (new Function('A','B','C','D',src))(A,B,C,D).build()
// A = p4gen {phone,S1,SH,S2,S3,S3x}; B = p5gen {phone,VIEWS,STATES}; C = p5+p6 {phone,S5}; D = p4+p7 {phone,S7,S6,S8,S0}
const AH="'Atkinson Hyperlegible',sans-serif", FG="'Familjen Grotesk',sans-serif";
const frameOf=(P,f,o)=>{ const s=P.phone(Object.assign({},f,{note:''},o||{})); const i=s.indexOf('<div data-screen-label'); return s.slice(i,s.lastIndexOf('</div>')); };
const SCR=[];
const add=(P,arr,o)=>arr.forEach(f=>SCR.push({id:f.id,title:f.title,html:frameOf(P,f,o&&o[f.id])}));
add(D,D.S0); add(A,A.S1); add(A,A.SH); add(A,A.S2); add(A,A.S3); add(A,A.S3x); add(B,B.VIEWS); add(B,B.STATES); add(C,C.S5); add(D,D.S6); add(D,D.S7);
const s8=frameOf(D,D.S8[0],{h:852}).replace('gap:22px;overflow:hidden','gap:22px;overflow-y:auto'); SCR.push({id:'S8a',title:'You',html:s8});
const TABS=[['Ride','S1a'],['Routes','S7a'],['You','S8a']];
const tabs=except=>TABS.filter(t=>t[1]!==except);
const home=[['Where to?','S2a'],['Work','S3a'],['City','S1g'],['icon:layers','S1h']];
const R={
 S0a:[['Allow location','S0b']],
 S0b:[['Allow While Using App','S0d'],['Allow Once','S0d'],['Don’t Allow','S0c']],
 S0c:[['Open Settings','S0d'],['Continue without','S0d']],
 S0d:[['Continue','S0e']],
 S0e:[['Explore the map','S1a']], S0f:[['Start riding','S1a']], S0g:[['Try again','S0e'],['Explore the map','S1a']],
 S1a:[...home,['icon:x','S1b'],...tabs('S1a')],
 S1b:[...home,['icon:locate','S1a'],...tabs('S1a')],
 S1c:[['Set Home','S2c'],['Set Work','S2c'],['Where to?','S2c'],['City','S1g'],['icon:layers','S1h'],...tabs('S1a')],
 S1d:[...home,...tabs('S1a')], S1e:[...home,...tabs('S1a')], S1f:[...home,['Open Settings','S1a'],...tabs('S1a')],
 S1g:[['icon:x','S1a'],['Edit rules in You','S8a'],...['Calmest for city','Best for e-bike','Smoothest asphalt','Most scenic','Most off-road','Step-free and smooth'].map(k=>[k,'S1a',30])],
 S1h:[['icon:x','S1a'],['canvas','S1a']], S1i:[['icon:x','S1a'],['canvas','S1a']],
 S2a:[['Cancel','S1a'],['Work','S3a',40],['Milano Centrale','S3c',40],['Villa Reale','S3d',40],['Piazza Leonardo da Vinci','S3a',40]],
 S2b:[['Cancel','S1a'],['Milano Centrale','S3c',60]], S2c:[['Cancel','S1a'],['Set Work','S1a'],['Set Home','S1a']],
 S2d:[['Cancel','S1a']], S2e:[['Cancel','S1a'],['Work','S3a',40]],
 S3a:[['Why this route','S3b'],['Start','S4a'],['icon:chevron-left','S1a'],['icon:x','S1a']],
 S3b:[['Why this route','S3a'],['icon:chevron-left','S1a'],['icon:x','S1a']],
 S3c:[['Start','S4a'],['icon:chevron-left','S2a'],['icon:x','S2a']],
 S3d:[['Long ride? Hop on the train with your bike','S3e',90],['Start','S4a'],['icon:chevron-left','S2a'],['icon:x','S2a']],
 S3e:[['Start','S5a'],['Bike only','S3d',60],['icon:chevron-left','S3d'],['icon:x','S3d']],
 S3f:[['Change rules in You','S8a'],['icon:chevron-left','S1a'],['icon:x','S1a']],
 S3g:[['icon:chevron-left','S1a']], S3h:[['Start','S4a'],['icon:chevron-left','S1a'],['icon:x','S1a']],
 S3i:[['Start','S4a'],['icon:chevron-left','S1a'],['icon:x','S1a']], S3j:[['Start','S4a'],['icon:chevron-left','S1a'],['icon:x','S1a']],
 S4a:[['2D','S4b'],['Overview','S4d'],['End','S6a'],['canvas','S4e']],
 S4b:[['3D','S4c'],['Overview','S4d'],['End','S6a'],['canvas','S4e']],
 S4c:[['North','S4a'],['Overview','S4d'],['End','S6a'],['canvas','S4e']],
 S4d:[['Overview','S4a'],['End','S6a'],['canvas','S4a']],
 S4e:[['End','S6a'],['canvas','S4i']], S4f:[['End','S6a'],['canvas','S4e']], S4g:[['End','S6a'],['canvas','S4a']], S4h:[['End','S6a'],['canvas','S4e']],
 S4i:[['End','S6a'],['canvas','S6a']], S4j:[['icon:locate-fixed','S4a'],['End','S6a']],
 S5a:[['End','S6a'],['canvas','S5b']], S5b:[['End','S6a'],['canvas','S5c']], S5c:[['End','S6a'],['canvas','S5d']], S5d:[['canvas','S5e']], S5e:[['End','S6a'],['canvas','S6a']],
 S6a:[['Done','S1a']], S6b:[['Done','S1a'],['Connect','S6a']], S6c:[['Done','S1a'],['Report','S6a']],
 S7a:[['Search a place','S7e'],['All','S7b'],['Alzaia Naviglio Pavese','S7c',120],...tabs('S7a')],
 S7b:[['Fits Gravel','S7a'],['Alzaia Naviglio Pavese','S7c',120],['Search a place','S7e'],...tabs('S7a')],
 S7c:[['Ride this route','S7d'],['icon:x','S7a'],['icon:chevron-left','S7a'],...tabs('S7a')],
 S7d:[['Start','S4a'],['icon:chevron-left','S7c'],['icon:x','S7c']],
 S7e:[['Search routes in this area','S7f'],['icon:circle-x','S7a'],...tabs('S7a')],
 S7f:[['Show all routes','S7b'],['icon:circle-x','S7a'],...tabs('S7a')],
 S7g:[['Back to Milan','S7a'],['icon:circle-x','S7a'],...tabs('S7a')],
 S8a:[['Politecnico','S6a',40],['Connect','S8a'],...tabs('S8a')],
};
const NEXT={S0e:'S0f',S3g:'S3a',S4a:'S4e',S4b:'S4e',S4c:'S4e',S4d:'S4a',S4e:'S4i',S4f:'S4e',S4g:'S4a',S4h:'S4e',S4i:'S6a',S4j:'S4a',S5a:'S5b',S5b:'S5c',S5c:'S5d',S5d:'S5e',S5e:'S6a'};
const GROUPS=[['First launch','S0'],['Ride','S1'],['Search','S2'],['Route options','S3'],['Riding','S4'],['Riding with transit','S5'],['Summary','S6'],['Routes','S7'],['You','S8']].map(([n,p])=>[n,SCR.filter(s=>s.id.startsWith(p)).map(s=>s.id)]);
const FLOWS=[['Commute','S1a','Open → Work → Start. Two taps. Then simulate the ride to the summary.'],['Long trip with transit','S1a','Where to? → Villa Reale → Long ride? → Start, then simulate each stage.'],['Routes','S7a','Gravel rider: list, focus, open Naviglio Pavese, Ride this route.'],['You','S8a','Rules, lit streets, rides, connections, offline map.'],['First launch','S0a','Location, ride type, download, then the Ride map.']];
const TITLES=Object.fromEntries(SCR.map(s=>[s.id,s.title]));

function build(){
  const css=`body{margin:0;background:#EFEEE2;color:#021624;font-family:${AH}}a{color:#021624}a:hover{color:#2E4A5A}`;
  const V='?v=20261011h';
  const helmet=`<helmet><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Atkinson+Hyperlegible:wght@400;700&family=Familjen+Grotesk:wght@500;600;700&display=swap"><script src="https://unpkg.com/lucide@0.460.0/dist/umd/lucide.min.js"></script><script src="https://unpkg.com/d3@7.9.0/dist/d3.min.js"></script><script src="p3v3/palettes.js${V}"></script><script src="p3v3/render.js${V}"></script><script src="p4/maps.js${V}"></script><style>${css}</style></helmet>`;
  const btn=(label,h,extra)=>`<button onClick="{{ ${h} }}" style="height:44px;padding:0 14px;border-radius:12px;border:0;font:700 15px ${AH};cursor:pointer;display:flex;align-items:center;gap:6px;${extra||'background:#FFFFFF;color:#021624;box-shadow:inset 0 0 0 1.5px #DEDDCB'}">${label}</button>`;
  const panel=`<aside style="flex:1 1 300px;max-width:380px;display:flex;flex-direction:column;gap:18px">
<div style="display:flex;align-items:center;gap:12px"><span style="width:40px;height:40px;border-radius:11px;background:#DBF227;box-shadow:inset 0 0 0 2px #021624;display:flex;align-items:center;justify-content:center;font:700 20px ${FG}">V</span><div style="display:flex;flex-direction:column;gap:3px"><div style="font:700 11px/1 ui-monospace,Menlo,monospace;letter-spacing:.08em;color:#4F6570">VELIX · P9 · PROTOTYPE</div><div style="font:700 22px/1.1 ${FG}">Tap through the app</div></div></div>
<div style="background:#FFFFFF;border-radius:16px;padding:16px;display:flex;flex-direction:column;gap:12px"><div style="display:flex;align-items:baseline;gap:8px"><span style="font:700 12px/1 ui-monospace,Menlo,monospace;background:#021624;color:#FFFFFF;padding:5px 7px;border-radius:6px">{{ cur }}</span><span style="font:700 16px/1.3 ${FG}">{{ curTitle }}</span></div><div style="font:15px/1.45 ${AH};color:#2E4A5A;text-wrap:pretty">{{ hint }}</div><div style="display:flex;flex-wrap:wrap;gap:8px">${btn('← Back','back')}<sc-if value="{{ hasNext }}" hint-placeholder-val="{{ false }}">${btn('Simulate riding ▸','next','background:#DBF227;color:#021624;box-shadow:inset 0 0 0 2px #021624')}</sc-if>${btn('{{ hintsLabel }}','toggleHints')}</div></div>
<div style="display:flex;flex-direction:column;gap:8px"><div style="font:700 11px/1.2 ${AH};letter-spacing:.06em;text-transform:uppercase;color:#4F6570">Flows</div><sc-for list="{{ flows }}" as="f" hint-placeholder-count="5"><button onClick="{{ f.go }}" style="text-align:left;border:0;background:#FFFFFF;border-radius:14px;padding:12px 14px;cursor:pointer;display:flex;flex-direction:column;gap:3px;box-shadow:inset 0 0 0 1px #DEDDCB"><span style="font:700 16px ${FG};color:#021624">{{ f.name }}</span><span style="font:14px/1.4 ${AH};color:#2E4A5A">{{ f.desc }}</span></button></sc-for></div>
<div style="display:flex;flex-direction:column;gap:10px"><div style="font:700 11px/1.2 ${AH};letter-spacing:.06em;text-transform:uppercase;color:#4F6570">All screens</div><sc-for list="{{ groups }}" as="g" hint-placeholder-count="9"><div style="display:flex;flex-direction:column;gap:6px"><div style="font:700 13px ${AH};color:#2E4A5A">{{ g.name }}</div><div style="display:flex;flex-wrap:wrap;gap:6px"><sc-for list="{{ g.items }}" as="it" hint-placeholder-count="5"><sc-if value="{{ it.on }}" hint-placeholder-val="{{ false }}"><button onClick="{{ it.go }}" style="height:32px;padding:0 9px;border-radius:8px;border:0;cursor:pointer;font:700 12px ui-monospace,Menlo,monospace;background:#021624;color:#FFFFFF">{{ it.id }}</button></sc-if><sc-if value="{{ it.off }}" hint-placeholder-val="{{ true }}"><button onClick="{{ it.go }}" style="height:32px;padding:0 9px;border-radius:8px;border:0;cursor:pointer;font:700 12px ui-monospace,Menlo,monospace;background:#FFFFFF;color:#021624;box-shadow:inset 0 0 0 1px #DEDDCB">{{ it.id }}</button></sc-if></sc-for></div></div></sc-for></div>
<div style="font:13px/1.45 ${AH};color:#4F6570;text-wrap:pretty">Light mode. Maps are real OSM data and bike routing; times and timetables are sample data, illustrative. Dark versions are in P4–P7.</div>
</aside>`;
  const frames=SCR.map(s=>`<sc-if value="{{ is.${s.id} }}" hint-placeholder-val="{{ ${s.id==='S1a'?'true':'false'} }}">${s.html}</sc-if>`).join('');
  const body=`${helmet}<div style="min-height:100vh;box-sizing:border-box;display:flex;flex-direction:row-reverse;flex-wrap:wrap;gap:40px;padding:36px 32px;justify-content:center;align-items:flex-start"><main style="flex:none;display:flex;flex-direction:column;align-items:center;gap:14px;padding:10px;position:sticky;top:16px"><div data-proto-frame="1" onClick="{{ tap }}" style="width:393px;cursor:pointer">${frames}</div><div style="min-height:20px;font:700 14px ${AH};color:#4F6570">{{ miss }}</div></main>${panel}</div>`;
  const js=`const R=${JSON.stringify(R)}, NEXT=${JSON.stringify(NEXT)}, TITLES=${JSON.stringify(TITLES)}, GROUPS=${JSON.stringify(GROUPS)}, FLOWS=${JSON.stringify(FLOWS)};
const ICN={'chevron-left':'Back','x':'Close','layers':'Map','locate':'Recenter','locate-fixed':'Recenter','circle-x':'Clear'};
function match(el,r){ const k=r[0]; if(k==='canvas') return el.tagName==='CANVAS'; if(k.indexOf('icon:')===0){ const n='lucide-'+k.slice(5); if(el.classList&&el.classList.contains(n)) return true; return !!(el.children&&el.children.length===1&&el.children[0].classList&&el.children[0].classList.contains(n)&&!(el.textContent||'').trim()); } if(el.tagName==='svg'||el.tagName==='path') return false; const t=(el.textContent||'').replace(/\\s+/g,' ').trim(); const s=r[2]||0; return s?(t.indexOf(k)>=0&&t.length<=k.length+s):t===k; }
class Component extends DCLogic {
  state = { cur: this.props.start === 'First launch' ? 'S0a' : this.props.start === 'Routes' ? 'S7a' : 'S1a', hist: [], hints: this.props.showHints ?? true, miss: '' };
  componentDidMount() { this.paint(); }
  componentDidUpdate() { this.paint(); }
  paint() { const run = () => { if (window.lucide && window.VXP4 && window.VX && window.VX.render && window.d3) { window.lucide.createIcons(); window.VXP4.mount(document); this.applyHints(); } else setTimeout(run, 150); }; run(); }
  applyHints() { const root = document.querySelector('[data-proto-frame]'); if (!root) return; root.querySelectorAll('[data-hint]').forEach(e => { e.style.outline = ''; e.removeAttribute('data-hint'); }); if (!this.state.hints) return; const all = [...root.querySelectorAll('*')]; (R[this.state.cur] || []).filter(r => r[0] !== 'canvas').forEach(r => { const c = all.filter(el => match(el, r)); c.filter(el => !c.some(o => o !== el && el.contains(o))).forEach(el => { el.setAttribute('data-hint', '1'); el.style.outline = '2px dashed #021624'; el.style.outlineOffset = '3px'; }); }); }
  go(id) { if (!id || id === this.state.cur) return; this.setState(s => ({ cur: id, hist: s.hist.concat(s.cur).slice(-50), miss: '' })); }
  tap = (e) => { const root = e.currentTarget; const rules = R[this.state.cur] || []; let el = e.target; while (el && el !== root) { for (const r of rules) { if (match(el, r)) { this.go(r[1]); return; } } el = el.parentElement; } this.setState({ miss: 'Not linked in this prototype' }); clearTimeout(this._t); this._t = setTimeout(() => this.setState({ miss: '' }), 1400); };
  renderVals() {
    const cur = this.state.cur, rules = R[cur] || [];
    const words = rules.map(r => r[0] === 'canvas' ? 'the map' : r[0].indexOf('icon:') === 0 ? (ICN[r[0].slice(5)] || r[0].slice(5)) : r[0]).filter((v, i, a) => a.indexOf(v) === i);
    const hint = (words.length ? 'Tap: ' + words.join(' · ') : 'No links here.') + (NEXT[cur] ? ' Or Simulate riding.' : '');
    return {
      cur, curTitle: TITLES[cur] || '', hint, tap: this.tap, is: { [cur]: true }, miss: this.state.miss,
      hasNext: !!NEXT[cur], next: () => this.go(NEXT[cur]),
      back: () => this.setState(s => s.hist.length ? { cur: s.hist[s.hist.length - 1], hist: s.hist.slice(0, -1) } : null),
      hintsLabel: this.state.hints ? 'Hide tap targets' : 'Show tap targets', toggleHints: () => this.setState(s => ({ hints: !s.hints })),
      flows: FLOWS.map(([name, id, desc]) => ({ name, desc, go: () => this.setState(s => ({ cur: id, hist: s.hist.concat(s.cur), miss: '' })) })),
      groups: GROUPS.map(([name, ids]) => ({ name, items: ids.map(id => ({ id, on: id === cur, off: id !== cur, go: () => this.go(id) })) }))
    };
  }
}`;
  const props={start:{editor:'enum',options:['Commute','First launch','Routes'],default:'Commute',tsType:"'Commute'|'First launch'|'Routes'",section:'Prototype'},showHints:{editor:'boolean',default:true,tsType:'boolean',section:'Prototype'}};
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
return {build, count:SCR.length};
