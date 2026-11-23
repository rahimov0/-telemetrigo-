import puppeteer from 'puppeteer-core';
const browser = await puppeteer.launch({ executablePath: '/usr/bin/google-chrome', headless: 'new', args: ['--no-sandbox'] });
const page = await browser.newPage(); await page.setViewport({ width: 414, height: 1200 });
page.on('pageerror', e => console.log('[pageerror]', e.message));
await page.goto('http://localhost:8765/dist/index.html'); await page.evaluate(() => localStorage.clear()); await page.reload();
for (const [vid, gpx] of [['DJI_20261114_0001.MP4', 'sentetik.gpx'], ['h264_gpmd.mp4', 'sentetik_cam.gpx'], ['h264_gpmd.mp4', 'sentetik.gpx']]) {
  await page.reload();
  await (await page.$('#file')).uploadFile('/home/claude/tg/test/' + vid);
  await page.waitForFunction(() => !document.getElementById('work').classList.contains('hidden'), { timeout: 20000 });
  await (await page.$('#gpxFile')).uploadFile('/home/claude/tg/test/' + gpx); await new Promise(r => setTimeout(r, 1500));
  const t = id => page.$eval(id, e => e.innerText).catch(e => 'YOK');
  console.log('---', vid, gpx);
  console.log('info:', (await t('#gpsInfo')).replace(/\n/g, ' | '));
  console.log('cov:', await t('#gpsCov'), '| sync:', await t('#syncMsg'), '| off:', await t('#offV'), '| gAt:', await t('#gAtV'), await t('#gAtInfo'));
}
await browser.close();
