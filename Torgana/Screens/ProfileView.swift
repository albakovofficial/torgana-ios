import SwiftUI

// Профиль: карточка человека, мои объявления, уведомления, настройки и помощь.
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var mine: [MyListing] = []
    @State private var confirmLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let me = app.me {
                    card(me)
                    tiles
                    menu
                } else {
                    guest
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            TabBarSpace()
        }
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await app.refreshMe(); await loadMine() }
        .task(id: app.me?.id) { await loadMine() }
        .confirmationDialog("Выйти из профиля?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await logout() } }
        }
    }

    private var guest: some View {
        VStack(spacing: 18) {
            Image("Logo").resizable().frame(width: 84, height: 84).clipShape(Circle()).padding(.top, 40)
            Text("Торгана. Сторгуемся!").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text("Войдите, чтобы размещать объявления, переписываться с продавцами и сохранять избранное.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Войти") { app.needLogin = true }.buttonStyle(TButton(kind: .dark))
            Button("Создать профиль") { app.needLogin = true }.buttonStyle(TButton(kind: .soft))
            VStack(spacing: 0) {
                row("questionmark.circle", "Помощь") { nav.push(.web("/page/help")) }
                row("doc.text", "Правила и документы") { nav.push(.web("/page/rules")) }
            }
            .panel(radius: 24, padding: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ me: Me) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(name: me.name, url: me.avatar, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(me.name).font(.on(22, .heavy)).foregroundStyle(T.text).lineLimit(2)
                        if me.badges?.official == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(T.accent) }
                    }
                    Text([me.city, me.createdAt.map { "на Торгане с \(Fmt.monthYear($0))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.on(14)).foregroundStyle(T.muted)
                    if let lvl = me.rep?.levelName { Text(lvl).font(.on(14, .semibold)).foregroundStyle(T.accent) }
                }
                Spacer(minLength: 0)
            }
            if let no = me.badges?.first?.no {
                Label("Медаль «\(me.badges?.first?.form == "f" ? "Одна из первых" : "Один из первых")» · № \(no)", systemImage: "rosette")
                    .font(.on(14, .semibold)).foregroundStyle(T.accent)
                    .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.accentSoft))
            }
            HStack(spacing: 10) {
                stat(mine.filter { $0.status == "active" }.count, "активных")
                stat(mine.filter { $0.status == "sold" }.count, "продано")
            }
        }
        .panel()
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text(label).font(.on(14)).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("square.grid.2x2", "Мои объявления", "\(mine.count)", .myListings)
            tile("bell", "Уведомления", app.notices > 0 ? "\(app.notices) новых" : "Все прочитаны", .notices)
        }
    }

    private func tile(_ icon: String, _ title: String, _ sub: String, _ route: Route) -> some View {
        Button { nav.push(route) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.grad))
                Text(title).font(.on(16, .bold)).foregroundStyle(T.text)
                Text(sub).font(.on(13)).foregroundStyle(T.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.gradSoft))
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            row("star", "Отзывы и репутация") { nav.push(.web("/profile/reputation")) }
            row("person.2", "Подписки") { nav.push(.web("/profile/following")) }
            row("magnifyingglass", "Сохранённые поиски") { nav.push(.web("/profile/searches")) }
            row("gearshape", "Настройки") { nav.push(.web("/profile/settings")) }
            row("headphones", "Поддержка") { nav.push(.support) }
            row("questionmark.circle", "Помощь") { nav.push(.web("/page/help")) }
            row("rectangle.portrait.and.arrow.right", "Выйти", danger: true) { confirmLogout = true }
        }
        .panel(radius: 24, padding: 6)
    }

    private func row(_ icon: String, _ title: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).frame(width: 26).foregroundStyle(danger ? T.danger : T.accent)
                Text(title).font(.on(16, .medium)).foregroundStyle(danger ? T.danger : T.text)
                Spacer()
                if !danger { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint) }
            }
            .padding(.horizontal, 14).frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadMine() async {
        guard app.me != nil else { mine = []; return }
        if let r: MyListings = try? await API.shared.get("/api/my/listings") { mine = r.items }
    }

    private func logout() async {
        _ = try? await API.shared.post("/api/auth/logout")
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.name == "tg_sid" { HTTPCookieStorage.shared.deleteCookie(c) }
        CookieSync.shared.pushToWeb { Task { await app.refreshMe() } }
        app.favs = [:]
    }
}

