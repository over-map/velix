# M2 hazard spot check (14 Oct 2026)

3 random hazards per type in Milan from `hazards.sqlite` (pack 2026.10), checked against live OpenStreetMap (API v0.6, 14 Oct). Skill requirement: velix-region-pack "Spot-check 3 hazards per type".

| Type | OSM | Where | OSM says | Result |
|---|---|---|---|---|
| tram | n295561825 | 45.46584, 9.12779 | `railway=tram_level_crossing` | ✅ |
| tram | n9965892821 | 45.44208, 9.18306 | `railway=tram_crossing` | ✅ |
| tram | n1476095583 | 45.48567, 9.21007 | `railway=tram_level_crossing` | ✅ |
| along | w59428297 Via G.B. Viotti | 45.48203, 9.23786 | rails within 1.3 m along 43 of its 44 m (tram junction) | ✅ |
| along | w183411381 Piazza Prealpi | 45.49455, 9.15333 | residential street with tram tracks | ✅ (geometry) |
| along | w369267846 Piazzale Baracca | 45.46649, 9.16496 | residential street with tram tracks | ✅ (geometry) |
| cobbles | w398835700 Via Don F. Tornaghi | 45.43992, 9.11355 | `highway=cycleway`, `surface=sett` | ✅ |
| cobbles | w239599824 | 45.50071, 9.26629 | `highway=pedestrian` (bicycle designated), `surface=sett` | ✅ |
| cobbles | w259729490 Via Trasimeno | 45.51712, 9.25187 | `surface=sett` | ✅ |
| steps | w1175289839 / w1498800018 / w1365068569 | Milan | `highway=steps` | ✅ ✅ ✅ |
| gap | n4299971969 / n7142996429 | Milan | `barrier=gate` | ✅ ✅ |
| gap | n355712607 | 45.46179, 9.25574 | `barrier=cycle_barrier` | ✅ |
| dismount | w495490852 / w138917479 Piazza della Scienza / w1463770907 | Milan | `highway=pedestrian`, no bicycle access | ✅ ✅ ✅ |
| door | w266653600 Via Pola | 45.48894, 9.19346 | `cycleway=lane` + `parking:lane:both=parallel` | ✅ |
| door | w859694091 Piazzale Loreto | 45.48635, 9.21629 | `cycleway:right=lane` + `parking:lane:right=parallel` | ✅ |
| door | w269510013 Viale Monza | 45.49763, 9.22010 | `cycleway=lane` + `parking:lane:right=parallel` | ✅ |
| lane | n2394469837 Viale Marche | 45.49478, 9.19781 | first node of a one-way section that *starts* a lane | ❌ **false positive → fixed** (direction-aware rule, see below) |
| lane | n25543602 Via Mincio | 45.43815, 9.21960 | one-way cycleway ends on residential streets | ✅ (after fix) |
| lane | n1328900777 Via M. Gioia | 45.49276, 9.20504 | one-way segregated cycleway ends on Via Melchiorre Gioia | ✅ (after fix) |
| lane | n2781431566 Via A. Tosi | 45.44370, 9.16374 | two-way cycleway ends on Via Arturo Tosi (riding against the way direction) | ✅ (after fix) |

**Fix:** lane ends now respect one-way direction: only the downstream end of a one-way lane counts. Every lane end also stores the travel `heading` it applies to, so M7 can alert only riders going that way. Count: 11,098 → 10,420.

**Note on `door` (19 in Lombardy):** few because Milan's on-street parking is rarely tagged in OSM. The ones found are correct.
