import SwiftUI

// Торг в переписке: карточка предложения цены и окно «Предложить цену» / «Своя цена».
// Предложение цены в переписке: сумма, статус, кнопки для того, кому предложили.
struct OfferCard: View {
    let offer: Offer
    let mine: Bool
    let role: String
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kindText).font(.on(12, .bold)).kerning(0.3).foregroundStyle(T.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.price(offer.price)).font(.on(24, .heavy)).foregroundStyle(T.text)
                if let lp = offer.listingPrice, lp != offer.price { Text(Fmt.price(lp)).font(.on(14)).strikethrough().foregroundStyle(T.faint) }
            }
            .padding(.top, 2)
            HStack(spacing: 5) {
                Image(systemName: statusIcon).font(.system(size: 12, weight: .bold))
                Text(statusText)
                Spacer(minLength: 6)
                Text(Fmt.time(offer.createdAt)).font(.on(11)).foregroundStyle(T.faint)
            }
            .font(.on(14, .bold)).foregroundStyle(statusColor)
            .padding(.top, 4)
            if offer.status == "pending" {
                if mine {
                    Button("Отозвать") { onAction("withdraw") }.font(.on(14, .semibold)).foregroundStyle(T.muted).buttonStyle(.plain).padding(.top, 8)
                } else {
                    HStack(spacing: 8) {
                        Button("Принять") { onAction("accept") }.buttonStyle(TButton(kind: .accent, height: 38))
                        Button("Отклонить") { onAction("decline") }.buttonStyle(TButton(kind: .soft, height: 38))
                    }
                    .padding(.top, 10)
                    if role == "seller" && offer.bySeller != true {
                        Button("Предложить свою цену") { onAction("counter") }.buttonStyle(TButton(kind: .line, height: 38)).padding(.top, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 256, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6, bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
                .fill(T.card)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6, bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
                .strokeBorder(T.accentSoft2, lineWidth: 1.5)
        )
    }

    /// «ВАШЕ ПРЕДЛОЖЕНИЕ», «ПРЕДЛОЖЕНИЕ ПОКУПАТЕЛЯ», «ВСТРЕЧНАЯ ЦЕНА».
    private var kindText: String {
        if offer.bySeller == true { return mine ? "ВАША ЦЕНА" : "ВСТРЕЧНАЯ ЦЕНА" }
        return mine ? "ВАШЕ ПРЕДЛОЖЕНИЕ" : "ПРЕДЛОЖЕНИЕ ПОКУПАТЕЛЯ"
    }

    private var other: String { role == "seller" ? "Покупатель" : "Продавец" }

    private var statusText: String {
        switch offer.status {
        case "accepted": return mine ? "\(other) принял" : "Вы приняли"
        case "declined": return mine ? "\(other) отказался" : "Вы отказались"
        case "withdrawn": return "Отозвано"
        case "countered": return "Ответили своей ценой"
        default: return mine ? "Ждём ответа" : "Ждёт вашего ответа"
        }
    }

    private var statusIcon: String {
        switch offer.status {
        case "accepted": return "checkmark"
        case "declined", "withdrawn": return "xmark"
        case "countered": return "arrow.left.arrow.right"
        default: return "clock"
        }
    }

    private var statusColor: Color {
        switch offer.status {
        case "accepted": return T.good
        case "declined", "withdrawn": return T.muted
        default: return T.text2
        }
    }
}

// Ввод суммы: «Предложить цену», «Своя цена».
struct PriceSheet: View {
    let title: String
    let hint: String
    let submit: (Int) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if !hint.isEmpty { Text(hint).font(.on(15)).foregroundStyle(T.muted) }
                HStack {
                    TextField("Сумма", text: $value).keyboardType(.numberPad).font(.on(28, .bold)).focused($focused)
                    Text("₽").font(.on(28, .bold)).foregroundStyle(T.muted)
                }
                .padding(.horizontal, 18).frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
                if let error { Text(error).font(.on(14)).foregroundStyle(T.danger) }
                Button {
                    Task {
                        busy = true
                        error = await submit(Int(value.filter(\.isNumber)) ?? 0)
                        busy = false
                        if error == nil { dismiss() }
                    }
                } label: { if busy { ProgressView().tint(.white) } else { Text("Отправить") } }
                .buttonStyle(TButton(kind: .accent))
                .disabled(value.filter(\.isNumber).isEmpty || busy)
                Spacer()
            }
            .padding(20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
