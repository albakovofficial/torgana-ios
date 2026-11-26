import Foundation
import WebKit
import Security

// Связь с сервером torgana.ru — те же /api/…, что у сайта. Вход — та же кука сессии (tg_sid), что у сайта внутри приложения:
// куки WKWebView и URLSession синхронизируются (CookieSync), поэтому вошли в одном месте — вошли везде.
struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    static let offline = APIError(status: 0, message: "Нет связи с сервером. Проверьте интернет.")
}

// Один слой ошибок для всех экранов: что показать человеку и что молча пропустить.
extension Error {
    /// Текст для человека: ответ сервера или «нет связи» (APIError) — как есть, иначе — запасной текст места.
    func userMessage(_ fallback: String = "Не получилось") -> String { (self as? APIError)?.message ?? fallback }
    /// Отмена — ушли с экрана или начали заново: это не ошибка, показывать нечего.
    var isCancellation: Bool { self is CancellationError || (self as? URLError)?.code == .cancelled }
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
        // Сеть на телефоне пропадает на секунды (лифт, смена Wi-Fi на мобильную) — подождать её, а не сразу «нет связи».
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForResource = 40
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

    /// Файл с сервера как есть (выгрузка статистики в Excel).
    func data(_ path: String, query: [String: String] = [:]) async throws -> Data {
        var comps = URLComponents(url: url(path), resolvingAgainstBaseURL: true)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await session.data(from: comps.url!) } catch { throw APIError.offline }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, message: "Не получилось скачать файл (\(status))") }
        return data
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
        do {
            // Чтение (GET) не отменяется вместе с экраном: SwiftUI отменяет .task/.refreshable при перерисовке,
            // и раньше отменённый запрос показывался как «Нет связи с сервером». Плюс один повтор при обрыве связи
            // (после возврата приложения из фона первый запрос часто падает с «соединение потеряно»).
            if method == "GET" {
                let request = req
                (data, resp) = try await Task.detached { [session] in
                    do { return try await session.data(for: request) } catch let e as URLError where API.retryable.contains(e.code) {
                        try await Task.sleep(nanoseconds: 600_000_000)
                        return try await session.data(for: request)
                    }
                }.value
            } else {
                (data, resp) = try await session.data(for: req)
            }
        } catch let e as URLError where e.code == .cancelled {
            throw CancellationError() // отменили сами (крестик загрузки) — не ошибка связи
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }
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
    private static let retryable: Set<URLError.Code> = [.networkConnectionLost, .timedOut, .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost, .notConnectedToInternet, .secureConnectionFailed]
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

