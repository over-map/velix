// StyleGen: the P3 cartography (design/p3v3/palettes.js + render.js) as MapLibre style JSON.
// Writes App/Resources/MapStyle/{standard,outdoor,satellite}-{day,night}.json. `--check` fails if they are stale.
//
// Sources the app resolves at load time (VelixMapStyle.swift):
//   pmtiles://velix-pack/basemap.pmtiles   OpenMapTiles schema (pack role basemap)
//   pmtiles://velix-pack/overlays.pmtiles  velix_cycling / velix_routes / velix_transit / velix_stations
// Glyphs are bundled (asset://MapStyle/glyphs). Icons and patterns are registered at runtime (MapImages.swift):
//   trees-<mode>, poi-<cat>-<mode>, metro-<ref.family.alt,…>-<mode>, rail-<mode>, hz-<type>-<mode>, cnt-<n>-<mode>, hz-stripe-<mode>,
//   avoided-<mode>, start-<mode>, end-<mode>, puck.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const OUT = path.join(ROOT, 'App/Resources/MapStyle');

// ---- design source of truth ----
const ctx = {}; ctx.window = ctx; vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(ROOT, 'design/p3v3/palettes.js'), 'utf8'), ctx);
const VX = ctx.VX, W = VX.W, FAM = VX.METRO_FAM;
const overrides = JSON.parse(fs.readFileSync(path.join(ROOT, 'tools/TokenGen/overrides.json'), 'utf8'));
const tokens = JSON.parse(fs.readFileSync(path.join(ROOT, 'design/velix-tokens.json'), 'utf8'));
const tokenColor = (name, mode) => (overrides.color?.[name] ?? tokens.color[name])[mode === 'day' ? 'light' : 'dark'];

// P3 width curve (render.js interp): exponential base 1.5 between stops, decaying below the first stop.
function interp(st, z) {
  const ks = Object.keys(st).map(Number).sort((a, b) => a - b);
  if (z <= ks[0]) return st[ks[0]] * Math.pow(1.5, (z - ks[0]) * 1.4);
  if (z >= ks[ks.length - 1]) return st[ks[ks.length - 1]];
  for (let i = 0; i < ks.length - 1; i++) {
    const a = ks[i], b = ks[i + 1];
    if (z >= a && z <= b) { const t = (Math.pow(1.5, z - a) - 1) / (Math.pow(1.5, b - a) - 1); return st[a] + (st[b] - st[a]) * t; }
  }
}
const ZS = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
const r2 = (v) => Math.round(v * 100) / 100;
/** A zoom-driven width: f(z) sampled at every zoom, interpolated exponentially (base 1.5) like P3. */
const width = (f) => ['interpolate', ['exponential', 1.5], ['zoom'], ...ZS.flatMap((z) => [z, r2(Math.max(0, f(z)))])];
const w = (k, mul = 1, add = 0) => width((z) => interp(W[k], z) * mul + add);
/** Canvas dashes are in px; MapLibre's are in line widths: one dash array per zoom (step). */
const dashAt = (px, f, z) => ['literal', px.map((d) => r2(d / Math.max(0.2, f(z))))];
const dash = (px, f) => ['step', ['zoom'], dashAt(px, f, ZS[0]), ...ZS.slice(1).flatMap((z) => [z, dashAt(px, f, z)])];

const F_REG = ['Atkinson Hyperlegible Regular'], F_BOLD = ['Atkinson Hyperlegible Bold'];
const ROAD = { motor: ['motorway', 'trunk'], primary: ['primary'], secondary: ['secondary'], tertiary: ['tertiary'],
  minor: ['minor', 'busway'], service: ['service', 'raceway'] };
const ORDER = ['service', 'minor', 'tertiary', 'secondary', 'primary', 'motor'];
const CH_ALPHA = { motor: 1, primary: 1, secondary: 0.9, tertiary: 0.8, minor: 0.55, service: 0.4 };
const POI_CAT = { cafe: 'food', restaurant: 'food', bar: 'food', ice_cream: 'food', bakery: 'food', fast_food: 'food', beer: 'food',
  shop: 'shop', grocery: 'shop', clothing_store: 'shop', pharmacy: 'health', hospital: 'health', school: 'edu', college: 'edu',
  library: 'edu', museum: 'culture', theatre: 'culture', cinema: 'culture', art_gallery: 'culture', attraction: 'culture',
  castle: 'culture', place_of_worship: 'worship', lodging: 'lodging', park: 'green', garden: 'green', playground: 'green',
  dog_park: 'green', pitch: 'green', sports_centre: 'green', stadium: 'green', swimming_pool: 'green', picnic_site: 'green',
  bicycle_parking: 'bike', bicycle_rental: 'bike', bicycle: 'bike', drinking_water: 'water', toilets: 'generic', information: 'generic' };
const CIVIC = ['bike', 'water', 'culture', 'worship', 'edu', 'health'];

