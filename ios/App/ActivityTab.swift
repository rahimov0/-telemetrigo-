import SwiftUI
import MapKit
import Charts
import WebKit
import CoreLocation

/// Aktivite sekmesi: yürüyüş, koşu, bisiklet, motor kaydı + geçmiş + özet
struct ActivityTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    @State private var path: [Activity] = []
    @State private var confirmEnd = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if act.state == .idle { home } else { live }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(act.state == .idle ? "Aktivite" : act.type.name)
            .navigationDestination(for: Activity.self) { ActivityDetail(act: act, a: $0) }
        }
        .onAppear { act.preview() }
        .onDisappear { act.stopPreview() }
    }

    // MARK: Başlangıç ekranı
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Tür", selection: $act.type) {
                    ForEach(ActType.allCases) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented)
                signal
                Button { act.start() } label: {
                    Label("Başlat", systemImage: act.type.icon).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                VStack(spacing: 0) {
                    Toggle("Otomatik duraklat", isOn: $act.autoPause).padding(.vertical, 10)
                    Divider().overlay(Theme.line)
                    Toggle("Her kilometrede sesli bildirim", isOn: $act.voice).padding(.vertical, 10)
                }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                totals
                if !act.activities.isEmpty {
                    Text("Geçmiş").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(act.activities) { a in
                            NavigationLink(value: a) { ActivityRow(a: a) }.buttonStyle(.plain)
                            if a.id != act.activities.last?.id { Divider().overlay(Theme.line) }
                        }
                    }.background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }
                Text("Kayıt ekran kilitliyken de sürer. Aktiviteler bu telefonda saklanır.").font(.footnote).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private var signal: some View {
        let acc = act.accuracy
        let (txt, col): (String, Color) = acc == nil ? ("Konum bekleniyor", .secondary) : acc! <= 10 ? ("GPS iyi · ±\(Int(acc!)) m", Theme.ok) : acc! <= 25 ? ("GPS orta · ±\(Int(acc!)) m", Theme.mid) : ("GPS zayıf · ±\(Int(acc!)) m", Theme.err)
        return HStack(spacing: 8) { Circle().fill(col).frame(width: 7, height: 7); Text(txt).font(.footnote.weight(.medium)).foregroundStyle(.secondary) }
    }

    private var totals: some View {
        let cal = Calendar(identifier: .iso8601)
        let wk = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let mo = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let w = act.activities.filter { $0.start >= wk }, m = act.activities.filter { $0.start >= mo }
        return StatGrid(items: [
            ("Bu hafta", Fmt.km(w.reduce(0) { $0 + $1.distance }) + " km"), ("Bu hafta süre", Fmt.dur(w.reduce(0) { $0 + $1.moving })),
            ("Bu ay", Fmt.km(m.reduce(0) { $0 + $1.distance }) + " km"), ("Bu ay aktivite", "\(m.count)"),
        ])
    }

    // MARK: Canlı ekran
    private var live: some View {
        let a = act.current
        let avg = (a?.distance ?? 0) / max(1, act.moving)
        return VStack(spacing: 0) {
            if act.autoPaused && act.autoPause && act.state == .running {
                Text("Otomatik duraklatıldı").font(.footnote.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.mid.opacity(0.18), in: Capsule()).foregroundStyle(Theme.mid).padding(.top, 8)
            } else if act.state == .paused {
                Text("Duraklatıldı").font(.footnote.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule()).padding(.top, 8)
            }
            Spacer(minLength: 8)
            Text(Fmt.dur(act.moving)).font(.system(size: 76, weight: .semibold, design: .rounded)).monospacedDigit()
            Text("Süre").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                big(Fmt.km(a?.distance ?? 0), "Mesafe (km)")
                Divider().frame(height: 60).overlay(Theme.line)
                if act.type.pace { big(Fmt.pace(act.speed ?? 0), "Anlık tempo") } else { big(act.speed.map { Fmt.num($0 * 3.6) } ?? "—", "Hız (km/h)") }
            }
            HStack(spacing: 0) {
                big(act.type.pace ? Fmt.pace(avg) : Fmt.num(avg * 3.6, 1), act.type.pace ? "Ort. tempo" : "Ort. hız")
                Divider().frame(height: 60).overlay(Theme.line)
                big(act.type.pace ? Fmt.pace(a?.maxSpeed ?? 0) : Fmt.num((a?.maxSpeed ?? 0) * 3.6), act.type.pace ? "En iyi tempo" : "Maks hız")
            }.padding(.top, 18)
            Spacer()
            if act.route.count > 1 {
                LiveMap(route: act.route).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line)).padding(.horizontal, 16)
            }
            HStack(spacing: 12) {
                if act.state == .running {
                    Button { act.pause() } label: { Label("Duraklat", systemImage: "pause.fill").frame(maxWidth: .infinity, minHeight: 56) }
                        .buttonStyle(.bordered).tint(.white)
                } else {
                    Button { act.resume() } label: { Label("Devam", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 56) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    Button { confirmEnd = true } label: { Label("Bitir", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 56) }
                        .buttonStyle(.borderedProminent).tint(Theme.err)
                }
            }.font(.headline).padding(16)
        }
        .confirmationDialog("Aktivite bitirilsin mi?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Bitir ve kaydet") { if let a = act.finish() { path = [a] } }
            Button("Kaydetmeden sil", role: .destructive) { act.discard() }
            Button("Vazgeç", role: .cancel) {}
        }
    }
    private func big(_ v: String, _ k: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(k).font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct ActivityRow: View {
    let a: Activity
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: a.type.icon).frame(width: 36, height: 36).background(Theme.card2, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(a.type.title(a.start)).font(.subheadline.weight(.semibold))
                Text(a.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Fmt.km(a.distance)) km").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(Fmt.dur(a.moving)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct StatGrid: View {
    let items: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(items[i].0).font(.caption).foregroundStyle(.secondary)
                    Text(items[i].1).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Theme.card)
            }
        }.background(Theme.line).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

