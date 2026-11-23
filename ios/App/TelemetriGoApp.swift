import SwiftUI

@main
struct TelemetriGoApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.dark).tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(white: 0.98)
    static let acc = Color(red: 1, green: 0.353, blue: 0.122)         // #FF5A1F (yalnızca aktivite vurgusu)
    static let onAcc = Color(red: 0.10, green: 0.04, blue: 0.01)
    static let text = Color(white: 0.98)
    static let text2 = Color(white: 0.72)
    static let text3 = Color(white: 0.55)
    static let bg = Color(red: 0, green: 0, blue: 0)                   // saf siyah (OLED)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.118)       // #1C1C1E
    static let card2 = Color(red: 0.173, green: 0.173, blue: 0.18)    // #2C2C2E
    static let line = Color.white.opacity(0.08)
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

    init() {
        gopro.onEncodingChange = { [weak self] on, t in
            self?.rec.mark(on ? "camstart" : "camstop", at: t)
        }
    }

    var recording: Bool { rec.current != nil }

    func startAll() {
        rec.start()
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
    private func finish() { rec.stop(); busy = false }

    func useInVideo(_ s: Session) {
        pendingGpx = (s.gpxName, rec.gpxText(s))
        tab = 1
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        // Sekme çubuğu içeriğin altında ayrı yer kaplar (üst üste binme olmaz); üç sekme de canlı kalır (video durumu kaybolmaz)
        VStack(spacing: 0) {
            ZStack {
                page(0) { ActivityTab(act: model.activity, health: model.health) }
                page(1) { VideoTab() }
                page(2) { ProfileTab(act: model.activity, health: model.health, store: model.profile) }
            }
            FloatingTabBar(selection: $model.tab)
        }
        .background(Theme.bg.ignoresSafeArea())
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
