// Tile renders into one labeled contact sheet.
// node tools/contact_sheet.js <out.png> <cols> <tileWidth> <img1> [img2 ...]
// Labels come from file names. Requires: npm install (jimp) in tools/.
const Jimp = require("jimp");
const path = require("path");

(async () => {
  const [out, colsS, tileWS, ...files] = process.argv.slice(2);
  const cols = parseInt(colsS, 10);
  const tileW = parseInt(tileWS, 10);
  const imgs = [];
  for (const f of files) {
    try {
      const im = await Jimp.read(f);
      im.resize(tileW, Jimp.AUTO);
      imgs.push({ im, label: path.basename(f, ".png") });
    } catch (e) {
      console.error("skip", f, e.message);
    }
  }
  if (!imgs.length) { console.error("no images"); process.exit(1); }
  const tileH = Math.max(...imgs.map(x => x.im.bitmap.height));
  const labelH = 22;
  const rows = Math.ceil(imgs.length / cols);
  const sheet = new Jimp(cols * tileW, rows * (tileH + labelH), 0x1d2430ff);
  const font = await Jimp.loadFont(Jimp.FONT_SANS_16_WHITE);
  imgs.forEach((x, i) => {
    const cx = (i % cols) * tileW;
    const cy = Math.floor(i / cols) * (tileH + labelH);
    sheet.composite(x.im, cx, cy + labelH);
    sheet.print(font, cx + 6, cy + 3, x.label.slice(0, Math.floor(tileW / 9)));
  });
  await sheet.writeAsync(out);
  console.log("SHEET", out, imgs.length);
})();
