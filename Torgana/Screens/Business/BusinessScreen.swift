import SwiftUI

// «Для бизнеса» — родные экраны (решение 26.11: хаб с карточками, сверху чек-лист запуска, пока магазин не настроен).
// Запросы те же, что у сайта: /api/my/business, /api/my/shop, /api/me/business, /api/me/trademark, /api/my/shop/stats.
// Купить тариф или продвижение в приложении нельзя (правила App Store) — только посмотреть, что подключено.
enum BizSection: String, Hashable {
    case hub, shop, trust, brand, stats, promo, payments

    var title: String {
        switch self {
        case .hub: return "Для бизнеса"
        case .shop: return "Витрина"
        case .trust: return "Доверие"
        case .brand: return "Галочка бренда"
        case .stats: return "Статистика"
        case .promo: return "Продвижение"
        case .payments: return "Платежи и чеки"
        }
    }
}

/// Данные раздела: один запрос на все экраны, после сохранения — обновить.
@MainActor
final class BizStore: ObservableObject {
    static let shared = BizStore()
    @Published var hub: BizHub?
    @Published var error: String?

    func load() async {
        do { hub = try await API.shared.get("/api/my/business"); error = nil }
        catch is CancellationError {}
        catch { if hub == nil { self.error = error.userMessage() } }
    }

    var open: Bool { hub?.plan != nil || hub?.shop.official == true }
}

struct BusinessScreen: View {
    let section: BizSection
    @ObservedObject private var store = BizStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: section.title).padding(.bottom, 16)
                if let h = store.hub {
                    switch section {
                    case .hub: BizHubView(h: h)
                    case .shop: ShopEditView(h: h)
                    case .trust: TrustView(h: h)
                    case .brand: BrandView(h: h)
                    case .stats: StatsView()
                    case .promo: PromoList(items: h.promotions ?? [])
                    case .payments: PaymentList(items: h.payments ?? [])
                    }
                } else if let error = store.error {
                    LoadFailed(error: error, retry: store.load)
                } else { LoadingView() }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.load() }
        .task { await store.load() }
        .sitePage()
    }
}
