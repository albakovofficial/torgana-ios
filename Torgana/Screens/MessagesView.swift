import SwiftUI

// Сообщения: поддержка сверху, ниже — переписки по объявлениям (как список на сайте).
struct MessagesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [ConvItem] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сообщения").font(.on(24, .bold)).foregroundStyle(T.text)
                    .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 14)
                if app.me == nil {
                    EmptyState(title: "Переписка с продавцами", text: "Войдите, чтобы писать продавцам и отвечать покупателям.", button: "Войти") { app.needLogin = true }
                } else {
                    NavigationLink(value: Route.support) { supportRow }.buttonStyle(.plain)
                    Text("ПЕРЕПИСКИ").font(.on(11, .semibold)).kerning(0.6).foregroundStyle(T.muted)
                        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
                    if loading && items.isEmpty {
                        LoadingView()
                    } else if let error, items.isEmpty {
                        EmptyState(title: "Не загрузилось", text: error, button: "Повторить") { Task { await load() } }
                    } else if items.isEmpty {
                        Text("Пока нет переписок. Напишите продавцу из объявления — переписка появится здесь.")
                            .font(.on(14)).foregroundStyle(T.muted).padding(12)
                    } else {
                        ForEach(items) { c in
                            NavigationLink(value: Route.chat(c.id)) { ConvRow(c: c) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 11).padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            .padding(.horizontal, 20).padding(.top, 16)
            TabBarSpace()
        }
        .sitePage()
        .refreshable { await load() }
        .task(id: app.me?.id) {
            // Пока список на экране — обновляем раз в 10 секунд.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    // Поддержка (.conv.support): мягкий переход «небо → сирень», знак Торганы 44, галочка у названия.
    private var supportRow: some View {
        HStack(spacing: 12) {
            Image("Logo").resizable().frame(width: 44, height: 44).clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: Color(hex: 0x3D4FB8).opacity(0.28), radius: 8, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Поддержка Торганы").font(.on(14.5, .bold)).foregroundStyle(T.text)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 15)).foregroundStyle(T.accentFill)
                }
                Text("Отвечают люди, а не боты").font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "pin").font(.system(size: 13, weight: .medium)).foregroundStyle(T.accent)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.gradSoft))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(hex: 0x5B5FD6).opacity(0.12), lineWidth: 1))
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

// Строка переписки (.conv): фото 48 со скруглением 14, аватарка собеседника 24 с белой обводкой, имя 14/650,
// время 12, объявление 13/500, последнее сообщение 13, число непрочитанных — синий кружок 20.
struct ConvRow: View {
    let c: ConvItem
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: API.shared.media(c.photo))
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let o = c.other { Avatar(name: o.name, url: o.avatar, size: 24).overlay(Circle().strokeBorder(T.card, lineWidth: 2)).offset(x: 3, y: 3) }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.other?.name ?? "Собеседник").font(.on(14, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Fmt.chatTime(c.updatedAt)).font(.on(12)).foregroundStyle(T.muted)
                }
                Text([c.title, c.price.map { Fmt.price($0, unit: c.priceUnit) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.on(13, .medium)).foregroundStyle(T.text2).lineLimit(1)
                HStack(spacing: 5) {
                    if (c.lastMine ?? 0) == 1 { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(T.muted) }
                    Text(c.lastBody ?? "").font(.on(13)).foregroundStyle(T.muted).lineLimit(1)
                    Spacer(minLength: 6)
                    if let n = c.unread, n > 0 {
                        Text("\(n)").font(.on(12, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(T.accentFill))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
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
