import SwiftUI

// Главный экран: тариф, чек-лист запуска, витрина, статистика, продвижение, доверие, платежи
struct BizHubView: View {
    let h: BizHub
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var app: AppState

    private var official: Bool { h.shop.official == true }
    private var open: Bool { official || h.plan != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if open { planCard } else { intro }
            if open && !launched { checklist }
            if open {
                SettingsGroup {
                    row(.shop, sub: "заполнено \(shopFilled) из 6 · обложка, описание, адрес", last: true) { nav.push(.business(.shop)) }
                }
                HStack(spacing: 10) {
                    tile(.stats, "просмотры и избранное")
                    tile(.promo, promoSub)
                }
            }
            SettingsGroup(title: "Доверие покупателей") {
                row(.trust, title: bizTitle, sub: "значок у имени", status: bizStatus) { nav.push(.business(.trust)) }
                row(.brand, sub: "для владельцев товарного знака",
                            status: brandStatus, locked: !bizSent, last: true) { nav.push(.business(bizSent ? .brand : .trust)) }
            }
            if open || !(h.payments ?? []).isEmpty {
                SettingsGroup {
                    row(.payments, sub: paySub, last: true) { nav.push(.business(.payments)) }
                }
            }
        }
    }

    // Тариф: что подключено и сколько осталось.
    private var planCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(official ? "Аккаунт" : h.plan?.trial == true ? "Бесплатный период" : "Ваш тариф").font(.on(13)).opacity(0.85)
            Text(official ? "Официальный аккаунт Торганы" : h.plan?.name ?? "").font(.on(22, .heavy))
            Text(official ? "Витрина, статистика и закреплённые — без тарифа" : left).font(.on(13.5)).opacity(0.92)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.grad))
    }

    private var left: String {
        guard let p = h.plan else { return "" }
        let days = max(0, Int(ceil((p.until / 1000 - Date().timeIntervalSince1970) / 86400)))
        return "до \(Fmt.day(p.until)) · осталось \(days) \(Fmt.plural(days, "день", "дня", "дней"))"
    }

    // Без тарифа: что даёт магазин; проверка ИП и галочка — бесплатно и без тарифа.
    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "storefront.fill").font(.system(size: 26)).foregroundStyle(T.accent)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(T.accentSoft))
            VStack(spacing: 6) {
                Text("Магазин на Торгане").font(.on(19, .heavy)).foregroundStyle(T.text)
                Text("Объявления бесплатны для всех. Тариф добавляет витрину, статистику и значок «Магазин».")
                    .font(.on(14)).foregroundStyle(T.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                feature("storefront", "Витрина с обложкой и описанием")
                feature("chart.bar", "Статистика и выгрузка в Excel")
                feature("pin", "Закреплённые товары — в «Магазин Про»")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("Подключение тарифа в приложении скоро появится").font(.on(12.5)).foregroundStyle(T.faint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .panel(radius: 22)
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.on(14.5, .medium)).foregroundStyle(T.text) } icon: { Image(systemName: icon).foregroundStyle(T.accent) }
    }

    // Чек-лист запуска: тариф, обложка и описание, проверка ИП; галочка — по желанию.
    private var steps: [(title: String, sub: String, done: Bool, to: BizSection?)] {
        let cover = !(h.shop.cover ?? "").isEmpty, about = !(h.shop.about ?? "").isEmpty
        return [
            (official ? "Официальный аккаунт" : "Тариф «\(h.plan?.name ?? "")»", official ? "без срока" : left, true, nil),
            ("Обложка и описание", "витрина", cover && about, .shop),
            ("Подтвердите ИП или компанию", h.biz?.status == "pending" ? "на проверке — обычно за день" : "значок «ИП проверен» · 2 минуты", h.biz?.status == "verified", .trust),
            ("Галочка бренда", "по желанию · нужен товарный знак", app.me?.badges?.tm != nil, bizSent ? .brand : .trust),
        ]
    }
    private var launched: Bool { steps.prefix(3).allSatisfy(\.done) }

    private var checklist: some View {
        let done = steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Запуск магазина").font(.on(17, .heavy)).foregroundStyle(T.text)
                    Text("\(done) из \(steps.count) шагов").font(.on(13)).foregroundStyle(T.muted)
                }
                Spacer()
                Text("\(done * 100 / steps.count)%").font(.on(22, .heavy)).foregroundStyle(T.accent)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            GeometryReader { g in
                Capsule().fill(T.surface).overlay(alignment: .leading) { Capsule().fill(T.accent).frame(width: g.size.width * CGFloat(done) / CGFloat(steps.count)) }
            }
            .frame(height: 6).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                Button { if let to = s.to, !s.done { nav.push(.business(to)) } } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(s.done ? T.goodSoft : i == steps.firstIndex { !$0.done } ? T.accentSoft : T.surface)
                            if s.done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(T.good) }
                            else { Text("\(i + 1)").font(.on(14, .heavy)).foregroundStyle(i == steps.firstIndex { !$0.done } ? T.accent : T.muted) }
                        }
                        .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.on(15, .semibold)).foregroundStyle(s.done ? T.muted : T.text).strikethrough(s.done, color: T.faint)
                            Text(s.sub).font(.on(12.5)).foregroundStyle(T.muted)
                        }
                        Spacer(minLength: 6)
                        if !s.done && s.to != nil { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 58).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { T.line.opacity(0.6).frame(height: 1).padding(.leading, 60) }
            }
        }
        .padding(.bottom, 4)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    /// Строка раздела: значок, цвет и название — из BizSection (те же, что в шапке раздела).
    private func row(_ s: BizSection, title: String? = nil, sub: String, status: RowStatus? = nil, locked: Bool = false, last: Bool = false,
                     action: @escaping () -> Void) -> some View {
        SettingsRow(icon: s.icon, color: s.tone.color, title: title ?? s.title, sub: sub, status: status, locked: locked, last: last, action: action)
    }

    private func tile(_ s: BizSection, _ sub: String) -> some View {
        Button { nav.push(.business(s)) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: s.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(s.tone.color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.on(15.5, .semibold)).foregroundStyle(T.text)
                    Text(sub).font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shopFilled: Int {
        let s = h.shop
        return [s.cover, s.about, s.address, s.hours, s.site, s.delivery].filter { !($0 ?? "").isEmpty }.count
    }
    private var promoSub: String {
        let n = (h.promotions ?? []).filter { $0.status == "active" }.count
        return n > 0 ? "\(n) \(Fmt.plural(n, "активное", "активных", "активных"))" : "нет активных"
    }
    private var paySub: String {
        let n = (h.payments ?? []).count
        return n > 0 ? "\(n) \(Fmt.plural(n, "платёж", "платежа", "платежей"))" : "чеки приходят на почту"
    }
    private var bizSent: Bool { ["pending", "verified"].contains(h.biz?.status ?? "") }
    private var bizTitle: String { h.biz?.kind == "org" && h.biz?.status == "verified" ? "Компания проверена" : "ИП или компания" }
    private var bizStatus: RowStatus { TrustView.status(of: h.biz) }
    private var brandStatus: RowStatus? {
        if app.me?.badges?.tm != nil { return RowStatus(text: "Готово", tone: .ok) }
        return bizSent ? nil : RowStatus(text: "После ИП", tone: .off)
    }
}
