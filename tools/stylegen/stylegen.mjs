// StyleGen: the P3 cartography (design/p3v3/palettes.js + render.js) as MapLibre style JSON.
// Writes App/Resources/MapStyle/{standard,outdoor,satellite}-{day,night}.json. `--check` fails if they are stale.
//
// Sources served by the app from every installed pack (PackTileProtocol.swift):
//   https://tiles.velix.invalid/basemap/{z}/{x}/{y}   OpenMapTiles schema (pack role basemap; OpenFreeMap outside the packs)
//   https://tiles.velix.invalid/overlays/{z}/{x}/{y}  velix_cycling / velix_routes / velix_transit / velix_stations
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
/** POI colour by category: overrides.json `poi` (30 Oct: colours by category), else P3's. `m`: day | night. */
const poiColor = (cat, m, P) => overrides.poi?.[cat]?.[m === 'day' ? 'light' : 'dark'] ?? P.poi[cat];
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
/** `a` moved `t` of the way to `b` (#RRGGBB). */
const mixHex = (a, b, t) => '#' + [1, 3, 5].map((i) => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - t) + parseInt(b.slice(i, i + 2), 16) * t)
  .toString(16).padStart(2, '0')).join('').toUpperCase();
/** A zoom-driven width: f(z) sampled at every zoom, interpolated exponentially (base 1.5) like P3. */
const width = (f) => ['interpolate', ['exponential', 1.5], ['zoom'], ...ZS.flatMap((z) => [z, r2(Math.max(0, f(z)))])];
const w = (k, mul = 1, add = 0) => width((z) => interp(W[k], z) * mul + add);
// Route lines never thinner than this (pt): P3's curves fade out below z11, where route overviews of 10–20 km sit and
// the route must still stand out (Filippo, 30 Oct). The casing keeps its 3 pt over the line.
const ROUTE_MIN = 4.5, CASE_MIN = ROUTE_MIN + 3;
const rw = (k, mul = 1, add = 0) => width((z) => Math.max(interp(W[k], z) * mul + add, (k === 'routeCase' ? CASE_MIN : ROUTE_MIN) * mul + add));
/** Canvas dashes are in px; MapLibre's are in line widths: one dash array per zoom (step). */
const dashAt = (px, f, z) => ['literal', px.map((d) => r2(d / Math.max(0.2, f(z))))];
const dash = (px, f) => ['step', ['zoom'], dashAt(px, f, ZS[0]), ...ZS.slice(1).flatMap((z) => [z, dashAt(px, f, z)])];

const F_REG = ['Atkinson Hyperlegible Regular'], F_BOLD = ['Atkinson Hyperlegible Bold'];

// ---- multi-zoom (Filippo, 6 Nov: below z13 the map is Velix's own; P3 starts at z13) ----
/** 0 → `max` over in0–in1, `max` → 0 over out0–out1 (either end may be null): features come and go over a zoom or so
 * instead of popping. `max` may be a data expression. */
function fade(in0, in1, out0 = null, out1 = null, max = 1) {
  const st = [];
  if (in0 != null) st.push([in0, 0], [in1, max]);
  if (out0 != null) { if (!st.length || out0 > in1) st.push([out0, max]); st.push([out1, 0]); }
  return st.length ? ['interpolate', ['linear'], ['zoom'], ...st.flat()] : max;
}
/** Piecewise-linear zoom function `f(z)` (a number or a data expression) sampled at the zooms where it bends. */
function zfn(zs, f) {
  const ks = [...new Set(zs.map(r2))].sort((a, b) => a - b);
  return ['interpolate', ['linear'], ['zoom'], ...ks.flatMap((z) => [z, f(z)])];
}
const ramp01 = (a, b, z) => (z <= a ? 0 : z >= b ? 1 : (z - a) / (b - a));
/** Linear text sizes by zoom (pt). */
const zsize = (...stops) => ['interpolate', ['linear'], ['zoom'], ...stops];
/** Place and water names: the phone's language at runtime (VelixMapStyle.localize), English in the file. */
const PLACE_NAME = ['coalesce', ['get', 'name:en'], ['get', 'name:latin'], ['get', 'name']];
/** Streets, suburbs, POIs, stations: the name as signed (Filippo, 6 Nov). */
const LOCAL_NAME = ['get', 'name'];
/** When each road class arrives in the tiles (OpenMapTiles): its chart line fades in over these zooms. */
const ROAD_IN = { motorway: [3.5, 5], trunk: [5, 6.5], primary: [7, 8.5], secondary: [8.5, 10], tertiary: [10, 11.5],
  minor: [11.5, 13], busway: [11.5, 13], service: [13, 14.5], raceway: [13, 14.5] };
/** Zoomed out the chart hairlines calm down (45 % to z6, 60 % at z8, full from z9.5): the tangle of 6 Nov. */
const calm = (z) => (z <= 8 ? 0.45 + 0.15 * ramp01(6, 8, z) : 0.6 + 0.4 * ramp01(8, 9.5, z));
/** Chart hairlines never thinner than this (pt) below z11, so zoomed out a motorway still reads. */
const CHART_FLOOR = { motor: 0.6, primary: 0.5, secondary: 0.4 };
/** Chart hairlines → outlined streets (P3's switch at fillFrom 15.2): the streets fade in over the hairlines, then
 * the hairlines go underneath them, so the roads never look washed out half-way. */
const XFADE = [14.9, 15.3], XOUT = [15.3, 15.6];
const ROAD = { motor: ['motorway', 'trunk'], primary: ['primary'], secondary: ['secondary'], tertiary: ['tertiary'],
  minor: ['minor', 'busway'], service: ['service', 'raceway'] };
const ORDER = ['service', 'minor', 'tertiary', 'secondary', 'primary', 'motor'];
const lineLayoutRound = () => ({ 'line-cap': 'round', 'line-join': 'round' });
const CH_ALPHA = { motor: 1, primary: 1, secondary: 0.9, tertiary: 0.8, minor: 0.55, service: 0.4 };
const POI_CAT = { cafe: 'food', restaurant: 'food', bar: 'food', ice_cream: 'food', bakery: 'food', fast_food: 'food', beer: 'food',
  shop: 'shop', grocery: 'shop', clothing_store: 'shop', pharmacy: 'health', hospital: 'health', school: 'edu', college: 'edu',
  library: 'edu', museum: 'culture', theatre: 'culture', cinema: 'culture', art_gallery: 'culture', attraction: 'culture',
  castle: 'culture', place_of_worship: 'worship', lodging: 'lodging', park: 'green', garden: 'green', playground: 'green',
  dog_park: 'green', pitch: 'green', sports_centre: 'green', stadium: 'green', swimming_pool: 'green', picnic_site: 'green',
  bicycle_parking: 'bike', bicycle_rental: 'bike', bicycle: 'bike', drinking_water: 'water', toilets: 'generic', information: 'generic' };
const CIVIC = ['bike', 'water', 'culture', 'worship', 'edu', 'health'];

