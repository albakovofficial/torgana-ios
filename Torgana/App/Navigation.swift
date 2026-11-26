import SwiftUI

// Экраны приложения. Адрес сайта (ссылка, push, «Поделиться») переводится в экран: свой, родной — или страница сайта,
// пока раздел не переписан на Swift.
enum Route: Hashable {
    case listing(Int)
    case search(SearchQuery)
    case chat(Int)
    case support
    case notices
    case edit(Int)
    case user(Int)
    case doc(String)
    case web(String)
    case settings(SettingsSection)
    case business(BizSection)

    /// /l/123-velosiped → .listing(123); /search?q=… и /c/… → поиск; остальное — страница сайта.
    static func from(path raw: String) -> Route? {
        guard let comps = URLComponents(string: raw) else { return nil }
        let path = comps.path.isEmpty ? "/" : comps.path
        let items = Dictionary((comps.queryItems ?? []).compactMap { q in q.value.map { (q.name, $0) } }, uniquingKeysWith: { a, _ in a })
        if let m = path.firstMatch(of: #/^\/l\/(\d+)/#), let id = Int(m.1) { return .listing(id) }
        if path == "/messages/support" { return .support }
        if let m = path.firstMatch(of: #/^\/edit\/(\d+)/#), let id = Int(m.1) { return .edit(id) }
        if let m = path.firstMatch(of: #/^\/u\/(\d+)/#), let id = Int(m.1) { return .user(id) }
        if let m = path.firstMatch(of: #/^\/page\/(rules|terms|privacy|consent|contacts)$/#) { return .doc(String(m.1)) }
        if let m = path.firstMatch(of: #/^\/messages\/(\d+)/#), let id = Int(m.1) { return .chat(id) }
        if path == "/search" { return .search(SearchQuery(params: items)) }
        if let m = path.firstMatch(of: #/^\/c\/([a-z]+)(?:\/([a-z0-9_-]+))?/#) {
            var q = SearchQuery(params: items)
            q.category = String(m.1)
            if let sub = m.2 { q.sub = String(sub) }
            return .search(q)
        }
        return nil
    }
}

enum Tab: Int, CaseIterable {
    case home, favorites, post, messages, profile

    /// Шторка входа, когда гость открывает вкладку.
    var loginAsk: AppState.LoginAsk {
        switch self {
        case .favorites: return .init(title: "Войдите, чтобы сохранять", text: "Отмечайте объявления сердечком — сообщим, когда подешевеют")
        case .post: return .init(title: "Войдите, чтобы продать", text: "Бесплатно и без лимитов — через пару минут объявление уйдёт на проверку")
        case .messages: return .init(title: "Войдите, чтобы переписываться", text: "Спрашивайте, торгуйтесь и договаривайтесь о встрече прямо здесь")
        default: return .init(title: "Войдите в Торгану", text: "Объявления, переписка и избранное — в одном профиле")
        }
    }
}

// Навигация: выбранная вкладка и стопка экранов в каждой.
@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var tab: Tab = .home
    @Published var paths: [Tab: [Route]] = [:]   // стопка экранов в каждой вкладке
    /// Экраны со своей нижней панелью (объявление) прячут нижнее меню.
    @Published var barHidden = 0
    /// Подача объявления во вкладке «+»: внизу своя панель «Назад / Далее».
    @Published var editorDock = false
    var barVisible: Bool { barHidden <= 0 && !(tab == .post && editorDock) }

    func path(_ tab: Tab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route) {
        // Своя страница продавца — это вкладка «Профиль» (витрина), отдельной нет.
        if case .user(let id) = route, id == AppState.shared.me?.id { tab = .profile; paths[.profile] = []; return }
        paths[tab, default: []].append(route)
    }

    /// С чистого листа: все вкладки — к началу, открыта главная (после выхода из профиля).
    func reset() { paths = [:]; tab = .home }

    /// Открыть адрес сайта: родной экран, если он есть, иначе — страницу сайта.
    func open(path: String) {
        let clean = path.hasPrefix("/") ? path : "/" + path
        switch clean.split(separator: "?").first.map(String.init) ?? clean {
        case "/": tab = .home; paths[.home] = []; return
        case "/favorites": tab = .favorites; paths[.favorites] = []; return
        case "/new": tab = .post; paths[.post] = []; return
        case "/profile": tab = .profile; paths[.profile] = []; return
        case "/profile/listings": tab = .profile; paths[.profile] = []; return   // свои объявления — первая вкладка профиля
        case "/profile/settings": tab = .profile; paths[.profile] = []; return   // настройки — в профиле
        default: break
        }
        // Разделы настроек сайта (#sf, #sn…) — родные экраны; «Пароль и вход» остаётся страницей сайта.
        if clean.hasPrefix("/profile/settings#"), let s = SettingsSection(hash: String(clean.split(separator: "#").last ?? "")) {
            tab = .profile; paths[.profile] = [Route.settings(s)]; return
        }
        // «Для бизнеса» — родные экраны: тарифы, «Мой магазин», витрина, статистика, проверка ИП (#s-biz).
        let biz: [String: BizSection] = ["/business": .hub, "/profile/business": .hub, "/profile/business/shop": .shop, "/profile/business/stats": .stats, "/profile/settings#s-biz": .trust]
        if let s = biz[clean.split(separator: "?").first.map(String.init) ?? clean] ?? biz[clean.replacingOccurrences(of: "#sh-about", with: "")] {
            tab = .profile; paths[.profile] = s == .hub ? [Route.business(.hub)] : [Route.business(.hub), Route.business(s)]; return
        }
        if clean.hasPrefix("/messages") {
            // Переписка — во вкладке «Сообщения», поверх списка.
            tab = .messages
            paths[.messages] = Route.from(path: clean).map { [$0] } ?? []
            return
        }
        if clean.hasPrefix("/profile") { tab = .profile; paths[.profile] = [Route.web(clean)]; return }
        push(Route.from(path: clean) ?? .web(clean))
    }

    func reselect(_ t: Tab) {
        // Гостю вне главной — шторка входа; после входа откроется выбранная вкладка.
        if t != .home && AppState.shared.me == nil {
            AppState.shared.requireLogin(t.loginAsk) { Nav.shared.tab = t }
            return
        }
        if tab == t {
            paths[t] = []
        } else { tab = t }
        Haptics.play("selection")
    }
}

// Главный экран: вкладки и нижнее меню как на сайте — «таблетка» с названием у открытого раздела и «+» посередине.
struct MainView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @ObservedObject private var push = PushManager.shared

    /// Вкладка гостю недоступна — на главную и шторка входа; после входа — открыть её.
    private func guestGuard() {
        let t = nav.tab
        guard app.meKnown, t != .home, app.me == nil else { return }
        nav.tab = .home
        app.requireLogin(t.loginAsk) { Nav.shared.tab = t }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                stack(.home) { HomeView() }
                stack(.favorites) { FavoritesView() }
                stack(.post) { EditorView() }
                stack(.messages) { MessagesView() }
                stack(.profile) { ProfileView() }
            }
            if nav.barVisible {
                TabBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: nav.barVisible)
        .modifier(ToastHost())
        .sheet(item: $app.ask, onDismiss: { app.loginClosed() }) { LoginSheet(ask: $0) }
        .sheet(isPresented: $app.accountsOpen) { AccountSheet() }
        .fullScreenCover(item: Binding(get: { app.loginFull.map(LoginFull.init) }, set: { app.loginFull = $0?.mode }),
                         onDismiss: { app.loginClosed() }) { f in NavigationStack { LoginView(start: f.mode) } }
        // Ссылка или push открыли раздел, а профиля нет — на главную и шторка входа.
        .onChange(of: nav.tab) { _, _ in guestGuard() }
        .onChange(of: app.meKnown) { _, _ in guestGuard() }
        // Один раз после входа, как на сайте; потом — системный запрос iPhone.
        .alert("Включить уведомления?", isPresented: $push.ask) {
            Button("Включить") {
                Task {
                    do { try await push.turnOn(); app.show("Уведомления включены") } catch { app.fail(error) }
                }
            }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Сообщим, когда объявление опубликуют, напишут в чате или подешевеет товар из избранного. Выключить можно в разделе «Уведомления» профиля.")
        }
    }

    private func stack<V: View>(_ tab: Tab, @ViewBuilder _ root: () -> V) -> some View {
        NavigationStack(path: nav.path(tab)) {
            root()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .tint(T.accent)
        .opacity(nav.tab == tab ? 1 : 0)
        .allowsHitTesting(nav.tab == tab)
    }
}

private struct LoginFull: Identifiable { let mode: LoginView.Mode; var id: String { "\(mode)" } }

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .listing(let id): ListingView(id: id)
        case .search(let q): SearchView(query: q)
        case .chat(let id): ChatView(kind: .conv(id))
        case .support: ChatView(kind: .support)
        case .notices: NoticesView()
        case .edit(let id): EditorView(editId: id).hidesTabBar()
        case .user(let id): UserView(id: id)
        case .doc(let slug): DocView(slug: slug)
        case .web(let path): WebScreen(path: path)
        case .settings(let s): SettingsScreen(section: s)
        case .business(let s): BusinessScreen(section: s)
        }
    }
}

