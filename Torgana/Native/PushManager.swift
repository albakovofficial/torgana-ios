import UIKit
import UserNotifications

// Push-уведомления Apple (APNs). Всё ведёт приложение — и для родных экранов, и для страницы настроек сайта внутри
// (она зовёт то же через мост: push.state, push.on, push.off, push.signout).
// Адрес устройства (token) уходит на сервер (POST /api/push/apns) при входе и раз за запуск: сервер мог удалить его,
// если Apple ответил, что адрес устарел. Выключили на этом iPhone — адрес удаляется с сервера (POST /api/push/apns/off)
// и больше не отправляется, пока человек сам не включит снова.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    // Отладочная сборка из Xcode ходит в «песочницу» APNs, TestFlight и App Store — в боевой.
    nonisolated static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    enum Permission: String { case granted, denied, notAsked = "default" }

    /// Для экранов: включены ли push на этом iPhone для вошедшего человека.
    @Published private(set) var on = false
    /// Один раз после входа — предложить включить (как на сайте); показывает MainView.
    @Published var ask = false

    private(set) var token: String?
    private var lastError: String?
    private var sent = ""   // «кто:адрес» — уже отправлено в этот запуск
    private var waiters: [UUID: CheckedContinuation<String?, Never>] = [:]

    private override init() { super.init() }

    private func offKey(_ userId: Int) -> String { "push.off.\(userId)" }
    private var userId: Int? { AppState.shared.me?.id }

    func permission() async -> Permission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        default: return .notAsked
        }
    }

    /// Пересчитать «включены ли» (после входа, выхода, возвращения из Настроек iPhone).
    @discardableResult
    func refresh() async -> Bool {
        guard let uid = userId else { on = false; return false }
        on = await permission() == .granted && !UserDefaults.standard.bool(forKey: offKey(uid))
        return on
    }

    // MARK: адрес устройства от Apple (AppDelegate)

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        lastError = nil
        resumeWaiters()
        Task { await sync() }
    }

    func didFail(_ error: Error) {
        lastError = error.localizedDescription
        resumeWaiters()
    }

    private func resumeWaiters() {
        let w = waiters
        waiters = [:]
        w.values.forEach { $0.resume(returning: token) }
    }

    private func waitToken(seconds: Double) async -> String? {
        if let token { return token }
        let id = UUID()
        return await withCheckedContinuation { c in
            waiters[id] = c
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self.waiters.removeValue(forKey: id)?.resume(returning: self.token)
            }
        }
    }

    // MARK: сервер

    /// Вошли или запустили приложение: отдать адрес серверу (раз за запуск), если push разрешены и не выключены здесь.
    @discardableResult
    func sync(force: Bool = false) async -> Bool {
        guard let uid = userId, let token else { await refresh(); return false }
        defer { Task { await self.refresh() } }
        if !force && (UserDefaults.standard.bool(forKey: offKey(uid)) || sent == "\(uid):\(token)") { return true }
        guard await permission() == .granted else { return false }
        do {
            _ = try await API.shared.post("/api/push/apns", ["token": token, "env": Self.environment], as: JSONValue.self)
        } catch { return false }
        sent = "\(uid):\(token)"
        return true
    }

    /// Включить на этом iPhone: системный запрос разрешения, адрес от Apple, отправка на сервер.
    func turnOn() async throws {
        guard let uid = userId else { throw APIError(status: 401, message: "Войдите, чтобы включить уведомления") }
        let denied = APIError(status: 0, message: "Уведомления запрещены — включите их в Настройках iPhone → Торгана → Уведомления")
        switch await permission() {
        case .denied: throw denied
        case .notAsked:
            let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !ok { await refresh(); throw denied }
        case .granted: break
        }
        UIApplication.shared.registerForRemoteNotifications()
        guard await waitToken(seconds: 8) != nil else {
            throw APIError(status: 0, message: "iPhone не выдал адрес для уведомлений\(lastError.map { " (\($0))" } ?? ""). Закройте приложение, откройте снова и включите ещё раз")
        }
        UserDefaults.standard.removeObject(forKey: offKey(uid))
        guard await sync(force: true) else {
            throw APIError(status: 0, message: "Не получилось подключить уведомления — проверьте интернет и попробуйте ещё раз")
        }
    }

    /// Выключить на этом iPhone. Разрешение iPhone из приложения не отзовёшь — сервер перестаёт слать сюда.
    func turnOff() async {
        guard let uid = userId else { return }
        UserDefaults.standard.set(true, forKey: offKey(uid))
        await forget()
        await refresh()
    }

    /// Перед выходом из аккаунта (пока кука ещё действует): этому человеку на этот iPhone больше не слать.
    func forget() async {
        sent = ""
        guard let token, userId != nil else { return }
        _ = try? await API.shared.post("/api/push/apns/off", ["token": token], as: JSONValue.self)
    }

    /// Один раз на iPhone, если человек вошёл и iPhone ещё не спрашивал разрешение.
    func askOnce() async {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "route") != nil { return }   // снимки экранов — без окон поверх
        #endif
        guard userId != nil, !UserDefaults.standard.bool(forKey: "push.asked"), await permission() == .notAsked else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard userId != nil, AppState.shared.ask == nil, AppState.shared.loginFull == nil else { return }   // окно входа ещё открыто — спросим при следующем запуске
        UserDefaults.standard.set(true, forKey: "push.asked")
        ask = true
    }

    /// «Проверить»: сервер присылает проверочное уведомление на включённые устройства.
    func test() async throws {
        let r = try await API.shared.post("/api/push/test")
        if r["ok"]?.bool != true {
            throw APIError(status: 0, message: r["error"]?.string ?? "Не получилось отправить — выключите и снова включите уведомления")
        }
    }
}

// Уведомления на экране и нажатия на них.
extension PushManager: UNUserNotificationCenterDelegate {
    // Приложение открыто — всё равно показываем баннер (новое сообщение в чате и т. п.).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Нажали на уведомление — открываем экран из поля "url" (полный адрес или путь: "/messages/42").
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if let link = response.notification.request.content.userInfo["url"] as? String, !link.isEmpty {
            DispatchQueue.main.async {
                if let url = URL(string: link), url.scheme != nil { Router.shared.open(url) } else { Router.shared.open(path: link) }
            }
        }
        completionHandler()
    }
}