struct LiveMap: View {
    let route: [CLLocationCoordinate2D]
    var body: some View {
        Map(interactionModes: []) {
            MapPolyline(coordinates: route).stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let l = route.last { Annotation("", coordinate: l) { Circle().fill(.white).frame(width: 12, height: 12).overlay(Circle().stroke(.black, lineWidth: 2)) } }
        }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll)).environment(\.colorScheme, .dark)
    }
}

// MARK: Özet ekranı
struct Split: Identifiable { let id: Int; let len: Double; let time: Double; let ele: Double? }

struct ActivityDetail: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    let a: Activity
    @State private var coords: [CLLocationCoordinate2D] = []
    @State private var splits: [Split] = []
    @State private var elev: [(Double, Double)] = []
    @State private var photo = false
    @State private var confirmDel = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.type.name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(a.type.title(a.start)).font(.title2.weight(.bold))
                    Text(a.start.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                }
                if coords.count > 1 {
                    Map(interactionModes: [.pan, .zoom]) {
                        MapPolyline(coordinates: coords).stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coords).stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        Annotation("Başlangıç", coordinate: coords[0]) { Circle().fill(Theme.ok).frame(width: 12, height: 12).overlay(Circle().stroke(.black, lineWidth: 2)) }
                        Annotation("Bitiş", coordinate: coords[coords.count - 1]) { Circle().fill(Theme.err).frame(width: 12, height: 12).overlay(Circle().stroke(.black, lineWidth: 2)) }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 10) {
                    Button { photo = true } label: { Label("Fotoğrafa ekle", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 46) }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    Button { model.pendingGpx = (a.gpxName, act.gpxText(a)); model.tab = 1 } label: { Label("Videoya ekle", systemImage: "film").frame(maxWidth: .infinity, minHeight: 46) }
                        .buttonStyle(.bordered).tint(.white)
                }.font(.subheadline.weight(.semibold))
                let avg = a.distance / max(1, a.moving)
                StatGrid(items: [
                    ("Mesafe", Fmt.km(a.distance) + " km"), ("Hareket süresi", Fmt.dur(a.moving)),
                    a.type.pace ? ("Ort. tempo", Fmt.pace(avg) + " /km") : ("Ort. hız", Fmt.num(avg * 3.6, 1) + " km/h"),
                    a.type.pace ? ("En iyi tempo", Fmt.pace(a.maxSpeed) + " /km") : ("Maks hız", Fmt.num(a.maxSpeed * 3.6) + " km/h"),
                    ("Yükseliş", Fmt.num(a.gain) + " m"), ("Geçen süre", Fmt.dur((a.end ?? a.start).timeIntervalSince(a.start))),
                ])
                if elev.count > 2 {
                    card("Yükseklik") {
                        Chart(elev.indices, id: \.self) { i in
                            AreaMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(.white.opacity(0.12))
                            LineMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(.white)
                        }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 140)
                    }
                }
                if !splits.isEmpty {
                    card("Kilometre bölümleri") {
                        let worst = splits.map { $0.time / $0.len }.max() ?? 1
                        VStack(spacing: 0) {
                            ForEach(splits) { s in
                                HStack {
                                    Text(s.len < 999 ? Fmt.num(s.len / 1000, 2) : "\(s.id)").frame(width: 40, alignment: .leading)
                                    Text(a.type.pace ? Fmt.pace(s.len / max(1, s.time)) : Fmt.num(s.len / max(1, s.time) * 3.6, 1) + " km/h").frame(width: 84, alignment: .leading)
                                    Text(s.ele.map { ($0 >= 0 ? "+" : "") + Fmt.num($0) + " m" } ?? "—").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                                    GeometryReader { g in Capsule().fill(.white.opacity(0.85)).frame(width: max(8, g.size.width * (worst / max(0.0001, s.time / s.len)) * 0.9), height: 6).frame(maxHeight: .infinity) }
                                }.font(.subheadline).monospacedDigit().frame(height: 34)
                                Divider().overlay(Theme.line)
                            }
                        }
                    }
                }
                HStack {
                    ShareLink(item: act.gpxURL(a)) { Label("GPX paylaş", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered).tint(.white)
                    Spacer()
                    Button(role: .destructive) { confirmDel = true } label: { Label("Sil", systemImage: "trash") }
                }.font(.subheadline)
            }.padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { compute() }
        .sheet(isPresented: $photo) { PhotoEditorSheet(gpx: act.gpxText(a), name: a.type.title(a.start), type: a.type.rawValue).environmentObject(model) }
        .confirmationDialog("Aktivite silinsin mi? Bu işlem geri alınamaz.", isPresented: $confirmDel, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { act.delete(a); dismiss() }
        }
    }

    private func card<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(t).font(.subheadline.weight(.semibold)); c() }
            .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func compute() {
        let pts = act.readPoints(a.id).filter { $0.ha <= 30 }
        guard pts.count > 1 else { return }
        coords = pts.map { CLLocationCoordinate2D(latitude: $0.la, longitude: $0.lo) }
        var dist = 0.0, mv = 0.0, k = 1, lastT = 0.0, lastE: Double? = pts.first?.al
        var sp: [Split] = [], el: [(Double, Double)] = []
        for i in 1..<pts.count {
            let p = pts[i - 1], q = pts[i], dt = q.t - p.t
            let d = CLLocation(latitude: p.la, longitude: p.lo).distance(from: CLLocation(latitude: q.la, longitude: q.lo))
            let v = q.sp ?? d / max(dt, 0.1)
            if dt < 30, v >= a.type.stopSpeed { dist += d; mv += dt }
            if let e = q.al, i % 5 == 0 { el.append((dist / 1000, e)) }
            if dist >= Double(k) * 1000 {
                sp.append(Split(id: k, len: 1000, time: mv - lastT, ele: q.al.flatMap { e in lastE.map { e - $0 } }))
                lastT = mv; lastE = q.al; k += 1
            }
        }
        let rest = dist - Double(k - 1) * 1000
        if rest > 50 { sp.append(Split(id: k, len: rest, time: mv - lastT, ele: pts.last?.al.flatMap { e in lastE.map { e - $0 } })) }
        splits = sp; elev = el
    }
}

