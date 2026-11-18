import SwiftUI
import MapKit
import Charts
import WebKit
import CoreLocation

// MARK: Ortak parçalar

/// Rotayı kutuya sığdırıp çizen şekil (harita gerektirmez)
struct RouteShape: Shape {
    let pts: [CLLocationCoordinate2D]
    func path(in r: CGRect) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        let lats = pts.map { $0.latitude }, lons = pts.map { $0.longitude }
        let minLa = lats.min()!, maxLa = lats.max()!, minLo = lons.min()!, maxLo = lons.max()!
        let kx = cos((minLa + maxLa) / 2 * .pi / 180)
        let w = max((maxLo - minLo) * kx, 1e-9), h = max(maxLa - minLa, 1e-9)
        let sc = min(r.width / w, r.height / h)
        let ox = r.midX - w * sc / 2, oy = r.midY - h * sc / 2
        func pt(_ c: CLLocationCoordinate2D) -> CGPoint { CGPoint(x: ox + (c.longitude - minLo) * kx * sc, y: oy + (maxLa - c.latitude) * sc) }
        p.move(to: pt(pts[0]))
        for c in pts.dropFirst() { p.addLine(to: pt(c)) }
        return p
    }
}

struct RouteThumb: View {
    let act: ActivityRecorder
    let a: Activity
    @State private var pts: [CLLocationCoordinate2D] = []
    var body: some View {
        ZStack {
            Theme.card2
            RouteShape(pts: pts).stroke(Theme.acc, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)).padding(22)
        }
        .task(id: a.id) {
            var raw = a.preview ?? []
            if raw.count < 2 { raw = ActivityRecorder.thumb(act.readPoints(a.id)) }
            pts = raw.filter { $0.count == 2 }.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        }
    }
}

struct StatCell: View {
    let label: String, value: String
    var unit: String = ""
    var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: big ? 34 : 24, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(Theme.text)
                if !unit.isEmpty { Text(unit).font(.footnote.weight(.medium)).foregroundStyle(Theme.text2) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Panel<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }
}

struct AccButton: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Theme.onAcc).frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.acc.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct GhostButton: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.card2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

// MARK: Aktivite akışı (ana ekran)

