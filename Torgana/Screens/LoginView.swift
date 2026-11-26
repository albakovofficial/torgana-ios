import SwiftUI
import AuthenticationServices

// Вход и регистрация — отдельные экраны (решение 25.11, макет «A+C, вариант 2»): градиентная шапка со «стеклянными»
// плашками категорий, поля на белой карточке поверх шапки, Apple / Яндекс ID / VK ID в один ряд, внизу — ссылка
// на соседний экран. После регистрации (или входа с неподтверждённой почтой) — код из письма.
// Гостю вход предлагается шторкой (LoginSheet ниже, решение 25.11): во вкладках «Избранное», «+», «Сообщения»,
// «Профиль» и по кнопкам «Написать», «♡», «Подписаться»; «Войти по почте» в шторке открывает этот экран.
struct LoginView: View {
    enum Mode { case login, register, code }

    var start: Mode = .login
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .login
    @State private var back: Mode = .login     // куда вернуться с экрана кода
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    @State private var doc: String?

    var body: some View {
        Group {
            if mode == .code {
                CodeStep(email: email, back: { withAnimation { mode = back } }, done: { await AuthButtons.signedIn() })
            } else {
                form
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: Binding(get: { doc.map(DocLink.init) }, set: { doc = $0?.slug })) { d in
            NavigationStack { DocView(slug: d.slug) }
        }
        .onChange(of: app.me?.id) { _, id in if id != nil { dismiss() } }
        .onAppear { mode = start }
        .task { await AppleSignIn.shared.prefetchNonce() }
    }

    // MARK: - Вход / регистрация

    private var register: Bool { mode == .register }

    private var form: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                card.padding(.horizontal, 14).padding(.top, -64)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mode = register ? .login : .register; error = nil }
                } label: {
                    (Text(register ? "Уже есть профиль? " : "Нет профиля? ").foregroundStyle(T.muted)
                     + Text(register ? "Войти" : "Зарегистрироваться").foregroundStyle(T.accent).fontWeight(.bold))
                        .font(.on(15.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 24).padding(.bottom, 30)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.dyn(0xF5F7FC, 0x0F121B).ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.18)))
                }
                .accessibilityLabel("Закрыть")
                Spacer()
                Image("Logo").resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 22).padding(.top, 8)
            CategoryChips().padding(.horizontal, 10).padding(.top, 14)
            Text(register ? "Создайте профиль" : "С возвращением!")
                .font(.on(30, .heavy)).foregroundStyle(.white).padding(.top, 18)
            Text(register ? "Бесплатно — объявления, избранное и чаты" : "Войдите, чтобы писать продавцам")
                .font(.on(15)).foregroundStyle(.white.opacity(0.85)).padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 92)
        .background {
            AuthGradient()
                .overlay(alignment: .topTrailing) { Circle().fill(.white.opacity(0.08)).frame(width: 260, height: 260).offset(x: 80, y: -60) }
                .clipped()
                .padding(.top, -600)          // при оттягивании вниз сверху тоже градиент
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if register { AuthField(icon: "person", placeholder: "Имя", text: $name, content: .name) }
            AuthField(icon: "envelope", placeholder: "Почта", text: $email, keyboard: .emailAddress, content: .username)
            AuthField(icon: "lock", placeholder: register ? "Придумайте пароль" : "Пароль", text: $password, secure: true,
                      content: register ? .newPassword : .password)
            if register {
                if !password.isEmpty { Strength(password: password) }
                Button { consent.toggle(); Haptics.play("light") } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                            .opacity(consent ? 1 : 0)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(consent ? T.accentFill : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(consent ? .clear : T.faint, lineWidth: 1.5))
                        Text("Принимаю [правила Торганы](torgana-doc://rules) и даю согласие на [обработку данных](torgana-doc://consent)")
                            .font(.on(13.5)).foregroundStyle(T.muted).tint(T.accent).multilineTextAlignment(.leading)
                            .environment(\.openURL, OpenURLAction { url in doc = url.host; return .handled })
                    }
                }
                .buttonStyle(.plain).padding(.top, 4)
            } else {
                HStack {
                    Spacer()
                    Button("Забыли пароль?") { nav.push(.web("/forgot")); dismiss() }
                        .font(.on(14.5, .semibold)).foregroundStyle(T.accent)
                }
            }
            if let error { Text(error).font(.on(14)).foregroundStyle(T.danger).fixedSize(horizontal: false, vertical: true) }
            Button { Task { busy = true; await submit(); busy = false } } label: {
                if busy { ProgressView().tint(.white) } else { Text(register ? "Создать профиль" : "Войти") }
            }
            .buttonStyle(TButton(kind: .accent, height: 54))
            .disabled(busy)
            .padding(.top, 2)
            HStack(spacing: 12) {
                Rectangle().fill(T.line).frame(height: 1)
                Text("или").font(.on(13)).foregroundStyle(T.faint)
                Rectangle().fill(T.line).frame(height: 1)
            }
            .padding(.vertical, 4)
            AuthButtons()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.card))
        .shadow(color: Color(hex: 0x161A2B).opacity(0.12), radius: 25, y: 14)
    }

    // MARK: - Запросы    // MARK: - Запросы

    private struct AuthResult: Decodable { let needCode: Bool?; let email: String? }
    private struct RegisterBody: Encodable { let name: String; let email: String; let password: String; let consent: Bool; let src: String }

    private func submit() async {
        error = nil
        let mail = email.trimmingCharacters(in: .whitespaces)
        do {
            let r: AuthResult
            if register {
                guard name.trimmingCharacters(in: .whitespaces).count >= 2 else { error = "Укажите имя"; return }
                guard password.count >= 8 else { error = "Пароль — минимум 8 символов"; return }
                guard consent else { error = "Отметьте согласие с правилами и обработкой данных"; return }
                r = try await API.shared.post("/api/auth/register", RegisterBody(name: name, email: mail, password: password, consent: true, src: "ios"))
            } else {
                r = try await API.shared.post("/api/auth/login", ["email": mail, "password": password])
            }
            if r.needCode == true {
                if let e = r.email { email = e }
                back = mode
                withAnimation { mode = .code }
                return
            }
            await AuthButtons.signedIn()
        } catch { self.error = (error as? APIError)?.message ?? "Нет связи с Торганой — попробуйте ещё раз" }
    }

}

