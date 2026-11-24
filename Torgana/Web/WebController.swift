import SwiftUI
import WebKit

// Страницы сайта внутри приложения — для разделов, которые ещё не переписаны на Swift.
// WebController — общее: настройки WKWebView, мост с сайтом (window.TorganaApp), правила переходов.
// Каждый экран сайта — свой WKWebView (WebPage); куки общие (WKWebsiteDataStore.default), поэтому вход один на всё приложение.
final class WebController: NSObject {
    static let shared = WebController()

    /// Страница, которая последней писала приложению, — ей уходят ответы (push.status, auth.apple, share.result).
    weak var current: WKWebView?

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // Вход через Яндекс ID и VK ID идёт внутри приложения — иначе вход сохранится в Safari, а не здесь.
    static let authHosts = ["oauth.yandex.ru", "passport.yandex.ru", "id.vk.com", "oauth.vk.com", "login.vk.com", "vk.com", "id.vk.ru", "oauth.vk.ru", "vk.ru"]

    private lazy var handler = WeakScriptHandler(self)

    func makeWebView(embedded: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = .default()
        // Сайт узнаёт приложение по этой метке: прячет оплату, установку на экран, web-push.
        config.applicationNameForUserAgent = "TorganaApp/\(WebController.appVersion) (iOS)"
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: WebController.bootScript(embedded: embedded), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(handler, name: "torgana")
        config.userContentController = content
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isOpaque = false
        web.backgroundColor = UIColor(T.bg)
        web.scrollView.backgroundColor = UIColor(T.bg)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.keyboardDismissMode = .interactive
        #if DEBUG
        web.isInspectable = true
        #endif
        return web
    }

