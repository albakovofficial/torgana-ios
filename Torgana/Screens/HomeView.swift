import SwiftUI

// Главная: поиск, разделы, свежие объявления в городе (как главная сайта).
struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @StateObject private var feed = Feed()
    @State private var category: String?
    @State private var cityPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchBar.padding(.top, 4)
                categories.padding(.top, 14)
                HStack(alignment: .center) {
                    Text(title).font(.on(22, .bold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer()
                    Button("Смотреть все") { nav.push(.search(query)) }
                        .font(.on(15, .semibold)).foregroundStyle(T.text).frame(height: 44)
                }
                .padding(.top, 16)
                FeedView(feed: feed).padding(.top, 14)
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .refreshable { await feed.reload(query) }
        .task(id: query) { await feed.reload(query) }
        .sitePage()
        .sheet(isPresented: $cityPicker) { CityPicker(city: $app.city) }
    }

    private var query: SearchQuery {
        var q = SearchQuery()
        q.city = app.city
        q.category = category ?? ""
        return q
    }

    private var title: String { app.config?.category(category)?.name ?? "Свежие объявления" }

    private var searchBar: some View {
        SearchCapsule(city: app.city, onField: {
            var q = query
            q.focus = true
            nav.push(.search(q))
        }, onCity: { cityPicker = true }, onGo: { nav.push(.search(query)) })
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Все", icon: "list.bullet", on: category == nil) { category = nil }
                ForEach(app.config?.categories ?? []) { c in
                    Chip(title: c.name, icon: CatIcon.of(c.id), on: category == c.id) {
                        category = category == c.id ? nil : c.id
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
}

// Лента с подгрузкой: 24 объявления, следующие — при прокрутке до конца.
@MainActor
final class Feed: ObservableObject {
    @Published var items: [ListingCard] = []
    @Published var total: Int?
    @Published var loading = false
    @Published var error: String?
    private var query = SearchQuery()
    private var done = false
    private var gen = 0

    func reload(_ q: SearchQuery) async {
        query = q
        gen += 1
        done = false
        error = nil
        if items.isEmpty { loading = true }
        await load(reset: true, gen: gen)
    }

    func retry() { Task { await reload(query) } }

    func more() {
        guard !loading, !done, error == nil else { return }
        let g = gen
        Task { await load(reset: false, gen: g) }
    }

    private func load(reset: Bool, gen g: Int) async {
        loading = true
        defer { if g == gen { loading = false } }
        var params = query.params
        params["limit"] = "24"
        params["offset"] = String(reset ? 0 : items.count)
        do {
            let page: ListingsPage = try await API.shared.get("/api/listings", query: params)
            guard g == gen else { return }
            items = reset ? page.items : items + page.items.filter { n in !items.contains { $0.id == n.id } }
            total = page.total
            done = page.items.count < 24
        } catch is CancellationError {
            return
        } catch {
            guard g == gen else { return }
            if reset { items = [] }
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
    }
}

struct FeedView: View {
    @ObservedObject var feed: Feed
    var emptyTitle = "Здесь появятся первые объявления"
    var emptyText = "Разместите своё — это бесплатно и займёт пару минут."

    var body: some View {
        if feed.items.isEmpty {
            if feed.loading { LoadingView() }
            else if let e = feed.error { EmptyState(title: "Не загрузилось", text: e, button: "Повторить") { feed.retry() } }
            else { EmptyState(title: emptyTitle, text: emptyText) }
        } else {
            ListingGrid(items: feed.items) { feed.more() }
            if feed.loading { ProgressView().tint(T.accent).frame(maxWidth: .infinity).padding(.vertical, 20) }
        }
    }
}

// Выбор города: поиск по списку городов сайта и «Вся Россия».
struct CityPicker: View {
    @Binding var city: String
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""

    var body: some View {
        NavigationStack {
            List {
                if q.isEmpty {
                    row("Вся Россия", value: "")
                }
                ForEach(filtered, id: \.self) { row($0, value: $0) }
            }
            .listStyle(.plain)
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Город")
            .navigationTitle("Город")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }

    private var filtered: [String] {
        let all = app.config?.cities ?? []
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? all : all.filter { $0.lowercased().contains(t) }
    }

    private func row(_ title: String, value: String) -> some View {
        Button {
            city = value
            Haptics.play("selection")
            dismiss()
        } label: {
            HStack {
                Text(title).font(.on(17)).foregroundStyle(T.text)
                Spacer()
                if city == value { Image(systemName: "checkmark").foregroundStyle(T.accent).font(.system(size: 15, weight: .bold)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
