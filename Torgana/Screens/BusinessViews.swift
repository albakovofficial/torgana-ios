import SwiftUI
import PhotosUI
import Charts
import UniformTypeIdentifiers

// «Для бизнеса» — родные экраны (решение 26.11: хаб с карточками, сверху чек-лист запуска, пока магазин не настроен).
// Запросы те же, что у сайта: /api/my/business, /api/my/shop, /api/me/business, /api/me/trademark, /api/my/shop/stats.
// Купить тариф или продвижение в приложении нельзя (правила App Store) — только посмотреть, что подключено.
enum BizSection: String, Hashable {
    case hub, shop, trust, brand, stats, promo, payments

    var title: String {
        switch self {
        case .hub: return "Для бизнеса"
        case .shop: return "Витрина"
        case .trust: return "Доверие"
        case .brand: return "Галочка бренда"
        case .stats: return "Статистика"
        case .promo: return "Продвижение"
        case .payments: return "Платежи и чеки"
        }
    }
}

/// Данные раздела: один запрос на все экраны, после сохранения — обновить.
@MainActor
final class BizStore: ObservableObject {
    static let shared = BizStore()
    @Published var hub: BizHub?
    @Published var failed = false

    func load() async {
        do { hub = try await API.shared.get("/api/my/business"); failed = false }
        catch is CancellationError {}
        catch { if hub == nil { failed = true } }
    }

    var open: Bool { hub?.plan != nil || hub?.shop.official == true }
}

struct BusinessScreen: View {
    let section: BizSection
    @ObservedObject private var store = BizStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: section.title).padding(.bottom, 16)
                if let h = store.hub {
                    switch section {
                    case .hub: BizHubView(h: h)
                    case .shop: ShopEditView(h: h)
                    case .trust: TrustView(h: h)
                    case .brand: BrandView(h: h)
                    case .stats: StatsView()
                    case .promo: PromoList(items: h.promotions ?? [])
                    case .payments: PaymentList(items: h.payments ?? [])
                    }
                } else if store.failed {
                    EmptyState(icon: "wifi.slash", title: "Не удалось загрузить", text: "Проверьте связь и попробуйте ещё раз.", button: "Повторить") { Task { await store.load() } }
                } else { LoadingView() }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.load() }
        .task { await store.load() }
        .sitePage()
    }
}

// MARK: - Главный экран: тариф, чек-лист запуска, витрина, статистика, продвижение, доверие, платежи

private struct BizHubView: View {
    let h: BizHub
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var app: AppState

