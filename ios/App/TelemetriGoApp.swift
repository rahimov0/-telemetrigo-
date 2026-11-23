import SwiftUI

@main
struct TelemetriGoApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"   // system | dark | light
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil).tint(Theme.accent)
        }
    }
}

extension Color {
    /// Koyu/açık temada farklı değer alan renk
    init(dark: UIColor, light: UIColor) { self.init(UIColor { $0.userInterfaceStyle == .dark ? dark : light }) }
}

enum Theme {
    static let accent = Color(dark: UIColor(white: 0.98, alpha: 1), light: UIColor(white: 0.07, alpha: 1))
    static let acc = Color(red: 1, green: 0.353, blue: 0.122)         // #FF5A1F (yalnızca aktivite vurgusu)
    static let onAcc = Color(red: 0.10, green: 0.04, blue: 0.01)
    static let text = Color(dark: UIColor(white: 0.98, alpha: 1), light: UIColor(white: 0.07, alpha: 1))
    static let text2 = Color(dark: UIColor(white: 0.72, alpha: 1), light: UIColor(red: 0.36, green: 0.36, blue: 0.40, alpha: 1))
    static let text3 = Color(dark: UIColor(white: 0.55, alpha: 1), light: UIColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1))
    static let bg = Color(dark: .black, light: UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1))
    static let card = Color(dark: UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1), light: .white)
    static let card2 = Color(dark: UIColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1), light: UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1))
    static let line = Color(dark: UIColor.white.withAlphaComponent(0.08), light: UIColor.black.withAlphaComponent(0.08))
    /// Grafik çubuklarının boş zemini
    static let track = Color(dark: UIColor.white.withAlphaComponent(0.07), light: UIColor.black.withAlphaComponent(0.06))
    static let ok = Color(red: 0.31, green: 0.9, blue: 0.55)
    static let mid = Color(red: 1, green: 0.82, blue: 0.25)
    static let err = Color(red: 1, green: 0.3, blue: 0.37)
}

/// Kayıt ve GoPro'yu birlikte yöneten model
final class AppModel: ObservableObject {
    let gopro = GoProManager()
    let rec = Recorder()
    let activity = ActivityRecorder()
    let health = HealthManager()
    let profile = ProfileStore()
    @Published var tab = 0   // 0 Özet · 1 Stüdyo · 2 Profil
    @Published var useGoPro = true
    @Published var pendingGpx: (name: String, text: String)?
    @Published var busy = false
    @Published var videoRoute: VideoRoute?   // video editörü (Stüdyo ve Özet'ten)

    /// Video editörünü aç. `lead` verilirse o aktivitenin verisi videoya hazır bağlanır.
    func openVideo(mode: String, lead: Activity?) { videoRoute = VideoRoute(mode: mode, lead: lead) }

    init() {
        gopro.onEncodingChange = { [weak self] on, t in
            self?.rec.mark(on ? "camstart" : "camstop", at: t)
        }
    }

    var recording: Bool { rec.current != nil }

    func startAll() {
        rec.start(); gopro.reconnectWhileRecording = true
        if useGoPro && gopro.isReady && !gopro.encoding {
            gopro.syncClock()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.rec.mark("camcmd", at: Date())
                self?.gopro.shutter(true)
            }
        }
    }
    func stopAll() {
        busy = true
        if gopro.isReady && gopro.encoding {
            gopro.shutter(false)
            // kameranın "kayıt bitti" bildirimini bekle (en fazla 3 sn), sonra GPS'i kapat
            waitUntil = Date().addingTimeInterval(3)
            waitForCamera()
        } else { finish() }
    }
    private var waitUntil = Date()
    private func waitForCamera() {
        if !gopro.encoding || Date() >= waitUntil { finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.waitForCamera() }
    }
    /// Kayıt bitince kamerayla bağlantıyı kes: kamera kendi uyku/kapanma süresine dönsün, kendiliğinden uyanmasın
    private func finish() { rec.stop(); busy = false; gopro.reconnectWhileRecording = false; gopro.disconnect() }

    func useInVideo(_ s: Session) {
        pendingGpx = (s.gpxName, rec.gpxText(s))
        tab = 1
        if videoRoute == nil { openVideo(mode: "live", lead: nil) }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        // Sekme çubuğu içeriğin altında ayrı yer kaplar (üst üste binme olmaz); üç sekme de canlı kalır (video durumu kaybolmaz)
        VStack(spacing: 0) {
            ZStack {
                page(0) { ActivityTab(act: model.activity, health: model.health) }
                page(1) { StudioTab(act: model.activity) }
                page(2) { ProfileTab(act: model.activity, health: model.health, store: model.profile) }
            }
            FloatingTabBar(selection: $model.tab)
        }
        .background(Theme.bg.ignoresSafeArea())
        .fullScreenCover(item: $model.videoRoute) { VideoCover(v: $0).environmentObject(model) }
    }
    private func page<V: View>(_ i: Int, @ViewBuilder _ v: () -> V) -> some View {
        v().opacity(model.tab == i ? 1 : 0).allowsHitTesting(model.tab == i).accessibilityHidden(model.tab != i)
    }
}

/// Yuvarlak, yarı saydam, yüzen sekme çubuğu
struct FloatingTabBar: View {
    @Binding var selection: Int
    private let items: [(String, String)] = [("Özet", "chart.bar.fill"), ("Stüdyo", "play.rectangle.fill"), ("Profil", "person.crop.circle.fill")]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    if selection != i { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    selection = i
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].1).font(.system(size: 20, weight: .semibold))
                        Text(items[i].0).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selection == i ? Theme.text : Theme.text3)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(selection == i ? Theme.bg.opacity(0.55) : Color.clear, in: Capsule())
                }.buttonStyle(.plain)
                .accessibilityLabel(items[i].0)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 40).padding(.top, 6).padding(.bottom, 4)
    }
}