struct ActivityTab: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    @ObservedObject var health: HealthManager
    @State private var path: [Activity] = []
    @State private var showRecord = false
    @State private var showSettings = false
    @AppStorage("showSteps") private var showSteps = true

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    weekCard
                    if HealthManager.available && showSteps { stepsCard }
                    if act.activities.isEmpty {
                        Panel {
                            VStack(spacing: 8) {
                                Image(systemName: "figure.run").font(.system(size: 30)).foregroundStyle(Theme.acc)
                                Text("İlk aktiviteni kaydet").font(.headline).foregroundStyle(Theme.text)
                                Text("Yürüyüş, koşu, bisiklet ya da motor sürüşünü başlat; rota ve değerler burada birikir.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Theme.text2)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    } else {
                        Text("Aktiviteler").font(.title3.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 4)
                        ForEach(act.activities) { a in
                            NavigationLink(value: a) { ActivityCard(act: act, a: a) }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Aktivite")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.text) }.accessibilityLabel("Aktivite ayarları")
                }
            }
            .navigationDestination(for: Activity.self) { ActivityDetail(act: act, health: health, a: $0) }
            .safeAreaInset(edge: .bottom) {
                Button { showRecord = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: act.state == .idle ? "record.circle" : "waveform.path.ecg")
                        Text(act.state == .idle ? "Kayda başla" : "Kayda dön · \(Fmt.dur(act.moving))").monospacedDigit()
                    }.font(.headline).foregroundStyle(Theme.onAcc).padding(.horizontal, 26).frame(height: 54)
                        .background(Theme.acc, in: Capsule())
                }.padding(.bottom, 10)
            }
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordScreen(act: act, health: health) { a in
                showRecord = false
                if let a { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { path = [a] } }
            }
        }
        .sheet(isPresented: $showSettings) { ActivitySettings(act: act, health: health) }
        .onAppear { health.refresh(); if act.state != .idle { showRecord = true } }
    }

    // Haftalık özet + günlük çubuklar
    private var weekCard: some View {
        let cal = Calendar(identifier: .iso8601)
        let wk = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let w = act.activities.filter { $0.start >= wk }
        let days = (0..<7).map { i -> (String, Double) in
            let d0 = cal.date(byAdding: .day, value: i, to: wk) ?? wk, d1 = cal.date(byAdding: .day, value: 1, to: d0) ?? d0
            return (["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"][i], w.filter { $0.start >= d0 && $0.start < d1 }.reduce(0) { $0 + $1.distance } / 1000)
        }
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bu hafta").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2)
                HStack(alignment: .top) {
                    StatCell(label: "Mesafe", value: Fmt.km(w.reduce(0) { $0 + $1.distance }), unit: "km", big: true)
                    StatCell(label: "Süre", value: Fmt.dur(w.reduce(0) { $0 + $1.moving }), big: true)
                    StatCell(label: "Aktivite", value: "\(w.count)", big: true)
                }
                Chart(days.indices, id: \.self) { i in
                    BarMark(x: .value("Gün", days[i].0), y: .value("km", max(days[i].1, 0.05)), width: .ratio(0.55))
                        .foregroundStyle(days[i].1 > 0 ? Theme.acc : Color.white.opacity(0.12)).cornerRadius(4)
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.text2) } }
                .frame(height: 70)
            }
        }
    }

    // Apple Sağlık adımları
    private var stepsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Adımlar", systemImage: "figure.walk").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2)
                    Spacer()
                    Text("Apple Sağlık").font(.caption).foregroundStyle(Theme.text3)
                }
                if health.connected {
                    HStack(alignment: .top) {
                        StatCell(label: "Bugün", value: health.stepsToday.formatted(), unit: "adım", big: true)
                        StatCell(label: "Yürünen", value: Fmt.km(health.distToday), unit: "km", big: true)
                    }
                    Chart(health.week, id: \.day) { d in
                        BarMark(x: .value("Gün", d.day, unit: .day), y: .value("Adım", d.steps), width: .ratio(0.55))
                            .foregroundStyle(Calendar.current.isDateInToday(d.day) ? Theme.acc : Color.white.opacity(0.25)).cornerRadius(4)
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(Theme.text2) } }
                    .frame(height: 70)
                } else {
                    Text("Günlük adımların ve yürüyüşlerin burada görünsün. Bitirdiğin aktiviteler de Sağlık uygulamasına antrenman olarak yazılır.").font(.subheadline).foregroundStyle(Theme.text2)
                    Button { health.connect() } label: { Label("Apple Sağlık'a bağlan", systemImage: "heart.fill") }.buttonStyle(GhostButton(height: 46))
                    if let e = health.lastError { Text(e).font(.caption).foregroundStyle(Theme.err) }
                }
            }
        }
    }
}

struct ActivityCard: View {
    let act: ActivityRecorder
    let a: Activity
    var body: some View {
        let avg = a.distance / max(1, a.moving)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: a.type.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 34, height: 34).background(Theme.card2, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(a.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.text3)
            }.padding(14)
            HStack(alignment: .top, spacing: 8) {
                StatCell(label: "Mesafe", value: Fmt.km(a.distance), unit: "km")
                StatCell(label: a.type.pace ? "Tempo" : "Hız", value: a.type.pace ? Fmt.pace(avg) : Fmt.num(avg * 3.6, 1), unit: a.type.pace ? "/km" : "km/h")
                StatCell(label: "Süre", value: Fmt.dur(a.moving))
            }.padding(.horizontal, 14).padding(.bottom, 12)
            RouteThumb(act: act, a: a).frame(height: 150)
        }
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: Tam ekran kayıt

