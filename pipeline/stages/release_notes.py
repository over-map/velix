"""Release notes for a pack Release: sizes, source dates and licences (ODbL attribution required)."""
import json
import sys

m = json.load(open(sys.argv[1]))
print(f"Velix offline region pack **{m['name']} {m['version']}** (built from OSM data of {m['built']}, Valhalla {m['valhalla']}).\n")
print(f"Download {m['download_bytes'] / 1e6:.1f} MB · unpacked on the phone {m['unpacked_bytes'] / 1e6:.0f} MB.\n")
print("| File | Download | Unpacked | sha256 |\n|---|---|---|---|")
for f in m["files"]:
    print(f"| `{f['asset']}` | {f['bytes'] / 1e6:.1f} MB | {f['unpacked_bytes'] / 1e6:.1f} MB | `{f['sha256'][:16]}…` |")
print("\n## Sources and licences\n")
for s in m["sources"]:
    until = f", service until {s['service_until']}" if s.get("service_until") else ""
    print(f"- **{s['name']}** ({s['date']}{until}): {s['licence']}. {s['attribution']}. <{s['url']}>")
print("\nThe pack is a database derived from OpenStreetMap and is made available under the ODbL 1.0.")
