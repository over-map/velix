// MVT decode + compact extraction (used from run_script via new Function)
const TILE='https://tiles.openfreemap.org/planet/20261004_113936_pt/{z}/{x}/{y}.pbf';
function lon2x(lon,z){return Math.floor((lon+180)/360*2**z);}
function lat2y(lat,z){const r=lat*Math.PI/180;return Math.floor((1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2*2**z);}
function decode(buf){ const b=new Uint8Array(buf); const dec=new TextDecoder();
  function varint(r){ let v=0,sh=0,c; do{ c=b[r.p++]; v+=(c&0x7f)*2**sh; sh+=7; }while(c&0x80); return v; }
  function skip(r,wt){ if(wt===0) varint(r); else if(wt===1) r.p+=8; else if(wt===2){ const l=varint(r); r.p+=l; } else if(wt===5) r.p+=4; }
  const layers=[]; const R={p:0,e:b.length};
  while(R.p<R.e){ const tag=varint(R), f=tag>>3, wt=tag&7; if(f===3&&wt===2){ const l=varint(R); const L={name:'',keys:[],vals:[],feats:[],extent:4096}; const r={p:R.p,e:R.p+l}; R.p+=l;
      while(r.p<r.e){ const t=varint(r), ff=t>>3, w=t&7;
        if(ff===1){ const n=varint(r); L.name=dec.decode(b.subarray(r.p,r.p+n)); r.p+=n; }
        else if(ff===3){ const n=varint(r); L.keys.push(dec.decode(b.subarray(r.p,r.p+n))); r.p+=n; }
        else if(ff===4){ const n=varint(r); const vr={p:r.p,e:r.p+n}; r.p+=n; let v=null; while(vr.p<vr.e){ const tt=varint(vr), f2=tt>>3, w2=tt&7; if(f2===1){ const m=varint(vr); v=dec.decode(b.subarray(vr.p,vr.p+m)); vr.p+=m; } else if(f2===2){ v=new DataView(b.buffer,b.byteOffset+vr.p,4).getFloat32(0,true); vr.p+=4; } else if(f2===3){ v=new DataView(b.buffer,b.byteOffset+vr.p,8).getFloat64(0,true); vr.p+=8; } else if(f2===4||f2===5){ v=varint(vr); } else if(f2===6){ const x=varint(vr); v=(x%2)?-(x+1)/2:x/2; } else if(f2===7){ v=!!varint(vr); } else skip(vr,w2); } L.vals.push(v); }
        else if(ff===5){ L.extent=varint(r); }
        else if(ff===2){ const n=varint(r); const fr={p:r.p,e:r.p+n}; r.p+=n; const F={tags:[],type:0,geom:[]}; while(fr.p<fr.e){ const tt=varint(fr), f2=tt>>3, w2=tt&7; if(f2===2){ const m=varint(fr), e2=fr.p+m; while(fr.p<e2) F.tags.push(varint(fr)); } else if(f2===3){ F.type=varint(fr); } else if(f2===4){ const m=varint(fr), e2=fr.p+m; while(fr.p<e2) F.geom.push(varint(fr)); } else skip(fr,w2); } L.feats.push(F); }
        else skip(r,w); }
      layers.push(L); } else skip(R,wt); }
  return layers; }
function clipRing(r,ext){ const edges=[[p=>p[0]>=0,(a,b)=>{const t=(0-a[0])/(b[0]-a[0]);return [0,a[1]+t*(b[1]-a[1])];}],[p=>p[0]<=ext,(a,b)=>{const t=(ext-a[0])/(b[0]-a[0]);return [ext,a[1]+t*(b[1]-a[1])];}],[p=>p[1]>=0,(a,b)=>{const t=(0-a[1])/(b[1]-a[1]);return [a[0]+t*(b[0]-a[0]),0];}],[p=>p[1]<=ext,(a,b)=>{const t=(ext-a[1])/(b[1]-a[1]);return [a[0]+t*(b[0]-a[0]),ext];}]]; let out=r; for(const [ins,cut] of edges){ const inp=out; out=[]; if(!inp.length) break; for(let i=0;i<inp.length;i++){ const cur=inp[i], prev=inp[(i+inp.length-1)%inp.length]; if(ins(cur)){ if(!ins(prev)) out.push(cut(prev,cur)); out.push(cur); } else if(ins(prev)) out.push(cut(prev,cur)); } } return out; }
function rings(g){ const out=[]; let x=0,y=0,i=0,cur=null; while(i<g.length){ const c=g[i++], id=c&7, cnt=c>>3; if(id===1||id===2){ for(let k=0;k<cnt;k++){ const dx=g[i++], dy=g[i++]; x+=(dx&1)?-(dx+1)/2:dx/2; y+=(dy&1)?-(dy+1)/2:dy/2; if(id===1){ cur=[]; out.push(cur); } cur.push([x,y]); } } } return out; }
const POI_KEEP=new Set(['railway','attraction','college','school','hospital','museum','theatre','cinema','library','place_of_worship','park','garden','bicycle_parking','bicycle_rental','bicycle','drinking_water','cafe','restaurant','bar','ice_cream','bakery','grocery','pharmacy','lodging','town_hall','stadium','playground','toilets','castle','art_gallery','sports_centre','pitch','entrance','shop','clothing_store','beer','fast_food','swimming_pool','dog_park','picnic_site','information','shelter','cycle_barrier','bollard','gate']);
async function extract(bbox, origin){
  const z=14; const xs=[lon2x(bbox[0],z),lon2x(bbox[2],z)], ys=[lat2y(bbox[3],z),lat2y(bbox[1],z)];
  const jobs=[]; for(let x=xs[0];x<=xs[1];x++) for(let y=ys[0];y<=ys[1];y++) jobs.push([x,y]);
  const bufs=await Promise.all(jobs.map(([x,y])=>fetch(TILE.replace('{z}',z).replace('{x}',x).replace('{y}',y)).then(r=>r.arrayBuffer())));
  const k=Math.cos(origin[1]*Math.PI/180);
  const toLocal=(tx,ty,px,py,ext)=>{ const n=2**z; const lon=(tx+px/ext)/n*360-180; const lat=Math.atan(Math.sinh(Math.PI*(1-2*(ty+py/ext)/n)))*180/Math.PI; return [Math.round((lon-origin[0])*111320*k*2), Math.round((origin[1]-lat)*110574*2)]; };
  const out={origin, unit:0.5, building:[], transportation:[], transportation_name:[], landuse:[], landcover:[], park:[], water:[], waterway:[], poi:[], place:[], housenumber:[], water_name:[], mountain_peak:[]};
  const seen=new Set();
  bufs.forEach((buf,ti)=>{ const [tx,ty]=jobs[ti]; decode(buf).forEach(L=>{ if(!(L.name in out)) return; const ext=L.extent;
    L.feats.forEach(F=>{ const p={}; for(let i=0;i<F.tags.length;i+=2) p[L.keys[F.tags[i]]]=L.vals[F.tags[i+1]];
      let rs=rings(F.geom);
      const conv=r=>{ const o=[]; let lx=null,ly=null; r.forEach(([px,py])=>{ const [X,Y]=toLocal(tx,ty,px,py,ext); if(X!==lx||Y!==ly){ o.push(X,Y); lx=X; ly=Y; } }); return o; };
      if(F.type===1){ rs.forEach(r=>r.forEach(([px,py])=>{ if(px<0||py<0||px>ext||py>ext) return; const [X,Y]=toLocal(tx,ty,px,py,ext);
        const key=L.name+X+','+Y+(p.name||p.housenumber||''); if(seen.has(key)) return; seen.add(key);
        if(L.name==='poi'){ if(!POI_KEEP.has(p.class)) return; out.poi.push([X,Y,p.class,p.subclass||'',p.name||'',p.rank||99]); }
        else if(L.name==='place') out.place.push([X,Y,p.class,p.name||'',p.rank||99]);
        else if(L.name==='housenumber') out.housenumber.push([X,Y,p.housenumber]);
        else if(L.name==='water_name') out.water_name.push([X,Y,p.class,p.name||'']);
        else if(L.name==='mountain_peak') out.mountain_peak.push([X,Y,p.name||'',p.ele||0]);
      })); return; }
      if(L.name==='building'){ if(p.hide_3d) return; rs.forEach(r=>{ let cx=0,cy=0; r.forEach(q=>{cx+=q[0];cy+=q[1];}); cx/=r.length; cy/=r.length; if(cx<0||cy<0||cx>=ext||cy>=ext) return; let a=0; for(let i=0;i<r.length;i++){ const q=r[i],w=r[(i+1)%r.length]; a+=q[0]*w[1]-w[0]*q[1]; } if(a<0) return; const c=conv(r); if(c.length>=6) out.building.push([Math.round((p.render_height||6)*2)/2, Math.round((p.render_min_height||0)*2)/2, c]); }); return; }
      if(F.type===3) rs=rs.map(r=>clipRing(r,ext)).filter(r=>r.length>=3);
      const geo=rs.map(conv).filter(c=>c.length>=4);
      if(!geo.length) return;
      if(L.name==='transportation') out.transportation.push([p.class||'',p.subclass||'',p.brunnel||'',p.surface||'',p.bicycle||'',p.layer||0,p.oneway||0,geo]);
      else if(L.name==='transportation_name') out.transportation_name.push([p.class||'',p.name||'',p.ref||'',geo]);
      else if(L.name==='landuse') out.landuse.push([p.class||'',geo]);
      else if(L.name==='landcover') out.landcover.push([p.class||'',p.subclass||'',geo]);
      else if(L.name==='park') out.park.push([p.class||'',p.name||'',geo]);
      else if(L.name==='water') out.water.push([p.class||'',p.brunnel||'',geo]);
      else if(L.name==='waterway') out.waterway.push([p.class||'',p.name||'',p.brunnel||'',geo]);
    }); }); });
  return out;
}
return {extract, decode};