/// Место под нижнее меню внизу прокрутки.
struct TabBarSpace: View {
    var body: some View { Color.clear.frame(height: 92) }
}

// Нижнее меню сайта (.bottom-nav): белая «таблетка» 64 с отступом 12, кнопки 46, у открытого раздела — подпись 14/650
// на синем 12 %, «+» — круг с переходом. Число непрочитанных — у «Сообщений» (уведомления — в колокольчике шапки).
struct TabBar: View {
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var app: AppState

    var body: some View {
        // Кнопки — своей ширины (открытая — с подписью), между ними поровну свободного места, как justify-content сайта.
        HStack(spacing: 0) {
            item(.home, "house", "Главная")
            Spacer(minLength: 2)
            item(.favorites, "heart", "Избранное")
            Spacer(minLength: 2)
            Button { nav.reselect(.post) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(T.grad))
                    .shadow(color: Color(hex: 0x5B5FD6).opacity(0.35), radius: 10, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подать объявление")
            Spacer(minLength: 2)
            item(.messages, "message", "Сообщения", badge: app.unread)
            Spacer(minLength: 2)
            item(.profile, "person", "Профиль")
                .contextMenu { if app.me != nil { AccountMenu() } }   // долгое нажатие — переключить аккаунт
        }
        .padding(.horizontal, 8)
        .frame(height: 64)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
        .shadow(color: Color(hex: 0x101010).opacity(0.12), radius: 18, y: 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func item(_ tab: Tab, _ icon: String, _ label: String, badge: Int = 0) -> some View {
        let on = nav.tab == tab
        return Button { nav.reselect(tab) } label: {
            HStack(spacing: 8) {
                Group {
                    // Вошли — вместо значка своя аватарка (видно, в каком аккаунте вы).
                    if tab == .profile, let me = app.me { Avatar(name: me.name, url: me.avatar, size: 26) }
                    else { Image(systemName: icon).font(.system(size: 20, weight: .regular)) }
                }
                .overlay(alignment: .topTrailing) { CountBadge(n: badge).offset(x: 11, y: -8) }
                if on { Text(label).font(.on(14, .semibold)).lineLimit(1).fixedSize() }
            }
            .foregroundStyle(on ? Color.dyn(0x2F53B5, 0x8EA9F7) : T.text)
            .padding(.leading, on ? 12 : 0).padding(.trailing, on ? 16 : 0)
            .frame(minWidth: 46, minHeight: 46)
            .background(Capsule().fill(on ? T.accentFill.opacity(0.12) : .clear))
            .fixedSize()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: on)
    }
}

/// Экран со своей нижней панелью прячет нижнее меню, пока он открыт.
struct HidesTabBar: ViewModifier {
    @EnvironmentObject private var nav: Nav
    func body(content: Content) -> some View {
        content
            .onAppear { nav.barHidden += 1 }
            .onDisappear { nav.barHidden -= 1 }
    }
}

extension View {
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}
