import SwiftUI

// Продвижение и платежи
struct PromoList: View {
    let items: [Promotion]
    @EnvironmentObject private var nav: Nav

    var body: some View {
        if items.isEmpty {
            EmptyState(icon: "megaphone", title: "Продвижений пока не было", text: "Продвинутое объявление стоит в блоке «Реклама» над поиском в вашем городе.")
        } else {
            SettingsGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                    Button { if let id = p.listingId { nav.push(.listing(id)) } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.title).font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                                Spacer(minLength: 6)
                                let st = Self.status(p.status)
                                Text(st.text).font(.on(12, .bold)).foregroundStyle(st.tone.ink).padding(.horizontal, 9).frame(height: 24).background(Capsule().fill(st.tone.fill))
                            }
                            Text(line(p)).font(.on(13)).foregroundStyle(T.muted)
                        }
                        .padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) { if i < items.count - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 14) } }
                }
            }
        }
    }

    static func status(_ s: String) -> RowStatus {
        switch s {
        case "active": return RowStatus(text: "Продвигается", tone: .ok)
        case "stopped": return RowStatus(text: "Остановлено", tone: .bad)
        default: return RowStatus(text: "Завершено", tone: .off)
        }
    }

    private func line(_ p: Promotion) -> String {
        if p.status == "stopped" { return p.note ?? "остановлено модератором" }
        let stats = "показов \(Fmt.number(p.shows ?? 0)) · переходов \(Fmt.number(p.clicks ?? 0))"
        return p.status == "active" ? "до \(Fmt.day(p.endsAt)) · \(stats)" : stats
    }
}

struct PaymentList: View {
    let items: [Payment]
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                EmptyState(icon: "doc.text", title: "Платежей пока не было")
            } else {
                SettingsGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.on(14.5, .semibold)).foregroundStyle(T.text).fixedSize(horizontal: false, vertical: true)
                                Text([Fmt.day(p.createdAt), p.method ?? "", (p.refunded ?? 0) > 0 ? "возвращено \(Fmt.price(p.refunded))" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.on(12.5)).foregroundStyle(T.muted)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Fmt.price(p.amount)).font(.on(14.5, .bold)).foregroundStyle(T.text)
                                let st = Self.status(p.status)
                                Text(st.text).font(.on(11.5, .bold)).foregroundStyle(st.tone.ink).padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(st.tone.fill))
                            }
                        }
                        .padding(14)
                        .overlay(alignment: .bottom) { if i < items.count - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 14) } }
                    }
                }
            }
            Text("Кассовые чеки приходят на \(app.me?.email ?? "вашу почту") от ЮKassa.").font(.on(13)).foregroundStyle(T.muted).padding(.horizontal, 4)
        }
    }

    static func status(_ s: String) -> RowStatus {
        switch s {
        case "succeeded": return RowStatus(text: "Оплачен", tone: .ok)
        case "pending": return RowStatus(text: "Ждёт оплаты", tone: .wait)
        case "canceled": return RowStatus(text: "Не оплачен", tone: .off)
        default: return RowStatus(text: "Ошибка", tone: .bad)
        }
    }
}
