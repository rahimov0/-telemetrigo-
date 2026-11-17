#!/bin/bash
# Paketle ve dosya adlarına içerik özeti ekle (önbellek karışmasın): app.<hash>.js, kayit.<hash>.js
set -e
cd /home/claude/tg
rm -rf dist && mkdir dist
npx esbuild app/app.js --bundle --format=esm --minify --target=es2020,safari16 --outfile=dist/app.js >/dev/null 2>&1
cp app/kayit.js dist/kayit.js
for f in app kayit; do h=$(sha1sum dist/$f.js | cut -c1-8); mv dist/$f.js dist/$f.$h.js; echo "$f.$h.js"; done
A=$(ls dist/app.*.js | xargs -n1 basename); K=$(ls dist/kayit.*.js | xargs -n1 basename)
sed "s#src=\"app.js\"#src=\"$A\"#" app/index.html > dist/index.html
sed "s#src=\"kayit.js\"#src=\"$K\"#" app/kayit.html > dist/kayit.html
cp app/manifest.webmanifest app/icon-*.png app/nosleep.mp4 dist/
grep -o 'src="[a-z]*\.[0-9a-f]*\.js"' dist/index.html dist/kayit.html
