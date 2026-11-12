import SwiftUI

// Экраны приложения. Адрес сайта (ссылка, push, «Поделиться») переводится в экран: свой, родной — или страница сайта,
// пока раздел не переписан на Swift.
enum Route: Hashable {
    case listing(Int)
    case search(SearchQuery)
    case chat(Int)
    case support
    case myListings
    case notices
    case edit(Int)
    case user(Int)
    case doc(String)
    case web(String)

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

enum Tab: Int, CaseIterable { case home, favorites, post, messages, profile }

// Навигация: выбранная вкладка и стопка экранов в каждой.
@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var tab: Tab = .home
    @Published var paths: [Tab: NavigationPath] = [:]
    /// Экраны со своей нижней панелью (объявление) прячут нижнее меню.
    @Published var barHidden = 0
    var barVisible: Bool { barHidden <= 0 }

    func path(_ tab: Tab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route) {
        var p = paths[tab] ?? NavigationPath()
        p.append(route)
        paths[tab] = p
    }

    /// Открыть адрес сайта: родной экран, если он есть, иначе — страницу сайта.
    func open(path: String) {
        let clean = path.hasPrefix("/") ? path : "/" + path
        switch clean.split(separator: "?").first.map(String.init) ?? clean {
        case "/": tab = .home; paths[.home] = NavigationPath(); return
        case "/favorites": tab = .favorites; paths[.favorites] = NavigationPath(); return
        case "/new": tab = .post; paths[.post] = NavigationPath(); return
        case "/profile": tab = .profile; paths[.profile] = NavigationPath(); return
        case "/profile/listings": tab = .profile; paths[.profile] = NavigationPath([Route.myListings]); return
        default: break
        }
        if clean.hasPrefix("/messages") {
            // Переписка — во вкладке «Сообщения», поверх списка.
            tab = .messages
            var p = NavigationPath()
            if let r = Route.from(path: clean) { p.append(r) }
            paths[.messages] = p
            return
        }
        if clean.hasPrefix("/profile") { tab = .profile; paths[.profile] = NavigationPath([Route.web(clean)]); return }
        push(Route.from(path: clean) ?? .web(clean))
    }

    func reselect(_ t: Tab) {
        if tab == t {
            paths[t] = NavigationPath()
        } else { tab = t }
        Haptics.play("selection")
    }
}

// Главный экран: вкладки и нижнее меню как на сайте — «таблетка» с названием у открытого раздела и «+» посередине.
struct MainView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @ObservedObject private var push = PushManager.shared

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
        .sheet(isPresented: $app.needLogin) {
            NavigationStack { LoginView() }
        }
        // Один раз после входа, как на сайте; потом — системный запрос iPhone.
        .alert("Включить уведомления?", isPresented: $push.ask) {
            Button("Включить") {
                Task {
                    do { try await push.turnOn(); app.show("Уведомления включены") } catch { app.show(error.localizedDescription, bad: true) }
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

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .listing(let id): ListingView(id: id)
        case .search(let q): SearchView(query: q)
        case .chat(let id): ChatView(kind: .conv(id))
        case .support: ChatView(kind: .support)
        case .myListings: MyListingsView()
        case .notices: NoticesView()
        case .edit(let id): EditorView(editId: id).hidesTabBar()
        case .user(let id): UserView(id: id)
        case .doc(let slug): DocView(slug: slug)
        case .web(let path): WebScreen(path: path)
        }
    }
}

/// Место под нижнее меню внизу прокрутки.
struct TabBarSpace: View {
    var body: some View { Color.clear.frame(height: 96) }
}

struct TabBar: View {
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "house", "house.fill", "Главная")
            item(.favorites, "heart", "heart.fill", "Избранное")
            Button { nav.reselect(.post) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(T.grad))
                    .shadow(color: Color(hex: 0x3D67D0).opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Подать объявление")
            item(.messages, "message", "message.fill", "Сообщения", badge: app.unread)
            item(.profile, "person", "person.fill", "Профиль", badge: app.notices)
        }
        .padding(.horizontal, 8)
        .frame(height: 70)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func item(_ tab: Tab, _ icon: String, _ iconOn: String, _ label: String, badge: Int = 0) -> some View {
        let on = nav.tab == tab
        return Button { nav.reselect(tab) } label: {
            HStack(spacing: 7) {
                Image(systemName: on ? iconOn : icon)
                    .font(.system(size: 20, weight: on ? .semibold : .regular))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.on(11, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Color(hex: 0xE5484D)))
                                .overlay(Capsule().strokeBorder(T.card, lineWidth: 2))
                                .offset(x: 10, y: -8)
                        }
                    }
                if on { Text(label).font(.on(15, .semibold)).lineLimit(1).fixedSize() }
            }
            .foregroundStyle(on ? T.accent : T.muted)
            .padding(.horizontal, on ? 16 : 0)
            .frame(height: 50)
            .background(Capsule().fill(on ? T.accentSoft : .clear))
            .frame(maxWidth: on ? nil : .infinity)
            .contentShape(Rectangle())
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
