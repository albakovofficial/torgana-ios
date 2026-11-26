import AuthenticationServices
import CryptoKit
import UIKit

// «Войти с Apple». Сайт присылает { type: 'auth.apple', nonce }, приложение показывает системное окно Apple
// и возвращает сайту событие 'auth.apple' с identityToken. Сайт отправляет его на сервер (POST /api/auth/apple),
// сервер проверяет подпись Apple (JWKS, RS256), aud = ru.torgana.app и nonce: в токене лежит SHA-256 от nonce.
final class AppleSignIn: NSObject {
    static let shared = AppleSignIn()

    private var rawNonce: String?

    private override init() { super.init() }

    func start(nonce: String?) {
        let raw: String
        if let nonce, !nonce.isEmpty { raw = nonce } else { raw = AppleSignIn.randomNonce() }
        rawNonce = raw

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignIn.sha256(raw)

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

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let raw = serverNonce?.value ?? AppleSignIn.randomNonce()
        rawNonce = raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignIn.sha256(raw)
    }

    /// Родной экран входа: системное окно Apple со своей кнопкой (значок в ряду с Яндексом и VK).
    @MainActor
    func authorize() async -> Result<ASAuthorization, Error> {
        await withCheckedContinuation { c in
            let request = ASAuthorizationAppleIDProvider().createRequest()
            prepare(request)
            let flow = NativeFlow { [weak self] r in self?.native = nil; c.resume(returning: r) }
            native = flow
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = flow
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    private var native: NativeFlow?

    private final class NativeFlow: NSObject, ASAuthorizationControllerDelegate {
        let done: (Result<ASAuthorization, Error>) -> Void
        init(_ done: @escaping (Result<ASAuthorization, Error>) -> Void) { self.done = done }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) { done(.success(authorization)) }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { done(.failure(error)) }
    }

    /// Что отправить на сервер (POST /api/auth/apple). nonce одноразовый — следующий берём сразу.
    func payload(_ authorization: ASAuthorization) -> [String: JSONValue]? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else { return nil }
        var p: [String: JSONValue] = ["identityToken": .string(token), "nonce": .string(rawNonce ?? "")]
        let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty { p["name"] = .string(name) }
        if let email = credential.email { p["email"] = .string(email) }
        rawNonce = nil
        serverNonce = nil
        Task { await prefetchNonce() }
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

extension AppleSignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            WebController.shared.send(["type": "auth.apple.error", "code": "no_token"])
            return
        }
        var payload: [String: Any] = [
            "type": "auth.apple",
            "identityToken": identityToken,
            "nonce": rawNonce ?? "",
            "user": credential.user
        ]
        if let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) {
            payload["authorizationCode"] = code
        }
        // Имя и почту Apple отдаёт только при самом первом входе — сайт должен сохранить их сразу.
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { payload["name"] = name }
        if let email = credential.email { payload["email"] = email }
        rawNonce = nil
        WebController.shared.send(payload)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
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
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.torganaWindow ?? ASPresentationAnchor()
    }
}