    private var official: Bool { h.shop.official == true }
    private var open: Bool { official || h.plan != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if open { planCard } else { intro }
            if open && !launched { checklist }
            if open {
                SettingsGroup {
                    SettingsRow(icon: "storefront.fill", color: Tint.blue, title: "Витрина", sub: "заполнено \(shopFilled) из 6 · обложка, описание, адрес", last: true) { nav.push(.business(.shop)) }
                }
                HStack(spacing: 10) {
                    tile("chart.bar.fill", Tint.violet, "Статистика", "просмотры и избранное") { nav.push(.business(.stats)) }
                    tile("megaphone.fill", Tint.orange, "Продвижение", promoSub) { nav.push(.business(.promo)) }
                }
            }
            SettingsGroup(title: "Доверие покупателей") {
                SettingsRow(icon: "checkmark.shield.fill", color: Tint.green, title: bizTitle, sub: "значок у имени", status: bizStatus) { nav.push(.business(.trust)) }
                SettingsRow(icon: "checkmark.seal.fill", color: Tint.sky, title: "Галочка бренда", sub: "для владельцев товарного знака",
                            status: brandStatus, locked: !bizSent, last: true) { nav.push(.business(bizSent ? .brand : .trust)) }
            }
            if open || !(h.payments ?? []).isEmpty {
                SettingsGroup {
                    SettingsRow(icon: "doc.text.fill", color: Tint.gray, title: "Платежи и чеки", sub: paySub, last: true) { nav.push(.business(.payments)) }
                }
            }
        }
    }

    // Тариф: что подключено и сколько осталось.
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(official ? "Аккаунт" : h.plan?.trial == true ? "Бесплатный период" : "Ваш тариф").font(.on(13)).opacity(0.85)
            Text(official ? "Официальный аккаунт Торганы" : h.plan?.name ?? "").font(.on(22, .heavy))
            Text(official ? "Витрина, статистика и закреплённые — без тарифа" : left).font(.on(13.5)).opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.grad))
    }

    private var left: String {
        guard let p = h.plan else { return "" }
        let days = max(0, Int(ceil((p.until / 1000 - Date().timeIntervalSince1970) / 86400)))
        return "до \(Fmt.day(p.until)) · осталось \(days) \(Fmt.plural(days, "день", "дня", "дней"))"
    }

    // Без тарифа: что даёт магазин; проверка ИП и галочка — бесплатно и без тарифа.
    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "storefront.fill").font(.system(size: 26)).foregroundStyle(T.accent)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(T.accentSoft))
            VStack(spacing: 6) {
                Text("Магазин на Торгане").font(.on(19, .heavy)).foregroundStyle(T.text)
                Text("Объявления бесплатны для всех. Тариф добавляет витрину, статистику и значок «Магазин».")
                    .font(.on(14)).foregroundStyle(T.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                feature("storefront", "Витрина с обложкой и описанием")
                feature("chart.bar", "Статистика и выгрузка в Excel")
                feature("pin", "Закреплённые товары — в «Магазин Про»")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Подключение тарифа в приложении скоро появится").font(.on(12.5)).foregroundStyle(T.faint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .panel(radius: 22)
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.on(14.5, .medium)).foregroundStyle(T.text) } icon: { Image(systemName: icon).foregroundStyle(T.accent) }
    }

    // Чек-лист запуска: тариф, обложка и описание, проверка ИП; галочка — по желанию.
    private var steps: [(title: String, sub: String, done: Bool, to: BizSection?)] {
        let cover = !(h.shop.cover ?? "").isEmpty, about = !(h.shop.about ?? "").isEmpty
        return [
            (official ? "Официальный аккаунт" : "Тариф «\(h.plan?.name ?? "")»", official ? "без срока" : left, true, nil),
            ("Обложка и описание", "витрина", cover && about, .shop),
            ("Подтвердите ИП или компанию", h.biz?.status == "pending" ? "на проверке — обычно за день" : "значок «ИП проверен» · 2 минуты", h.biz?.status == "verified", .trust),
            ("Галочка бренда", "по желанию · нужен товарный знак", app.me?.badges?.tm != nil, bizSent ? .brand : .trust),
        ]
    }
    private var launched: Bool { steps.prefix(3).allSatisfy(\.done) }

    private var checklist: some View {
        let done = steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Запуск магазина").font(.on(17, .heavy)).foregroundStyle(T.text)
                    Text("\(done) из \(steps.count) шагов").font(.on(13)).foregroundStyle(T.muted)
                }
                Spacer()
                Text("\(done * 100 / steps.count)%").font(.on(22, .heavy)).foregroundStyle(T.accent)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            GeometryReader { g in
                Capsule().fill(T.surface).overlay(alignment: .leading) { Capsule().fill(T.accent).frame(width: g.size.width * CGFloat(done) / CGFloat(steps.count)) }
            }
            .frame(height: 6).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                Button { if let to = s.to, !s.done { nav.push(.business(to)) } } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(s.done ? T.goodSoft : i == steps.firstIndex { !$0.done } ? T.accentSoft : T.surface)
                            if s.done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(T.good) }
                            else { Text("\(i + 1)").font(.on(14, .heavy)).foregroundStyle(i == steps.firstIndex { !$0.done } ? T.accent : T.muted) }
                        }
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.on(15, .semibold)).foregroundStyle(s.done ? T.muted : T.text).strikethrough(s.done, color: T.faint)
                            Text(s.sub).font(.on(12.5)).foregroundStyle(T.muted)
                        }
                        Spacer(minLength: 6)
                        if !s.done && s.to != nil { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 58).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { T.line.opacity(0.6).frame(height: 1).padding(.leading, 60) }
            }
        }
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    private func tile(_ icon: String, _ color: Color, _ title: String, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.on(15.5, .semibold)).foregroundStyle(T.text)
                    Text(sub).font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shopFilled: Int {
        let s = h.shop
        return [s.cover, s.about, s.address, s.hours, s.site, s.delivery].filter { !($0 ?? "").isEmpty }.count
    }
    private var promoSub: String {
        let n = (h.promotions ?? []).filter { $0.status == "active" }.count
        return n > 0 ? "\(n) \(Fmt.plural(n, "активное", "активных", "активных"))" : "нет активных"
    }
    private var paySub: String {
        let n = (h.payments ?? []).count
        return n > 0 ? "\(n) \(Fmt.plural(n, "платёж", "платежа", "платежей"))" : "чеки приходят на почту"
    }
    private var bizSent: Bool { ["pending", "verified"].contains(h.biz?.status ?? "") }
    private var bizTitle: String { h.biz?.kind == "org" && h.biz?.status == "verified" ? "Компания проверена" : "ИП или компания" }
    private var bizStatus: RowStatus { TrustView.status(of: h.biz) }
    private var brandStatus: RowStatus? {
        if app.me?.badges?.tm != nil { return RowStatus(text: "Готово", tone: .ok) }
        return bizSent ? nil : RowStatus(text: "После ИП", tone: .off)
    }
}