struct RecordScreen: View {
    @ObservedObject var act: ActivityRecorder
    @ObservedObject var health: HealthManager
    let done: (Activity?) -> Void
    @State private var cam: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var confirmEnd = false
    @AppStorage("keepAwake") private var keepAwake = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cam) {
                UserAnnotation()
                if act.route.count > 1 {
                    MapPolyline(coordinates: act.route).stroke(Theme.acc, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if act.state == .idle {
                    HStack {
                        Button { done(nil) } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                                .frame(width: 40, height: 40).background(Theme.bg.opacity(0.85), in: Circle())
                        }
                        Spacer()
                        signal
                    }.padding(.horizontal, 16).padding(.top, 8)
                } else if act.autoPaused && act.autoPause && act.state == .running {
                    badge("Otomatik duraklatıldı", Theme.mid)
                } else if act.state == .paused {
                    badge("Duraklatıldı", Theme.text2)
                }
                Spacer()
                panel
            }
        }
        .background(Theme.bg)
        .onAppear { act.preview() }
        .onDisappear { act.stopPreview(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: act.state) { _, st in UIApplication.shared.isIdleTimerDisabled = keepAwake && st != .idle }
        .confirmationDialog("Aktivite bitirilsin mi?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Bitir ve kaydet") {
                if let a = act.finish() { health.save(a, points: act.readPoints(a.id)); done(a) } else { done(nil) }
            }
            Button("Kaydetmeden sil", role: .destructive) { act.discard(); done(nil) }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.footnote.weight(.semibold)).foregroundStyle(c).padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.bg.opacity(0.9), in: Capsule()).padding(.top, 10)
    }

    private var signal: some View {
        let acc = act.accuracy
        let (txt, col): (String, Color) = acc == nil ? ("Konum bekleniyor", Theme.text2) : acc! <= 10 ? ("GPS iyi", Theme.ok) : acc! <= 25 ? ("GPS orta", Theme.mid) : ("GPS zayıf", Theme.err)
        return HStack(spacing: 6) { Circle().fill(col).frame(width: 8, height: 8); Text(txt).font(.footnote.weight(.semibold)).foregroundStyle(Theme.text) }
            .padding(.horizontal, 12).frame(height: 34).background(Theme.bg.opacity(0.85), in: Capsule())
    }

    @ViewBuilder private var panel: some View {
        VStack(spacing: 16) {
            if act.state == .idle { idlePanel } else { livePanel }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.bg.opacity(0.96).clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)).ignoresSafeArea(edges: .bottom))
    }

    private var idlePanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(ActType.sport) { t in
                    Button { act.type = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.icon).font(.system(size: 20, weight: .semibold))
                            Text(t.name).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(act.type == t ? Theme.onAcc : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(act.type == t ? Theme.acc : Theme.card2, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            Button { act.start() } label: {
                Text("BAŞLA").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onAcc)
                    .frame(width: 104, height: 104).background(Theme.acc, in: Circle())
                    .overlay(Circle().stroke(Theme.acc.opacity(0.35), lineWidth: 8))
            }.buttonStyle(.plain).padding(.vertical, 4)
            VStack(spacing: 0) {
                Toggle("Otomatik duraklat", isOn: $act.autoPause).padding(.vertical, 8)
                Divider().overlay(Theme.line)
                Toggle("Her kilometrede sesli bildirim", isOn: $act.voice).padding(.vertical, 8)
            }
            .tint(Theme.acc).foregroundStyle(Theme.text).font(.subheadline)
            .padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var livePanel: some View {
        let a = act.current
        let avg = (a?.distance ?? 0) / max(1, act.moving)
        let pace = act.type.pace
        return VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Fmt.dur(act.moving)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
                Text("Süre").font(.footnote).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .top, spacing: 0) {
                big(Fmt.km(a?.distance ?? 0), "Mesafe (km)")
                big(pace ? Fmt.pace(act.speed ?? 0) : (act.speed.map { Fmt.num($0 * 3.6, 1) } ?? "—"), pace ? "Anlık tempo" : "Hız (km/h)")
                big(pace ? Fmt.pace(avg) : Fmt.num(avg * 3.6, 1), pace ? "Ort. tempo" : "Ort. hız")
            }
            HStack(spacing: 28) {
                if act.state == .running {
                    Button { act.pause() } label: { circle("pause.fill", fg: Theme.onAcc, bg: Theme.acc, size: 84) }
                } else {
                    Button { confirmEnd = true } label: { circle("stop.fill", fg: Theme.text, bg: Theme.card2, size: 72, ring: true) }
                    Button { act.resume() } label: { circle("play.fill", fg: Theme.onAcc, bg: Theme.acc, size: 84) }
                }
            }.padding(.top, 4)
            if act.state == .running {
                Button { confirmEnd = true } label: { Text("Bitir").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2).frame(height: 36) }
            }
        }
    }

    private func big(_ v: String, _ k: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(Theme.text)
            Text(k).font(.caption).foregroundStyle(Theme.text2)
        }.frame(maxWidth: .infinity)
    }
    private func circle(_ icon: String, fg: Color, bg: Color, size: CGFloat, ring: Bool = false) -> some View {
        Image(systemName: icon).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(fg)
            .frame(width: size, height: size).background(bg, in: Circle()).overlay(Circle().stroke(Theme.line, lineWidth: ring ? 1 : 0))
    }
}

