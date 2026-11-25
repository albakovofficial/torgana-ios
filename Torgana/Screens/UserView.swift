import SwiftUI

// Страница продавца (решение 25.11, вариант A): обложка (у магазина — своя, у остальных — фирменный градиент),
// аватарка поверх неё и уровень; имя, город, срок на Торгане и скорость ответа; три числа; «Написать», «Подписаться», «⋯».
// Вкладки «Объявления» и «Репутация» — обе здесь же, без перехода на сайт. Своя страница — с плашкой «Так вас видят».
struct UserView: View {
    let id: Int
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var user: PublicUser?
    @State private var items: [ListingCard] = []
    @State private var error: String?
    @State private var confirmBlock = false
    @State private var pick = false
    @State private var repTab = false

    private static let replyText = ["hour": "за час", "hours": "за 1–3 ч", "day": "в течение дня", "days": "за 1–2 дня"]
    private static let marks = ["first": "Первая сделка", "10": "10 сделок", "50": "50 сделок", "100": "100 сделок", "year": "Год без жалоб"]
    private static let steps = [("Новичок", "с первого дня"),
                                ("Надёжный", "телефон и фото профиля · 5 сделок · 3 комплимента · ответ в течение дня"),
                                ("Опытный", "30 сделок · 15 комплиментов · ответ за 1–3 ч · 2 месяца на Торгане"),
                                ("Мастер Торганы", "100 сделок · 50 комплиментов · ответ за час · 3 месяца без жалоб")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(route: .user(id), current: "Продавец").padding(.bottom, 14)
                if let u = user {
                    if app.me?.id == u.id { ownBar }
                    hero(u)
                    segment(u).padding(.top, 18)
                    if repTab {
                        reputation(u).padding(.top, 14)
                    } else if items.isEmpty {
                        EmptyState(title: "Нет активных объявлений").padding(.top, 14)
                    } else {
                        ListingGrid(items: items).padding(.top, 14)
                    }
                } else if let error {
                    EmptyState(title: "Не открылось", text: error)
                } else {
                    LoadingView()
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .sheet(isPresented: $confirmBlock) {
            if let u = user { BlockSheet(name: u.name, avatar: u.avatar, blocked: u.block == "me") { await toggleBlock() } }
        }
        .sheet(isPresented: $pick) { WritePicker(name: user?.name ?? "", items: items) { lid in pick = false; Task { await app.openChat(listingId: lid) } } }
        .refreshable { await load() }
        .task { if user == nil { await load() } }
    }

    private var ownBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.accent)
            Text("Так вас видят покупатели").font(.on(14, .semibold)).foregroundStyle(T.text)
            Spacer()
            Button("Изменить") { nav.push(.settings(.profile)) }.font(.on(14, .semibold)).foregroundStyle(T.accent)
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.accentSoft))
        .padding(.bottom, 12)
    }

    private func hero(_ u: PublicUser) -> some View {
        let own = app.me?.id == u.id
        let shop = u.shop
        let sub = [u.city, u.createdAt.map { "на Торгане с \(Fmt.monthYear($0))" },
                   u.rep?.reply?.time.flatMap { Self.replyText[$0] }.map { "отвечает \($0)" }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            // Обложка: у магазина — своя, у остальных — фирменный градиент; «Поделиться» — на ней.
            ZStack(alignment: .topTrailing) {
                if let cover = API.shared.media(shop?.cover) {
                    RemoteImage(url: cover)
                } else {
                    AuthGradient().overlay(alignment: .topTrailing) {
                        Circle().fill(.white.opacity(0.1)).frame(width: 170, height: 170).offset(x: 40, y: -70)
                    }
                }
                ShareLink(item: API.shared.url("/u/\(u.id)"), subject: Text(u.name)) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(Circle().fill(.black.opacity(0.18)))
                }
                .accessibilityLabel("Поделиться")
                .padding(12)
            }
            .frame(height: 100).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 10) {
                    Avatar(name: u.name, url: u.avatar, size: 84)
                        .overlay(Circle().strokeBorder(T.card, lineWidth: 4))
                        .shadow(color: Color(hex: 0x161A2B).opacity(0.15), radius: 10, y: 6)
                    if shop?.official != true { RepLine(rep: u.rep, medal: u.badges?.first).padding(.bottom, 6) }
                }
                .padding(.top, -42)
                HStack(spacing: 6) {
                    Text(shop?.name ?? u.name).font(.on(22, .heavy)).foregroundStyle(T.text)
                    if u.badges?.official == true || u.badges?.shop == true { Verified(size: 22) }
                }
                .padding(.top, 10)
                Text(sub).font(.on(13.5)).foregroundStyle(T.muted).padding(.top, 3).fixedSize(horizontal: false, vertical: true)
                if let about = shop?.about, !about.isEmpty {
                    Text(about).font(.on(14.5)).foregroundStyle(T.text2).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    num(u.activeCount ?? items.count, Fmt.plural(u.activeCount ?? items.count, "объявление", "объявления", "объявлений"))
                    num(u.rep?.deals ?? 0, Fmt.plural(u.rep?.deals ?? 0, "сделка", "сделки", "сделок"))
                    num(u.followers ?? 0, Fmt.plural(u.followers ?? 0, "подписчик", "подписчика", "подписчиков"))
                }
                .padding(.top, 14)
                if !own { actions(u).padding(.top, 14) }
                if u.block == "me" {
                    Label("Вы заблокировали продавца — он не может вам писать", systemImage: "hand.raised.fill")
                        .font(.on(13.5, .semibold)).foregroundStyle(T.danger).padding(.top, 12)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.card))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    private func actions(_ u: PublicUser) -> some View {
        HStack(spacing: 8) {
            if u.shop?.official != true {
                Button { write() } label: { Label("Написать", systemImage: "message") }
                    .buttonStyle(TButton(kind: .accent, height: 48))
            }
            Button {
                Task { if let r = await app.follow(u.id, !(u.following ?? false)) { user?.following = r.following; if let n = r.followers { user?.followers = n } } }
            } label: {
                Label(u.following == true ? "Вы подписаны" : "Подписаться", systemImage: u.following == true ? "bell.fill" : "bell")
                    .font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    .padding(.horizontal, 14).frame(height: 48)
                    .frame(maxWidth: u.shop?.official == true ? .infinity : nil)
                    .background(Capsule().fill(T.surface))
            }
            .buttonStyle(.plain)
            Menu {
                Button(u.block == "me" ? "Разблокировать" : "Заблокировать", systemImage: u.block == "me" ? "hand.raised.slash" : "hand.raised") {
                    if app.me == nil { app.requireLogin(Tab.profile.loginAsk) } else { confirmBlock = true }
                }
                Button("Пожаловаться в поддержку", systemImage: "flag") { nav.push(.support) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(T.text)
                    .frame(width: 48, height: 48).background(Circle().fill(T.surface))
            }
            .accessibilityLabel("Ещё")
        }
    }

    private func num(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.on(18, .heavy)).foregroundStyle(T.text)
            Text(label).font(.on(12)).foregroundStyle(T.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    /// «Объявления N» и «Репутация» — переключатель на этой же странице.
    private func segment(_ u: PublicUser) -> some View {
        HStack(spacing: 0) {
            tabButton(on: !repTab) {
                Text("Объявления").font(.on(15, repTab ? .semibold : .bold)).foregroundStyle(repTab ? T.text2 : T.text)
                Text("\(items.count)").font(.on(12, .semibold)).foregroundStyle(T.onInk)
                    .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22).background(Capsule().fill(T.ink))
            } action: { repTab = false }
            tabButton(on: repTab) {
                LevelCoin(level: u.rep?.level ?? 0, size: 18)
                Text("Репутация").font(.on(15, repTab ? .bold : .semibold)).foregroundStyle(repTab ? T.text : T.text2)
            } action: { repTab = true }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
        .animation(.easeOut(duration: 0.15), value: repTab)
    }

    private func tabButton<C: View>(on: Bool, @ViewBuilder _ content: () -> C, action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.play("selection") } label: {
            HStack(spacing: 7) { content() }
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? T.card : .clear)
                    .shadow(color: Color(hex: 0x161A2B).opacity(on ? 0.08 : 0), radius: 5, y: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Репутация — как вкладка сайта (repCard + «Как считается»): уровень, сделки, ответ, жалобы, комплименты, вехи.
    private func reputation(_ u: PublicUser) -> some View {
        let r = u.rep
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LevelCoin(level: r?.level ?? 0, size: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r?.levelName ?? "Новичок").font(.on(18, .heavy)).foregroundStyle(T.text)
                        Text(r?.newbie == false ? "за 12 месяцев" : "сделок пока мало").font(.on(13)).foregroundStyle(T.muted)
                    }
                    Spacer(minLength: 0)
                    if r?.buyer == true {
                        Label("Надёжный покупатель", systemImage: "checkmark").font(.on(12, .bold)).foregroundStyle(T.good)
                            .padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(T.good.opacity(0.12)))
                    }
                }
                if r?.newbie == false {
                    HStack(spacing: 8) {
                        fact("\(r?.deals ?? 0)", Fmt.plural(r?.deals ?? 0, "сделка", "сделки", "сделок"))
                        if let t = r?.reply?.time.flatMap({ Self.replyText[$0] }) { fact(t, "ответ") }
                        fact("\(r?.complaints ?? 0)", Fmt.plural(r?.complaints ?? 0, "жалоба", "жалобы", "жалоб"), bad: (r?.complaints ?? 0) > 0)
                    }
                }
                if let tags = r?.tags, !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags, id: \.tag) { t in
                            (Text(t.tag + " ") + Text("\(t.n)").fontWeight(.heavy)).font(.on(13, .semibold)).foregroundStyle(T.accent)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(T.accentSoft))
                        }
                    }
                }
                if let marks = r?.marks, !marks.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(marks, id: \.self) { m in
                            Label(Self.marks[m] ?? m, systemImage: "star.fill").font(.on(12.5, .semibold)).foregroundStyle(T.text2)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(T.surface))
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            SettingsGroup(title: "Как считается") {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 12) {
                        LevelCoin(level: i, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.0).font(.on(15, .bold)).foregroundStyle(i == (r?.level ?? 0) ? T.accent : T.text)
                            Text(s.1).font(.on(12.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            Text("Уровень считается по сделкам за 12 месяцев: комплименты покупателей, скорость ответа и подтверждённые жалобы.")
                .font(.on(12.5)).foregroundStyle(T.muted).padding(.horizontal, 4)
        }
    }

    private func fact(_ value: String, _ label: String, bad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.on(17, .heavy)).foregroundStyle(bad ? T.danger : T.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.on(12)).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
    }

    /// Переписка всегда об объявлении: одно — сразу в чат, несколько — выбрать (как writePicker сайта).
    private func write() {
        guard app.me != nil else { app.requireLogin(.init(title: "Войдите, чтобы написать", text: "Продавец ответит вам в сообщениях")); return }
        if items.isEmpty { app.show("Сейчас у продавца нет объявлений", bad: true) }
        else if items.count == 1 { Task { await app.openChat(listingId: items[0].id) } }
        else { pick = true }
    }

    private func load() async {
        do {
            let r: UserResponse = try await API.shared.get("/api/users/\(id)")
            user = r.user
            let page: ListingsPage = try await API.shared.get("/api/listings", query: ["user": String(id), "limit": "60"])
            items = page.items
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func toggleBlock() async {
        do {
            if user?.block == "me" {
                _ = try await API.shared.send("DELETE", "/api/blocks/\(id)", body: Optional<[String: String]>.none) as JSONValue
                user?.block = nil
            } else {
                _ = try await API.shared.post("/api/blocks", ["userId": id], as: JSONValue.self)
                user?.block = "me"
            }
            Haptics.play("success")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

/// «Написать продавцу»: о каком объявлении переписка.
struct WritePicker: View {
    let name: String
    let items: [ListingCard]
    let choose: (Int) -> Void
    @State private var q = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items.filter { q.isEmpty || $0.title.lowercased().contains(q.lowercased()) }) { i in
                        Button { choose(i.id) } label: {
                            HStack(spacing: 12) {
                                RemoteImage(url: API.shared.media(i.photo)).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(i.title).font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(2)
                                    Text(Fmt.price(i.price, unit: i.priceUnit)).font(.on(14)).foregroundStyle(T.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(T.faint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(name) · выберите объявление — переписка будет о нём, так проще ответить.").font(.on(13)).textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $q, prompt: "Найти по названию")
            .navigationTitle("Написать продавцу")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
