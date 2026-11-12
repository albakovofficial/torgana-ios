import SwiftUI
import WebKit

// Один WKWebView на всё приложение: сайт, мост с сайтом (window.TorganaApp) и правила переходов.
final class WebController: NSObject, ObservableObject {
    static let shared = WebController()

    let webView: WKWebView
    @Published var firstLoadDone = false
    @Published var failed = false

    private var started = false
    private var lastURL: URL?

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // Вход через Яндекс ID и VK ID идёт внутри приложения — иначе вход сохранится в Safari, а не здесь.
    private static let authHosts = ["oauth.yandex.ru", "passport.yandex.ru", "id.vk.com", "oauth.vk.com", "login.vk.com", "vk.com", "id.vk.ru", "oauth.vk.ru", "vk.ru"]

    private override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = .default()
        // Сайт узнаёт приложение по этой метке: прячет то, что в приложении не нужно (установка на экран, web-push).
        config.applicationNameForUserAgent = "TorganaApp/\(WebController.appVersion) (iOS)"
        let content = WKUserContentController()
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        content.addUserScript(WKUserScript(source: WebController.bootScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakScriptHandler(self), name: "torgana")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        if #available(iOS 16.4, *) { webView.isInspectable = isDebug }

        // Обновление жестом вниз — у сайта (бережёт недописанное сообщение и прокрутку переписки); своё не добавляем, иначе два значка.
    }

    private var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // window.TorganaApp — признак приложения и отправка сообщений в него.
    private static var bootScript: String {
        """
        (function () {
          window.TorganaApp = {
            platform: 'ios',
            version: '\(appVersion)',
            post: function (msg) { try { window.webkit.messageHandlers.torgana.postMessage(msg); } catch (e) {} }
          };
          var mark = function () { document.documentElement.classList.add('in-app', 'in-app-ios'); };
          if (document.documentElement) mark(); else document.addEventListener('DOMContentLoaded', mark);
        })();
        """
    }

    func start(_ url: URL) {
        guard !started else { return }
        started = true
        load(url)
    }

    // Ссылка из push/письма может прийти раньше, чем открылась главная, — тогда главную уже не грузим.
    func load(_ url: URL) {
        started = true
        lastURL = url
        webView.load(URLRequest(url: url))
    }

    func retry() {
        failed = false
        if webView.url != nil { webView.reload() } else { load(lastURL ?? Router.shared.baseURL) }
    }

    // Сообщение сайту: window.addEventListener('torgana-native', e => e.detail).
    func send(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            self.webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('torgana-native', { detail: \(json) }));", completionHandler: nil)
        }
    }

    fileprivate func openOutside(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    fileprivate func isAuthHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return WebController.authHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - Переходы
extension WebController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        let scheme = url.scheme?.lowercased() ?? ""
        // Телефон, почта, карты, магазины приложений — системой.
        if !["http", "https", "about", "blob", "data"].contains(scheme) {
            openOutside(url)
            return decisionHandler(.cancel)
        }
        // Встроенные рамки (карта, видео) — как есть; правила только для главной страницы.
        let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !mainFrame || scheme == "about" || scheme == "blob" || scheme == "data" { return decisionHandler(.allow) }
        if Router.shared.isInternal(url) || isAuthHost(url) { return decisionHandler(.allow) }
        // Чужие сайты — в Safari, чтобы не уводить человека из Торганы.
        openOutside(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        failed = false
        if !firstLoadDone { firstLoadDone = true }
        PushManager.shared.resendToken()   // сайт загрузился — отдаём ему адрес устройства для push
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return } // переход отдан системе
        let offline = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                       NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed]
        if e.domain == NSURLErrorDomain && offline.contains(e.code) { failed = true }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - Окна и диалоги
extension WebController: WKUIDelegate {
    // target="_blank": свои страницы — здесь же, чужие — в Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if Router.shared.isInternal(url) || isAuthHost(url) { webView.load(navigationAction.request) } else { openOutside(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        guard let top = UIApplication.shared.topController else { return completionHandler() }
        top.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        guard let top = UIApplication.shared.topController else { return completionHandler(false) }
        top.present(alert, animated: true)
    }
}

// MARK: - Сообщения от сайта
extension WebController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        // Только со своих страниц: чужая рамка или страница входа не может звать приложение.
        guard let origin = message.frameInfo.request.url, Router.shared.isInternal(origin) else { return }
        Bridge.handle(type: type, body: body)
    }
}

// WKUserContentController держит обработчик сильно — прослойка, чтобы не было цикла.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

// Не «WebView»: в iOS 26 у WebKit есть свой SwiftUI-тип WebView.
struct TorganaWebView: UIViewRepresentable {
    let controller: WebController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension UIApplication {
    var torganaWindow: UIWindow? {
        let windows = connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }
    var topController: UIViewController? {
        var top = torganaWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
