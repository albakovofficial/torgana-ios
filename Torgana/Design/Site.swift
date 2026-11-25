import SwiftUI
import UIKit

// Каркас страниц как у мобильного сайта: шапка (знак «торгана», колокольчик, меню с аватаркой), фон страницы —
// сверху слегка голубой (body в app.css: --c-edf2ff → --bg за 340 px), заголовки и ссылка «назад» над заголовком.
// Размеры — из сайта на ширине iPhone (393 px): 1 px сайта = 1 точка экрана.

extension T {
    static let pageTop = Color.dyn(0xEDF2FF, 0x141A2C)
    static let glass = Color.dyn(0xFFFFFF, 0x0F121B)
    static let line2 = Color.dyn(0xCFCFCA, 0x3B4258)
    /// Переход страницы: голубоватый сверху → фон.
    static let page = LinearGradient(stops: [.init(color: pageTop, location: 0), .init(color: bg, location: 1)], startPoint: .top, endPoint: .bottom)
}

/// Фон страницы сайта: голубоватый верх на 340 точек, дальше — фон темы.
struct SiteBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            T.page.frame(height: 340)
            T.bg
        }
        .ignoresSafeArea()
    }
}

/// Шапка сайта: 64 точки, знак 36, «торгана» 20/700, колокольчик 44, меню-«таблетка» 70×40 с аватаркой 30.
struct SiteHeader: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var menu = false

    var body: some View {
        HStack(spacing: 0) {
            Button { nav.open(path: "/") } label: {
                HStack(spacing: 10) {
                    Image("Logo").resizable().frame(width: 36, height: 36).clipShape(Circle())
                    Text("торгана").font(.on(20, .bold)).foregroundStyle(T.text)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Торгана, на главную")
            Spacer()
            if app.me != nil {
                Button { nav.push(.notices) } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(T.text)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) { CountBadge(n: app.notices).offset(x: -2, y: 4) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Уведомления")
                .padding(.trailing, 8)
            }
            Button { menu = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 16, weight: .semibold)).foregroundStyle(T.text)
                    if let me = app.me {
                        Avatar(name: me.name, url: me.avatar, size: 30)
                    } else {
                        Image(systemName: "person").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.accent)
                            .frame(width: 30, height: 30).background(Circle().fill(T.accentSoft))
                    }
                }
                .padding(.leading, 10).padding(.trailing, 4)
                .frame(height: 40)
                .background(Capsule().fill(T.card))
                .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.me == nil ? "Меню" : "Меню профиля")
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(T.glass.opacity(0.92).background(.ultraThinMaterial).ignoresSafeArea(edges: .top))
        .sheet(isPresented: $menu) { SiteMenu().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
    }
}

/// Число в кружке (непрочитанное): 18 точек, 11/700, синий с белой обводкой — как .badge сайта.
struct CountBadge: View {
    let n: Int
    var body: some View {
        if n > 0 {
            Text(n > 99 ? "99+" : "\(n)")
                .font(.on(11, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(T.accentFill))
                .overlay(Capsule().strokeBorder(T.card, lineWidth: 2))
        }
    }
}

/// Меню из шапки (на сайте — выезжающая панель): разделы профиля, помощь, вход и выход.
struct SiteMenu: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let me = app.me {
                    Button { go("/profile") } label: {
                        HStack(spacing: 12) {
                            Avatar(name: me.name, url: me.avatar, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(me.name).font(.on(17, .bold)).foregroundStyle(T.text)
                                Text("Профиль и настройки").font(.on(13)).foregroundStyle(T.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Войти или зарегистрироваться") { dismiss(); app.requireLogin(Tab.profile.loginAsk) }.buttonStyle(TButton(kind: .dark))
                }
                SettingsGroup {
                    SettingsRow(icon: "headphones", color: Tint.green, title: "Поддержка", sub: "Отвечают люди, а не боты") { go("/messages/support") }
                    SettingsRow(icon: "questionmark", color: Tint.sky, title: "Помощь и безопасность") { go("/page/help") }
                    SettingsRow(icon: "doc.text", color: Tint.gray, title: "Правила и документы", last: true) { go("/page/rules") }
                }
            }
            .padding(20)
        }
        .background(T.bg)
    }

    private func go(_ path: String) { dismiss(); nav.open(path: path) }
}

/// Группа строк, как в «Настройках» iPhone: белая карточка с обводкой, скругление 20, тонкие разделители.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased()).font(.on(12, .semibold)).kerning(0.5).foregroundStyle(T.muted).padding(.horizontal, 4)
            }
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Строка настроек: цветной квадрат со значком (белый значок, как в «Настройках» iPhone), название, пояснение, справа — счётчик и стрелка.
struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var sub: String? = nil
    var badge = 0
    var last = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.on(15.5, .medium)).foregroundStyle(T.text).lineLimit(1)
                    if let sub, !sub.isEmpty { Text(sub).font(.on(12.5)).foregroundStyle(T.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                CountBadge(n: badge)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint)
            }
            .padding(.horizontal, 14).frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { T.line.opacity(0.6).frame(height: 1).padding(.leading, 58) } }
    }
}

/// Цвета значков настроек (насыщенные, как в iOS).
enum Tint {
    static let blue = Color(hex: 0x3963CC)
    static let sky = Color(hex: 0x2E8BEA)
    static let green = Color(hex: 0x2FA45F)
    static let red = Color(hex: 0xE5484D)
    static let violet = Color(hex: 0x8A5CF0)
    static let indigo = Color(hex: 0x5B5FD6)
    static let orange = Color(hex: 0xE9A23B)
    static let gray = Color(hex: 0x7A8094)
}