function style(name, mode) {
  const P = VX.PAL[name][mode], T = VX.TK[mode];
  const sat = !!P.sat, od = name === 'outdoor';
  T.routeAlt = tokenColor('routeAlt', mode);           // cobalt alternative (overrides.json, Filippo 15 Oct)
  T.altCase = T.casing;                                // same casing as Best (Filippo 15 Oct)
  const L = [];
  const add = (l) => { L.push(l); return l; };
  const omt = (layer, id, type, extra) => add({ id, type, source: 'omt', 'source-layer': layer, ...extra });
  const not = (k, v) => ['!=', ['get', k], v];
  const inList = (k, vs) => ['in', ['get', k], ['literal', vs]];
  const surface = ['!', inList('brunnel', ['tunnel', 'bridge'])];

  // ---- background ----
  add({ id: 'background', type: 'background', paint: { 'background-color': P.land } });
  if (sat) add({ id: 'imagery', type: 'background', paint: { 'background-color': P.land, 'background-opacity': 0 },
    metadata: { 'velix:note': 'velix_imagery raster goes here (imagery milestone); until then land colour + landcover' } });

  // ---- landuse ----
  if (!sat) {
    const LU = [['residential', ['residential', 'neighbourhood'], 10], ['commercial', ['commercial'], 12], ['retail', ['retail'], 12],
      ['industrial', ['industrial'], 11], ['railway', ['railway', 'bus_station'], 11], ['military', ['military'], 11],
      ['education', ['school', 'college', 'university', 'kindergarten', 'education', 'library'], 12], ['hospital', ['hospital'], 12],
      ['cemetery', ['cemetery'], 12], ['playground', ['playground'], 14], ['pitch', ['pitch', 'track'], 14]];
    for (const [k, cls, minzoom] of LU) omt('landuse', `landuse-${k}`, 'fill', { minzoom, filter: inList('class', cls), paint: { 'fill-color': P[k] } });
    omt('landuse', 'landuse-pitch-line', 'line', { minzoom: 15.5, filter: inList('class', ['pitch', 'track']), paint: { 'line-color': P.pitchLine, 'line-width': 1 } });
  }

  // ---- landcover (farmland, grass, meadow, golf, park, scrub, sand, wood) ----
  const sub = (vs) => inList('subclass', vs);
  const LC = [
    ['farmland', ['==', ['get', 'class'], 'farmland']],
    ['grass', ['all', ['==', ['get', 'class'], 'grass'], ['!', sub(['park', 'garden', 'recreation_ground', 'village_green', 'scrub', 'shrubbery', 'heath', ...(od ? ['meadow', 'grassland', 'golf_course'] : [])])]]],
    ...(od ? [['meadow', sub(['meadow', 'grassland'])], ['golf', sub(['golf_course'])]] : []),
    ['park', sub(['park', 'garden', 'recreation_ground', 'village_green'])],
    ['scrub', sub(['scrub', 'shrubbery', 'heath'])],
    ['sand', ['==', ['get', 'class'], 'sand']],
    ['wood', ['==', ['get', 'class'], 'wood']]];
  for (const [k, filter] of LC) omt('landcover', `landcover-${k}`, 'fill', { filter, paint: { 'fill-color': P[k] || P.grass } });
  // OpenMapTiles puts parks in landuse/park too; draw them like landcover parks.
  if (!sat) omt('park', 'park', 'fill', { filter: ['==', ['get', 'class'], 'park'], paint: { 'fill-color': P.park } });
  omt('landcover', 'landcover-trees', 'fill', { minzoom: 14, filter: ['==', ['get', 'class'], 'wood'],
    paint: { 'fill-pattern': `trees-${mode}`, 'fill-opacity': sat ? 0.9 : 0.55 } });
  if (!sat) omt('landcover', 'landcover-park-trees', 'fill', { minzoom: 15, filter: sub(['park', 'garden', 'recreation_ground', 'village_green']),
    paint: { 'fill-pattern': `trees-${mode}`, 'fill-opacity': 0.45 } });

  // ---- water ----
  omt('water', 'water', 'fill', { filter: not('brunnel', 'tunnel'), paint: { 'fill-color': P.water } });
  if (!sat) omt('water', 'water-shore', 'line', { filter: not('brunnel', 'tunnel'),
    paint: { 'line-color': P.waterLine, 'line-opacity': 0.7, 'line-width': ['step', ['zoom'], 0.6, 15, 1] } });
  omt('waterway', 'waterway', 'line', { minzoom: 11, filter: not('brunnel', 'tunnel'), layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': P.water, 'line-width': w('water') } });

  // ---- roads ----
  const roadCol = (k) => (sat ? P.road : k === 'tertiary' ? P.secondary : P[k]);
  const caseCol = (k) => (sat ? P.roadEdge : k === 'tertiary' ? P.secondaryCase : P[`${k}Case`]);
  const wr = (k) => (z) => interp(W[k], z);
  const caseW = (k, mul = 1) => (z) => interp(W[k], z) + interp(W.caseAdd, z) * mul;
  const lineLayout = { 'line-cap': 'round', 'line-join': 'round' };
  const cls = (k) => inList('class', ROAD[k]);
  if (!sat) for (const k of ORDER) omt('transportation', `road-tunnel-${k}`, 'line', { minzoom: 14.5, filter: ['all', cls(k), ['==', ['get', 'brunnel'], 'tunnel']],
    layout: lineLayout, paint: { 'line-color': P.tunnel, 'line-opacity': 0.8, 'line-width': width(wr(k)) } });
  const ped = ['all', ['==', ['get', 'class'], 'path'], ['==', ['get', 'subclass'], 'pedestrian'], not('brunnel', 'tunnel')];
  if (!sat) {
    omt('transportation', 'road-pedestrian-case', 'line', { minzoom: 14, filter: ped, layout: lineLayout, paint: { 'line-color': P.pedCase, 'line-width': width(caseW('ped')) } });
    omt('transportation', 'road-pedestrian', 'line', { minzoom: 14, filter: ped, layout: lineLayout, paint: { 'line-color': P.pedFill, 'line-width': w('ped') } });
  }
  const chart = !!P.chartLine;
  const fillFrom = P.fillFrom;
  if (chart) for (const k of ORDER) omt('transportation', `road-chart-${k}`, 'line', { maxzoom: fillFrom, filter: ['all', cls(k), surface],
    layout: lineLayout, paint: { 'line-color': P.chartLine, 'line-opacity': CH_ALPHA[k], 'line-width': width((z) => interp(W[k], z) * P.chartW + interp(W.caseAdd, z)) } });
  const casedFrom = chart ? fillFrom : 0;
  for (const k of ORDER) {
    const big = k === 'primary' || k === 'motor';
    omt('transportation', `road-case-${k}`, 'line', { minzoom: big ? casedFrom : Math.max(casedFrom, 13.5), filter: ['all', cls(k), surface],
      layout: lineLayout, paint: { 'line-color': caseCol(k), 'line-width': width(caseW(k, big ? 1.3 : 1)) } });
  }
  for (const k of ORDER) omt('transportation', `road-${k}`, 'line', { minzoom: casedFrom, filter: ['all', cls(k), surface],
    layout: lineLayout, paint: { 'line-color': roadCol(k), 'line-width': width(wr(k)) } });
  if (!sat) {
    const pathAlpha = chart ? 0.7 : 1;
    omt('transportation', 'path-footway', 'line', { minzoom: 15, filter: ['all', ['==', ['get', 'class'], 'path'], sub(['footway', 'path']), not('brunnel', 'tunnel')],
      layout: { 'line-cap': 'round' }, paint: { 'line-color': P.path, 'line-opacity': pathAlpha, 'line-width': w('path'), 'line-dasharray': dash([1, 2.4], wr('path')) } });
    const stepsW = (z) => interp(W.steps, z) * 2.2;
    omt('transportation', 'path-steps', 'line', { minzoom: 15, filter: ['all', ['==', ['get', 'class'], 'path'], ['==', ['get', 'subclass'], 'steps'], not('brunnel', 'tunnel')],
      layout: { 'line-cap': 'butt' }, paint: { 'line-color': P.steps, 'line-width': width(stepsW), 'line-dasharray': dash([1, 1.6], stepsW) } });
    omt('transportation', 'road-construction', 'line', { minzoom: 15, filter: ['in', '_construction', ['get', 'class']],
      paint: { 'line-color': P.construction, 'line-width': w('minor'), 'line-dasharray': dash([4, 3], wr('minor')) } });
  }
  if (od) {
    const track = ['==', ['get', 'class'], 'track'];
    omt('transportation', 'track-case', 'line', { minzoom: 12, filter: track, layout: lineLayout, paint: { 'line-color': P.trackCase, 'line-opacity': 0.9, 'line-width': w('track', 1, 1.6) } });
    omt('transportation', 'track-paved', 'line', { minzoom: 12, filter: ['all', track, ['==', ['get', 'surface'], 'paved']], layout: lineLayout, paint: { 'line-color': P.track, 'line-width': w('track') } });
    omt('transportation', 'track-unpaved', 'line', { minzoom: 12, filter: ['all', track, ['!=', ['get', 'surface'], 'paved']], layout: { 'line-cap': 'butt' },
      paint: { 'line-color': P.track, 'line-width': w('track'), 'line-dasharray': dash([5, 3], wr('track')) } });
    omt('transportation', 'trail', 'line', { minzoom: 13, filter: ['all', ['==', ['get', 'class'], 'path'], sub(['path', 'footway', 'bridleway'])],
      layout: { 'line-cap': 'round' }, paint: { 'line-color': P.track, 'line-width': w('mpath'), 'line-dasharray': dash([0.1, 3.6], wr('mpath')) } });
  }
  // ---- rail + tram ----
  const rail = ['all', ['==', ['get', 'class'], 'rail'], not('brunnel', 'tunnel')];
  omt('transportation', 'rail', 'line', { minzoom: 11, filter: rail, paint: { 'line-color': P.rail, 'line-width': w('rail') } });
  const tiesW = (z) => interp(W.rail, z) * 3;
  omt('transportation', 'rail-ties', 'line', { minzoom: 14, filter: rail, layout: { 'line-cap': 'butt' },
    paint: { 'line-color': P.rail, 'line-width': width(tiesW), 'line-dasharray': dash([1, 6], tiesW) } });
  const tram = ['all', ['==', ['get', 'class'], 'transit'], ['==', ['get', 'subclass'], 'tram'], not('brunnel', 'tunnel')];
  omt('transportation', 'tram', 'line', { minzoom: 14, filter: tram, layout: lineLayout, paint: { 'line-color': P.tram, 'line-width': w('tram') } });
  omt('transportation', 'tram-groove', 'line', { minzoom: 16, filter: tram, layout: lineLayout,   // twin rails once the line is > 2.2 pt
    paint: { 'line-color': sat ? P.road : P.minor, 'line-width': width((z) => (interp(W.tram, z) > 2.2 ? interp(W.tram, z) - 1.6 : 0)) } });
  // ---- bridges ----
  for (const k of ORDER) {
    const f = ['all', cls(k), ['==', ['get', 'brunnel'], 'bridge']];
    if (chart) omt('transportation', `bridge-chart-${k}`, 'line', { maxzoom: fillFrom, filter: f, layout: lineLayout,
      paint: { 'line-color': P.chartLine, 'line-opacity': CH_ALPHA[k], 'line-width': width((z) => interp(W[k], z) * P.chartW + interp(W.caseAdd, z) * 2) } });
    omt('transportation', `bridge-case-${k}`, 'line', { minzoom: casedFrom, filter: f, layout: lineLayout,
      paint: { 'line-color': caseCol(k) || P.secondaryCase, 'line-width': width(caseW(k, 2)) } });
    omt('transportation', `bridge-${k}`, 'line', { minzoom: casedFrom, filter: f, layout: lineLayout, paint: { 'line-color': roadCol(k), 'line-width': width(wr(k)) } });
  }

  // ---- cycling infrastructure: base (z14+, ×0.7, 80 %) and the Bike lanes overlay (z11+, full) ----
  const vel = (layer, id, type, extra) => add({ id, type, source: 'velix', 'source-layer': layer, ...extra });
  const kerb = ['interpolate', ['linear'], ['zoom'], 16.9, 0, 17, ['match', ['get', 'side'], 'right', 2, 'left', -2, 0], 19, ['match', ['get', 'side'], 'right', 7, 'left', -7, 0]];
  for (const [prefix, minzoom, mul, alpha, visible] of [['cycle', 14, 0.7, 0.8, !sat], ['overlay-cycle', 11, 1, 1, false]]) {
    const bw = (z) => interp(W.bike, z) * mul;
    const vis = { visibility: visible ? 'visible' : 'none' };
    if (sat) vel('velix_cycling', `${prefix}-halo`, 'line', { minzoom, layout: { ...lineLayout, ...vis }, paint: { 'line-color': '#FFFFFF', 'line-width': width((z) => bw(z) + 3), 'line-offset': kerb } });
    vel('velix_cycling', `${prefix}-protected`, 'line', { minzoom, filter: ['==', ['get', 'kind'], 'protected'], layout: { ...lineLayout, ...vis },
      paint: { 'line-color': T.prot, 'line-opacity': alpha, 'line-width': width(bw), 'line-offset': kerb } });
    vel('velix_cycling', `${prefix}-painted`, 'line', { minzoom, filter: ['==', ['get', 'kind'], 'painted'], layout: { ...lineLayout, ...vis },
      paint: { 'line-color': T.paint, 'line-width': width(bw), 'line-offset': kerb } });
    const tickW = (z) => (bw(z) >= 2 ? bw(z) * 0.8 : 0);
    vel('velix_cycling', `${prefix}-painted-ticks`, 'line', { minzoom, filter: ['==', ['get', 'kind'], 'painted'], layout: { 'line-cap': 'butt', ...vis },
      paint: { 'line-color': T.tick, 'line-width': width(tickW), 'line-dasharray': dash([2, 7], (z) => Math.max(0.5, tickW(z))), 'line-offset': kerb } });
  }
  // EuroVelo ribbon, under the route; fades out z15–16.
  vel('velix_routes', 'eurovelo-ribbon', 'line', { minzoom: 8, layout: { ...lineLayout, visibility: 'none' },
    paint: { 'line-color': mode === 'day' ? 'rgba(44,88,112,0.35)' : 'rgba(176,173,173,0.30)',
      'line-width': ['interpolate', ['linear'], ['zoom'], 13, 7, 15, 10, 17, 14],
      'line-opacity': ['interpolate', ['linear'], ['zoom'], 15, 1, 16, 0] } });

  // ---- Train & metro overlay (MapStyleSheet toggle; the app dims it to 60 % while a route is shown) ----
  const mw = (add2 = 0) => w('metro', 1, add2);
  const ovl = { visibility: 'none' };
  const transit = (m) => ['==', ['get', 'mode'], m];
  vel('velix_transit', 'overlay-train-tunnel-halo', 'line', { minzoom: 10, filter: ['all', transit('train'), ['get', 'tunnel']], layout: ovl,
    paint: { 'line-color': mode === 'day' ? '#FFFFFF' : '#000000', 'line-width': mw(1.5) } });
  vel('velix_transit', 'overlay-train-tunnel', 'line', { minzoom: 10, filter: ['all', transit('train'), ['get', 'tunnel']], layout: { ...ovl, 'line-cap': 'butt' },
    paint: { 'line-color': T.train, 'line-width': mw(), 'line-dasharray': dash([6, 4], (z) => interp(W.metro, z)) } });
  vel('velix_transit', 'overlay-train', 'line', { minzoom: 10, filter: ['all', transit('train'), ['!', ['get', 'tunnel']]], layout: { ...ovl, ...lineLayout },
    paint: { 'line-color': T.train, 'line-width': mw(0.4) } });
  vel('velix_transit', 'overlay-metro-casing', 'line', { minzoom: 10, filter: transit('metro'), layout: { ...ovl, ...lineLayout },
    paint: { 'line-color': T.metroCase, 'line-width': mw(1.5) } });
  const famColor = ['match', ['get', 'family'], ...Object.entries(FAM).flatMap(([k, f]) => [k, ['case', ['get', 'alt'], f.alt, f.main]]), FAM.grey.main];
  vel('velix_transit', 'overlay-metro', 'line', { minzoom: 10, filter: transit('metro'), layout: { ...ovl, ...lineLayout },
    paint: { 'line-color': famColor, 'line-width': mw() } });

  // ---- buildings: flat z13.6–15, then extruded (render_height ramped z14.6–15.8) ----
  const roofIdx = ['%', ['to-number', ['id'], 0], P.roof.length];
  const roof = ['match', roofIdx, ...P.roof.flatMap((c, i) => [i, c]).slice(0, -2), P.roof[P.roof.length - 1]];
  const landmark = ['>=', ['coalesce', ['get', 'render_height'], 0], 85];
  omt('building', 'building-flat', 'fill', { minzoom: 13.6, maxzoom: 15, paint: { 'fill-color': ['case', landmark, P.lmRoof, roof] } });
  omt('building', 'building-edge', 'line', { minzoom: 14.2, maxzoom: 15, paint: { 'line-color': P.wallD, 'line-width': 0.4, 'line-opacity': 0.5 } });
  omt('building', 'building-3d', 'fill-extrusion', { minzoom: 15, filter: ['!=', ['get', 'hide_3d'], true],
    paint: { 'fill-extrusion-color': ['case', landmark, P.lmRoof, roof],
      'fill-extrusion-height': ['interpolate', ['linear'], ['zoom'], 14.6, 0, 15.8, ['coalesce', ['get', 'render_height'], 6]],
      'fill-extrusion-base': ['interpolate', ['linear'], ['zoom'], 14.6, 0, 15.8, ['coalesce', ['get', 'render_min_height'], 0]],
      'fill-extrusion-vertical-gradient': true, 'fill-extrusion-opacity': 1 } });
  if (sat && P.dim) add({ id: 'night-dim', type: 'background', paint: { 'background-color': `rgba(5,8,12,${P.dim})` } });

  // ---- road labels (below the route: it covers its own street names) ----
  const roadLabel = (id, classes, minzoom, bold) => omt('transportation_name', id, 'symbol', { minzoom, filter: inList('class', classes),
    layout: { 'symbol-placement': 'line', 'text-field': ['coalesce', ['get', 'name:it'], ['get', 'name']], 'text-font': bold ? F_BOLD : F_REG,
      'text-size': ['step', ['zoom'], 11, 16, 12, 17, 13], 'text-max-angle': 30, 'text-padding': 4, 'symbol-sort-key': 6 },
    paint: { 'text-color': classes.includes('minor') || classes.includes('path') ? P.labelMinor : P.label, 'text-halo-color': P.halo,
      'text-halo-width': sat ? 1.75 : 1.5 } });
  roadLabel('label-road-primary', ['primary', 'trunk'], 14.6, true);
  roadLabel('label-road-secondary', ['secondary'], 14.6, false);
  roadLabel('label-road-minor', ['tertiary', 'minor'], 15.2, false);
  roadLabel('label-road-path', ['path'], 16, false);

  // ---- route stack (GeoJSON from the app) ----
  const role = (r) => ['==', ['get', 'role'], r];
  const route = (id, type, extra) => add({ id, type, source: 'velix-route', ...extra });
  const halo = (id, filter, f) => sat && route(id, 'line', { filter, layout: lineLayout, paint: { 'line-color': '#FFFFFF', 'line-width': width(f) } });
  halo('route-avoided-halo', role('avoided'), (z) => interp(W.avoided, z) + 3);
  route('route-avoided', 'line', { filter: role('avoided'), layout: { 'line-cap': 'butt' },
    paint: { 'line-color': T.avoided, 'line-width': w('avoided'), 'line-dasharray': dash([7, 6], (z) => interp(W.avoided, z)) } });
  // Alternatives: cobalt, same width and casing as Best (docs/DECISIONS.md, 15 Oct).
  halo('route-alt-halo', role('alt'), (z) => interp(W.routeCase, z) + 3);
  route('route-alt-casing', 'line', { filter: role('alt'), layout: lineLayout, paint: { 'line-color': T.altCase, 'line-width': w('routeCase') } });
  route('route-alt', 'line', { filter: role('alt'), layout: lineLayout, paint: { 'line-color': T.routeAlt, 'line-width': w('route') } });
  halo('route-best-halo', role('best'), (z) => interp(W.routeCase, z) + 3);
  route('route-best-casing', 'line', { filter: role('best'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': w('routeCase') } });
  route('route-best', 'line', { filter: role('best'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': w('route') } });
  // Train leg drawn as a route with ink ties; metro leg: casing, white core, dashed line colour.
  route('leg-train-casing', 'line', { filter: role('leg-train'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': w('routeCase') } });
  route('leg-train', 'line', { filter: role('leg-train'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': w('route') } });
  const tieW = (z) => Math.max(1.6, interp(W.route, z) * 0.34);
  route('leg-train-ties', 'line', { filter: role('leg-train'), layout: { 'line-cap': 'butt' },
    paint: { 'line-color': T.casing, 'line-width': width(tieW), 'line-dasharray': dash([1.1, 0.9].map((x) => x * 9), tieW) } });
  route('leg-metro-casing', 'line', { filter: role('leg-metro'), layout: lineLayout, paint: { 'line-color': T.metroCase, 'line-width': w('leg', 1, 2) } });
  route('leg-metro-core', 'line', { filter: role('leg-metro'), layout: lineLayout, paint: { 'line-color': mode === 'day' ? '#FFFFFF' : '#1E2125', 'line-width': w('leg') } });
  route('leg-metro', 'line', { filter: role('leg-metro'), layout: { 'line-cap': 'butt' },
    paint: { 'line-color': ['get', 'color'], 'line-width': w('leg'), 'line-dasharray': dash([10, 4], (z) => interp(W.leg, z)) } });
  route('hazard-tube', 'line', { filter: role('tube'), layout: { 'line-cap': 'butt', 'line-join': 'round' },
    paint: { 'line-pattern': `hz-stripe-${mode}`, 'line-width': w('tube') } });
  // Arrows have their own source: while riding the app trims them to the route ahead, and the Best line stays whole
  // (its travelled part is faded by a line-gradient on line-progress, set at runtime).
  add({ id: 'route-arrows', type: 'symbol', source: 'velix-arrows', minzoom: 15.8,
    layout: { 'symbol-placement': 'line', 'symbol-spacing': 70, 'icon-image': `arrow-${mode}`, 'icon-allow-overlap': true, 'icon-ignore-placement': true, 'icon-rotation-alignment': 'map' } });

  // ---- stations, places, POIs ----
  const stationName = (minzoom, id, vis) => vel('velix_stations', id, 'symbol', { minzoom, filter: ['==', ['get', 'mode'], 'metro'],
    layout: { visibility: vis, 'icon-image': ['concat', 'metro-', ['get', 'tiles'], `-${mode}`], 'icon-allow-overlap': false,
      'text-field': ['step', ['zoom'], '', minzoom === 12.5 ? 14 : 15.2, ['get', 'name']], 'text-font': F_BOLD,
      'text-size': ['step', ['zoom'], 11, 16, 12], 'text-anchor': 'left', 'text-justify': 'left', 'text-offset': ['literal', [1.4, 0.05]],
      'text-optional': true, 'symbol-sort-key': 4 },
    paint: { 'text-color': P.placeMajor, 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  stationName(14.6, 'station-metro', 'visible');
  stationName(12.5, 'overlay-station-metro', 'none');
  vel('velix_stations', 'station-rail', 'symbol', { minzoom: 13.5, filter: ['==', ['get', 'mode'], 'train'],
    layout: { 'icon-image': `rail-${mode}`, 'text-field': ['get', 'name'], 'text-font': F_BOLD, 'text-size': 11, 'text-anchor': 'left',
      'text-offset': ['literal', [1.1, 0.05]], 'text-optional': true, 'symbol-sort-key': 4 },
    paint: { 'text-color': P.placeMajor, 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  omt('place', 'label-suburb', 'symbol', { minzoom: 11.5, maxzoom: 15.6, filter: inList('class', ['suburb', 'quarter']),
    layout: { 'text-field': ['upcase', ['coalesce', ['get', 'name:it'], ['get', 'name']]], 'text-font': F_BOLD, 'text-size': 12, 'text-letter-spacing': 0.08, 'symbol-sort-key': 5 },
    paint: { 'text-color': P.place, 'text-halo-color': P.halo, 'text-halo-width': sat ? 1.75 : 1.5 } });
  omt('place', 'label-neighbourhood', 'symbol', { minzoom: 13.8, maxzoom: 16.4, filter: inList('class', ['neighbourhood']),
    layout: { 'text-field': ['upcase', ['coalesce', ['get', 'name:it'], ['get', 'name']]], 'text-font': F_BOLD, 'text-size': 10.5, 'text-letter-spacing': 0.08, 'symbol-sort-key': 5 },
    paint: { 'text-color': P.labelMinor, 'text-halo-color': P.halo, 'text-halo-width': sat ? 1.75 : 1.5 } });
  omt('poi', 'label-park', 'symbol', { minzoom: 14.5, filter: ['==', ['get', 'class'], 'park'],
    layout: { 'text-field': ['get', 'name'], 'text-font': F_REG, 'text-size': 11.5, 'symbol-sort-key': 7 },
    paint: { 'text-color': P.parkInk, 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  const poiCat = ['match', ['coalesce', ['get', 'subclass'], ''], ...Object.entries(POI_CAT).flatMap(([k, v]) => [k, v]),
    ['match', ['get', 'class'], ...Object.entries(POI_CAT).flatMap(([k, v]) => [k, v]), '']];
  const poi = (id, minzoom, civicOnly) => omt('poi', id, 'symbol', { minzoom, ...(civicOnly ? { maxzoom: 16.4 } : {}),
    filter: ['all', ['!=', ['get', 'class'], 'park'], ['in', poiCat, ['literal', civicOnly ? CIVIC : Object.values(POI_CAT)]],
      ['any', ['has', 'name'], ['in', poiCat, ['literal', ['bike', 'water']]]]],
    layout: { 'icon-image': ['concat', 'poi-', poiCat, `-${mode}`], 'icon-size': ['step', ['zoom'], 1, 17, 8 / 6.5],
      'text-field': ['step', ['zoom'], '', 16.8, ['coalesce', ['get', 'name'], '']], 'text-font': F_REG, 'text-size': 11,
      'text-anchor': 'left', 'text-offset': ['literal', [1.0, 0.05]], 'text-optional': true, 'symbol-sort-key': ['+', 7, ['/', ['coalesce', ['get', 'rank'], 50], 100]] },
    paint: { 'text-color': P.poiInk, 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  poi('poi-civic', 15.6, true);
  poi('poi', 16.4, false);
  omt('housenumber', 'housenumber', 'symbol', { minzoom: 17.6,
    layout: { 'text-field': ['get', 'housenumber'], 'text-font': F_REG, 'text-size': 9.5, 'symbol-sort-key': 8 },
    paint: { 'text-color': P.hn, 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  vel('velix_routes', 'eurovelo-badge', 'symbol', { minzoom: 9, layout: { visibility: 'none', 'symbol-placement': 'line', 'symbol-spacing': 280,
    'icon-image': ['concat', 'ev-', ['get', 'ref']], 'icon-size': ['interpolate', ['linear'], ['zoom'], 9, 20 / 24, 15, 1], 'symbol-sort-key': 4.5 } });

  // ---- markers: hazards (clusters below z15, markers + pips from z15), avoided tags, endpoints, puck ----
  add({ id: 'hazard-pip', type: 'circle', source: 'velix-hazards', minzoom: 15, filter: ['!', ['has', 'point_count']],
    paint: { 'circle-radius': 3, 'circle-color': T.hazard, 'circle-stroke-color': T.hazardRing, 'circle-stroke-width': 1.5 } });
  add({ id: 'hazard-cluster', type: 'symbol', source: 'velix-hazards', filter: ['has', 'point_count'],
    layout: { 'icon-image': ['concat', 'cnt-', ['to-string', ['get', 'point_count']], `-${mode}`], 'icon-size': ['step', ['zoom'], 16 / 28, 14.5, 22 / 28],
      'icon-anchor': 'bottom', 'icon-allow-overlap': true,
      'symbol-sort-key': ['-', 0, ['get', 'point_count']] } });
  add({ id: 'hazard-marker', type: 'symbol', source: 'velix-hazards', minzoom: 15, filter: ['!', ['has', 'point_count']],
    layout: { 'icon-image': ['concat', 'hz-', ['get', 'hazard'], `-${mode}`], 'icon-size': ['step', ['zoom'], 22 / 28, 16.5, 1],
      'icon-anchor': 'bottom', 'icon-allow-overlap': false,
      'icon-padding': 2, 'symbol-sort-key': ['get', 'rank'] } });
  add({ id: 'avoided-tag', type: 'symbol', source: 'velix-markers', minzoom: 14, filter: role('avoided-tag'),
    layout: { 'icon-image': ['concat', 'avoided-', ['get', 'id'], `-${mode}`], 'icon-allow-overlap': false, 'symbol-sort-key': 1 } });
  add({ id: 'route-start', type: 'symbol', source: 'velix-markers', filter: role('start'),
    layout: { 'icon-image': `start-${mode}`, 'icon-size': ['step', ['zoom'], 5.5 / 8, 14, 6.5 / 8, 16, 1], 'icon-allow-overlap': true, 'symbol-sort-key': 2 } });
  add({ id: 'route-end', type: 'symbol', source: 'velix-markers', filter: role('end'),
    layout: { 'icon-image': `end-${mode}`, 'icon-size': ['step', ['zoom'], 8 / 11, 14, 9.5 / 11, 16, 1], 'icon-allow-overlap': true,
      'text-field': ['coalesce', ['get', 'name'], ''], 'text-font': F_BOLD, 'text-size': 13, 'text-anchor': 'bottom', 'text-offset': ['literal', [0, -1.2]],
      'text-optional': true, 'symbol-sort-key': 2 },
    paint: { 'text-color': sat ? '#FFFFFF' : P.lmInk, 'text-halo-color': P.halo, 'text-halo-width': 1.75 } });
  add({ id: 'puck', type: 'symbol', source: 'velix-markers', filter: role('puck'),
    layout: { 'icon-image': ['step', ['zoom'], 'puck-22', 14, 'puck-34', 16, 'puck-46'], 'icon-rotate': ['coalesce', ['get', 'heading'], 0],
      'icon-rotation-alignment': 'map', 'icon-allow-overlap': true, 'icon-ignore-placement': true } });

  const empty = { type: 'geojson', data: { type: 'FeatureCollection', features: [] } };
  return {
    version: 8,
    name: `Velix ${name} ${mode}`,
    metadata: { 'velix:generator': 'tools/stylegen/stylegen.mjs', 'velix:source': 'design/p3v3 (palettes.js, render.js)', 'velix:style': name, 'velix:mode': mode },
    glyphs: 'asset://MapStyle/glyphs/{fontstack}/{range}.pbf',
    light: { anchor: 'map', position: [1.15, 300, 40], color: '#FFFFFF', intensity: mode === 'day' ? 0.35 : 0.25 },
    sources: {
      omt: { type: 'vector', url: 'pmtiles://velix-pack/basemap.pmtiles', attribution: '© OpenMapTiles © OpenStreetMap contributors' },
      velix: { type: 'vector', url: 'pmtiles://velix-pack/overlays.pmtiles' },
      'velix-route': { ...empty, lineMetrics: true },
      'velix-arrows': empty,
      'velix-hazards': { ...empty, cluster: true, clusterRadius: 44, clusterMaxZoom: 14 },
      'velix-markers': empty,
    },
    layers: L.filter(Boolean),
  };
}

// ---- the palette the runtime map images need (MapImages.swift), as generated Swift ----
function swiftPalette() {
  const hex = (h) => {
    const m = /^#([0-9a-f]{6})$/i.exec(h); if (!m) throw new Error(`not a hex colour: ${h}`);
    const v = parseInt(m[1], 16); return `UIColor(red: ${r3(((v >> 16) & 255) / 255)}, green: ${r3(((v >> 8) & 255) / 255)}, blue: ${r3((v & 255) / 255)}, alpha: 1)`;
  };
  const r3 = (x) => Math.round(x * 1000) / 1000;
  const keys = ['woodDot', 'glyph', 'halo', 'placeMajor', 'land'];
  const tk = ['accent', 'accentInk', 'casing', 'hazard', 'hazardInk', 'hazardRing', 'avoided', 'avoidedInk', 'surface', 'ink', 'prot', 'paint', 'train', 'metroCase'];
  const cats = Object.keys(VX.PAL.standard.day.poi);
  const mode = (m) => {
    const P = VX.PAL.standard[m], T = VX.TK[m];
    const lines = [...keys.map((k) => `        ${k}: ${hex(P[k])},`), ...tk.map((k) => `        ${k}: ${hex(T[k])},`),
      `        poi: [${cats.map((c) => `"${c}": ${hex(P.poi[c])}`).join(', ')}],`, `        poiAlpha: ${P.poiAlpha}`];
    return `    static let ${m} = MapPalette(\n${lines.join('\n')}\n    )`;
  };
  const fam = Object.entries(FAM).map(([k, f]) => `        "${k}": (${hex(f.main)}, ${hex(f.alt)}, ${hex(f.ink)}, ${hex(f.altInk)}),`).join('\n');
  return `// Generated by tools/stylegen/stylegen.mjs from design/p3v3/palettes.js. Do not edit.
import UIKit

/// P3 map colours the runtime map images need (markers, POI discs, station tiles, patterns).
struct MapPalette: Sendable {
    let ${keys.join(', ')}: UIColor
    let ${tk.join(', ')}: UIColor
    let poi: [String: UIColor]
    let poiAlpha: Double

${mode('day')}

${mode('night')}

    /// Metro colour families (main, alt, ink, altInk), P3 mapRules.
    static let metroFamilies: [String: (main: UIColor, alt: UIColor, ink: UIColor, altInk: UIColor)] = [
${fam}
    ]
}
`;
}

const files = {};
for (const name of ['standard', 'outdoor', 'satellite']) for (const mode of ['day', 'night'])
  files[`${name}-${mode}.json`] = JSON.stringify(style(name, mode), null, 1) + '\n';
const check = process.argv.includes('--check');
let stale = 0;
fs.mkdirSync(OUT, { recursive: true });
const all = { ...Object.fromEntries(Object.entries(files).map(([f, t]) => [path.join(OUT, f), t])),
  [path.join(ROOT, 'App/DesignSystem/Generated/MapPalette+Velix.swift')]: swiftPalette() };
for (const [p, text] of Object.entries(all)) {
  const f = path.relative(ROOT, p);
  if (check) { if (!fs.existsSync(p) || fs.readFileSync(p, 'utf8') !== text) { console.error(`stale: ${f}`); stale++; } }
  else fs.writeFileSync(p, text);
}
if (check && stale) { console.error('Run: node tools/stylegen/stylegen.mjs'); process.exit(1); }
console.log(check ? 'Map styles up to date' : `Wrote ${Object.keys(files).length} styles to App/Resources/MapStyle and MapPalette+Velix.swift`);
