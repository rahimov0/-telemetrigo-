import SwiftUI
import CoreLocation

struct RecordView: View {
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
                    Text("Motor sürüşünü GPS ile kaydet. GoPro bağlıysa kamerayı da birlikte başlatır; sonra Video sekmesinde göstergeli videoyu oluşturursun.")
                        .font(.subheadline).foregroundStyle(Theme.text2)
                    goproPanel
                    gpsPanel
                    recordButton
                    if !rec.sessions.isEmpty { sessionsList }
                    help
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Sürüş")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { rec.startPreview(); if gopro.hasSavedCamera && gopro.phase == .idle { gopro.connect() } }
        .sheet(item: Binding(get: { share.map { ShareItem(url: $0) } }, set: { share = $0?.url })) { ShareSheet(items: [$0.url]) }
        .confirmationDialog("Bu kayıt silinsin mi?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let s = confirmDelete { rec.delete(s) } }
        }
    }

    // MARK: GoPro
    private var goproPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 18)).foregroundStyle(goproColor).frame(width: 42, height: 42)
                        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 11))
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
                    HStack(spacing: 8) { Circle().fill(Theme.err).frame(width: 9, height: 9); Text("GoPro kayıtta · \(clock(gopro.recSeconds))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text) }
                }
                if let e = gopro.lastError { Text(e).font(.footnote).foregroundStyle(Theme.mid) }
                HStack(spacing: 10) {
                    switch gopro.phase {
                    case .ready: Button("Bağlantıyı kes") { gopro.disconnect() }.buttonStyle(GhostButton(height: 42))
                    case .scanning, .connecting: Button("Vazgeç") { gopro.disconnect() }.buttonStyle(GhostButton(height: 42))
                    default: Button(gopro.hasSavedCamera ? "GoPro'ya bağlan" : "GoPro ekle") { gopro.connect() }.buttonStyle(AccButton(height: 42))
                    }
                    if gopro.hasSavedCamera && !gopro.isReady {
                        Menu { Button("Kayıtlı kamerayı unut", role: .destructive) { gopro.forget() } } label: {
                            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text).frame(width: 42, height: 42)
                                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                        }
                    }
                }
                if !gopro.hasSavedCamera && !gopro.isReady {
                    Text("İlk bağlantı: GoPro'da aşağı kaydır → Tercihler → Kablosuz Bağlantılar → Cihaz Bağla → GoPro Quik. Sonra burada \"GoPro ekle\"ye bas ve eşleşme isteğini onayla.")
                        .font(.footnote).foregroundStyle(Theme.text3)
                }
            }
        }
    }
    private var goproTitle: String {
        switch gopro.phase {
        case .ready: return gopro.name.isEmpty ? "GoPro bağlı" : "\(gopro.name) bağlı"
        case .scanning: return "GoPro aranıyor…"
        case .connecting: return "Bağlanıyor…"
        case .off: return "Bluetooth kapalı"
        case .failed: return "Bağlanamadı"
        case .idle: return "GoPro bağlı değil"
        }
    }
    private var goproSub: String {
        switch gopro.phase {
        case .ready: return "Saat eşitlendi. Kayıt düğmesi GoPro'yu da başlatır."
        case .scanning: return "Kamerayı aç. Uyku modundaysa bir tuşa bas."
        case .failed(let m): return m
        case .off: return "Ayarlar'dan Bluetooth'u aç."
        default: return "İstersen yalnızca GPS kaydı da alabilirsin."
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
                        Button("İzin ver") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(.subheadline).foregroundStyle(Theme.acc)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(rec.speed.map { "\(Int(($0 * 3.6).rounded()))" } ?? "—").font(.system(size: 76, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
                    Text("km/h").font(.title3).foregroundStyle(Theme.text2)
                }.frame(maxWidth: .infinity)
                if let s = rec.current {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 8) {
                            stat(clock(Int(ctx.date.timeIntervalSince(s.start))), "Süre")
                            stat(String(format: "%.2f", s.distance / 1000).replacingOccurrences(of: ".", with: ","), "Mesafe km")
                            stat("\(Int((s.maxSpeed * 3.6).rounded()))", "Maks km/h")
                        }
                    }
                }
            }
        }
    }
    private var quality: (String, Color) {
        if rec.auth == .denied || rec.auth == .restricted { return ("Konum izni yok", Theme.err) }
        guard let a = rec.accuracy else { return ("Konum bekleniyor", Theme.text2) }
        if a <= 10 { return ("Sinyal iyi · ±\(Int(a)) m", Theme.ok) }
        if a <= 25 { return ("Sinyal orta · ±\(Int(a)) m", Theme.mid) }
        return ("Sinyal zayıf · ±\(Int(a)) m", Theme.err)
    }

    // MARK: Kayıt düğmesi
    private var recordButton: some View {
        VStack(spacing: 10) {
            if !model.recording {
                if gopro.isReady {
                    Toggle("GoPro kaydını da başlat", isOn: $model.useGoPro).tint(Theme.acc).foregroundStyle(Theme.text).padding(.horizontal, 4)
                }
                Button { model.startAll() } label: {
                    Label(gopro.isReady && model.useGoPro ? "GPS + GoPro kaydını başlat" : "GPS kaydını başlat", systemImage: "record.circle")
                }.buttonStyle(AccButton(height: 56))
            } else {
                Button { model.stopAll() } label: {
                    Label(model.busy ? "Durduruluyor…" : "Kaydı durdur", systemImage: "stop.circle.fill")
                }.buttonStyle(RedButton(height: 56)).disabled(model.busy)
                Text("Ekranı kilitleyebilirsin, kayıt devam eder.").font(.footnote).foregroundStyle(Theme.text2)
            }
        }
    }

    // MARK: Kayıtlar
    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kayıtlar").font(.title3.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 6)
            ForEach(rec.sessions) { s in
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("\(clock(Int((s.end ?? s.start).timeIntervalSince(s.start)))) · " + String(format: "%.2f km", s.distance / 1000).replacingOccurrences(of: ".", with: ",") + " · maks \(Int((s.maxSpeed * 3.6).rounded())) km/h")
                                    .font(.footnote).foregroundStyle(Theme.text2)
                                if s.camEvents.contains(where: { $0.type == "camstart" }) {
                                    Label("GoPro ile eşleşti", systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Theme.ok)
                                }
                            }
                            Spacer()
                            Menu {
                                Button { share = rec.gpxURL(s) } label: { Label("GPX'i paylaş", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { confirmDelete = s } label: { Label("Sil", systemImage: "trash") }
                            } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text2).frame(width: 36, height: 36).contentShape(Rectangle()) }
                        }
                        Button { model.useInVideo(s) } label: { Label("Videoya ekle", systemImage: "film") }.buttonStyle(GhostButton(height: 42))
                    }
                }
            }
        }
    }

    private var help: some View {
        DisclosureGroup {
            Text("• Telefon gidonda, gökyüzünü görecek şekilde dursun.\n• Sinyal \"iyi\" olunca kaydı başlat.\n• GoPro bağlıysa kayıt düğmesi kamerayı da başlatır; video ile GPS otomatik eşleşir.\n• Bitince \"Videoya ekle\" ile Video sekmesinde göstergeli videoyu oluştur.")
                .font(.footnote).foregroundStyle(Theme.text2).padding(.top, 6)
        } label: { Text("Nasıl kullanılır?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text2) }
            .tint(Theme.text2).padding(.horizontal, 4)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text); Text(l).font(.caption).foregroundStyle(Theme.text2) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }
}

struct ShareItem: Identifiable { let url: URL; var id: String { url.path } }
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
