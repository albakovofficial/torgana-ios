import SwiftUI

// Избранное: объявления, отмеченные сердечком. Гостю — предложение войти.
struct FavoritesView: View {
    @EnvironmentObject private var app: AppState
    @State private var items: [ListingCard] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Избранное").font(.on(30, .heavy)).foregroundStyle(T.text).padding(.top, 8)
                if app.me == nil {
                    EmptyState(icon: "heart", title: "Сохраняйте понравившееся", text: "Войдите, чтобы отмечать объявления сердечком и узнавать, когда они дешевеют.", button: "Войти") { app.needLogin = true }
                        .panel()
                } else if loading && items.isEmpty {
                    LoadingView()
                } else if let error, items.isEmpty {
                    EmptyState(icon: "wifi.slash", title: "Не загрузилось", text: error, button: "Повторить") { Task { await load() } }
                } else if shown.isEmpty {
                    EmptyState(icon: "heart", title: "Пока пусто", text: "Нажмите на сердечко у объявления — оно появится здесь.").panel()
                } else {
                    ListingGrid(items: shown)
                }
            }
            .padding(.horizontal, 16)
            TabBarSpace()
        }
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
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
