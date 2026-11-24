import SwiftUI
import MapKit
import KrovaCore
import ReplayKit
import Photos

/// K rota logosu (uygulama ikonuyla aynı çizim): dikey gövde + ortadan çıkan iki rota kolu
struct KrovaMark: View {
    var bar: Color = .white
    var arm: Color = Color(red: 1.0, green: 0.353, blue: 0.122)   // #FF5A1F
    var dot: Color = .white
    var height: CGFloat = 40
    var body: some View {
        let s = height / 80.2
        Canvas { ctx, _ in
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x - 36) * s, y: (y - 26.9) * s) }
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: (28 - 26.9) * s, width: 12 * s, height: 74 * s), cornerRadius: 6 * s), with: .color(bar))
            var a = Path(); a.move(to: p(50, 66)); a.addLine(to: p(88, 33)); a.move(to: p(50, 66)); a.addLine(to: p(90, 101))
            ctx.stroke(a, with: .color(arm), style: StrokeStyle(lineWidth: 12 * s, lineCap: .round, lineJoin: .round))
            for c in [p(88, 33), p(90, 101)] {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6.1 * s, y: c.y - 6.1 * s, width: 12.2 * s, height: 12.2 * s)), with: .color(dot))
            }
        }
        .frame(width: 60.1 * s, height: height)
    }
}

/// K + ROVA imzası
struct KrovaSignature: View {
    var height: CGFloat = 34
    var mono: Color? = nil
    var body: some View {
        HStack(spacing: height * 0.14) {
            KrovaMark(bar: mono ?? .white, arm: mono ?? Color(red: 1.0, green: 0.353, blue: 0.122), dot: mono ?? .white, height: height)
            Text("ROVA").font(.system(size: height * 0.72, weight: .medium)).tracking(height * 0.1).foregroundStyle(mono ?? .white)
        }
    }
}

/// Flyover: rotanın başından sonuna kuş bakışı, 3D uydu haritada akan video
struct FlyoverView: View {
    @Environment(\.dismiss) private var dismiss
    let a: Activity
    let points: [TrackPoint]
    @State private var track: FlyoverTrack?
    @State private var playing = false
    @State private var t0 = Date()
    @State private var base = 0.0
    @State private var seconds = 30.0
    @State private var done = false
    @State private var follow = 800.0
    @State private var recording = false
    @State private var exporting = false
    @State private var cancelExport = false
    @State private var message: String?

    private let orange = Color(red: 1.0, green: 0.353, blue: 0.122)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let tr = track {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
                    let p = progress(at: ctx.date)
                    scene(tr, p: p)
                        .onChange(of: p >= 1) { _, end in if end && playing { playing = false; base = 1; done = true } }
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .task {
            let pts = points.filter { $0.ha <= 30 }.map { FlyoverTrack.Input(lat: $0.la, lon: $0.lo, t: $0.t, ele: $0.al) }
            guard let first = FlyoverTrack(points: pts) else { return }
            // Yakınlık: tür başına taban; uzun rotada kamera biraz daha yukarıdan bakar ki harita yetişsin
            let base: Double = a.type.kind.group == .drive ? 2200 : a.type.kind == .bike ? 1300 : 700
            let f = min(6000, max(base, first.totalDistance / 18))
            follow = f
            // Yön, kameranın önündeki yola göre ve hızlı virajları geriden izlemeyecek kadar kısa pencereyle
            track = FlyoverTrack(points: pts, lookMeters: f * 0.3, smoothMeters: f * 0.12)
            seconds = min(60, max(20, (first.totalDistance / 1000 * 2).rounded()))
            try? await Task.sleep(nanoseconds: 900_000_000)
            start(from: 0)
        }
        .statusBarHidden()
        .onChange(of: done) { _, d in
            if d && recording { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { stopRecord() } }
        }
        .alert("Flyover", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Tamam") {}
        } message: { Text(message ?? "") }
    }

