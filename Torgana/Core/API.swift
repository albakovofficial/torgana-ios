import Foundation
import WebKit

// Связь с сервером torgana.ru — те же /api/…, что у сайта. Вход — та же кука сессии (tg_sid), что у сайта внутри приложения:
// куки WKWebView и URLSession синхронизируются (CookieSync), поэтому вошли в одном месте — вошли везде.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    static let offline = APIError(status: 0, message: "Нет связи с сервером. Проверьте интернет.")
}

final class API {
    static let shared = API()
    let base: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        base = Router.shared.baseURL
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": "TorganaApp/\(WebController.appVersion) (iOS; native)"]
        session = URLSession(configuration: cfg)
    }

    func url(_ path: String) -> URL { URL(string: path, relativeTo: base)?.absoluteURL ?? base }

    /// Полный адрес картинки: «/uploads/…» → https://torgana.ru/uploads/…
    func media(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    func get<R: Decodable>(_ path: String, query: [String: String] = [:], as type: R.Type = R.self) async throws -> R {
        try await send("GET", path, query: query, body: Optional<[String: String]>.none)
    }

    @discardableResult
    func post<R: Decodable, B: Encodable>(_ path: String, _ body: B, as type: R.Type = R.self) async throws -> R {
        try await send("POST", path, body: body)
    }

    @discardableResult
    func post(_ path: String) async throws -> JSONValue {
        try await send("POST", path, body: [String: String]())
    }

    /// Файл целиком в теле запроса (видео частями, документ) — тот же разбор ответа и ошибок.
    func upload<R: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], data: Data, as type: R.Type = R.self) async throws -> R {
        try await send(method, path, query: query, body: Optional<[String: String]>.none, raw: data)
    }

    func send<R: Decodable, B: Encodable>(_ method: String, _ path: String, query: [String: String] = [:], body: B?, raw: Data? = nil) async throws -> R {
        var comps = URLComponents(url: url(path), resolvingAgainstBaseURL: true)!
        if !query.isEmpty { comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        if let raw {
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.httpBody = raw
            req.timeoutInterval = 180
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError.offline }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.error
            throw APIError(status: status, message: msg ?? "Что-то пошло не так (\(status)). Попробуйте ещё раз.")
        }
        if R.self == JSONValue.self, data.isEmpty { return JSONValue.null as! R }
        do { return try decoder.decode(R.self, from: data) } catch {
            #if DEBUG
            print("decode \(path):", error)
            #endif
            throw APIError(status: status, message: "Не удалось прочитать ответ сервера. Обновите приложение.")
        }
    }

    private struct ErrorBody: Decodable { let error: String? }
}

// Любой JSON — для ответов, где нужно одно-два поля.
enum JSONValue: Codable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    subscript(key: String) -> JSONValue? { if case .object(let o) = self { return o[key] } else { return nil } }
    var int: Int? { if case .number(let n) = self { return Int(n) } else { return nil } }
    var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
}

// Куки сессии: WKWebView (сайт внутри приложения) ⇄ URLSession (родные экраны).
final class CookieSync: NSObject, WKHTTPCookieStoreObserver {
    static let shared = CookieSync()
    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }
    private var lastSid: String?
    var onChange: (() -> Void)?

    func start() {
        store.add(self)
        pullFromWeb()
    }

    private var host: String { Router.shared.baseURL.host ?? "torgana.ru" }
    private func ours(_ c: HTTPCookie) -> Bool { c.domain.hasSuffix(host) || host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }

    /// Сайт вошёл или вышел — переносим куки в URLSession.
    func pullFromWeb() {
        store.getAllCookies { cookies in
            let mine = cookies.filter(self.ours)
            let shared = HTTPCookieStorage.shared
            for c in shared.cookies ?? [] where self.ours(c) && !mine.contains(where: { $0.name == c.name }) { shared.deleteCookie(c) }
            for c in mine { shared.setCookie(c) }
            let sid = mine.first { $0.name == "tg_sid" }?.value
            if sid != self.lastSid {
                self.lastSid = sid
                DispatchQueue.main.async { self.onChange?() }
            }
        }
    }

    /// Родной экран вошёл или вышел — переносим куки в WKWebView.
    func pushToWeb(completion: (() -> Void)? = nil) {
        let mine = (HTTPCookieStorage.shared.cookies ?? []).filter(ours)
        store.getAllCookies { web in
            let group = DispatchGroup()
            for c in web where self.ours(c) && !mine.contains(where: { $0.name == c.name }) { group.enter(); self.store.delete(c) { group.leave() } }
            for c in mine { group.enter(); self.store.setCookie(c) { group.leave() } }
            group.notify(queue: .main) {
                self.lastSid = mine.first { $0.name == "tg_sid" }?.value
                completion?()
            }
        }
    }

    var hasSession: Bool { (HTTPCookieStorage.shared.cookies ?? []).contains { $0.name == "tg_sid" && ours($0) } }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { pullFromWeb() }
}
