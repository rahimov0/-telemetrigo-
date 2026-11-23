import SwiftUI
import KrovaCore
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
            LinearGradient(colors: [a.type.color.opacity(0.28), a.type.color.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RouteShape(pts: pts)
                .stroke(LinearGradient(colors: [Theme.cPace, Theme.cTime, Theme.cKcal], startPoint: .bottomLeading, endPoint: .topTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: a.type.color.opacity(0.6), radius: 8)
                .padding(24)
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
    var tint: Color = Theme.text
    var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: big ? 34 : 24, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(tint)
                if !unit.isEmpty { Text(unit).font(.footnote.weight(.semibold)).foregroundStyle(tint.opacity(0.75)) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Panel<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AccButton: ButtonStyle {
    var height: CGFloat = 52
    var color: Color = Theme.acc
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Theme.onAcc).frame(maxWidth: .infinity, minHeight: height)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
struct GhostButton: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(Theme.text).frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.card2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TypeIcon: View {
    let t: ActType
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: t.icon).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(t.color)
            .frame(width: size, height: size).background(t.color.opacity(0.18), in: Circle())
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
    @AppStorage("goalKcal") private var goalKcal = 300.0
    @AppStorage("goalMin") private var goalMin = 30.0
    @AppStorage("goalSteps") private var goalSteps = 8000.0
    @State private var selDay = Calendar.current.startOfDay(for: Date())
    @State private var daySteps = 0
    @State private var weekBack = 0

    enum Period: String, CaseIterable { case day = "Gün", week = "Hafta", month = "Ay", year = "Yıl" }
    @State private var period: Period = .day
    @State private var monthBack = 0
    @State private var yearBack = 0
    @AppStorage("ozetGroup") private var groupRaw = "sport"
    private var group: ActivityGroup { groupRaw == "drive" ? .drive : .sport }
    /// Seçili gruba (Spor / Sürüş) ait aktiviteler; iki grup hiçbir yerde karışmaz
    private var acts: [Activity] { act.activities.filter { $0.type.kind.group == group } }
    private var dayList: [Activity] { acts.filter { Calendar.current.isDate($0.start, inSameDayAs: selDay) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    periodPicker
                    switch period {
                    case .day:
                        dayNav
                        if group == .sport { todayCard }
                        if group == .sport && (period == .day || period == .week) && HealthManager.available && showSteps { stepsCard }
                        dayActivities
                    case .week:
                        weekCard
                        if group == .sport { todayCard }
                        if group == .sport && (period == .day || period == .week) && HealthManager.available && showSteps { stepsCard }
                        dayActivities
                    case .month:
                        monthCard
                    case .year:
                        yearCard
                    }
                    if act.activities.isEmpty {
                        Panel {
                            VStack(spacing: 8) {
                                Image(systemName: "figure.run").font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.acc)
                                Text("İlk aktiviteni kaydet").font(.headline).foregroundStyle(Theme.text)
                                Text("Yürüyüş, koşu, bisiklet ya da motor sürüşünü başlat; rota ve değerler burada birikir.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Theme.text2)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 130)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.8 else { return }
                swipePeriod(back: dx > 0)
            })
            .background(Glow())
            .navigationBarTitleDisplayMode(.inline)
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
                    }.font(.headline).foregroundStyle(Theme.onAcc).padding(.horizontal, 28).frame(height: 56)
                        .background(Theme.acc, in: Capsule()).shadow(color: Theme.acc.opacity(0.45), radius: 16, y: 4)
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
        .onAppear { health.refresh(); health.loadWeek(containing: selDay, force: true); loadDaySteps(); if act.state != .idle { showRecord = true } }
        .onChange(of: selDay) { _, d in
            loadDaySteps()
            health.loadWeek(containing: d)
            var cal = Calendar(identifier: .iso8601); cal.locale = Locale(identifier: "tr_TR")
            let a = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d, b = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            weekBack = max(0, (cal.dateComponents([.weekOfYear], from: a, to: b).weekOfYear ?? 0))
        }
        .onChange(of: health.connected) { _, _ in loadDaySteps() }
    }

    private func loadDaySteps() {
        guard health.connected else { daySteps = 0; return }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: selDay) ?? selDay
        health.steps(from: selDay, to: end) { daySteps = $0 ?? 0 }
    }

    // Bugün: kalori, süre, adım hedefleri
    private var todayCard: some View {
        let list = dayList
        let own = list.reduce(0.0) { $0 + (Cal.active($1) ?? 0) }
        // Sağlık'ta o günün aktif enerjisi varsa (Apple Watch dahil) o geçerli; yoksa kendi hesabımız
        let hk = health.connected ? (health.weekEnergy[Calendar.current.startOfDay(for: selDay)] ?? 0) : 0
        let fromHealth = hk >= 1
        let kcal = fromHealth ? hk : own
        let mins = list.reduce(0.0) { $0 + $1.moving } / 60
        let steps = Double(daySteps)
        let isToday = Calendar.current.isDateInToday(selDay)
        return Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(isToday ? "Bugün" : "Özet").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(selDay.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline).foregroundStyle(Theme.text2)
                }
                HStack(alignment: .top, spacing: 0) {
                    goal(kcal, goalKcal, Theme.cKcal, "flame.fill", (Cal.ready || fromHealth) ? Fmt.num(kcal) : "—", "kcal")
                    goal(mins, goalMin, Theme.cElev, "timer", Fmt.num(mins), "dakika")
                    goal(steps, goalSteps, Theme.cSteps, "figure.walk", health.connected ? Int(steps).formatted() : "—", "adım")
                }
                if !Cal.ready && !fromHealth {
                    Button { showSettings = true } label: {
                        Label("Kalori için boy ve kilonu gir", systemImage: "person.crop.circle.badge.plus").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.acc)
                    }
                }
            }
        }
    }
    private func goal(_ v: Double, _ g: Double, _ c: Color, _ icon: String, _ text: String, _ unit: String) -> some View {
        VStack(spacing: 8) {
            GoalRing(value: v, goal: g, color: c, icon: icon)
            VStack(spacing: 0) {
                Text(text).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
                Text(unit).font(.caption).foregroundStyle(Theme.text2)
            }
        }.frame(maxWidth: .infinity)
    }

    // Haftalık özet: günlere dokununca aşağıdaki özet ve liste o güne geçer; oklarla önceki haftalar
    private var weekCard: some View {
        var cal = Calendar(identifier: .iso8601); cal.locale = Locale(identifier: "tr_TR")
        let thisWk = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let wk = cal.date(byAdding: .weekOfYear, value: -weekBack, to: thisWk) ?? thisWk
        let wkEnd = cal.date(byAdding: .day, value: 7, to: wk) ?? wk
        let w = acts.filter { $0.start >= wk && $0.start < wkEnd }
        let days = (0..<7).map { i -> (date: Date, km: Double) in
            let d0 = cal.date(byAdding: .day, value: i, to: wk) ?? wk, d1 = cal.date(byAdding: .day, value: 1, to: d0) ?? d0
            return (d0, w.filter { $0.start >= d0 && $0.start < d1 }.reduce(0) { $0 + $1.distance } / 1000)
        }
        let mx = max(days.map { $0.km }.max() ?? 0, 0.1)
        let title = weekBack == 0 ? "Bu hafta" : weekBack == 1 ? "Geçen hafta" : wk.formatted(.dateTime.day().month(.abbreviated)) + " haftası"
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Button { shiftWeek(1) } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36).background(Theme.card2, in: Circle()) }.buttonStyle(.plain)
                    Button { shiftWeek(-1) } label: { Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36).background(Theme.card2, in: Circle()) }.buttonStyle(.plain).opacity(weekBack == 0 ? 0.3 : 1).disabled(weekBack == 0)
                }.foregroundStyle(Theme.text)
                HStack(alignment: .top) {
                    StatCell(label: "Mesafe", value: Fmt.km(w.reduce(0) { $0 + $1.distance }), unit: "km", tint: Theme.cDist, big: true)
                    StatCell(label: "Süre", value: Fmt.dur(w.reduce(0) { $0 + $1.moving }), tint: Theme.cTime, big: true)
                    StatCell(label: "Aktivite", value: "\(w.count)", big: true)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(days.indices, id: \.self) { i in
                        let d = days[i].date
                        let sel = cal.isDate(d, inSameDayAs: selDay)
                        let future = d > Date()
                        Button { withAnimation(.easeOut(duration: 0.15)) { selDay = cal.startOfDay(for: d) } } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Theme.track).frame(height: 64)
                                    Capsule().fill(sel ? Theme.acc : Theme.cDist).frame(height: days[i].km > 0 ? max(8, 64 * days[i].km / mx) : 0)
                                }.frame(width: 26)
                                Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold)).foregroundStyle(sel ? Theme.onAcc : Theme.text2)
                                    .padding(.horizontal, 6).padding(.vertical, 3).background(sel ? Theme.acc : .clear, in: Capsule())
                                Text(d.formatted(.dateTime.day())).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(future ? Theme.text3 : Theme.text)
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(future)
                    }
                }
            }
        }
    }

    // MARK: Üst başlık, dönem seçici, gün/ay/yıl kartları
    private var header: some View {
        HStack {
            Text("Özet").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 2) {
                ForEach([("sport", "Spor"), ("drive", "Sürüş")], id: \.0) { g in
                    Button { withAnimation(.easeOut(duration: 0.15)) { groupRaw = g.0 } } label: {
                        Text(g.1).font(.subheadline.weight(.semibold))
                            .foregroundStyle(groupRaw == g.0 ? Theme.text : Theme.text3)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(groupRaw == g.0 ? Theme.card2 : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(3).background(Theme.card, in: Capsule())
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(Period.allCases, id: \.self) { p in
                Button { withAnimation(.easeOut(duration: 0.15)) { period = p } } label: {
                    VStack(spacing: 8) {
                        Text(p.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(period == p ? Theme.text : Theme.text3)
                        Rectangle().fill(period == p ? Theme.acc : .clear).frame(height: 2)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func navArrows(canForward: Bool, back: @escaping () -> Void, forward: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36).background(Theme.card2, in: Circle()) }.buttonStyle(.plain)
            Button(action: forward) { Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).frame(width: 36, height: 36).background(Theme.card2, in: Circle()) }
                .buttonStyle(.plain).opacity(canForward ? 1 : 0.3).disabled(!canForward)
        }.foregroundStyle(Theme.text)
    }

    private func totals(_ list: [Activity]) -> some View {
        HStack(alignment: .top) {
            StatCell(label: "Mesafe", value: Fmt.km(list.reduce(0) { $0 + $1.distance }), unit: "km", tint: Theme.cDist, big: true)
            StatCell(label: "Süre", value: Fmt.dur(list.reduce(0) { $0 + $1.moving }), tint: Theme.cTime, big: true)
            StatCell(label: "Aktivite", value: "\(list.count)", big: true)
        }
    }

    private var dayNav: some View {
        let today = Calendar.current.startOfDay(for: Date())
        return Panel {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Calendar.current.isDateInToday(selDay) ? "Bugün" : selDay.formatted(.dateTime.weekday(.wide))).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Text(selDay.formatted(.dateTime.day().month(.wide).year())).font(.subheadline).foregroundStyle(Theme.text2)
                }
                Spacer()
                navArrows(canForward: selDay < today,
                          back: { selDay = Calendar.current.date(byAdding: .day, value: -1, to: selDay) ?? selDay },
                          forward: { selDay = min(today, Calendar.current.date(byAdding: .day, value: 1, to: selDay) ?? selDay) })
            }
        }
    }

    @ViewBuilder private var dayActivities: some View {
        if !dayList.isEmpty {
            ForEach(dayList) { a in
                NavigationLink(value: a) { ActivityCard(act: act, a: a) }.buttonStyle(.plain)
            }
        } else if !act.activities.isEmpty {
            Panel { Text(group == .sport ? "Bu gün kayıtlı spor aktivitesi yok." : "Bu gün kayıtlı sürüş yok.").font(.subheadline).foregroundStyle(Theme.text2).frame(maxWidth: .infinity) }
        }
    }

    private var monthCard: some View {
        let cal = Calendar.current
        let thisM = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let m0 = cal.date(byAdding: .month, value: -monthBack, to: thisM) ?? thisM
        let m1 = cal.date(byAdding: .month, value: 1, to: m0) ?? m0
        let list = acts.filter { $0.start >= m0 && $0.start < m1 }
        let n = cal.range(of: .day, in: .month, for: m0)?.count ?? 30
        let perDay = (0..<n).map { i -> Double in
            let d0 = cal.date(byAdding: .day, value: i, to: m0) ?? m0, d1 = cal.date(byAdding: .day, value: 1, to: d0) ?? d0
            return list.filter { $0.start >= d0 && $0.start < d1 }.reduce(0) { $0 + $1.distance } / 1000
        }
        let mx = max(perDay.max() ?? 0, 0.1)
        return VStack(alignment: .leading, spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(m0.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                        Spacer()
                        navArrows(canForward: monthBack > 0, back: { monthBack += 1 }, forward: { monthBack = max(0, monthBack - 1) })
                    }
                    totals(list)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<n, id: \.self) { i in
                            Capsule().fill(perDay[i] > 0 ? Theme.cDist : Theme.track)
                                .frame(height: perDay[i] > 0 ? max(6, 56 * perDay[i] / mx) : 6)
                                .frame(maxWidth: .infinity)
                        }
                    }.frame(height: 56, alignment: .bottom)
                    HStack { Text("1"); Spacer(); Text("\(n)") }.font(.caption2).foregroundStyle(Theme.text3)
                }
            }
            if list.isEmpty {
                Panel { Text(group == .sport ? "Bu ay kayıtlı spor aktivitesi yok." : "Bu ay kayıtlı sürüş yok.").font(.subheadline).foregroundStyle(Theme.text2).frame(maxWidth: .infinity) }
            } else {
                ForEach(list) { a in NavigationLink(value: a) { ActivityCard(act: act, a: a) }.buttonStyle(.plain) }
            }
        }
    }

    private var yearCard: some View {
        let cal = Calendar.current
        let thisY = cal.dateInterval(of: .year, for: Date())?.start ?? Date()
        let y0 = cal.date(byAdding: .year, value: -yearBack, to: thisY) ?? thisY
        let y1 = cal.date(byAdding: .year, value: 1, to: y0) ?? y0
        let list = acts.filter { $0.start >= y0 && $0.start < y1 }
        let months = (0..<12).map { i -> (date: Date, km: Double) in
            let m0 = cal.date(byAdding: .month, value: i, to: y0) ?? y0, m1 = cal.date(byAdding: .month, value: 1, to: m0) ?? m0
            return (m0, list.filter { $0.start >= m0 && $0.start < m1 }.reduce(0) { $0 + $1.distance } / 1000)
        }
        let mx = max(months.map { $0.km }.max() ?? 0, 0.1)
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(y0.formatted(.dateTime.year())).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    navArrows(canForward: yearBack > 0, back: { yearBack += 1 }, forward: { yearBack = max(0, yearBack - 1) })
                }
                totals(list)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(months.indices, id: \.self) { i in
                        let m = months[i]
                        Button {
                            let nowM = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
                            monthBack = max(0, cal.dateComponents([.month], from: m.date, to: nowM).month ?? 0)
                            period = .month
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Theme.track).frame(height: 90)
                                    Capsule().fill(Theme.cDist).frame(height: m.km > 0 ? max(8, 90 * m.km / mx) : 0)
                                }
                                Text(m.date.formatted(.dateTime.month(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(Theme.text2)
                            }.frame(maxWidth: .infinity).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Sağa kaydır: geçmişe; sola kaydır: ileri (bugünden öteye geçmez)
    private func swipePeriod(back: Bool) {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        withAnimation(.easeOut(duration: 0.2)) {
            switch period {
            case .day: selDay = min(today, cal.date(byAdding: .day, value: back ? -1 : 1, to: selDay) ?? selDay)
            case .week: if back || weekBack > 0 { shiftWeek(back ? 1 : -1) }
            case .month: monthBack = max(0, monthBack + (back ? 1 : -1))
            case .year: yearBack = max(0, yearBack + (back ? 1 : -1))
            }
        }
    }

    private func shiftWeek(_ by: Int) {
        let nb = max(0, weekBack + by)
        guard nb != weekBack else { return }
        var cal = Calendar(identifier: .iso8601); cal.locale = Locale(identifier: "tr_TR")
        let off = cal.dateComponents([.day], from: cal.dateInterval(of: .weekOfYear, for: selDay)?.start ?? selDay, to: selDay).day ?? 0
        let thisWk = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let wk = cal.date(byAdding: .weekOfYear, value: -nb, to: thisWk) ?? thisWk
        let d = cal.date(byAdding: .day, value: off, to: wk) ?? wk
        weekBack = nb
        selDay = min(cal.startOfDay(for: d), cal.startOfDay(for: Date()))
    }

    // Apple Sağlık adımları
    private var stepsCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Adımlar", systemImage: "figure.walk").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                    Spacer()
                    Label("Apple Sağlık", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.cKcal)
                }
                if health.connected {
                    let cal = Calendar.current
                    let isToday = cal.isDateInToday(selDay)
                    let steps = health.week.first(where: { cal.isDate($0.day, inSameDayAs: selDay) })?.steps ?? 0
                    let dist = health.weekDist[cal.startOfDay(for: selDay)] ?? 0
                    HStack(alignment: .top) {
                        StatCell(label: isToday ? "Bugün" : selDay.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)), value: steps.formatted(), unit: "adım", tint: Theme.cSteps, big: true)
                        StatCell(label: "Yürünen", value: Fmt.km(dist), unit: "km", tint: Theme.cDist, big: true)
                    }
                    Chart(health.week, id: \.day) { d in
                        BarMark(x: .value("Gün", d.day, unit: .day), y: .value("Adım", max(d.steps, 60)), width: .ratio(0.55))
                            .foregroundStyle(cal.isDate(d.day, inSameDayAs: selDay) ? Theme.cSteps : Theme.cSteps.opacity(0.32)).cornerRadius(5)
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(Theme.text2) } }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { loc in
                                guard let frame = proxy.plotFrame else { return }
                                let x = loc.x - geo[frame].origin.x
                                if let d: Date = proxy.value(atX: x), let hit = health.week.first(where: { cal.isDate($0.day, inSameDayAs: d) }), hit.day <= Date() {
                                    withAnimation(.easeOut(duration: 0.15)) { selDay = cal.startOfDay(for: hit.day) }
                                }
                            }
                        }
                    }
                    .frame(height: 84)
                    Text("Bir güne dokun: o günün özeti açılır.").font(.caption).foregroundStyle(Theme.text3)
                } else {
                    Text("Günlük adımların ve yürüyüşlerin burada görünsün. Bitirdiğin aktiviteler de Sağlık uygulamasına antrenman olarak yazılır.").font(.subheadline).foregroundStyle(Theme.text2)
                    Button { health.connect() } label: { Label("Apple Sağlık'a bağlan", systemImage: "heart.fill") }.buttonStyle(AccButton(height: 46, color: Theme.cKcal))
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
                TypeIcon(t: a.type)
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.type.title(a.start)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(a.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.text3)
            }.padding(14)
            HStack(alignment: .top, spacing: 8) {
                StatCell(label: "Mesafe", value: Fmt.km(a.distance), unit: "km", tint: Theme.cDist)
                StatCell(label: "Süre", value: Fmt.dur(a.moving), tint: Theme.cTime)
                if a.type.pace { StatCell(label: "Tempo", value: Fmt.pace(avg), unit: "/km", tint: Theme.cPace) }
                else { StatCell(label: "Hız", value: Fmt.num(avg * 3.6, 1), unit: "km/h", tint: Theme.cPace) }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            RouteThumb(act: act, a: a).frame(height: 150)
        }
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                    MapPolyline(coordinates: act.route).stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: act.route).stroke(act.type.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
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
                        }.buttonStyle(.plain)
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
        Text(t).font(.footnote.weight(.bold)).foregroundStyle(c).padding(.horizontal, 14).padding(.vertical, 7)
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
        .background(Theme.bg.opacity(0.96).clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)).ignoresSafeArea(edges: .bottom))
    }

    private func typeChip(_ t: ActType) -> some View {
        Button { act.type = t } label: {
            VStack(spacing: 5) {
                Image(systemName: t.icon).font(.system(size: 20, weight: .bold))
                Text(t.name).font(.caption.weight(.semibold))
            }
            .foregroundStyle(act.type == t ? Theme.onAcc : t.color)
            .frame(width: 64, height: 62)
            .background(act.type == t ? t.color : t.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var idlePanel: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActType.sport) { typeChip($0) }
                    Rectangle().fill(Theme.line).frame(width: 1, height: 40).padding(.horizontal, 2)
                    ForEach(ActType.drive) { typeChip($0) }
                }.padding(.horizontal, 2)
            }
            Button { act.start() } label: {
                Text("BAŞLA").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Theme.onAcc)
                    .frame(width: 108, height: 108).background(act.type.color, in: Circle())
                    .overlay(Circle().stroke(act.type.color.opacity(0.35), lineWidth: 9))
                    .shadow(color: act.type.color.opacity(0.5), radius: 22)
            }.buttonStyle(.plain).padding(.vertical, 6)
            VStack(spacing: 0) {
                if act.type.kind.supportsAutoPause {
                    Toggle("Otomatik duraklat", isOn: $act.autoPause).padding(.vertical, 8)
                    Divider().overlay(Theme.line)
                }
                Toggle("Her kilometrede sesli bildirim", isOn: $act.voice).padding(.vertical, 8)
            }
            .tint(act.type.color).foregroundStyle(Theme.text).font(.subheadline)
            .padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var livePanel: some View {
        let a = act.current
        let avg = (a?.distance ?? 0) / max(1, act.moving)
        let pace = act.type.pace
        let kcal = a.flatMap { Cal.active(act.type, dist: $0.distance, moving: act.moving) }
        return VStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(Fmt.dur(act.moving)).font(.system(size: 68, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.cTime)
                Text("Süre").font(.footnote.weight(.semibold)).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .top, spacing: 0) {
                big(Fmt.km(a?.distance ?? 0), "Mesafe (km)", Theme.cDist)
                big(pace ? Fmt.pace(act.speed ?? 0) : (act.speed.map { Fmt.num($0 * 3.6, 1) } ?? "—"), pace ? "Anlık tempo" : "Hız (km/h)", Theme.cPace)
                if let k = kcal { big(Fmt.num(k), "Kalori", Theme.cKcal) }
                else { big(pace ? Fmt.pace(avg) : Fmt.num(avg * 3.6, 1), pace ? "Ort. tempo" : "Ort. hız", Theme.text) }
            }
            HStack(spacing: 28) {
                if act.state == .running {
                    Button { act.pause() } label: { circle("pause.fill", fg: Theme.onAcc, bg: act.type.color, size: 88) }.buttonStyle(.plain)
                } else {
                    Button { confirmEnd = true } label: { circle("stop.fill", fg: Theme.text, bg: Theme.card2, size: 72) }.buttonStyle(.plain)
                    Button { act.resume() } label: { circle("play.fill", fg: Theme.onAcc, bg: act.type.color, size: 88) }.buttonStyle(.plain)
                }
            }.padding(.top, 4)
            if act.type.kind.supportsAutoPause {
                Toggle("Otomatik duraklat", isOn: $act.autoPause).font(.subheadline).foregroundStyle(Theme.text)
                    .tint(act.type.color).padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if act.state == .running {
                Button { confirmEnd = true } label: { Text("Bitir").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2).frame(height: 36) }
            }
        }
    }

    private func big(_ v: String, _ k: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(c)
            Text(k).font(.caption).foregroundStyle(Theme.text2)
        }.frame(maxWidth: .infinity)
    }
    private func circle(_ icon: String, fg: Color, bg: Color, size: CGFloat) -> some View {
        Image(systemName: icon).font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(fg)
            .frame(width: size, height: size).background(bg, in: Circle()).shadow(color: bg.opacity(0.4), radius: 14)
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
    @State private var segs: [RouteSeg] = []
    @State private var splits: [Split] = []
    @State private var elev: [(Double, Double)] = []
    @State private var steps: Int?
    @State private var cam: MapCameraPosition = .automatic
    @State private var photo = false
    @State private var videoPick = false
    @State private var showSettings = false
    @State private var confirmDel = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapHero
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        TypeIcon(t: a.type, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.type.title(a.start)).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                            Text(a.start.formatted(date: .long, time: .shortened)).font(.subheadline).foregroundStyle(Theme.text2)
                        }
                    }
                    statsPanel
                    VStack(spacing: 10) {
                        Button { photo = true } label: { Label("Fotoğrafa ekle", systemImage: "photo") }.buttonStyle(AccButton(height: 52))
                        Button { videoPick = true } label: { Label("Videoya ekle", systemImage: "film") }.buttonStyle(GhostButton(height: 52))
                    }
                    if elev.count > 2 {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Yükseklik", systemImage: "mountain.2.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.cElev)
                                Chart(elev.indices, id: \.self) { i in
                                    AreaMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(LinearGradient(colors: [Theme.cElev.opacity(0.35), Theme.cElev.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                    LineMark(x: .value("km", elev[i].0), y: .value("m", elev[i].1)).foregroundStyle(Theme.cElev)
                                }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 140)
                            }
                        }
                    }
                    if !splits.isEmpty { splitsPanel }
                }.padding(.horizontal, 16)
            }.padding(.bottom, 24)
        }
        .background(Glow(color: a.type.color))
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
        .sheet(isPresented: $photo) { PhotoEditorSheet(gpx: act.gpxText(a), name: a.type.title(a.start), type: a.type.rawValue, steps: steps, kcal: Cal.active(a), lead: a).environmentObject(model) }
        .sheet(isPresented: $videoPick) {
            SourceSheet(a: a, videoOnly: true) { choice in
                videoPick = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.openVideo(mode: choice == .card ? "card" : "live", lead: a) }
            }
            .presentationDetents([.height(330), .medium]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) { ActivitySettings(act: act, health: health) }
        .confirmationDialog("Aktivite silinsin mi? Bu işlem geri alınamaz.", isPresented: $confirmDel, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { act.delete(a); dismiss() }
        }
    }

    private var mapHero: some View {
        Group {
            if coords.count > 1 {
                Map(position: $cam, interactionModes: [.pan, .zoom]) {
                    MapPolyline(coordinates: coords).stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    ForEach(segs) { s in
                        MapPolyline(coordinates: s.coords).stroke(s.color, style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                    }
                    Annotation("", coordinate: coords[0]) { Circle().fill(Theme.ok).frame(width: 15, height: 15).overlay(Circle().stroke(.white, lineWidth: 2.5)) }
                    Annotation("", coordinate: coords[coords.count - 1]) { Circle().fill(Theme.err).frame(width: 15, height: 15).overlay(Circle().stroke(.white, lineWidth: 2.5)) }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .environment(\.colorScheme, .dark)
                .frame(height: 330)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        Text("Yavaş").font(.caption2.weight(.bold)).foregroundStyle(Theme.text)
                        Capsule().fill(LinearGradient(colors: [speedColor(0), speedColor(0.5), speedColor(1)], startPoint: .leading, endPoint: .trailing)).frame(width: 64, height: 6)
                        Text("Hızlı").font(.caption2.weight(.bold)).foregroundStyle(Theme.text)
                    }.padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.6), in: Capsule()).padding(12)
                }
            } else {
                Theme.card.frame(height: 220).overlay(ProgressView())
            }
        }
    }

    private var statsPanel: some View {
        let avg = a.distance / max(1, a.moving)
        let kcal = Cal.active(a)
        return Panel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.km(a.distance)).font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.cDist)
                    Text("km").font(.title3.weight(.bold)).foregroundStyle(Theme.cDist.opacity(0.75))
                }
                Divider().overlay(Theme.line)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 18) {
                    StatCell(label: "Süre", value: Fmt.dur(a.moving), tint: Theme.cTime, big: true)
                    if let k = kcal { StatCell(label: "Aktif kalori", value: Fmt.num(k), unit: "kcal", tint: Theme.cKcal, big: true) }
                    else if a.type.kind.countsCalories { Button { showSettings = true } label: { StatCell(label: "Aktif kalori", value: "—", unit: "kilonu gir", tint: Theme.cKcal, big: true) }.buttonStyle(.plain) }
                    if a.type.pace { StatCell(label: "Ort. tempo", value: Fmt.pace(avg), unit: "/km", tint: Theme.cPace, big: true) }
                    else { StatCell(label: "Ort. hız", value: Fmt.num(avg * 3.6, 1), unit: "km/h", tint: Theme.cPace, big: true) }
                    StatCell(label: "Yükseliş", value: Fmt.num(a.gain), unit: "m", tint: Theme.cElev, big: true)
                    if a.type.pace { StatCell(label: "En iyi tempo", value: Fmt.pace(min(a.maxSpeed, a.type.maxPlausible)), unit: "/km", tint: Theme.cMax, big: true) }
                    else { StatCell(label: "Maks hız", value: Fmt.num(min(a.maxSpeed, a.type.maxPlausible) * 3.6), unit: "km/h", tint: Theme.cMax, big: true) }
                    if let s = steps, s > 0 { StatCell(label: "Adım", value: s.formatted(), tint: Theme.cSteps, big: true) }
                    else { StatCell(label: "Geçen süre", value: Fmt.dur((a.end ?? a.start).timeIntervalSince(a.start)), big: true) }
                }
            }
        }
    }

    private var splitsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text("Kilometre bölümleri").font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).padding(.bottom, 6)
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
                    let t = worst > best ? 1 - (r - best) / (worst - best) : 1
                    HStack {
                        Text(s.len < 999 ? Fmt.num(s.len / 1000, 2) : "\(s.id)").frame(width: 40, alignment: .leading)
                        Text(a.type.pace ? Fmt.pace(s.len / max(1, s.time)) : Fmt.num(s.len / max(1, s.time) * 3.6, 1)).foregroundStyle(Theme.cPace).frame(width: 84, alignment: .leading)
                        Text(s.ele.map { ($0 >= 0 ? "+" : "") + Fmt.num($0) + " m" } ?? "—").foregroundStyle(Theme.text2).frame(width: 70, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(speedColor(1 - t)).frame(width: max(8, g.size.width * (0.35 + 0.65 * t)), height: 8).frame(maxHeight: .infinity, alignment: .center)
                        }
                    }.font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text).frame(height: 34)
                }
            }
        }
    }

    private func compute() {
        let pts = act.readPoints(a.id).filter { $0.ha <= 30 }
        guard pts.count > 1 else { return }
        coords = pts.map { CLLocationCoordinate2D(latitude: $0.la, longitude: $0.lo) }
        segs = routeSegments(pts)
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
    var kcal: Double? = nil
    var lead: Activity? = nil
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
            ActivityWeb(gpx: gpx, name: name, type: type, steps: steps, kcal: kcal, toVideo: { g, n in
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if let l = lead { model.openVideo(mode: "live", lead: l) } else { model.pendingGpx = (n, g); model.tab = 1; model.openVideo(mode: "live", lead: nil) }
                }
            }, onImage: { _ in }, onProfile: { d, ext in
                model.profile.add(data: d, ext: ext, title: name, type: type)
                model.tab = 2; dismiss()
            })
        }
        .background(Theme.bg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
    }
}

