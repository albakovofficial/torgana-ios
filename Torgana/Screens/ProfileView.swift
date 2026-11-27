import SwiftUI

// Профиль = ваша витрина (решение 25.11, «вариант 2»): сверху та же карточка, что видят покупатели (SellerCard), —
// с «Изменить профиль» и «Поделиться»; под ней вкладки «Объявления» (свои, со статусами), «Репутация» и «Ещё»
// (сообщения, сделки, подписки, модерация, настройки, помощь, «Выйти»). Отдельной «Как меня видят покупатели» нет.
struct ProfileView: View {
    @AppStorage("theme") private var theme = ""   // подпись «Оформление» меняется сразу
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @StateObject private var store = MyListingsStore()
    @State private var pub: PublicUser?
    @State private var tab = "ads"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let me = app.me {
                    if let u = pub {
                        SellerCard(user: u, count: active, own: true) { ownActions(u) }.padding(.top, 12)
                    } else {
                        LoadingView()
                    }
                    // 1.66.0: только «Объявления» и «Репутация»; всё из бывшего «Ещё» — в меню ≡ (SiteMenu, вариант A «Плитки»).
                    Seg(items: [("ads", "Объявления"), ("rep", "Репутация")], value: $tab,
                        level: ("rep", pub?.rep?.level ?? me.rep?.level ?? 0))
                        .padding(.top, 18)
                    switch tab {
                    case "rep": ReputationPanel(rep: pub?.rep).padding(.top, 14)
                    default: MyListingsSection(store: store).padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await app.refreshMe(); await reload() }
        .task(id: app.me?.id) { await reload() }
        .onAppear(perform: openList)
        .onChange(of: nav.profileList) { _, _ in openList() }
    }

    /// Открыли профиль из push — сразу на нужной вкладке своих объявлений.
    private func openList() {
        guard let t = nav.profileList else { return }
        if MyListingsSection.tabs.contains(where: { $0.0 == t }) { tab = "ads"; store.tab = t }
        nav.profileList = nil
    }

    private func reload() async {
        guard let me = app.me else { return }
        if let r: UserResponse = try? await API.shared.get("/api/users/\(me.id)") { pub = r.user }
        await store.load()
    }

    private var active: Int { store.items.filter { $0.status == "active" }.count }

    private func ownActions(_ u: PublicUser) -> some View {
        HStack(spacing: 8) {
            Button { nav.push(.settings(.profile)) } label: {
                Label("Изменить профиль", systemImage: "person").font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    .frame(maxWidth: .infinity).frame(height: 46).background(Capsule().fill(T.surface))
            }
            .buttonStyle(.plain)
            ShareLink(item: API.shared.url("/u/\(u.id)"), subject: Text(u.name)) {
                Label("Поделиться", systemImage: "square.and.arrow.up").font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1).fixedSize()
                    .padding(.horizontal, 16).frame(height: 46).background(Capsule().fill(T.surface))
            }
        }
    }
}

@MainActor
final class MyListingsStore: ObservableObject {
    @Published var items: [MyListing] = []
    @Published var loading = true
    @Published var error: String?
    @Published var tab = "active"

    func load() async {
        do { items = (try await API.shared.get("/api/my/listings") as MyListings).items; error = nil }
        catch is CancellationError {} catch { self.error = error.userMessage() }
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
        } catch { AppState.shared.fail(error) }
    }
}

/// Плашки статусов (выбранная — синяя) и карточки своих объявлений с меню «…».
struct MyListingsSection: View {
    @ObservedObject var store: MyListingsStore
    @EnvironmentObject private var nav: Nav

    static let tabs = [("active", "Активные"), ("pending", "На проверке"), ("rejected", "На исправлении"), ("archived", "Архив")]

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
            } else if let error = store.error, store.items.isEmpty {
                LoadFailed(error: error, retry: store.load)
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

// Уведомления: решения модерации, снижение цен, новое у продавцов из подписок…
struct NoticesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [Notice] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageCover(title: "Уведомления", sub: "Модерация, цены в избранном, новое в подписках", icon: "bell.fill", tone: .red)
                PushCard().padding(.top, 18)
                if loading && items.isEmpty {
                    LoadingView()
                } else if let error, items.isEmpty {
                    LoadFailed(error: error, retry: load).padding(.top, 16)
                } else if items.isEmpty {
                    EmptyState(title: "Уведомлений нет", text: "Здесь появятся решения модерации, снижение цен в избранном и новое у продавцов из подписок.").padding(.top, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { n in
                            Button { if let u = n.url, !u.isEmpty { nav.open(path: u) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Glyph(name: icon(n), size: 16)
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
        case "handshake", "star": return "asset:Handshake"
        case "user", "follow": return "person"
        default: return "bell"
        }
    }

    private func load() async {
        do { items = (try await API.shared.get("/api/notices") as NoticeList).items; error = nil }
        catch is CancellationError {} catch { self.error = error.userMessage() }
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
            do { try await work(); app.show(ok) } catch { app.fail(error) }
            await reload()
            busy = false
        }
    }
}