// Мои объявления по статусам: продано, снять, вернуть, редактировать.
struct MyListingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [MyListing] = []
    @State private var loading = true
    @State private var tab = "active"

    private static let tabs = [("active", "Активные"), ("pending", "На проверке"), ("rejected", "Исправить"), ("archived", "Архив")]

    var body: some View {
        List {
            Picker("", selection: $tab) {
                ForEach(0..<MyListingsView.tabs.count, id: \.self) { i in Text(MyListingsView.tabs[i].1).tag(MyListingsView.tabs[i].0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden).listRowBackground(T.bg)
            if loading && items.isEmpty {
                LoadingView().listRowSeparator(.hidden).listRowBackground(T.bg)
            } else if shown.isEmpty {
                EmptyState(icon: "tray", title: "Здесь пусто", text: tab == "active" ? "Подайте объявление — это бесплатно." : "")
                    .listRowSeparator(.hidden).listRowBackground(T.bg)
            }
            ForEach(shown) { l in
                Button { nav.push(.listing(l.id)) } label: { MyRow(l: l) }
                    .buttonStyle(.plain)
                    .listRowBackground(T.bg)
                    .swipeActions(edge: .trailing) {
                        if l.status == "active" {
                            Button("Продано") { Task { await setStatus(l, "sold") } }.tint(T.good)
                            Button("Снять") { Task { await setStatus(l, "archived") } }.tint(.gray)
                        } else if l.status == "sold" || l.status == "archived" {
                            Button("Вернуть") { Task { await setStatus(l, "active") } }.tint(T.accentFill)
                        }
                    }
                    .contextMenu {
                        Button { nav.push(.edit(l.id)) } label: { Label("Редактировать", systemImage: "pencil") }
                        if l.status == "active" {
                            Button { Task { await setStatus(l, "sold") } } label: { Label("Продано", systemImage: "checkmark.circle") }
                            Button { Task { await setStatus(l, "archived") } } label: { Label("Снять с публикации", systemImage: "archivebox") }
                        }
                    }
            }
            TabBarSpace().listRowSeparator(.hidden).listRowBackground(T.bg)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(T.bg)
        .navigationTitle("Мои объявления")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var shown: [MyListing] {
        items.filter { l in
            switch tab {
            case "pending": return l.status == "pending" || l.status == "scheduled"
            case "archived": return l.status == "sold" || l.status == "archived"
            default: return l.status == tab
            }
        }
    }

    private func load() async {
        if let r: MyListings = try? await API.shared.get("/api/my/listings") { items = r.items }
        loading = false
    }

    private func setStatus(_ l: MyListing, _ status: String) async {
        do {
            _ = try await API.shared.send("PATCH", "/api/listings/\(l.id)", body: ["status": status]) as JSONValue
            Haptics.play("success")
            app.show(status == "sold" ? "Отмечено проданным" : status == "archived" ? "Снято с публикации" : "Снова опубликовано")
            await load()
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

struct MyRow: View {
    let l: MyListing
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: API.shared.media(l.photo)).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(l.title).font(.on(16, .semibold)).foregroundStyle(T.text).lineLimit(2)
                Text(Fmt.price(l.price, unit: l.priceUnit)).font(.on(15, .bold)).foregroundStyle(T.text)
                if l.status == "rejected", let r = l.rejectReason, !r.isEmpty {
                    Text(r).font(.on(13)).foregroundStyle(T.danger).lineLimit(2)
                } else {
                    Label("\(l.views ?? 0)  ·  ♥ \(l.favCount ?? 0)", systemImage: "eye").font(.on(13)).foregroundStyle(T.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// Уведомления: решения модерации, снижение цен, новое у продавцов из подписок…
struct NoticesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [Notice] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading && items.isEmpty { LoadingView().listRowSeparator(.hidden).listRowBackground(T.bg) }
            else if items.isEmpty { EmptyState(icon: "bell", title: "Уведомлений нет", text: "Здесь появятся решения модерации, снижение цен в избранном и новое у продавцов из подписок.").listRowSeparator(.hidden).listRowBackground(T.bg) }
            ForEach(items) { n in
                Button { if let u = n.url, !u.isEmpty { nav.open(path: u) } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(n))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(n.tone == "bad" ? T.danger : n.tone == "ok" ? T.good : T.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(n.tone == "bad" ? T.dangerSoft : n.tone == "ok" ? T.goodSoft : T.accentSoft))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(n.title).font(.on(15, n.read == true ? .medium : .bold)).foregroundStyle(T.text)
                            if let b = n.body, !b.isEmpty { Text(b).font(.on(14)).foregroundStyle(T.text2) }
                            Text(Fmt.dayTime(n.at)).font(.on(12)).foregroundStyle(T.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(n.read == true ? T.bg : T.accentSoft.opacity(0.5))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(T.bg)
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            await load()
            // Открыли список — всё прочитано.
            _ = try? await API.shared.post("/api/notices/read", [String: Int](), as: JSONValue.self)
            await app.refreshMe()
        }
    }

    private func icon(_ n: Notice) -> String {
        switch n.icon {
        case "check": return "checkmark"
        case "warn": return "exclamationmark.triangle"
        case "medal": return "rosette"
        case "price", "tag": return "tag"
        case "clock": return "clock"
        case "star": return "star"
        case "user", "follow": return "person"
        default: return "bell"
        }
    }

    private func load() async {
        if let r: NoticeList = try? await API.shared.get("/api/notices") { items = r.items }
        loading = false
    }
}
