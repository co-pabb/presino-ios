import UIKit
import WebKit

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private var webView: WKWebView!
    private let refresh = UIRefreshControl()
    private var lastTokenAt = Date.distantPast
    private var lastPath = ""
    private var downloadURL: URL?

    // گرفتن توکن برای ارسال موقعیت در پس‌زمینه؛ با همان نشستِ ورودِ صفحه‌ی وب
    private static let tokenJS = """
    try {
      var r = await fetch('/employee/api/native_token.php', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'X-Presino-Native': '1', 'Content-Type': 'application/json' }, body: '{}'
      });
      var t = await r.text();
      try {
        var j = JSON.parse(t);
        if (j && j.success && j.token) { return { ok: true, token: j.token }; }
        return { ok: false, definite: true };
      } catch (e) {
        return { ok: false, definite: r.status !== 500 };
      }
    } catch (e) {
      return { ok: false, definite: false };
    }
    """

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        // «Presino» در نام برنامه باعث می‌شود سایت مثل نسخه‌ی نصب‌شده مستقیم به پنل برود
        cfg.applicationNameForUserAgent = "PresinoiOS/1.0"

        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: GeoBridge.shimJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.add(GeoBridge.shared, name: "presinoGeo")
        cfg.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .automatic
        refresh.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        wv.scrollView.refreshControl = refresh
        webView = wv
        view = wv
        GeoBridge.shared.webView = wv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.load(URLRequest(url: Config.startURL))
        NotificationCenter.default.addObserver(self, selector: #selector(reloadPage), name: .presinoReload, object: nil)
    }

    @objc private func reloadPage() {
        if webView.url?.host == Config.host {
            webView.reload()
        } else {
            webView.load(URLRequest(url: Config.startURL))
        }
    }

    // MARK: - ناوبری

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }   // دانلودِ blob/لینک download
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = (url.scheme ?? "").lowercased()
        if ["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            if url.host == Config.host, url.path.lowercased().contains("logout") {
                Session.token = nil
                GeofenceService.shared.stopAll()
            }
            decisionHandler(.allow)
            return
        }
        // tel: / mailto: / sms: و… بیرون از برنامه باز می‌شوند
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse,
           let cd = http.value(forHTTPHeaderField: "Content-Disposition"),
           cd.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresh.endRefreshing()
        syncToken()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOffline(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showOffline(error)
    }

    private func showOffline(_ error: Error) {
        refresh.endRefreshing()
        if (error as NSError).code == NSURLErrorCancelled { return }
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body dir="rtl" style="font-family:-apple-system;text-align:center;padding:64px 24px;color:#333">
        <div style="font-size:48px">📡</div>
        <h3>اتصال به اینترنت برقرار نیست</h3>
        <p style="color:#777">اتصال را بررسی کنید و دوباره تلاش کنید.</p>
        <p><a href="https://presino.ir/?pwa=1" style="display:inline-block;padding:12px 28px;background:#2563eb;color:#fff;border-radius:10px;text-decoration:none">تلاش دوباره</a></p>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - توکن پس‌زمینه

    private func syncToken() {
        guard let url = webView.url, url.host == Config.host else { return }
        let path = url.path
        let force = lastPath.contains("/auth") || Session.token == nil
        lastPath = path
        if path.contains("/auth") || path == "/" || path.isEmpty { return }   // صفحه‌ی ورود یا معرفی
        if !force && Date().timeIntervalSince(lastTokenAt) < 600 { return }
        lastTokenAt = Date()
        webView.callAsyncJavaScript(Self.tokenJS, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let d = value as? [String: Any] else { return }
            if (d["ok"] as? Bool) == true, let t = d["token"] as? String {
                Session.token = t
                GeofenceService.shared.start()
            } else if (d["definite"] as? Bool) == true {
                Session.token = nil
                GeofenceService.shared.stopAll()
            }
        }
    }

    // MARK: - پنجره‌های جاوااسکریپت (alert / confirm / prompt)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "باشه", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "انصراف", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "تأیید", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "انصراف", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "تأیید", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }

    // پیوندهای target=_blank در همین صفحه باز می‌شوند
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // دوربین (تأیید چهره) فقط برای خود سایت
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == Config.host ? .grant : .prompt)
    }

    // MARK: - دانلود فایل (اکسل، PDF، فیش حقوقی…)

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename)
        downloadURL = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadURL else { return }
        downloadURL = nil
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(vc, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadURL = nil
    }
}