// MARK: Özet ekranı
struct Split: Identifiable { let id: Int; let len: Double; let time: Double; let ele: Double? }

struct ActivityDetail: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var act: ActivityRecorder
    @ObservedObject var health: HealthManager
    let a: Activity
    @State private var coords: [CLLocationCoordinate2D] = []
    @State private var splits: [Split] = []
    @State private var elev: [(Double, Double)] = []
    @State private var steps: Int?
    @State private var cam: MapCameraPosition = .automatic
    @State private var photo = false
    @State private var confirmDel = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if coords.count > 1 {
                    Map(position: $cam, interactionModes: [.pan, .zoom]) {
                        MapPolyline(coordinates: coords).stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coords).stroke(Theme.acc, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        Annotation("", coordinate: coords[0]) { Circle().fill(Theme.ok).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2)) }
                        Annotation("", coordinate: coords[coords.count - 1]) { Circle().fill(Theme.err).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2)) }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .frame(height: 320)
                } else {
                    Theme.card2.frame(height: 200).overlay(ProgressView())
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: a.type.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44).background(Theme.card2, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.type.title(a.start)).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                            Text(a.start.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(Theme.text2)
                        }
                    }
                    let avg = a.distance / max(1, a.moving)
                    Panel {
                        VStack(spacing: 18) {
                            HStack(alignment: .top, spacing: 8) {
                                StatCell(label: "Mesafe", value: Fmt.km(a.distance), unit: "km", big: true)
                                StatCell(label: "Süre", value: Fmt.dur(a.moving), big: true)
                                StatCell(label: a.type.pace ? "Tempo" : "Ort. hız", value: a.type.pace ? Fmt.pace(avg) : Fmt.num(avg * 3.6, 1), unit: a.type.pace ? "/km" : "km/h", big: true)
                            }
                            Divider().overlay(Theme.line)
                            HStack(alignment: .top, spacing: 8) {
                                StatCell(label: "Yükseliş", value: Fmt.num(a.gain), unit: "m")
                                StatCell(label: a.type.pace ? "En iyi tempo" : "Maks hız", value: a.type.pace ? Fmt.pace(a.maxSpeed) : Fmt.num(a.maxSpeed * 3.6), unit: a.type.pace ? "/km" : "km/h")
                                if let s = steps, s > 0 { StatCell(label: "Adım", value: s.formatted()) }
                                else { StatCell(label: "Geçen süre", value: Fmt.dur((a.end ?? a.start).timeIntervalSince(a.start))) }
                            }
                        }
                    }
                    VStack(spacing: 10) {
                        Button { photo = true } label: { Label("Fotoğrafa ekle", systemImage: "photo") }.buttonStyle(AccButton(height: 50))
                        Button { model.pendingGpx = (a.gpxName, act.gpxText(a)); model.tab = 1 } label: { Label("Videoya ekle", systemImage: "film") }.buttonStyle(GhostButton(height: 50))
                    }
                    if elev.count > 2 {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Yükseklik").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Chart(elev.indices, id: \.self) { i in
                                    AreaMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(Theme.acc.opacity(0.18))
                                    LineMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(Theme.acc)
                                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 140)
                            }
                        }
                    }
                    if !splits.isEmpty {
                        Panel {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Kilometre bölümleri").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).padding(.bottom, 6)
                                let rates = splits.map { $0.time / max($0.len, 1) }
                                let best = rates.min() ?? 1, worst = rates.max() ?? 1
                                HStack {
                                    Text("Km").frame(width: 40, alignment: .leading)
                                    Text(a.type.pace ? "Tempo" : "Hız").frame(width: 84, alignment: .leading)
                                    Text("Yükseklik").frame(width: 70, alignment: .leading)
                                    Spacer()
                                }.font(.caption).foregroundStyle(Theme.text3)
                                ForEach(splits) { s in
                                    let r = s.time / max(s.len, 1)
                                    HStack {
                                        Text(s.len < 999 ? Fmt.num(s.len / 1000, 2) : "\(s.id)").frame(width: 40, alignment: .leading)
                                        Text(a.type.pace ? Fmt.pace(s.len / max(1, s.time)) : Fmt.num(s.len / max(1, s.time) * 3.6, 1)).frame(width: 84, alignment: .leading)
                                        Text(s.ele.map { ($0 >= 0 ? "+" : "") + Fmt.num($0) + " m" } ?? "—").foregroundStyle(Theme.text2).frame(width: 70, alignment: .leading)
                                        GeometryReader { g in
                                            let frac = worst > best ? 1 - 0.55 * (r - best) / (worst - best) : 1
                                            Capsule().fill(Theme.acc.opacity(r == best ? 1 : 0.5)).frame(width: max(8, g.size.width * frac), height: 7).frame(maxHeight: .infinity, alignment: .center)
                                        }
                                    }.font(.subheadline).monospacedDigit().foregroundStyle(Theme.text).frame(height: 34)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 16)
            }.padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: act.gpxURL(a)) { Label("GPX paylaş", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmDel = true } label: { Label("Sil", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { compute() }
        .sheet(isPresented: $photo) { PhotoEditorSheet(gpx: act.gpxText(a), name: a.type.title(a.start), type: a.type.rawValue, steps: steps).environmentObject(model) }
        .confirmationDialog("Aktivite silinsin mi? Bu işlem geri alınamaz.", isPresented: $confirmDel, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { act.delete(a); dismiss() }
        }
    }

    private func compute() {
        let pts = act.readPoints(a.id).filter { $0.ha <= 30 }
        guard pts.count > 1 else { return }
        coords = pts.map { CLLocationCoordinate2D(latitude: $0.la, longitude: $0.lo) }
        let lats = coords.map { $0.latitude }, lons = coords.map { $0.longitude }
        let c = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.004), longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.004))
        cam = .region(MKCoordinateRegion(center: c, span: span))
        if a.type.pace { health.steps(from: a.start, to: a.end ?? Date()) { steps = $0 } }
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
    var steps: Int? = nil
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Fotoğrafa ekle").font(.headline).foregroundStyle(Theme.text)
                HStack {
                    Button { dismiss() } label: { Text("Kapat").font(.body.weight(.medium)).foregroundStyle(Theme.text).padding(.horizontal, 14).frame(height: 36).background(Theme.card2, in: Capsule()) }.buttonStyle(.plain)
                    Spacer()
                }
            }.padding(.horizontal, 16).frame(height: 56).background(Theme.bg)
            Divider().overlay(Theme.line)
            ActivityWeb(gpx: gpx, name: name, type: type, steps: steps) { g, n in
                model.pendingGpx = (n, g); model.tab = 1; dismiss()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}

