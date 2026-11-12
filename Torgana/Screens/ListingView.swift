import SwiftUI

// Объявление: фото, цена, характеристики, описание, условия, продавец, похожие. Внизу — «Написать».
struct ListingView: View {
    let id: Int
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var data: ListingResponse?
    @State private var error: String?
    @State private var page = 0
    @State private var gallery = false
    @State private var report = false
    @State private var writing = false

    var body: some View {
        Group {
            if let d = data { content(d) }
            else if let error { EmptyState(icon: "exclamationmark.triangle", title: "Не открылось", text: error, button: "Повторить") { Task { await load() } } }
            else { LoadingView() }
        }
        .background(T.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let d = data {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: API.shared.url("/l/\(d.listing.id)"), subject: Text(d.listing.title), message: Text("\(d.listing.title) — \(Fmt.price(d.listing.price, unit: d.listing.priceUnit))")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    if d.listing.isOwner != true {
                        let on = app.isFav(d.listing.id, d.listing.isFav)
                        Button { Task { _ = await app.toggleFav(d.listing.id, current: on) } } label: {
                            Image(systemName: on ? "heart.fill" : "heart").foregroundStyle(on ? Color(hex: 0xE5484D) : T.accent)
                        }
                    }
                }
            }
        }
        .hidesTabBar()
        .task { if data == nil { await load() } }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $gallery) { if let d = data { Gallery(photos: d.listing.photos ?? [], page: $page) } }
        .sheet(isPresented: $report) { ReportSheet(listingId: id) }
    }

    private func load() async {
        do {
            data = try await API.shared.get("/api/listings/\(id)")
            error = nil
            _ = try? await API.shared.post("/api/stats/view", ["id": id], as: JSONValue.self)
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }

    @ViewBuilder private func content(_ d: ListingResponse) -> some View {
        let l = d.listing
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                photos(l)
                VStack(alignment: .leading, spacing: 22) {
                    head(l)
                    if l.status != nil && l.status != "active" { statusNote(l) }
                    if let specs = l.specs, !specs.isEmpty { specsBlock(specs) }
                    if let text = l.description, !text.isEmpty {
                        block("Описание") { Text(text).font(.on(16)).foregroundStyle(T.text).lineSpacing(4).textSelection(.enabled) }
                    }
                    conditions(l)
                    if let s = d.seller { sellerCard(s) }
                    safety
                    if l.isOwner != true && app.me != nil {
                        Button { report = true } label: { Label("Пожаловаться", systemImage: "exclamationmark.triangle") }
                            .buttonStyle(TButton(kind: .line, height: 48))
                    }
                    if let similar = d.similar, !similar.isEmpty {
                        block("Похожие объявления") { ListingGrid(items: similar) }
                    }
                }
                .padding(16)
                Color.clear.frame(height: 100)
            }
        }
        .overlay(alignment: .bottom) { actionBar(d) }
    }

    private func photos(_ l: Listing) -> some View {
        let list = l.photos ?? []
        return ZStack(alignment: .bottom) {
            if list.isEmpty {
                T.surface.overlay(Image(systemName: "photo").font(.system(size: 40)).foregroundStyle(T.faint))
            } else {
                TabView(selection: $page) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, p in
                        RemoteImage(url: API.shared.media(p))
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { gallery = true }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                if list.count > 1 {
                    Text("\(page + 1) из \(list.count)")
                        .font(.on(13, .semibold)).foregroundStyle(T.text)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(T.card.opacity(0.92)))
                        .padding(.bottom, 14)
                }
            }
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: T.rCard, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func head(_ l: Listing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.title).font(.on(24, .heavy)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Fmt.price(l.price, unit: l.priceUnit)).font(.on(30, .heavy)).foregroundStyle(T.text)
                if let was = l.priceWas, let p = l.price, was > p {
                    Text(Fmt.price(was)).font(.on(16)).strikethrough().foregroundStyle(T.faint)
                }
            }
            let place = [l.metro?.name.map { "м. \($0)" }, l.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            Text([place, Fmt.dayTime(l.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.on(14)).foregroundStyle(T.muted)
            HStack(spacing: 16) {
                Label("\(l.views ?? 0) \(Fmt.plural(l.views ?? 0, "просмотр", "просмотра", "просмотров"))", systemImage: "eye")
                Label("в избранном у \(l.favCount ?? 0)", systemImage: "heart")
            }
            .font(.on(13)).foregroundStyle(T.muted)
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

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.on(21, .heavy)).foregroundStyle(T.text)
            content()
        }
    }

    private func specsBlock(_ specs: [Spec]) -> some View {
        block("Характеристики") {
            VStack(spacing: 0) {
                ForEach(Array(specs.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.label ?? "").font(.on(15)).foregroundStyle(T.muted)
                        Spacer(minLength: 12)
                        Text(s.value ?? "").font(.on(15, .medium)).foregroundStyle(T.text).multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 11)
                    if i < specs.count - 1 { Divider().overlay(T.line) }
                }
            }
        }
    }

    private struct Cond: Identifiable { let text: String; let icon: String; let soft: Bool; var id: String { text } }

    private func conditions(_ l: Listing) -> some View {
        var tags = [Cond(text: l.delivery == true ? "Есть доставка" : "Только встреча", icon: l.delivery == true ? "shippingbox" : "person.2", soft: false)]
        if l.bargain == true { tags.append(Cond(text: "Торг уместен", icon: "tag", soft: true)) }
        if l.exchange == true { tags.append(Cond(text: "Возможен обмен", icon: "arrow.left.arrow.right", soft: true)) }
        if let c = l.city, !c.isEmpty { tags.append(Cond(text: c, icon: "mappin", soft: false)) }
        return block("Условия") {
            FlowLayout(spacing: 8) {
                ForEach(tags) { t in
                    Label(t.text, systemImage: t.icon)
                        .font(.on(14, .medium))
                        .foregroundStyle(t.soft ? T.accent : T.text)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().fill(t.soft ? T.accentSoft : T.surface))
                }
            }
        }
    }

    private func sellerCard(_ s: Seller) -> some View {
        Button { nav.push(.web("/u/\(s.id)")) } label: {
            HStack(spacing: 14) {
                Avatar(name: s.name, url: s.avatar, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(s.name).font(.on(17, .bold)).foregroundStyle(T.text).lineLimit(1)
                        if s.badges?.official == true || s.badges?.shop == true {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(T.accent).font(.system(size: 14))
                        }
                    }
                    if let lvl = s.rep?.levelName { Text(lvl).font(.on(14, .semibold)).foregroundStyle(T.text2) }
                    Text("На Торгане с \(Fmt.monthYear(s.createdAt)) · \(s.activeCount ?? 0) \(Fmt.plural(s.activeCount ?? 0, "объявление", "объявления", "объявлений"))")
                        .font(.on(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(T.faint).font(.system(size: 14, weight: .semibold))
            }
            .panel(radius: 24, padding: 16)
        }
        .buttonStyle(.plain)
    }

    private var safety: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield").foregroundStyle(T.accent).font(.system(size: 17, weight: .semibold))
            (Text("Мы никогда не просим ").foregroundColor(T.text2) + Text("переходить в мессенджеры, называть код из СМС или платить по ссылке.").foregroundColor(T.text2) + Text(" Если об этом просят — это мошенники.").bold().foregroundColor(T.text))
                .font(.on(14)).lineSpacing(2)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface))
    }

    private func actionBar(_ d: ListingResponse) -> some View {
        let l = d.listing
        return HStack(spacing: 10) {
            if l.isOwner == true {
                Button("Редактировать") { nav.push(.web("/edit/\(l.id)")) }.buttonStyle(TButton(kind: .dark))
            } else if l.status == "active" {
                Button { Task { await write(l.id) } } label: {
                    HStack(spacing: 8) {
                        if writing { ProgressView().tint(.white) } else { Image(systemName: "message.fill") }
                        Text("Написать")
                    }
                }
                .buttonStyle(TButton(kind: .accent))
                .disabled(writing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    /// Чат с продавцом: создаём (или находим) переписку и открываем её.
    private func write(_ listingId: Int) async {
        guard app.me != nil else { app.needLogin = true; return }
        writing = true
        defer { writing = false }
        do {
            let r: IdResult = try await API.shared.post("/api/conversations", ["listingId": listingId])
            nav.push(.web("/messages/\(r.id)"))
        } catch {
            app.show((error as? APIError)?.message ?? "Не получилось", bad: true)
        }
    }
}

// Фото на весь экран: листание и увеличение двумя пальцами.
struct Gallery: View {
    let photos: [String]
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                    ZoomImage(url: API.shared.media(p)).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .statusBarHidden()
    }
}

struct ZoomImage: View {
    let url: URL?
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1

    var body: some View {
        RemoteImage(url: url, contentMode: .fit)
            .scaleEffect(scale)
            .gesture(MagnificationGesture()
                .onChanged { scale = max(1, min(4, last * $0)) }
                .onEnded { _ in last = scale })
            .onTapGesture(count: 2) { withAnimation(.spring()) { scale = scale > 1 ? 1 : 2.5; last = scale } }
    }
}

// Жалоба на объявление — те же причины, что у сайта.
struct ReportSheet: View {
    let listingId: Int
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var text = ""
    @State private var sending = false

    static let reasons = ["Запрещённый товар или услуга", "Мошенничество", "Неверная цена или описание", "Товар уже продан",
                          "Чужие фото или подделка", "Оскорбления или спам", "Нарушены мои права (правообладатель)"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Что не так?") {
                    ForEach(ReportSheet.reasons, id: \.self) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r).foregroundStyle(T.text)
                                Spacer()
                                if reason == r { Image(systemName: "checkmark").foregroundStyle(T.accent) }
                            }
                        }
                    }
                }
                Section("Подробности") {
                    TextField("Например: просит предоплату на карту", text: $text, axis: .vertical).lineLimit(3...6)
                }
            }
            .font(.on(16))
            .navigationTitle("Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }.disabled(reason.isEmpty || sending).fontWeight(.semibold)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            _ = try await API.shared.post("/api/listings/\(listingId)/report", ["reason": reason, "text": text], as: JSONValue.self)
            app.show("Спасибо! Модератор проверит объявление")
            Haptics.play("success")
            dismiss()
        } catch {
            app.show((error as? APIError)?.message ?? "Не получилось", bad: true)
        }
    }
}

// Плашки в несколько строк.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