// Сессия (кука tg_sid): WKWebView (страницы сайта) ⇄ URLSession (родные экраны) ⇄ Связка ключей.
// Выход решает только сервер: /api/me ответил «никто не вошёл» при нашей куке — или вы сами нажали «Выйти».
// Пустое хранилище кук WKWebView ничего не значит: при холодном запуске оно бывает пустым, пока WebKit не прочитал
// диск, — раньше это принималось за выход, и через пару часов (iOS выгрузила приложение) приходилось входить заново.
final class CookieSync: NSObject, WKHTTPCookieStoreObserver {
    static let shared = CookieSync()
    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }
    private var lastSid: String?
    var onChange: (() -> Void)?

    private let name = "tg_sid"
    private var host: String { Router.shared.baseURL.host ?? "torgana.ru" }
    private func ours(_ c: HTTPCookie) -> Bool { c.domain.hasSuffix(host) || host.hasSuffix(c.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
    private var sid: HTTPCookie? { (HTTPCookieStorage.shared.cookies ?? []).first { $0.name == name && ours($0) } }
    var hasSession: Bool { sid != nil }

    private var adopting = false   // пока отдаём сессию страницам сайта, их старую куку не забираем

    /// Запуск: сессия из Связки ключей — родным экранам и страницам сайта, до первого запроса.
    func start() {
        if sid == nil, let saved = SessionVault.load(host: host) { HTTPCookieStorage.shared.setCookie(saved) }
        store.add(self)
        if sid != nil { adoptNative { self.pullFromWeb() } } else { pullFromWeb() }
    }

    /// Страница сайта вошла (или вошла другим профилем) — забираем её сессию. Нет куки у сайта — спрашиваем сервер.
    func pullFromWeb() {
        store.getAllCookies { cookies in
            DispatchQueue.main.async {
                guard !self.adopting else { return }
                guard let web = cookies.first(where: { $0.name == self.name && self.ours($0) && !$0.value.isEmpty }) else {
                    if self.lastSid != nil { self.onChange?() }   // вышли на странице сайта? проверит /api/me
                    return
                }
                guard web.value != self.lastSid else { return }
                HTTPCookieStorage.shared.setCookie(web)
                SessionVault.save(web)
                self.lastSid = web.value
                self.onChange?()
            }
        }
    }

    /// Вошли в родном экране: сессия (её поставил ответ сервера) — в Связку ключей и страницам сайта.
    func adoptNative(completion: (() -> Void)? = nil) {
        guard let c = sid else { completion?(); return }
        SessionVault.save(c)
        lastSid = c.value
        adopting = true
        store.setCookie(c) { DispatchQueue.main.async { self.adopting = false; completion?() } }
    }

    /// Вход через Яндекс или VK начат родным запросом, а закончится на странице: кука начала входа нужна и ей,
    /// иначе сервер не примет возврат от сервиса (вход привязан к тому, кто его начал).
    func share(_ cookie: String, completion: @escaping () -> Void) {
        guard let c = (HTTPCookieStorage.shared.cookies ?? []).first(where: { $0.name == cookie && ours($0) }) else { completion(); return }
        store.setCookie(c) { DispatchQueue.main.async { completion() } }
    }

    /// Ответ сервера продлил сессию (1.59.3: Set-Cookie на /api/me) — запомнить новый срок.
    func remember() { if let c = sid, c.value == lastSid { SessionVault.save(c) } }

    /// Текущая сессия — её запоминает список аккаунтов.
    var current: (value: String, expires: Double)? {
        guard let c = sid else { return nil }
        return (c.value, c.expiresDate?.timeIntervalSince1970 ?? Date().addingTimeInterval(30 * 86400).timeIntervalSince1970)
    }

    /// Переключиться на сохранённый аккаунт: его сессия — родным экранам, страницам сайта и в Связку ключей.
    func use(_ value: String, expires: Double, completion: @escaping () -> Void) {
        drop {
            guard let c = SessionVault.cookie(value, expires: expires, host: self.host) else { completion(); return }
            HTTPCookieStorage.shared.setCookie(c)
            self.adoptNative(completion: completion)
        }
    }

    /// Выход: «Выйти», удаление профиля или сервер не узнал сессию.
    func drop(completion: (() -> Void)? = nil) {
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.name == name && ours(c) { HTTPCookieStorage.shared.deleteCookie(c) }
        SessionVault.clear()
        lastSid = nil
        store.getAllCookies { web in
            let group = DispatchGroup()
            for c in web where c.name == self.name && self.ours(c) { group.enter(); self.store.delete(c) { group.leave() } }
            group.notify(queue: .main) { completion?() }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { pullFromWeb() }
}

/// Запись в Связке ключей (только этот iPhone, после первой разблокировки): текущая сессия и сохранённые аккаунты.
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ru.torgana.session", kSecAttrAccount as String: account]
    }
    static func write(_ account: String, _ data: Data) {
        SecItemDelete(query(account) as CFDictionary)
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
    static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    static func delete(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
}

/// Сессия в Связке ключей: переживает выгрузку приложения и не зависит от того, успели ли куки записаться на диск.
enum SessionVault {
    static func save(_ c: HTTPCookie) {
        let exp = c.expiresDate?.timeIntervalSince1970 ?? Date().addingTimeInterval(30 * 86400).timeIntervalSince1970
        guard let data = try? JSONEncoder().encode(["v": c.value, "exp": String(exp)]) else { return }
        Keychain.write("tg_sid", data)
    }

    static func load(host: String) -> HTTPCookie? {
        guard let data = Keychain.read("tg_sid"), let d = try? JSONDecoder().decode([String: String].self, from: data),
              let v = d["v"], let exp = Double(d["exp"] ?? ""), exp > Date().timeIntervalSince1970 else { return nil }
        return cookie(v, expires: exp, host: host)
    }

    /// Кука сессии сайта — та же, что ставит сервер (tg_sid, HttpOnly, Secure).
    static func cookie(_ value: String, expires: Double, host: String) -> HTTPCookie? {
        HTTPCookie(properties: [.name: "tg_sid", .value: value, .domain: host, .path: "/", .secure: "TRUE",
                                .expires: Date(timeIntervalSince1970: expires), HTTPCookiePropertyKey("HttpOnly"): "TRUE"])
    }

    static func clear() { Keychain.delete("tg_sid") }
}