struct ActivityWeb: UIViewRepresentable {
    let gpx: String, name: String, type: String
    var steps: Int? = nil
    let toVideo: (String, String) -> Void
    static let url = URL(string: "https://telemetrigo.rahimov.tr/aktivite.html?app=1")!

    func makeCoordinator() -> C { C(self) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.applicationNameForUserAgent = "TelemetriGoApp/1.0"
        cfg.websiteDataStore = .default()
        cfg.userContentController.add(context.coordinator, name: "tg")
        // Aktivite, sayfa açılmadan önce verilir: yükleme sırasına bağlı kalmaz (editör her seferinde açılır)
        var payload: [String: Any] = ["gpx": gpx, "name": name, "type": type, "view": "photo"]
        payload["steps"] = steps ?? NSNull()
        if let d = try? JSONSerialization.data(withJSONObject: payload), let j = String(data: d, encoding: .utf8) {
            cfg.userContentController.addUserScript(WKUserScript(source: "window.__TG_PENDING = \(j);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false; wv.backgroundColor = UIColor(Theme.bg); wv.scrollView.backgroundColor = UIColor(Theme.bg)
        context.coordinator.web = wv
        wv.load(URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData))
        return wv
    }
    func updateUIView(_ wv: WKWebView, context: Context) {}
    static func dismantleUIView(_ wv: WKWebView, coordinator: C) { wv.configuration.userContentController.removeScriptMessageHandler(forName: "tg") }

    final class C: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        let p: ActivityWeb; weak var web: WKWebView?; private var dest: URL?
        init(_ p: ActivityWeb) { self.p = p }
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


// MARK: Aktivite ayarları
struct ActivitySettings: View {
    @ObservedObject var act: ActivityRecorder
    @ObservedObject var health: HealthManager
    @AppStorage("showSteps") private var showSteps = true
    @AppStorage("keepAwake") private var keepAwake = false
    @Environment(\.dismiss) private var dismiss
    @State private var apW = ActivityRecorder.autoPauseSetting(.yuruyus)
    @State private var apR = ActivityRecorder.autoPauseSetting(.kosu)
    @State private var apB = ActivityRecorder.autoPauseSetting(.bisiklet)

    private func save(_ t: ActType, _ v: Bool) {
        if act.type == t { act.autoPause = v } else { UserDefaults.standard.set(v, forKey: "autoPause2_" + t.rawValue) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Yürüyüş", isOn: $apW).onChange(of: apW) { _, v in save(.yuruyus, v) }
                    Toggle("Koşu", isOn: $apR).onChange(of: apR) { _, v in save(.kosu, v) }
                    Toggle("Bisiklet", isOn: $apB).onChange(of: apB) { _, v in save(.bisiklet, v) }
                } header: { head("Otomatik duraklat") } footer: { foot("Yaklaşık 10 saniye yerinde durursan kayıt kendiliğinden bekler, yürümeye başlayınca devam eder. Yürüyüşte varsayılan kapalıdır.") }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Sesli bildirim", isOn: $act.voice)
                    if act.voice {
                        Picker("Sıklık", selection: $act.voiceEvery) {
                            Text("Her 1 km").tag(1); Text("Her 2 km").tag(2); Text("Her 5 km").tag(5)
                        }.pickerStyle(.menu)
                    }
                    Toggle("Ekran açık kalsın", isOn: $keepAwake)
                } header: { head("Kayıt sırasında") } footer: { foot("Ekran açık kalırsa pil daha hızlı biter. Kapalıyken de kayıt sürer.") }
                .listRowBackground(Theme.card)

                if HealthManager.available {
                    Section {
                        if health.connected {
                            Toggle("Adım kartını göster", isOn: $showSteps)
                            Toggle("Aktiviteyi Sağlık'a kaydet", isOn: $health.write)
                            Button("Bağlantıyı kes", role: .destructive) { health.disconnect() }
                        } else {
                            Button { health.connect() } label: { Label("Apple Sağlık'a bağlan", systemImage: "heart.fill").foregroundStyle(Theme.acc) }
                        }
                    } header: { head("Apple Sağlık") } footer: { foot("Adımlar yalnızca bu cihazda gösterilir. İstersen fotoğrafa ekleyeceğin değerler arasından \"Adım\"ı seçebilirsin. Erişimi iPhone Ayarlar > Sağlık > Veri Erişimi bölümünden de değiştirebilirsin.") }
                    .listRowBackground(Theme.card)
                }

                Section {
                    Button { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } label: { Label("Konum izni ayarları", systemImage: "location") }
                } header: { head("İzinler") } footer: { foot("Kayıt ekran kilitliyken de sürsün diye konum izni \"Her zaman\" olmalı.") }
                .listRowBackground(Theme.card)
            }
            .foregroundStyle(Theme.text)
            .tint(Theme.acc)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Aktivite ayarları").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.foregroundStyle(Theme.text) } }
        }
        .presentationDragIndicator(.visible)
    }
    private func head(_ t: String) -> some View { Text(t).foregroundStyle(Theme.text2) }
    private func foot(_ t: String) -> some View { Text(t).foregroundStyle(Theme.text3) }
}
