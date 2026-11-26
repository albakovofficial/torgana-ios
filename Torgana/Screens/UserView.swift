import SwiftUI

// Страница продавца (решение 25.11, вариант A): карточка SellerCard и вкладки «Объявления» / «Репутация».
// Своя страница не открывается: свой профиль и есть витрина (ProfileView, решение 25.11 «вариант 2»).
struct UserView: View {
    let id: Int
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var user: PublicUser?
    @State private var items: [ListingCard] = []
    @State private var error: String?
    @State private var confirmBlock = false
    @State private var pick = false
    @State private var tab = "ads"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader().padding(.bottom, 14)
                if let u = user {
                    SellerCard(user: u, count: items.count) { actions(u) }
                    Seg(items: [("ads", "Объявления"), ("rep", "Репутация")], value: $tab, counts: ["ads": items.count], level: ("rep", u.rep?.level ?? 0))
                        .padding(.top, 18)
                    if tab == "rep" {
                        ReputationPanel(rep: u.rep).padding(.top, 14)
                    } else if items.isEmpty {
                        EmptyState(title: "Нет активных объявлений").padding(.top, 14)
                    } else {
                        ListingGrid(items: items).padding(.top, 14)
                    }
                } else if let error {
                    LoadFailed(title: "Не открылось", error: error)
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

    private func actions(_ u: PublicUser) -> some View {
        HStack(spacing: 8) {
            if u.shop?.official != true {
                Button { write() } label: {
                    Label("Написать", systemImage: "message").font(.on(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(T.grad))
                }
                .buttonStyle(.plain)
            }
            Button {
                Task { if let r = await app.follow(u.id, !(u.following ?? false)) { user?.following = r.following; if let n = r.followers { user?.followers = n } } }
            } label: {
                Label(u.following == true ? "Вы подписаны" : "Подписаться", systemImage: u.following == true ? "bell.fill" : "bell")
                    .font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1).fixedSize()
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
        } catch { self.error = error.userMessage() }
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
        } catch { app.fail(error) }
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

// MARK: - Карточка продавца: страница продавца и свой профиль (витрина)

/// Обложка — только у магазина (своя или фирменный градиент; решение 27.11, вариант C): без тарифа шапки нет, аватарка сверху,
/// а в своём профиле — строка «Обложка и витрина — с тарифом «Магазин»». Дальше имя с галочкой, скорость ответа, уровень,
/// описание магазина («Читать полностью»), три числа и кнопки (actions). Города и «на Торгане с» нет нигде (решение 27.11).
/// Своя (own): камера на аватарке и шестерёнка ведут в настройки профиля; иначе — «Поделиться».
struct SellerCard<Actions: View>: View {
    @EnvironmentObject private var app: AppState
    let user: PublicUser
    var count = 0
    var own = false
    @ViewBuilder let actions: () -> Actions
    @EnvironmentObject private var nav: Nav
    @State private var aboutOpen = false

    var body: some View {
        let u = user
        let shop = u.shop
        let sub = u.rep?.replyText.map { "Отвечает \($0)" } ?? ""
        VStack(alignment: .leading, spacing: 0) {
            if shop != nil {
                ZStack(alignment: .topTrailing) {
                    if let cover = API.shared.media(shop?.cover) {
                        RemoteImage(url: cover)
                    } else {
                        AuthGradient().overlay(alignment: .topTrailing) {
                            Circle().fill(.white.opacity(0.1)).frame(width: 170, height: 170).offset(x: 40, y: -70)
                        }
                    }
                    corner(dark: true).padding(.top, 18).padding(.trailing, 14)
                }
                .frame(height: 100).frame(maxWidth: .infinity).clipped()
            }
            VStack(alignment: .leading, spacing: 0) {
                Button { if own { nav.push(.settings(.profile)) } } label: {
                    Avatar(name: u.name, url: u.avatar, size: 84)
                        .overlay(Circle().strokeBorder(T.card, lineWidth: 4))
                        .overlay(alignment: .bottomTrailing) {
                            if own {
                                Image(systemName: "camera.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.text)
                                    .frame(width: 28, height: 28).background(Circle().fill(T.card)).overlay(Circle().strokeBorder(T.line, lineWidth: 1.5))
                            }
                        }
                        .shadow(color: Color(hex: 0x161A2B).opacity(0.15), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(!own)
                .accessibilityLabel(own ? "Сменить фото профиля" : u.name)
                .padding(.top, shop != nil ? -42 : 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) { if shop == nil { corner(dark: false).padding(.top, 16) } }
                // Своё имя — кнопка: шторка «Аккаунты» (переключить или добавить).
                Button { app.accountsOpen = true } label: {
                    HStack(spacing: 6) {
                        Text(shop?.name ?? u.name).font(.on(22, .heavy)).foregroundStyle(T.text)
                        if u.badges?.official == true || u.badges?.shop == true { Verified(size: 22) }
                        if own { Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(T.muted) }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!own)
                .accessibilityHint(own ? "Переключить аккаунт" : "")
                .padding(.top, 10)
                if !sub.isEmpty { Text(sub).font(.on(13.5)).foregroundStyle(T.muted).padding(.top, 3).fixedSize(horizontal: false, vertical: true) }
                Group {
                    if shop?.official == true {
                        Text("Официальный аккаунт").font(.on(13, .bold)).foregroundStyle(T.accent)
                            .padding(.horizontal, 11).frame(height: 28).background(Capsule().fill(T.accentSoft))
                    } else { RepLine(rep: u.rep, medal: u.badges?.first) }
                }
                .padding(.top, 10)
                // Описание магазина: три строки, «Читать полностью» — раскрыть.
                if let about = shop?.about, !about.isEmpty {
                    Text(about).font(.on(14.5)).foregroundStyle(T.text2).lineSpacing(2)
                        .lineLimit(aboutOpen ? nil : 3).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    HStack(spacing: 16) {
                        if about.count > 120 || about.contains("\n") {
                            Button(aboutOpen ? "Свернуть" : "Читать полностью") { withAnimation(.easeOut(duration: 0.2)) { aboutOpen.toggle() } }
                                .font(.on(14, .semibold)).foregroundStyle(T.accent)
                        }
                        if own { Button { nav.push(.business(.shop)) } label: { Label("Изменить", systemImage: "pencil") }.font(.on(14, .semibold)).foregroundStyle(T.accent) }
                    }
                    .buttonStyle(.plain).padding(.top, 4)
                } else if own && shop != nil {
                    // Своя витрина без описания — сразу туда, где его пишут.
                    Button { nav.push(.business(.shop)) } label: { Label("Добавить описание магазина", systemImage: "plus") }
                        .font(.on(14, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain).padding(.top, 10)
                }
                // Своя страница без тарифа: обложка и витрина закрыты — откроются с тарифом «Магазин».
                if own && shop == nil {
                    Button { nav.push(.business(.hub)) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(T.muted)
                            Text("Обложка и витрина — с тарифом «Магазин»").font(.on(13.5)).foregroundStyle(T.text2)
                                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            Text("Подробнее").font(.on(13.5, .bold)).foregroundStyle(T.accent)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
                    }
                    .buttonStyle(.plain).padding(.top, 14)
                }
                HStack(spacing: 8) {
                    let ads = u.activeCount ?? count
                    num(ads, Fmt.plural(ads, "объявление", "объявления", "объявлений"))
                    num(u.rep?.deals ?? 0, Fmt.plural(u.rep?.deals ?? 0, "сделка", "сделки", "сделок"))
                    num(u.followers ?? 0, Fmt.plural(u.followers ?? 0, "подписчик", "подписчика", "подписчиков"))
                }
                .padding(.top, 14)
                actions().padding(.top, 14)
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

    /// Кнопка в углу: своя — шестерёнка (настройки профиля), чужая — «Поделиться». На обложке — белая на тёмном, без обложки — на сером.
    @ViewBuilder private func corner(dark: Bool) -> some View {
        let icon = { (name: String) in
            Image(systemName: name).font(.system(size: 16, weight: .semibold)).foregroundStyle(dark ? .white : T.text)
                .frame(width: 40, height: 40).background(Circle().fill(dark ? Color.black.opacity(0.18) : T.surface))
        }
        if own {
            Button { nav.push(.settings(.profile)) } label: { icon("gearshape") }.buttonStyle(.plain).accessibilityLabel("Настройки профиля")
        } else {
            ShareLink(item: API.shared.url("/u/\(user.id)"), subject: Text(user.name)) { icon("square.and.arrow.up") }.accessibilityLabel("Поделиться")
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
}
