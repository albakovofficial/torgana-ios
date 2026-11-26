import SwiftUI
import PhotosUI

// Подать или изменить объявление в три шага: фото (до 10, первое — обложка); категория, название, характеристики,
// цена, описание, состояние, город; превью страницы объявления с торгом, обменом и доставкой.
// Если подключён ИИ — заполняем по первому фото. Публикуется после проверки модератором (как на сайте).
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
    /// Объявление для изменения не загрузилось — экран с «Повторить» вместо пустой формы.
    @State private var loadError: String?
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
    /// После «Изменить» в превью — к какому полю прокрутить.
    @State private var jump: String?
    @State private var pickingCat = false
    @State private var gridW: CGFloat = 0
    @State private var autoName = ""
    /// Длинный список (марка) или модель из списка марки — выбор с поиском.
    @State private var listField: FieldDef?

    private static let stepCount = 3
    private var stepTitle: String { [editId == nil ? "Новое объявление" : "Редактирование", "Что продаёте", "Всё верно?"][step] }

    private enum Slot { case photo(EditorPhoto), add, empty }

    var body: some View {
        Group {
            if let id = done {
                success(id)
            } else if editId != nil && !loaded {
                editLoading
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
        #if DEBUG
        .onAppear { demoStep() }
        .onChange(of: app.config?.categories.count ?? 0) { _, _ in demoStep() }
        #endif
        .sheet(item: $listField) { f in
            OptionPicker(title: f.label, options: listOptions(f) ?? [], value: Binding(get: { attrs[f.key] ?? "" }, set: { setAttr(f.key, $0) }))
        }
        .sheet(isPresented: $cityPicker) { OptionPicker(title: "Город", options: app.config?.cities ?? [], value: $city) }
    }

    /// Изменение: пока объявление не пришло — загрузка; не пришло — понятная ошибка, а не пустая форма.
    private var editLoading: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: stepTitle) { dismiss() }
            if let loadError {
                LoadFailed(title: "Не открылось", error: loadError, retry: prefill).padding(.top, 8)
            } else { LoadingView() }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    /// Пока заполняют форму, вместо нижнего меню — панель «Далее» / «Опубликовать».
    private func syncDock() { if editId == nil { nav.editorDock = app.me != nil && done == nil } }

    private var subs: [Subcategory] { app.config?.subs(category) ?? [] }
    private var fields: [FieldDef] { subs.first { $0.id == sub }?.fields ?? [] }

    // MARK: шаги (решение 26.11): стрелка и заголовок шага, тонкие полоски, без пояснений; шаг 3 — превью страницы объявления.
    private var wizard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: stepTitle) {
                        if step > 0 { go(step - 1) } else if editId != nil { dismiss() } else { nav.open(path: "/profile/listings") }
                    }
                    .id("top")
                    stepsBar.padding(.top, 12)
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
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                Color.clear.frame(height: 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: step) { _, _ in
                let to = jump ?? "top"
                jump = nil
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(60)); withAnimation { proxy.scrollTo(to, anchor: .top) } }
            }
        }
        .overlay(alignment: .bottom) { dock }
    }

    private var stepsBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { i in
                Capsule().fill(i <= step ? T.accent : Color.dyn(0xE6E9F5, 0x272D3E)).frame(height: 4)
                    .padding(.vertical, 8).contentShape(Rectangle())
                    .onTapGesture { go(i) }
            }
        }
    }

    // Шаг 1: сетка — крупная обложка 2×2, справа и ниже маленькие ячейки; пустые ячейки тоже открывают галерею.
    private var photosStep: some View {
        let cell = max(0, (gridW - 16) / 3)
        var rest: [Slot] = photos.dropFirst().map { .photo($0) }
        if !photos.isEmpty && photos.count < 10 { rest.append(.add) }
        while rest.count < 5 { rest.append(.empty) }
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    if let first = photos.first { thumb(first, cell * 2 + 8) } else { picker { bigAdd(cell * 2 + 8) } }
                    VStack(spacing: 8) { slot(rest[0], cell); slot(rest[1], cell) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                    ForEach(Array(rest.dropFirst(2).enumerated()), id: \.offset) { _, sl in slot(sl, cell) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridW = $0 }
            Text(photos.isEmpty ? "до 10 фото · первое — обложка" : "\(photos.count) из 10 · обложку можно сменить долгим нажатием")
                .font(.on(13)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            if aiBusy { Label("Заполняем по фото…", systemImage: "sparkles").font(.on(14, .semibold)).foregroundStyle(T.accent) }
        }
    }

    private func picker<L: View>(@ViewBuilder _ label: () -> L) -> some View {
        PhotosPicker(selection: $picked, maxSelectionCount: max(1, 10 - photos.count), matching: .images, label: label)
    }

    private func bigAdd(_ size: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera").font(.system(size: 30, weight: .medium))
            Text("Добавить фото").font(.on(16, .bold))
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.accentFill))
    }

    @ViewBuilder private func slot(_ sl: Slot, _ size: CGFloat) -> some View {
        switch sl {
        case .photo(let p): thumb(p, size)
        case .add:
            picker {
                Image(systemName: "camera").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.accentFill))
            }
        case .empty:
            if photos.count < 10 {
                picker {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(T.faint)
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
            } else { Color.clear.frame(width: size, height: size) }
        }
    }

    // Шаг 2: категория (выбрали — сворачивается в строку), название, характеристики, цена, описание, состояние и город.
    private var whatStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            if pickingCat || category.isEmpty || (!subs.isEmpty && sub.isEmpty) { categoryPicker.padding(.bottom, 6) } else { categoryField }
            if !autoTitle {
                box("Название") { TextField("Например: iPhone 15 Pro, 256 ГБ", text: $title).font(.on(16, .semibold)) }
            }
            ForEach(fields, id: \.key) { f in fieldRow(f) }
            box("Цена") {
                HStack {
                    TextField("0", text: $price).keyboardType(.numberPad).font(.on(24, .heavy))
                    Text("₽").font(.on(24, .heavy)).foregroundStyle(T.muted)
                }
            }
            .id("price")
            let units = app.config?.priceUnits ?? []
            if units.count > 1 { Seg(items: units.map { ($0, $0.isEmpty ? "за всё" : "за \($0)") }, value: $priceUnit) }
            box("Описание") {
                TextField("Состояние, комплектация, особенности", text: $text, axis: .vertical).lineLimit(3...14).font(.on(15))
            }
            .id("text")
            FlowLayout(spacing: 8) {
                if !category.isEmpty {
                    Chip(title: "Новое", on: condition == "new") { condition = condition == "new" ? "" : "new" }
                    Chip(title: "Б/у", on: condition == "used") { condition = condition == "used" ? "" : "used" }
                }
                Chip(title: city.isEmpty ? "Город" : city, icon: "mappin", on: !city.isEmpty) { cityPicker = true }
            }
            .padding(.top, 4)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Категория").font(.on(13, .semibold)).foregroundStyle(T.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(app.config?.categories ?? []) { c in
                    let on = category == c.id
                    Button {
                        if category != c.id { category = c.id; sub = ""; attrs = [:] }
                        if subs.isEmpty { pickingCat = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: CatIcon.of(c.id)).font(.system(size: 17)).foregroundStyle(on ? T.accent : T.text2).frame(width: 24)
                            Text(c.name).font(.on(14, .semibold)).foregroundStyle(T.text).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? T.accentSoft : T.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? T.accent : T.line, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !subs.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(subs) { sc in
                        Chip(title: sc.name, on: sub == sc.id) { if sub != sc.id { sub = sc.id; attrs = [:] }; pickingCat = false }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var categoryField: some View {
        Button { pickingCat = true } label: {
            box("Категория") {
                HStack(spacing: 8) {
                    Image(systemName: CatIcon.of(category)).font(.system(size: 15)).foregroundStyle(T.accent)
                    Text([app.config?.category(category)?.name, subs.first { $0.id == sub }?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.on(16, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Изменить").font(.on(14, .semibold)).foregroundStyle(T.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Поле шага 2: белая плашка, подпись мелко сверху, ввод под ней.
    private func box<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.on(12, .medium)).foregroundStyle(T.muted)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    // Шаг 3: страница объявления как у покупателя (ListingView в режиме превью), условия, отправка.
    private var sendStep: some View {
        VStack(spacing: 16) {
            Text("так увидят покупатели").font(.on(13)).foregroundStyle(T.muted)
            ListingView(id: editId ?? 0, draft: .init(data: draftData, images: photos.map(\.image), edit: edit))
            VStack(spacing: 0) {
                toggleRow("Торг", "tag", $bargain)
                toggleRow("Обмен", "arrow.left.arrow.right", $exchange)
                toggleRow("Доставка", "truck.box", $delivery, last: true)
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            Button { nav.push(.doc("rules")) } label: {
                (Text("Проверка модератором — обычно пара часов. Публикуя, вы принимаете ") + Text("правила").foregroundColor(T.accent))
                    .font(.on(12.5)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
        }
    }

    private func toggleRow(_ t: String, _ icon: String, _ on: Binding<Bool>, last: Bool = false) -> some View {
        Toggle(isOn: on) {
            Label(t, systemImage: icon).font(.on(15, .medium)).foregroundStyle(T.text)
        }
        .tint(T.accentFill)
        .padding(.horizontal, 14).frame(height: 50)
        .overlay(alignment: .bottom) { if !last { T.line.frame(height: 1).padding(.leading, 14) } }
    }

    /// Черновик в виде ответа сервера — его рисует ListingView; продавец — вы сами.
    private var draftData: ListingResponse {
        let subName = subs.first { $0.id == sub }?.name
        let specs = fields.compactMap { f -> Spec? in
            guard let v = attrs[f.key], !v.isEmpty else { return nil }
            return Spec(label: f.label, value: [v, f.type == "number" ? f.unit : nil].compactMap { $0 }.joined(separator: " "))
        }
        let name = autoTitle ? autoName : title
        let l = Listing(id: editId ?? 0, title: name.isEmpty ? (subName ?? "Ваше объявление") : name, description: text, category: category, subcategory: sub,
                        price: Int(price.filter(\.isNumber)), priceUnit: priceUnit, priceWas: nil, city: city, metro: nil, district: nil, condition: condition,
                        delivery: delivery, bargain: bargain, exchange: exchange, status: nil, views: nil, favCount: nil,
                        createdAt: Date().timeIntervalSince1970 * 1000, updatedAt: nil, photos: photos.map { $0.url?.absoluteString ?? "" },
                        isFav: nil, isOwner: true, specs: specs, rejectReason: nil, attrs: nil)
        let seller = app.me.map { Seller(id: $0.id, name: $0.name, city: $0.city, avatar: $0.avatar, createdAt: $0.createdAt, activeCount: nil,
                                         rep: $0.rep, badges: $0.badges, followers: nil, following: nil) }
        return ListingResponse(listing: l, seller: seller, similar: nil)
    }

    /// «Изменить» в превью: фото — шаг 1, цена и описание — шаг 2 сразу у нужного поля.
    private func edit(_ f: ListingView.Field) {
        switch f {
        case .photos: go(0)
        case .price: jump = "price"; go(1)
        case .text: jump = "text"; go(1)
        }
    }

    // Нижняя панель: «Далее» (тёмная) / «Опубликовать» (синяя). Назад — стрелкой в шапке.
    private var dock: some View {
        Group {
            if step < Self.stepCount - 1 {
                Button("Далее") { go(step + 1) }.buttonStyle(TButton(kind: .dark, height: 50))
            } else {
                Button { Task { await submit() } } label: {
                    if busy { ProgressView().tint(.white) } else { Text(editId == nil ? "Опубликовать" : "Сохранить") }
                }
                .buttonStyle(TButton(kind: .accent, height: 50))
                .disabled(busy || photos.contains { $0.file == nil && !$0.failed })
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.card.opacity(0.96)).shadow(color: Color(hex: 0x101010).opacity(0.14), radius: 18, y: 12))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    /// Переход между шагами: вперёд — только если на текущем всё обязательное заполнено (как «Далее» на сайте).
    private func go(_ to: Int) {
        if to > step, let e = problem(upTo: to) { stepError = e; Haptics.play("error"); return }
        stepError = nil
        withAnimation(.easeOut(duration: 0.2)) { step = max(0, min(Self.stepCount - 1, to)) }
        if step == Self.stepCount - 1 { Task { await loadAutoName() } }
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

    private var autoTitle: Bool { subs.first { $0.id == sub }?.auto == true }

    /// Название из характеристик для превью — его же сервер поставит при сохранении.
    private func loadAutoName() async {
        guard autoTitle else { autoName = ""; return }
        var a: [String: JSONValue] = [:]
        for f in fields { if let v = attrs[f.key], !v.isEmpty { a[f.key] = f.type == "number" ? Double(v.replacingOccurrences(of: ",", with: ".")).map { .number($0) } ?? .string(v) : .string(v) } }
        struct R: Decodable { let title: String }
        let r: R? = try? await API.shared.post("/api/listings/title", ["subcategory": JSONValue.string(sub), "attrs": .object(a)])
        autoName = r?.title ?? ""
    }

    /// Варианты для выбора с поиском: длинный список (больше 12) или модели выбранной марки; nil — обычное поле.
    private func listOptions(_ f: FieldDef) -> [String]? {
        if f.type == "select", let o = f.options, o.count > 12 { return o }
        if f.type == "text", f.fixed == true, let list = f.suggest?[attrs["brand"] ?? ""], !list.isEmpty { return list }
        return nil
    }

    /// Сменили марку — модель другой марки сбрасываем.
    private func setAttr(_ key: String, _ v: String) {
        attrs[key] = v
        guard key == "brand", let m = fields.first(where: { $0.key == "model" && $0.fixed == true }) else { return }
        if let list = m.suggest?[v], !list.contains(attrs["model"] ?? "") { attrs["model"] = nil }
    }

    @ViewBuilder private func fieldRow(_ f: FieldDef) -> some View {
        let binding = Binding(get: { attrs[f.key] ?? "" }, set: { setAttr(f.key, $0) })
        if listOptions(f) != nil {
            Button { listField = f } label: {
                box(f.label) {
                    HStack {
                        Text(binding.wrappedValue.isEmpty ? "Выберите" : binding.wrappedValue).font(.on(16, .semibold)).foregroundStyle(binding.wrappedValue.isEmpty ? T.faint : T.text)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.muted)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            switch f.type {
            case "select":
                Menu {
                    Picker(f.label, selection: binding) {
                        Text("Не указывать").tag("")
                        ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    box(f.label) {
                        HStack {
                            Text(binding.wrappedValue.isEmpty ? "Выберите" : binding.wrappedValue).font(.on(16, .semibold)).foregroundStyle(binding.wrappedValue.isEmpty ? T.faint : T.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.muted)
                        }
                    }
                }
            case "number":
                box(f.label) {
                    HStack {
                        TextField(f.placeholder ?? "", text: binding).keyboardType(f.step != nil ? .decimalPad : .numberPad).font(.on(16, .semibold))
                        if let u = f.unit { Text(u).foregroundStyle(T.muted) }
                    }
                }
            default:
                box(f.label) { TextField(f.placeholder ?? "", text: binding).font(.on(16, .semibold)) }
            }
        }
    }

    private func thumb(_ p: EditorPhoto, _ size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size > 150 ? 22 : 16, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = p.image { Image(uiImage: img).resizable().scaledToFill() } else { RemoteImage(url: p.url) }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if p.file == nil && !p.failed { ProgressView().tint(.white).frame(width: size, height: size).background(.black.opacity(0.3)).clipShape(shape) }
                if p.failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white).frame(width: size, height: size).background(T.danger.opacity(0.6)).clipShape(shape) }
            }
            .overlay(alignment: .bottomLeading) {
                if photos.first?.id == p.id { Text("Обложка").font(.on(11, .bold)).foregroundStyle(.white).padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(.black.opacity(0.55))).padding(8) }
            }
            .contentShape(.contextMenuPreview, shape)
            .contextMenu {
                if photos.first?.id != p.id { Button { makeCover(p) } label: { Label("Сделать обложкой", systemImage: "star") } }
                Button(role: .destructive) { photos.removeAll { $0.id == p.id } } label: { Label("Удалить", systemImage: "trash") }
            }
            Button { photos.removeAll { $0.id == p.id } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(5)
            .accessibilityLabel("Удалить фото")
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
        if let id = editId {
            loadError = nil
            let l: Listing
            do { l = (try await API.shared.get("/api/listings/\(id)") as ListingResponse).listing } catch is CancellationError { return } catch {
                loadError = error.localizedDescription
                return
            }
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

    #if DEBUG
    /// Снимки экрана: «-step 1/2» — открыть шаг с примером объявления.
    private func demoStep() {
        let n = UserDefaults.standard.integer(forKey: "step")
        guard n > 0, step == 0, app.config != nil else { return }
        category = "electronics"; sub = "phones"; attrs = ["brand": "Apple", "model": "iPhone 15 Pro", "memory": "256 ГБ"]
        price = "89990"; condition = "used"; city = city.isEmpty ? "Москва" : city
        text = "Телефон в идеальном состоянии, носил в чехле и со стеклом с первого дня. Аккумулятор 98%. Полный комплект: коробка, кабель, чек."
        go(min(n, Self.stepCount - 1))
    }
    #endif

    private func reset() {
        photos = []; category = ""; sub = ""; attrs = [:]; title = ""; text = ""; price = ""; priceUnit = ""; condition = ""
        delivery = false; bargain = true; exchange = false; done = nil; aiTried = false; stepError = nil; step = 0
        if editId != nil { dismiss() }
    }
}
