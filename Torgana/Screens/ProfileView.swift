import SwiftUI

// Профиль (вариант B, 24.11): карточка с переходом цвета (аватарка, имя, уровень, цифры), четыре плитки — объявления,
// сообщения, сделки и отзывы, подписки; модерация — только администраторам; настройки и помощь — списками; «Выйти» — внизу.
// Каждый раздел — в одном месте: меню шапки ведёт сюда.
struct ProfileView: View {
    @AppStorage("theme") private var theme = ""   // подпись «Оформление» меняется сразу
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @StateObject private var store = MyListingsStore()
    @State private var admin: AdminStats?
    @State private var confirmLogout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let me = app.me {
                    hero(me).padding(.top, 12)
                    tiles(me).padding(.top, 14)
                    if me.isAdmin == true { moderation.padding(.top, 12) }
                    SettingsGroup {
                        SettingsRow(icon: "eye", color: Tint.blue, title: "Как меня видят покупатели", last: true) { nav.push(.user(me.id)) }
                    }
                    .padding(.top, 22)
                    SettingsGroup(title: "Настройки") {
                        SettingsRow(icon: "person.fill", color: Tint.blue, title: "Профиль", sub: "Фото, имя, город, телефон") { nav.push(.settings(.profile)) }
                        SettingsRow(icon: "bell.fill", color: Tint.red, title: "Уведомления", sub: "Push на этом iPhone и письма") { nav.push(.settings(.notify)) }
                        SettingsRow(icon: "lock.fill", color: Tint.sky, title: "Пароль и вход", sub: "Почта, Apple, Яндекс, VK") { nav.push(.web("/profile/settings#sp")) }
                        SettingsRow(icon: "moon.fill", color: Tint.indigo, title: "Оформление", sub: LookSettings.title) { nav.push(.settings(.look)) }
                        SettingsRow(icon: "nosign", color: Tint.gray, title: "Чёрный список", sub: "Кому нельзя вам писать") { nav.push(.settings(.blocks)) }
                        SettingsRow(icon: "briefcase.fill", color: Tint.orange, title: "Для бизнеса", sub: "Витрина и значок «ИП проверен»") { nav.push(.web("/profile/settings#s-biz")) }
                        SettingsRow(icon: "envelope.fill", color: Tint.violet, title: "Аккаунт", sub: me.email ?? "", last: true) { nav.push(.settings(.account)) }
                    }
                    .padding(.top, 22)
                    SettingsGroup(title: "Помощь") {
                        SettingsRow(icon: "headphones", color: Tint.green, title: "Поддержка", sub: "Отвечают люди, а не боты") { nav.push(.support) }
                        SettingsRow(icon: "questionmark", color: Tint.sky, title: "Помощь и безопасность") { nav.push(.web("/page/help")) }
                        SettingsRow(icon: "doc.text", color: Tint.gray, title: "Правила и документы", last: true) { nav.push(.doc("rules")) }
                    }
                    .padding(.top, 22)
                    Button { confirmLogout = true } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.on(16, .semibold)).foregroundStyle(T.danger)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(T.card))
                            .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)
                    Text("Торгана \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.on(12)).foregroundStyle(T.faint).frame(maxWidth: .infinity).padding(.top, 12)
                } else {
                    guest
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await app.refreshMe(); await reload() }
        .task(id: app.me?.id) { await reload() }
        .confirmationDialog("Выйти из профиля?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await app.logout() } }
        }
    }

    private func reload() async {
        guard let me = app.me else { return }
        await store.load()
        if me.isAdmin == true { admin = try? await API.shared.get("/api/admin/stats") }
    }

    private var guest: some View {
        VStack(spacing: 14) {
            Image("Logo").resizable().frame(width: 84, height: 84).clipShape(Circle()).padding(.top, 36)
            Text("Торгана. Сторгуемся!").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text("Войдите, чтобы размещать объявления, переписываться с продавцами и сохранять избранное.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Войти") { app.needLogin = true }.buttonStyle(TButton(kind: .dark)).padding(.top, 6)
            Button("Создать профиль") { app.needLogin = true }.buttonStyle(TButton(kind: .soft))
            SettingsGroup {
                SettingsRow(icon: "headphones", color: Tint.green, title: "Поддержка") { nav.push(.support) }
                SettingsRow(icon: "doc.text", color: Tint.gray, title: "Правила и документы", last: true) { nav.push(.doc("rules")) }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var active: Int { store.items.filter { $0.status == "active" }.count }

    // Карточка: фирменный переход цвета, скругление 26; аватарка 64 с камерой, шестерёнка — профиль; три цифры.
    private func hero(_ me: Me) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Button { nav.push(.settings(.profile)) } label: {
                    Avatar(name: me.name, url: me.avatar, size: 64)
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 3))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.accent)
                                .frame(width: 26, height: 26).background(Circle().fill(.white)).offset(x: 4, y: 4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(me.avatar == nil ? "Добавить фото профиля" : "Сменить фото профиля")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(me.name).font(.on(20, .heavy)).foregroundStyle(.white).lineLimit(1)
                        if me.badges?.official == true { Verified(size: 20) }
                    }
                    Text([me.city, "с \(Fmt.monthYear(me.createdAt))"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.on(13)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    if let lvl = me.rep?.levelName {
                        HStack(spacing: 6) {
                            LevelCoin(level: me.rep?.level ?? 0, size: 18)
                            Text(lvl).font(.on(12.5, .bold)).foregroundStyle(.white)
                        }
                        .padding(.leading, 4).padding(.trailing, 10).frame(height: 26)
                        .background(Capsule().fill(.white.opacity(0.18)))
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
                Button { nav.push(.settings(.profile)) } label: {
                    Image(systemName: "gearshape").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Профиль и фото")
            }
            HStack(spacing: 8) {
                num(active, Fmt.plural(active, "активное", "активных", "активных")) { nav.push(.myListings) }
                num(store.items.filter { $0.status == "sold" }.count, "продано") { nav.push(.myListings) }
                num(me.rep?.deals ?? 0, Fmt.plural(me.rep?.deals ?? 0, "сделка", "сделки", "сделок")) { nav.push(.web("/profile/reputation")) }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.grad))
    }

    private func num(_ n: Int, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(n)").font(.on(18, .heavy)).foregroundStyle(.white)
                Text(label).font(.on(12)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    // Четыре крупные плитки со счётчиками.
    private func tiles(_ me: Me) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("square.grid.2x2", Tint.blue, "Мои объявления", "\(active) \(Fmt.plural(active, "активное", "активных", "активных"))") { nav.push(.myListings) }
            tile("message", Tint.green, "Сообщения", app.unread > 0 ? "\(app.unread) \(Fmt.plural(app.unread, "новое", "новых", "новых"))" : "Переписки", badge: app.unread) { nav.open(path: "/messages") }
            tile("star", Tint.orange, "Сделки и отзывы", (me.rep?.deals ?? 0) > 0 ? "\(me.rep?.deals ?? 0) \(Fmt.plural(me.rep?.deals ?? 0, "сделка", "сделки", "сделок"))" : "Пока нет") { nav.push(.web("/profile/reputation")) }
            tile("person.2", Tint.violet, "Подписки", "Продавцы и новинки") { nav.push(.web("/profile/following")) }
        }
    }

    private func tile(_ icon: String, _ color: Color, _ title: String, _ sub: String, badge: Int = 0, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12)))
                    Spacer()
                    CountBadge(n: badge)
                }
                Spacer(minLength: 10)
                Text(title).font(.on(15.5, .bold)).foregroundStyle(T.text).lineLimit(1)
                Text(sub).font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // Модерация — только администраторам: что ждёт решения; открывается модерация сайта.
    private var moderation: some View {
        let a = admin
        let parts: [String] = [
            (a?.pending ?? 0) > 0 ? "\(a!.pending!) на проверке" : nil,
            (a?.reports ?? 0) > 0 ? "\(a!.reports!) \(Fmt.plural(a!.reports!, "жалоба", "жалобы", "жалоб"))" : nil,
            (a?.support ?? 0) > 0 ? "\(a!.support!) в поддержке" : nil,
            (a?.appeals ?? 0) > 0 ? "\(a!.appeals!) \(Fmt.plural(a!.appeals!, "обжалование", "обжалования", "обжалований"))" : nil
        ].compactMap { $0 }
        return Button { nav.push(.web("/admin")) } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.accentFill))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Модерация").font(.on(15.5, .bold)).foregroundStyle(T.text)
                    Text(a == nil ? "Загружаем…" : parts.isEmpty ? "Всё разобрано" : parts.joined(separator: " · "))
                        .font(.on(12.5)).foregroundStyle(T.muted).lineLimit(2)
                }
                Spacer(minLength: 6)
                if let t = a?.total, t > 0 {
                    Text("\(t)").font(.on(12, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24).background(Capsule().fill(T.danger))
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.accent, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// Мои объявления: загрузка и смена статуса — одно место для профиля и отдельной страницы.
@MainActor
final class MyListingsStore: ObservableObject {
    @Published var items: [MyListing] = []
    @Published var loading = true
    @Published var tab = "active"

    func load() async {
        if let r: MyListings = try? await API.shared.get("/api/my/listings") { items = r.items }
        loading = false
    }

    func count(_ t: String) -> Int { items.filter { Self.matches(t, $0.status) }.count }
    var shown: [MyListing] { items.filter { Self.matches(tab, $0.status) } }

    static func matches(_ tab: String, _ status: String?) -> Bool {
        switch tab {
        case "pending": return status == "pending" || status == "scheduled"
        case "archived": return status == "sold" || status == "archived"
        default: return status == tab
        }
    }

    func setStatus(_ l: MyListing, _ status: String) async {
        do {
            _ = try await API.shared.send("PATCH", "/api/listings/\(l.id)", body: ["status": status]) as JSONValue
            Haptics.play("success")
            AppState.shared.show(status == "sold" ? "Отмечено проданным" : status == "archived" ? "Снято с публикации" : "Снова опубликовано")
            await load()
        } catch { AppState.shared.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

/// Плашки статусов (выбранная — синяя) и карточки своих объявлений с меню «…».
struct MyListingsSection: View {
    @ObservedObject var store: MyListingsStore
    @EnvironmentObject private var nav: Nav

    private static let tabs = [("active", "Активные"), ("pending", "На проверке"), ("rejected", "На исправлении"), ("archived", "Архив")]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<Self.tabs.count, id: \.self) { i in
                        let t = Self.tabs[i]
                        let on = store.tab == t.0
                        Button { store.tab = t.0 } label: {
                            HStack(alignment: .top, spacing: 4) {
                                Text(t.1).font(.on(15, .medium))
                                if !on { Text("\(store.count(t.0))").font(.on(11, .semibold)).offset(y: -2) }
                            }
                            .foregroundStyle(on ? .white : T.text)
                            .padding(.horizontal, 20).frame(height: 48)
                            .background(Capsule().fill(on ? AnyShapeStyle(T.accentFill) : AnyShapeStyle(T.card)))
                            .overlay(Capsule().strokeBorder(on ? .clear : T.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
            if store.loading && store.items.isEmpty {
                LoadingView()
            } else if store.shown.isEmpty {
                EmptyState(icon: "square.grid.2x2", title: store.tab == "active" ? "Пока нет объявлений" : "Здесь пусто",
                           text: store.tab == "active" ? "Бесплатно и за пару минут." : "",
                           button: store.tab == "active" ? "Создать первое объявление" : nil) { nav.open(path: "/new") }
            } else {
                ForEach(store.shown) { l in MyCard(l: l, store: store) }
            }
        }
    }
}

// Своё объявление: фото 104, статус точкой, название 16/700, цена 17/800, просмотры и избранное, «…» с действиями.
struct MyCard: View {
    let l: MyListing
    @ObservedObject var store: MyListingsStore
    @EnvironmentObject private var nav: Nav

    var body: some View {
        Button { nav.push(.listing(l.id)) } label: {
            HStack(alignment: .top, spacing: 14) {
                RemoteImage(url: API.shared.media(l.photo)).frame(width: 104, height: 104).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                        Text(statusText).font(.on(12.5, .bold)).foregroundStyle(statusColor)
                    }
                    Text(l.title).font(.on(16, .bold)).foregroundStyle(T.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text(Fmt.price(l.price, unit: l.priceUnit)).font(.on(17, .heavy)).foregroundStyle(T.text)
                    if l.status == "rejected", let r = l.rejectReason, !r.isEmpty {
                        Text(r).font(.on(13)).foregroundStyle(T.danger).lineLimit(2)
                    } else {
                        HStack(spacing: 10) {
                            Label("\(l.views ?? 0)", systemImage: "eye")
                            Label("\(l.favCount ?? 0)", systemImage: "heart")
                            Text([l.city, Fmt.day(l.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).lineLimit(1)
                        }
                        .font(.on(13)).foregroundStyle(T.muted).labelStyle(TightLabel())
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button { nav.push(.edit(l.id)) } label: { Label("Редактировать", systemImage: "pencil") }
                    if l.status == "active" {
                        Button { Task { await store.setStatus(l, "sold") } } label: { Label("Продано", systemImage: "checkmark.circle") }
                        Button { Task { await store.setStatus(l, "archived") } } label: { Label("Снять с публикации", systemImage: "archivebox") }
                    } else if l.status == "sold" || l.status == "archived" {
                        Button { Task { await store.setStatus(l, "active") } } label: { Label("Опубликовать снова", systemImage: "arrow.uturn.up") }
                    }
                } label: { RoundIcon(icon: "ellipsis", size: 40) }
                .accessibilityLabel("Действия")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        switch l.status {
        case "active": return "Опубликовано"
        case "pending": return "На проверке"
        case "scheduled": return "Запланировано"
        case "rejected": return "Нужно исправить"
        case "sold": return "Продано"
        default: return "В архиве"
        }
    }

    private var statusColor: Color {
        switch l.status {
        case "active": return T.accent
        case "rejected": return T.danger
        case "sold": return T.good
        default: return T.muted
        }
    }
}

// Отдельная страница «Мои объявления» (из уведомлений и ссылок /profile/listings).
struct MyListingsView: View {
    @StateObject private var store = MyListingsStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Профиль")
                PageTitle(text: "Мои объявления", size: 30).padding(.top, 4)
                MyListingsSection(store: store).padding(.top, 18)
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await store.load() }
        .task { await store.load() }
    }
}

// Уведомления: решения модерации, снижение цен, новое у продавцов из подписок…
struct NoticesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [Notice] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink()
                PageTitle(text: "Уведомления", size: 30).padding(.top, 4)
                PushCard().padding(.top, 18)
                if loading && items.isEmpty {
                    LoadingView()
                } else if items.isEmpty {
                    EmptyState(title: "Уведомлений нет", text: "Здесь появятся решения модерации, снижение цен в избранном и новое у продавцов из подписок.").padding(.top, 16)
                } else {
                    VStack(spacing: 0) {
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
                                        Text(Fmt.dayTime(n.at)).font(.on(12)).foregroundStyle(T.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(n.read == true ? Color.clear : T.accentSoft.opacity(0.6)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.line, lineWidth: 1))
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
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

// Push на этом iPhone: включить, проверить, выключить. То же, что на странице настроек сайта (через PushManager).
struct PushCard: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var push = PushManager.shared
    @Environment(\.scenePhase) private var phase
    @State private var perm: PushManager.Permission = .granted
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: push.on ? "bell.badge.fill" : "bell.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(push.on ? .white : T.accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(push.on ? AnyShapeStyle(T.grad) : AnyShapeStyle(T.accentSoft)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(push.on ? "Push включены на этом iPhone" : perm == .denied ? "Уведомления запрещены" : "Push выключены")
                        .font(.on(16, .bold)).foregroundStyle(T.text)
                    Text(push.on ? "Сообщения, модерация, снижение цен и новое в подписках"
                         : perm == .denied ? "Разрешите их в Настройках iPhone → Торгана → Уведомления"
                         : "Сообщим о новых сообщениях, решениях модерации и снижении цен")
                        .font(.on(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if push.on {
                    Button("Проверить") { run("Отправили проверочное уведомление") { try await push.test() } }
                        .buttonStyle(TButton(kind: .soft, height: 42))
                    Button("Выключить") { run("Уведомления на этом iPhone выключены") { await push.turnOff() } }
                        .buttonStyle(TButton(kind: .line, height: 42))
                } else if perm == .denied {
                    Button("Открыть настройки") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                        .buttonStyle(TButton(kind: .accent, height: 42))
                } else {
                    Button { run("Уведомления включены") { try await push.turnOn() } } label: { Label("Включить уведомления", systemImage: "bell") }
                        .buttonStyle(TButton(kind: .accent, height: 42))
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.6 : 1)
        }
        .panel(radius: 24, padding: 16)
        .padding(.vertical, 4)
        .task { await reload() }
        .onChange(of: phase) { _, p in if p == .active { Task { await reload() } } }   // вернулись из Настроек iPhone
    }

    private func reload() async {
        perm = await push.permission()
        await push.refresh()
    }

    private func run(_ ok: String, _ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await work(); app.show(ok) } catch { app.show(error.localizedDescription, bad: true) }
            await reload()
            busy = false
        }
    }
}
