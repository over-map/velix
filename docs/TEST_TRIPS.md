# Test trips (golden routes)

Ten trips × six ride types = 60 golden cases, run by `Tests/Golden/GoldenRouteTests.swift` against a real region pack.

```bash
TEST_RUNNER_VELIX_PACK_DIR=$PWD/pipeline/out/lombardy TEST_RUNNER_VELIX_GOLDEN_OUT=$PWD/build/golden \
  xcodebuild -scheme Velix -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' -derivedDataPath build/DerivedData \
  -skipMacroValidation -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO test -only-testing:VelixGoldenTests
```

## Trips

| # | Trip | From → to (lat,lon) | Why it's here |
|---|---|---|---|
| 1 | Porta Venezia → Politecnico | 45.4746,9.2050 → 45.4781,9.2272 | Daily commute; tram crossings in Città Studi; the pinned M1 benchmark. |
| 2 | Duomo → Bicocca | 45.4642,9.1900 → 45.5140,9.2110 | Design example: avoid busy Viale Fulvio Testi / Viale Monza. |
| 3 | Darsena → Città Studi | 45.4520,9.1757 → 45.4760,9.2350 | Cross-city; tram corridors and the cobbled centre. |
| 4 | Stazione Centrale → Brera (Via Fiori Chiari) | 45.4855,9.2035 → 45.4720,9.1865 | Cobbled destination: Cargo may be blocked by No cobbles. |
| 5 | Porta Romana → Arco della Pace | 45.4520,9.2030 → 45.4757,9.1725 | Through the centre: cobbles, pedestrian zones, tram streets. |
| 6 | San Siro → Duomo | 45.4781,9.1240 → 45.4642,9.1900 | Long western axis: lanes vs busy roads, tram streets near the centre. |
| 7 | Darsena → Abbiategrasso (Naviglio Grande) | 45.4520,9.1757 → 45.3986,8.9188 | 22 km Naviglio Grande towpath; Darsena start among tram rails. |
| 8 | Stazione Centrale → Villa Reale, Monza | 45.4855,9.2035 → 45.5885,9.2740 | 15 km out of Milan (transit trigger later); park paths in Monza. |
| 9 | Bovisa → Parco Nord | 45.5020,9.1590 → 45.5300,9.1960 | Off-road park network: Gravel/MTB go more off-road than Fastest. |
| 10 | Bergamo FS → Città Alta | 45.6905,9.6750 → 45.7037,9.6625 | Steep: Max grade 6 % blocks Cargo; climbs for the others. |

## What every case must satisfy (robust to monthly OSM changes)

- A route exists (`noRoute` fails the test).
- **Cargo / kids** (strict): either Best meets every active rule, or the result is *No route meets your Cargo / kids rules* for a rule listed as an expected block below.
- **Other ride types** (soft rules, design: City Best keeps 70 m of cobbles with *No cobbles* on): never blocked, and Best scores no worse than Fastest on time + rule penalty.
- Fastest is never slower than Best. A separate Fastest card only when it is ≥ 5 % quicker; otherwise one *Best and fastest* card with its line.
- Road: ≤ 200 m unpaved. Gravel/MTB on trips 7 and 9: at least as off-road as Fastest. City trip 2: < 500 m on Viale Fulvio Testi. City: no steps except at the doorstep.
- Planning finishes in < 5 s on the simulator (phone budget 1.5 s, measured on the iPhone 11 separately).

**Expected Cargo / kids blocks** (data, not bugs): trip 3 and 7 *Never along tram rails* (tram corridors around Darsena); trip 4 *No cobbles* (cobbled destination); trip 5 any rule (cobbled, pedestrian centre); trip 8 *No steps or narrow gaps* (cycle barrier on the way into Monza, OSM n2704536133); trip 10 *Max grade 6%* (Città Alta).

## Results on pack 2026.10 (M3 build, 60 cases)

Best card line, or the blocking rule. `single` = one *Best and fastest* card.

| # | City | E-bike | Road | Gravel | MTB | Cargo / kids |
|---|---|---|---|---|---|---|
| 1 | +1 min · avoids 280 m cobbles | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | +1 min · avoids 280 m cobbles |
| 2 | +3 min · avoids rails along Via Santa Margherita and 530 m cobbles | +2 min · avoids rails along Via Santa Margherita and 530 m cobbles | +2 min · avoids rails along Via Santa Margherita and 560 m cobbles | +3 min · 2.9 km of park path | one card: Fastest takes the same way. So there’s one route. | +5 min · avoids rails along Via Santa Margherita and 560 m cobbles |
| 3 | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | ⛔ Never along tram rails |
| 4 | +1 min · avoids 210 m cobbles | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | +18 min · avoids 270 m cobbles |
| 5 | one card: Fastest is only 30 s quicker, with rails along Corso Magenta. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | +5 min · avoids rails along Corso Magenta and 630 m cobbles | one card: Fastest is only 20 s quicker, with rails along Corso Magenta. So there’s one route. | one card: Fastest is only 40 s quicker, with rails along Corso di Porta Romana. So there’s one route. | +17 min · avoids rails along Corso Magenta and 630 m cobbles |
| 6 | +4 min · avoids rails along Via Vincenzo Monti and 300 m cobbles | one card: Fastest takes the same way. So there’s one route. | +10 min · avoids rails along Via Vincenzo Monti and 590 m cobbles | +5 min · 5.6 km of park path | +5 min · 4.4 km of park path | +23 min · avoids rails along Via Vincenzo Monti and 590 m cobbles |
| 7 | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest is only 30 s quicker, with rails along Ripa di Porta Ticinese. So there’s one route. | one card: Fastest is only 2 min quicker, with rails along Ripa di Porta Ticinese. So there’s one route. | ⛔ Never along tram rails |
| 8 | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | ⛔ No steps or narrow gaps |
| 9 | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | +2 min · calmer streets | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | +4 min · calmer streets |
| 10 | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | one card: Fastest takes the same way. So there’s one route. | ⛔ Max grade 6% |
