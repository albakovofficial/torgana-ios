import SwiftUI
import AuthenticationServices

// Вход и регистрация: почта и пароль (с кодом из письма, если почта не подтверждена), «Войти с Apple»,
// Яндекс ID и VK ID (их страницы входа — внутри приложения, вход сохраняется и для страниц сайта).
struct LoginView: View {
    enum Mode { case login, register, code }

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    @State private var oauthURL: OAuthLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image("Logo").resizable().frame(width: 64, height: 64).clipShape(Circle()).padding(.top, 8)
                Text(mode == .register ? "Создать профиль" : mode == .code ? "Код из письма" : "Вход в Торгану")
                    .font(.on(28, .heavy)).foregroundStyle(T.text)
                if mode == .code {
                    Text("Отправили код на \(email). Введите его — и почта подтверждена.").font(.on(15)).foregroundStyle(T.muted)
                    field("Код", text: $code, keyboard: .numberPad, content: .oneTimeCode)
                    primary("Подтвердить") { await submitCode() }
                    Button("Отправить код ещё раз") { Task { await resend() } }.font(.on(15, .semibold)).foregroundStyle(T.accent)
                } else {
                    if mode == .register { field("Имя", text: $name, content: .name) }
                    field("Email", text: $email, keyboard: .emailAddress, content: .username)
                    SecureField("Пароль", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .font(.on(17)).padding(.horizontal, 18).frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
                    if mode == .register {
                        Toggle(isOn: $consent) {
                            Text("Согласен на обработку персональных данных и с правилами Торганы").font(.on(14)).foregroundStyle(T.text2)
                        }
                        .tint(T.accentFill)
                    }
                    if let error { Text(error).font(.on(14)).foregroundStyle(T.danger) }
                    primary(mode == .register ? "Создать профиль" : "Войти") { await submit() }
                    if mode == .login {
                        Button("Забыли пароль?") { nav.push(.web("/forgot")); dismiss() }.font(.on(15, .semibold)).foregroundStyle(T.accent)
                    }
                    divider
                    SignInWithAppleButton(.signIn) { req in
                        AppleSignIn.shared.prepare(req)
                    } onCompletion: { result in
                        Task { await apple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .clipShape(Capsule())
                    Text("Входя через Apple, Яндекс или VK, вы соглашаетесь с правилами Торганы и обработкой персональных данных.")
                        .font(.on(12)).foregroundStyle(T.faint)
                    if app.config?.oauth?["yandex"] == true { oauthButton("Яндекс ID", "yandex") }
                    if app.config?.oauth?["vk"] == true { oauthButton("VK ID", "vk") }
                    Button(mode == .login ? "Нет профиля? Создать" : "Уже есть профиль? Войти") {
                        withAnimation { mode = mode == .login ? .register : .login; error = nil }
                    }
                    .font(.on(16, .semibold)).foregroundStyle(T.text).frame(maxWidth: .infinity).padding(.top, 6)
                }
            }
            .padding(20)
        }
        .background(T.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        .sheet(item: $oauthURL) { link in
            NavigationStack { WebScreen(path: link.url.absoluteString, title: "Вход", closeOnLogin: true) }
        }
        .onChange(of: app.me?.id) { _, id in if id != nil { dismiss() } }
        .task { await AppleSignIn.shared.prefetchNonce() }
    }

    private var divider: some View {
        HStack { Rectangle().fill(T.line).frame(height: 1); Text("или").font(.on(13)).foregroundStyle(T.faint); Rectangle().fill(T.line).frame(height: 1) }
            .padding(.vertical, 4)
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType = .default, content: UITextContentType? = nil) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textContentType(content)
            .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            .autocorrectionDisabled()
            .font(.on(17)).padding(.horizontal, 18).frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
    }

    private func primary(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { busy = true; await action(); busy = false } } label: {
            if busy { ProgressView().tint(T.onInk) } else { Text(title) }
        }
        .buttonStyle(TButton(kind: .dark))
        .disabled(busy)
    }

    private func oauthButton(_ title: String, _ provider: String) -> some View {
        Button {
            Task {
                do {
                    let r: JSONValue = try await API.shared.post("/api/auth/oauth/\(provider)/start", ["next": "/profile"])
                    if let s = r["url"]?.string, let u = URL(string: s) { oauthURL = OAuthLink(url: u) }
                } catch { self.error = (error as? APIError)?.message }
            }
        } label: { Text("Войти через \(title)") }
        .buttonStyle(TButton(kind: .soft))
    }

    private struct AuthResult: Decodable { let needCode: Bool?; let email: String? }

    private func submit() async {
        error = nil
        do {
            let r: AuthResult
            if mode == .register {
                guard consent else { error = "Нужно согласие на обработку персональных данных"; return }
                r = try await API.shared.post("/api/auth/register", RegisterBody(name: name, email: email, password: password, consent: true, src: "ios"))
            } else {
                r = try await API.shared.post("/api/auth/login", ["email": email, "password": password])
            }
            if r.needCode == true { mode = .code; return }
            await done()
        } catch { self.error = (error as? APIError)?.message }
    }

    private struct RegisterBody: Encodable { let name: String; let email: String; let password: String; let consent: Bool; let src: String }

    private func submitCode() async {
        error = nil
        do {
            _ = try await API.shared.post("/api/auth/code", ["email": email, "code": code], as: JSONValue.self)
            await done()
        } catch { app.show((error as? APIError)?.message ?? "Неверный код", bad: true) }
    }

    private func resend() async {
        do { _ = try await API.shared.post("/api/auth/code/resend", ["email": email], as: JSONValue.self); app.show("Отправили новый код") }
        catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }

    private func apple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { error = "Apple не подтвердил вход — попробуйте ещё раз" }
        case .success(let auth):
            guard let p = AppleSignIn.shared.payload(auth) else { error = "Apple не прислал данные для входа"; return }
            do {
                var body = p
                body["consent"] = .bool(true)
                _ = try await API.shared.post("/api/auth/apple", body, as: JSONValue.self)
                await done()
            } catch { self.error = (error as? APIError)?.message }
        }
    }

    /// Вошли: куки — страницам сайта, профиль — родным экранам.
    private func done() async {
        Haptics.play("success")
        await withCheckedContinuation { c in CookieSync.shared.pushToWeb { c.resume() } }
        await app.refreshMe()
    }
}

struct OAuthLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
