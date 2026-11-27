import SwiftUI

/// App Store'da daha yeni bir sürüm varsa üstte küçük, kapatılabilir bir bant gösterir.
/// Kapatılan sürüm için bir daha gösterilmez; daha yeni bir sürüm çıkınca yeniden görünür.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published var version: String?
    @Published var url: URL?
    private var checked = false

    static func isNewer(_ store: String, than current: String) -> Bool {
        let a = store.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func check() async {
        guard !checked, let id = Bundle.main.bundleIdentifier,
              let api = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)") else { return }
        checked = true
        var req = URLRequest(url: api); req.timeoutInterval = 8; req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = (obj["results"] as? [[String: Any]])?.first,
              let v = r["version"] as? String,
              let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              Self.isNewer(v, than: cur) else { return }
        if UserDefaults.standard.string(forKey: "updDismissed") == v { return }
        url = (r["trackViewUrl"] as? String).flatMap(URL.init(string:))
        version = v
    }
    func dismiss() {
        if let v = version { UserDefaults.standard.set(v, forKey: "updDismissed") }
        version = nil
    }
}

struct UpdateBanner: View {
    @StateObject private var u = UpdateChecker.shared
    @AppStorage("lang") private var langPref = "auto"
    @Environment(\.openURL) private var openURL
    var body: some View {
        Group {
            if let v = u.version {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.acc)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Yeni sürüm mevcut")).font(.system(size: 14, weight: .semibold))
                        Text(LF("Sürüm %@ App Store'da", v)).font(.system(size: 12)).foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 4)
                    Button(L("Güncelle")) { if let link = u.url { openURL(link) } }
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.acc)
                    Button { u.dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text3).padding(6) }
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                .padding(.horizontal, 12).padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: u.version)
        .task { await u.check() }
    }
}
