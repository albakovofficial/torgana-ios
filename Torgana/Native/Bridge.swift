import UIKit

// Мост «сайт → приложение». Сайт зовёт window.TorganaApp.post({ type: '…', … }),
// приложение отвечает событием window 'torgana-native' (e.detail). Полный список — в BRIDGE.md.
// Сообщения принимаются только со страниц torgana.ru (проверка в WebController).
@MainActor
enum Bridge {
    static func handle(type: String, body: [String: Any]) {
        switch type {
        case "share":
            share(body)
        case "haptic":
            Haptics.play(body["style"] as? String ?? "light")
        case "auth.apple":
            AppleSignIn.shared.start(nonce: body["nonce"] as? String)
        case "badge":
            Badge.set((body["count"] as? NSNumber)?.intValue ?? 0)
        case "native.open":
            // Ссылка на странице сайта ведёт в раздел, который уже родной, — открываем его в приложении.
            if let path = body["path"] as? String { Task { @MainActor in Nav.shared.open(path: path) } }
        case "open.external":
            if let raw = body["url"] as? String, let url = URL(string: raw),
               ["http", "https", "tel", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
        case "app.info":
            WebController.shared.send([
                "type": "app.info",
                "platform": "ios",
                "version": WebController.appVersion,
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                "system": UIDevice.current.systemVersion
            ])
        default:
            break
        }
    }

    // Системное «Поделиться»: ссылка на объявление + текст.
    private static func share(_ body: [String: Any]) {
        var items: [Any] = []
        if let text = body["text"] as? String, !text.isEmpty { items.append(text) }
        if let raw = body["url"] as? String, let url = URL(string: raw, relativeTo: Router.shared.baseURL)?.absoluteURL {
            items.append(url)
        }
        present(items) { activity, completed in
            WebController.shared.send(["type": "share.result", "completed": completed, "activity": activity ?? ""])
        }
    }

    /// Системное «Поделиться» с чем угодно: ссылка, текст, файл (выгрузка статистики).
    static func present(_ items: [Any], done: ((String?, Bool) -> Void)? = nil) {
        guard !items.isEmpty, let top = UIApplication.shared.topController else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60, width: 1, height: 1)
        }
        sheet.completionWithItemsHandler = { activity, completed, _, _ in done?(activity?.rawValue, completed) }
        top.present(sheet, animated: true)
    }
}

// Виброотклик: лёгкий щелчок на кнопках, «успех» после публикации и т. п.
@MainActor
enum Haptics {
    static func play(_ style: String) {
        switch style {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error": UINotificationFeedbackGenerator().notificationOccurred(.error)
        case "selection": UISelectionFeedbackGenerator().selectionChanged()
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "heavy": UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
