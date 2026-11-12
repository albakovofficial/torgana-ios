import SwiftUI

// Сообщения: поддержка сверху, ниже — переписки по объявлениям (как список на сайте).
struct MessagesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [ConvItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            Text("Сообщения").font(.on(30, .heavy)).foregroundStyle(T.text)
                .listRowSeparator(.hidden).listRowBackground(T.bg)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            if app.me == nil {
                EmptyState(icon: "message", title: "Переписка с продавцами", text: "Войдите, чтобы писать продавцам и отвечать покупателям.", button: "Войти") { app.needLogin = true }
                    .listRowSeparator(.hidden).listRowBackground(T.bg)
            } else {
                NavigationLink(value: Route.support) { supportRow }
                    .listRowBackground(T.bg)
                    .listRowSeparator(.hidden)
                if loading && items.isEmpty {
                    LoadingView().listRowSeparator(.hidden).listRowBackground(T.bg)
                } else if let error, items.isEmpty {
                    EmptyState(icon: "wifi.slash", title: "Не загрузилось", text: error, button: "Повторить") { Task { await load() } }
                        .listRowSeparator(.hidden).listRowBackground(T.bg)
                } else if items.isEmpty {
                    EmptyState(icon: "bubble.left.and.bubble.right", title: "Пока нет переписок", text: "Напишите продавцу из объявления — переписка появится здесь.")
                        .listRowSeparator(.hidden).listRowBackground(T.bg)
                } else {
                    ForEach(items) { c in
                        NavigationLink(value: Route.chat(c.id)) { ConvRow(c: c) }
                            .listRowBackground(T.bg)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            TabBarSpace().listRowSeparator(.hidden).listRowBackground(T.bg)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task(id: app.me?.id) {
            // Пока список на экране — обновляем раз в 10 секунд.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private var supportRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "headphones")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52).background(Circle().fill(T.grad))
            VStack(alignment: .leading, spacing: 3) {
                Text("Поддержка Торганы").font(.on(16, .bold)).foregroundStyle(T.text)
                Text("Отвечают модераторы, а не бот").font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        guard app.me != nil else { loading = false; return }
        do {
            let r: ConvList = try await API.shared.get("/api/conversations")
            items = r.items
            error = nil
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        loading = false
    }
}

struct ConvRow: View {
    let c: ConvItem
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: API.shared.media(c.photo))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let o = c.other { Avatar(name: o.name, url: o.avatar, size: 22).overlay(Circle().strokeBorder(T.bg, lineWidth: 2)).offset(x: 4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.other?.name ?? "Собеседник").font(.on(16, .bold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Fmt.chatTime(c.updatedAt)).font(.on(12)).foregroundStyle(T.faint)
                }
                Text(c.title ?? "").font(.on(13, .medium)).foregroundStyle(T.text2).lineLimit(1)
                HStack(spacing: 6) {
                    if (c.lastMine ?? 0) == 1 { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(T.faint) }
                    Text(c.lastBody ?? "").font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
                    Spacer(minLength: 6)
                    if let n = c.unread, n > 0 {
                        Text("\(n)").font(.on(12, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(T.accentFill))
                    }
                }
            }
        }
        .opacity(c.blocked == true ? 0.55 : 1)
    }
}

extension Fmt {
    /// «15:17», «вчера», «3 нояб.»
    static func chatTime(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if cal.isDateInToday(d) { f.dateFormat = "HH:mm"; return f.string(from: d) }
        if cal.isDateInYesterday(d) { return "вчера" }
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    static func time(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
