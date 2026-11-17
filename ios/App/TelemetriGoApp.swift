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
    static let accent = Color(red: 1, green: 0.478, blue: 0.102)
    static let bg = Color(red: 0.043, green: 0.051, blue: 0.071)
    static let card = Color(red: 0.082, green: 0.094, blue: 0.129)
    static let card2 = Color(red: 0.11, green: 0.125, blue: 0.188)
    static let ok = Color(red: 0.31, green: 0.9, blue: 0.55)
    static let mid = Color(red: 1, green: 0.82, blue: 0.25)
    static let err = Color(red: 1, green: 0.3, blue: 0.37)
}

/// Kayıt ve GoPro'yu birlikte yöneten model
final class AppModel: ObservableObject {
    let gopro = GoProManager()
    let rec = Recorder()
    @Published var tab = 0
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
            RecordView()
                .tabItem { Label("Kayıt", systemImage: "record.circle") }.tag(0)
            VideoTab()
                .ignoresSafeArea(edges: .bottom)
                .tabItem { Label("Video", systemImage: "film") }.tag(1)
        }
    }
}
