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
}

struct Subcategory: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let fields: [FieldDef]?
}

struct AppConfig: Codable {
    let categories: [Category]
    let cities: [String]
    let priceUnits: [String]?
    let subcategories: [String: [Subcategory]]?
    let supportEmail: String?
    let oauth: [String: Bool]?
    let operatorInfo: Operator?

    struct Operator: Codable { let name: String?; let inn: String?; let ogrnip: String? }

    enum CodingKeys: String, CodingKey {
        case categories, cities, priceUnits, subcategories, supportEmail, oauth
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
}

struct FirstMedal: Codable, Hashable { let no: Int?; let form: String?; let own: String? }

struct Badges: Codable, Hashable {
    let phone: Bool?
    let shop: Bool?
    let official: Bool?
    let first: FirstMedal?
}

struct Me: Codable, Hashable {
    let id: Int
    let name: String
    let email: String?
    let city: String?
    let avatar: String?
    let isAdmin: Bool?
    let createdAt: Double?
    let rep: Rep?
    let badges: Badges?
    let deactivatedAt: Double?
}

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
    let city: String?
    let avatar: String?
    let createdAt: Double?
    let activeCount: Int?
    let rep: Rep?
    let badges: Badges?
    let followers: Int?
    var following: Bool?
}

struct ListingResponse: Codable {
    let listing: Listing
    let seller: Seller?
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
    let body: String?
    let photo: String?
    let kind: String?
    let offerId: Int?
    let reply: Quote?
    let createdAt: Double?
    let read: Bool?
}

struct ChatListing: Codable, Hashable {
    let id: Int
    let title: String
    let price: Int?
    let priceUnit: String?
    let status: String?
    let bargain: Bool?
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
}

struct SentMessage: Codable { let message: Message }
struct OfferResult: Codable { let offers: [Offer]? }
/// Переписка с поддержкой — те же сообщения, что в обычном чате (без ответов и предложений цены).
struct SupportData: Codable { let messages: [Message] }
struct UploadResult: Codable { let file: String; let url: String? }

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
