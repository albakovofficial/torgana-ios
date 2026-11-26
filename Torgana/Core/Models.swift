import Foundation

// Ответы сервера. Почти все поля необязательные: новое поле на сервере или пропущенное старое не ломает приложение.

struct Category: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let hint: String?
}

struct FieldDef: Codable, Hashable {
    let key: String
    let label: String
    let type: String          // select | number | text
    let options: [String]?
    let unit: String?
    let popular: [String]?
    let req: Bool?
    let placeholder: String?
    let min: Double?
    let max: Double?
    let step: Double?
    /// Модели по маркам (у машин и телефонов); fixed — только из списка марки (машины), иначе — подсказки.
    let suggest: [String: [String]]?
    let fixed: Bool?
}

extension FieldDef: Identifiable { var id: String { key } }

struct Subcategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let fields: [FieldDef]?
    /// Название собирается из характеристик (машины, телефоны, недвижимость) — поле «Название» не показываем.
    let auto: Bool?
}

struct AppConfig: Codable {
    let categories: [Category]
    let cities: [String]
    let priceUnits: [String]?
    let subcategories: [String: [Subcategory]]?
    let supportEmail: String?
    let oauth: [String: Bool]?
    let operatorInfo: Operator?
    /// Письма включены на сервере — тогда в настройках есть переключатели «Почта».
    let mail: Bool?

    struct Operator: Codable { let name: String?; let inn: String?; let ogrnip: String? }

    enum CodingKeys: String, CodingKey {
        case categories, cities, priceUnits, subcategories, supportEmail, oauth, mail
        case operatorInfo = "operator"
    }

    func category(_ id: String?) -> Category? { categories.first { $0.id == id } }
    func subs(_ category: String?) -> [Subcategory] { subcategories?[category ?? ""] ?? [] }
}

struct Rep: Codable, Hashable {
    let level: Int?
    let levelName: String?
    let deals: Int?
    let total: Int?
    let newbie: Bool?
    // На странице продавца (repOf сервера): надёжный покупатель, жалобы за год, скорость ответа, комплименты, вехи.
    let buyer: Bool?
    let complaints: Int?
    let reply: RepReply?
    let tags: [RepTag]?
    let marks: [String]?
}

struct RepReply: Codable, Hashable { let time: String? }

extension Rep {
    /// Скорость ответа словами: «за час», «в течение дня».
    var replyText: String? { reply?.time.flatMap { ["hour": "за час", "hours": "за 1–3 ч", "day": "в течение дня", "days": "за 1–2 дня"][$0] } }
}
struct RepTag: Codable, Hashable { let tag: String; let n: Int }

/// Магазин (тариф для бизнеса): название, обложка, описание; official — официальный аккаунт Торганы.
struct PublicShop: Codable, Hashable {
    let name: String?
    let cover: String?
    let about: String?
    let official: Bool?
}

struct FirstMedal: Codable, Hashable { let no: Int?; let form: String?; let own: String? }

struct Badges: Codable, Hashable {
    let phone: Bool?
    let shop: Bool?
    let official: Bool?
    let first: FirstMedal?
    /// «ИП проверен» / «Компания проверена» и галочка бренда (товарный знак).
    let biz: BizBadge?
    let tm: TmBadge?
}
struct BizBadge: Codable, Hashable { let kind: String?; let name: String? }
struct TmBadge: Codable, Hashable { let number: String?; let name: String?; let until: Double? }

struct Me: Codable, Hashable {
    let id: Int
    let name: String
    let email: String?
    let avatar: String?
    let isAdmin: Bool?
    let rep: Rep?
    let badges: Badges?
    let deactivatedAt: Double?
    let phone: String?
    let emailVerified: Bool?
    // Уведомления (NOTIFY_FIELDS сайта): push — на iPhone и в браузере, notify — письмом.
    let pushMessages: Bool?
    let pushSearches: Bool?
    let pushPrices: Bool?
    let pushModeration: Bool?
    let notifyMessages: Bool?
    let notifyDigest: Bool?
    let notifyModeration: Bool?
}

/// Счётчики модерации для администратора (GET /api/admin/stats).
struct AdminStats: Codable {
    let pending: Int?
    let reports: Int?
    let support: Int?
    let appeals: Int?
    let biz: Int?
    let rep: Int?
    var total: Int { [pending, reports, support, appeals, biz, rep].compactMap { $0 }.reduce(0, +) }
}

struct BlockedUser: Codable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let avatar: String?
    let at: Double?
}

struct BlockList: Codable { let items: [BlockedUser] }

struct MeResponse: Codable {
    let user: Me?
    let unread: Int?
    let notices: Int?
}

