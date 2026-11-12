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
    @State private var error: String?

    struct EditorPhoto: Identifiable, Equatable {
        let id = UUID()
        var image: UIImage?
        var url: URL?
        var file: String?
        var failed = false
    }

    var body: some View {
        Group {
            if app.me == nil {
                EmptyState(icon: "plus.circle", title: "Подайте объявление", text: "Бесплатно и без лимитов. Войдите — и через пару минут объявление уйдёт на проверку.", button: "Войти") { app.needLogin = true }
                    .frame(maxHeight: .infinity)
            } else if let id = done {
                success(id)
            } else {
                form
            }
        }
        .background(T.bg)
        .navigationTitle(editId == nil ? "Новое объявление" : "Изменить объявление")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prefill() }
        .onChange(of: picked) { _, items in Task { await add(items) } }
        .sheet(isPresented: $cityPicker) { CityPicker(city: $city) }
    }

    private var subs: [Subcategory] { app.config?.subs(category) ?? [] }
    private var fields: [FieldDef] { subs.first { $0.id == sub }?.fields ?? [] }

    private var form: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if photos.count < 10 {
                            PhotosPicker(selection: $picked, maxSelectionCount: 10 - photos.count, matching: .images) {
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill").font(.system(size: 22))
                                    Text("Фото").font(.on(13, .semibold))
                                }
                                .foregroundStyle(T.accent)
                                .frame(width: 92, height: 92)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.accentSoft))
                            }
                        }
                        ForEach(photos) { p in thumb(p) }
                    }
                    .padding(.vertical, 4)
                }
                if aiBusy { Label("Заполняем по фото…", systemImage: "sparkles").font(.on(14)).foregroundStyle(T.accent) }
            } header: { Text("Фото") } footer: { Text("До 10 фото. Первое — на обложке, его видно в ленте.") }

            Section("Раздел") {
                Picker("Раздел", selection: $category) {
                    Text("Выберите").tag("")
                    ForEach(app.config?.categories ?? []) { Text($0.name).tag($0.id) }
                }
                .onChange(of: category) { old, _ in if loaded && !old.isEmpty { sub = ""; attrs = [:] } }
                if !subs.isEmpty {
                    Picker("Подраздел", selection: $sub) {
                        Text("Выберите").tag("")
                        ForEach(subs) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: sub) { old, _ in if loaded && !old.isEmpty { attrs = [:] } }
                }
            }

            if !fields.isEmpty {
                Section("Характеристики") {
                    ForEach(fields, id: \.key) { f in fieldRow(f) }
                }
            }

            Section("Описание") {
                TextField(autoTitle ? "Название — соберём из характеристик" : "Название, например «Велосипед Merida»", text: $title)
                TextField("Расскажите о состоянии, комплекте, причине продажи", text: $text, axis: .vertical).lineLimit(4...12)
            }

            Section("Цена") {
                HStack {
                    TextField("Цена, ₽", text: $price).keyboardType(.numberPad)
                    Picker("", selection: $priceUnit) {
                        ForEach(app.config?.priceUnits ?? [""], id: \.self) { Text($0.isEmpty ? "за всё" : "за \($0)").tag($0) }
                    }
                    .labelsHidden()
                }
                Picker("Состояние", selection: $condition) {
                    Text("Не указано").tag("")
                    Text("Новое").tag("new")
                    Text("Б/у").tag("used")
                }
                Toggle("Торг уместен", isOn: $bargain)
                Toggle("Возможен обмен", isOn: $exchange)
            }

            Section("Где") {
                Button { cityPicker = true } label: {
                    HStack {
                        Text("Город").foregroundStyle(T.text)
                        Spacer()
                        Text(city.isEmpty ? "Выберите" : city).foregroundStyle(city.isEmpty ? T.faint : T.muted)
                    }
                }
                Toggle("Есть доставка", isOn: $delivery)
            }

            Section {
                if let error { Text(error).foregroundStyle(T.danger) }
                Button { Task { await submit() } } label: {
                    HStack { Spacer(); if busy { ProgressView().tint(.white) } else { Text(editId == nil ? "Отправить на проверку" : "Сохранить") }; Spacer() }
                }
                .buttonStyle(TButton(kind: .accent))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .disabled(busy || photos.contains { $0.file == nil && !$0.failed })
            } footer: {
                Text("Каждое объявление проверяет модератор — обычно это занимает немного времени. Статус — в «Моих объявлениях».")
            }
            TabBarSpace().listRowBackground(Color.clear)
        }
        .font(.on(16))
        .tint(T.accent)
        .scrollContentBackground(.hidden)
        .background(T.bg)
        .scrollDismissesKeyboard(.interactively)
    }

    private var autoTitle: Bool { ["cars", "moto", "phones", "flats", "flats_rent", "daily", "rooms", "houses", "land", "garages", "commercial"].contains(sub) }

    @ViewBuilder private func fieldRow(_ f: FieldDef) -> some View {
        let binding = Binding(get: { attrs[f.key] ?? "" }, set: { attrs[f.key] = $0 })
        let label = f.label + (f.req == true ? " *" : "")
        switch f.type {
        case "select":
            Picker(label, selection: binding) {
                Text("Выберите").tag("")
                ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
            }
        case "number":
            HStack {
                Text(label).foregroundStyle(T.text)
                Spacer()
                TextField(f.unit ?? "", text: binding).keyboardType(f.step != nil ? .decimalPad : .numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140)
            }
        default:
            TextField(f.placeholder ?? label, text: binding)
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
            Button("Мои объявления") { nav.open(path: "/profile/listings"); reset() }.buttonStyle(TButton(kind: .dark))
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
        error = nil
        guard !category.isEmpty else { error = "Выберите раздел"; return }
        guard !city.isEmpty else { error = "Укажите город"; return }
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
            self.error = (error as? APIError)?.message ?? "Не получилось отправить"
            Haptics.play("error")
        }
    }

    private func reset() {
        photos = []; category = ""; sub = ""; attrs = [:]; title = ""; text = ""; price = ""; priceUnit = ""; condition = ""
        delivery = false; bargain = true; exchange = false; done = nil; aiTried = false; error = nil
        if editId != nil { dismiss() }
    }
}
