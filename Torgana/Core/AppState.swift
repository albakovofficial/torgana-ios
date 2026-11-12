import SwiftUI
import UserNotifications

// Общее состояние приложения: кто вошёл, справочники (категории, города), счётчики, избранное.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var me: Me?
    @Published var config: AppConfig?
    @Published var unread = 0
    @Published var notices = 0
    @Published var city: String = UserDefaults.standard.string(forKey: "city") ?? "" {
        didSet { UserDefaults.standard.set(city, forKey: "city") }
    }
    /// Избранное, изменённое на этом экране: id → в избранном ли. Карточки в других списках сразу видят изменение.
    @Published var favs: [Int: Bool] = [:]
    @Published var toast: Toast?

    struct Toast: Equatable { let text: String; let bad: Bool; let id = UUID() }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        // Вошли или вышли (на странице сайта или в родном экране) — обновляем профиль.
        CookieSync.shared.onChange = { [weak self] in Task { await self?.refreshMe() } }
        CookieSync.shared.start()
        Task {
            await loadConfig()
            await refreshMe()
            #if DEBUG
            // Снимки экранов: запуск с -route /l/5 открывает нужный экран.
            if let r = UserDefaults.standard.string(forKey: "route"), !r.isEmpty { Nav.shared.open(path: r) }
            #endif
        }
        // Счётчики и «кто вошёл» — раз в 30 секунд, как у сайта.
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await refreshMe()
            }
        }
    }

    func loadConfig() async {
        if let c: AppConfig = try? await API.shared.get("/api/config") { config = c }
    }

    func refreshMe() async {
        guard let r: MeResponse = try? await API.shared.get("/api/me") else { return }
        me = r.user
        unread = r.unread ?? 0
        notices = r.notices ?? 0
        if city.isEmpty, let c = r.user?.city, !c.isEmpty { city = c }
        Badge.set(unread + notices)
    }

    func show(_ text: String, bad: Bool = false) {
        toast = Toast(text: text, bad: bad)
        if bad { Haptics.play("error") }
    }

    func isFav(_ id: Int, _ fallback: Bool?) -> Bool { favs[id] ?? fallback ?? false }

    /// Добавить в избранное или убрать. Гостю — предложение войти.
    func toggleFav(_ id: Int, current: Bool) async -> Bool {
        guard me != nil else { needLogin = true; return current }
        favs[id] = !current
        Haptics.play("light")
        do {
            let r: FavResult = try await API.shared.post("/api/favorites/\(id)", [String: String]())
            favs[id] = r.fav
            return r.fav
        } catch {
            favs[id] = current
            show((error as? APIError)?.message ?? "Не получилось", bad: true)
            return current
        }
    }

    /// Нужно войти — открывается экран входа.
    @Published var needLogin = false
}

enum Badge {
    static func set(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
    }
}
