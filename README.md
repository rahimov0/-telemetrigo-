# TelemetriGo

GoPro videolarına yatış açısı, eğim, G-kuvveti ve dönüş hızı göstergesi ekleyen web uygulaması. iPhone'da (Safari) ve bilgisayarda (Chrome, Edge, Safari) çalışır.

- Video hiçbir sunucuya yüklenmez, tüm işlem cihazda yapılır (WebCodecs).
- Veriler GoPro'nun kendi dosyasındaki sensör izinden (GPMF: ACCL, GYRO, GRAV) okunur. GPS gerekmez.
- Orijinal video değişmez; göstergeli yeni bir MP4 oluşturulur, ses aynen korunur.

## Yayınlama

Klasördeki dosyaları olduğu gibi herhangi bir statik sunucuya (GitHub Pages vb.) koymak yeterli. HTTPS gerekir.

## Dosyalar

- `index.html`: arayüz
- `app.js`: uygulama (GPMF okuyucu + gösterge çizimi + mediabunny ile dönüştürme, tek dosyada)
- `manifest.webmanifest`, `icon-*.png`: "Ana Ekrana Ekle" için

## Bilinen sınırlar

- iPhone'da videoyu Fotoğraf Arşivi'nden değil, Dosyalar / Gözat'tan seç (aksi halde iOS sıkıştırıp sensör verisini silebilir).
- Çok uzun 4K videolar telefonda yavaş işlenir; paylaşım için 1080p önerilir.
- Açılar kameranın açısıdır: motorun yatışı için GoPro motora sabit monte edilmeli.

## Kaynak kod

`src/` klasöründe düzenlenebilir kaynak var (`gpmf.js`: sensör okuyucu, `overlay.js`: göstergeler, `app.js`: arayüz ve dönüştürme). Kökteki `app.js`, bunların [mediabunny](https://mediabunny.dev) ile birlikte paketlenmiş halidir:

```
npm i mediabunny esbuild
npx esbuild src/app.js --bundle --format=esm --minify --target=es2020,safari16 --outfile=app.js
```
