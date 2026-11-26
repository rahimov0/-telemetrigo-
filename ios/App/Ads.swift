import UIKit
import GoogleMobileAds
import UserMessagingPlatform

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
    private var consentDone = false
    private var gathering = false

    /// AB/BK'de Google'ın onay penceresi (UMP); diğer ülkelerde hiçbir şey göstermez. Reklam yalnızca izin uygunsa istenir
    func gatherConsent(_ completion: @escaping () -> Void) {
        if consentDone { completion(); return }
        if gathering { return }
        gathering = true
        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: UMPRequestParameters()) { [weak self] _ in
            Task { @MainActor in
                UMPConsentForm.loadAndPresentIfRequired(from: Self.topController()) { _ in
                    Task { @MainActor in self?.consentDone = true; self?.gathering = false; completion() }
                }
            }
        }
    }

    /// Ayarlar'daki "Reklam gizlilik seçenekleri" düğmesi yalnızca gerekli bölgelerde görünür
    static var privacyOptionsRequired: Bool {
        UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }
    static func showPrivacyOptions() {
        UMPConsentForm.presentPrivacyOptionsForm(from: topController()) { _ in }
    }
    private var onDone: (() -> Void)?

    /// Kişiselleştirme yok: izleme izni istenmez, Sağlık verisiyle hiçbir bağ kurulmaz
    private func request() -> GADRequest {
        let r = GADRequest()
        let e = GADExtras(); e.additionalParameters = ["npa": "1"]
        r.register(e)
        return r
    }

    func prepare() {
        if !consentDone { gatherConsent { [weak self] in self?.prepare() }; return }
        guard UMPConsentInformation.sharedInstance.canRequestAds else { return }
        if !started { started = true; GADMobileAds.sharedInstance().start(completionHandler: nil) }
        guard ad == nil else { return }
        GADInterstitialAd.load(withAdUnitID: Self.unitID, request: request()) { [weak self] ad, _ in
            DispatchQueue.main.async { self?.ad = ad; ad?.fullScreenContentDelegate = self }
        }
    }

    /// Reklam hazırsa gösterir; değilse kısa süre yüklenmesini bekler. Bitince (veya reklam yoksa) `done` çağrılır
    func show(done: @escaping () -> Void) {
        Task { @MainActor in
            if ad == nil { prepare() }
            var waited = 0.0
            while ad == nil && waited < 4 { try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25 }
            // dışa aktarma penceresi kapanırken ekran değişir: kısa bekle
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let ad, let vc = Self.topController() else { done(); return }
            onDone = done
            self.ad = nil
            ad.present(fromRootViewController: vc)
        }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in let d = self.onDone; self.onDone = nil; self.prepare(); d?() }
    }
    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in let d = self.onDone; self.onDone = nil; self.prepare(); d?() }
    }

    /// Önde görünen normal pencerenin en üstteki ekranı (bizim ilerleme penceremiz gibi üst seviye pencereler hariç)
    fileprivate static func topController() -> UIViewController? {
        let wins = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            .filter { !$0.isHidden && $0.windowLevel == .normal }
        var vc = (wins.first { $0.isKeyWindow } ?? wins.last)?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}
