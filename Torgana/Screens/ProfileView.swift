import SwiftUI

// Профиль — как «Мой профиль» сайта на телефоне: карточка (аватарка с камерой, имя, город, уровень, медаль, настройки),
// цифры, «Профиль заполнен», плитки разделов и «Мои объявления» по статусам прямо здесь.
struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @StateObject private var store = MyListingsStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let me = app.me {
                    card(me).padding(.top, 12)
                    tiles.padding(.top, 14)
                    Text("Мои объявления").font(.on(28, .heavy)).foregroundStyle(T.text).padding(.top, 30)
                    MyListingsSection(store: store).padding(.top, 16)
                } else {
                    guest
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await app.refreshMe(); await store.load() }
        .task(id: app.me?.id) { if app.me != nil { await store.load() } }
    }

    private var guest: some View {
        VStack(spacing: 14) {
            Image("Logo").resizable().frame(width: 84, height: 84).clipShape(Circle()).padding(.top, 36)
            Text("Торгана. Сторгуемся!").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text("Войдите, чтобы размещать объявления, переписываться с продавцами и сохранять избранное.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Войти") { app.needLogin = true }.buttonStyle(TButton(kind: .dark)).padding(.top, 6)
            Button("Создать профиль") { app.needLogin = true }.buttonStyle(TButton(kind: .soft))
        }
        .frame(maxWidth: .infinity)
    }

    // .pf-card: --surface, скругление 28, внутри 20.
    private func card(_ me: Me) -> some View {
        let todo = todoItems(me)
        let pct = Int((Double(3 - todo.count) / 3 * 100).rounded())
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Avatar(name: me.name, url: me.avatar, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        Button { nav.push(.web("/profile/settings")) } label: {
                            Image(systemName: "camera").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.text)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(T.card))
                                .overlay(Circle().strokeBorder(T.surface, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: 6)
                        .accessibilityLabel(me.avatar == nil ? "Добавить фото профиля" : "Сменить фото профиля")
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(me.name).font(.on(18, .bold)).foregroundStyle(T.text).lineLimit(2)
                        if me.badges?.official == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(T.accent) }
                    }
                    Text([me.city, "на Торгане с \(Fmt.monthYear(me.createdAt))"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.on(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                    RepLine(rep: me.rep, medal: me.badges?.first).padding(.top, 2)
                }
                Spacer(minLength: 0)
                Button { nav.push(.web("/profile/settings")) } label: { RoundIcon(icon: "gearshape", fill: T.card) }
                    .buttonStyle(.plain).accessibilityLabel("Настройки")
            }
            HStack(spacing: 8) {
                stat(store.items.filter { $0.status == "active" }.count, store.items.filter { $0.status == "active" }.count == 1 ? "активное" : "активных")
                stat(store.items.filter { $0.status == "sold" }.count, "продано")
            }
            if !todo.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Профиль заполнен").font(.on(13, .semibold)).foregroundStyle(T.text)
                        Spacer()
                        Text("\(pct)%").font(.on(13, .heavy)).foregroundStyle(T.accent)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(T.line)
                            Capsule().fill(T.accentFill).frame(width: g.size.width * CGFloat(pct) / 100)
                        }
                    }
                    .frame(height: 8)
                    .padding(.top, 9)
                    ForEach(Array(todo.enumerated()), id: \.offset) { _, t in
                        Button { nav.push(.web("/profile/settings")) } label: {
                            HStack(spacing: 10) {
                                Circle().strokeBorder(T.faint, style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 18, height: 18)
                                Text(t.0).font(.on(14)).foregroundStyle(T.text)
                                Spacer()
                                Text(t.1).font(.on(13.5, .bold)).foregroundStyle(T.accent)
                            }
                            .frame(height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.surface))
    }

    /// Что ещё заполнить — как profileTodo сайта (без витрины магазина): фото и город.
    private func todoItems(_ me: Me) -> [(String, String)] {
        var t: [(String, String)] = []
        if (me.avatar ?? "").isEmpty { t.append(("Фото профиля", "Добавить")) }
        if (me.city ?? "").isEmpty { t.append(("Город", "Указать")) }
        return t
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        Button { nav.push(.myListings) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(n)").font(.on(21, .heavy)).foregroundStyle(T.text)
                Text(label).font(.on(12)).foregroundStyle(T.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
        }
        .buttonStyle(.plain)
    }

    // Плитки разделов: белые, обводка, скругление 18, высота 56, 15/600.
    private var tiles: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            tile("message", "Сообщения") { nav.open(path: "/messages") }
            tile("heart", "Избранное") { nav.open(path: "/favorites") }
            tile("person.2", "Подписки") { nav.push(.web("/profile/following")) }
            tile("star", "Репутация") { nav.push(.web("/profile/reputation")) }
        }
    }

    private func tile(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular)).foregroundStyle(T.accent).frame(width: 22)
                Text(title).font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(T.line, lineWidth: 1))
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
