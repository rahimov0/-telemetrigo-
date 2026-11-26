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

/// Flyover'da gösterilebilen bilgiler
enum FlyStat: String, CaseIterable, Identifiable {
    case speed, gain, dist, time, alt
    var id: String { rawValue }
    func title(pace: Bool) -> String {
        switch self { case .speed: return pace ? "Tempo" : "Hız"; case .gain: return "Yükseliş"; case .dist: return "Mesafe"; case .time: return "Süre"; case .alt: return "Yükseklik" }
    }
}
enum FlyPalette {
    static let all: [(key: String, name: String, color: Color)] = [
        ("white", "Beyaz", .white), ("orange", "Turuncu", Color(red: 1.0, green: 0.353, blue: 0.122)),
        ("yellow", "Sarı", Color(red: 1.0, green: 0.82, blue: 0.2)), ("blue", "Mavi", Color(red: 0.35, green: 0.7, blue: 1.0)),
        ("green", "Yeşil", Color(red: 0.4, green: 0.9, blue: 0.55)), ("pink", "Pembe", Color(red: 1.0, green: 0.45, blue: 0.7))
    ]
    static func color(_ k: String) -> Color { all.first { $0.key == k }?.color ?? .white }
}
enum FlyExport: Identifiable {
    case fast, quality, screen
    var id: Int { switch self { case .fast: return 0; case .quality: return 1; case .screen: return 2 } }
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
    @State private var showStyle = false
    @State private var warming = false
    @State private var savedSeconds = 30.0
    @State private var pendingExport: FlyExport?
    @AppStorage("fly3D") private var fly3D = false
    @AppStorage("flyStats") private var statsRaw = "speed,gain,dist"
    @AppStorage("flyTextColor") private var textKey = "white"
    @AppStorage("flyRouteColor") private var routeKey = "orange"
    @AppStorage("flyFont") private var fontKey = "round"
    @AppStorage("flySign") private var showSign = true
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
            seconds = first.totalDistance / 1000 <= 5 ? 30 : 60
            try? await Task.sleep(nanoseconds: 900_000_000)
            start(from: 0)
        }
        .statusBarHidden()
        .onChange(of: done) { _, d in
            if d && warming { warming = false; seconds = savedSeconds; base = 0; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { startRecord() } }
            else if d && recording { DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { stopRecord() } }
        }
        .alert("Flyover", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Tamam") {}
        } message: { Text(message ?? "") }
        .alert("Kaydetmeden önce", isPresented: Binding(get: { pendingExport != nil }, set: { if !$0 { pendingExport = nil } })) {
            Button("Başla") { let m = pendingExport; pendingExport = nil; if let m { startExport(m) } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(pendingExport == .screen
                 ? "Sistem bir izin penceresi gösterecek, \"Kaydı Başlat\"a bas. Kayıt bitene kadar ekranı kapatma ve uygulamadan çıkma; yoksa kayıt iptal olur."
                 : "Video hazırlanırken uygulamayı açık tut. Başka uygulamaya geçersen veya ekran kapanırsa kayıt duraklar, geri dönünce kaldığı yerden devam eder. Hızlı yaklaşık 1–2, kaliteli 3–5 dakika sürer." + powerNote)
        }
        .sheet(isPresented: $showStyle) { styleSheet }
        .onAppear { FlyoverAd.shared.prepare() }
    }

    /// Gerçek zamanlı kayıtta harita karoları yetişmezse gri/bulanık kareler olur: önce rota kısa sürede (8 sn) sessizce gezilir, karolar önbelleğe alınır, sonra kayıt başlar
    private func warmThenRecord() {
        guard track != nil, !warming else { return }
        savedSeconds = seconds; seconds = 8; warming = true
        start(from: 0)
    }

    /// Şarj düşükse veya Düşük Güç Modu açıksa uyarı
    private var powerNote: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let low = UIDevice.current.batteryLevel >= 0 && UIDevice.current.batteryLevel < 0.25 && UIDevice.current.batteryState != .charging
        if low { return " Şarjın düşük, şarja takman önerilir." }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return " Düşük Güç Modu açık, kayıt yavaşlayabilir." }
        return ""
    }

    private func startExport(_ m: FlyExport) {
        switch m {
        case .screen: warmThenRecord()
        case .fast: exportDirect(fps: 15, wait: 130_000_000)
        case .quality: exportDirect(fps: 20, wait: 190_000_000)
        }
    }

    // MARK: Kaydet: uygulama içi ekran kaydı, bitince Fotoğraflar'a
    private func startRecord() {
        let r = RPScreenRecorder.shared()
        guard r.isAvailable else { message = "Ekran kaydı bu cihazda şu an kullanılamıyor."; return }
        playing = false; base = 0; done = false
        recording = true          // alt çubuk videonun başında görünmesin: izin penceresinden önce gizlenir
        r.isMicrophoneEnabled = false
        r.startRecording { err in
            DispatchQueue.main.async {
                if let err { recording = false; message = "Kayıt başlatılamadı: \(err.localizedDescription)"; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { start(from: 0) }   // ilk kare yüklensin
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
                DispatchQueue.main.async {
                    let text = ok ? "Flyover videosu Fotoğraflar'a kaydedildi." : "Kaydedilemedi: \(e?.localizedDescription ?? "bilinmeyen hata")"
                    // reklam yalnızca kayıt başarılıysa gösterilir
                    if ok { FlyoverAd.shared.show { message = text } } else { message = text }
                }
            }
        }
    }

    // MARK: Kaydet (otomatik): ekran kaydı izni istemeden kareleri tek tek videoya yazar
    private func exportDirect(fps: Int, wait: UInt64) {
        guard track != nil, !exporting, !recording, let ov = ExportOverlay() else { return }
        playing = false; done = false; exporting = true; cancelExport = false
        UIApplication.shared.isIdleTimerDisabled = true
        ov.onCancel = { cancelExport = true }
        let total = max(2, Int(seconds * Double(fps)))
        Task { @MainActor in
            defer { ov.close(); exporting = false; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let url = try await FlyoverExporter.render(frames: total, fps: fps, wait: wait,
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
        let wide = min(max(extent * 3.4, 1800), 120_000)
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
            dist = mix(dist, wide, outro); pitch = mix(pitch, 0, outro); head = mixAngle(head, 0, outro)
        }
        return MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), distance: dist, heading: head, pitch: pitch)
    }

    private func scene(_ tr: FlyoverTrack, p: Double) -> some View {
        let pos = tr.state(at: p)
        let route = tr.path(upTo: p).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let all = tr.samples.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let v = tr.speed(at: p)
        let cam = camera(tr, p: p)
        let rc = FlyPalette.color(routeKey)
        return ZStack {
            Map(position: .constant(.camera(cam)), interactionModes: []) {
                MapPolyline(coordinates: all).stroke(.white.opacity(0.28), lineWidth: 3)
                MapPolyline(coordinates: route).stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route).stroke(rc, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                // Nokta haritanın kendi çiziminde: her karede yeni bir görünüm oluşmaz, video kaydında çift görünmez
                MapCircle(center: CLLocationCoordinate2D(latitude: pos.lat, longitude: pos.lon), radius: max(cam.distance * 0.011, 2))
                    .foregroundStyle(rc)
                    .stroke(.white, lineWidth: 4)
            }
            .mapStyle(.hybrid(elevation: fly3D ? .realistic : .flat, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 230).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 14) {
                if showSign { KrovaSignature(height: 30) }
                Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(FlyPalette.color(textKey))
                HStack(alignment: .top) {
                    ForEach(stats) { st in statView(st, pos: pos, v: v) }
                }.padding(.horizontal, 16)
                Spacer()
                if warming { Text("Harita hazırlanıyor…").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white).padding(.bottom, 24) }
                else if !recording && !exporting { controls(p) }
            }
            .padding(.top, 56).padding(.bottom, 28)
            .shadow(color: .black.opacity(0.75), radius: 4, y: 1)
        }
    }

    private var stats: [FlyStat] { statsRaw.split(separator: ",").compactMap { FlyStat(rawValue: String($0)) } }
    private var fontDesign: Font.Design {
        switch fontKey { case "std": return .default; case "mono": return .monospaced; case "serif": return .serif; default: return .rounded }
    }

    private func statView(_ st: FlyStat, pos: FlyoverTrack.Sample, v: Double) -> some View {
        let pace = a.type.pace
        let (val, unit): (String, String) = {
            switch st {
            case .speed: return (pace ? Fmt.pace(v) : Fmt.num(v * 3.6, 1), pace ? "/km" : "km/sa")
            case .gain: return (Fmt.num(pos.gain), "m")
            case .dist: return (Fmt.num(pos.dist / 1000, pos.dist < 10_000 ? 2 : 1), "km")
            case .time: return (Fmt.dur(pos.time), "")
            case .alt: return (Fmt.num(pos.ele), "m")
            }
        }()
        return stat(st.title(pace: pace), val, unit, big: stats.count <= 3)
    }

    private func stat(_ label: String, _ value: String, _ unit: String, big: Bool) -> some View {
        let c = FlyPalette.color(textKey)
        return VStack(spacing: 2) {
            Text(label).font(.subheadline.weight(.bold)).foregroundStyle(c)
            Text(value).font(.system(size: big ? 38 : 30, weight: .bold, design: fontDesign)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(c)
            Text(unit.isEmpty ? " " : unit).font(.subheadline.weight(.bold)).foregroundStyle(c)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Görünüm ayarları
    private func swatches(_ sel: Binding<String>) -> some View {
        HStack(spacing: 12) {
            ForEach(FlyPalette.all, id: \.key) { c in
                Button { sel.wrappedValue = c.key } label: {
                    Circle().fill(c.color).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                        .overlay { if sel.wrappedValue == c.key { Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(c.key == "white" || c.key == "yellow" ? .black : .white) } }
                }.buttonStyle(.plain)
            }
        }
    }
    private var styleSheet: some View {
        NavigationStack {
            Form {
                Section("Gösterilecek bilgiler (en fazla 4)") {
                    ForEach(FlyStat.allCases) { st in
                        Toggle(st.title(pace: a.type.pace), isOn: Binding(
                            get: { stats.contains(st) },
                            set: { on in
                                var cur = stats
                                if on { if cur.count < 4 { cur.append(st) } } else if cur.count > 1 { cur.removeAll { $0 == st } }
                                statsRaw = FlyStat.allCases.filter { cur.contains($0) }.map(\.rawValue).joined(separator: ",")
                            }))
                    }
                }
                Section("Yazı") {
                    swatches($textKey)
                    Picker("Yazı tipi", selection: $fontKey) {
                        Text("Yuvarlak").tag("round"); Text("Standart").tag("std"); Text("Mono").tag("mono"); Text("Serif").tag("serif")
                    }.pickerStyle(.segmented)
                }
                Section("Rota rengi") { swatches($routeKey) }
                Section { Toggle("KROVA imzası", isOn: $showSign) }
                Section(footer: Text("Kapalıyken harita düz görünür: rota çizgisi ve nokta binaların arkasında kalıp kaybolmaz, video akıcı olur.")) { Toggle("3D bina ve arazi", isOn: $fly3D) }
            }
            .navigationTitle("Görünüm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showStyle = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Uzun rotada kısa süre seçilirse harita karoları yetişmez: en az ~1 sn / km
    private var durations: [Double] {
        let km = (track?.totalDistance ?? 0) / 1000
        return [30.0, 45.0, 60.0].filter { $0 >= min(45, km * 1.0) }
    }

    private func controls(_ p: Double) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: p).tint(orange).padding(.horizontal, 32)
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle()) }
                Button {
                    if playing { base = progress(at: Date()); playing = false }
                    else { start(from: done || base >= 1 ? 0 : base) }
                } label: {
                    Image(systemName: playing ? "pause.fill" : done ? "arrow.counterclockwise" : "play.fill")
                        .font(.title2.weight(.bold)).frame(width: 58, height: 58).background(orange, in: Circle())
                }
                Menu {
                    Button { pendingExport = .fast } label: { Label("Hızlı kaydet (15 kare/sn)", systemImage: "hare") }
                    Button { pendingExport = .quality } label: { Label("Kaliteli kaydet (20 kare/sn)", systemImage: "sparkles") }
                    Button { pendingExport = .screen } label: { Label("Ekran kaydı ile (gerçek zamanlı)", systemImage: "record.circle") }
                } label: { Image(systemName: "square.and.arrow.down").frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle()) }
                Button { if playing { base = progress(at: Date()); playing = false }; showStyle = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle()) }
                if (track?.totalDistance ?? 0) / 1000 <= 5 {
                    Menu {
                        ForEach([30.0, 60.0], id: \.self) { s in Button("\(Int(s)) sn") { let cur = progress(at: Date()); seconds = s; if playing { start(from: cur) } } }
                    } label: { Text("\(Int(seconds)) sn").font(.subheadline.weight(.bold)).frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle()) }
                }
            }.foregroundStyle(.white).buttonStyle(.plain).frame(maxWidth: .infinity)
        }
    }
}
