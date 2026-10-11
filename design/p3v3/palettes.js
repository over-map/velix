(function(){ if(window.VX&&window.VX.PAL) return;
// Velix "Chart" direction (P2 v2 / P3 v3). Base: 9 colours. Signals: accent, hazard, avoided (+ 12 metro colour families).
// Abyss #021624 · Navy #042940 · Slate #2C5870 · Teal #005C53 · Khaki #D6D58E · Lime #9FC131 · Mist #B0ADAD · Paper #EFEEE2 · Chartreuse #DBF227 (accent)
window.VX = window.VX || {};
VX.CORE = { abyss:'#021624', navy:'#042940', slate:'#2C5870', teal:'#005C53', khaki:'#D6D58E', lime:'#9FC131', mist:'#B0ADAD', paper:'#EFEEE2', accent:'#DBF227', hazard:'#E0532A', avoided:'#7A4FD6' };
VX.TK = {
  day:  { accent:'#DBF227', accentInk:'#021624', casing:'#021624', routeAlt:'#6A808B', altCase:'#FFFFFF', hazard:'#E0532A', hazardInk:'#1A0A03', hazardRing:'#021624', avoided:'#7A4FD6', avoidedInk:'#5B34B8', surface:'#FFFFFF', ink:'#021624', prot:'#4E8A12', paint:'#0A7F73', tick:'#BFE3DC', train:'#415C70', metroCase:'#021624' },
  night:{ accent:'#DBF227', accentInk:'#021624', casing:'#021624', routeAlt:'#9AA6AA', altCase:'#021624', hazard:'#FF7A4F', hazardInk:'#1A0A03', hazardRing:'#1A0A03', avoided:'#B79CFF', avoidedInk:'#CDBBFF', surface:'#0A2E45', ink:'#EEEDD6', prot:'#9FC131', paint:'#7FD1C3', tick:'#1E5A55', train:'#B0ADAD', metroCase:'#E9EBEE' }
};
// Metro: 12 colour families for every European network. A line's OSM colour=* snaps to a family; the 2nd line of one family in a city takes the alt tone.
VX.METRO_FAM = {
  red:      { main:'#C8102E', alt:'#94101F', ink:'#FFFFFF', altInk:'#FFFFFF' },
  orange:   { main:'#F08A00', alt:'#C46A00', ink:'#021624', altInk:'#021624' },
  yellow:   { main:'#F5C400', alt:'#C99A00', ink:'#021624', altInk:'#021624' },
  olive:    { main:'#9C9A2E', alt:'#757318', ink:'#021624', altInk:'#FFFFFF' },
  green:    { main:'#0F9158', alt:'#4DB37A', ink:'#021624', altInk:'#021624' },
  cyan:     { main:'#1AA6C4', alt:'#0B86A8', ink:'#021624', altInk:'#021624' },
  lightblue:{ main:'#5AAEE6', alt:'#3C8CC8', ink:'#021624', altInk:'#021624' },
  blue:     { main:'#1F5FB5', alt:'#163F80', ink:'#FFFFFF', altInk:'#FFFFFF' },
  purple:   { main:'#9A3A92', alt:'#6E2470', ink:'#FFFFFF', altInk:'#FFFFFF' },
  pink:     { main:'#E46FA8', alt:'#C24F88', ink:'#021624', altInk:'#FFFFFF' },
  brown:    { main:'#8A5A2B', alt:'#B07A45', ink:'#FFFFFF', altInk:'#021624' },
  grey:     { main:'#8C9196', alt:'#4A4F55', ink:'#021624', altInk:'#FFFFFF' }
};
VX.oklch = h=>{ const lin=x=>{x/=255;return x<=0.04045?x/12.92:Math.pow((x+0.055)/1.055,2.4)}; const r=lin(parseInt(h.substr(1,2),16)),g=lin(parseInt(h.substr(3,2),16)),b=lin(parseInt(h.substr(5,2),16)); const l=Math.cbrt(.4122214708*r+.5363325363*g+.0514459929*b),m=Math.cbrt(.2119034982*r+.6806995451*g+.1073969566*b),s=Math.cbrt(.0883024619*r+.2817188376*g+.6299787005*b); const L=.2104542553*l+.793617785*m-.0040720468*s,A=1.9779984951*l-2.428592205*m+.4505937099*s,B=.0259040371*l+.7827717662*m-.808675766*s; return [L,Math.hypot(A,B),(Math.atan2(B,A)*180/Math.PI+360)%360]; };
VX.metroFamily = hex=>{ const [L,C,H]=VX.oklch(hex); if(C<0.04) return 'grey'; if(H>=30&&H<95&&L<0.6&&C<0.16) return 'brown';
  if(H<15||H>=330){ if(L>=0.68) return 'pink'; if(H>=330&&H<350) return 'purple'; if(H>=350&&L<0.5) return 'purple'; return 'red'; }
  if(H<30) return 'red'; if(H<70) return 'orange'; if(H<100) return L>0.66?'yellow':'olive'; if(H<130) return L>0.82?'yellow':'olive'; if(H<165) return 'green'; if(H<215) return 'cyan'; if(H<275) return L>0.64?'lightblue':'blue'; return 'purple'; };
// Illustrative city mapping by family (not official hex). [ref, family, alt?]
VX.METRO_CITIES = [
  ['Milan',[['M1','red'],['M2','green'],['M3','yellow'],['M4','blue'],['M5','purple']]],
  ['Rome',[['A','orange'],['B','blue'],['C','green']]],
  ['Paris',[['1','yellow'],['2','blue'],['3','olive'],['3b','lightblue'],['4','purple'],['5','orange'],['6','green',1],['7','pink'],['7b','green'],['8','purple',1],['9','olive',1],['10','yellow',1],['11','brown'],['12','green'],['13','lightblue',1],['14','purple']]],
  ['London',[['Bak','brown'],['Cen','red'],['Cir','yellow'],['Dis','green'],['H&C','pink'],['Jub','grey'],['Met','purple'],['Nor','grey',1],['Pic','blue',1],['Vic','lightblue'],['W&C','cyan'],['Eliz','purple',1]]],
  ['Madrid',[['1','lightblue'],['2','red'],['3','yellow'],['4','brown'],['5','green'],['6','grey'],['7','orange'],['8','pink'],['9','purple'],['10','blue'],['11','green',1],['12','olive']]],
  ['Barcelona',[['L1','red'],['L2','purple'],['L3','green'],['L4','yellow'],['L5','blue'],['L9','orange'],['L10','lightblue'],['L11','green',1]]],
  ['Berlin',[['U1','green',1],['U2','red'],['U3','cyan'],['U4','yellow'],['U5','brown'],['U6','purple'],['U7','lightblue'],['U8','blue'],['U9','orange']]],
  ['Munich',[['U1','green'],['U2','red'],['U3','orange'],['U4','cyan'],['U5','brown'],['U6','blue']]],
  ['Vienna',[['U1','red'],['U2','purple'],['U3','orange'],['U4','green'],['U6','brown']]],
  ['Amsterdam',[['50','green'],['51','orange'],['52','lightblue'],['53','red'],['54','yellow']]],
  ['Brussels',[['1','purple'],['2','orange'],['5','yellow'],['6','lightblue']]],
  ['Lisbon',[['Az','blue'],['Am','yellow'],['Ve','green'],['Vm','red']]],
  ['Prague',[['A','green'],['B','yellow'],['C','red']]],
  ['Budapest',[['M1','yellow'],['M2','red'],['M3','blue'],['M4','green']]],
  ['Warsaw',[['M1','blue'],['M2','red']]],
  ['Copenhagen',[['M1','green'],['M2','yellow'],['M3','red'],['M4','lightblue']]],
  ['Stockholm',[['T10','blue'],['T11','blue'],['T13','red'],['T14','red'],['T17','green'],['T18','green'],['T19','green']]],
  ['Athens',[['1','green'],['2','red'],['3','blue']]]
];
VX.METRO = { M1:VX.METRO_FAM.red.main, M2:VX.METRO_FAM.green.main, M3:VX.METRO_FAM.yellow.main, M4:VX.METRO_FAM.blue.main, M5:VX.METRO_FAM.purple.main };
VX.METRO_INK = { M1:'#FFFFFF', M2:'#021624', M3:'#021624', M4:'#FFFFFF', M5:'#FFFFFF' };
// EuroVelo: all 17 routes (ECF list, checked 9 Oct 2026; re-check yearly). Lines from OSM route=bicycle, network=icn, ref=EV*.
VX.EUROVELO = [[1,'Atlantic Coast Route'],[2,'Capitals Route'],[3,'Pilgrims Route'],[4,'Central Europe Route'],[5,'Via Romea (Francigena)'],[6,'Atlantic – Black Sea'],[7,'Sun Route'],[8,'Mediterranean Route'],[9,'Baltic – Adriatic'],[10,'Baltic Sea Cycle Route'],[11,'East Europe Route'],[12,'North Sea Cycle Route'],[13,'Iron Curtain Trail'],[14,'Waters of Central Europe'],[15,'Rhine Cycle Route'],[17,'Rhone Cycle Route'],[19,'Meuse Cycle Route']];
const one=(c,w)=>({ food:c,shop:c,edu:c,health:c,culture:c,worship:c,lodging:c,green:c,bike:c,water:w,generic:c });
const CH_ALPHA={ motor:1, primary:1, secondary:.9, tertiary:.8, minor:.55, service:.4 };
const DAY = {
  land:'#EFEEE2', residential:'#E7E7D9', commercial:'#E3E4D8', retail:'#E3E4D8', industrial:'#E4E3D6', railway:'#E4E3D6', education:'#E9E7D2', hospital:'#E9E7D2', cemetery:'#D3DDB4', military:'#E4E3D6', pitch:'#D3DFA6', pitchLine:'#EEF2DA', playground:'#DCE4B8',
  grass:'#DCE3C0', park:'#CBDC8C', wood:'#BBD07E', woodDot:'#9DB860', farmland:'#E9E7CF', scrub:'#D2DCB0', sand:'#E7E2C2',
  water:'#8EC6BC', waterLine:'#5FA89B', waterInk:'#005C53',
  pedFill:'#F6F5EC', pedCase:'#C9CDBF', square:'#F3F2E8',
  chartLine:'#2C5870', chartAlpha:CH_ALPHA, chartW:.55, fillFrom:15.2,
  motor:'#FFFFFF', motorCase:'#5E7883', primary:'#FFFFFF', primaryCase:'#8FA3A8', secondary:'#FFFFFF', secondaryCase:'#A5B4B3', minor:'#FFFFFF', minorCase:'#BFC7BE', service:'#FBFBF5', serviceCase:'#CCD1C6', tunnel:'#E2E3D8', construction:'#E5E4D6',
  path:'#6F8A8F', steps:'#5E7883', rail:'#8E8B8B', tram:'#8E8B8B',
  roof:['#D4DEDC','#D0DAD8','#D8E1DE','#CDD8D6'], wallL:'#BCCBCB', wallM:'#A6B8BA', wallD:'#8EA3A8', edge:'#F2F5F2', shadow:'rgba(2,22,36,0.16)',
  lmRoof:'#E4E7B0', lmWallL:'#CFD195', lmWallM:'#B8BA7C', lmWallD:'#9D9F63', lmEdge:'#F4F5D8',
  label:'#2C5870', labelMinor:'#4F6E7E', halo:'#F4F3EA', place:'#005C53', placeMajor:'#042940', hn:'#7E9198', poiInk:'#3E6B1E', lmInk:'#021624', parkInk:'#3E6B1E',
  poi:one('#5E8A22','#00766A'), poiAlpha:1, glyph:'#FFFFFF', chrome:'#021624', chromeInk:'#EEEDD6', attr:'#4F6570', scaleBg:'rgba(255,255,255,.85)'
};
const NIGHT = {
  land:'#042940', residential:'#0B3350', commercial:'#113953', retail:'#113953', industrial:'#09304A', railway:'#09304A', education:'#14394C', hospital:'#14394C', cemetery:'#2A4528', military:'#09304A', pitch:'#28422D', pitchLine:'#3E6B3A', playground:'#28422D',
  grass:'#1F3B33', park:'#4A6A22', wood:'#2C4C27', woodDot:'#6F9A2C', farmland:'#123630', scrub:'#22403A', sand:'#35633E',
  water:'#005C53', waterLine:'#00776B', waterInk:'#5FC2B4',
  pedFill:'#1C4560', pedCase:'#3F6274', square:'#173F58',
  chartLine:'#D6D58E', chartAlpha:CH_ALPHA, chartW:.55, fillFrom:15.2,
  motor:'#17465F', motorCase:'#D6D58E', primary:'#133F5A', primaryCase:'#D6D58E', secondary:'#103A54', secondaryCase:'#C3C389', minor:'#0D3550', minorCase:'#8F9C78', service:'#0A3049', serviceCase:'#5F7A6E', tunnel:'#0D3550', construction:'#173E56',
  path:'#D6D58E', steps:'#D6D58E', rail:'#B0ADAD', tram:'#B0ADAD',
  roof:['#2C5870','#2A556D','#2F5B73','#295369'], wallL:'#3A6A84', wallM:'#214A62', wallD:'#163A50', edge:'#042940', shadow:'rgba(1,10,18,0.55)',
  lmRoof:'#4B7F8E', lmWallL:'#3B6E7E', lmWallM:'#2A5868', lmWallD:'#1E4656', lmEdge:'#9FC131',
  label:'#9FC131', labelMinor:'#86A632', halo:'#021624', place:'#9FC131', placeMajor:'#D6D58E', hn:'#5E7F3A', poiInk:'#9FC131', lmInk:'#EEEDD6', parkInk:'#B5D35A',
  poi:one('#9FC131','#5FC2B4'), poiAlpha:.75, glyph:'#021624', chrome:'#D6D58E', chromeInk:'#021624', attr:'#9FC131', scaleBg:'rgba(2,22,36,.85)'
};
const OD_DAY = Object.assign({}, DAY, { land:'#F0EEDF', meadow:'#D9E2B0', golf:'#CBDDA0', contour:'#C9C79A', contourIdx:'#A3A06A', contourInk:'#7F7C45', track:'#6E5A1E', trackCase:'#F7F6EA', shadeDark:'2,22,36', shadeLight:'255,255,240', spring:'#00766A' });
const OD_NIGHT = Object.assign({}, NIGHT, { meadow:'#2A4A2C', golf:'#2E5232', contour:'#2E4E46', contourIdx:'#55704A', contourInk:'#9FC131', track:'#D6D58E', trackCase:'#042940', shadeDark:'1,10,18', shadeLight:'44,73,70', spring:'#5FC2B4' });
const SAT_DAY = Object.assign({}, DAY, {
  sat:true, land:'#5F625B', ground:['#5E615A','#666860','#585B55','#6B6A62'], grass:'#5E6D45', park:'#5A6B42', wood:'#3E4E31', woodDot:'#34432A', farmland:'#7A7756', scrub:'#58653F', water:'#2E4148', waterLine:'#2E4148',
  road:'#77766F', roadEdge:'#55554F', rail:'#4E4B46', tram:'#4E4B46', chartLine:null,
  roof:['#9C6F5B','#8B8378','#A69B8C','#7D756B','#B28B73','#6F6A63'], wallL:'#5F5A54', wallM:'#4E4A45', wallD:'#3D3A36', edge:'#B3AA9C', shadow:'rgba(10,12,8,0.45)',
  lmRoof:'#B9A58A', lmWallL:'#7E715F', lmWallM:'#665B4C', lmWallD:'#4E463B', lmEdge:'#D6C6AC',
  label:'#FFFFFF', labelMinor:'#F2F2EF', halo:'#021624', place:'#DBF227', placeMajor:'#FFFFFF', hn:'#E0E0DA', poiInk:'#FFFFFF', lmInk:'#FFFFFF', parkInk:'#FFFFFF', waterInk:'#FFFFFF',
  chrome:'#EEEDD6', chromeInk:'#021624', attr:'#EEEDD6', scaleBg:'rgba(2,22,36,.8)', dim:0
});
const SAT_NIGHT = Object.assign({}, SAT_DAY, { dim:0.55, label:'#9FC131', place:'#9FC131' });
VX.PAL = { standard:{day:DAY,night:NIGHT}, outdoor:{day:OD_DAY,night:OD_NIGHT}, satellite:{day:SAT_DAY,night:SAT_NIGHT} };
// MapLibre zooms (512 px tiles). Reference-style ramps: hairlines to z15, then streets open up to real width by z18–19.
VX.W = {
  motor:{11:1,13:1.6,15:4,17:12,19:40}, primary:{11:.6,13:1.2,15:3.4,17:11,19:36}, secondary:{11:.4,13:.9,15:2.8,17:9,19:30}, tertiary:{12:.3,13:.7,15:2.4,17:8,19:26},
  minor:{13:.3,14:.6,15:1.4,17:6,19:20}, service:{14:.3,15:.6,17:3,19:10}, ped:{14:.8,15:1.4,17:5,19:16}, path:{14:.3,15:.5,17:.9,19:1.6}, steps:{15:.6,17:2,19:4.5},
  caseAdd:{13:.4,15:.8,17:1.2,19:1.8}, rail:{11:.4,13:.6,15:1,17:2,19:3}, tram:{13:.5,15:1.2,17:3,19:6},
  bike:{11:1,13:1.5,15:3,17:5,19:8}, metro:{10:1,13:1.6,15:2.5,17:4,19:6},
  routeCase:{11:5,13:8,15:13,17:20,19:28}, route:{11:3,13:5,15:9,17:14,19:20}, alt:{11:2,13:3,15:5,17:8,19:12}, altCase:{11:3.5,13:5,15:8,17:11,19:16},
  tube:{11:3,13:5,15:9,17:14,19:20}, avoided:{11:1.5,13:2,15:3,17:4,19:6}, leg:{11:2,13:3,15:5,17:7,19:10},
  track:{12:.8,14:1.2,16:2.2,18:4.5}, mpath:{13:.5,15:.9,17:1.6,19:2.6}, water:{11:.8,13:1.5,15:3.5,17:9}
};

})();