function style(name, mode) {
  // overrides.json `map`: palette fixes for standard and outdoor (Filippo, 2 Nov: one colour per feature at every zoom).
  const fix = Object.fromEntries(Object.entries(overrides.map?.[mode === 'day' ? 'light' : 'dark'] ?? {}).filter(([k]) => !k.startsWith('_')));
  const P = VX.PAL[name][mode].sat ? VX.PAL[name][mode] : { ...VX.PAL[name][mode], ...fix }, T = VX.TK[mode];
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
    // Residential from z8, fading in: towns read as patches before their streets (6 Nov).
    const LU = [['residential', ['residential', 'neighbourhood'], 8], ['commercial', ['commercial'], 12], ['retail', ['retail'], 12],
      ['industrial', ['industrial'], 11], ['railway', ['railway', 'bus_station'], 11], ['military', ['military'], 11],
      ['education', ['school', 'college', 'university', 'kindergarten', 'education', 'library'], 12], ['hospital', ['hospital'], 12],
      ['cemetery', ['cemetery'], 12], ['playground', ['playground'], 14], ['pitch', ['pitch', 'track'], 14]];
    for (const [k, cls, minzoom] of LU) omt('landuse', `landuse-${k}`, 'fill', { minzoom, filter: inList('class', cls),
      paint: { 'fill-color': P[k], 'fill-opacity': k === 'residential' ? fade(8, 9.5) : fade(minzoom, minzoom + 1) } });
    omt('landuse', 'landuse-pitch-line', 'line', { minzoom: 15.5, filter: inList('class', ['pitch', 'track']),
      paint: { 'line-color': P.pitchLine, 'line-opacity': fade(15.5, 16.1), 'line-width': 1 } });
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
  // Zoomed out the woods and fields would blotch the whole Alps: softer until the city zooms (6 Nov).
  const coverCalm = ['interpolate', ['linear'], ['zoom'], 7, 0.55, 10, 1];
  for (const [k, filter] of LC) omt('landcover', `landcover-${k}`, 'fill', { filter, paint: { 'fill-color': P[k] || P.grass, 'fill-opacity': coverCalm } });
  // OpenMapTiles puts parks in landuse/park too; draw them like landcover parks.
  if (!sat) omt('park', 'park', 'fill', { filter: ['==', ['get', 'class'], 'park'], paint: { 'fill-color': P.park } });
  // Zoomed out (6 Nov): glaciers and bare rock give the Alps their shape; national parks and reserves a light tint.
  const ice = mode === 'day' || sat ? mixHex(P.land, '#FFFFFF', sat ? 0.45 : 0.6) : mixHex(P.land, P.waterInk, 0.2);
  omt('landcover', 'landcover-ice', 'fill', { filter: ['in', ['get', 'class'], ['literal', ['ice', 'glacier']]], paint: { 'fill-color': ice } });
  omt('landcover', 'landcover-rock', 'fill', { minzoom: 7, filter: ['==', ['get', 'class'], 'rock'],
    paint: { 'fill-color': mixHex(P.land, P.rail, od ? 0.24 : 0.16), 'fill-opacity': fade(7, 8.5) } });
  const protectedArea = inList('class', ['national_park', 'nature_reserve', 'protected_area']);
  const protectedOut = od ? [13.5, 14.5] : [11, 13];
  omt('park', 'park-protected', 'fill', { minzoom: 5.5, maxzoom: protectedOut[1], filter: protectedArea,
    paint: { 'fill-color': P.park, 'fill-opacity': fade(5.5, 6.5, ...protectedOut, sat ? 0.25 : mode === 'day' ? 0.3 : 0.35) } });
  if (od) omt('park', 'park-protected-edge', 'line', { minzoom: 7, maxzoom: 14.5, filter: protectedArea,
    paint: { 'line-color': P.parkInk, 'line-opacity': fade(7, 8, 13.5, 14.5, 0.45), 'line-width': zsize(7, 0.5, 12, 1),
      'line-dasharray': ['literal', [3, 2]] } });
  omt('landcover', 'landcover-trees', 'fill', { minzoom: 14, filter: ['==', ['get', 'class'], 'wood'],
    paint: { 'fill-pattern': `trees-${mode}`, 'fill-opacity': fade(14, 14.8, null, null, sat ? 0.9 : 0.55) } });
  if (!sat) omt('landcover', 'landcover-park-trees', 'fill', { minzoom: 15, filter: sub(['park', 'garden', 'recreation_ground', 'village_green']),
    paint: { 'fill-pattern': `trees-${mode}`, 'fill-opacity': fade(15, 15.8, null, null, 0.45) } });

  // ---- hillshade (6 Nov): Mapterhorn elevation, 30 m worldwide and finer where countries publish it, z0–12 tiles
  // overzoomed. Strongest zoomed out where relief shapes the land, gone by z14.5 so riding zooms (15–17) never pay
  // for it. Colours: P3's outdoor shade tokens (shadeDark / shadeLight), for every style. Below water: lakes stay flat.
  const OD = VX.PAL.outdoor[mode];
  const shadeA = od ? 1 : sat ? 0.8 : 0.7;
  const rgba = (rgb, a) => `rgba(${rgb},${r2(a * shadeA)})`;
  add({ id: 'hillshade', type: 'hillshade', source: 'terrain', maxzoom: 14.5,
    paint: { 'hillshade-illumination-direction': 315, 'hillshade-illumination-anchor': 'map',
      'hillshade-exaggeration': ['interpolate', ['linear'], ['zoom'], 3, 0.55, 8, 0.45, 11, 0.5, 13.5, 0.5, 14.5, 0],
      'hillshade-shadow-color': rgba(OD.shadeDark, mode === 'day' ? 0.38 : 0.55),
      'hillshade-highlight-color': rgba(OD.shadeLight, mode === 'day' ? 0.35 : 0.22),
      'hillshade-accent-color': rgba(OD.shadeDark, mode === 'day' ? 0.12 : 0.2) } });

  // ---- water ----
  omt('water', 'water', 'fill', { filter: not('brunnel', 'tunnel'), paint: { 'fill-color': P.water } });
  if (!sat) omt('water', 'water-shore', 'line', { filter: not('brunnel', 'tunnel'),
    paint: { 'line-color': P.waterLine, 'line-opacity': 0.7, 'line-width': zsize(14, 0.6, 15, 1) } });
  // Rivers from z6 (6 Nov), never thinner than 0.5 pt; the smaller waterways from z11, as before.
  const river = ['==', ['get', 'class'], 'river'];
  const riverW = ['interpolate', ['exponential', 1.5], ['zoom'], 6, 0.5, 9, 0.7, ...ZS.filter((z) => z >= 11).flatMap((z) => [z, r2(Math.max(0.7, interp(W.water, z)))])];
  omt('waterway', 'waterway-river', 'line', { minzoom: 6, maxzoom: 11, filter: ['all', not('brunnel', 'tunnel'), river],
    layout: { 'line-cap': 'round', 'line-join': 'round' }, paint: { 'line-color': P.water, 'line-opacity': fade(6, 7), 'line-width': riverW } });
  omt('waterway', 'waterway', 'line', { minzoom: 11, filter: not('brunnel', 'tunnel'), layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': P.water, 'line-opacity': zfn([11, 11.8], (z) => ['case', river, 1, r2(ramp01(11, 11.8, z))]),
      'line-width': ['interpolate', ['exponential', 1.5], ['zoom'],
      ...ZS.filter((z) => z >= 11).flatMap((z) => [z, ['case', river, r2(Math.max(0.7, interp(W.water, z))), r2(interp(W.water, z))]])] } });

  // ---- borders (6 Nov): countries a soft band and a line, regions dashed, provinces dotted; not at sea ----
  const land = ['!=', ['get', 'maritime'], 1];
  const admin = (l) => ['==', ['get', 'admin_level'], l];
  omt('boundary', 'boundary-country-band', 'line', { minzoom: 3.5, maxzoom: 12.5, filter: ['all', admin(2), land],
    layout: lineLayoutRound(), paint: { 'line-color': P.place, 'line-blur': 1,
      'line-opacity': fade(3.5, 4.5, 11, 12.5, sat ? 0.1 : mode === 'day' ? 0.14 : 0.11),
      'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 3.5, 2, 6, 4, 10, 8, 12.5, 10] } });
  omt('boundary', 'boundary-province', 'line', { minzoom: 8.5, maxzoom: 12.5, filter: ['all', admin(6), land],
    layout: lineLayoutRound(), paint: { 'line-color': P.labelMinor, 'line-opacity': fade(8.5, 9.5, 11.5, 12.5, 0.4),
      'line-width': 0.9, 'line-dasharray': ['literal', [0.1, 2.6]] } });
  omt('boundary', 'boundary-region', 'line', { minzoom: 4.5, filter: ['all', admin(4), land],
    paint: { 'line-color': P.labelMinor, 'line-opacity': fade(4.5, 5.5, 13, 15, 0.5),
      'line-width': zsize(5, 0.5, 9, 0.9, 13, 1.2), 'line-dasharray': ['literal', [4, 2.5]] } });
  for (const [id, disputed] of [['boundary-country', false], ['boundary-country-disputed', true]])
    omt('boundary', id, 'line', { filter: ['all', admin(2), land, [disputed ? '==' : '!=', ['get', 'disputed'], 1]],
      layout: lineLayoutRound(), paint: { 'line-color': P.placeMajor, 'line-opacity': fade(0.5, 1.5, null, null, mode === 'day' ? 0.5 : 0.6),
        'line-width': ['interpolate', ['exponential', 1.5], ['zoom'], 3, 0.6, 6, 1, 10, 1.6, 14, 2.4],
        ...(disputed ? { 'line-dasharray': ['literal', [3, 2]] } : {}) } });

  // ---- roads ----
  const roadCol = (k) => (sat ? P.road : k === 'tertiary' ? P.secondary : P[k]);
  const caseCol = (k) => (sat ? P.roadEdge : k === 'tertiary' ? P.secondaryCase : P[`${k}Case`]);
  const wr = (k) => (z) => interp(W[k], z);
  const caseW = (k, mul = 1) => (z) => interp(W[k], z) + interp(W.caseAdd, z) * mul;
  const lineLayout = { 'line-cap': 'round', 'line-join': 'round' };
  const cls = (k) => inList('class', ROAD[k]);
  if (!sat) for (const k of ORDER) omt('transportation', `road-tunnel-${k}`, 'line', { minzoom: 14.5, filter: ['all', cls(k), ['==', ['get', 'brunnel'], 'tunnel']],
    layout: lineLayout, paint: { 'line-color': P.tunnel, 'line-opacity': fade(14.5, 15.2, null, null, 0.8), 'line-width': width(wr(k)) } });
  const ped = ['all', ['==', ['get', 'class'], 'path'], ['==', ['get', 'subclass'], 'pedestrian'], not('brunnel', 'tunnel')];
  if (!sat) {
    omt('transportation', 'road-pedestrian-case', 'line', { minzoom: 14, filter: ped, layout: lineLayout, paint: { 'line-color': P.pedCase, 'line-opacity': fade(14, 14.6), 'line-width': width(caseW('ped')) } });
    omt('transportation', 'road-pedestrian', 'line', { minzoom: 14, filter: ped, layout: lineLayout, paint: { 'line-color': P.pedFill, 'line-opacity': fade(14, 14.6), 'line-width': w('ped') } });
  }
  const chart = !!P.chartLine;
  const fillFrom = P.fillFrom;
  // Each class fades in as the tiles bring it (ROAD_IN), calmer zoomed out; zoomed-out widths have a floor.
  // Chart hairlines hand over to the outlined streets by cross-fading over XFADE (was a switch at 15.2).
  const roadIn = (k, alpha, out = false) => {
    const classes = ROAD[k], zs = [0, 6, 8, 9.5, ...(out ? XOUT : [15.2]), ...classes.flatMap((c) => ROAD_IN[c])];
    return zfn(zs, (z) => {
      const v = classes.map((c) => r2(alpha * calm(z) * ramp01(...ROAD_IN[c], z) * (out ? 1 - ramp01(...XOUT, z) : 1)));
      return v.every((x) => x === v[0]) ? v[0] : ['match', ['get', 'class'], ...classes.flatMap((c, i) => [c, v[i]]), v[0]];
    });
  };
  const chartW = (k, caseMul = 1) => width((z) => Math.max(interp(W[k], z) * P.chartW + interp(W.caseAdd, z) * caseMul, z < 11 ? CHART_FLOOR[k] ?? 0 : 0));
  if (chart) for (const k of ORDER) omt('transportation', `road-chart-${k}`, 'line', { maxzoom: XOUT[1], filter: ['all', cls(k), surface],
    layout: lineLayout, paint: { 'line-color': P.chartLine, 'line-opacity': roadIn(k, CH_ALPHA[k], true), 'line-width': chartW(k) } });
  const casedFrom = chart ? XFADE[0] : 0;
  const casedIn = chart ? { 'line-opacity': fade(...XFADE) } : {};
  for (const k of ORDER) {
    const big = k === 'primary' || k === 'motor';
    omt('transportation', `road-case-${k}`, 'line', { minzoom: big ? casedFrom : Math.max(casedFrom, 13.5), filter: ['all', cls(k), surface],
      layout: lineLayout, paint: { 'line-color': caseCol(k), 'line-width': width(caseW(k, big ? 1.3 : 1)),
        'line-opacity': chart ? fade(...XFADE) : big ? roadIn(k, 1) : fade(13.5, 14.1) } });
  }
  for (const k of ORDER) omt('transportation', `road-${k}`, 'line', { minzoom: casedFrom, filter: ['all', cls(k), surface],
    layout: lineLayout, paint: { 'line-color': roadCol(k), 'line-width': width(wr(k)), ...(chart ? casedIn : { 'line-opacity': roadIn(k, 1) }) } });
  if (!sat) {
    const pathAlpha = chart ? 0.7 : 1;
    omt('transportation', 'path-footway', 'line', { minzoom: 15, filter: ['all', ['==', ['get', 'class'], 'path'], sub(['footway', 'path']), not('brunnel', 'tunnel')],
      layout: { 'line-cap': 'round' }, paint: { 'line-color': P.path, 'line-opacity': fade(15, 15.6, null, null, pathAlpha), 'line-width': w('path'), 'line-dasharray': dash([1, 2.4], wr('path')) } });
    const stepsW = (z) => interp(W.steps, z) * 2.2;
    omt('transportation', 'path-steps', 'line', { minzoom: 15, filter: ['all', ['==', ['get', 'class'], 'path'], ['==', ['get', 'subclass'], 'steps'], not('brunnel', 'tunnel')],
      layout: { 'line-cap': 'butt' }, paint: { 'line-color': P.steps, 'line-opacity': fade(15, 15.6), 'line-width': width(stepsW), 'line-dasharray': dash([1, 1.6], stepsW) } });
    omt('transportation', 'road-construction', 'line', { minzoom: 15, filter: ['in', '_construction', ['get', 'class']],
      paint: { 'line-color': P.construction, 'line-opacity': fade(15, 15.6), 'line-width': w('minor'), 'line-dasharray': dash([4, 3], wr('minor')) } });
  }
  if (od) {
    const track = ['==', ['get', 'class'], 'track'];
    omt('transportation', 'track-case', 'line', { minzoom: 12, filter: track, layout: lineLayout, paint: { 'line-color': P.trackCase, 'line-opacity': fade(12, 12.8, null, null, 0.9), 'line-width': w('track', 1, 1.6) } });
    omt('transportation', 'track-paved', 'line', { minzoom: 12, filter: ['all', track, ['==', ['get', 'surface'], 'paved']], layout: lineLayout, paint: { 'line-color': P.track, 'line-opacity': fade(12, 12.8), 'line-width': w('track') } });
    omt('transportation', 'track-unpaved', 'line', { minzoom: 12, filter: ['all', track, ['!=', ['get', 'surface'], 'paved']], layout: { 'line-cap': 'butt' },
      paint: { 'line-color': P.track, 'line-opacity': fade(12, 12.8), 'line-width': w('track'), 'line-dasharray': dash([5, 3], wr('track')) } });
    omt('transportation', 'trail', 'line', { minzoom: 13, filter: ['all', ['==', ['get', 'class'], 'path'], sub(['path', 'footway', 'bridleway'])],
      layout: { 'line-cap': 'round' }, paint: { 'line-color': P.track, 'line-opacity': fade(13, 13.8), 'line-width': w('mpath'), 'line-dasharray': dash([0.1, 3.6], wr('mpath')) } });
  }
  // ---- rail + tram ----
  const rail = ['all', ['==', ['get', 'class'], 'rail'], not('brunnel', 'tunnel')];
  omt('transportation', 'rail', 'line', { minzoom: 9.5, filter: ['all', rail, ['!', ['has', 'service']]],
    paint: { 'line-color': P.rail, 'line-opacity': fade(9.5, 11), 'line-width': width((z) => Math.max(0.4, interp(W.rail, z))) } });
  omt('transportation', 'rail-service', 'line', { minzoom: 13, filter: ['all', rail, ['has', 'service']],
    paint: { 'line-color': P.rail, 'line-opacity': fade(13, 14), 'line-width': w('rail') } });
  const tiesW = (z) => interp(W.rail, z) * 3;
  omt('transportation', 'rail-ties', 'line', { minzoom: 14, filter: rail, layout: { 'line-cap': 'butt' },
    paint: { 'line-color': P.rail, 'line-opacity': fade(14, 14.6), 'line-width': width(tiesW), 'line-dasharray': dash([1, 6], tiesW) } });
  const tram = ['all', ['==', ['get', 'class'], 'transit'], ['==', ['get', 'subclass'], 'tram'], not('brunnel', 'tunnel')];
  omt('transportation', 'tram', 'line', { minzoom: 14, filter: tram, layout: lineLayout, paint: { 'line-color': P.tram, 'line-opacity': fade(14, 14.6), 'line-width': w('tram') } });
  omt('transportation', 'tram-groove', 'line', { minzoom: 16, filter: tram, layout: lineLayout,   // twin rails once the line is > 2.2 pt
    paint: { 'line-color': sat ? P.road : P.minor, 'line-width': width((z) => (interp(W.tram, z) > 2.2 ? interp(W.tram, z) - 1.6 : 0)) } });
  // ---- bridges ----
  for (const k of ORDER) {
    const f = ['all', cls(k), ['==', ['get', 'brunnel'], 'bridge']];
    if (chart) omt('transportation', `bridge-chart-${k}`, 'line', { maxzoom: XOUT[1], filter: f, layout: lineLayout,
      paint: { 'line-color': P.chartLine, 'line-opacity': roadIn(k, CH_ALPHA[k], true), 'line-width': chartW(k, 2) } });
    omt('transportation', `bridge-case-${k}`, 'line', { minzoom: casedFrom, filter: f, layout: lineLayout,
      paint: { 'line-color': caseCol(k) || P.secondaryCase, 'line-width': width(caseW(k, 2)), ...casedIn } });
    omt('transportation', `bridge-${k}`, 'line', { minzoom: casedFrom, filter: f, layout: lineLayout,
      paint: { 'line-color': roadCol(k), 'line-width': width(wr(k)), ...casedIn } });
  }

  // ---- cycling infrastructure: only the Bike lanes overlay (z11+), switched in the Map sheet; the base map has none
  // (Filippo, 30 Oct: one place for bike lanes) ----
  const vel = (layer, id, type, extra) => add({ id, type, source: 'velix', 'source-layer': layer, ...extra });
  const kerb = ['interpolate', ['linear'], ['zoom'], 16.9, 0, 17, ['match', ['get', 'side'], 'right', 2, 'left', -2, 0], 19, ['match', ['get', 'side'], 'right', 7, 'left', -7, 0]];
  for (const [prefix, minzoom, mul, alpha, visible] of [['overlay-cycle', 11, 1, 1, false]]) {
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
  omt('building', 'building-flat', 'fill', { minzoom: 13.6, maxzoom: 15, paint: { 'fill-color': ['case', landmark, P.lmRoof, roof], 'fill-opacity': fade(13.6, 14.2) } });
  omt('building', 'building-edge', 'line', { minzoom: 14.2, maxzoom: 15, paint: { 'line-color': P.wallD, 'line-width': 0.4, 'line-opacity': fade(14.2, 14.6, null, null, 0.5) } });
  // Walls lighter at the bottom, darker at the top (Filippo, 30 Oct): MapLibre's own vertical gradient darkens the
  // bottom and can't be reversed, so each building is stacked slices of its height, lighter to darker, with the
  // built-in gradient off. `building-3d` is the bottom slice, `building-3d-1`… the ones above it. The top slice is the
  // roof colour itself, so roofs keep the flat z<15 colour (Filippo, 2 Nov).
  const hgt = ['coalesce', ['get', 'render_height'], 6], minH = ['coalesce', ['get', 'render_min_height'], 0];
  const ramp = (v) => ['interpolate', ['linear'], ['zoom'], 14.6, 0, 15.8, v];
  // Darker: toward black, or (light, 6 Nov) toward the navy ink, so pale walls deepen without going grey.
  const lift = (c, t) => mixHex(c, t > 0 ? (DEEP ? P.placeMajor : '#000000') : '#FFFFFF', Math.abs(t));
  // Landmarks too (Filippo, 2 Nov): their walls shade like every building's.
  const shade = (t) => ['case', landmark, lift(P.lmRoof, t), ['match', roofIdx, ...P.roof.flatMap((c, i) => [i, lift(c, t)]).slice(0, -2),
    lift(P.roof[P.roof.length - 1], t)]];
  // Dark: lighter than the roof colour at the bottom (`wallLift`), the roof colour at the top.
  // Light (Filippo, 6 Nov): one ramp ending in the roof colour, so the roof is its lightest colour and the walls
  // deepen toward the base (DEEP toward the navy ink: pale walls darken without going grey). All slices opaque.
  // The roof is the top face of the last slice, which is the roof colour itself (2 Nov: roofs keep the z<15 colour).
  const DEEP = !sat && mode === 'day' ? 0.2 : 0;
  const at = (f) => ['+', minH, ['*', ['-', hgt, minH], f]];
  const SLICES = 8, LIGHT = -(P.wallLift ?? 0.3), DARK = 0;   // 2 Nov: a stronger gradient (was 14 %, light 35 %)
  for (let i = 0; i < SLICES; i++) {
    const k = i / (SLICES - 1);
    const t = DEEP ? DEEP * (1 - k) : LIGHT + (DARK - LIGHT) * k;
    omt('building', i === 0 ? 'building-3d' : `building-3d-${i}`, 'fill-extrusion', { minzoom: 15, filter: ['!=', ['get', 'hide_3d'], true],
      paint: { 'fill-extrusion-color': shade(t),
        'fill-extrusion-base': ramp(i === 0 ? minH : at(i / SLICES)), 'fill-extrusion-height': ramp(at((i + 1) / SLICES)),
        'fill-extrusion-vertical-gradient': false, 'fill-extrusion-opacity': 1 } });
  }
  if (sat && P.dim) add({ id: 'night-dim', type: 'background', paint: { 'background-color': `rgba(5,8,12,${P.dim})` } });

  // ---- road labels (below the route: it covers its own street names) ----
  const roadLabel = (id, classes, minzoom, bold) => omt('transportation_name', id, 'symbol', { minzoom, filter: inList('class', classes),
    layout: { 'symbol-placement': 'line', 'text-field': LOCAL_NAME, 'text-font': bold ? F_BOLD : F_REG,
      'text-size': zsize(15, 11, 17, 13), 'text-max-angle': 30, 'text-padding': 4, 'symbol-sort-key': 6 },
    paint: { 'text-color': classes.includes('minor') || classes.includes('path') ? P.labelMinor : P.label, 'text-halo-color': P.halo,
      'text-opacity': fade(minzoom, minzoom + 0.4),
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
  halo('route-alt-halo', role('alt'), (z) => Math.max(interp(W.routeCase, z), CASE_MIN) + 3);
  route('route-alt-casing', 'line', { filter: role('alt'), layout: lineLayout, paint: { 'line-color': T.altCase, 'line-width': rw('routeCase') } });
  route('route-alt', 'line', { filter: role('alt'), layout: lineLayout, paint: { 'line-color': T.routeAlt, 'line-width': rw('route') } });
  // Routes tab (P7 S7): every listed route thin in accent ('list'), the one in focus wider on top with a white halo
  // ('focus'); in S7c the others go grey ('list-grey'). Each feature carries its relation `id` (tap to focus).
  route('route-list-grey', 'line', { filter: role('list-grey'), layout: lineLayout,
    paint: { 'line-color': tokenColor('ink3', mode), 'line-opacity': 0.7, 'line-width': rw('route', 0.5) } });
  route('route-list-casing', 'line', { filter: role('list'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('route', 0.5, 2) } });
  route('route-list', 'line', { filter: role('list'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route', 0.5) } });
  route('route-focus-halo', 'line', { filter: role('focus'), layout: lineLayout,
    paint: { 'line-color': '#FFFFFF', 'line-width': width((z) => Math.max(interp(W.routeCase, z), CASE_MIN) + 4) } });
  route('route-focus-casing', 'line', { filter: role('focus'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('routeCase') } });
  route('route-focus', 'line', { filter: role('focus'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route') } });
  // While riding, Best is split: the stretches around the rider ('best-near' and 'best-near-b', 400 m each, taking turns
  // every 200 m so a new one is drawn before the old one goes, 30 Oct) carry the ridden-part fade (a
  // line-gradient set at runtime: its 256-step ramp is fine enough only on a short line), the rest stays 'best'.
  // Casings first, so the two pieces join without a casing cap across the line.
  halo('route-best-halo', role('best'), (z) => Math.max(interp(W.routeCase, z), CASE_MIN) + 3);
  halo('route-best-near-halo', role('best-near'), (z) => Math.max(interp(W.routeCase, z), CASE_MIN) + 3);
  halo('route-best-near-b-halo', role('best-near-b'), (z) => Math.max(interp(W.routeCase, z), CASE_MIN) + 3);
  route('route-best-casing', 'line', { filter: role('best'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('routeCase') } });
  route('route-best-near-casing', 'line', { filter: role('best-near'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('routeCase') } });
  route('route-best-near-b-casing', 'line', { filter: role('best-near-b'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('routeCase') } });
  route('route-best', 'line', { filter: role('best'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route') } });
  route('route-best-near', 'line', { filter: role('best-near'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route') } });
  route('route-best-near-b', 'line', { filter: role('best-near-b'), layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route') } });
  // Train leg drawn as a route with ink ties; metro leg: casing, white core, dashed line colour.
  route('leg-train-casing', 'line', { filter: role('leg-train'), layout: lineLayout, paint: { 'line-color': T.casing, 'line-width': rw('routeCase') } });
  // Overviews: accent with ink ties (P6). Close in (z14+, riding up to the station) the ties crowd: a plain line in
  // the train colour instead (Filippo, 30 Oct).
  route('leg-train', 'line', { filter: role('leg-train'), maxzoom: 14, layout: lineLayout, paint: { 'line-color': T.accent, 'line-width': rw('route') } });
  route('leg-train-near', 'line', { filter: role('leg-train'), minzoom: 14, layout: lineLayout,
    paint: { 'line-color': tokenColor('transitTrain', mode), 'line-width': rw('route') } });
  const tieW = (z) => Math.max(1.6, interp(W.route, z) * 0.34);
  route('leg-train-ties', 'line', { filter: role('leg-train'), maxzoom: 14, layout: { 'line-cap': 'butt' },
    paint: { 'line-color': T.casing, 'line-width': width(tieW), 'line-dasharray': dash([1.1, 0.9].map((x) => x * 9), tieW) } });
  route('leg-metro-casing', 'line', { filter: role('leg-metro'), layout: lineLayout, paint: { 'line-color': T.metroCase, 'line-width': w('leg', 1, 2) } });
  route('leg-metro-core', 'line', { filter: role('leg-metro'), layout: lineLayout, paint: { 'line-color': mode === 'day' ? '#FFFFFF' : '#1E2125', 'line-width': w('leg') } });
  route('leg-metro', 'line', { filter: role('leg-metro'), layout: { 'line-cap': 'butt' },
    paint: { 'line-color': ['get', 'color'], 'line-width': w('leg'), 'line-dasharray': dash([10, 4], (z) => interp(W.leg, z)) } });
  route('hazard-tube', 'line', { filter: role('tube'), layout: { 'line-cap': 'butt', 'line-join': 'round' },
    paint: { 'line-pattern': `hz-stripe-${mode}`, 'line-width': w('tube') } });
  // On foot to the place or the station from where the ride ends: dotted ink (Filippo, 30 Oct).
  route('route-connector', 'line', { filter: role('connector'), layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': T.casing, 'line-width': width((z) => Math.max(2.5, interp(W.route, z) * 0.35)),
      'line-dasharray': ['literal', [0.1, 2]] } });
  // No direction arrows on the route (docs/DECISIONS.md, 21 Oct: Filippo).

  // ---- stations, places, POIs ----
  // Stations grow close in (riding zooms 16–17: Filippo, 30 Oct, too small to spot), their names moving out with them.
  const stationSize = ['interpolate', ['linear'], ['zoom'], 14, 1, 16, 1.6, 18, 2];
  const stationOffset = (x) => ['interpolate', ['linear'], ['zoom'], 14, ['literal', [x, 0.05]], 16, ['literal', [x * 1.5, 0.05]], 18, ['literal', [x * 1.9, 0.05]]];
  const stationName = (minzoom, id, vis) => vel('velix_stations', id, 'symbol', { minzoom, filter: ['==', ['get', 'mode'], 'metro'],
    layout: { visibility: vis, 'icon-image': ['concat', 'metro-', ['get', 'tiles'], `-${mode}`], 'icon-allow-overlap': false,
      'icon-size': stationSize,
      'text-field': ['step', ['zoom'], '', minzoom === 12.5 ? 14 : 15.2, ['get', 'name']], 'text-font': F_BOLD,
      'text-size': ['step', ['zoom'], 11, 16, 12], 'text-anchor': 'left', 'text-justify': 'left', 'text-offset': stationOffset(1.4),
      'text-optional': true, 'symbol-sort-key': 4 },
    paint: { 'text-color': P.placeMajor, 'text-halo-color': P.halo, 'text-halo-width': 1.5, 'icon-opacity': fade(minzoom, minzoom + 0.3),
      'text-opacity': fade(minzoom === 12.5 ? 14 : 15.2, (minzoom === 12.5 ? 14 : 15.2) + 0.3) } });
  stationName(14.6, 'station-metro', 'visible');
  stationName(12.5, 'overlay-station-metro', 'none');
  vel('velix_stations', 'station-rail', 'symbol', { minzoom: 13.5, filter: ['==', ['get', 'mode'], 'train'],
    layout: { 'icon-image': `rail-${mode}`, 'icon-size': stationSize, 'text-field': ['get', 'name'], 'text-font': F_BOLD, 'text-size': 11,
      'text-anchor': 'left', 'text-offset': stationOffset(1.1), 'text-optional': true, 'symbol-sort-key': 4 },
    paint: { 'text-color': P.placeMajor, 'text-halo-color': P.halo, 'text-halo-width': 1.5, 'icon-opacity': fade(13.5, 13.8), 'text-opacity': fade(13.5, 13.8) } });
  // Station entrances from z16 (where the stairs and lifts are: useful with a bike, 30 Oct); their name from z17.
  vel('velix_stations', 'station-entrance', 'symbol', { minzoom: 16, filter: ['==', ['get', 'mode'], 'entrance'],
    layout: { 'icon-image': ['concat', 'entrance-', ['get', 'kind'], `-${mode}`], 'icon-allow-overlap': false, 'icon-padding': 1,
      'text-field': ['step', ['zoom'], '', 17, ['coalesce', ['get', 'name'], '']], 'text-font': F_REG, 'text-size': 10.5,
      'text-anchor': 'left', 'text-offset': ['literal', [1.0, 0.05]], 'text-optional': true, 'symbol-sort-key': 4.2 },
    paint: { 'text-color': P.placeMajor, 'text-halo-color': P.halo, 'text-halo-width': 1.5, 'icon-opacity': fade(16, 16.3), 'text-opacity': fade(17, 17.3) } });
  omt('place', 'label-suburb', 'symbol', { minzoom: 11.5, maxzoom: 15.6, filter: inList('class', ['suburb', 'quarter']),
    layout: { 'text-field': ['upcase', LOCAL_NAME], 'text-font': F_BOLD, 'text-size': 12, 'text-letter-spacing': 0.08, 'symbol-sort-key': 5 },
    paint: { 'text-color': P.place, 'text-opacity': fade(11.5, 12.1, 15, 15.6), 'text-halo-color': P.halo, 'text-halo-width': sat ? 1.75 : 1.5 } });
  omt('place', 'label-neighbourhood', 'symbol', { minzoom: 13.8, maxzoom: 16.4, filter: inList('class', ['neighbourhood']),
    layout: { 'text-field': ['upcase', LOCAL_NAME], 'text-font': F_BOLD, 'text-size': 10.5, 'text-letter-spacing': 0.08, 'symbol-sort-key': 5 },
    paint: { 'text-color': P.labelMinor, 'text-opacity': fade(13.8, 14.4, 15.8, 16.4), 'text-halo-color': P.halo, 'text-halo-width': sat ? 1.75 : 1.5 } });
  // ---- places zoomed out (6 Nov): seas, countries, regions, cities with a dot, towns, villages, lakes, peaks ----
  const textHalo = { 'text-halo-color': P.halo, 'text-halo-width': sat ? 1.75 : 1.5 };
  const placeCls = (c) => ['==', ['get', 'class'], c];
  const rankAtMost = (n) => ['<=', ['coalesce', ['get', 'rank'], 99], n];
  const label = (layer, id, { minzoom, maxzoom, filter, field = PLACE_NAME, font = F_REG, size, color, opacity, spacing, upper, sort, extra = {} }) =>
    omt(layer, id, 'symbol', { minzoom, maxzoom, filter,
      layout: { 'text-field': field, 'text-font': font, 'text-size': size, 'text-max-width': 8, 'text-padding': 3,
        ...(spacing ? { 'text-letter-spacing': spacing } : {}), ...(upper ? { 'text-transform': 'uppercase' } : {}),
        ...(sort ? { 'symbol-sort-key': sort } : {}), ...extra.layout },
      paint: { 'text-color': color, 'text-opacity': opacity, ...textHalo, ...extra.paint } });
  const rankKey = ['coalesce', ['get', 'rank'], 30];
  label('water_name', 'label-water-lake', { minzoom: 8.5, filter: inList('class', ['lake', 'bay', 'lagoon']),
    font: F_REG, size: zsize(9, 10.5, 14, 12.5), color: P.waterInk, opacity: fade(8.5, 9.5), spacing: 0.04 });
  label('water_name', 'label-water-sea', { minzoom: 1.5, maxzoom: 9, filter: inList('class', ['ocean', 'sea', 'strait', 'gulf']),
    font: F_REG, size: zsize(2, 10, 7, 13), color: P.waterInk, opacity: fade(1.5, 2.5, 8, 9, 0.85), spacing: 0.22, upper: true,
    extra: { layout: { 'symbol-placement': 'point', 'text-max-width': 6 } } });
  if (od) label('mountain_peak', 'label-peak', { minzoom: 11, filter: ['all', ['has', 'name'], ['has', 'ele']],
    field: ['concat', LOCAL_NAME, '\n', ['to-string', ['get', 'ele']], ' m'], size: zsize(11, 10, 15, 11.5), color: P.labelMinor,
    opacity: fade(11, 12), sort: ['coalesce', ['get', 'rank'], 30] });
  label('place', 'label-village', { minzoom: 10.2, maxzoom: 15, filter: inList('class', ['village', 'hamlet']),
    size: zsize(10.5, 10.5, 14, 12), color: P.labelMinor, opacity: fade(10.2, 10.8, 14.2, 15), sort: rankKey });
  label('place', 'label-town', { minzoom: 7.2, maxzoom: 14, filter: placeCls('town'), font: F_BOLD,
    size: zsize(7.5, 10.5, 11, 12.5, 13.5, 14), color: P.place, opacity: fade(7.2, 7.8, 13.2, 14), sort: rankKey });
  label('place', 'label-region', { minzoom: 4.5, maxzoom: 8.6, filter: placeCls('state'), size: zsize(5, 10, 8, 11.5),
    color: P.labelMinor, opacity: fade(4.5, 5.3, 7.8, 8.6, 0.9), spacing: 0.15, upper: true, sort: rankKey });
  // Cities: a dot with the name beside it out to z9, then the name alone, centred, growing to z12 and giving way to
  // the suburbs by 13.
  const city = placeCls('city'), major = ['any', rankAtMost(3), ['in', ['get', 'capital'], ['literal', [2, 4]]]];
  const cityFont = ['case', major, ['literal', F_BOLD], ['literal', F_REG]];
  label('place', 'label-city', { minzoom: 9.35, maxzoom: 13, filter: city, font: cityFont, size: zsize(9.35, 12.5, 12, 16.5),
    color: P.placeMajor, opacity: fade(9.35, 9.65, 12.2, 13), sort: rankKey });
  for (const [id, filter, minzoom] of [['label-city-dot', major, 2.5], ['label-city-dot-minor', ['!', major], 5]])
    label('place', id, { minzoom, maxzoom: 9.65, filter: ['all', city, filter],
      font: cityFont, size: zsize(3, 11, 9.35, 12.5), color: P.placeMajor, opacity: fade(minzoom, minzoom + 0.8, 9.35, 9.65), sort: rankKey,
      extra: { layout: { 'icon-image': `dot-${sat ? 'night' : mode}`, 'icon-size': zsize(3, 0.75, 8, 1), 'text-anchor': 'left',
        'text-offset': ['literal', [0.55, 0]], 'text-justify': 'left' }, paint: { 'icon-opacity': fade(minzoom, minzoom + 0.8, 9.35, 9.65) } } });
  for (const [id, filter, minzoom, size] of [['label-country-minor', ['!', rankAtMost(2)], 3.5, zsize(3.5, 9.5, 6, 12)],
    ['label-country', rankAtMost(2), 1.5, zsize(2, 10.5, 4, 12.5, 6.5, 15)]])
    label('place', id, { minzoom, maxzoom: 7.9, filter: ['all', placeCls('country'), filter], font: F_BOLD, size,
      color: P.placeMajor, opacity: fade(minzoom, minzoom + 0.8, 7.3, 7.9, 0.8), spacing: 0.12, upper: true, sort: rankKey,
      extra: { layout: { 'text-max-width': 6 } } });
  omt('poi', 'label-park', 'symbol', { minzoom: 14.5, filter: ['==', ['get', 'class'], 'park'],
    layout: { 'text-field': ['get', 'name'], 'text-font': F_REG, 'text-size': 11.5, 'symbol-sort-key': 7 },
    paint: { 'text-color': P.parkInk, 'text-opacity': fade(14.5, 15), 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  const poiCat = ['match', ['coalesce', ['get', 'subclass'], ''], ...Object.entries(POI_CAT).flatMap(([k, v]) => [k, v]),
    ['match', ['get', 'class'], ...Object.entries(POI_CAT).flatMap(([k, v]) => [k, v]), '']];
  // POIs come in tiers, a few categories at a time (Filippo, 2 Nov: every POI appearing at one zoom stalled the
  // pinch for a moment while MapLibre placed them all). Sparse and useful to a rider first; shops and food last, the
  // more important of them (OpenMapTiles `rank`, lower is more important) before the rest; names a step later.
  const rank = ['coalesce', ['get', 'rank'], 50];
  const POI_TIERS = [
    ['poi-t1', 15.4, 16.8, ['bike', 'water', 'health']],
    ['poi-t2', 15.8, 16.8, ['culture', 'worship', 'edu']],
    ['poi-t3', 16.2, 17.0, ['green', 'lodging', 'generic']],
    ['poi-t4', 16.6, 17.2, ['food', 'shop'], ['<=', rank, 20]],
    ['poi-t5', 17.2, 17.8, ['food', 'shop'], ['>', rank, 20]],
  ];
  for (const [id, minzoom, names, cats, more] of POI_TIERS) omt('poi', id, 'symbol', { minzoom,
    filter: ['all', ['!=', ['get', 'class'], 'park'], ['in', poiCat, ['literal', cats]],
      ['any', ['has', 'name'], ['in', poiCat, ['literal', ['bike', 'water']]]], ...(more ? [more] : [])],
    layout: { 'icon-image': ['concat', 'poi-', poiCat, `-${mode}`], 'icon-size': zsize(16.8, 1, 17.2, r2(8 / 6.5)),
      'text-field': ['step', ['zoom'], '', names, ['coalesce', ['get', 'name'], '']], 'text-font': F_REG, 'text-size': 11,
      'text-anchor': 'left', 'text-offset': ['literal', [1.0, 0.05]], 'text-optional': true, 'symbol-sort-key': ['+', 7, ['/', rank, 100]] },
    // Names in their category's colour (overrides.json `poi`), so shops, food and the rest read apart.
    paint: { 'icon-opacity': fade(minzoom, minzoom + 0.3), 'text-opacity': fade(names, names + 0.3),
      'text-color': ['match', poiCat, ...Object.keys(P.poi).filter((c) => overrides.poi?.[c]).flatMap((c) => [c, poiColor(c, mode, P)]), P.poiInk],
      'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  // While riding (the app swaps it in for the tiers above): bike shops and drinking water only, icons
  // without names. Every shop and café of central Milan made the iPhone 11 re-place thousands of symbols each frame
  // of the moving camera (3 fps instead of 60, 30 Oct), and they aren't what a rider looks at.
  // Bike parking left out too (Filippo, 30 Oct: riders park where they like): bike shops and water.
  const bikeShop = ['all', ['==', ['get', 'class'], 'bicycle'], ['!=', ['coalesce', ['get', 'subclass'], ''], 'bicycle_parking']];
  omt('poi', 'poi-riding', 'symbol', { minzoom: 15.6,
    filter: ['any', bikeShop, ['==', ['coalesce', ['get', 'subclass'], ''], 'bicycle'], ['==', poiCat, 'water']],
    layout: { visibility: 'none', 'icon-image': ['case', ['==', poiCat, 'water'], `poi-water-${mode}`, `poi-bikeshop-${mode}`],
      'icon-size': zsize(16.8, 1, 17.2, r2(8 / 6.5)), 'symbol-sort-key': 7 }, paint: { 'icon-opacity': fade(15.6, 15.9) } });
  omt('housenumber', 'housenumber', 'symbol', { minzoom: 17.6,
    layout: { 'text-field': ['get', 'housenumber'], 'text-font': F_REG, 'text-size': 9.5, 'symbol-sort-key': 8 },
    paint: { 'text-color': P.hn, 'text-opacity': fade(17.6, 18), 'text-halo-color': P.halo, 'text-halo-width': 1.5 } });
  vel('velix_routes', 'eurovelo-badge', 'symbol', { minzoom: 9, layout: { visibility: 'none', 'symbol-placement': 'line', 'symbol-spacing': 280,
    'icon-image': ['concat', 'ev-', ['get', 'ref']], 'icon-size': ['interpolate', ['linear'], ['zoom'], 9, 20 / 24, 15, 1], 'symbol-sort-key': 4.5 } });

  // ---- markers: hazards (clusters below z15, markers + pips from z15), avoided tags, endpoints, puck ----
  add({ id: 'hazard-pip', type: 'circle', source: 'velix-hazards', minzoom: 15, filter: ['!', ['has', 'point_count']],
    paint: { 'circle-radius': 3, 'circle-color': T.hazard, 'circle-stroke-color': T.hazardRing, 'circle-stroke-width': 1.5 } });
  add({ id: 'hazard-cluster', type: 'symbol', source: 'velix-hazards', filter: ['has', 'point_count'],
    layout: { 'icon-image': ['concat', 'cnt-', ['to-string', ['get', 'point_count']], `-${mode}`], 'icon-size': zsize(14.2, r2(16 / 28), 14.8, r2(22 / 28)),
      'icon-anchor': 'bottom', 'icon-allow-overlap': true,
      'symbol-sort-key': ['-', 0, ['get', 'point_count']] } });
  add({ id: 'hazard-marker', type: 'symbol', source: 'velix-hazards', minzoom: 15, filter: ['!', ['has', 'point_count']],
    layout: { 'icon-image': ['concat', 'hz-', ['get', 'hazard'], `-${mode}`], 'icon-size': zsize(16.2, r2(22 / 28), 16.8, 1),
      'icon-anchor': 'bottom', 'icon-allow-overlap': false,
      'icon-padding': 2, 'symbol-sort-key': ['get', 'rank'] } });
  add({ id: 'avoided-tag', type: 'symbol', source: 'velix-markers', minzoom: 14, filter: role('avoided-tag'),
    layout: { 'icon-image': ['concat', 'avoided-', ['get', 'id'], `-${mode}`], 'icon-allow-overlap': false, 'symbol-sort-key': 1 } });
  add({ id: 'route-start', type: 'symbol', source: 'velix-markers', filter: role('start'),
    layout: { 'icon-image': `start-${mode}`, 'icon-size': 1, 'icon-allow-overlap': true, 'symbol-sort-key': 2 } });
  // Bike + transit: getting on and off (the train leg itself isn't drawn without rail geometry, 30 Oct).
  add({ id: 'route-change', type: 'symbol', source: 'velix-markers', filter: role('change'),
    layout: { 'icon-image': ['concat', 'change-', ['get', 'mode'], `-${mode}`], 'icon-allow-overlap': true, 'symbol-sort-key': 2 } });
  add({ id: 'route-end', type: 'symbol', source: 'velix-markers', filter: role('end'),
    layout: { 'icon-image': `end-${mode}`, 'icon-size': 1, 'icon-allow-overlap': true,
      'text-field': ['coalesce', ['get', 'name'], ''], 'text-font': F_BOLD, 'text-size': 13, 'text-anchor': 'bottom', 'text-offset': ['literal', [0, -1.2]],
      'text-optional': true, 'symbol-sort-key': 2 },
    paint: { 'text-color': sat ? '#FFFFFF' : P.lmInk, 'text-halo-color': P.halo, 'text-halo-width': 1.75 } });
  // S7 key tiles (numbered, accent when in focus), drawn by the app (MapImages `key-<n>[-sel]`).
  // The others give way when they collide (keys near Milan bunch up); the one in focus always shows.
  add({ id: 'route-key', type: 'symbol', source: 'velix-markers', filter: ['all', role('key'), ['!', ['get', 'focus']]],
    layout: { 'icon-image': ['concat', 'key-', ['to-string', ['get', 'key']], `-${mode}`], 'icon-padding': 4,
      'symbol-sort-key': ['get', 'key'] } });
  add({ id: 'route-key-focus', type: 'symbol', source: 'velix-markers', filter: ['all', role('key'), ['get', 'focus']],
    layout: { 'icon-image': ['concat', 'key-', ['to-string', ['get', 'key']], '-sel', `-${mode}`], 'icon-allow-overlap': true } });
  add({ id: 'puck', type: 'symbol', source: 'velix-markers', filter: role('puck'),
    layout: { 'icon-image': ['step', ['zoom'], 'puck-22', 14, 'puck-34', 16, 'puck-46'], 'icon-rotate': ['coalesce', ['get', 'heading'], 0],
      'icon-rotation-alignment': 'map', 'icon-allow-overlap': true, 'icon-ignore-placement': true } });

  const empty = { type: 'geojson', data: { type: 'FeatureCollection', features: [] } };
  return {
    version: 8,
    name: `Velix ${name} ${mode}`,
    metadata: { 'velix:generator': 'tools/stylegen/stylegen.mjs', 'velix:source': 'design/p3v3 (palettes.js, render.js)', 'velix:style': name, 'velix:mode': mode },
    glyphs: 'asset://MapStyle/glyphs/{fontstack}/{range}.pbf',
    // A higher sun from the south-west (30 Oct): softer walls, roofs lit; dimmer at night. White, so a roof (facing the
    // light) renders at exactly its colour: a tinted light turned the light style's blue roofs ochre (Filippo, 2 Nov).
    light: { anchor: 'map', position: [1.15, 210, 30], color: '#FFFFFF', intensity: mode === 'day' ? 0.42 : 0.2 },
    sources: {
      // Every installed pack as one source, served by the app (PackTileProtocol.swift): regions side by side.
      omt: { type: 'vector', tiles: ['https://tiles.velix.invalid/basemap/{z}/{x}/{y}'], minzoom: 0, maxzoom: 14,
        attribution: '© OpenMapTiles © OpenStreetMap contributors' },
      velix: { type: 'vector', tiles: ['https://tiles.velix.invalid/overlays/{z}/{x}/{y}'], minzoom: 8, maxzoom: 14 },
      // Elevation for the hillshade, online only (PackTileProtocol `terrain`: Mapterhorn, through the tile cache).
      terrain: { type: 'raster-dem', tiles: ['https://tiles.velix.invalid/terrain/{z}/{x}/{y}'], tileSize: 512, encoding: 'terrarium',
        minzoom: 0, maxzoom: 12, attribution: '© Mapterhorn (Copernicus GLO-30 and national elevation data)' },
      'velix-route': { ...empty, lineMetrics: true },
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
      `        poi: [${cats.map((c) => `"${c}": ${hex(poiColor(c, m, P))}`).join(', ')}],`, `        poiAlpha: ${P.poiAlpha}`];
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
