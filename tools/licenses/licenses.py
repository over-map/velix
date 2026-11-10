#!/usr/bin/env python3
"""Open-source licences shown in the app (You → About → Open-source licences) → App/Resources/Licenses.json.

MIT, BSD, ISC and OFL ask for their copyright notice and licence text to travel with every copy, the app binary
included. The texts live in tools/licenses/texts/ (copied from each package's checkout) and next to the fonts.
Usage: python3 tools/licenses/licenses.py [--check]   (--check: fail if the JSON is stale or THIRD_PARTY.md lists a
shipped Swift package, font or icon set that has no entry here; CI runs it)."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEXTS = ROOT / "tools/licenses/texts"
OUT = ROOT / "App/Resources/Licenses.json"

# What ships inside the app. Build-time and test-only packages (swift-syntax, snapshot testing…) are not here.
SHIPPED = [
    ("Ferrostar", "BSD-3-Clause", TEXTS / "ferrostar.txt"),
    ("MapLibre Native", "BSD-2-Clause", TEXTS / "maplibre-native.txt"),
    ("MapLibre SwiftUI DSL", "BSD-3-Clause", TEXTS / "maplibre-swiftui-dsl.txt"),
    ("Valhalla", "MIT", TEXTS / "valhalla.txt"),
    ("valhalla-mobile", "MIT", TEXTS / "valhalla-mobile.txt"),
    ("valhalla-openapi-models-swift", "MIT", TEXTS / "valhalla-openapi-models-swift.txt"),
    ("Light-Swift-Untar", "BSD-2-Clause", TEXTS / "light-swift-untar.txt"),
    ("AnyCodable", "MIT", TEXTS / "anycodable.txt"),
    ("Atkinson Hyperlegible", "OFL-1.1", ROOT / "App/Resources/Fonts/OFL-AtkinsonHyperlegible.txt"),
    ("Familjen Grotesk", "OFL-1.1", ROOT / "App/Resources/Fonts/OFL-FamiljenGrotesk.txt"),
    ("Lucide icons", "ISC", TEXTS / "lucide.txt"),
]

# THIRD_PARTY.md rows that must have an entry above: the shipped Swift packages, fonts and icons (first cell's link text).
NOT_SHIPPED = {"swift-syntax", "swift-snapshot-testing", "swift-custom-dump", "xctest-dynamic-overlay"}


def build():
    items = [{"name": n, "license": lic, "text": p.read_text().strip()} for n, lic, p in SHIPPED]
    return json.dumps(items, ensure_ascii=False, indent=1) + "\n"


def listed_in_third_party():
    md = (ROOT / "THIRD_PARTY.md").read_text()
    names = set()
    for section in ("## Swift packages", "## Fonts", "## Icons and artwork"):
        body = md.split(section, 1)[1].split("\n## ", 1)[0]
        for line in body.splitlines():
            if line.startswith("| ") and not line.startswith(("| Package", "| Font", "| Asset", "|---")):
                cell = line.split("|")[1].strip()
                m = re.match(r"\[([^\]]+)\]", cell)
                names.add((m.group(1) if m else cell.split(",")[0]).strip())
    return names


def main():
    data = build()
    if "--check" not in sys.argv:
        OUT.write_text(data)
        print(f"[licenses] {len(SHIPPED)} entries → {OUT.relative_to(ROOT)}")
        return 0
    ok = True
    if not OUT.exists() or OUT.read_text() != data:
        print("Licenses.json out of date: run python3 tools/licenses/licenses.py")
        ok = False
    shipped = {n.lower() for n, _, _ in SHIPPED}
    for name in sorted(listed_in_third_party()):
        key = name.lower()
        if key in NOT_SHIPPED or key.startswith("velix"):
            continue
        if not any(key.startswith(s) or s.startswith(key) for s in shipped):
            print(f"THIRD_PARTY.md lists {name!r} but the app's licence list has no entry for it")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
