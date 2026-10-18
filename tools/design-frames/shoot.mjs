// Saves design frames (elements with data-screen-label) as PNGs, through headless Chrome's DevTools protocol.
// Usage: node tools/design-frames/shoot.mjs "<page.html under design/>" <out-dir> [label-prefix ...]
// Needs the repo served on 127.0.0.1:8766 (python3 -m http.server 8766 --bind 127.0.0.1) and Google Chrome.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const [page, outDir, ...prefixes] = process.argv.slice(2);
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9333;
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`, '--hide-scrollbars', '--window-size=1600,1200',
  `--user-data-dir=/tmp/velix-chrome-${process.pid}`, 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page'); } catch {}
}
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evalJS = async (expr) => (await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })).result.result.value;

await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 1200, deviceScaleFactor: 2, mobile: false });
await send('Page.navigate', { url: `http://127.0.0.1:8766/design/${encodeURIComponent(page)}` });
await sleep(6000);
const labels = await evalJS(`[...document.querySelectorAll('[data-screen-label]')].map(e=>e.dataset.screenLabel)`);
fs.mkdirSync(outDir, { recursive: true });
let n = 0;
for (const label of labels) {
  if (prefixes.length && !prefixes.some((p) => label.startsWith(p))) continue;
  const rect = await evalJS(`(async()=>{ const e=[...document.querySelectorAll('[data-screen-label]')].find(x=>x.dataset.screenLabel===${JSON.stringify(label)});
    e.scrollIntoView({block:'start'}); await new Promise(r=>setTimeout(r,400)); const b=e.getBoundingClientRect();
    return {x:b.left+scrollX,y:b.top+scrollY,w:b.width,h:b.height}; })()`);
  const shot = await send('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true,
    clip: { x: rect.x, y: rect.y, width: rect.w, height: rect.h, scale: 1 } });
  const file = path.join(outDir, label.split(' ')[0] + '.png');
  fs.writeFileSync(file, Buffer.from(shot.result.data, 'base64'));
  n++;
}
console.log(`${n} frames → ${outDir}`);
ws.close(); chrome.kill();
