import XCTest
@testable import Torgana

// Тесты без сети: форматы, слой ошибок, разбор ответов сервера, какие адреса приложение считает своими.
// Запускаются в GitHub Actions перед снимками экранов (xcodebuild test).

final class FormatTests: XCTestCase {
    private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: " ") }

    func testPrice() {
        XCTAssertEqual(plain(Fmt.price(45000)), "45 000 ₽")
        XCTAssertEqual(plain(Fmt.price(35000, unit: "мес")), "35 000 ₽ / мес")
        XCTAssertEqual(Fmt.price(0), "Даром")
        XCTAssertEqual(Fmt.price(nil), "Цена не указана")
    }

    func testPlural() {
        XCTAssertEqual(Fmt.plural(1, "день", "дня", "дней"), "день")
        XCTAssertEqual(Fmt.plural(3, "день", "дня", "дней"), "дня")
        XCTAssertEqual(Fmt.plural(11, "день", "дня", "дней"), "дней")
        XCTAssertEqual(Fmt.plural(21, "день", "дня", "дней"), "день")
    }

    func testSizesAndDuration() {
        XCTAssertEqual(Fmt.bytes(1000), "1 КБ", "меньше килобайта — всё равно 1 КБ")
        XCTAssertEqual(Fmt.bytes(240 * 1024), "240 КБ")
        XCTAssertEqual(Fmt.bytes(4_404_019), "4,2 МБ")
        XCTAssertEqual(Fmt.duration(24.4), "0:24")
        XCTAssertEqual(Fmt.duration(60), "1:00")
    }
}

final class ErrorLayerTests: XCTestCase {
    struct Other: Error {}

    func testUserMessage() {
        XCTAssertEqual(APIError(status: 400, message: "Проверьте цену").userMessage(), "Проверьте цену")
        XCTAssertEqual(APIError.offline.userMessage("Не загрузилось"), APIError.offline.message, "«нет связи» — как есть")
        XCTAssertEqual(Other().userMessage("Не отправилось"), "Не отправилось", "чужая ошибка — запасной текст места")
    }

    func testCancellation() {
        XCTAssertTrue(CancellationError().isCancellation)
        XCTAssertTrue(URLError(.cancelled).isCancellation)
        XCTAssertFalse(URLError(.notConnectedToInternet).isCancellation)
        XCTAssertFalse(APIError.offline.isCancellation)
    }

    @MainActor
    func testFailShowsOnlyRealErrors() {
        let app = AppState.shared
        app.toast = nil
        app.fail(CancellationError())
        XCTAssertNil(app.toast, "отмену не показываем")
        app.fail(APIError(status: 403, message: "Нет доступа"))
        XCTAssertEqual(app.toast?.text, "Нет доступа")
        XCTAssertEqual(app.toast?.bad, true)
        app.fail(Other(), "Файл не отправился")
        XCTAssertEqual(app.toast?.text, "Файл не отправился")
        app.toast = nil
    }
}

final class DecodingTests: XCTestCase {
    func testMessageWithFileAndReply() throws {
        let json = """
        {"id": 7, "mine": true, "body": "Договор", "photo": null, "file": {"url": "/uploads/a.pdf", "name": "Договор.pdf", "size": 2048},
         "kind": null, "offerId": null, "reply": {"id": 5, "mine": false, "body": "Пришлите договор"}, "createdAt": 1764000000000, "read": true}
        """
        let m = try JSONDecoder().decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(m.id, 7)
        XCTAssertEqual(m.file?.name, "Договор.pdf")
        XCTAssertEqual(m.reply?.body, "Пришлите договор")
        XCTAssertNil(m.editedAt)
    }

    func testMessageWithoutOptionalFields() throws {
        let m = try JSONDecoder().decode(Message.self, from: Data(#"{"id": 1, "mine": false}"#.utf8))
        XCTAssertNil(m.body)
        XCTAssertNil(m.file)
    }
}

final class AddressTests: XCTestCase {
    func testOwnSiteOnly() {
        let host = Router.shared.baseURL.host ?? "torgana.ru"
        XCTAssertTrue(Router.shared.isInternal(URL(string: "https://\(host)/l/1")!))
        XCTAssertTrue(Router.shared.isInternal(URL(string: "https://www.\(host)/")!))
        XCTAssertFalse(Router.shared.isInternal(URL(string: "https://\(host).evil.com/")!), "чужой домен с нашим именем в начале")
        XCTAssertFalse(Router.shared.isInternal(URL(string: "https://evil\(host)/")!))
    }

    func testLoginPagesOfServices() {
        XCTAssertTrue(WebController.isAuthHost(URL(string: "https://oauth.yandex.ru/authorize")!))
        XCTAssertTrue(WebController.isAuthHost(URL(string: "https://id.vk.com/auth")!))
        XCTAssertFalse(WebController.isAuthHost(URL(string: "https://vk.com.evil.ru/")!))
        XCTAssertFalse(WebController.isAuthHost(URL(string: "https://example.com/")!))
    }
}
