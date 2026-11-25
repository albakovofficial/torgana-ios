import SwiftUI

// Сообщения (вариант A, «мессенджер», выбран владельцем 13 ноября): на всю ширину, поиск по перепискам,
// фильтры «Все / Непрочитанные / Покупаю / Продаю», поддержка закреплена первой, строки с фото товара и аватаркой.
struct MessagesView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var items: [ConvItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query = ""
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable { case all, unread, buy, sell }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Сообщения").font(.on(30, .heavy)).foregroundStyle(T.text)
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
                search
                filters
                NavigationLink(value: Route.support) { supportRow }.buttonStyle(.plain)
                list
            }
            TabBarSpace()
        }
        .scrollDismissesKeyboard(.immediately)
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

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(T.faint)
            TextField("Поиск по перепискам", text: $query).font(.on(16)).submitLabel(.search).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.faint) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, "Все")
                chip(.unread, "Непрочитанные", count: items.filter { ($0.unread ?? 0) > 0 }.count)
                chip(.buy, "Покупаю")
                chip(.sell, "Продаю")
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 10)
    }

    private func chip(_ f: Filter, _ title: String, count: Int = 0) -> some View {
        let on = filter == f
        return Button { filter = f; Haptics.play("selection") } label: {
            HStack(spacing: 6) {
                Text(title).font(.on(14, .semibold))
                if count > 0 {
                    Text("\(count)").font(.on(12, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20).background(Capsule().fill(T.accentFill))
                }
            }
            .foregroundStyle(on ? T.onInk : T.text)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(on ? T.ink : T.surface))
        }
        .buttonStyle(.plain)
    }

    // Поддержка: закреплена первой, мягкая полоса фирменного цвета, знак Торганы 56, галочка у названия.
    private var supportRow: some View {
        HStack(spacing: 12) {
            Image("SupportAvatar").resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Поддержка Торганы").font(.on(16, .bold)).foregroundStyle(T.text).lineLimit(1)
                    Verified(size: 18)
                    Spacer(minLength: 6)
                    Image(systemName: "pin.fill").font(.system(size: 12)).foregroundStyle(T.accent).rotationEffect(.degrees(45))
                }
                Text("Отвечают люди, а не боты").font(.on(15)).foregroundStyle(T.muted).lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(LinearGradient(colors: [T.accentSoft, T.accentSoft.opacity(0)], startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var list: some View {
        if loading && items.isEmpty {
            LoadingView()
        } else if let error, items.isEmpty {
            EmptyState(title: "Не загрузилось", text: error, button: "Повторить") { Task { await load() } }
        } else if shown.isEmpty {
            Text(emptyText).font(.on(15)).foregroundStyle(T.muted).padding(.horizontal, 20).padding(.vertical, 24)
        } else {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, c in
                NavigationLink(value: Route.chat(c.id)) { ConvRow(c: c, divider: i > 0) }.buttonStyle(.plain)
            }
        }
    }

    private var emptyText: String {
        if !query.isEmpty { return "Ничего не нашлось по «\(query)»." }
        switch filter {
        case .unread: return "Все сообщения прочитаны."
        case .buy: return "Здесь будут переписки с продавцами — напишите из объявления."
        case .sell: return "Здесь будут вопросы покупателей о ваших объявлениях."
        case .all: return "Пока нет переписок. Напишите продавцу из объявления — переписка появится здесь."
        }
    }

    private var shown: [ConvItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { c in
            switch filter {
            case .all: break
            case .unread: if (c.unread ?? 0) == 0 { return false }
            case .buy: if c.role != "buyer" { return false }
            case .sell: if c.role != "seller" { return false }
            }
            guard !q.isEmpty else { return true }
            return [c.other?.name, c.title, c.lastBody].compactMap { $0?.lowercased() }.contains { $0.contains(q) }
        }
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

// Строка переписки: фото товара 58 (скругление 18) с аватаркой собеседника 24, имя 16/700 и время (синее, если есть новое),
// «товар · цена», последнее сообщение с галочками и число непрочитанных. Разделитель — от текста, не от края.
struct ConvRow: View {
    let c: ConvItem
    var divider = true

    private var gone: String? {
        switch c.status {
        case "sold": return "продано"
        case "deleted": return "удалено"
        case "archived": return "снято"
        default: return nil
        }
    }

    var body: some View {
        let unread = (c.unread ?? 0) > 0
        HStack(spacing: 12) {
            RemoteImage(url: API.shared.media(c.photo))
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let o = c.other { Avatar(name: o.name, url: o.avatar, size: 24).overlay(Circle().strokeBorder(T.bg, lineWidth: 2.5)).offset(x: 4, y: 4) }
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(c.other?.name ?? "Собеседник").font(.on(16, .bold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Fmt.chatTime(c.updatedAt)).font(.on(13, unread ? .semibold : .regular)).foregroundStyle(unread ? T.accent : T.faint)
                }
                HStack(spacing: 6) {
                    Text([c.title, c.price.map { Fmt.price($0, unit: c.priceUnit) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.on(14)).foregroundStyle(T.text2).lineLimit(1)
                    if let gone {
                        Text(gone).font(.on(11, .bold)).foregroundStyle(T.muted)
                            .padding(.horizontal, 6).frame(height: 18).background(RoundedRectangle(cornerRadius: 6).fill(T.surface))
                    }
                }
                HStack(spacing: 6) {
                    if let mine = c.lastMine, mine > 0 { Ticks(read: mine == 2) }
                    Text(c.lastBody ?? "Нет сообщений").font(.on(15, unread ? .medium : .regular)).foregroundStyle(unread ? T.text : T.muted).lineLimit(1)
                    Spacer(minLength: 6)
                    if let n = c.unread, n > 0 {
                        Text("\(n)").font(.on(12, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(T.accentFill))
                    }
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) { if divider { T.line.frame(height: 1) } }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .opacity(c.blocked == true ? 0.55 : 1)
    }
}

/// Галочки у своих сообщений: одна серая — доставлено, две синие — прочитано (как на сайте).
struct Ticks: View {
    let read: Bool
    var tint: Color? = nil
    var body: some View {
        HStack(spacing: -6) {
            Image(systemName: "checkmark")
            if read { Image(systemName: "checkmark") }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(tint ?? (read ? T.accent : T.faint))
        .accessibilityLabel(read ? "Прочитано" : "Доставлено")
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
