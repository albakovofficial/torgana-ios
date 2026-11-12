import SwiftUI

// Страница продавца: кто он, репутация, подписка, объявления. Можно заблокировать.
struct UserView: View {
    let id: Int
    @EnvironmentObject private var app: AppState
    @State private var user: PublicUser?
    @State private var items: [ListingCard] = []
    @State private var error: String?
    @State private var confirmBlock = false

    var body: some View {
        ScrollView {
            if let u = user {
                VStack(alignment: .leading, spacing: 18) {
                    head(u)
                    if items.isEmpty {
                        EmptyState(icon: "tray", title: "Нет активных объявлений").panel()
                    } else {
                        Text("Объявления · \(items.count)").font(.on(21, .heavy)).foregroundStyle(T.text)
                        ListingGrid(items: items)
                    }
                }
                .padding(16)
                TabBarSpace()
            } else if let error {
                EmptyState(icon: "person.crop.circle.badge.exclamationmark", title: "Не открылось", text: error)
            } else {
                LoadingView()
            }
        }
        .background(T.bg)
        .navigationTitle(user?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let u = user, app.me != nil, app.me?.id != u.id {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: API.shared.url("/u/\(u.id)")) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        Button(role: u.block == "me" ? nil : .destructive) { confirmBlock = true } label: {
                            Label(u.block == "me" ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .confirmationDialog(user?.block == "me" ? "Разблокировать?" : "Заблокировать продавца?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button(user?.block == "me" ? "Разблокировать" : "Заблокировать", role: user?.block == "me" ? nil : .destructive) { Task { await toggleBlock() } }
        } message: { Text(user?.block == "me" ? "Он снова сможет вам писать." : "Он не сможет вам писать, а его объявления пропадут из вашей выдачи.") }
        .refreshable { await load() }
        .task { if user == nil { await load() } }
    }

    private func head(_ u: PublicUser) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(name: u.name, url: u.avatar, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(u.name).font(.on(22, .heavy)).foregroundStyle(T.text)
                        if u.badges?.official == true || u.badges?.shop == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(T.accent) }
                    }
                    if let lvl = u.rep?.levelName { Text(lvl).font(.on(15, .semibold)).foregroundStyle(T.accent) }
                    Text([u.city, u.createdAt.map { "на Торгане с \(Fmt.monthYear($0))" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.on(14)).foregroundStyle(T.muted)
                }
            }
            if let no = u.badges?.first?.no {
                Label("\(u.badges?.first?.form == "f" ? "Одна из первых" : "Один из первых") · № \(no)", systemImage: "rosette")
                    .font(.on(14, .semibold)).foregroundStyle(T.accent)
                    .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.accentSoft))
            }
            if let deals = u.rep?.deals, deals > 0 {
                Text("\(deals) \(Fmt.plural(deals, "сделка", "сделки", "сделок")) на Торгане").font(.on(14)).foregroundStyle(T.text2)
            }
            if app.me?.id != u.id {
                Button { Task { await follow() } } label: {
                    Label(u.following == true ? "Вы подписаны" : "Подписаться", systemImage: u.following == true ? "bell.fill" : "bell")
                }
                .buttonStyle(TButton(kind: u.following == true ? .soft : .dark, height: 48))
                Text("\(u.followers ?? 0) \(Fmt.plural(u.followers ?? 0, "подписчик", "подписчика", "подписчиков")) · узнают о новых объявлениях первыми")
                    .font(.on(13)).foregroundStyle(T.muted)
            }
        }
        .panel()
    }

    private func load() async {
        do {
            let r: UserResponse = try await API.shared.get("/api/users/\(id)")
            user = r.user
            let page: ListingsPage = try await API.shared.get("/api/listings", query: ["user": String(id), "limit": "60"])
            items = page.items
        } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
    }

    private func follow() async {
        guard app.me != nil else { app.needLogin = true; return }
        do {
            let r: FollowResult = try await API.shared.post("/api/users/\(id)/follow", ["follow": !(user?.following ?? false)])
            user?.following = r.following
            user?.followers = r.followers
            Haptics.play("light")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }

    private func toggleBlock() async {
        do {
            if user?.block == "me" {
                _ = try await API.shared.send("DELETE", "/api/blocks/\(id)", body: Optional<[String: String]>.none) as JSONValue
                user?.block = nil
            } else {
                _ = try await API.shared.post("/api/blocks", ["userId": id], as: JSONValue.self)
                user?.block = "me"
            }
            Haptics.play("success")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}
