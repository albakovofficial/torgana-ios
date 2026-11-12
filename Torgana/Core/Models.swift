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
    let type: String          // select | number | text | bool
    let options: [String]?
    let unit: String?
    let popular: [String]?
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

struct Boost: Codable, Hashable {
    let xl: Bool?
    let frame: Bool?
    let tags: [String]?
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
