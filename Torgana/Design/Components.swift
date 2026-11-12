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
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(on ? Color(hex: 0xE5484D) : T.text)
                .frame(width: size, height: size)
                .background(Circle().fill(T.card))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Убрать из избранного" : "В избранное")
    }
}

// MARK: - Карточка объявления в ленте (как .card на сайте).
struct ListingCardView: View {
    let item: ListingCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RemoteImage(url: API.shared.media(item.photo)))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(item.boost?.frame == true ? T.accentFill : .clear, lineWidth: 2.5)
                    )
                FavButton(id: item.id, initial: item.isFav, size: 36)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Fmt.price(item.price, unit: item.priceUnit))
                        .font(.on(17, .bold))
                        .foregroundStyle(T.text)
                    if let was = item.priceWas, let p = item.price, was > p {
                        Text(Fmt.price(was)).font(.on(12)).strikethrough().foregroundStyle(T.faint)
                    }
                }
                .lineLimit(1)
                Text(item.title)
                    .font(.on(15))
                    .foregroundStyle(T.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if item.goodPrice == true {
                    Text("Хорошая цена").font(.on(12, .semibold)).foregroundStyle(T.good)
                }
                Text([item.metro.flatMap { $0.isEmpty ? nil : "м. \($0)" } ?? item.city, Fmt.day(item.createdAt)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.on(13))
                    .foregroundStyle(T.muted)
                    .lineLimit(1)
                if let s = item.seller {
                    HStack(spacing: 6) {
                        Avatar(name: s.name, url: s.avatar, size: 20)
                        Text(s.name).font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        if s.shop == true { Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(T.accent) }
                    }
                    .padding(.top, 5)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 10)
        }
        .contentShape(Rectangle())
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

// MARK: - Плашка-фильтр (как .chip на сайте).
struct Chip: View {
    let title: String
    var icon: String? = nil
    var on = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.on(15, .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .foregroundStyle(on ? T.accent : T.text)
            .background(Capsule().fill(on ? T.accentSoft : T.surface))
            .overlay(Capsule().strokeBorder(on ? T.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Пустой экран, ошибка, загрузка.
struct EmptyState: View {
    let icon: String
    let title: String
    var text: String = ""
    var button: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(T.accent)
                .frame(width: 72, height: 72)
                .background(Circle().fill(T.accentSoft))
            Text(title).font(.on(20, .bold)).foregroundStyle(T.text).multilineTextAlignment(.center)
            if !text.isEmpty { Text(text).font(.on(15)).foregroundStyle(T.muted).multilineTextAlignment(.center) }
            if let button, let action {
                Button(button, action: action).buttonStyle(TButton(kind: .dark, full: false)).padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
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
