import Foundation

// Несколько аккаунтов на одном iPhone (решение 26.11: шторка из профиля + долгое нажатие на вкладку «Профиль»).
// Сессия каждого вошедшего аккаунта хранится в Связке ключей; переключение — без пароля: его сессия становится
// текущей (родные экраны, страницы сайта). «Добавить аккаунт» не выходит из текущего на сервере — к нему можно
// вернуться. Непрочитанные у остальных — запросом /api/me с их сессией, не трогая текущую.
@MainActor
final class Accounts: ObservableObject {
    static let shared = Accounts()

    struct Saved: Codable, Identifiable, Hashable {
        let id: Int
        var name: String
        var avatar: String?
        var email: String?
        var verified: Bool?
        var sid: String
        var exp: Double
        /// Сервер больше не узнаёт сессию — нужно войти снова.
        var expired: Bool?
    }

    @Published private(set) var list: [Saved] = []
    /// Непрочитанные сообщения и уведомления остальных аккаунтов.
    @Published private(set) var unread: [Int: Int] = [:]
    /// Пока добавляют аккаунт — в какой вернуться, если вход закрыли.
    private(set) var addingFrom: Int?

    private init() {
        list = Keychain.read("accounts").flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
    }

    private func save() {
        if let d = try? JSONEncoder().encode(list) { Keychain.write("accounts", d) }
    }

    var others: [Saved] { list.filter { $0.id != AppState.shared.me?.id } }

    /// Профиль загрузился — запомнить аккаунт и его текущую (возможно, продлённую) сессию.
    func remember(_ me: Me) {
        guard let c = CookieSync.shared.current else { return }
        let a = Saved(id: me.id, name: me.name, avatar: me.avatar, email: me.email,
                      verified: me.badges?.official == true || me.badges?.shop == true || me.badges?.tm != nil, sid: c.value, exp: c.expires)
        if let i = list.firstIndex(where: { $0.id == me.id }) {
            if list[i] != a { list[i] = a; save() }
        } else {
            list.append(a)
            save()
        }
        addingFrom = nil
    }

    /// Убрать из списка (вышли из аккаунта).
    func forget(_ id: Int) {
        list.removeAll { $0.id == id }
        unread[id] = nil
        save()
    }

    /// Переключиться: сессия аккаунта — текущая. Не узнал сервер — вернуться в прежний и попросить войти снова.
    func switchTo(_ a: Saved) async {
        let app = AppState.shared
        guard a.id != app.me?.id else { return }
        if a.expired == true { await startAdding(); return }
        let from = app.me.flatMap { m in list.first { $0.id == m.id } }
        await use(a)
        if app.me?.id == a.id {
            Nav.shared.paths = [:]
            Haptics.play("success")
            app.show("Вы в аккаунте «\(a.name)»")
        } else {
            mark(a.id, expired: true)
            if let from { await use(from) }
            app.show("Вход в «\(a.name)» истёк — войдите снова", bad: true)
        }
        await refreshUnread()
    }

    private func use(_ a: Saved) async {
        await CookieSync.shared.use(a.sid, expires: a.exp)
        AppState.shared.favs = [:]
        await AppState.shared.refreshMe()
    }

    /// «Добавить аккаунт»: текущий остаётся на сервере и в списке, на iPhone — окно входа.
    func startAdding() async {
        let app = AppState.shared
        addingFrom = app.me?.id
        await CookieSync.shared.drop()
        app.favs = [:]
        await app.refreshMe()
        app.ask = AppState.LoginAsk(title: "Добавить аккаунт", text: "Войдите в другой профиль — переключаться можно одним касанием")
    }

    /// Окно входа закрыли, не войдя, — вернуться в прежний аккаунт.
    func cancelAdding() async {
        guard let id = addingFrom, let a = list.first(where: { $0.id == id }) else { addingFrom = nil; return }
        addingFrom = nil
        await use(a)
    }

    private func mark(_ id: Int, expired: Bool) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].expired = expired
        save()
    }

    /// Непрочитанные остальных аккаунтов; продлённую сервером сессию — запомнить, неузнанную — отметить.
    func refreshUnread() async {
        struct R: Decodable { let user: Me?; let unread: Int?; let notices: Int? }
        for a in others where a.expired != true {
            var req = URLRequest(url: API.shared.url("/api/me"))
            req.setValue("tg_sid=\(a.sid)", forHTTPHeaderField: "Cookie")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("TorganaApp/\(WebController.appVersion) (iOS; native)", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await Self.session.data(for: req), let r = try? JSONDecoder().decode(R.self, from: data) else { continue }
            if r.user == nil { mark(a.id, expired: true); continue }
            unread[a.id] = (r.unread ?? 0) + (r.notices ?? 0)
            if let h = resp as? HTTPURLResponse, let url = h.url,
               let c = HTTPCookie.cookies(withResponseHeaderFields: h.allHeaderFields as? [String: String] ?? [:], for: url).first(where: { $0.name == "tg_sid" }),
               let i = list.firstIndex(where: { $0.id == a.id }) {
                list[i].sid = c.value
                list[i].exp = c.expiresDate?.timeIntervalSince1970 ?? list[i].exp
                save()
            }
        }
    }

    #if DEBUG
    /// Снимок «/accounts»: ещё два аккаунта рядом с демо-профилем.
    func seedDemo() {
        guard list.count < 2 else { return }
        if let me = AppState.shared.me, !list.contains(where: { $0.id == me.id }) {
            list.append(Saved(id: me.id, name: me.name, avatar: me.avatar, email: me.email, verified: false, sid: "demo", exp: Date().timeIntervalSince1970 + 86400))
        }
        list += [Saved(id: 90, name: "ALBAKOV", avatar: nil, email: "shop@albakov.ru", verified: true, sid: "demo", exp: Date().timeIntervalSince1970 + 86400),
                 Saved(id: 91, name: "Мария", avatar: nil, email: "maria@mail.ru", verified: false, sid: "demo", exp: Date().timeIntervalSince1970 + 86400, expired: true)]
        unread[90] = 3
    }
    #endif

    /// Запросы за другие аккаунты — без общих кук, чтобы не задеть текущую сессию.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()
}
