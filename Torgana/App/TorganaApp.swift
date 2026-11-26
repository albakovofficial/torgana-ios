import SwiftUI

// Торгана для iPhone — родное приложение на SwiftUI. Данные — с сервера torgana.ru (те же /api/…, что у сайта).
// Разделы, которые ещё не переписаны на Swift, открываются страницами сайта внутри приложения (Web/WebController.swift).
@main
struct TorganaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared
    @StateObject private var nav = Nav.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(app)
                .environmentObject(nav)
                .font(.on(16))
                .tint(T.accent)
                .onAppear { app.start(); LookSettings.apply() }
                .onOpenURL { Router.shared.open($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { Router.shared.open(url) }
                }
        }
    }
}

// Куда перейти: ссылка torgana.ru (из письма, мессенджера), нажатие на push, адрес torgana://…
// Только постоянный адрес сайта — можно звать с любого потока (Sendable).
final class Router: Sendable {
    static let shared = Router()

    let baseURL: URL

    private init() {
        var raw = Bundle.main.object(forInfoDictionaryKey: "TorganaBaseURL") as? String ?? "https://torgana.ru"
        #if DEBUG
        // Снимки экранов на GitHub Actions: запуск с -base http://127.0.0.1:8787 (ci/demo-server.js).
        if let b = UserDefaults.standard.string(forKey: "base"), !b.isEmpty { raw = b }
        #endif
        baseURL = URL(string: raw) ?? URL(string: "https://torgana.ru")!
    }

    func open(_ url: URL) {
        if url.scheme == "torgana" {
            // torgana://l/123 → /l/123
            let path = "/" + [url.host, url.path].compactMap { $0 }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            open(path: path + (url.query.map { "?" + $0 } ?? ""))
        } else if isInternal(url) {
            open(path: url.path + (url.query.map { "?" + $0 } ?? ""))
        }
    }

    func open(path: String) {
        Task { @MainActor in Nav.shared.open(path: path) }
    }

    func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let base = baseURL.host?.lowercased() else { return false }
        return host == base || host == "www." + base
    }
}
