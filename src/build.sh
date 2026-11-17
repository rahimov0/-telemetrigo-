#!/bin/bash
# Paketle ve dosya adlarına içerik özeti ekle (önbellek karışmasın): app.<hash>.js, kayit.<hash>.js, aktivite.<hash>.js, ui.<hash>.css
set -e
cd /home/claude/tg
rm -rf dist && mkdir dist
for f in app kayit aktivite; do
  npx esbuild app/$f.js --bundle --format=esm --minify --target=es2020,safari16 --outfile=dist/$f.js >/dev/null 2>&1
done
cp app/ui.css dist/ui.css
declare -A N
for f in app.js kayit.js aktivite.js ui.css; do
  b=${f%.*}; e=${f##*.}; h=$(sha1sum dist/$f | cut -c1-8); mv dist/$f dist/$b.$h.$e; N[$f]=$b.$h.$e
done
for p in index kayit aktivite; do
  sed -e "s#src=\"app.js\"#src=\"${N[app.js]}\"#" -e "s#src=\"kayit.js\"#src=\"${N[kayit.js]}\"#" -e "s#src=\"aktivite.js\"#src=\"${N[aktivite.js]}\"#" \
      -e "s#href=\"ui.css\"#href=\"${N[ui.css]}\"#" app/$p.html > dist/$p.html
done
cp app/manifest.webmanifest app/icon-*.png app/nosleep.mp4 dist/
grep -oh '\(src\|href\)="[a-z]*\.[0-9a-f]\{8\}\.\(js\|css\)"' dist/*.html | sort | uniq -c
