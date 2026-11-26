import SwiftUI
import PhotosUI

// Данные формы объявления и всё, что с ними делается: загрузка для правки, фото, заполнение по фото (ИИ),
// проверка шагов, название из характеристик, отправка. Экран (EditorView и шаги) только показывает и вызывает.
@MainActor
final class EditorModel: ObservableObject {
    let editId: Int?

    @Published var photos: [EditorPhoto] = []
    @Published var category = ""
    @Published var sub = ""
    @Published var attrs: [String: String] = [:]
    @Published var title = ""
    @Published var text = ""
    @Published var price = ""
    @Published var priceUnit = ""
    @Published var condition = ""
    @Published var city = ""
    @Published var delivery = false
    @Published var bargain = true
    @Published var exchange = false
    @Published private(set) var busy = false
    @Published private(set) var loaded = false
    /// Объявление для изменения не загрузилось — экран с «Повторить» вместо пустой формы.
    @Published private(set) var loadError: String?
    @Published private(set) var aiBusy = false
    @Published var done: Int?
    @Published private(set) var step = 0
    @Published var stepError: String?
    /// После «Изменить» в превью — к какому полю прокрутить.
    @Published var jump: String?
    /// Категория выбрана, но список категорий снова открыт («Изменить»).
    @Published var pickingCat = false
    @Published private(set) var autoName = ""
    private var aiTried = false

    static let stepCount = 3

    struct EditorPhoto: Identifiable, Equatable {
        let id = UUID()
        var image: UIImage?
        var url: URL?
        var file: String?
        var failed = false
    }

    init(editId: Int?) { self.editId = editId }

    private var app: AppState { AppState.shared }
    var subs: [Subcategory] { app.config?.subs(category) ?? [] }
    var fields: [FieldDef] { subs.first { $0.id == sub }?.fields ?? [] }
    var autoTitle: Bool { subs.first { $0.id == sub }?.auto == true }
    var stepTitle: String { [editId == nil ? "Новое объявление" : "Редактирование", "Что продаёте", "Всё верно?"][step] }
    /// Фото ещё грузятся — отправлять нельзя.
    var uploading: Bool { photos.contains { $0.file == nil && !$0.failed } }

    // MARK: шаги

    /// Переход между шагами: вперёд — только если на текущем всё обязательное заполнено (как «Далее» на сайте).
    func go(_ to: Int) {
        if to > step, let e = problem(upTo: to) { stepError = e; Haptics.play("error"); return }
        stepError = nil
        withAnimation(.easeOut(duration: 0.2)) { step = max(0, min(Self.stepCount - 1, to)) }
        if step == Self.stepCount - 1 { Task { await loadAutoName() } }
    }

    private func problem(upTo to: Int) -> String? {
        if uploading { return "Подождите, фото ещё загружаются" }
        guard to >= 2 else { return nil }
        if category.isEmpty { return "Выберите категорию" }
        if !subs.isEmpty && sub.isEmpty { return "Выберите раздел" }
        if !autoTitle && title.trimmingCharacters(in: .whitespaces).isEmpty { return "Напишите название" }
        if let f = fields.first(where: { $0.req == true && (attrs[$0.key] ?? "").isEmpty }) { return "Укажите «\(f.label)» — это главная характеристика раздела" }
        if city.isEmpty { return "Укажите город" }
        return nil
    }

    /// «Изменить» в превью: фото — шаг 1, цена и описание — шаг 2 сразу у нужного поля.
    func edit(_ f: ListingView.Field) {
        switch f {
        case .photos: go(0)
        case .price: jump = "price"; go(1)
        case .text: jump = "text"; go(1)
        }
    }

    // MARK: категория и характеристики

    func pick(category id: String) {
        if category != id { category = id; sub = ""; attrs = [:] }
        if subs.isEmpty { pickingCat = false }
    }

    func pick(sub id: String) {
        if sub != id { sub = id; attrs = [:] }
        pickingCat = false
    }

    /// Варианты для выбора с поиском: длинный список (больше 12) или модели выбранной марки; nil — обычное поле.
    func listOptions(_ f: FieldDef) -> [String]? {
        if f.type == "select", let o = f.options, o.count > 12 { return o }
        if f.type == "text", f.fixed == true, let list = f.suggest?[attrs["brand"] ?? ""], !list.isEmpty { return list }
        return nil
    }

    /// Сменили марку — модель другой марки сбрасываем.
    func setAttr(_ key: String, _ v: String) {
        attrs[key] = v
        guard key == "brand", let m = fields.first(where: { $0.key == "model" && $0.fixed == true }) else { return }
        if let list = m.suggest?[v], !list.contains(attrs["model"] ?? "") { attrs["model"] = nil }
    }

