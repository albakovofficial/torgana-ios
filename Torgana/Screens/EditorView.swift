import SwiftUI
import PhotosUI

// Подать или изменить объявление: фото (до 10, первое — главное), раздел и подраздел, характеристики подраздела,
// название, описание, цена, состояние, город, доставка, торг, обмен. Если подключён ИИ — заполняем по первому фото.
// Публикуется после проверки модератором (как на сайте).
struct EditorView: View {
    var editId: Int? = nil

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [EditorPhoto] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var category = ""
    @State private var sub = ""
    @State private var attrs: [String: String] = [:]
    @State private var title = ""
    @State private var text = ""
    @State private var price = ""
    @State private var priceUnit = ""
    @State private var condition = ""
    @State private var city = ""
    @State private var delivery = false
    @State private var bargain = true
    @State private var exchange = false
    @State private var busy = false
    @State private var loaded = false
    @State private var aiTried = false
    @State private var aiBusy = false
    @State private var done: Int?
    @State private var cityPicker = false

    struct EditorPhoto: Identifiable, Equatable {
        let id = UUID()
        var image: UIImage?
        var url: URL?
        var file: String?
        var failed = false
    }

    @State private var step = 0
    @State private var stepError: String?

    private static let steps = ["Фото", "Что и сколько", "Отправка"]

