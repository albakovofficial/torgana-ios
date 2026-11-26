import SwiftUI

// Объявление — как страница объявления сайта на телефоне: фото, карточка (название, избранное, поделиться,
// просмотры, цена, «Написать продавцу», «Предложить цену»), характеристики, описание, условия, продавец,
// предупреждение о мошенниках, похожие. Она же — превью на последнем шаге подачи (draft).
struct ListingView: View {
    let id: Int
    /// Превью при подаче («Всё верно?»): та же страница без кнопок покупателя; «Изменить» возвращает к полю.
    var draft: Draft? = nil

    struct Draft {
        let data: ListingResponse
        /// Снятые фото — показываем сразу, не дожидаясь сервера (по порядку с data.listing.photos).
        let images: [UIImage?]
        let edit: (Field) -> Void
    }
    enum Field { case photos, price, text }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var data: ListingResponse?
    @State private var error: String?
    @State private var page = 0
    @State private var gallery = false
    @State private var report = false
    @State private var offer = false
    @State private var writing = false

    var body: some View {
        if let draft { blocks(draft.data) } else { screen }
    }

    private var screen: some View {
        Group {
            if let d = data { content(d) }
            else if let error { LoadFailed(title: "Не открылось", error: error, retry: load).padding(20) }
            else { LoadingView() }
        }
        .sitePage()
        .task { if data == nil { await load() } }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $gallery) { if let d = data { Gallery(photos: d.listing.photos ?? [], page: $page) } }
        .sheet(isPresented: $report) { ReportSheet(listingId: id) }
        .sheet(isPresented: $offer) {
            if let l = data?.listing {
                PriceSheet(title: "Предложить цену", hint: "Цена продавца — \(Fmt.price(l.price, unit: l.priceUnit)). Предложение придёт ему в чат.") { sum in
                    await app.openChat(listingId: l.id, offer: sum)
                    return nil
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func load() async {
        do {
            data = try await API.shared.get("/api/listings/\(id)")
            error = nil
            _ = try? await API.shared.post("/api/stats/view", ["id": id], as: JSONValue.self)
        } catch {
            self.error = error.userMessage()
        }
    }

    private func content(_ d: ListingResponse) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    BackButton().padding(.top, 10)
                    blocks(d).padding(.top, 14)
                }
                .padding(.horizontal, 20)
                TabBarSpace()
            }
            #if DEBUG
            .task {   // снимок «/l/5#bottom» — блок продавца
                guard UserDefaults.standard.bool(forKey: "bottom") else { return }
                try? await Task.sleep(nanoseconds: 800_000_000)
                proxy.scrollTo("seller", anchor: .center)
            }
            #endif
        }
    }

    @ViewBuilder private func blocks(_ d: ListingResponse) -> some View {
        let l = d.listing
        VStack(alignment: .leading, spacing: 0) {
            photos(l)
            panel(l).padding(.top, 28)
            if draft == nil, l.status != nil && l.status != "active" { statusNote(l).padding(.top, 16) }
            if let specs = l.specs, !specs.isEmpty { specsBlock(l, specs).padding(.top, 36) }
            if let text = l.description, !text.isEmpty {
                section("Описание", edit: .text) { Text(text).font(.on(18)).foregroundStyle(T.text).lineSpacing(6).textSelection(.enabled) }
                    .padding(.top, 36)
            }
            conditions(l).padding(.top, 36)
            if let s = d.seller { seller(s, own: l.isOwner == true).padding(.top, 36).id("seller") }
            if draft == nil {
                fraud.padding(.top, 16)
                if let similar = d.similar, !similar.isEmpty {
                    section("Похожие объявления") { ListingGrid(items: similar) }.padding(.top, 36)
                }
            }
        }
    }

    /// «Изменить» в превью подачи.
    @ViewBuilder private func editLink(_ f: Field) -> some View {
        if let draft {
            Button("Изменить") { draft.edit(f) }.font(.on(15, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
        }
    }

    private func photos(_ l: Listing) -> some View {
        let list = l.photos ?? []
        return Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if list.isEmpty {
                    T.surface.overlay(Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(T.faint))
                        .onTapGesture { draft?.edit(.photos) }
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                            Group {
                                if let img = draft?.images[safe: i] ?? nil {
                                    Color.clear.overlay(Image(uiImage: img).resizable().scaledToFill())
                                } else {
                                    RemoteImage(url: API.shared.media(p))
                                }
                            }
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { if let draft { draft.edit(.photos) } else { gallery = true } }
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .overlay(alignment: .bottom) {
                if list.count > 1 {
                    Text("\(page + 1) из \(list.count)")
                        .font(.on(13, .semibold)).foregroundStyle(T.text)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(T.card.opacity(0.92)))
                        .padding(.bottom, 12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let draft {
                    Button { draft.edit(.photos) } label: {
                        Label("Фото", systemImage: "pencil").font(.on(13, .semibold)).foregroundStyle(T.accent)
                            .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(T.card))
                    }
                    .buttonStyle(.plain).padding(12)
                }
            }
            .background(T.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // Карточка (.panel.panel-shadow): белая, скругление 28, обводка и мягкая тень; внутри 22×20.
    private func panel(_ l: Listing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.title).font(.on(24, .bold)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
                    let place = [l.metro?.name.map { "м. \($0)" }, l.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                    Text([place, Fmt.dayTime(l.createdAt)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.on(14)).foregroundStyle(T.muted)
                    if draft == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(l.views ?? 0) \(Fmt.plural(l.views ?? 0, "просмотр", "просмотра", "просмотров"))", systemImage: "eye")
                        Label("в избранном у \(l.favCount ?? 0)", systemImage: "heart")
                    }
                    .font(.on(14)).foregroundStyle(T.muted).labelStyle(MetaLabel())
                    }
                }
                Spacer(minLength: 0)
                if draft == nil {
                if l.isOwner != true {
                    let on = app.isFav(l.id, l.isFav)
                    Button { Task { _ = await app.toggleFav(l.id, current: on) } } label: {
                        RoundIcon(icon: on ? "heart.fill" : "heart", tint: on ? Color(hex: 0xE5484D) : T.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "Убрать из избранного" : "В избранное")
                }
                ShareLink(item: API.shared.url("/l/\(l.id)"), subject: Text(l.title), message: Text("\(l.title) — \(Fmt.price(l.price, unit: l.priceUnit))")) {
                    RoundIcon(icon: "square.and.arrow.up")
                }
                .accessibilityLabel("Поделиться")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.price(l.price, unit: l.priceUnit)).font(.on(36, .heavy)).foregroundStyle(T.text).minimumScaleFactor(0.6).lineLimit(1)
                if let was = l.priceWas, let p = l.price, was > p {
                    Text(Fmt.price(was)).font(.on(17)).strikethrough().foregroundStyle(T.faint)
                }
                Spacer(minLength: 0)
                editLink(.price)
            }
            .padding(.top, 22)
            if draft == nil {
            VStack(spacing: 10) {
                if l.isOwner == true {
                    Button { nav.push(.edit(l.id)) } label: { Label("Редактировать", systemImage: "pencil") }
                        .buttonStyle(TButton(kind: .dark, height: 58))
                } else if l.status == "active" {
                    Button { Task { writing = true; await app.openChat(listingId: l.id); writing = false } } label: {
                        HStack(spacing: 10) {
                            if writing { ProgressView().tint(.white) } else { Image(systemName: "message") }
                            Text("Написать продавцу")
                        }
                    }
                    .buttonStyle(TButton(kind: .accent, height: 58))
                    .disabled(writing)
                    if l.bargain == true {
                        Button { if app.me == nil { app.requireLogin(.init(title: "Войдите, чтобы предложить цену", text: "Продавец увидит ваше предложение в сообщениях")) } else { offer = true } } label: { Label("Предложить цену", systemImage: "tag") }
                            .buttonStyle(TButton(kind: .soft, height: 58))
                    }
                    if app.me != nil {
                        Button { report = true } label: { Label("Пожаловаться", systemImage: "flag") }
                            .buttonStyle(TButton(kind: .line, height: 48))
                    }
                }
            }
            .padding(.top, 22)
            VStack(alignment: .leading, spacing: 14) {
                note("checkmark.shield", "Общайтесь в чате Торганы.", "Так переписка сохранится, а мы сможем помочь при споре.")
                if l.delivery == true {
                    note("truck.box", "Доставка по России.", "Продавец готов отправить товар — договоритесь о способе в чате.")
                }
            }
            .padding(.top, 20)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.card).shadow(color: Color(hex: 0x101010).opacity(0.08), radius: 20, y: 12))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    private func note(_ icon: String, _ bold: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular)).foregroundStyle(T.accent).frame(width: 22)
            (Text(bold + " ").font(.on(14, .bold)).foregroundColor(T.text) + Text(text).font(.on(14)).foregroundColor(T.text2))
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusNote(_ l: Listing) -> some View {
        let text: String = {
            switch l.status {
            case "pending": return "Объявление на проверке у модератора — его пока видите только вы."
            case "rejected": return "Нужно исправить" + ((l.rejectReason ?? "").isEmpty ? "" : ": \(l.rejectReason!)")
            case "sold": return "Продано"
            case "archived": return "Снято с публикации"
            default: return "Объявление недоступно"
            }
        }()
        return Label(text, systemImage: "info.circle")
            .font(.on(14, .medium)).foregroundStyle(T.text2)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.warnSoft))
    }

    private func section<C: View>(_ title: String, edit: Field? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.on(26, .bold)).foregroundStyle(T.text)
                Spacer(minLength: 0)
                if let edit { editLink(edit) }
            }
            content()
        }
    }

    // Характеристики: раздел › подраздел, первые четыре — плитками 2×2, остальные — строками.
    private func specsBlock(_ l: Listing, _ specs: [Spec]) -> some View {
        let tiles = Array(specs.prefix(4))
        let rest = Array(specs.dropFirst(4))
        let path = [app.config?.category(l.category)?.name, app.config?.subs(l.category).first { $0.id == l.subcategory }?.name].compactMap { $0 }
        return section("Характеристики") {
            if !path.isEmpty { Text(path.joined(separator: " › ")).font(.on(15)).foregroundStyle(T.muted).padding(.top, -6) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.label ?? "").font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
                        Text(s.value ?? "").font(.on(18, .bold)).foregroundStyle(T.text).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
                }
            }
            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.offset) { _, s in
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.label ?? "").font(.on(16)).foregroundStyle(T.muted)
                            Spacer(minLength: 12)
                            Text(s.value ?? "").font(.on(16, .semibold)).foregroundStyle(T.text).multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 15)
                        .overlay(alignment: .bottom) { T.line.frame(height: 1) }
                    }
                }
            }
        }
    }

    private struct Cond: Identifiable { let text: String; let icon: String; let soft: Bool; var id: String { text } }

    // Условия — плашки: синие (доставка, торг, обмен) и серая с городом.
    private func conditions(_ l: Listing) -> some View {
        var tags: [Cond] = []
        if l.delivery == true { tags.append(Cond(text: "Отправит по России", icon: "truck.box", soft: true)) } else { tags.append(Cond(text: "Только встреча", icon: "person.2", soft: false)) }
        if l.bargain == true { tags.append(Cond(text: "Торг уместен", icon: "tag", soft: true)) }
        if l.exchange == true { tags.append(Cond(text: "Возможен обмен", icon: "arrow.left.arrow.right", soft: true)) }
        if let c = l.city, !c.isEmpty { tags.append(Cond(text: c, icon: "mappin", soft: false)) }
        return section("Условия") {
            FlowLayout(spacing: 8) {
                ForEach(tags) { t in
                    HStack(spacing: 6) {
                        Image(systemName: t.icon).font(.system(size: 13, weight: .semibold))
                        Text(t.text).font(.on(15, .semibold))
                    }
                    .foregroundStyle(t.soft ? T.accent : T.text)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Capsule().fill(t.soft ? T.accentSoft : T.surface))
                }
            }
        }
    }

    // Продавец (решение 26.11, «A1»): серая плашка — аватар с монетой уровня, имя, уровень; под чертой — сделки,
    // скорость ответа, «без жалоб» (только то, что есть). Покупателю — «Все объявления» и колокольчик подписки.
    private func seller(_ s: Seller, own: Bool) -> some View {
        let r = s.rep
        let deals = r?.deals ?? 0
        var facts: [(icon: String, text: String, tint: Color)] = []
        if deals > 0 { facts.append(("checkmark.circle", "\(deals) \(Fmt.plural(deals, "сделка", "сделки", "сделок"))", T.accent)) }
        if let t = r?.replyText { facts.append(("clock", "отвечает \(t)", T.accent)) }
        if deals > 0 && (r?.complaints ?? 0) == 0 { facts.append(("checkmark.shield", "без жалоб", T.good)) }
        return VStack(alignment: .leading, spacing: 0) {
            Button { nav.push(.user(s.id)) } label: {
                HStack(spacing: 12) {
                    Avatar(name: s.name, url: s.avatar, size: 52)
                        .overlay(alignment: .bottomTrailing) {
                            if let lvl = r?.level { LevelCoin(level: lvl, size: 22).background(Circle().fill(T.surface).padding(-2)).offset(x: 3, y: 3) }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(s.name).font(.on(17, .heavy)).foregroundStyle(T.text).lineLimit(1)
                            if s.badges?.official == true || s.badges?.shop == true { Verified(size: 16) }
                        }
                        if let name = r?.levelName { Text(name).font(.on(14, .bold)).foregroundStyle(LevelPill.tint(r?.level ?? 0)) }
                    }
                    Spacer(minLength: 4)
                    if draft == nil { Image(systemName: "chevron.right").foregroundStyle(T.muted).font(.system(size: 15, weight: .semibold)) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(draft != nil)
            if !facts.isEmpty {
                T.line.frame(height: 1).padding(.vertical, 12)
                FlowLayout(spacing: 14) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                        HStack(spacing: 5) {
                            Image(systemName: f.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(f.tint)
                            Text(f.text).font(.on(13.5, .semibold)).foregroundStyle(T.text2)
                        }
                    }
                }
            }
            if draft == nil && !own {
                HStack(spacing: 8) {
                    Button("Все объявления · \(s.activeCount ?? 0)") { nav.push(.user(s.id)) }
                        .buttonStyle(TButton(kind: .line, height: 44))
                    Button { Task { if let r = await app.follow(s.id, !(data?.seller?.following ?? false)) { data?.seller?.following = r.following; if let n = r.followers { data?.seller?.followers = n } } } } label: {
                        RoundIcon(icon: s.following == true ? "bell.fill" : "bell", size: 44, fill: T.accentSoft, tint: T.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.following == true ? "Вы подписаны" : "Подписаться")
                }
                .padding(.top, 14)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface))
    }

    private var fraud: some View {
        (Text("Мы никогда не просим ").font(.on(15, .bold)).foregroundColor(T.text)
         + Text("переходить в мессенджеры, называть код из СМС или платить по ссылке. Если вас об этом просят — это мошенники.").font(.on(15)).foregroundColor(T.text2))
            .lineSpacing(3)
            .padding(.horizontal, 22).padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.surface))
    }
}