    // MARK: Kaydet: uygulama içi ekran kaydı, bitince Fotoğraflar'a
    private func startRecord() {
        let r = RPScreenRecorder.shared()
        guard r.isAvailable else { message = "Ekran kaydı bu cihazda şu an kullanılamıyor."; return }
        playing = false; base = 0
        r.isMicrophoneEnabled = false
        r.startRecording { err in
            DispatchQueue.main.async {
                if let err { message = "Kayıt başlatılamadı: \(err.localizedDescription)"; return }
                recording = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { start(from: 0) }
            }
        }
    }
    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { st in
            guard st == .authorized || st == .limited else {
                DispatchQueue.main.async { message = "Fotoğraflar'a kaydetme izni verilmedi. iPhone Ayarlar > KROVA > Fotoğraflar'dan izin ver." }
                return
            }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }) { ok, e in
                DispatchQueue.main.async { message = ok ? "Flyover videosu Fotoğraflar'a kaydedildi." : "Kaydedilemedi: \(e?.localizedDescription ?? "bilinmeyen hata")" }
            }
        }
    }

    // MARK: Kaydet (otomatik): ekran kaydı izni istemeden kareleri tek tek videoya yazar
    private func exportDirect() {
        guard track != nil, !exporting, !recording, let ov = ExportOverlay() else { return }
        playing = false; done = false; exporting = true; cancelExport = false
        UIApplication.shared.isIdleTimerDisabled = true
        ov.onCancel = { cancelExport = true }
        let fps = 24, total = max(2, Int(seconds * Double(fps)))
        Task { @MainActor in
            defer { ov.close(); exporting = false; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let url = try await FlyoverExporter.render(frames: total, fps: fps,
                    step: { i in base = Double(i) / Double(total - 1) },
                    progress: { n in ov.update(n * 100 / total) },
                    cancelled: { cancelExport })
                base = 1; done = true
                saveToPhotos(url)
            } catch is CancellationError {
                base = 0
            } catch {
                base = 0; message = "Video hazırlanamadı: \(error.localizedDescription)"
            }
        }
    }

    private func stopRecord() {
        guard recording else { return }
        recording = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KROVA-Flyover-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: url)
        RPScreenRecorder.shared().stopRecording(withOutput: url) { err in
            DispatchQueue.main.async {
                if let err { message = "Kayıt kaydedilemedi: \(err.localizedDescription)"; return }
                saveToPhotos(url)
            }
        }
    }

    private func progress(at d: Date) -> Double {
        guard playing else { return base }
        return min(1, base + d.timeIntervalSince(t0) / seconds)
    }
    private func start(from p: Double) { base = p; t0 = Date(); done = false; playing = true }

    private func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
    private func mix(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    private func mixAngle(_ a: Double, _ b: Double, _ u: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360); if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return (a + d * u + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Kamera: başta tüm rotayı gösterir, sonra yaklaşıp noktayı izler, sonda tekrar uzaklaşır
    private func camera(_ tr: FlyoverTrack, p: Double) -> MapCamera {
        let lats = tr.samples.map { $0.lat }, lons = tr.samples.map { $0.lon }
        let mid = (lat: (lats.min()! + lats.max()!) / 2, lon: (lons.min()! + lons.max()!) / 2)
        let extent = max(FlyoverTrack.meters((lats.min()!, lons.min()!), (lats.max()!, lons.max()!)), 300)
        let wide = min(max(extent * 2.4, 1500), 90_000)
        let intro = ease(p / 0.12), outro = ease((p - 0.9) / 0.1)
        let pos = tr.state(at: p)
        var head = mixAngle(0, pos.heading, intro), dist = mix(wide, follow, intro), pitch = mix(0, 60, intro)
        // Merkez, noktanın kamera yönünde biraz ilerisinde: nokta her zaman ekranın alt ortasında kalır
        func shifted(_ lat: Double, _ lon: Double, _ h: Double, _ m: Double) -> (Double, Double) {
            (lat + cos(h * .pi / 180) * m / 111_195, lon + sin(h * .pi / 180) * m / (111_195 * max(cos(lat * .pi / 180), 0.2)))
        }
        let fc = shifted(pos.lat, pos.lon, head, follow * 0.16)
        var lat = mix(mid.lat, fc.0, intro), lon = mix(mid.lon, fc.1, intro)
        if outro > 0 {
            lat = mix(lat, mid.lat, outro); lon = mix(lon, mid.lon, outro)
            dist = mix(dist, wide, outro); pitch = mix(pitch, 35, outro); head = mixAngle(head, 0, outro)
        }
        return MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), distance: dist, heading: head, pitch: pitch)
    }

    private func scene(_ tr: FlyoverTrack, p: Double) -> some View {
        let pos = tr.state(at: p)
        let route = tr.path(upTo: p).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let all = tr.samples.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let v = tr.speed(at: p)
        let cam = camera(tr, p: p)
        return ZStack {
            Map(position: .constant(.camera(cam)), interactionModes: []) {
                MapPolyline(coordinates: all).stroke(.white.opacity(0.28), lineWidth: 3)
                MapPolyline(coordinates: route).stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route).stroke(orange, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                // Nokta haritanın kendi çiziminde: her karede yeni bir görünüm oluşmaz, video kaydında çift görünmez
                MapCircle(center: CLLocationCoordinate2D(latitude: pos.lat, longitude: pos.lon), radius: max(cam.distance * 0.011, 2))
                    .foregroundStyle(orange)
                    .stroke(.white, lineWidth: 4)
            }
            .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            VStack(spacing: 14) {
                KrovaSignature(height: 30)
                Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.92))
                HStack(alignment: .top) {
                    stat(a.type.pace ? "Tempo" : "Hız", a.type.pace ? Fmt.pace(v) : Fmt.num(v * 3.6, 1), a.type.pace ? "/km" : "km/s")
                    stat("Yükseliş", Fmt.num(pos.gain), "m")
                    stat("Mesafe", Fmt.num(pos.dist / 1000, pos.dist < 10_000 ? 2 : 1), "km")
                }.padding(.horizontal, 24)
                Spacer()
                if !recording && !exporting { controls(p) }
            }
            .padding(.top, 56).padding(.bottom, 28)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            Text(unit).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
        }.frame(maxWidth: .infinity)
    }

    private func controls(_ p: Double) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: p).tint(orange).padding(.horizontal, 32)
            HStack(spacing: 18) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }
                Button {
                    if playing { base = progress(at: Date()); playing = false }
                    else { start(from: done || base >= 1 ? 0 : base) }
                } label: {
                    Image(systemName: playing ? "pause.fill" : done ? "arrow.counterclockwise" : "play.fill")
                        .font(.title2.weight(.bold)).frame(width: 64, height: 64).background(orange, in: Circle())
                }
                Menu {
                    Button { exportDirect() } label: { Label("Videoyu kaydet (otomatik)", systemImage: "square.and.arrow.down") }
                    Button { startRecord() } label: { Label("Ekran kaydı ile kaydet", systemImage: "record.circle") }
                } label: { Image(systemName: "square.and.arrow.down").frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }
                Menu {
                    ForEach([15.0, 30.0, 60.0], id: \.self) { s in Button("\(Int(s)) sn") { let cur = progress(at: Date()); seconds = s; if playing { start(from: cur) } } }
                } label: { Text("\(Int(seconds)) sn").font(.subheadline.weight(.bold)).frame(width: 48, height: 48).background(.black.opacity(0.45), in: Circle()) }
            }.foregroundStyle(.white)
        }
    }
}
