import AuthenticationServices
import CryptoKit
import UIKit

// «Войти с Apple». Сайт присылает { type: 'auth.apple', nonce }, приложение показывает системное окно Apple
// и возвращает сайту событие 'auth.apple' с identityToken. Сайт отправляет его на сервер (POST /api/auth/apple),
// сервер проверяет подпись Apple (JWKS, RS256), aud = ru.torgana.app и nonce: в токене лежит SHA-256 от nonce.
@MainActor
final class AppleSignIn: NSObject {
    static let shared = AppleSignIn()

    private var rawNonce: String?

    private override init() { super.init() }

    /// Вход со страницы сайта (мост auth.apple): nonce прислал сайт, ответ уходит ему же (webDone / webFailed).
    func start(nonce: String?) {
        let request = makeRequest(nonce: nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    // MARK: родной экран входа (SignInWithAppleButton)
    // Одноразовый nonce выдаёт сервер (POST /api/auth/apple/nonce) — берём заранее: кнопка Apple не ждёт сети.
    /// Сервер хранит код 10 минут — старше 9 минут берём новый.
    private var serverNonce: (value: String, at: Date)?

    /// false — кода нет (нет связи): своим кодом вход не пройдёт, сервер ответит «Вход устарел».
    @discardableResult
    func prefetchNonce() async -> Bool {
        if let n = serverNonce, Date().timeIntervalSince(n.at) < 540 { return true }
        guard let r: JSONValue = try? await API.shared.post("/api/auth/apple/nonce", ["next": "/profile"]), let n = r["nonce"]?.string else { return false }
        serverNonce = (n, Date())
        return true
    }

    /// Запрос Apple: имя и почта, nonce — его SHA-256 (сам nonce уходит на сервер вместе с токеном).
    private func makeRequest(nonce: String?) -> ASAuthorizationAppleIDRequest {
        let raw = nonce.flatMap { $0.isEmpty ? nil : $0 } ?? AppleSignIn.randomNonce()
        rawNonce = raw
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignIn.sha256(raw)
        return request
    }

    /// Родной экран входа: системное окно Apple со своей кнопкой (значок в ряду с Яндексом и VK).
    /// Возвращает, что отправить на сервер (POST /api/auth/apple); отмена — ASAuthorizationError.canceled.
    func authorize() async throws -> [String: JSONValue] {
        try await withCheckedThrowingContinuation { c in
            let request = makeRequest(nonce: serverNonce?.value)
            let flow = NativeFlow { [weak self] r in
                self?.native = nil
                switch r {
                case .failure(let e): c.resume(throwing: e)
                case .success(let auth):
                    guard let self, let p = self.payload(auth) else { c.resume(throwing: APIError(status: 0, message: "Apple не прислал данные для входа")); return }
                    // Код с сервера одноразовый — следующий берём сразу.
                    self.serverNonce = nil
                    Task { await self.prefetchNonce() }
                    c.resume(returning: p)
                }
            }
            native = flow
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = flow
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    private var native: NativeFlow?

    // Apple отвечает на главном потоке.
    private final class NativeFlow: NSObject, ASAuthorizationControllerDelegate {
        let done: @MainActor (Result<ASAuthorization, Error>) -> Void
        init(_ done: @escaping @MainActor (Result<ASAuthorization, Error>) -> Void) { self.done = done }
        nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            MainActor.assumeIsolated { done(.success(authorization)) }
        }
        nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            MainActor.assumeIsolated { done(.failure(error)) }
        }
    }

    /// Что отправить на сервер (POST /api/auth/apple): токен Apple, nonce, имя и почта —
    /// их Apple отдаёт только при самом первом входе, поэтому они уходят сразу. Один и тот же для родного экрана и сайта.
    private func payload(_ authorization: ASAuthorization) -> [String: JSONValue]? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return nil }
        var p: [String: JSONValue] = ["identityToken": .string(token), "nonce": .string(rawNonce ?? "")]
        let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { p["name"] = .string(name) }
        if let email = credential.email { p["email"] = .string(email) }
        rawNonce = nil
        return p
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// Вход со страницы сайта (мост auth.apple). Apple отвечает на главном потоке.
extension AppleSignIn: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { webDone(authorization) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { webFailed(error) }
    }

    private func webDone(_ authorization: ASAuthorization) {
        guard let p = payload(authorization) else {
            WebController.shared.send(["type": "auth.apple.error", "code": "no_token"])
            return
        }
        var message: [String: Any] = ["type": "auth.apple"]
        for (k, v) in p { if let text = v.string { message[k] = text } }
        WebController.shared.send(message)
    }

    private func webFailed(_ error: Error) {
        rawNonce = nil
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        WebController.shared.send([
            "type": "auth.apple.error",
            "code": canceled ? "canceled" : "failed",
            "message": error.localizedDescription
        ])
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated { UIApplication.shared.torganaWindow ?? ASPresentationAnchor() }
    }
}
