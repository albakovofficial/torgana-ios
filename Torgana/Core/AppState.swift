import SwiftUI
import UserNotifications

// Общее состояние приложения: кто вошёл, справочники (категории, города), счётчики, избранное.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var me: Me?
    /// Сервер уже ответил, кто вошёл: до этого вкладки гостя не закрываем (ссылка при запуске открывается раньше профиля).
    @Published var meKnown = false
    @Published var config: AppConfig?
    @Published var unread = 0
    @Published var notices = 0
    @Published var city: String = UserDefaults.standard.string(forKey: "city") ?? "" {
        didSet { UserDefaults.standard.set(city, forKey: "city") }
    }
    /// Избранное, изменённое на этом экране: id → в избранном ли. Карточки в других списках сразу видят изменение.
    @Published var favs: [Int: Bool] = [:]
    /// Шторка входа для гостя (нажал «Написать», «♡», вкладку «Профиль»…) и полный экран входа или регистрации.
    struct LoginAsk: Identifiable { let id = UUID(); let title: String; let text: String }
    @Published var ask: LoginAsk?
    @Published var loginFull: LoginView.Mode?
    /// Шторка закрывается, чтобы открыть полный экран входа, — начатое действие не забываем.
    var keepPending = false
    /// Что сделать сразу после входа (открыть вкладку, написать продавцу, добавить в избранное).
    private var pending: (@MainActor () async -> Void)?
    @Published var toast: Toast?

    struct Toast: Equatable { let text: String; let bad: Bool; let id = UUID() }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        // Вошли или вышли (на странице сайта или в родном экране) — обновляем профиль.
        CookieSync.shared.onChange = { [weak self] in Task { await self?.refreshMe() } }
        CookieSync.shared.start()
        #if DEBUG
        // Снимки экранов: запуск с -route /l/5 сразу открывает нужный экран (данные он грузит сам).
        if let r = UserDefaults.standard.string(forKey: "route"), !r.isEmpty {
            if r == "/login" || r == "/register" || r == "/ask" {
                // окно входа — когда профиль уже загружен (иначе его загрузка закроет окно)
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if r == "/ask" { ask = Tab.profile.loginAsk } else { loginFull = r == "/login" ? .login : .register }
                }
            } else { Nav.shared.open(path: r) }
        }
        #endif
        Task {
            await loadConfig()
            await refreshMe()
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
        guard let r: MeResponse = try? await API.shared.get("/api/me") else { return }   // нет сети — профиль не трогаем
        if r.user == nil && CookieSync.shared.hasSession {
            // Сервер не узнал сессию (вышли на сайте, удалили профиль, истёк срок) — только тогда она стирается.
            await withCheckedContinuation { c in CookieSync.shared.drop { c.resume() } }
        } else {
            CookieSync.shared.remember()
        }
        let changed = me?.id != r.user?.id
        me = r.user
        meKnown = true
        if changed && r.user == nil { Nav.shared.reset() }   // вышли — с главной, гостем
        if changed && r.user != nil, let then = pending { pending = nil; Task { await then() } }
        if changed { Task { await PushManager.shared.sync(); await PushManager.shared.askOnce() } }
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

    /// Гостю — шторка входа; после входа выполнится then.
    func requireLogin(_ ask: LoginAsk, then: (@MainActor () async -> Void)? = nil) {
        pending = then
        self.ask = ask
    }

    /// Шторку или экран входа закрыли, не войдя, — начатое действие отменяется.
    func loginClosed() {
        if me == nil && !keepPending { pending = nil }
        keepPending = false
    }

    /// Добавить в избранное или убрать. Гостю — шторка входа, после входа — добавить.
    func toggleFav(_ id: Int, current: Bool) async -> Bool {
        guard me != nil else {
            requireLogin(LoginAsk(title: "Войдите, чтобы сохранить", text: "Отмечайте объявления сердечком — сообщим, когда подешевеют")) { [weak self] in
                _ = await self?.toggleFav(id, current: current)
            }
            return current
        }
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

    /// Переписка о объявлении (создаётся или находится) и, если задано, предложение цены; затем — открыть чат.
    /// Гостю — вход. Ошибка — всплывающим сообщением.
    func openChat(listingId: Int, offer: Int? = nil) async {
        guard me != nil else {
            requireLogin(LoginAsk(title: "Войдите, чтобы написать", text: "Продавец ответит вам в сообщениях")) { [weak self] in
                await self?.openChat(listingId: listingId, offer: offer)
            }
            return
        }
        do {
            let r: IdResult = try await API.shared.post("/api/conversations", ["listingId": listingId])
            if let offer {
                _ = try await API.shared.post("/api/conversations/\(r.id)/offer", ["price": offer], as: JSONValue.self)
                show("Предложение отправлено — ответ придёт в чат")
            }
            Nav.shared.push(.chat(r.id))
        } catch {
            show((error as? APIError)?.message ?? "Не получилось", bad: true)
        }
    }

    /// Подписаться на продавца или отписаться. nil — не получилось (сообщение уже показано).
    func follow(_ userId: Int, _ on: Bool) async -> FollowResult? {
        guard me != nil else {
            requireLogin(LoginAsk(title: "Войдите, чтобы подписаться", text: "Новые объявления продавца придут в уведомления")) { [weak self] in
                _ = await self?.follow(userId, on)
            }
            return nil
        }
        do {
            let r: FollowResult = try await API.shared.post("/api/users/\(userId)/follow", ["follow": on])
            Haptics.play("light")
            return r
        } catch {
            show((error as? APIError)?.message ?? "Не получилось", bad: true)
            return nil
        }
    }

    /// Выйти: push на этот iPhone больше не слать, сессию закрыть на сервере и в страницах сайта.
    func logout() async {
        await PushManager.shared.forget()
        _ = try? await API.shared.post("/api/auth/logout")
        favs = [:]
        await withCheckedContinuation { c in CookieSync.shared.drop { c.resume() } }
        await refreshMe()
    }

    /// Нужно войти — открывается экран входа.
}

enum Badge {
    static func set(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, n)) { _ in }
    }
}