    func attrBinding(_ f: FieldDef) -> Binding<String> {
        Binding(get: { self.attrs[f.key] ?? "" }, set: { self.setAttr(f.key, $0) })
    }

    /// Характеристики для сервера: числа — числами.
    private var attrsJSON: [String: JSONValue] {
        var a: [String: JSONValue] = [:]
        for f in fields {
            guard let v = attrs[f.key], !v.isEmpty else { continue }
            if f.type == "number", let n = Double(v.replacingOccurrences(of: ",", with: ".").filter({ !$0.isWhitespace })) { a[f.key] = .number(n) } else { a[f.key] = .string(v) }
        }
        return a
    }

    /// Название из характеристик для превью — его же сервер поставит при сохранении.
    private func loadAutoName() async {
        guard autoTitle else { autoName = ""; return }
        struct R: Decodable { let title: String }
        let r: R? = try? await API.shared.post("/api/listings/title", ["subcategory": JSONValue.string(sub), "attrs": .object(attrsJSON)])
        autoName = r?.title ?? ""
    }

    /// Черновик в виде ответа сервера — его рисует ListingView; продавец — вы сами.
    var draftData: ListingResponse {
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
        let seller = app.me.map { Seller(id: $0.id, name: $0.name, avatar: $0.avatar, activeCount: nil,
                                         rep: $0.rep, badges: $0.badges, followers: nil, following: nil) }
        return ListingResponse(listing: l, seller: seller, similar: nil)
    }

    // MARK: фото

    func add(_ items: [PhotosPickerItem]) async {
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
                app.fail(error, "Фото не загрузилось")
            }
        }
    }

    func makeCover(_ p: EditorPhoto) {
        guard let i = photos.firstIndex(of: p) else { return }
        photos.insert(photos.remove(at: i), at: 0)
    }

    func remove(_ p: EditorPhoto) { photos.removeAll { $0.id == p.id } }

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
            if let x = Self.attrText(v) { attrs[k] = x }
        }
        if price.isEmpty, let h = s.priceHint { price = String(h) }
        app.show("Заполнили по фото — проверьте")
    }

    /// Значение характеристики с сервера — как в поле: «2017», «1,6» → «1.6», да/нет — «1»/пусто.
    private static func attrText(_ v: JSONValue) -> String? {
        switch v {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "1" : ""
        default: return nil
        }
    }

    // MARK: загрузка и отправка

    func prefill() async {
        guard !loaded else { return }
        if city.isEmpty { city = app.city }
        if let id = editId {
            loadError = nil
            let l: Listing
            do { l = (try await API.shared.get("/api/listings/\(id)") as ListingResponse).listing } catch is CancellationError { return } catch {
                loadError = error.userMessage()
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
            for (k, v) in l.attrs ?? [:] { if let x = Self.attrText(v) { attrs[k] = x } }
            photos = (l.photos ?? []).map { EditorPhoto(image: nil, url: API.shared.media($0), file: ($0 as NSString).lastPathComponent) }
            aiTried = true
        }
        loaded = true
    }

    func submit() async {
        if let e = problem(upTo: 2) { stepError = e; step = e == "Подождите, фото ещё загружаются" ? 0 : 1; return }
        busy = true
        defer { busy = false }
        let body: [String: JSONValue] = [
            "title": .string(title), "description": .string(text), "category": .string(category), "subcategory": .string(sub),
            "attrs": .object(attrsJSON), "price": price.filter(\.isNumber).isEmpty ? .null : .string(price.filter(\.isNumber)),
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
            stepError = error.userMessage("Не получилось отправить")
            Haptics.play("error")
        }
    }

    /// «Подать ещё» и «Мои объявления» после отправки: форма с начала.
    func reset() {
        photos = []; category = ""; sub = ""; attrs = [:]; title = ""; text = ""; price = ""; priceUnit = ""; condition = ""
        delivery = false; bargain = true; exchange = false; done = nil; aiTried = false; stepError = nil; step = 0
    }

    #if DEBUG
    /// Снимки экрана: «-step 1/2» — открыть шаг с примером объявления.
    func demoStep() {
        let n = UserDefaults.standard.integer(forKey: "step")
        guard n > 0, step == 0, app.config != nil else { return }
        category = "electronics"; sub = "phones"; attrs = ["brand": "Apple", "model": "iPhone 15 Pro", "memory": "256 ГБ"]
        price = "89990"; condition = "used"; city = city.isEmpty ? "Москва" : city
        text = "Телефон в идеальном состоянии, носил в чехле и со стеклом с первого дня. Аккумулятор 98%. Полный комплект: коробка, кабель, чек."
        go(min(n, Self.stepCount - 1))
    }
    #endif
}