// MARK: Fotoğraf editörü (web: aktivite sayfası)
struct PhotoEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let gpx: String, name: String, type: String
    var body: some View {
        NavigationStack {
            ActivityWeb(gpx: gpx, name: name, type: type) { g, n in
                model.pendingGpx = (n, g); model.tab = 1; dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Fotoğrafa ekle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

struct ActivityWeb: UIViewRepresentable {
    let gpx: String, name: String, type: String
    let toVideo: (String, String) -> Void
    static let url = URL(string: "https://telemetrigo.rahimov.tr/aktivite.html?app=1")!

    func makeCoordinator() -> C { C(self) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.applicationNameForUserAgent = "TelemetriGoApp/1.0"
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(context.coordinator, name: "tg")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false; wv.backgroundColor = UIColor(Theme.bg); wv.scrollView.backgroundColor = UIColor(Theme.bg)
        context.coordinator.web = wv
        wv.load(URLRequest(url: Self.url, cachePolicy: .reloadRevalidatingCacheData))
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
    static func dismantleUIView(_ wv: WKWebView, coordinator: C) { wv.configuration.userContentController.removeScriptMessageHandler(forName: "tg") }

    final class C: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        let p: ActivityWeb; weak var web: WKWebView?; private var sent = false; private var dest: URL?
        init(_ p: ActivityWeb) { self.p = p }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
            guard !sent else { return }; sent = true
            guard let d = try? JSONSerialization.data(withJSONObject: [p.gpx, p.name, p.type]), let j = String(data: d, encoding: .utf8) else { return }
            w.evaluateJavaScript("(function(a){ window.TelemetriGo && window.TelemetriGo.receiveActivity(a[0], a[1], a[2], 'photo'); })(\(j));")
        }
        func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let b = m.body as? [String: Any], b["action"] as? String == "video", let g = b["gpx"] as? String else { return }
            p.toVideo(g, b["name"] as? String ?? "aktivite.gpx")
        }
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            decisionHandler(a.shouldPerformDownload ? .download : .allow, preferences)
        }
        func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome d: WKDownload) { d.delegate = self }
        func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome d: WKDownload) { d.delegate = self }
        func download(_ d: WKDownload, decideDestinationUsing r: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename.isEmpty ? "TelemetriGo.jpg" : suggestedFilename)
            try? FileManager.default.removeItem(at: u); dest = u; completionHandler(u)
        }
        func downloadDidFinish(_ d: WKDownload) {
            guard let u = dest, let web else { return }
            let vc = UIActivityViewController(activityItems: [u], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = web
            web.window?.rootViewController?.topMost.present(vc, animated: true)
        }
    }
}