struct CardSeller: Codable, Hashable {
    let id: Int
    let name: String
    let avatar: String?
    let level: Int?
    let shop: Bool?
}

/// Платное продвижение в карточке. У своих объявлений сервер присылает здесь список покупок — тогда поля пустые.
struct Boost: Codable, Hashable {
    let xl: Bool?
    let frame: Bool?
    let tags: [String]?
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: K.self)
        xl = try? c?.decode(Bool.self, forKey: .xl)
        frame = try? c?.decode(Bool.self, forKey: .frame)
        tags = try? c?.decode([String].self, forKey: .tags)
    }
    private enum K: String, CodingKey { case xl, frame, tags }
}

/// Объявление в ленте и поиске.
struct ListingCard: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let price: Int?
    let priceUnit: String?
    let priceWas: Int?
    let city: String?
    let metro: String?
    let category: String?
    let subcategory: String?
    let summary: String?
    let photo: String?
    let createdAt: Double?
    var isFav: Bool?
    let goodPrice: Bool?
    let delivery: Bool?
    let hasVideo: Bool?
    let status: String?
    let boost: Boost?
    let seller: CardSeller?
}

struct ListingsPage: Codable {
    let items: [ListingCard]
    let total: Int?
}

struct ItemsPage: Codable { let items: [ListingCard] }

struct Spec: Codable, Hashable {
    let label: String?
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        label = try? c.decode(String.self, forKey: .label)
        if let s = try? c.decode(String.self, forKey: .value) { value = s }
        else if let n = try? c.decode(Double.self, forKey: .value) { value = n == n.rounded() ? String(Int(n)) : String(n) }
        else if let b = try? c.decode(Bool.self, forKey: .value) { value = b ? "Да" : "Нет" }
        else { value = nil }
    }
    private enum K: String, CodingKey { case label, value }
    /// Превью при подаче: строки характеристик собираем сами, как describe() сервера.
    init(label: String, value: String) { self.label = label; self.value = value }
}

struct Station: Codable, Hashable { let name: String?; let line: String?; let color: String? }

/// Объявление целиком.
struct Listing: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String?
    let category: String?
    let subcategory: String?
    let price: Int?
    let priceUnit: String?
    let priceWas: Int?
    let city: String?
    let metro: Station?
    let district: String?
    let condition: String?
    let delivery: Bool?
    let bargain: Bool?
    let exchange: Bool?
    let status: String?
    let views: Int?
    let favCount: Int?
    let createdAt: Double?
    let updatedAt: Double?
    let photos: [String]?
    var isFav: Bool?
    let isOwner: Bool?
    let specs: [Spec]?
    let rejectReason: String?
    let attrs: [String: JSONValue]?
}

struct Seller: Codable, Hashable {
    let id: Int
    let name: String
    let avatar: String?
    let activeCount: Int?
    let rep: Rep?
    let badges: Badges?
    var followers: Int?
    var following: Bool?
}

struct ListingResponse: Codable {
    let listing: Listing
    var seller: Seller?
    let similar: [ListingCard]?
}

struct FavResult: Codable { let fav: Bool; let favCount: Int? }
struct IdResult: Codable { let id: Int }

// MARK: - Сообщения

struct Person: Codable, Hashable {
    let id: Int
    let name: String
    let avatar: String?
    let createdAt: Double?
    let rep: Rep?
}

struct ConvItem: Codable, Identifiable, Hashable {
    let id: Int
    let listingId: Int?
    let title: String?
    let price: Int?
    let priceUnit: String?
    let status: String?
    let photo: String?
    let other: Person?
    let lastBody: String?
    let unread: Int?
    let updatedAt: Double?
    let role: String?
    let blocked: Bool?
    let lastMine: Int?
}

struct ConvList: Codable { let items: [ConvItem] }

struct Quote: Codable, Hashable {
    let id: Int
    let mine: Bool?
    let body: String?
    let photo: JSONValue?
    let video: Bool?
    let file: Bool?
    let kind: String?
}

struct Offer: Codable, Hashable, Identifiable {
    let id: Int
    let price: Int
    let listingPrice: Int?
    let status: String          // pending, accepted, declined, withdrawn, countered
    let bySeller: Bool?
    let parentId: Int?
    let createdAt: Double?
}

struct Message: Codable, Identifiable, Hashable {
    let id: Int
    let mine: Bool
    var body: String?
    let photo: String?
    let video: String?          // 1.57.0: видео (адрес /uploads/…)
    let file: ChatFile?         // 1.57.0: документ
    let kind: String?
    let offerId: Int?
    let reply: Quote?
    let createdAt: Double?
    let read: Bool?
    var editedAt: Double?       // 1.57.0: изменено
}

