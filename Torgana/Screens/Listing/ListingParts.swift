import SwiftUI

// Части страницы объявления, которые есть и в профиле продавца: строка репутации, уровень, плашки, галочка.

/// Значок 16 и текст через 6 — строки «просмотров» и «в избранном» сайта.
struct MetaLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .regular)).frame(width: 16)
            configuration.title
        }
    }
}

/// Уровень продавца и медаль «Один из первых» — плашками: у каждого уровня своя объёмная монета
/// (Новичок — бронза с листком, Надёжный — изумруд со щитом, Опытный — золото со звездой, Мастер Торганы — бриллиант с короной).
struct RepLine: View {
    let rep: Rep?
    let medal: FirstMedal?
    var body: some View {
        FlowLayout(spacing: 6) {
            if let lvl = rep?.levelName { LevelPill(level: rep?.level ?? 0, name: lvl) }
            if medal?.no != nil {
                Pill(icon: "rosette", text: medal?.form == "f" ? "Одна из первых" : "Один из первых",
                     tint: .white, fill: AnyShapeStyle(T.grad), iconFill: AnyShapeStyle(Color.white.opacity(0.22)))
            }
        }
    }
}

struct LevelPill: View {
    let level: Int
    let name: String
    var body: some View {
        HStack(spacing: 6) {
            LevelCoin(level: level, size: 22)
            Text(name).font(.on(13, .bold)).foregroundStyle(LevelPill.tint(level)).lineLimit(1)
        }
        .padding(.leading, 3).padding(.trailing, 10)
        .frame(height: 28)
        .background(Capsule().fill(LevelPill.tint(level).opacity(0.12)))
    }

    /// Цвет надписи уровня — под цвет монеты.
    static func tint(_ level: Int) -> Color {
        switch level {
        case 1: return Color.dyn(0x13804A, 0x5FD394)
        case 2: return Color.dyn(0x9A5B05, 0xF2C35B)
        case 3...: return Color.dyn(0x5B3DF5, 0xA99BFF)
        default: return Color.dyn(0x8A4B22, 0xE0A37A)
        }
    }
}

/// Монета уровня — та же картинка, что на сайте (levelMedal в app.js): Assets Level0–3.
struct LevelCoin: View {
    let level: Int
    var size: CGFloat = 22
    var body: some View {
        Image("Level\(min(max(level, 0), 3))").resizable().interpolation(.high).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Плашка со значком в кружке: 28 точек, 13/700.
struct Pill: View {
    let icon: String
    let text: String
    let tint: Color
    let fill: AnyShapeStyle
    let iconFill: AnyShapeStyle
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(iconFill))
            Text(text).font(.on(13, .bold)).foregroundStyle(tint).lineLimit(1)
        }
        .padding(.leading, 4).padding(.trailing, 10)
        .frame(height: 28)
        .background(Capsule().fill(fill))
    }
}

/// Галочка «Официальный аккаунт» / проверенный магазин — та же, что на сайте (verifiedSeal).
struct Verified: View {
    var size: CGFloat = 18
    var body: some View {
        Image("VerifiedSeal").resizable().frame(width: size, height: size)
            .accessibilityLabel("Подтверждённый аккаунт")
    }
}
