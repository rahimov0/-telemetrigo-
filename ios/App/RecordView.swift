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
                VStack(spacing: 12) {
                    goproCard
                    gpsCard
                    recordButton
                    if !rec.sessions.isEmpty { sessionsList }
                    tips
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("TelemetriGo")
        }
        .onAppear { rec.startPreview(); if gopro.hasSavedCamera && gopro.phase == .idle { gopro.connect() } }
        .sheet(item: Binding(get: { share.map { ShareItem(url: $0) } }, set: { share = $0?.url })) { ShareSheet(items: [$0.url]) }
        .confirmationDialog("Bu kayıt silinsin mi?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) { if let s = confirmDelete { rec.delete(s) } }
        }
    }

    // MARK: GoPro
    private var goproCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.title2).foregroundStyle(goproColor).frame(width: 44, height: 44)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(goproTitle).font(.headline)
                    Text(goproSub).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if gopro.isReady, let b = gopro.battery {
                    Label("%\(b)", systemImage: b > 20 ? "battery.75" : "battery.25").font(.subheadline.weight(.semibold))
                }
            }
            if gopro.encoding {
                HStack { Circle().fill(Theme.err).frame(width: 10, height: 10); Text("GoPro kayıtta · \(clock(gopro.recSeconds))").font(.subheadline.weight(.semibold)) }
            }
            if let e = gopro.lastError { Text(e).font(.footnote).foregroundStyle(Theme.mid) }
            HStack {
                switch gopro.phase {
                case .ready: Button("Bağlantıyı kes") { gopro.disconnect() }.buttonStyle(.bordered)
                case .scanning, .connecting: Button("Vazgeç") { gopro.disconnect() }.buttonStyle(.bordered)
                default: Button(gopro.hasSavedCamera ? "GoPro'ya bağlan" : "GoPro ekle") { gopro.connect() }.buttonStyle(.borderedProminent)
                }
                if gopro.hasSavedCamera && !gopro.isReady {
                    Menu { Button("Kayıtlı kamerayı unut", role: .destructive) { gopro.forget() } } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            if !gopro.hasSavedCamera && !gopro.isReady {
                Text("İlk bağlantı: GoPro'da aşağı kaydır → Tercihler → Kablosuz Bağlantılar → Cihaz Bağla → GoPro Quik. Sonra burada \"GoPro ekle\"ye bas ve eşleşme isteğini onayla.")
                    .font(.footnote).foregroundStyle(.secondary)
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
        default: return "İstersen sadece GPS kaydı da alabilirsin."
        }
    }
    private var goproColor: Color { gopro.isReady ? Theme.ok : gopro.phase == .scanning || gopro.phase == .connecting ? Theme.mid : .secondary }

    // MARK: GPS
    private var gpsCard: some View {
        Card {
            HStack {
                let q = quality
                Label(q.0, systemImage: "location.fill").font(.subheadline.weight(.semibold)).foregroundStyle(q.1)
                Spacer()
                if rec.auth == .denied || rec.auth == .restricted {
                    Button("İzin ver") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(.subheadline)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rec.speed.map { "\(Int(($0 * 3.6).rounded()))" } ?? "—").font(.system(size: 88, weight: .bold, design: .rounded)).monospacedDigit()
                Text("km/h").font(.title3).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            if let s = rec.current {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack {
                        stat(clock(Int(ctx.date.timeIntervalSince(s.start))), "Süre")
                        stat(String(format: "%.2f", s.distance / 1000).replacingOccurrences(of: ".", with: ",") + " km", "Mesafe")
                        stat("\(Int((s.maxSpeed * 3.6).rounded()))", "Maks km/h")
                    }
                }
            }
        }
    }
    private var quality: (String, Color) {
        if rec.auth == .denied || rec.auth == .restricted { return ("Konum izni yok", Theme.err) }
        guard let a = rec.accuracy else { return ("Konum bekleniyor", .secondary) }
        if a <= 10 { return ("Sinyal iyi · ±\(Int(a)) m", Theme.ok) }
        if a <= 25 { return ("Sinyal orta · ±\(Int(a)) m", Theme.mid) }
        return ("Sinyal zayıf · ±\(Int(a)) m", Theme.err)
    }

    // MARK: Kayıt düğmesi
    private var recordButton: some View {
        VStack(spacing: 10) {
            if !model.recording {
                if gopro.isReady { Toggle("GoPro kaydını da başlat", isOn: $model.useGoPro).padding(.horizontal, 4) }
                Button { model.startAll() } label: {
                    Label(gopro.isReady && model.useGoPro ? "GPS + GoPro kaydını başlat" : "GPS kaydını başlat", systemImage: "record.circle")
                        .font(.title3.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 18)
                }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
            } else {
                Button { model.stopAll() } label: {
                    Label(model.busy ? "Durduruluyor…" : "Kaydı durdur", systemImage: "stop.circle.fill")
                        .font(.title3.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 18)
                }.buttonStyle(.borderedProminent).tint(Theme.err).disabled(model.busy)
                Text("Ekranı kilitleyebilirsin, kayıt devam eder.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Kayıtlar
    private var sessionsList: some View {
        Card {
            Text("Kayıtlar").font(.headline)
            ForEach(rec.sessions) { s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(s.start.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                        if s.camEvents.contains(where: { $0.type == "camstart" }) {
                            Label("GoPro eşli", systemImage: "link").font(.caption.weight(.semibold)).foregroundStyle(Theme.ok)
                        }
                        Spacer()
                        Menu {
                            Button { share = rec.gpxURL(s) } label: { Label("GPX'i paylaş", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) { confirmDelete = s } label: { Label("Sil", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    }
                    Text("\(clock(Int((s.end ?? s.start).timeIntervalSince(s.start)))) · " + String(format: "%.2f km", s.distance / 1000).replacingOccurrences(of: ".", with: ",") + " · maks \(Int((s.maxSpeed * 3.6).rounded())) km/h")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { model.useInVideo(s) } label: { Label("Videoya ekle", systemImage: "film").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                .padding(12).background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var tips: some View {
        Card {
            Text("İpuçları").font(.headline)
            Text("• Telefon gidonda, gökyüzünü görecek şekilde dursun.\n• Sinyal \"iyi\" olunca kaydı başlat.\n• GoPro bağlıysa kayıt düğmesi kamerayı da başlatır; video ile GPS otomatik eşleşir.\n• Bitince \"Videoya ekle\" ile Video sekmesinde göstergeli videoyu oluştur.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) { Text(v).font(.title3.weight(.bold)).monospacedDigit(); Text(l).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.card2, in: RoundedRectangle(cornerRadius: 12))
    }
    private func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }
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
