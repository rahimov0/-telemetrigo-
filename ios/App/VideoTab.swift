import SwiftUI
import WebKit

/// Video işleme ekranı: TelemetriGo web uygulaması (göstergeler + dışa aktarma).
/// Kayıt sekmesindeki GPX buraya aktarılır; oluşturulan video paylaşım ekranıyla kaydedilir.
struct VideoTab: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        WebView(pending: $model.pendingGpx).background(Theme.bg.ignoresSafeArea())
    }
}

struct WebView: UIViewRepresentable {
    @Binding var pending: (name: String, text: String)?
    static let home = URL(string: "https://telemetrigo.rahimov.tr/?app=1")!

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.applicationNameForUserAgent = "TelemetriGoApp/1.0"
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = UIColor(Theme.bg)
        wv.scrollView.backgroundColor = UIColor(Theme.bg)
        wv.allowsLinkPreview = false
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coordinator.reload(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = rc
        context.coordinator.web = wv
        wv.load(URLRequest(url: Self.home))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if let p = pending {
            context.coordinator.deliver(p)
            DispatchQueue.main.async { pending = nil }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        weak var web: WKWebView?
        private var loaded = false
        private var queued: (name: String, text: String)?
        private var dest: URL?

        @objc func reload(_ rc: UIRefreshControl) { web?.reload(); rc.endRefreshing() }

        /// GPX'i web uygulamasına ver (sayfa yüklenmediyse yüklenince)
        func deliver(_ p: (name: String, text: String)) {
            guard loaded, let web else { queued = p; return }
            guard let data = try? JSONSerialization.data(withJSONObject: ["name": p.name, "gpx": p.text]),
                  let json = String(data: data, encoding: .utf8) else { return }
            web.evaluateJavaScript("window.TelemetriGo && window.TelemetriGo.receiveGpx(\(json));")
        }

        func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let q = queued { queued = nil; deliver(q) }
        }
        func webView(_ w: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loaded = false }
        func webView(_ w: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let html = """
            <html><head><meta name=viewport content="width=device-width,initial-scale=1"></head>
            <body style="background:#0b0d12;color:#f2f4f8;font:17px -apple-system;padding:40px 24px;text-align:center">
            <h2>Bağlantı yok</h2><p style="color:#8b93a7">Video ekranı internetten açılıyor. İnternete bağlanıp sayfayı aşağı çekerek yenile.</p></body></html>
            """
            w.loadHTMLString(html, baseURL: nil)
        }

        // Dış bağlantılar Safari'de açılsın
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, preferences: WKWebpagePreferences,
                     decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if a.shouldPerformDownload { decisionHandler(.download, preferences); return }
            if let u = a.request.url, a.navigationType == .linkActivated, let h = u.host, !h.hasSuffix("rahimov.tr"), !h.hasSuffix("github.io") {
                UIApplication.shared.open(u); decisionHandler(.cancel, preferences); return
            }
            decisionHandler(.allow, preferences)
        }
        func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(r.canShowMIMEType ? .allow : .download)
        }
        func webView(_ w: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ w: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

        // MARK: İndirme → paylaşım ekranı (Videoyu Kaydet)
        func download(_ d: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename.isEmpty ? "TelemetriGo.mp4" : suggestedFilename)
            try? FileManager.default.removeItem(at: url)
            dest = url; completionHandler(url)
        }
        func downloadDidFinish(_ d: WKDownload) {
            guard let url = dest, let web else { return }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            vc.popoverPresentationController?.sourceView = web
            web.window?.rootViewController?.topMost.present(vc, animated: true)
        }
        func download(_ d: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            web?.evaluateJavaScript("alert('Video kaydedilemedi: ' + \(String(reflecting: error.localizedDescription)))")
        }

        // MARK: Sayfa uyarıları (alert/confirm)
        func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler() })
            if let top = w.window?.rootViewController?.topMost { top.present(a, animated: true) } else { completionHandler() }
        }
    }
}

extension UIViewController {
    var topMost: UIViewController { presentedViewController?.topMost ?? self }
}
