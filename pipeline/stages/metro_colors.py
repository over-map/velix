"""Metro colour families (design/velix-tokens.json mapRules, P3 render.js VX.METRO_FAM): the line's OSM colour=*
is snapped in OKLCH to one of 12 Velix families; a second line of the same family in a city takes the alt tone.
Lines without a colour take the fallback order red, green, yellow, blue, orange, purple."""
import math

FAMILIES = ["red", "orange", "yellow", "olive", "green", "cyan", "lightblue", "blue", "purple", "pink", "brown", "grey"]
FALLBACK = ["red", "green", "yellow", "blue", "orange", "purple"]


def _lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklch(hex_color: str) -> tuple[float, float, float]:
    """sRGB hex → (L 0–1, C, H degrees)."""
    h = hex_color.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(ch * 2 for ch in h)
    r, g, b = (_lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))
    l_ = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m_ = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s_ = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (math.copysign(abs(v) ** (1 / 3), v) for v in (l_, m_, s_))
    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
    bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def family(hex_color: str) -> str:
    """Port of VX.metroFamily (design/p3v3/palettes.js); tests pin it to the JS outputs."""
    L, C, H = oklch(hex_color)
    if C < 0.04:
        return "grey"
    if 30 <= H < 95 and L < 0.6 and C < 0.16:
        return "brown"
    if H < 15 or H >= 330:
        if L >= 0.68:
            return "pink"
        if 330 <= H < 350:
            return "purple"
        if H >= 350 and L < 0.5:
            return "purple"
        return "red"
    if H < 30:
        return "red"
    if H < 70:
        return "orange"
    if H < 100:
        return "yellow" if L > 0.66 else "olive"
    if H < 130:
        return "yellow" if L > 0.82 else "olive"
    if H < 165:
        return "green"
    if H < 215:
        return "cyan"
    if H < 275:
        return "lightblue" if L > 0.64 else "blue"
    return "purple"


def assign(lines: list[tuple[str, str | None]]) -> dict[str, tuple[str, bool]]:
    """[(ref, colour or None)] for one city, in ref order → {ref: (family, alt)}."""
    out: dict[str, tuple[str, bool]] = {}
    used: dict[str, int] = {}
    fallback = iter(FALLBACK)
    for ref, colour in sorted(lines, key=lambda x: _ref_key(x[0])):
        fam = family(colour) if colour else next((f for f in fallback if f not in used), "grey")
        out[ref] = (fam, used.get(fam, 0) > 0)
        used[fam] = used.get(fam, 0) + 1
    return out


def _ref_key(ref: str):
    digits = "".join(ch for ch in ref if ch.isdigit())
    return (int(digits) if digits else 999, ref)