    var body: some View {
        Group {
            if app.me == nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PageTitle(text: "Новое объявление", size: 30).padding(.top, 16)
                        EmptyState(title: "Подайте объявление", text: "Бесплатно и без лимитов. Войдите — и через пару минут объявление уйдёт на проверку.", button: "Войти") { app.needLogin = true }
                    }
                    .padding(.horizontal, 20)
                }
            } else if let id = done {
                success(id)
            } else {
                wizard
            }
        }
        .sitePage()
        .task { await prefill() }
        .onAppear { syncDock() }
        .onChange(of: done) { _, _ in syncDock() }
        .onChange(of: app.me?.id) { _, _ in syncDock() }
        .onChange(of: picked) { _, items in Task { await add(items) } }
        .sheet(isPresented: $cityPicker) { CityPicker(city: $city) }
    }

    /// Пока заполняют форму, вместо нижнего меню — панель «Назад / Далее» (как на сайте).
    private func syncDock() { if editId == nil { nav.editorDock = app.me != nil && done == nil } }

    private var subs: [Subcategory] { app.config?.subs(category) ?? [] }
    private var fields: [FieldDef] { subs.first { $0.id == sub }?.fields ?? [] }

    // MARK: шаги
    private var wizard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { if editId != nil { dismiss() } else { nav.open(path: "/profile/listings") } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                            Text(editId == nil ? "Мои объявления" : "К объявлению").font(.on(15, .semibold))
                        }
                        .foregroundStyle(T.text2).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .id("top")
                    PageTitle(text: editId == nil ? "Новое объявление" : "Редактирование", size: 30)
                    Text(editId == nil ? "Бесплатно и без лимитов. Каждое объявление проверяет модератор — обычно это несколько часов."
                         : "После сохранения объявление снова проверит модератор — обычно несколько часов. Пока идёт проверка, его не видно в поиске.")
                        .font(.on(15)).foregroundStyle(T.muted).lineSpacing(4).padding(.top, 10)
                    stepsBar.padding(.top, 22)
                    stepCard.padding(.top, 20).padding(.horizontal, -6)
                }
                .padding(.horizontal, 20)
                Color.clear.frame(height: 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: step) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .overlay(alignment: .bottom) { dock }
    }

    // Полоски шагов: пройденные и текущий — синие, подписи 12 (текущий — жирнее и тёмный).
    private var stepsBar: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<Self.steps.count, id: \.self) { i in
                Button { go(i) } label: {
                    VStack(spacing: 8) {
                        Capsule().fill(i <= step ? T.accent : Color.dyn(0xE6E9F5, 0x272D3E)).frame(height: 5)
                        Text(Self.steps[i]).font(.on(12, i == step ? .bold : .semibold)).foregroundStyle(i == step ? T.text : T.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Карточка шага (.ed-step): белая, обводка, скругление 24; «Шаг N из 3», заголовок 24/800, пояснение 15.
    private var stepCard: some View {
        let head: (String, String) = {
            switch step {
            case 0: return ("Фото и видео", "До 10 фото. Первое фото — обложка в поиске.")
            case 1: return ("Что и сколько", "")
            default: return ("Проверьте и отправьте", editId == nil ? "Так увидят покупатели · 30 дней бесплатно" : "Так увидят покупатели")
            }
        }()
        return VStack(alignment: .leading, spacing: 0) {
            Text("ШАГ \(step + 1) ИЗ \(Self.steps.count)").font(.on(12.5, .heavy)).kerning(0.4).foregroundStyle(T.accent)
            Text(head.0).font(.on(24, .heavy)).foregroundStyle(T.text).padding(.top, 4)
            if !head.1.isEmpty { Text(head.1).font(.on(15)).foregroundStyle(T.muted).padding(.top, 4) }
            if let stepError {
                Label(stepError, systemImage: "exclamationmark.circle").font(.on(14, .semibold)).foregroundStyle(T.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
                    .padding(.top, 14)
            }
            Group {
                switch step {
                case 0: photosStep
                case 1: whatStep
                default: sendStep
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 16).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    // Шаг 1: большая область «Добавьте фото», миниатюры, советы.
    private var photosStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if photos.isEmpty {
                PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "camera").font(.system(size: 26, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.accentFill).shadow(color: T.accentFill.opacity(0.25), radius: 12, y: 10))
                        Text("Добавьте фото").font(.on(17, .bold)).foregroundStyle(T.text)
                        Text("Нажмите, чтобы выбрать · JPG, PNG, HEIC").font(.on(13.5)).foregroundStyle(T.muted).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 34).padding(.horizontal, 20)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(LinearGradient(colors: [Color.dyn(0xFAFAF8, 0x171B27), T.card], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.line2, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(photos) { p in thumb(p) }
                    if photos.count < 10 {
                        PhotosPicker(selection: $picked, maxSelectionCount: 10 - photos.count, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                                Text("Ещё").font(.on(13, .semibold))
                            }
                            .foregroundStyle(T.accent)
                            .frame(width: 92, height: 92)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.accentSoft))
                        }
                    }
                }
            }
            if aiBusy { Label("Заполняем по фото…", systemImage: "sparkles").font(.on(14, .semibold)).foregroundStyle(T.accent) }
            VStack(alignment: .leading, spacing: 10) {
                tip("sparkles", "Светлое фото при дневном свете")
                tip("photo.on.rectangle", "Несколько ракурсов и детали")
                tip("checkmark", "Только ваш товар, без надписей")
            }
        }
    }

    private func tip(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(T.accent).frame(width: 16)
            Text(t).font(.on(13.5)).foregroundStyle(T.text2)
        }
    }

    // Шаг 2: название, категория плитками, раздел, главные характеристики, состояние, цена, условия, город, описание.
    private var whatStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            field("Название" + (autoTitle ? "" : " *"), help: autoTitle ? "Можно не писать — соберём из характеристик." : "Марка, модель и главное — так объявление легче найти.") {
                TextField("Например: iPhone 15 Pro, 256 ГБ", text: $title).modifier(InputBox())
            }
            field("Категория *") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(app.config?.categories ?? []) { c in
                        let on = category == c.id
                        Button { if category != c.id { category = c.id; sub = ""; attrs = [:] } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: CatIcon.of(c.id)).font(.system(size: 17)).foregroundStyle(on ? T.accent : T.text2).frame(width: 24)
                                Text(c.name).font(.on(14, .semibold)).foregroundStyle(T.text).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).frame(height: 58)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? T.accentSoft : T.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? T.accent : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !subs.isEmpty {
                field("Раздел *") {
                    FlowLayout(spacing: 8) {
                        ForEach(subs) { sc in Chip(title: sc.name, on: sub == sc.id) { if sub != sc.id { sub = sc.id; attrs = [:] } } }
                    }
                }
            }
            ForEach(fields, id: \.key) { f in fieldRow(f) }
            if !category.isEmpty {
                field("Состояние") {
                    Seg(items: [("new", "Новое"), ("used", "Б/у"), ("", "Не указывать")], value: $condition)
                }
            }
            field("Цена") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("0", text: $price).keyboardType(.numberPad).font(.on(26, .heavy))
                        Text("₽").font(.on(26, .heavy)).foregroundStyle(T.muted)
                    }
                    .padding(.horizontal, 18).frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(T.line, lineWidth: 1))
                    let units = app.config?.priceUnits ?? []
                    if units.count > 1 { Seg(items: units.map { ($0, $0.isEmpty ? "за всё" : "за \($0)") }, value: $priceUnit) }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                opt("bubble.left.and.bubble.right", "Торг", "Покупатели смогут предложить свою цену", $bargain)
                opt("arrow.triangle.2.circlepath", "Обмен", "Покажем «Обмен» в объявлении и фильтрах", $exchange)
                opt("truck.box", "Доставка", "Отправлю по России", $delivery)
            }
            field("Город *") {
                Button { cityPicker = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin").foregroundStyle(T.muted)
                        Text(city.isEmpty ? "Выберите город" : city).font(.on(16)).foregroundStyle(city.isEmpty ? T.faint : T.text)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
                    }
                    .modifier(InputBox())
                }
                .buttonStyle(.plain)
            }
            field("Описание — по желанию") {
                TextField("Состояние, комплектация, причина продажи, особенности", text: $text, axis: .vertical)
                    .lineLimit(5...14)
                    .modifier(InputBox(multiline: true))
            }
        }
    }

    // Шаг 3: как увидят в поиске, правила, отправка.
    private var sendStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            ListingCardView(item: preview).frame(maxWidth: 200).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                check(!photos.isEmpty, "Фото", photos.isEmpty ? "без фото откликов меньше" : "\(photos.count) шт.")
                check(!category.isEmpty && (subs.isEmpty || !sub.isEmpty), "Раздел", [app.config?.category(category)?.name, subs.first { $0.id == sub }?.name].compactMap { $0 }.joined(separator: " › "))
                check(!price.filter(\.isNumber).isEmpty, "Цена", price.filter(\.isNumber).isEmpty ? "договорная" : Fmt.price(Int(price.filter(\.isNumber)), unit: priceUnit))
                check(!city.isEmpty, "Город", city)
                check(!text.isEmpty, "Описание", text.isEmpty ? "по желанию" : "есть")
            }
            Text("Отправляя, вы принимаете правила размещения.").font(.on(13.5)).foregroundStyle(T.muted)
            Button { nav.push(.doc("rules")) } label: { Text("Правила размещения").font(.on(14, .semibold)).foregroundStyle(T.accent).underline() }.buttonStyle(.plain)
        }
    }

    private func check(_ ok: Bool, _ t: String, _ v: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ok ? T.good : T.faint)
            Text(t).font(.on(14, .semibold)).foregroundStyle(T.text)
            Spacer()
            Text(v).font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
        }
    }

    private var preview: ListingCard {
        ListingCard(id: 0, title: title.isEmpty ? (subs.first { $0.id == sub }?.name ?? "Ваше объявление") : title,
                    price: Int(price.filter(\.isNumber)), priceUnit: priceUnit, priceWas: nil, city: city, metro: nil, category: category, subcategory: sub,
                    summary: nil, photo: nil, createdAt: Date().timeIntervalSince1970 * 1000, isFav: false, goodPrice: nil, delivery: delivery,
                    hasVideo: nil, status: nil, boost: nil, seller: nil)
    }

    // Нижняя панель (.ed-dock): «‹» и «Далее» (тёмная) / «Отправить на проверку» (синяя).
    private var dock: some View {
        HStack(spacing: 8) {
            if step > 0 {
                Button { go(step - 1) } label: { RoundIcon(icon: "chevron.left", size: 48) }.buttonStyle(.plain).accessibilityLabel("Назад")
            }
            if step < Self.steps.count - 1 {
                Button("Далее") { go(step + 1) }.buttonStyle(TButton(kind: .dark, height: 48))
            } else {
                Button { Task { await submit() } } label: {
                    if busy { ProgressView().tint(.white) } else { Text(editId == nil ? "Отправить на проверку" : "Сохранить") }
                }
                .buttonStyle(TButton(kind: .accent, height: 48))
                .disabled(busy || photos.contains { $0.file == nil && !$0.failed })
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.card.opacity(0.96)).shadow(color: Color(hex: 0x101010).opacity(0.14), radius: 18, y: 12))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    /// Переход между шагами: вперёд — только если на текущем всё обязательное заполнено (как «Далее» на сайте).
    private func go(_ to: Int) {
        if to > step, let e = problem(upTo: to) { stepError = e; Haptics.play("error"); return }
        stepError = nil
        withAnimation(.easeOut(duration: 0.2)) { step = max(0, min(Self.steps.count - 1, to)) }
    }

    private func problem(upTo to: Int) -> String? {
        if photos.contains(where: { $0.file == nil && !$0.failed }) { return "Подождите, фото ещё загружаются" }
        guard to >= 2 else { return nil }
        if category.isEmpty { return "Выберите категорию" }
        if !subs.isEmpty && sub.isEmpty { return "Выберите раздел" }
        if !autoTitle && title.trimmingCharacters(in: .whitespaces).isEmpty { return "Напишите название" }
        if let f = fields.first(where: { $0.req == true && (attrs[$0.key] ?? "").isEmpty }) { return "Укажите «\(f.label)» — это главная характеристика раздела" }
        if city.isEmpty { return "Укажите город" }
        return nil
    }

    private func field<C: View>(_ label: String, help: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.on(14, .semibold)).foregroundStyle(T.text)
            content()
            if let help { Text(help).font(.on(13)).foregroundStyle(T.muted) }
        }
    }

    private func opt(_ icon: String, _ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle(); Haptics.play("selection") } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).font(.system(size: 17)).foregroundStyle(T.accent)
                    Spacer()
                    Image(systemName: on.wrappedValue ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(on.wrappedValue ? T.accentFill : T.faint)
                }
                Text(title).font(.on(15, .bold)).foregroundStyle(T.text)
                Text(sub).font(.on(12.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on.wrappedValue ? T.accentSoft : T.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on.wrappedValue ? T.accent : T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var autoTitle: Bool { ["cars", "moto", "phones", "flats", "flats_rent", "daily", "rooms", "houses", "land", "garages", "commercial"].contains(sub) }

    @ViewBuilder private func fieldRow(_ f: FieldDef) -> some View {
        let binding = Binding(get: { attrs[f.key] ?? "" }, set: { attrs[f.key] = $0 })
        let label = f.label + (f.req == true ? " *" : "")
        switch f.type {
        case "select":
            field(label) {
                Menu {
                    Picker(label, selection: binding) {
                        Text("Не указывать").tag("")
                        ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    HStack {
                        Text(binding.wrappedValue.isEmpty ? "Выберите" : binding.wrappedValue).font(.on(16)).foregroundStyle(binding.wrappedValue.isEmpty ? T.faint : T.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.muted)
                    }
                    .modifier(InputBox())
                }
            }
        case "number":
            field(label) {
                HStack {
                    TextField(f.placeholder ?? "", text: binding).keyboardType(f.step != nil ? .decimalPad : .numberPad)
                    if let u = f.unit { Text(u).foregroundStyle(T.muted) }
                }
                .modifier(InputBox())
            }
        default:
            field(label) { TextField(f.placeholder ?? "", text: binding).modifier(InputBox()) }
        }
    }

    private func thumb(_ p: EditorPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = p.image { Image(uiImage: img).resizable().scaledToFill() } else { RemoteImage(url: p.url) }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if p.file == nil && !p.failed { ProgressView().tint(.white).frame(width: 92, height: 92).background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
                if p.failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white).frame(width: 92, height: 92).background(T.danger.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)) }
            }
            .overlay(alignment: .bottomLeading) {
                if photos.first?.id == p.id { Text("Обложка").font(.on(11, .bold)).foregroundStyle(.white).padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(.black.opacity(0.55))).padding(6) }
            }
            .contextMenu {
                if photos.first?.id != p.id { Button { makeCover(p) } label: { Label("Сделать обложкой", systemImage: "star") } }
                Button(role: .destructive) { photos.removeAll { $0.id == p.id } } label: { Label("Удалить", systemImage: "trash") }
            }
            Button { photos.removeAll { $0.id == p.id } } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(5)
        }
    }

    private func makeCover(_ p: EditorPhoto) {
        guard let i = photos.firstIndex(of: p) else { return }
        photos.insert(photos.remove(at: i), at: 0)
    }

    private func success(_ id: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                .frame(width: 84, height: 84).background(Circle().fill(T.grad))
            Text(editId == nil ? "Отправили на проверку" : "Изменения отправлены").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text("Модератор проверит объявление и опубликует его. Мы пришлём уведомление.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Мои объявления") { reset(); nav.open(path: "/profile/listings") }.buttonStyle(TButton(kind: .dark))
            if editId == nil { Button("Подать ещё") { reset() }.buttonStyle(TButton(kind: .soft)) }
        }
        .padding(28)
        .frame(maxHeight: .infinity)
    }

    // MARK: данные
    private func prefill() async {
        guard !loaded else { return }
        if city.isEmpty { city = app.city.isEmpty ? (app.me?.city ?? "") : app.city }
        if let id = editId, let r: ListingResponse = try? await API.shared.get("/api/listings/\(id)") {
            let l = r.listing
            category = l.category ?? ""
            sub = l.subcategory ?? ""
            title = l.title
            text = l.description ?? ""
            price = l.price.map(String.init) ?? ""
            priceUnit = l.priceUnit ?? ""
            condition = l.condition ?? ""
            city = l.city ?? city
            delivery = l.delivery ?? false
            bargain = l.bargain ?? true
            exchange = l.exchange ?? false
            for (k, v) in l.attrs ?? [:] {
                switch v {
                case .string(let s): attrs[k] = s
                case .number(let n): attrs[k] = n == n.rounded() ? String(Int(n)) : String(n)
                case .bool(let b): attrs[k] = b ? "1" : ""
                default: break
                }
            }
            photos = (l.photos ?? []).map { EditorPhoto(image: nil, url: API.shared.media($0), file: ($0 as NSString).lastPathComponent) }
            aiTried = true
        }
        loaded = true
    }

    private func add(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        picked = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { continue }
            let p = EditorPhoto(image: img)
            photos.append(p)
            do {
                let file = try await Uploader.upload(img)
                if let i = photos.firstIndex(where: { $0.id == p.id }) { photos[i].file = file }
                if !aiTried, photos.first?.id == p.id { aiTried = true; Task { await suggest(file) } }
            } catch {
                if let i = photos.firstIndex(where: { $0.id == p.id }) { photos[i].failed = true }
                app.show((error as? APIError)?.message ?? "Фото не загрузилось", bad: true)
            }
        }
    }

    private struct Suggestion: Decodable {
        let title: String?
        let category: String?
        let subcategory: String?
        let description: String?
        let attrs: [String: JSONValue]?
        let priceHint: Int?
    }

    /// ИИ по первому фото: заполняем только пустые поля.
    private func suggest(_ file: String) async {
        guard app.config != nil else { return }
        aiBusy = true
        defer { aiBusy = false }
        guard let s: Suggestion = try? await API.shared.post("/api/ai/suggest", ["file": file]) else { return }
        if category.isEmpty, let c = s.category { category = c }
        if sub.isEmpty, let sc = s.subcategory { sub = sc }
        if title.isEmpty, let t = s.title { title = t }
        if text.isEmpty, let d = s.description { text = d }
        for (k, v) in s.attrs ?? [:] where (attrs[k] ?? "").isEmpty {
            if case .string(let x) = v { attrs[k] = x } else if case .number(let n) = v { attrs[k] = n == n.rounded() ? String(Int(n)) : String(n) }
        }
        if price.isEmpty, let h = s.priceHint { price = String(h) }
        app.show("Заполнили по фото — проверьте")
    }

    private func submit() async {
        if let e = problem(upTo: 2) { stepError = e; step = e == "Подождите, фото ещё загружаются" ? 0 : 1; return }
        busy = true
        defer { busy = false }
        var a: [String: JSONValue] = [:]
        for f in fields {
            guard let v = attrs[f.key], !v.isEmpty else { continue }
            if f.type == "number", let n = Double(v.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }) { a[f.key] = .number(n) } else { a[f.key] = .string(v) }
        }
        let body: [String: JSONValue] = [
            "title": .string(title), "description": .string(text), "category": .string(category), "subcategory": .string(sub),
            "attrs": .object(a), "price": price.filter(\.isNumber).isEmpty ? .null : .string(price.filter(\.isNumber)),
            "priceUnit": .string(priceUnit), "condition": .string(condition), "city": .string(city),
            "delivery": .bool(delivery), "bargain": .bool(bargain), "exchange": .bool(exchange),
            "photos": .array(photos.compactMap { $0.file }.map { JSONValue.string($0) })
        ]
        do {
            if let id = editId {
                _ = try await API.shared.send("PATCH", "/api/listings/\(id)", body: body) as JSONValue
                done = id
            } else {
                let r: IdResult = try await API.shared.post("/api/listings", body)
                done = r.id
            }
            Haptics.play("success")
        } catch {
            stepError = (error as? APIError)?.message ?? "Не получилось отправить"
            Haptics.play("error")
        }
    }

    private func reset() {
        photos = []; category = ""; sub = ""; attrs = [:]; title = ""; text = ""; price = ""; priceUnit = ""; condition = ""
        delivery = false; bargain = true; exchange = false; done = nil; aiTried = false; stepError = nil; step = 0
        if editId != nil { dismiss() }
    }
}
