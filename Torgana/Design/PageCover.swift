import SwiftUI

// Шапка внутренних страниц (решение 27.11, «одна строка»): мягкая скруглённая обложка, в ней «‹», заголовок,
// подпись под ним и значок раздела справа. Та же шапка на сайте — cover.js (.pcover): страницы сайта внутри
// приложения отдают её заголовок, подпись, значок и тон через data-атрибуты, а рисует её приложение.

extension T {
    /// Фон обложки: светлый сине-сиреневый сверху вниз (--cover сайта).
    static let cover = LinearGradient(colors: [Color.dyn(0xECEEFC, 0x1C2440), Color.dyn(0xF6F7FD, 0x161B2B)], startPoint: .top, endPoint: .bottom)
}

/// Тон плитки со значком — те же градиенты, что у .tile-ic.t-* сайта.
enum Tone: String {
    case blue, red, purple, yellow, teal, green, gray

    var gradient: LinearGradient {
        let (a, b) = stops
        return LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Ровный цвет тона — для маленьких значков строк настроек.
    var color: Color { Color(hex: stops.1) }

    private var stops: (UInt32, UInt32) {
        switch self {
        case .blue: (0x4C86E0, 0x3D67D0)
        case .red: (0xF06A5D, 0xD23F33)
        case .purple: (0x9A8CF2, 0x6A55DE)
        case .yellow: (0xF6C453, 0xE08A1E)
        case .teal: (0x3DBFAE, 0x1F8E80)
        case .green: (0x55B776, 0x2E8F4E)
        case .gray: (0x7D8AA8, 0x55617E)
        }
    }
}

/// Значок: символ iPhone или свой рисунок из Assets («asset:Handshake» — рукопожатие репутации, его нет среди символов).
struct Glyph: View {
    let name: String
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        if name.hasPrefix("asset:") {
            Image(String(name.dropFirst(6))).renderingMode(.template).resizable().scaledToFit().frame(width: size * 1.2, height: size * 1.2)
        } else {
            Image(systemName: name).font(.system(size: size, weight: weight))
        }
    }
}

/// Плитка со значком: скруглённый квадрат с градиентом тона, белый значок.
struct ToneTile: View {
    let icon: String
    var tone: Tone = .blue
    var size: CGFloat = 40

    var body: some View {
        Glyph(name: icon, size: size * 0.42)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(tone.gradient))
            .accessibilityHidden(true)
    }
}

/// Обложка раздела. below — то, что лежит в обложке под заголовком (поиск, вкладки, кнопка).
struct PageCover<Below: View>: View {
    let title: String
    var sub: String? = nil
    var icon: String? = nil
    var tone: Tone = .blue
    var back: (() -> Void)? = nil
    @ViewBuilder var below: () -> Below

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BackButton(action: back)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.on(23, .heavy)).foregroundStyle(T.text).lineLimit(2).minimumScaleFactor(0.8)
                    if let sub, !sub.isEmpty {
                        Text(sub).font(.on(14.5)).foregroundStyle(T.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let icon { ToneTile(icon: icon, tone: tone) }
            }
            below()
        }
        .padding(14).padding(.bottom, 2)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(T.cover))
        .padding(.top, 6)
    }
}

extension PageCover where Below == EmptyView {
    init(title: String, sub: String? = nil, icon: String? = nil, tone: Tone = .blue, back: (() -> Void)? = nil) {
        self.init(title: title, sub: sub, icon: icon, tone: tone, back: back) { EmptyView() }
    }
}

/// Шапка страницы сайта (data-атрибуты .pcover): значок сайта переводится в символ SF.
struct WebCover: Equatable {
    var title = ""
    var sub = ""
    var icon = ""
    var tone = ""

    var symbol: String? {
        if icon.isEmpty { return nil }
        return Self.symbols[icon] ?? "doc.text.fill"
    }

    var toneValue: Tone { Tone(rawValue: tone) ?? .blue }

    private static let symbols = [
        "info": "info", "search": "magnifyingglass", "tag": "tag.fill", "shield": "shield.fill", "handshake": "asset:Handshake",
        "list": "list.bullet", "chat": "bubble.left.and.bubble.right.fill", "edit": "doc.text.fill", "lock": "lock.fill",
        "check": "checkmark", "store": "storefront.fill", "chart": "chart.bar.fill", "users": "person.2.fill",
        "heart": "heart.fill", "gear": "gearshape.fill"
    ]
}