    // window.TorganaApp — признак приложения и отправка сообщений в него.
    // embedded: страница внутри родного приложения — шапку, подвал и нижнее меню сайта прячем (есть свои),
    // а ссылки на уже родные экраны (объявление, поиск, главная, избранное) открываем в приложении.
    private static func bootScript(embedded: Bool) -> String {
        let app = "window.TorganaApp = { platform: 'ios', version: '" + appVersion + "', native: " + (embedded ? "true" : "false") + ", push: 'app', "
            + "post: function (msg) { try { window.webkit.messageHandlers.torgana.postMessage(msg); } catch (e) {} } };"
        let classes = embedded ? "'in-app', 'in-app-ios', 'in-app-native'" : "'in-app', 'in-app-ios'"
        let css = "#header, #footer, #bottom-nav, .cookie-bar { display: none !important; } "
            + "#app { min-height: 0 !important; padding-bottom: 110px; }"
        let style = embedded
            ? "var st = document.createElement('style'); st.textContent = '" + css + "'; (document.head || document.documentElement).appendChild(st);"
            : ""
        let mark = "var mark = function () { document.documentElement.classList.add(" + classes + "); " + style + " };"
            + "if (document.documentElement) mark(); else document.addEventListener('DOMContentLoaded', mark);"
        let links = embedded ? #"""
          var NATIVE = /^\/(?:$|l\/\d+|search$|c\/|favorites$|messages(?:\/(?:\d+|support))?$|u\/\d+$|edit\/\d+$|new$|profile(?:\/listings)?$)/;
          window.addEventListener('click', function (e) {
            var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
            if (!a || a.target === '_blank' || a.hasAttribute('download')) return;
            var u; try { u = new URL(a.href, location.href); } catch (x) { return; }
            if (u.origin !== location.origin || !NATIVE.test(u.pathname)) return;
            e.preventDefault(); e.stopImmediatePropagation();
            window.TorganaApp.post({ type: 'native.open', path: u.pathname + u.search });
          }, true);
          """# : ""
        return "(function () { " + app + mark + links + " })();"
    }

    // Сообщение сайту: window.addEventListener('torgana-native', e => e.detail).
    func send(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            guard let web = self.current,
                  JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            web.evaluateJavaScript("window.dispatchEvent(new CustomEvent('torgana-native', { detail: \(json) }));", completionHandler: nil)
        }
    }

    static func openOutside(_ url: URL) {
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    static func isAuthHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return authHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Куда можно уйти со страницы: свои страницы и вход Яндекс/VK — внутри, остальное — системой или в Safari.
    static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "blob", "data"].contains(scheme) { openOutside(url); return .cancel }
        let mainFrame = action.targetFrame?.isMainFrame ?? true
        if !mainFrame || scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }
        if Router.shared.isInternal(url) || isAuthHost(url) { return .allow }
        openOutside(url)
        return .cancel
    }
}

// MARK: - Сообщения от сайта
extension WebController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        // Только со своих страниц: чужая рамка или страница входа не может звать приложение.
        guard let origin = message.frameInfo.request.url, Router.shared.isInternal(origin) else { return }
        current = message.webView
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

// MARK: - Одна страница сайта
final class WebPage: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    @Published var loading = true
    @Published var failed = false
    @Published var title = ""
    /// Адрес открытой страницы (сайт меняет его без перезагрузки — следим через KVO).
    @Published var path = ""
    private var lastURL: URL?
    private var urlWatch: NSKeyValueObservation?

    init(path: String, embedded: Bool = true) {
        web = WebController.shared.makeWebView(embedded: embedded)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        urlWatch = web.observe(\.url, options: [.new]) { [weak self] w, _ in
            let p = w.url.map { $0.path + ($0.query.map { "?" + $0 } ?? "") } ?? ""
            DispatchQueue.main.async { if self?.path != p { self?.path = p } }
        }
        load(path: path)
    }

    func load(path: String) {
        let url = URL(string: path, relativeTo: Router.shared.baseURL)?.absoluteURL ?? Router.shared.baseURL
        lastURL = url
        failed = false
        web.load(URLRequest(url: url))
    }

    func retry() {
        failed = false
        if web.url != nil { web.reload() } else if let u = lastURL { web.load(URLRequest(url: u)) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(WebController.policy(for: navigationAction))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        failed = false
        title = webView.title ?? ""
        CookieSync.shared.pullFromWeb()     // вошли или вышли на странице сайта — родные экраны узнают сразу
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }

    private func handle(_ error: Error) {
        loading = false
        let e = error as NSError
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return } // переход отдан системе
        let offline = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                       NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed]
        if e.domain == NSURLErrorDomain && offline.contains(e.code) { failed = true }
    }

    // target="_blank": свои страницы — здесь же, чужие — в Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if Router.shared.isInternal(url) || WebController.isAuthHost(url) { webView.load(navigationAction.request) } else { WebController.openOutside(url) }
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

struct WebHostView: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = .clear
        attach(web, to: box)
        return box
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if web.superview !== uiView { attach(web, to: uiView) }
    }
    private func attach(_ web: WKWebView, to box: UIView) {
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: box.leadingAnchor), web.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            web.topAnchor.constraint(equalTo: box.topAnchor), web.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
    }
}

struct WebPageView: View {
    @ObservedObject var page: WebPage
    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            WebHostView(web: page.web).ignoresSafeArea(edges: .bottom)
            if page.loading { ProgressView().tint(T.accent) }
            if page.failed { OfflineView { page.retry() } }
        }
    }
}

// Страница сайта, открытая из родного экрана (чат, продавец, документы…) — с родной кнопкой «Назад».
struct WebScreen: View {
    let path: String
    var title: String = ""
    var closeOnLogin = false
    @StateObject private var page: WebPage
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    init(path: String, title: String = "", closeOnLogin: Bool = false) {
        self.path = path
        self.title = title
        self.closeOnLogin = closeOnLogin
        _page = StateObject(wrappedValue: WebPage(path: path))
    }

    var body: some View {
        if closeOnLogin {
            // Вход через Яндекс/VK — в окне поверх экрана входа.
            WebPageView(page: page)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
                .onChange(of: app.me?.id) { _, id in if id != nil { dismiss() } }
        } else {
            // Раздел сайта внутри приложения: шапка и нижнее меню — родные, как на остальных экранах.
            VStack(alignment: .leading, spacing: 0) {
                BackLink().padding(.horizontal, 20)
                WebPageView(page: page)
            }
            .sitePage()
        }
    }
}

// Нет связи: понятный экран и кнопка «Повторить» вместо белой страницы.
struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(T.accent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(T.accentSoft))
            Text("Нет соединения").font(.on(22, .bold)).foregroundStyle(T.text)
            Text("Проверьте интернет и попробуйте ещё раз.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Повторить", action: retry).buttonStyle(TButton(kind: .dark, full: false)).padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg.ignoresSafeArea())
    }
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