/// Поиск сайта (.home-search): белая «таблетка» 50 с обводкой, внутри — город (36, --surface) и круглая синяя кнопка 36.
/// На главной поле — кнопка (открывает поиск), на странице поиска — настоящее поле ввода.
struct SearchCapsule: View {
    var text: Binding<String>? = nil
    var focus: FocusState<Bool>.Binding? = nil
    let city: String
    var onField: () -> Void = {}
    let onCity: () -> Void
    let onGo: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(T.muted).padding(.trailing, 10)
            if let text {
                field(text)
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = ""; onGo() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.faint).padding(.horizontal, 6) }
                        .buttonStyle(.plain)
                }
            } else {
                Button(action: onField) {
                    Text("Поиск").font(.on(17)).foregroundStyle(T.faint).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(action: onCity) {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 13, weight: .medium)).foregroundStyle(T.accent)
                    Text(city.isEmpty ? "Вся Россия" : city).font(.on(13.5, .semibold)).foregroundStyle(T.text).lineLimit(1)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(Capsule().fill(T.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Город: \(city.isEmpty ? "Вся Россия" : city)")
            Button(action: onGo) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Circle().fill(T.accentFill))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Найти")
        }
        .padding(.leading, 16).padding(.trailing, 7)
        .frame(height: 50)
        .background(Capsule().fill(T.card))
        .overlay(Capsule().strokeBorder(T.line, lineWidth: 1))
        .shadow(color: Color(hex: 0x101010).opacity(0.04), radius: 1, y: 1)
    }

    @ViewBuilder private func field(_ text: Binding<String>) -> some View {
        let f = TextField("Поиск", text: text).font(.on(17)).submitLabel(.search).onSubmit(onGo)
        if let focus { f.focused(focus) } else { f }
    }
}

/// Плашка-кнопка 40 на --surface (.rh-filters, .pick-btn сайта).
struct SoftPill<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    var body: some View {
        Button(action: action) {
            label().font(.on(14, .semibold)).foregroundStyle(T.text)
                .padding(.horizontal, 12).frame(height: 40)
                .background(Capsule().fill(T.surface))
        }
        .buttonStyle(.plain)
    }
}

/// Переключатель (.ed-seg, .seg сайта): «таблетка» --surface, выбранное — белое с тенью.
struct Seg: View {
    let items: [(String, String)]
    @Binding var value: String
    /// Число у вкладки («Объявления 12») и монета уровня («Репутация»).
    var counts: [String: Int] = [:]
    var level: (key: String, level: Int)? = nil
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                let on = value == items[i].0
                Button { value = items[i].0; Haptics.play("selection") } label: {
                    HStack(spacing: 6) {
                        if level?.key == items[i].0 { LevelCoin(level: level?.level ?? 0, size: 18) }
                        Text(items[i].1).font(.on(14, on ? .bold : .semibold)).foregroundStyle(on ? T.text : T.text2).lineLimit(1).minimumScaleFactor(0.8)
                        if let n = counts[items[i].0] {
                            Text("\(n)").font(.on(11.5, .semibold)).foregroundStyle(T.onInk)
                                .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20).background(Capsule().fill(T.ink))
                        }
                    }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(on ? T.card : .clear).shadow(color: Color(hex: 0x101010).opacity(on ? 0.08 : 0), radius: 5, y: 2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(T.surface))
    }
}

/// Поле ввода сайта (.input): белое, обводка, скругление 16, высота 52.
struct InputBox: ViewModifier {
    var multiline = false
    func body(content: Content) -> some View {
        content
            .font(.on(16))
            .padding(.horizontal, 16)
            .padding(.vertical, multiline ? 14 : 0)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }
}

/// Страница как на сайте: своя шапка вместо системной панели, фон с голубым верхом, место под нижнее меню.
/// Назад — свайпом от края (SwipeBack ниже) и круглой стрелкой (BackButton) в самой странице.
struct SitePage: ViewModifier {
    var header = true
    func body(content: Content) -> some View {
        content
            .background(SiteBackground())
            .safeAreaInset(edge: .top, spacing: 0) { if header { SiteHeader() } }
            .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    func sitePage(header: Bool = true) -> some View { modifier(SitePage(header: header)) }
}

/// Кнопка «назад» на всех экранах (решение 25.11): круглая стрелка без подписи и без «хлебных крошек».
/// По умолчанию закрывает экран; можно передать своё действие.
struct BackButton: View {
    var action: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { if let action { action() } else { dismiss() } } label: {
            Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(T.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(T.card))
                .overlay(Circle().strokeBorder(T.line, lineWidth: 1))
                .shadow(color: Color(hex: 0x161A2B).opacity(0.08), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Назад")
    }
}

/// Шапка раздела: круглая стрелка назад и, если есть, крупный заголовок в той же строке.
struct PageHeader: View {
    var title: String? = nil
    var back: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            BackButton(action: back)
            if let title {
                Text(title).font(.on(28, .heavy)).foregroundStyle(T.text).lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .padding(.top, 6)
    }
}

/// Круглая кнопка-значок (.icon-btn): 44, фон --surface.
struct RoundIcon: View {
    let icon: String
    var size: CGFloat = 44
    var fill: Color = T.surface
    var tint: Color = T.text
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
    }
}

// Свайп «назад» от края работает и без системной панели навигации.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
