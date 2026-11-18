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
    static let bg = Color(red: 0.035, green: 0.035, blue: 0.043)       // #09090B
    static let card = Color(red: 0.067, green: 0.067, blue: 0.075)     // #111113
    static let card2 = Color(red: 0.094, green: 0.094, blue: 0.106)   // #18181B
    static let line = Color(red: 0.137, green: 0.137, blue: 0.153)    // #232327
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
    @Published var tab = 2
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
        TabView(selection: $model.tab) {
            ActivityTab(act: model.activity, health: model.health)
                .tabItem { Label("Aktivite", systemImage: "figure.run") }.tag(2)
            RecordView()
                .tabItem { Label("Sürüş", systemImage: "gauge.with.dots.needle.67percent") }.tag(0)
            VideoTab()
                .ignoresSafeArea(edges: .bottom)
                .tabItem { Label("Video", systemImage: "film") }.tag(1)
        }
    }
}
