import SwiftUI
import UIKit

// Фирменный стиль Торганы — те же цвета, что у сайта (public/assets/app.css, :root и тёмная тема).
// Светлая и тёмная тема переключаются вместе с iPhone.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
    /// Цвет со своим значением в тёмной теме.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum T {
    // --bg, --card, --surface, --line, --text …
    static let bg = Color.dyn(0xFFFFFF, 0x0F121B)
    static let card = Color.dyn(0xFFFFFF, 0x171B27)
    static let surface = Color.dyn(0xF0F2FA, 0x1E2331)
    static let surface2 = Color.dyn(0xE6E9F5, 0x272D3E)
    static let line = Color.dyn(0xE1E4F1, 0x2A3043)
    static let text = Color.dyn(0x161A2B, 0xECEEF6)
    static let text2 = Color.dyn(0x3D4256, 0xC6CAD8)
    static let muted = Color.dyn(0x545A70, 0x9AA1B6)
    static let faint = Color.dyn(0x9AA0B4, 0x6C738A)
    static let accent = Color.dyn(0x3963CC, 0x8AA6F6)
    static let accentFill = Color(hex: 0x3D67D0)          // заливки с белым текстом — одинаковые в обеих темах
    static let accentSoft = Color.dyn(0xECEEFC, 0x1E2746)
    static let accentSoft2 = Color.dyn(0xDCE2FA, 0x2A3664)
    static let hot = Color.dyn(0x5B5FD6, 0x8E90F2)
    static let ink = Color.dyn(0x161A2B, 0xECEEF6)       // «тёмные» кнопки; в тёмной теме — светлые
    static let onInk = Color.dyn(0xFFFFFF, 0x11141D)
    static let danger = Color.dyn(0xB42318, 0xFF8D7E)
    static let dangerSoft = Color.dyn(0xFDECEA, 0x3A1E1E)
    static let warnSoft = Color.dyn(0xFFF6E5, 0x33290F)
    static let good = Color.dyn(0x1F8A4C, 0x4CC07E)
    static let goodSoft = Color.dyn(0xE6F5EC, 0x142A1E)
    static let msgOut = Color.dyn(0xE4EAFC, 0x24315A)

    static let grad = LinearGradient(colors: [Color(hex: 0x2E6FCC), Color(hex: 0x5B5FD6)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let gradSoft = LinearGradient(colors: [Color.dyn(0xDCE9FF, 0x1A2646), Color.dyn(0xE9E4FF, 0x251F48)], startPoint: .leading, endPoint: .trailing)

    // Радиусы: --r-card, --r-md, --r-sm
    static let rCard: CGFloat = 28
    static let rMd: CGFloat = 20
    static let rSm: CGFloat = 14
}

// Шрифт сайта — Onest (OFL). Файлы — в Resources/Fonts, из переменного шрифта сайта: 400–800.
enum Onest {
    static func name(_ w: Font.Weight) -> String {
        switch w {
        case .medium: return "Onest-Medium"
        case .semibold: return "Onest-SemiBold"
        case .bold: return "Onest-Bold"
        case .heavy, .black: return "Onest-ExtraBold"
        default: return "Onest-Regular"
        }
    }
}

extension Font {
    /// Onest нужного размера; растёт вместе с системным размером текста.
    static func on(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Onest.name(weight), size: size, relativeTo: style)
    }
}

// Кнопки как на сайте: тёмная (btn-dark), фирменная (btn-accent, градиент), мягкая (btn-soft), контурная (btn-line).
struct TButton: ButtonStyle {
    enum Kind { case dark, accent, soft, line, danger, red }
    var kind: Kind = .dark
    var height: CGFloat = 52
    var full = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.on(16, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(maxWidth: full ? .infinity : nil)
            .frame(height: height)
            .foregroundStyle(fg)
            .background(bg)
            .overlay(Capsule().strokeBorder(kind == .line ? T.line : .clear, lineWidth: 1.5))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var fg: Color {
        switch kind {
        case .dark: return T.onInk
        case .accent: return .white
        case .soft: return T.text
        case .line: return T.text
        case .danger: return T.danger
        case .red: return .white
        }
    }

    @ViewBuilder private var bg: some View {
        switch kind {
        case .dark: T.ink
        case .accent: T.grad
        case .soft: T.surface
        case .line: Color.clear
        case .danger: T.dangerSoft
        case .red: LinearGradient(colors: [Color(hex: 0xEF5A50), Color(hex: 0xC8322A)], startPoint: .top, endPoint: .bottom)
        }
    }
}

// Карточка-панель: белая (в тёмной теме — приподнятая), скругление 28, тонкая обводка.
struct Panel: ViewModifier {
    var radius: CGFloat = T.rCard
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }
}

extension View {
    func panel(radius: CGFloat = T.rCard, padding: CGFloat = 18) -> some View { modifier(Panel(radius: radius, padding: padding)) }
}

enum Fmt {
    private static let num: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{00A0}"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "ru_RU")
        return f
    }()

    static func number(_ n: Int) -> String { num.string(from: NSNumber(value: n)) ?? String(n) }

    /// «45 000 ₽», «35 000 ₽ / мес», «Цена не указана»
    static func price(_ value: Int?, unit: String? = nil) -> String {
        guard let value else { return "Цена не указана" }
        if value == 0 { return "Даром" }
        let base = "\(number(value))\u{00A0}₽"
        if let unit, !unit.isEmpty { return "\(base) / \(unit)" }
        return base
    }

    /// «сегодня», «вчера», «3 ноября», «3 ноября 2025»
    static func day(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "сегодня" }
        if cal.isDateInYesterday(d) { return "вчера" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "d MMMM" : "d MMMM yyyy"
        return f.string(from: d)
    }

    /// «сегодня в 15:17»
    static func dayTime(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let t = DateFormatter()
        t.locale = Locale(identifier: "ru_RU")
        t.dateFormat = "HH:mm"
        return "\(day(ms)) в \(t.string(from: d))"
    }

    /// Склонение: plural(5, "объявление", "объявления", "объявлений")
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }

    /// «На Торгане с ноября 2026»
    static func monthYear(_ ms: Double?) -> String {
        guard let ms else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        let s = f.string(from: Date(timeIntervalSince1970: ms / 1000))
        // «ноябрь 2026» → «ноября 2026»
        let gen = ["январь": "января", "февраль": "февраля", "март": "марта", "апрель": "апреля", "май": "мая", "июнь": "июня",
                   "июль": "июля", "август": "августа", "сентябрь": "сентября", "октябрь": "октября", "ноябрь": "ноября", "декабрь": "декабря"]
        var parts = s.split(separator: " ").map(String.init)
        if let first = parts.first, let g = gen[first.lowercased()] { parts[0] = g }
        return parts.joined(separator: " ")
    }

    /// «0:24», «1:00»
    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /// «234 КБ», «4,2 МБ»
    static func bytes(_ n: Int) -> String {
        n >= 1_048_576 ? String(format: "%.1f МБ", Double(n) / 1_048_576).replacingOccurrences(of: ".", with: ",") : "\(max(1, n / 1024)) КБ"
    }
}
