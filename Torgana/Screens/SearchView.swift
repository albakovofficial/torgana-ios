import SwiftUI

// Запрос поиска — те же параметры, что у адреса /search на сайте (q, category, sub, city, min, max, sort, a_<поле>…).
struct SearchQuery: Hashable {
    var q = ""
    var category = ""
    var sub = ""
    var city = ""
    var min = ""
    var max = ""
    var sort = ""            // "" — новые, cheap, expensive
    var delivery = false
    var bargain = false
    var exchange = false
    var trusted = false
    var attrs: [String: String] = [:]
    /// Открыть поиск сразу с клавиатурой.
    var focus = false

    init() {}

    init(params p: [String: String]) {
        q = p["q"] ?? ""
        category = p["category"] ?? ""
        sub = p["sub"] ?? ""
        city = p["city"] ?? ""
        min = p["min"] ?? ""
        max = p["max"] ?? ""
        sort = p["sort"] ?? ""
        delivery = p["delivery"] == "1"
        bargain = p["bargain"] == "1"
        exchange = p["exchange"] == "1"
        trusted = p["trusted"] == "1"
        for (k, v) in p where k.hasPrefix("a_") { attrs[k] = v }
    }

    var params: [String: String] {
        var p: [String: String] = [:]
        if !q.isEmpty { p["q"] = q }
        if !category.isEmpty { p["category"] = category }
        if !sub.isEmpty { p["sub"] = sub }
        if !city.isEmpty { p["city"] = city }
        if !min.isEmpty { p["min"] = min }
        if !max.isEmpty { p["max"] = max }
        if !sort.isEmpty { p["sort"] = sort }
        if delivery { p["delivery"] = "1" }
        if bargain { p["bargain"] = "1" }
        if exchange { p["exchange"] = "1" }
        if trusted { p["trusted"] = "1" }
        for (k, v) in attrs where !v.isEmpty { p[k] = v }
        return p
    }

    /// Сколько фильтров включено (для значка на кнопке «Фильтры»).
    var filterCount: Int {
        [!sub.isEmpty, !min.isEmpty || !max.isEmpty, delivery, bargain, exchange, trusted].filter { $0 }.count + attrs.values.filter { !$0.isEmpty }.count
    }

    // focus не влияет на выдачу
    static func == (a: SearchQuery, b: SearchQuery) -> Bool { a.params == b.params }
    func hash(into h: inout Hasher) { h.combine(params) }
}

struct SearchView: View {
    @State var query: SearchQuery
    @EnvironmentObject private var app: AppState
    @StateObject private var feed = Feed()
    @State private var text = ""
    @State private var filters = false
    @State private var cityPicker = false
    @FocusState private var focused: Bool

