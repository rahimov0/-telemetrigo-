import SwiftUI
import CoreLocation

struct RecordView: View {
    @AppStorage("units") private var unitsPref = "metric"   // birim değişince ekran yenilensin
    @AppStorage("lang") private var langPref = "auto"
    @EnvironmentObject var model: AppModel
    var body: some View {
        // Alt nesnelerin değişikliklerini izlemek için ayrı görünüm
        RecordContent(gopro: model.gopro, rec: model.rec)
    }
}

private struct RecordContent: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var gopro: GoProManager
    @ObservedObject var rec: Recorder
    @State private var share: URL?
    @State private var confirmDelete: Session?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Motor sürüşünü GPS ile kaydet. GoPro bağlıysa kamerayı da birlikte başlatır; sonra Video sekmesinde göstergeli videoyu oluşturursun."))
                        .font(.subheadline).foregroundStyle(Theme.text2)
                    goproPanel
                    gpsPanel
                    recordButton
                    if !rec.sessions.isEmpty { sessionsList }
                    help
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 130)
            }
            .background(Glow(color: Theme.mid))
            .navigationTitle(L("Sürüş"))
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { rec.startPreview(); if gopro.hasSavedCamera && gopro.phase == .idle { gopro.connect() } }
        .onDisappear { if rec.current == nil { gopro.disconnect() } }   // ekrandan çıkınca bağlantı açık kalmasın
        .sheet(item: Binding(get: { share.map { ShareItem(url: $0) } }, set: { share = $0?.url })) { ShareSheet(items: [$0.url]) }
        .confirmationDialog(L("Bu kayıt silinsin mi?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button(L("Sil"), role: .destructive) { if let s = confirmDelete { rec.delete(s) } }
        }
    }

    // MARK: GoPro
    private var goproPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(goproColor).frame(width: 42, height: 42)
                        .background(goproColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goproTitle).font(.headline).foregroundStyle(Theme.text)
                        Text(goproSub).font(.footnote).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if gopro.isReady, let b = gopro.battery {
                        Label("%\(b)", systemImage: b > 20 ? "battery.75" : "battery.25").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                }
                if gopro.encoding {
                    HStack(spacing: 8) { Circle().fill(Theme.err).frame(width: 9, height: 9); Text(LF("GoPro kayıtta · %@", clock(gopro.recSeconds))).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text) }
                }
                if let e = gopro.lastError { Text(e).font(.footnote).foregroundStyle(Theme.mid) }
                HStack(spacing: 10) {
                    switch gopro.phase {
                    case .ready: Button(L("Bağlantıyı kes")) { gopro.disconnect() }.buttonStyle(GhostButton(height: 42))
                    case .scanning, .connecting: Button(L("Vazgeç")) { gopro.disconnect() }.buttonStyle(GhostButton(height: 42))
                    default: Button(gopro.hasSavedCamera ? L("GoPro'ya bağlan") : "GoPro ekle") { gopro.connect() }.buttonStyle(AccButton(height: 42))
                    }
                    if gopro.hasSavedCamera && !gopro.isReady {
                        Menu { Button(L("Kayıtlı kamerayı unut"), role: .destructive) { gopro.forget() } } label: {
                            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text).frame(width: 42, height: 42)
                                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                        }
                    }
                }
                if !gopro.hasSavedCamera && !gopro.isReady {
                    Text(L("İlk bağlantı: GoPro'da aşağı kaydır → Tercihler → Kablosuz Bağlantılar → Cihaz Bağla → GoPro Quik. Sonra burada \"GoPro ekle\"ye bas ve eşleşme isteğini onayla."))
                        .font(.footnote).foregroundStyle(Theme.text3)
                }
            }
        }
    }
    private var goproTitle: String {
        switch gopro.phase {
        case .ready: return gopro.name.isEmpty ? L("GoPro bağlı") : LF("%@ bağlı", gopro.name)
        case .scanning: return L("GoPro aranıyor…")
        case .connecting: return L("Bağlanıyor…")
        case .off: return L("Bluetooth kapalı")
        case .failed: return L("Bağlanamadı")
        case .idle: return L("GoPro bağlı değil")
        }
    }
    private var goproSub: String {
        switch gopro.phase {
        case .ready: return L("Saat eşitlendi. Kayıt düğmesi GoPro'yu da başlatır.")
        case .scanning: return L("Kamerayı aç. Uyku modundaysa bir tuşa bas.")
        case .failed(let m): return m
        case .off: return L("Ayarlar'dan Bluetooth'u aç.")
        default: return L("İstersen yalnızca GPS kaydı da alabilirsin.")
        }
    }
    private var goproColor: Color { gopro.isReady ? Theme.ok : gopro.phase == .scanning || gopro.phase == .connecting ? Theme.mid : Theme.text2 }

    // MARK: GPS
    private var gpsPanel: some View {
        Panel {
            VStack(spacing: 10) {
                HStack {
                    let q = quality
                    HStack(spacing: 6) { Circle().fill(q.1).frame(width: 8, height: 8); Text(q.0).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text) }
                    Spacer()
                    if rec.auth == .denied || rec.auth == .restricted {
                        Button(L("İzin ver")) { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(.subheadline).foregroundStyle(Theme.acc)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rec.speed.map { "\(Int(Units.speed($0).rounded()))" } ?? "—").font(.system(size: 84, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.cPace)
                    Text(Units.speedUnit).font(.title3.weight(.bold)).foregroundStyle(Theme.cPace.opacity(0.75))
                }.frame(maxWidth: .infinity)
                if let s = rec.current {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 8) {
                            stat(clock(Int(ctx.date.timeIntervalSince(s.start))), L("Süre"), Theme.cTime)
                            stat(String(format: "%.2f", s.distance / Units.distDiv).replacingOccurrences(of: ".", with: ","), "Mesafe \(Units.distUnit)", Theme.cDist)
                            stat("\(Int(Units.speed(s.maxSpeed).rounded()))", LF("Maks %@", Units.speedUnit), Theme.cMax)
                        }
                    }
                }
            }
        }
    }
    private var quality: (String, Color) {
        if rec.auth == .denied || rec.auth == .restricted { return (L("Konum izni yok"), Theme.err) }
        guard let a = rec.accuracy else { return (L("Konum bekleniyor"), Theme.text2) }
        if a <= 10 { return (LF("Sinyal iyi · ±%d m", Int(a)), Theme.ok) }
        if a <= 25 { return (LF("Sinyal orta · ±%d m", Int(a)), Theme.mid) }
        return (LF("Sinyal zayıf · ±%d m", Int(a)), Theme.err)
    }

    // MARK: Kayıt düğmesi
    private var recordButton: some View {
        VStack(spacing: 10) {
            if !model.recording {
                if gopro.isReady {
                    Toggle(L("GoPro kaydını da başlat"), isOn: $model.useGoPro).tint(Theme.acc).foregroundStyle(Theme.text).padding(.horizontal, 4)
                }
                Button { model.startAll() } label: {
                    Label(gopro.isReady && model.useGoPro ? L("GPS + GoPro kaydını başlat") : L("GPS kaydını başlat"), systemImage: "record.circle")
                }.buttonStyle(AccButton(height: 56))
            } else {
                Button { model.stopAll() } label: {
                    Label(model.busy ? L("Durduruluyor…") : L("Kaydı durdur"), systemImage: "stop.circle.fill")
                }.buttonStyle(RedButton(height: 56)).disabled(model.busy)
                Text(L("Ekranı kilitleyebilirsin, kayıt devam eder.")).font(.footnote).foregroundStyle(Theme.text2)
            }
        }
    }

    // MARK: Kayıtlar
    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Kayıtlar")).font(.title3.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 6)
            ForEach(rec.sessions) { s in
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("\(clock(Int((s.end ?? s.start).timeIntervalSince(s.start)))) · " + (String(format: "%.2f ", s.distance / Units.distDiv).replacingOccurrences(of: ".", with: ",") + Units.distUnit) + " · maks \(Int(Units.speed(s.maxSpeed).rounded())) \(Units.speedUnit)")
                                    .font(.footnote).foregroundStyle(Theme.text2)
                                if s.camEvents.contains(where: { $0.type == "camstart" }) {
                                    Label(L("GoPro ile eşleşti"), systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Theme.ok)
                                }
                            }
                            Spacer()
                            Menu {
                                Button { share = rec.gpxURL(s) } label: { Label(L("GPX'i paylaş"), systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { confirmDelete = s } label: { Label(L("Sil"), systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 36, height: 36).contentShape(Rectangle()) }
                        }
                        Button { model.useInVideo(s) } label: { Label(L("Videoya ekle"), systemImage: "film") }.buttonStyle(GhostButton(height: 42))
                    }
                }
            }
        }
    }

    private var help: some View {
        DisclosureGroup {
            Text(L("• Telefon gidonda, gökyüzünü görecek şekilde dursun.\n• Sinyal \"iyi\" olunca kaydı başlat.\n• GoPro bağlıysa kayıt düğmesi kamerayı da başlatır; video ile GPS otomatik eşleşir.\n• Bitince \"Videoya ekle\" ile Video sekmesinde göstergeli videoyu oluştur."))
                .font(.footnote).foregroundStyle(Theme.text2).padding(.top, 6)
        } label: { Text(L("Nasıl kullanılır?")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2) }
            .tint(Theme.text2).padding(.horizontal, 4)
    }

    private func stat(_ v: String, _ l: String, _ c: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(c); Text(l).font(.caption).foregroundStyle(Theme.text2) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.card2, in: RoundedRectangle(cornerRadius: 14))
    }
    private func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }
}

struct RedButton: ButtonStyle {
    var height: CGFloat = 52
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: height)
            .background(Theme.err.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ShareItem: Identifiable { let url: URL; var id: String { url.path } }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
