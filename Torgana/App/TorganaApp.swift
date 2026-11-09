import SwiftUI

// Торгана для iPhone: сайт torgana.ru внутри приложения + то, чего сайт в браузере не умеет:
// push-уведомления Apple, «Войти с Apple», системное «Поделиться», виброотклик, ссылки torgana.ru сразу в приложении.
@main
struct TorganaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { url in router.open(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.open(url) }
                }
        }
    }
}

// Куда перейти: ссылка torgana.ru (из письма, мессенджера), нажатие на push, адрес torgana://…
final class Router: ObservableObject {
    static let shared = Router()

    let baseURL: URL
    @Published var pendingURL: URL?

    private init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "TorganaBaseURL") as? String ?? "https://torgana.ru"
        baseURL = URL(string: raw) ?? URL(string: "https://torgana.ru")!
    }

    func open(_ url: URL) {
        if url.scheme == "torgana" {
            // torgana://l/123 → https://torgana.ru/l/123
            let path = "/" + [url.host, url.path].compactMap { $0 }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            open(path: path + (url.query.map { "?" + $0 } ?? ""))
        } else if isInternal(url) {
            pendingURL = url
        }
    }

    func open(path: String) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, isInternal(url) else { return }
        pendingURL = url
    }

    func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let base = baseURL.host?.lowercased() else { return false }
        return host == base || host == "www." + base
    }
}
