import SwiftUI
import UIKit

// MARK: - Картинки с сервера: кэш в памяти + системный кэш URLSession.
final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 300 << 20)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    init() { memory.totalCostLimit = 80 << 20 }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        guard let (data, _) = try? await session.data(from: url), let img = UIImage(data: data) else { return nil }
        let decoded = img.preparingForDisplay() ?? img
        memory.setObject(decoded, forKey: url as NSURL, cost: data.count)
        return decoded
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                T.surface
                if url == nil {
                    Image(systemName: "photo").font(.system(size: 26, weight: .regular)).foregroundStyle(T.faint)
                }
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImageCache.shared.cached(url) { image = c; return }
            let img = await ImageCache.shared.load(url)
            withAnimation(.easeOut(duration: 0.18)) { image = img }
        }
    }
}

// MARK: - Аватар: фото или первая буква на фирменном градиенте.
struct Avatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let u = API.shared.media(url) {
                RemoteImage(url: u)
            } else {
                T.grad
                Text(String(name.prefix(1)).uppercased())
                    .font(.on(size * 0.42, .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Сердечко «в избранное».
struct FavButton: View {
    let id: Int
    let initial: Bool?
    var size: CGFloat = 38
    @EnvironmentObject private var app: AppState

    var body: some View {
        let on = app.isFav(id, initial)
        Button {
            Task { _ = await app.toggleFav(id, current: on) }
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(on ? Color(hex: 0xE5484D) : T.text)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.dyn(0xFFFFFF, 0x171B27)))
                .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Убрать из избранного" : "В избранное")
    }
}

// MARK: - Карточка объявления в ленте (.card сайта): фото 1:1 со скруглением 20, цена 17/750, название 14.5/500,
// характеристики и город — 12.5, «Доставка» — синим, продавец — аватарка 20 и имя.
struct ListingCardView: View {
    let item: ListingCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RemoteImage(url: API.shared.media(item.photo)))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if item.hasVideo == true {
                            Label("Видео", systemImage: "play.fill")
                                .font(.on(12, .semibold))
                                .padding(.horizontal, 9).frame(height: 26)
                                .background(Capsule().fill(.black.opacity(0.55)))
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(item.boost?.frame == true ? T.accentFill : .clear, lineWidth: 2.5)
                    )
                FavButton(id: item.id, initial: item.isFav, size: 38)
                    .padding(6)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.price(item.price, unit: item.priceUnit)).font(.on(17, .bold)).foregroundStyle(T.text)
                    if let was = item.priceWas, let p = item.price, was > p {
                        Text(Fmt.price(was)).font(.on(12)).strikethrough().foregroundStyle(T.faint)
                    }
                }
                .lineLimit(1)
                .padding(.bottom, 4)
                Text(item.title)
                    .font(.on(14.5, .medium)).foregroundStyle(T.text)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.bottom, 3)
                if let sum = item.summary, !sum.isEmpty {
                    Text(sum).font(.on(12.5)).foregroundStyle(T.text2).lineLimit(1).padding(.bottom, 3)
                }
                Text([item.metro.flatMap { $0.isEmpty ? nil : "м. \($0)" } ?? item.city, Fmt.day(item.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
                if item.goodPrice == true {
                    Text("Хорошая цена").font(.on(12.5, .semibold)).foregroundStyle(T.good).padding(.top, 3)
                }
                if item.delivery == true {
                    Label("Доставка", systemImage: "truck.box").font(.on(12.5, .semibold)).foregroundStyle(T.accent)
                        .labelStyle(TightLabel()).padding(.top, 3)
                }
                if let s = item.seller {
                    HStack(spacing: 6) {
                        Avatar(name: s.name, url: s.avatar, size: 20)
                        Text(s.name).font(.on(12.5)).foregroundStyle(T.text2).lineLimit(1)
                        if s.shop == true { Verified(size: 14) }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 9)
        }
        .contentShape(Rectangle())
    }
}

/// Значок и текст вплотную (4 точки), значок поменьше — как иконки в строках сайта.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

// Сетка карточек в две колонки.
struct ListingGrid: View {
    let items: [ListingCard]
    var onAppearLast: (() -> Void)? = nil

    private let cols = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 22) {
            ForEach(items) { item in
                NavigationLink(value: Route.listing(item.id)) {
                    ListingCardView(item: item)
                }
                .buttonStyle(.plain)
                .onAppear { if item.id == items.last?.id { onAppearLast?() } }
            }
        }
    }
}