struct ActivityWeb: UIViewRepresentable {
    let gpx: String, name: String, type: String
    var steps: Int? = nil
    var kcal: Double? = nil
    let toVideo: (String, String) -> Void
    var onImage: ((URL) -> Void)? = nil     // dışa aktarılan görsel (profil galerisine eklenir)
    var onProfile: ((Data, String) -> Void)? = nil   // "Profilde paylaş": ham görsel verisi + uzantı
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
        payload["kcal"] = kcal.map { Int($0.rounded()) } ?? NSNull()
        if let d = try? JSONSerialization.data(withJSONObject: payload), let j = String(data: d, encoding: .utf8) {
            cfg.userContentController.addUserScript(WKUserScript(source: "window.__TG_PENDING = \(j);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false; wv.backgroundColor = .black; wv.scrollView.backgroundColor = .black
        wv.scrollView.pinchGestureRecognizer?.isEnabled = false
        wv.scrollView.bouncesZoom = false
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
            guard let b = m.body as? [String: Any] else { return }
            if b["action"] as? String == "profile", let s = b["image"] as? String, let d = Data(base64Encoded: s) {
                p.onProfile?(d, b["ext"] as? String ?? "jpg"); return
            }
            guard b["action"] as? String == "video", let g = b["gpx"] as? String else { return }
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
            p.onImage?(u)
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
    var embedded = false      // true: Profil sekmesi (Bitti düğmesi yok)
    @EnvironmentObject var model: AppModel
    @State private var showCam = false
    @AppStorage("showSteps") private var showSteps = true
    @AppStorage("keepAwake") private var keepAwake = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("profKg") private var kg = 0.0
    @AppStorage("profCm") private var cm = 0.0
    @AppStorage("goalKcal") private var goalKcal = 300.0
    @AppStorage("goalMin") private var goalMin = 30.0
    @AppStorage("goalSteps") private var goalSteps = 8000.0
    @Environment(\.dismiss) private var dismiss
    @State private var profMsg: String?
    @State private var apW = ActivityRecorder.autoPauseSetting(.yuruyus)
    @State private var apR = ActivityRecorder.autoPauseSetting(.kosu)
    @State private var apB = ActivityRecorder.autoPauseSetting(.bisiklet)
    @State private var apT = ActivityRecorder.autoPauseSetting(.tirmanis)

    private func save(_ t: ActType, _ v: Bool) {
        if act.type == t { act.autoPause = v } else { UserDefaults.standard.set(v, forKey: "autoPause2_" + t.rawValue) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tema", selection: $appearance) { Text("Sistem").tag("system"); Text("Koyu").tag("dark"); Text("Açık").tag("light") }.pickerStyle(.segmented)
                } header: { head("Görünüm") } footer: { foot("Stüdyo (video) ekranı şimdilik her zaman koyu kalır.") }
                .listRowBackground(Theme.card)

                Section {
                    HStack { Text("Kilo"); Spacer(); TextField("0", value: $kg, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kg").foregroundStyle(Theme.text2) }
                    HStack { Text("Boy"); Spacer(); TextField("0", value: $cm, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text("cm").foregroundStyle(Theme.text2) }
                    if HealthManager.available && health.connected {
                        Button { health.fetchProfile { w, h, msg in if let w { kg = w }; if let h { cm = h }; profMsg = msg } } label: { Label("Sağlık'tan al", systemImage: "heart.fill").foregroundStyle(Theme.cKcal) }
                    }
                    if let m = profMsg { Text(m).font(.footnote).foregroundStyle(Theme.text2) }
                } header: { head("Vücut bilgileri") } footer: { foot("Kalori hesabı için kullanılır; yalnızca bu cihazda tutulur. Aktif kalori = hareketle yakılan enerji (dinlenme enerjisi çıkarılmış), Apple Fitness'taki gibi.") }
                .listRowBackground(Theme.card)

                Section {
                    HStack { Text("Kalori"); Spacer(); TextField("300", value: $goalKcal, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80); Text("kcal").foregroundStyle(Theme.text2) }
                    HStack { Text("Süre"); Spacer(); TextField("30", value: $goalMin, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80); Text("dk").foregroundStyle(Theme.text2) }
                    HStack { Text("Adım"); Spacer(); TextField("8000", value: $goalSteps, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80); Text("adım").foregroundStyle(Theme.text2) }
                } header: { head("Günlük hedefler") }
                .listRowBackground(Theme.card)

                Section {
                    Toggle("Yürüyüş", isOn: $apW).onChange(of: apW) { _, v in save(.yuruyus, v) }
                    Toggle("Koşu", isOn: $apR).onChange(of: apR) { _, v in save(.kosu, v) }
                    Toggle("Tırmanış", isOn: $apT).onChange(of: apT) { _, v in save(.tirmanis, v) }
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
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    Text(embedded ? "Profil" : "Aktivite ayarları").font(.headline).foregroundStyle(Theme.text)
                    if !embedded { HStack { Spacer(); Button { dismiss() } label: { Text("Bitti").font(.body.weight(.semibold)).foregroundStyle(Theme.onAcc).padding(.horizontal, 16).frame(height: 36).background(Theme.acc, in: Capsule()) }.buttonStyle(.plain) } }
                }.padding(.horizontal, 16).frame(height: 56).background(Theme.bg)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
    }
    private func head(_ t: String) -> some View { Text(t).foregroundStyle(Theme.text2) }
    private func foot(_ t: String) -> some View { Text(t).foregroundStyle(Theme.text3) }
}
