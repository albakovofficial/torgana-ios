import SwiftUI

// Страница продавца — как на сайте: карточка (аватарка, имя, город, уровень, медаль, цифры), «Написать продавцу»,
// «Подписаться», «Поделиться», «Ещё» (заблокировать), переключатель «Объявления / Репутация» и объявления.
struct UserView: View {
    let id: Int
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var user: PublicUser?
    @State private var items: [ListingCard] = []
    @State private var error: String?
    @State private var confirmBlock = false
    @State private var pick = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let u = user {
                    hero(u).padding(.top, 12)
                    segment(u).padding(.top, 32)
                    if items.isEmpty {
                        EmptyState(title: "Нет активных объявлений").padding(.top, 16)
                    } else {
                        ListingGrid(items: items).padding(.top, 16)
                    }
                } else if let error {
                    EmptyState(title: "Не открылось", text: error).padding(.top, 16)
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

    // .pub-hero: --surface, скругление 26, внутри 18.
    private func hero(_ u: PublicUser) -> some View {
        let own = app.me?.id == u.id
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Avatar(name: u.name, url: u.avatar, size: 72).padding(.top, 13)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(u.name).font(.on(22, .heavy)).foregroundStyle(T.text)
                        if u.badges?.official == true || u.badges?.shop == true { Verified(size: 22) }
                    }
                    Text([u.city, u.createdAt.map { "на Торгане с \(Fmt.monthYear($0))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.on(13)).foregroundStyle(T.muted)
                    RepLine(rep: u.rep, medal: u.badges?.first)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                num(u.activeCount ?? items.count, Fmt.plural(u.activeCount ?? items.count, "объявление", "объявления", "объявлений"))
                num(u.rep?.deals ?? 0, Fmt.plural(u.rep?.deals ?? 0, "сделка", "сделки", "сделок"))
                num(u.followers ?? 0, Fmt.plural(u.followers ?? 0, "подписчик", "подписчика", "подписчиков"))
            }
            if !own {
                Button { write() } label: { Label("Написать продавцу", systemImage: "message") }
                    .buttonStyle(TButton(kind: .accent, height: 48))
                HStack(spacing: 8) {
                    Button {
                        Task { if let r = await app.follow(u.id, !(u.following ?? false)) { user?.following = r.following; if let n = r.followers { user?.followers = n } } }
                    } label: {
                        Label(u.following == true ? "Вы подписаны" : "Подписаться", systemImage: u.following == true ? "bell.fill" : "bell")
                            .font(.on(15, .semibold)).foregroundStyle(T.text)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Capsule().fill(T.card))
                    }
                    .buttonStyle(.plain)
                    ShareLink(item: API.shared.url("/u/\(u.id)"), subject: Text(u.name)) { RoundIcon(icon: "square.and.arrow.up", size: 48, fill: T.card) }
                        .accessibilityLabel("Поделиться")
                    if app.me != nil {
                        // Блокировка — своей кнопкой (рука; у заблокированного — красная), окно с объяснением.
                        Button { confirmBlock = true } label: {
                            RoundIcon(icon: u.block == "me" ? "hand.raised.slash.fill" : "hand.raised", size: 48,
                                      fill: u.block == "me" ? T.dangerSoft : T.card, tint: u.block == "me" ? T.danger : T.text)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(u.block == "me" ? "Разблокировать" : "Заблокировать")
                    }
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.surface))
    }

    private func num(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.on(18, .heavy)).foregroundStyle(T.text)
            Text(label).font(.on(12)).foregroundStyle(T.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
    }

    // .seg.seg-lg: «Объявления N» (выбрано) и «Репутация» (страница сайта).
    private func segment(_ u: PublicUser) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Объявления").font(.on(15, .semibold)).foregroundStyle(T.text)
                Text("\(items.count)").font(.on(12, .semibold)).foregroundStyle(T.onInk)
                    .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22).background(Capsule().fill(T.ink))
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(Capsule().fill(T.card).shadow(color: Color(hex: 0x101010).opacity(0.08), radius: 5, y: 2))
            Button { nav.push(.web("/u/\(u.id)?tab=rep")) } label: {
                HStack(spacing: 6) {
                    LevelCoin(level: u.rep?.level ?? 0, size: 18)
                    Text("Репутация").font(.on(15, .semibold)).foregroundStyle(T.text2)
                }
                .frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Capsule().fill(T.surface))
    }

    /// Переписка всегда об объявлении: одно — сразу в чат, несколько — выбрать (как writePicker сайта).
    private func write() {
        guard app.me != nil else { app.needLogin = true; return }
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
