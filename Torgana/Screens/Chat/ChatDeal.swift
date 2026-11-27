import SwiftUI

// Сделка в переписке — как на сайте (reputation.js, dealBar): «Сделка состоялась? Да / Нет», ожидание второй стороны,
// «Что понравилось?» после подтверждения обеими сторонами и «Что-то пошло не так» — жалоба модератору.
// Push «Сделка состоялась?» открывает эту переписку — здесь и отвечают, без перехода на сайт.

struct DealState: Codable, Hashable {
    struct Issue: Codable, Hashable { let status: String }
    let role: String?
    let mine: String?           // "yes" | "no" | ""
    let other: Bool?            // вторая сторона уже подтвердила
    let confirmed: Bool?
    let ready: Bool?            // переписка достаточная, чтобы спрашивать
    let praised: Bool?
    let tags: [String]?
    let reasons: [String]?
    let issue: Issue?
    let canIssue: Bool?
}
struct DealResult: Codable { let deal: DealState? }

struct DealBar: View {
    let deal: DealState
    let send: (String, [String: JSONValue]) async -> Bool   // действие и тело запроса; true — получилось
    @State private var picked: [String] = []
    @State private var issueOpen = false
    @State private var busy = false

    private var otherName: String { deal.role == "buyer" ? "продавец" : "покупатель" }
    private var issueText: String? {
        guard let s = deal.issue?.status else { return nil }
        return ["open": "Жалоба у модератора", "confirmed": "Жалоба подтверждена", "dismissed": "Жалоба не подтвердилась"][s]
    }
    private var canProblem: Bool { deal.canIssue == true && deal.issue == nil }

    var body: some View {
        if let content = content { content.padding(.horizontal, 12).padding(.top, 8) }
    }

    private var content: AnyView? {
        if deal.confirmed == true && deal.praised != true {
            return AnyView(card {
                Label("Сделка подтверждена. Что понравилось?", systemImage: "checkmark").font(.on(15, .bold)).foregroundStyle(T.text)
                FlowTags(tags: deal.tags ?? [], picked: $picked)
                HStack(spacing: 10) {
                    Button("Отправить") { act("praise", ["tags": .array(picked.map { .string($0) })], ok: "Спасибо! Отметки появятся в репутации") }
                        .buttonStyle(TButton(kind: .dark, height: 38, full: false)).disabled(picked.isEmpty || busy)
                    footer
                }
            })
        }
        if deal.confirmed == true || deal.ready != true || deal.mine == "no" {
            return issueText != nil || (canProblem && (deal.confirmed == true || deal.mine == "no")) ? AnyView(slim { footer }) : nil
        }
        if deal.mine == "yes" {
            return AnyView(slim {
                Label("Ждём, когда подтвердит \(otherName)", systemImage: "clock").font(.on(14, .medium)).foregroundStyle(T.muted)
                Spacer(minLength: 4)
                footer
            })
        }
        return AnyView(card {
            (Text("Сделка состоялась?").font(.on(15, .bold)).foregroundColor(T.text)
             + Text(deal.other == true ? "  \(otherName.capitalized) уже подтвердил" : "").font(.on(13)).foregroundColor(T.muted))
            HStack(spacing: 8) {
                Button("Да") { act("deal", ["answer": .string("yes")], ok: "Отметили — ждём вторую сторону") }.buttonStyle(TButton(kind: .dark, height: 38, full: false)).disabled(busy)
                Button("Нет") { act("deal", ["answer": .string("no")], ok: "Хорошо, не засчитываем") }.buttonStyle(TButton(kind: .soft, height: 38, full: false)).disabled(busy)
                footer
            }
        })
    }

    @ViewBuilder private var footer: some View {
        if let t = issueText {
            Label(t, systemImage: "exclamationmark.triangle").font(.on(13, .medium)).foregroundStyle(T.muted)
        } else if canProblem {
            Button("Что-то пошло не так") { issueOpen = true }.font(.on(13.5, .semibold)).foregroundStyle(T.muted).buttonStyle(.plain)
                .sheet(isPresented: $issueOpen) {
                    IssueSheet(reasons: deal.reasons ?? []) { reason, text in
                        await send("issue", ["reason": .string(reason), "text": .string(text)])
                    }
                }
        }
    }

    private func act(_ what: String, _ body: [String: JSONValue], ok: String) {
        busy = true
        Task {
            if await send(what, body) { AppState.shared.show(ok); picked = [] }
            busy = false
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10, content: c)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.accentSoft))
    }
    private func slim<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10, content: c).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
    }
}

// Метки «Что понравилось» — до трёх, переносятся по строкам.
private struct FlowTags: View {
    let tags: [String]
    @Binding var picked: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { t in
                let on = picked.contains(t)
                Button {
                    if on { picked.removeAll { $0 == t } } else if picked.count < 3 { picked.append(t) } else { AppState.shared.show("Не больше трёх", bad: true) }
                } label: {
                    Text(t).font(.on(13.5, .semibold)).foregroundStyle(on ? .white : T.text2)
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(Capsule().fill(on ? T.accentFill : T.card))
                        .overlay(Capsule().strokeBorder(on ? .clear : T.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct IssueSheet: View {
    let reasons: [String]
    let send: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Что случилось?").font(.on(22, .heavy)).foregroundStyle(T.text)
            Text("Увидит только модератор. Вторая сторона сможет объясниться.").font(.on(14)).foregroundStyle(T.muted)
            VStack(spacing: 8) {
                ForEach(reasons, id: \.self) { r in
                    Button { reason = r } label: {
                        HStack {
                            Text(r).font(.on(15, .medium)).foregroundStyle(T.text)
                            Spacer()
                            Image(systemName: reason == r ? "largecircle.fill.circle" : "circle").foregroundStyle(reason == r ? T.accent : T.faint)
                        }
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("Подробности — по желанию", text: $text, axis: .vertical).lineLimit(3...5)
                .font(.on(15)).padding(12).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
            Button("Отправить модератору") {
                busy = true
                Task { if await send(reason, String(text.prefix(500))) { AppState.shared.show("Отправлено модератору"); dismiss() }; busy = false }
            }
            .buttonStyle(TButton(kind: .dark)).disabled(reason.isEmpty || busy)
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.large])
        .onAppear { reason = reasons.first ?? "" }
    }
}