struct ChatFile: Codable, Hashable { let url: String; let name: String; let size: Int }
/// Правка сообщения, пришедшая при опросе (GET …?edits=).
struct MessageEdit: Codable, Hashable { let id: Int; let body: String; let editedAt: Double? }

struct ChatListing: Codable, Hashable {
    let id: Int
    let title: String
    let price: Int?
    let priceUnit: String?
    let status: String?
    let bargain: Bool?
    let delivery: Bool?
    let photo: String?
    let city: String?
}

struct ChatData: Codable {
    struct Conv: Codable { let id: Int; let role: String? }
    let conversation: Conv?
    let listing: ChatListing?
    let other: Person?
    let block: String?          // "me" — я заблокировал, "them" — меня
    let offers: [Offer]?
    let readUpTo: Int?
    let typing: Bool?
    let messages: [Message]
    let edited: [MessageEdit]?
    let now: Double?
}

struct SentMessage: Codable { let message: Message }
struct OfferResult: Codable { let offers: [Offer]? }
/// Переписка с поддержкой — те же сообщения, что в обычном чате (без ответов и предложений цены).
struct SupportData: Codable { let messages: [Message] }
struct UploadResult: Codable { let file: String; let url: String? }
struct VideoStart: Codable { let file: String; let chunk: Int }
struct VideoPart: Codable { let received: Int?; let ready: Bool? }

// MARK: - Профиль

/// Своё объявление в «Моих объявлениях» — карточка плюс просмотры, причина отклонения и т. п.
struct MyListing: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let price: Int?
    let priceUnit: String?
    let city: String?
    let photo: String?
    let status: String?          // active, pending, rejected, scheduled, sold, archived
    let createdAt: Double?
    let views: Int?
    let favCount: Int?
    let rejectReason: String?
    let expiresAt: Double?
}

struct MyListings: Codable { let items: [MyListing] }

struct Notice: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String?
    let title: String
    let body: String?
    let url: String?
    let icon: String?
    let tone: String?
    let at: Double?
    let read: Bool?
    let photo: String?
}

struct NoticeList: Codable { let items: [Notice]; let unread: Int? }

// MARK: - Страница продавца

struct PublicUser: Codable, Hashable {
    let id: Int
    let name: String
    let avatar: String?
    let activeCount: Int?
    let rep: Rep?
    let badges: Badges?
    var followers: Int?
    var following: Bool?
    var block: String?
    let shop: PublicShop?
}

struct UserResponse: Codable { let user: PublicUser }
struct FollowResult: Codable { let following: Bool; let followers: Int? }

// MARK: - Для бизнеса (GET /api/my/business, /api/me/trademark, /api/my/shop/stats)

struct BizHub: Decodable {
    let plan: BizPlan?
    let biz: BizCheck?
    let shop: ShopInfo
    let pinned: [PinnedItem]?
    let promotions: [Promotion]?
    let payments: [Payment]?
}
struct BizPlan: Decodable { let id: String; let name: String; let until: Double; let trial: Bool? }
/// Заявка на проверку ИП или компании: status — pending, verified, rejected.
struct BizCheck: Decodable { let status: String; let kind: String?; let name: String?; let inn: String?; let ogrn: String?; let note: String?; let at: Double? }
struct ShopInfo: Decodable {
    let official: Bool?
    let cover: String?
    let about: String?
    let hours: String?
    let address: String?
    let site: String?
    let delivery: String?
}
struct PinnedItem: Decodable, Identifiable { let id: Int; let title: String }
struct Promotion: Decodable, Identifiable {
    let id: Int
    let listingId: Int?
    let title: String
    let status: String
    let endsAt: Double?
    let shows: Int?
    let clicks: Int?
    let note: String?
}
struct Payment: Decodable, Identifiable {
    let id: Int
    let title: String
    let amount: Int
    let status: String
    let method: String?
    let refunded: Int?
    let createdAt: Double?
}

struct TrademarkResponse: Decodable {
    let trademark: Trademark?
    let code: String?
    let letter: String?
    let docs: [VerifyDoc]
    let kinds: [String: String]
}
struct Trademark: Decodable { let status: String; let number: String?; let name: String?; let until: Double?; let note: String?; let at: Double?; let live: Bool? }
struct VerifyDoc: Decodable, Identifiable { let id: Int; let kind: String; let kindName: String?; let mime: String?; let size: Int?; let name: String? }

struct ShopStats: Decodable {
    struct Sum: Decodable { let impressions: Int; let views: Int; let favs: Int }
    struct Day: Decodable { let day: String; let views: Int }
    struct Item: Decodable, Identifiable { let id: Int; let title: String; let photo: String?; let views: Int; let favs: Int }
    let totals: Sum
    let prev: Sum
    let daily: [Day]
    let listings: [Item]
    let active: Int?
}
