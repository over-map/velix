// SDF glyph PBFs for the map labels (P3: Atkinson Hyperlegible Regular + Bold only, self-hosted).
// Run with tools/glyphs/build.sh; output App/Resources/MapStyle/glyphs/<fontstack>/<start>-<end>.pbf.
const fs = require('fs');
const path = require('path');
const fontnik = require('fontnik');

const root = path.resolve(__dirname, '../..');
const fonts = {
  'Atkinson Hyperlegible Regular': 'App/Resources/Fonts/AtkinsonHyperlegible-Regular.ttf',
  'Atkinson Hyperlegible Bold': 'App/Resources/Fonts/AtkinsonHyperlegible-Bold.ttf',
};
// Latin, Latin-1, Latin Extended-A/B, IPA/spacing, general punctuation (·, –, ’, …), currency, letterlike, arrows.
const ranges = [0, 256, 512, 768, 8192, 8448, 8704];

async function main() {
  for (const [stack, file] of Object.entries(fonts)) {
    const font = fs.readFileSync(path.join(root, file));
    const dir = path.join(root, 'App/Resources/MapStyle/glyphs', stack);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    for (const start of ranges) {
      const end = start + 255;
      const pbf = await new Promise((ok, fail) => fontnik.range({ font, start, end }, (e, d) => (e ? fail(e) : ok(d))));
      fs.writeFileSync(path.join(dir, `${start}-${end}.pbf`), pbf);
    }
    console.log(stack, ranges.length, 'ranges');
  }
}
main().catch((e) => { console.error(e); process.exit(1); });