private struct DocLink: Identifiable { let slug: String; var id: String { slug } }

// MARK: - Поле с значком: подсветка при вводе, «глазок» у пароля

private struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var content: UITextContentType? = nil
    @State private var shown = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(focused ? T.accent : T.faint).frame(width: 22)
            Group {
                if secure && !shown { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .focused($focused)
            .keyboardType(keyboard)
            .textContentType(content)
            .textInputAutocapitalization(keyboard == .emailAddress || secure ? .never : .words)
            .autocorrectionDisabled()
            .font(.on(16.5)).foregroundStyle(T.text)
            if secure {
                Button { shown.toggle() } label: {
                    Image(systemName: shown ? "eye.slash" : "eye").font(.system(size: 16)).foregroundStyle(T.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shown ? "Скрыть пароль" : "Показать пароль")
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(focused ? T.card : T.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? T.accent : .clear, lineWidth: 1.5))
        .shadow(color: focused ? T.accent.opacity(0.15) : .clear, radius: 6)
        .animation(.easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Надёжность пароля

private struct Strength: View {
    let password: String

    private var score: Int {
        var s = 0
        if password.count >= 8 { s += 1 }
        if password.count >= 12 { s += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil && password.rangeOfCharacter(from: .letters) != nil { s += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil && password.rangeOfCharacter(from: .lowercaseLetters) != nil
            || password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { s += 1 }
        return password.count < 8 ? 0 : max(s, 1)
    }

    var body: some View {
        let (label, color): (String, Color) = switch score {
        case 0: ("Нужно ещё \(8 - password.count) \(Fmt.plural(8 - password.count, "символ", "символа", "символов"))", T.danger)
        case 1: ("Слабый пароль", Color(hex: 0xE9A23B))
        case 2: ("Неплохой пароль", Color(hex: 0xE9A23B))
        case 3: ("Хороший пароль", T.good)
        default: ("Надёжный пароль", T.good)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in Capsule().fill(i < max(score, 1) ? color : T.line).frame(height: 4) }
            }
            Text(label).font(.on(12.5, .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Код из письма

private struct CodeStep: View {
    let email: String
    let back: () -> Void
    let done: () async -> Void
    @EnvironmentObject private var app: AppState
    @State private var code = ""
    @State private var busy = false
    @State private var wait = 60
    @FocusState private var focused: Bool
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackButton(action: back)
                Image(systemName: "envelope").font(.system(size: 28, weight: .medium)).foregroundStyle(T.accent)
                    .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.accentSoft))
                    .padding(.top, 28)
                Text("Подтвердите почту").font(.on(30, .heavy)).foregroundStyle(T.text).padding(.top, 18)
                (Text("Отправили код на ").foregroundStyle(T.muted) + Text(email).foregroundStyle(T.text).fontWeight(.bold))
                    .font(.on(15)).padding(.top, 8)
                ZStack {
                    TextField("", text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($focused).opacity(0.02)
                        .onChange(of: code) { _, v in
                            let d = String(v.filter(\.isNumber).prefix(6))
                            if d != v { code = d }
                            if d.count == 6 { Task { await submit() } }
                        }
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in
                            let ch = i < code.count ? String(code[code.index(code.startIndex, offsetBy: i)]) : ""
                            let cur = focused && i == min(code.count, 5)
                            Text(ch).font(.on(26, .bold)).foregroundStyle(T.text)
                                .frame(maxWidth: .infinity).frame(height: 60)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cur ? T.card : T.surface))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cur ? T.accent : .clear, lineWidth: 2))
                        }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .padding(.top, 26)
                if busy { ProgressView().padding(.top, 16) }
                Group {
                    if wait > 0 {
                        (Text("Отправить ещё раз через ").foregroundStyle(T.muted) + Text(String(format: "0:%02d", wait)).foregroundStyle(T.text).fontWeight(.bold))
                    } else {
                        Text("Отправить код ещё раз").foregroundStyle(T.accent).fontWeight(.semibold)
                    }
                }
                .font(.on(14.5)).padding(.top, 18)
                .onTapGesture { if wait == 0 { Task { await resend() } } }
                Button("Изменить почту", action: back).font(.on(14.5, .semibold)).foregroundStyle(T.accent).padding(.top, 12)
                Text("Письма нет? Проверьте папку «Спам» — код приходит в течение минуты.")
                    .font(.on(13)).foregroundStyle(T.muted).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
                    .padding(.top, 28)
            }
            .padding(.horizontal, 22).padding(.top, 12)
        }
        .background(T.bg.ignoresSafeArea())
        .onAppear { focused = true }
        .onReceive(tick) { _ in if wait > 0 { wait -= 1 } }
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await API.shared.post("/api/auth/code", ["email": email, "code": code], as: JSONValue.self)
            await done()
        } catch {
            app.show((error as? APIError)?.message ?? "Неверный код", bad: true)
            code = ""
        }
    }

    private func resend() async {
        do {
            _ = try await API.shared.post("/api/auth/code/resend", ["email": email], as: JSONValue.self)
            wait = 60
            app.show("Отправили новый код")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

struct OAuthLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Общее для экрана входа и шторки

/// Фирменный переход цвета шапки входа.
struct AuthGradient: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x2E6FCC), Color(hex: 0x5B5FD6), Color(hex: 0x8A5CF0)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// «Стеклянные» плашки категорий на градиенте.
struct CategoryChips: View {
    var count = 7
    var size: CGFloat = 13.5
    private static let all: [(String, String)] = [("🚗", "Авто"), ("🏠", "Квартиры"), ("📱", "Электроника"), ("👟", "Одежда"),
                                                   ("🛋", "Для дома"), ("🔧", "Услуги"), ("🐾", "Животные")]
    var body: some View {
        FlowLayout(spacing: 8, center: true) {
            ForEach(Array(Self.all.prefix(count).enumerated()), id: \.offset) { i, c in
                Text("\(c.0) \(c.1)")
                    .font(.on(size, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, size - 0.5).frame(height: size * 2.5)
                    .background(Capsule().fill(.white.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .rotationEffect(.degrees([-5, 3, -2, 4, -3, 2, -4][i]))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Вход через Apple, Яндекс ID, VK ID: один ряд значками; если Apple один — широкая кнопка с подписью. Под ними — согласие.
struct AuthButtons: View {
    @EnvironmentObject private var app: AppState
    @State private var oauthURL: OAuthLink?

    private var providers: [String] { ["yandex", "vk"].filter { app.config?.oauth?[$0] == true } }

    private var fine: String {
        let names = ["Apple"] + providers.map { $0 == "vk" ? "VK" : "Яндекс" }
        let who = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " или " + names.last!
        return "Входя через \(who), вы принимаете правила Торганы и обработку данных"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { Task { await apple() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
                        if providers.isEmpty { Text("Продолжить с Apple").font(.on(16.5, .semibold)) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 50).foregroundStyle(.white)
                    .background(Capsule().fill(Color.black))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel("Войти с Apple")
                if providers.contains("yandex") {
                    oauth("yandex", label: "Войти с Яндекс ID", fill: Color.dyn(0x161A2B, 0x2C3248)) {
                        Text("Я").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(Circle().fill(Color(hex: 0xFC3F1D)))
                    }
                }
                if providers.contains("vk") {
                    oauth("vk", label: "Войти с VK ID", fill: Color(hex: 0x0077FF)) {
                        Text("VK").font(.system(size: 11, weight: .black)).foregroundStyle(Color(hex: 0x0077FF))
                            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7).fill(.white))
                    }
                }
            }
            .buttonStyle(.plain)
            Text(fine).font(.on(12)).foregroundStyle(T.faint).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $oauthURL) { link in
            NavigationStack { WebScreen(path: link.url.absoluteString, title: "Вход", closeOnLogin: true) }
        }
    }

    private struct OAuthStart: Encodable { let next: String; let consent: Bool; let src: String }

    private func oauth<L: View>(_ provider: String, label: String, fill: Color, @ViewBuilder icon: () -> L) -> some View {
        Button {
            Task {
                do {
                    let r: JSONValue = try await API.shared.post("/api/auth/oauth/\(provider)/start", OAuthStart(next: "/profile", consent: true, src: "ios"))
                    guard let s = r["url"]?.string, let u = URL(string: s) else { return }
                    await withCheckedContinuation { c in CookieSync.shared.share("tg_oauth") { c.resume() } }
                    oauthURL = OAuthLink(url: u)
                } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
            }
        } label: {
            icon().frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(fill))
        }
        .accessibilityLabel(label)
    }

    private func apple() async {
        switch await AppleSignIn.shared.authorize() {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { app.show("Apple не подтвердил вход — попробуйте ещё раз", bad: true) }
        case .success(let auth):
            guard let p = AppleSignIn.shared.payload(auth) else { app.show("Apple не прислал данные для входа", bad: true); return }
            do {
                var body = p
                body["consent"] = .bool(true)
                _ = try await API.shared.post("/api/auth/apple", body, as: JSONValue.self)
                await Self.signedIn()
            } catch { app.show((error as? APIError)?.message ?? "Не получилось войти", bad: true) }
        }
    }

    /// Вошли: сессия — страницам сайта и в Связку ключей, профиль — родным экранам.
    @MainActor
    static func signedIn() async {
        Haptics.play("success")
        await withCheckedContinuation { c in CookieSync.shared.adoptNative { c.resume() } }
        await AppState.shared.refreshMe()
    }
}

// MARK: - Шторка входа для гостя

struct LoginSheet: View {
    let ask: AppState.LoginAsk
    @State private var height: CGFloat = 440
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                CategoryChips(count: 4, size: 12.5).padding(.horizontal, 14).padding(.top, 26)
                Text(ask.title).font(.on(23, .heavy)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.top, 16)
                Text(ask.text).font(.on(14.5)).foregroundStyle(.white.opacity(0.88)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 5).padding(.horizontal, 22)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 22)
            .background {
                AuthGradient().overlay(alignment: .topTrailing) {
                    Circle().fill(.white.opacity(0.08)).frame(width: 220, height: 220).offset(x: 70, y: -70)
                }
                .clipped()
            }
            VStack(spacing: 12) {
                AuthButtons()
                Button { open(.login) } label: { HStack(spacing: 10) { MailBadge(); Text("Войти по почте") } }
                    .buttonStyle(TButton(kind: .accent, height: 52))
                Button { open(.register) } label: {
                    (Text("Нет профиля? ").foregroundStyle(T.muted) + Text("Зарегистрироваться").foregroundStyle(T.accent).fontWeight(.bold))
                        .font(.on(15))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(18).padding(.bottom, 8)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }   // шторка — ровно по содержимому
        .frame(maxHeight: .infinity, alignment: .top)
        .background(T.card)
        .presentationDetents([.height(max(height, 300))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onChange(of: app.me?.id) { _, id in if id != nil { dismiss() } }
        .task { await AppleSignIn.shared.prefetchNonce() }
    }

    /// Почта и пароль — на полном экране входа; шторка закрывается, начатое действие ждёт входа.
    private func open(_ mode: LoginView.Mode) {
        app.keepPending = true
        dismiss()
        Task { try? await Task.sleep(nanoseconds: 350_000_000); app.loginFull = mode }
    }
}

/// Значок на «Войти по почте» (решение 26.11, «A»): белая плашка, конверт в фирменном градиенте.
struct MailBadge: View {
    var body: some View {
        Image(systemName: "envelope.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.grad)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
    }
}
