import UIKit
import GoogleMobileAds

/// Flyover kaydı bittikten sonra gösterilen geçiş reklamı.
/// TestFlight/geliştirme derlemelerinde Google'ın TEST reklamı gösterilir (kendi reklamlarımıza dokunmak AdMob hesabını riske atar);
/// yalnızca App Store'dan indirilen sürümde gerçek reklam birimi kullanılır.
@MainActor
final class FlyoverAd: NSObject, GADFullScreenContentDelegate {
    static let shared = FlyoverAd()
    static let appID = "ca-app-pub-6811894230993861~5958730531"        // KROVA (AdMob) — Info.plist'te de aynı
    private static let realUnit = "ca-app-pub-6811894230993861/9051797732"   // "Flyover Kayit Sonrasi Gecis"
    private static let testUnit = "ca-app-pub-3940256099942544/4411468910"   // Google test geçiş reklamı
    /// App Store sürümünde makbuz "receipt", TestFlight'ta "sandboxReceipt" olur
    private static var isAppStoreBuild: Bool {
        #if DEBUG
        return false
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt"
        #endif
    }
    static var unitID: String { isAppStoreBuild ? realUnit : testUnit }
    private var ad: GADInterstitialAd?
    private var started = false
    private var onDone: (() -> Void)?

    /// Kişiselleştirme yok: izleme izni istenmez, Sağlık verisiyle hiçbir bağ kurulmaz
    private func request() -> GADRequest {
        let r = GADRequest()
        let e = GADExtras(); e.additionalParameters = ["npa": "1"]
        r.register(e)
        return r
    }

    func prepare() {
        if !started { started = true; GADMobileAds.sharedInstance().start(completionHandler: nil) }
        guard ad == nil else { return }
        GADInterstitialAd.load(withAdUnitID: Self.unitID, request: request()) { [weak self] ad, _ in
            DispatchQueue.main.async { self?.ad = ad; ad?.fullScreenContentDelegate = self }
        }
    }

    /// Reklam hazırsa gösterir, bitince (veya hazır değilse hemen) `done` çağrılır
    func show(done: @escaping () -> Void) {
        guard let ad, let vc = Self.topController() else { prepare(); done(); return }
        onDone = done
        self.ad = nil
        ad.present(fromRootViewController: vc)
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in let d = self.onDone; self.onDone = nil; self.prepare(); d?() }
    }
    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in let d = self.onDone; self.onDone = nil; self.prepare(); d?() }
    }

    private static func topController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}