// MARK: - Витрина: обложка, описание, адрес, часы, сайт, доставка; закреплённые

private struct ShopEditView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var about = ""
    @State private var address = ""
    @State private var hours = ""
    @State private var site = ""
    @State private var delivery = ""
    /// nil — обложку не трогали, "" — убрать, имя файла — новая.
    @State private var newCover: String?
    @State private var coverImage: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var filled = false

    private var coverURL: URL? { newCover == "" ? nil : API.shared.media(h.shop.cover) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cover
            LabeledField(label: "О магазине", hint: "Видят покупатели на вашей странице, под именем.") {
                TextField("Что продаёте, гарантия, доставка, самовывоз", text: $about, axis: .vertical).lineLimit(4...12).modifier(InputBox(multiline: true))
            }
            LabeledField(label: "Адрес") { TextField("Город, улица, дом", text: $address).modifier(InputBox()) }
            HStack(alignment: .top, spacing: 10) {
                LabeledField(label: "Часы работы") { TextField("10:00–21:00", text: $hours).modifier(InputBox()) }
                LabeledField(label: "Сайт") { TextField("shop.ru", text: $site).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().modifier(InputBox()) }
            }
            LabeledField(label: "Доставка") { TextField("СДЭК, Почта, курьер по городу", text: $delivery).modifier(InputBox()) }
            if let pinned = h.pinned, !pinned.isEmpty {
                SettingsGroup(title: "Закреплённые — первыми на витрине") {
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { i, p in
                        HStack {
                            Image(systemName: "pin.fill").foregroundStyle(T.accent)
                            Text(p.title).font(.on(15, .medium)).foregroundStyle(T.text).lineLimit(1)
                            Spacer()
                            Button("Открепить") { Task { await unpin(p.id) } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).frame(height: 50)
                        .overlay(alignment: .bottom) { if i < pinned.count - 1 { T.line.frame(height: 1).padding(.leading, 14) } }
                    }
                }
            }
            Button { Task { await save() } } label: { if saving { ProgressView().tint(.white) } else { Text("Сохранить") } }
                .buttonStyle(TButton(kind: .accent, height: 52)).disabled(saving || uploading)
            Button { if let id = app.me?.id { nav.push(.user(id)) } } label: { Label("Как видят покупатели", systemImage: "eye") }
                .buttonStyle(TButton(kind: .soft, height: 48))
        }
        .onAppear {
            guard !filled else { return }
            filled = true
            about = h.shop.about ?? ""; address = h.shop.address ?? ""; hours = h.shop.hours ?? ""; site = h.shop.site ?? ""; delivery = h.shop.delivery ?? ""
        }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Широкая обложка не должна раздвигать страницу: размер задаёт пустая рамка, картинка — поверх неё.
        return Color.clear.frame(maxWidth: .infinity).frame(height: 150)
        .overlay {
            if let coverImage { Image(uiImage: coverImage).resizable().scaledToFill() }
            else if let coverURL { RemoteImage(url: coverURL) }
            else { T.gradSoft.overlay(Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(T.accent.opacity(0.6))) }
        }
        .clipShape(shape)
        .overlay { if uploading { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.3)).clipShape(shape) } }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                if coverURL != nil || coverImage != nil {
                    Button { newCover = ""; coverImage = nil } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.danger).frame(width: 34, height: 34).background(Circle().fill(T.card))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Убрать обложку")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Обложка", systemImage: "camera").font(.on(13, .semibold)).foregroundStyle(T.text)
                        .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.card))
                }
            }
            .padding(10)
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
            newCover = try await Uploader.upload(img)
            coverImage = img
        } catch { app.show((error as? APIError)?.message ?? "Не получилось загрузить фото", bad: true) }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: JSONValue] = ["about": .string(about), "address": .string(address), "hours": .string(hours), "site": .string(site), "delivery": .string(delivery)]
        if let newCover { body["cover"] = .string(newCover) }
        do {
            let _: JSONValue = try await API.shared.send("PUT", "/api/my/shop", body: body)
            newCover = nil; coverImage = nil
            await BizStore.shared.load()
            await app.refreshMe()
            Haptics.play("success")
            app.show("Витрина сохранена")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось сохранить", bad: true) }
    }

    private func unpin(_ id: Int) async {
        do {
            let _: JSONValue = try await API.shared.send("PUT", "/api/my/shop/pins", body: ["id": JSONValue.number(Double(id)), "pin": .bool(false)])
            await BizStore.shared.load()
            app.show("Откреплено")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// MARK: - Доверие: как видят покупатели, проверка ИП или компании, переход к галочке

private struct TrustView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var name = ""
    @State private var inn = ""
    @State private var ogrn = ""
    @State private var busy = false

    static func status(of b: BizCheck?) -> RowStatus {
        switch b?.status {
        case "verified": return RowStatus(text: "Готово", tone: .ok)
        case "pending": return RowStatus(text: "На проверке", tone: .wait)
        case "rejected": return RowStatus(text: "Исправить", tone: .bad)
        default: return RowStatus(text: "Не начато", tone: .off)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preview
            switch h.biz?.status {
            case "verified": verified
            case "pending": pending
            default: form
            }
            SettingsGroup {
                SettingsRow(icon: "checkmark.seal.fill", color: Tint.sky, title: "Галочка бренда",
                            sub: sent ? "для владельцев товарного знака" : "после отправки данных ИП или компании",
                            status: app.me?.badges?.tm != nil ? RowStatus(text: "Готово", tone: .ok) : nil, locked: !sent, last: true) {
                    if sent { nav.push(.business(.brand)) }
                }
            }
        }
        .onAppear { if name.isEmpty, let b = h.biz { name = b.name ?? ""; inn = b.inn ?? ""; ogrn = b.ogrn ?? "" } }
    }

    private var sent: Bool { ["pending", "verified"].contains(h.biz?.status ?? "") }

    // Как значки выглядят у имени.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Так видят покупатели").font(.on(13)).foregroundStyle(T.muted)
            HStack(spacing: 12) {
                Avatar(name: app.me?.name ?? "", url: app.me?.avatar, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.me?.name ?? "").font(.on(16, .heavy)).foregroundStyle(T.text)
                        if app.me?.badges?.tm != nil || app.me?.badges?.official == true { Verified(size: 17) }
                    }
                    if h.biz?.status == "verified" {
                        Label(h.biz?.kind == "org" ? "Компания проверена" : "ИП проверен", systemImage: "checkmark.shield.fill")
                            .font(.on(13, .semibold)).foregroundStyle(T.good)
                    } else {
                        Text("значков пока нет").font(.on(13)).foregroundStyle(T.faint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
    }

    private var verified: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundStyle(T.good)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(h.biz?.name ?? "") — \(h.biz?.kind == "org" ? "компания проверена" : "ИП проверен")").font(.on(15, .bold)).foregroundStyle(T.text)
                Text("ИНН \(h.biz?.inn ?? "") · значок стоит у вашего имени").font(.on(13)).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.goodSoft))
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(h.biz?.name ?? "") — на проверке", systemImage: "clock.fill").font(.on(15, .bold)).foregroundStyle(T.text)
            Text("Отправлено \(Fmt.day(h.biz?.at)). Обычно проверяем за день — пришлём уведомление.").font(.on(13.5)).foregroundStyle(T.text2)
            Button("Отозвать заявку") { Task { await withdraw() } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.warnSoft))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ИП или компания").font(.on(18, .heavy)).foregroundStyle(T.text)
                Text("Сверим с ЕГРЮЛ или ЕГРИП — у имени появится значок «ИП проверен» или «Компания проверена».")
                    .font(.on(13.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            if h.biz?.status == "rejected", let note = h.biz?.note, !note.isEmpty {
                Label(note, systemImage: "exclamationmark.circle.fill").font(.on(14, .semibold)).foregroundStyle(T.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            }
            LabeledField(label: "Название") { TextField("ИП Иванов И. И. или ООО «Ромашка»", text: $name).modifier(InputBox()) }
            HStack(alignment: .top, spacing: 10) {
                LabeledField(label: "ИНН") { TextField("10 или 12 цифр", text: $inn).keyboardType(.numberPad).modifier(InputBox()) }
                LabeledField(label: "ОГРН или ОГРНИП") { TextField("13 или 15 цифр", text: $ogrn).keyboardType(.numberPad).modifier(InputBox()) }
            }
            Text("ИНН видит только модератор.").font(.on(12.5)).foregroundStyle(T.muted)
            Button { Task { await send() } } label: { if busy { ProgressView().tint(T.onInk) } else { Text("Отправить на проверку") } }
                .buttonStyle(TButton(kind: .dark, height: 52)).disabled(busy)
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            let _: JSONValue = try await API.shared.post("/api/me/business", ["name": name, "inn": inn, "ogrn": ogrn])
            await BizStore.shared.load()
            Haptics.play("success")
            app.show("Отправлено на проверку")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось отправить", bad: true) }
    }

    private func withdraw() async {
        do {
            let _: JSONValue = try await API.shared.send("DELETE", "/api/me/business", body: Optional<[String: String]>.none)
            await BizStore.shared.load()
            await app.refreshMe()
            app.show("Заявка отозвана")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// MARK: - Галочка бренда: номер свидетельства, название, срок, документы (видит только модератор)

private struct BrandView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @State private var d: TrademarkResponse?
    @State private var number = ""
    @State private var name = ""
    @State private var until = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    @State private var importing: String?
    @State private var busy = false
    @State private var letterOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Для владельцев товарного знака из реестра Роспатента. Галочка стоит рядом с именем везде на Торгане.")
                .font(.on(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if let d {
                if d.trademark?.live == true { live(d) }
                else if d.trademark?.status == "pending" { pending(d) }
                else { form(d) }
            } else { LoadingView() }
        }
        .task { await load() }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }), allowedContentTypes: [.pdf, .jpeg, .png, .webP]) { r in
            let kind = importing
            if case .success(let url) = r, let kind { Task { await upload(url, kind: kind) } }
        }
    }

    private func live(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Verified(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("«\(d.trademark?.name ?? "")» — бренд подтверждён").font(.on(15, .bold)).foregroundStyle(T.text)
                    Text("Свидетельство № \(d.trademark?.number ?? "") · действует до \(Fmt.day(d.trademark?.until))").font(.on(13)).foregroundStyle(T.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.accentSoft))
            Button("Убрать галочку") { Task { await withdraw("Галочка убрана") } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
    }

    private func pending(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("«\(d.trademark?.name ?? "")», № \(d.trademark?.number ?? "") — на проверке", systemImage: "clock.fill").font(.on(15, .bold)).foregroundStyle(T.text)
                Text("Модератор сверит реестр Роспатента и документы. Пока заявка на проверке, её нельзя менять.").font(.on(13.5)).foregroundStyle(T.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.warnSoft))
            docs(d, locked: true)
            Button("Отозвать заявку") { Task { await withdraw("Заявка отозвана") } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
    }

    private func form(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tm = d.trademark, tm.status == "rejected", let note = tm.note, !note.isEmpty {
                Label(note, systemImage: "exclamationmark.circle.fill").font(.on(14, .semibold)).foregroundStyle(T.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            } else if d.trademark?.status == "verified" {
                Label("Срок регистрации истёк — галочка снята. Продлите её в Роспатенте и отправьте заново.", systemImage: "exclamationmark.circle.fill")
                    .font(.on(14, .semibold)).foregroundStyle(T.danger).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            }
            LabeledField(label: "Номер свидетельства") { TextField("Например, 912345", text: $number).keyboardType(.numberPad).modifier(InputBox()) }
            LabeledField(label: "Название бренда, как в свидетельстве") { TextField("Например, ЯБЛОКОФФ", text: $name).modifier(InputBox()) }
            LabeledField(label: "Действует до") {
                DatePicker("", selection: $until, in: Date()..., displayedComponents: .date).labelsHidden().environment(\.locale, Locale(identifier: "ru_RU"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            docs(d, locked: false)
            Button { Task { await send() } } label: { if busy { ProgressView().tint(T.onInk) } else { Text("Отправить на проверку") } }
                .buttonStyle(TButton(kind: .dark, height: 52)).disabled(busy)
        }
    }

    // Документы: свидетельство и письмо с кодом — обязательны, доверенность — если подписывает не руководитель.
    private func docs(_ d: TrademarkResponse, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ДОКУМЕНТЫ · ВИДИТ ТОЛЬКО МОДЕРАТОР").font(.on(12, .semibold)).kerning(0.5).foregroundStyle(T.muted).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(["cert", "letter", "power"].enumerated()), id: \.offset) { i, kind in
                    let have = d.docs.filter { $0.kind == kind }
                    HStack(spacing: 12) {
                        Image(systemName: have.isEmpty ? "doc.badge.plus" : "doc.text.fill").font(.system(size: 17)).foregroundStyle(have.isEmpty ? T.muted : T.good)
                            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(have.isEmpty ? T.surface : T.goodSoft))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind == "letter" ? "Письмо с кодом \(d.code ?? "")" : d.kinds[kind] ?? kind).font(.on(14.5, .semibold)).foregroundStyle(T.text)
                            Text(have.isEmpty ? (kind == "power" ? "если подписывает не руководитель" : "обязательно") : have.map { $0.name ?? "файл" }.joined(separator: ", "))
                                .font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if !locked {
                            if let doc = have.first {
                                Button("Удалить") { Task { await remove(doc.id) } }.font(.on(13.5, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
                            } else {
                                Button("Добавить") { importing = kind }.font(.on(13.5, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 58)
                    .overlay(alignment: .bottom) { if i < 2 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 60) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            if !locked, let letter = d.letter {
                DisclosureGroup(isExpanded: $letterOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(letter).font(.on(13.5)).foregroundStyle(T.text2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button { UIPasteboard.general.string = letter; app.show("Текст скопирован") } label: { Label("Скопировать текст", systemImage: "doc.on.doc") }
                            .font(.on(14, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                } label: { Text("Текст письма — распечатать, подписать, сфотографировать").font(.on(14, .semibold)).foregroundStyle(T.text) }
                .tint(T.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
            }
        }
    }

    private func load() async {
        do {
            let r: TrademarkResponse = try await API.shared.get("/api/me/trademark")
            d = r
            if let tm = r.trademark, number.isEmpty {
                number = tm.number ?? ""; name = tm.name ?? ""
                if let u = tm.until, u > Date().timeIntervalSince1970 * 1000 { until = Date(timeIntervalSince1970: u / 1000) }
            }
        } catch is CancellationError {} catch { app.show((error as? APIError)?.message ?? "Не удалось загрузить", bad: true) }
    }

    private func upload(_ url: URL, kind: String) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { app.show("Не получилось открыть файл", bad: true); return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            let _: JSONValue = try await API.shared.post("/api/me/verify-docs", ["kind": kind, "name": url.lastPathComponent, "data": "data:\(mime);base64,\(data.base64EncodedString())"])
            await load()
        } catch { app.show((error as? APIError)?.message ?? "Не получилось загрузить", bad: true) }
    }

    private func remove(_ id: Int) async {
        do { let _: JSONValue = try await API.shared.send("DELETE", "/api/me/verify-docs/\(id)", body: Optional<[String: String]>.none); await load() }
        catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        do {
            let _: JSONValue = try await API.shared.post("/api/me/trademark", ["number": number, "name": name, "until": f.string(from: until)])
            await load()
            Haptics.play("success")
            app.show("Отправлено на проверку")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось отправить", bad: true) }
    }

    private func withdraw(_ done: String) async {
        do {
            let _: JSONValue = try await API.shared.send("DELETE", "/api/me/trademark", body: Optional<[String: String]>.none)
            await load()
            await app.refreshMe()
            app.show(done)
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// MARK: - Статистика магазина: 7/30/90 дней, график просмотров, лучшие объявления, выгрузка в Excel

private struct StatsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var days = "30"
    @State private var s: ShopStats?
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Seg(items: [("7", "7 дней"), ("30", "30 дней"), ("90", "90 дней")], value: $days)
            if let s {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metric("Показы в ленте", s.totals.impressions, s.prev.impressions)
                    metric("Просмотры", s.totals.views, s.prev.views)
                    metric("В избранное", s.totals.favs, s.prev.favs)
                    metric("Объявлений", s.active ?? 0, nil)
                }
                Chart(Array(s.daily.enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("День", d.day), y: .value("Просмотры", d.views)).foregroundStyle(T.accent).cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                .frame(height: 150)
                .panel(radius: 20, padding: 14)
                if !s.listings.isEmpty {
                    SettingsGroup(title: "Лучшие объявления") {
                        ForEach(Array(s.listings.prefix(5).enumerated()), id: \.element.id) { i, l in
                            Button { nav.push(.listing(l.id)) } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: API.shared.media(l.photo)).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(l.title).font(.on(14.5, .semibold)).foregroundStyle(T.text).lineLimit(1)
                                        Text("\(Fmt.number(l.views)) \(Fmt.plural(l.views, "просмотр", "просмотра", "просмотров")) · \(l.favs) в избранном").font(.on(12.5)).foregroundStyle(T.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14).frame(minHeight: 60).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { if i < min(5, s.listings.count) - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 70) } }
                        }
                    }
                }
                Button { Task { await export() } } label: {
                    if exporting { ProgressView() } else { Label("Выгрузить в Excel", systemImage: "tablecells") }
                }
                .buttonStyle(TButton(kind: .soft, height: 48)).disabled(exporting)
            } else { LoadingView() }
        }
        .task(id: days) { await load() }
    }

    // Плитка: число, стрелка вверх (зелёная) или вниз (красная) с процентом и «было N за прошлую неделю» — как на сайте.
    private func metric(_ title: String, _ n: Int, _ prev: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.on(12.5)).foregroundStyle(T.muted)
            Text(Fmt.number(n)).font(.on(22, .heavy)).foregroundStyle(T.text)
            if let prev {
                TrendBadge(now: n, was: prev)
                Text("было \(Fmt.number(prev)) \(Self.past[days] ?? "раньше")").font(.on(11.5)).foregroundStyle(T.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("активных сейчас").font(.on(11.5)).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .panel(radius: 18, padding: 14)
    }
    private static let past = ["7": "за прошлую неделю", "30": "за прошлые 30 дней", "90": "за прошлые 90 дней"]

    private func load() async {
        do { s = try await API.shared.get("/api/my/shop/stats", query: ["days": days]) }
        catch is CancellationError {} catch { app.show((error as? APIError)?.message ?? "Не удалось загрузить", bad: true) }
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        do {
            let data = try await API.shared.data("/api/my/shop/stats.csv", query: ["days": days])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("torgana-stats-\(days).csv")
            try data.write(to: url)
            Bridge.present([url])
        } catch { app.show((error as? APIError)?.message ?? "Не получилось выгрузить", bad: true) }
    }
}

// MARK: - Продвижение и платежи

private struct PromoList: View {
    let items: [Promotion]
    @EnvironmentObject private var nav: Nav

    var body: some View {
        if items.isEmpty {
            EmptyState(icon: "megaphone", title: "Продвижений пока не было", text: "Продвинутое объявление стоит в блоке «Реклама» над поиском в вашем городе.")
        } else {
            SettingsGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                    Button { if let id = p.listingId { nav.push(.listing(id)) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.title).font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                                Spacer(minLength: 6)
                                let st = Self.status(p.status)
                                Text(st.text).font(.on(12, .bold)).foregroundStyle(st.tone.ink).padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(st.tone.fill))
                            }
                            Text(line(p)).font(.on(13)).foregroundStyle(T.muted)
                        }
                        .padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { if i < items.count - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 14) } }
                }
            }
        }
    }

    static func status(_ s: String) -> RowStatus {
        switch s {
        case "active": return RowStatus(text: "Продвигается", tone: .ok)
        case "stopped": return RowStatus(text: "Остановлено", tone: .bad)
        default: return RowStatus(text: "Завершено", tone: .off)
        }
    }

    private func line(_ p: Promotion) -> String {
        if p.status == "stopped" { return p.note ?? "остановлено модератором" }
        let stats = "показов \(Fmt.number(p.shows ?? 0)) · переходов \(Fmt.number(p.clicks ?? 0))"
        return p.status == "active" ? "до \(Fmt.day(p.endsAt)) · \(stats)" : stats
    }
}

private struct PaymentList: View {
    let items: [Payment]
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                EmptyState(icon: "doc.text", title: "Платежей пока не было")
            } else {
                SettingsGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.on(14.5, .semibold)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
                                Text([Fmt.day(p.createdAt), p.method ?? "", (p.refunded ?? 0) > 0 ? "возвращено \(Fmt.price(p.refunded))" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.on(12.5)).foregroundStyle(T.muted)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Fmt.price(p.amount)).font(.on(14.5, .bold)).foregroundStyle(T.text)
                                let st = Self.status(p.status)
                                Text(st.text).font(.on(11.5, .bold)).foregroundStyle(st.tone.ink).padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(st.tone.fill))
                            }
                        }
                        .padding(14)
                        .overlay(alignment: .bottom) { if i < items.count - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 14) } }
                    }
                }
            }
            Text("Кассовые чеки приходят на \(app.me?.email ?? "вашу почту") от ЮKassa.").font(.on(13)).foregroundStyle(T.muted).padding(.horizontal, 4)
        }
    }

    static func status(_ s: String) -> RowStatus {
        switch s {
        case "succeeded": return RowStatus(text: "Оплачен", tone: .ok)
        case "pending": return RowStatus(text: "Ждёт оплаты", tone: .wait)
        case "canceled": return RowStatus(text: "Не оплачен", tone: .off)
        default: return RowStatus(text: "Ошибка", tone: .bad)
        }
    }
}

/// Стрелка вверх (зелёная), вниз (красная) или вправо (без изменений) и процент к прошлому периоду.
private struct TrendBadge: View {
    let now: Int
    let was: Int

    private var tone: RowStatus.Tone { now == was ? .off : now > was ? .ok : .bad }
    private var icon: String { now == was ? "arrow.right" : now > was ? "arrow.up" : "arrow.down" }
    private var label: String {
        if now == was { return "0%" }
        guard was > 0 else { return "новое" }
        let pct = (Double(now) - Double(was)) / Double(was) * 100
        return "\(abs(Int(pct.rounded())))%"
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy))
            Text(label).font(.on(12.5, .heavy))
        }
        .foregroundStyle(tone.ink)
        .padding(.leading, 6).padding(.trailing, 8).frame(height: 22)
        .background(Capsule().fill(tone.fill))
    }
}
