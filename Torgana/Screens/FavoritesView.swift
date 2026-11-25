import SwiftUI

// Избранное: объявления, отмеченные сердечком. Гостю — предложение войти.
struct FavoritesView: View {
    @EnvironmentObject private var app: AppState
    @State private var items: [ListingCard] = []
    @State private var loading = true
    @State private var error: String?

    @EnvironmentObject private var nav: Nav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Избранное").font(.on(22, .bold)).foregroundStyle(T.text).padding(.top, 24)
                if loading && items.isEmpty {
                    LoadingView()
                } else if let error, items.isEmpty {
                    EmptyState(title: "Не загрузилось", text: error, button: "Повторить") { Task { await load() } }
                } else if shown.isEmpty {
                    EmptyState(title: "Пока пусто", text: "Нажимайте на сердечко у объявлений, чтобы сохранить их здесь.", button: "Смотреть объявления") { nav.open(path: "/") }
                } else {
                    ListingGrid(items: shown)
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await load() }
        .task(id: app.me?.id) { await load() }
        .onChange(of: app.favs) { _, _ in Task { await load() } }
    }

    /// Убранное сердечком пропадает сразу, не дожидаясь сервера.
    private var shown: [ListingCard] { items.filter { app.favs[$0.id] != false } }

    private func load() async {
        guard app.me != nil else { items = []; loading = false; return }
        do {
            let r: ItemsPage = try await API.shared.get("/api/favorites")
            items = r.items
            error = nil
        } catch {
            self.error = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }
}