// MARK: - Плашка-фильтр (.cat-pill сайта): 38 точек, 13.5/600; выбранная — синяя с тонкой синей обводкой.
struct Chip: View {
    let title: String
    var icon: String? = nil
    var on = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .medium)) }
                Text(title).font(.on(13.5, .semibold)).lineLimit(1)
            }
            .padding(.leading, icon == nil ? 14 : 11).padding(.trailing, 14)
            .frame(height: 38)
            .foregroundStyle(on ? T.accent : T.text)
            .background(Capsule().fill(on ? T.accentFill.opacity(0.10) : T.surface))
            .overlay(Capsule().strokeBorder(on ? T.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Пустой экран (.empty сайта): панель --surface со скруглением 28, заголовок 22/700, текст 16, тёмная кнопка.
struct EmptyState: View {
    var icon: String? = nil
    let title: String
    var text: String = ""
    var button: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(T.accent)
                    .frame(width: 84, height: 84)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.card).shadow(color: T.accentFill.opacity(0.12), radius: 15, y: 10))
                    .padding(.bottom, 6)
            }
            Text(title).font(.on(22, .bold)).foregroundStyle(T.text).multilineTextAlignment(.center)
            if !text.isEmpty { Text(text).font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center) }
            if let button, let action {
                Button(button, action: action).buttonStyle(TButton(kind: .dark, height: 48, full: false)).padding(.top, 12)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 56)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.surface))
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView().tint(T.accent).frame(maxWidth: .infinity, minHeight: 200)
    }
}

// Всплывающее сообщение снизу (как toast на сайте).
struct ToastHost: ViewModifier {
    @EnvironmentObject private var app: AppState

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = app.toast {
                Text(t.text)
                    .font(.on(15, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(Capsule().fill(t.bad ? Color(hex: 0xA8322A) : Color(hex: 0x161A2B)))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(t.id)
                    .task(id: t.id) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        if app.toast?.id == t.id { withAnimation { app.toast = nil } }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.toast)
    }
}

// Значки разделов — как на сайте (там свои рисунки; здесь — ближайшие системные).
enum CatIcon {
    static func of(_ id: String) -> String {
        switch id {
        case "transport": return "car"
        case "realty": return "house"
        case "jobs": return "briefcase"
        case "services": return "wrench.and.screwdriver"
        case "electronics": return "iphone"
        case "personal": return "tshirt"
        case "home": return "sofa"
        case "hobby": return "bicycle"
        case "animals": return "pawprint"
        case "business": return "building.2"
        default: return "square.grid.2x2"
        }
    }
}

// MARK: - Блокировка: своё окно вместо системного меню — что произойдёт, и одна крупная кнопка.
struct BlockSheet: View {
    let name: String
    let avatar: String?
    let blocked: Bool
    let onConfirm: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(name: name, url: avatar, size: 76)
                Image(systemName: blocked ? "hand.raised.slash.fill" : "hand.raised.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(blocked ? AnyShapeStyle(T.grad) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF0645A), Color(hex: 0xC8322A)], startPoint: .top, endPoint: .bottom))))
                    .overlay(Circle().strokeBorder(T.bg, lineWidth: 3))
                    .offset(x: 6, y: 4)
            }
            .padding(.top, 28)
            Text(blocked ? "Разблокировать \(name)?" : "Заблокировать \(name)?")
                .font(.on(22, .heavy)).foregroundStyle(T.text).multilineTextAlignment(.center)
                .padding(.top, 16).padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 12) {
                if blocked {
                    point("message", "Снова сможет писать вам")
                    point("square.grid.2x2", "Его объявления вернутся в выдачу")
                } else {
                    point("message.badge.filled.fill", "Не сможет писать вам — ни в старых, ни в новых переписках")
                    point("eye.slash", "Его объявления пропадут из вашей выдачи")
                    point("arrow.uturn.backward", "Разблокировать можно в любой момент — здесь же")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
            .padding(.horizontal, 20).padding(.top, 18)
            Spacer(minLength: 16)
            VStack(spacing: 8) {
                Button {
                    Task { busy = true; await onConfirm(); busy = false; dismiss() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(blocked ? "Разблокировать" : "Заблокировать") }
                }
                .buttonStyle(TButton(kind: blocked ? .accent : .red))
                .disabled(busy)
                Button("Отмена") { dismiss() }.buttonStyle(TButton(kind: .soft))
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(T.bg.ignoresSafeArea())
        .presentationDetents([.height(blocked ? 430 : 500)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(blocked ? T.accent : T.danger)
                .frame(width: 30, height: 30)
                .background(Circle().fill(blocked ? T.accentSoft : T.dangerSoft))
            Text(text).font(.on(15)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
    }
}

extension Array {
    /// Элемент или nil, если индекса нет.
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
