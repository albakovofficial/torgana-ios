import SwiftUI
import AuthenticationServices

// Общее для экрана входа и шторки входа: градиентная шапка, плашки категорий, кнопки Apple / Яндекс ID / VK ID,
// шторка входа для гостя и значок письма.
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
                    await CookieSync.shared.share("tg_oauth")
                    oauthURL = OAuthLink(url: u)
                } catch { app.fail(error) }
            }
        } label: {
            icon().frame(maxWidth: .infinity).frame(height: 50).background(Capsule().fill(fill))
        }
        .accessibilityLabel(label)
    }

    private func apple() async {
        guard await AppleSignIn.shared.prefetchNonce() else { app.show(APIError.offline.message, bad: true); return }
        var body: [String: JSONValue]
        do { body = try await AppleSignIn.shared.authorize() } catch {
            if (error as? ASAuthorizationError)?.code != .canceled { app.show(error.userMessage("Apple не подтвердил вход — попробуйте ещё раз"), bad: true) }
            return
        }
        do {
            body["consent"] = .bool(true)
            _ = try await API.shared.post("/api/auth/apple", body, as: JSONValue.self)
            await Self.signedIn()
        } catch { app.fail(error, "Не получилось войти") }
    }

    /// Вошли: сессия — страницам сайта и в Связку ключей, профиль — родным экранам.
    @MainActor
    static func signedIn() async {
        Haptics.play("success")
        await CookieSync.shared.adoptNative()
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