    init(query: SearchQuery) {
        _query = State(initialValue: query)
        _text = State(initialValue: query.q)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chips
                if let total = feed.total, !feed.items.isEmpty {
                    Text("Найдено \(Fmt.number(total)) \(Fmt.plural(total, "объявление", "объявления", "объявлений"))")
                        .font(.on(14)).foregroundStyle(T.muted)
                }
                FeedView(feed: feed, emptyTitle: "Ничего не нашлось", emptyText: "Попробуйте другие слова, уберите фильтры или выберите всю Россию.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            TabBarSpace()
        }
        .scrollDismissesKeyboard(.immediately)
        .background(T.bg)
        .safeAreaInset(edge: .top, spacing: 0) { searchField }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await feed.reload(query) }
        .task(id: query) { await feed.reload(query) }
        .onAppear { if query.focus { focused = true; query.focus = false } }
        .sheet(isPresented: $filters) { FiltersSheet(query: $query) }
        .sheet(isPresented: $cityPicker) { CityPicker(city: $query.city) }
    }

    private var title: String {
        if !query.sub.isEmpty, let s = app.config?.subs(query.category).first(where: { $0.id == query.sub }) { return s.name }
        return app.config?.category(query.category)?.name ?? "Поиск"
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(T.muted)
                TextField("Что ищете?", text: $text)
                    .font(.on(17))
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { query.q = text.trimmingCharacters(in: .whitespaces) }
                if !text.isEmpty {
                    Button { text = ""; query.q = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(T.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Capsule().fill(T.surface))
            Button { filters = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(query.filterCount > 0 ? .white : T.text)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(query.filterCount > 0 ? AnyShapeStyle(T.grad) : AnyShapeStyle(T.surface)))
                    .overlay(alignment: .topTrailing) {
                        if query.filterCount > 0 {
                            Text("\(query.filterCount)").font(.on(11, .bold)).foregroundStyle(T.accent)
                                .frame(width: 18, height: 18).background(Circle().fill(T.card)).offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Фильтры")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(T.bg)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: query.city.isEmpty ? "Вся Россия" : query.city, icon: "mappin.and.ellipse", on: !query.city.isEmpty) { cityPicker = true }
                Menu {
                    Picker("Сортировка", selection: $query.sort) {
                        Text("Сначала новые").tag("")
                        Text("Сначала дешевле").tag("cheap")
                        Text("Сначала дороже").tag("expensive")
                    }
                } label: {
                    chipLabel(query.sort == "cheap" ? "Дешевле" : query.sort == "expensive" ? "Дороже" : "Новые", icon: "arrow.up.arrow.down", on: !query.sort.isEmpty)
                }
                Chip(title: "С доставкой", icon: "shippingbox", on: query.delivery) { query.delivery.toggle() }
                Chip(title: "Надёжные продавцы", icon: "checkmark.shield", on: query.trusted) { query.trusted.toggle() }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func chipLabel(_ title: String, icon: String, on: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
            Text(title).font(.on(15, .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 16).frame(height: 42)
        .foregroundStyle(on ? T.accent : T.text)
        .background(Capsule().fill(on ? T.accentSoft : T.surface))
        .overlay(Capsule().strokeBorder(on ? T.accent : .clear, lineWidth: 1.5))
    }
}

// Фильтры: раздел, подраздел, цена, характеристики подраздела, доставка/торг/обмен.
struct FiltersSheet: View {
    @Binding var query: SearchQuery
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SearchQuery

    init(query: Binding<SearchQuery>) {
        _query = query
        _draft = State(initialValue: query.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Раздел") {
                    Picker("Раздел", selection: $draft.category) {
                        Text("Все разделы").tag("")
                        ForEach(app.config?.categories ?? []) { Text($0.name).tag($0.id) }
                    }
                    .onChange(of: draft.category) { _, _ in draft.sub = ""; draft.attrs = [:] }
                    let subs = app.config?.subs(draft.category) ?? []
                    if !subs.isEmpty {
                        Picker("Подраздел", selection: $draft.sub) {
                            Text("Все").tag("")
                            ForEach(subs) { Text($0.name).tag($0.id) }
                        }
                        .onChange(of: draft.sub) { _, _ in draft.attrs = [:] }
                    }
                }
                Section("Цена, ₽") {
                    HStack {
                        TextField("от", text: $draft.min).keyboardType(.numberPad)
                        Divider()
                        TextField("до", text: $draft.max).keyboardType(.numberPad)
                    }
                }
                if let sub = app.config?.subs(draft.category).first(where: { $0.id == draft.sub }), let fields = sub.fields, !fields.isEmpty {
                    Section("Характеристики") {
                        ForEach(fields.filter { $0.type == "select" || $0.type == "number" }, id: \.key) { f in
                            if f.type == "select" {
                                Picker(f.label, selection: attr("a_\(f.key)")) {
                                    Text("Любой").tag("")
                                    ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
                                }
                            } else {
                                HStack {
                                    Text(f.label + (f.unit.map { ", \($0)" } ?? "")).foregroundStyle(T.text)
                                    Spacer()
                                    TextField("от", text: attr("a_\(f.key)_min")).keyboardType(.decimalPad).frame(width: 70)
                                    TextField("до", text: attr("a_\(f.key)_max")).keyboardType(.decimalPad).frame(width: 70)
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("С доставкой", isOn: $draft.delivery)
                    Toggle("Торг уместен", isOn: $draft.bargain)
                    Toggle("Возможен обмен", isOn: $draft.exchange)
                    Toggle("Надёжные продавцы", isOn: $draft.trusted)
                }
            }
            .font(.on(16))
            .tint(T.accent)
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Сбросить") { reset() } }
                ToolbarItem(placement: .confirmationAction) { Button("Показать") { query = draft; dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func attr(_ key: String) -> Binding<String> {
        Binding(get: { draft.attrs[key] ?? "" }, set: { draft.attrs[key] = $0 })
    }

    private func reset() {
        let keep = draft
        draft = SearchQuery()
        draft.q = keep.q
        draft.city = keep.city
        draft.category = keep.category
        draft.sort = keep.sort
    }
}
