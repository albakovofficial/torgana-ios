import UIKit
import UserNotifications

// Push-уведомления Apple (APNs).
// Приложение получает адрес устройства (token) и отдаёт его сайту событием 'push.token';
// сайт сам отправляет его на сервер (POST /api/push/apns) — с куками вошедшего пользователя.
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    // Отладочная сборка из Xcode ходит в «песочницу» APNs, TestFlight и App Store — в боевой.
    static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    private(set) var token: String?

    private override init() { super.init() }

    // Сайт нажал «Включить уведомления».
    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied:
                self.sendStatus("denied")
            case .authorized, .provisional, .ephemeral:
                self.sendStatus("granted")
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            default:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    self.sendStatus(granted ? "granted" : "denied")
                    if granted {
                        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                    }
                }
            }
        }
    }

    // Сайт спрашивает, включены ли уведомления (чтобы показать нужную кнопку).
    func reportStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = "granted"
            case .denied: status = "denied"
            default: status = "default"
            }
            self.sendStatus(status)
        }
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        resendToken()
    }

    // Вызывается после каждой загрузки страницы: сайт мог войти/выйти — пусть сам решит, отправлять ли.
    func resendToken() {
        guard let token else { return }
        WebController.shared.send(["type": "push.token", "token": token, "env": PushManager.environment])
    }

    private func sendStatus(_ status: String) {
        WebController.shared.send(["type": "push.status", "status": status])
    }

    // MARK: UNUserNotificationCenterDelegate

    // Приложение открыто — всё равно показываем баннер (новое сообщение в чате и т. п.).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Нажали на уведомление — открываем страницу из поля "url" (полный адрес или путь: "/chat/42").
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let link = info["url"] as? String, !link.isEmpty {
            DispatchQueue.main.async {
                if let url = URL(string: link), url.scheme != nil {
                    Router.shared.open(url)
                } else {
                    Router.shared.open(path: link)
                }
            }
        }
        completionHandler()
    }
}
