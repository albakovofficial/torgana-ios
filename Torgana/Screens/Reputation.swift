import SwiftUI

// Репутация — как на сайте (reputation.js): карточка repCard, «Как считается» и карточка собеседника в переписке.

/// Карточка репутации: уровень за 12 месяцев, сделки / ответ / жалобы, комплименты, вехи.
struct RepCard: View {
    let rep: Rep?

    private static let marks = ["first": "Первая сделка", "10": "10 сделок", "50": "50 сделок", "100": "100 сделок", "year": "Год без жалоб"]

    var body: some View {
        let r = rep
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LevelCoin(level: r?.level ?? 0, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r?.levelName ?? "Новичок").font(.on(18, .heavy)).foregroundStyle(T.text)
                    Text(r?.newbie == false ? "за 12 месяцев" : "сделок пока мало").font(.on(13)).foregroundStyle(T.muted)
                }
                Spacer(minLength: 0)
                if r?.buyer == true {
                    Label("Надёжный покупатель", systemImage: "checkmark").font(.on(12, .bold)).foregroundStyle(T.good)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(Capsule().fill(T.good.opacity(0.12)))
                }
            }
            if r?.newbie == false {
                HStack(spacing: 8) {
                    fact("\(r?.deals ?? 0)", Fmt.plural(r?.deals ?? 0, "сделка", "сделки", "сделок"))
                    if let t = r?.replyText { fact(t, "ответ") }
                    fact("\(r?.complaints ?? 0)", Fmt.plural(r?.complaints ?? 0, "жалоба", "жалобы", "жалоб"), bad: (r?.complaints ?? 0) > 0)
                }
            }
            if let tags = r?.tags, !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.tag) { t in
                        (Text(t.tag + " ") + Text("\(t.n)").fontWeight(.heavy)).font(.on(13, .semibold)).foregroundStyle(T.accent)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(T.accentSoft))
                    }
                }
            }
            if let marks = r?.marks, !marks.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(marks, id: \.self) { m in
                        Label(Self.marks[m] ?? m, systemImage: "star.fill").font(.on(12.5, .semibold)).foregroundStyle(T.text2)
                            .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(T.surface))
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }

    private func fact(_ value: String, _ label: String, bad: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.on(17, .heavy)).foregroundStyle(bad ? T.danger : T.text).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.on(12)).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
    }
}

/// Репутация — как вкладка сайта (repCard + «Как считается»).
struct ReputationPanel: View {
    let rep: Rep?

    private static let steps = [("Новичок", "с первого дня"),
                                ("Надёжный", "телефон и фото профиля · 5 сделок · 3 комплимента · ответ в течение дня"),
                                ("Опытный", "30 сделок · 15 комплиментов · ответ за 1–3 ч · 2 месяца на Торгане"),
                                ("Мастер Торганы", "100 сделок · 50 комплиментов · ответ за час · 3 месяца без жалоб")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RepCard(rep: rep)
            SettingsGroup(title: "Как считается") {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 12) {
                        LevelCoin(level: i, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.0).font(.on(15, .bold)).foregroundStyle(i == (rep?.level ?? 0) ? T.accent : T.text)
                            Text(s.1).font(.on(12.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            Text("Уровень считается по сделкам за 12 месяцев: комплименты покупателей, скорость ответа и подтверждённые жалобы.")
                .font(.on(12.5)).foregroundStyle(T.muted).padding(.horizontal, 4)
        }
    }
}

/// Переписка: нажали на имя (решение 27.11) — карточка собеседника: уровень за 12 месяцев, «Телефон подтверждён»,
/// сделки / ответ / жалобы, комплименты, напоминание о безопасности и «Профиль и все объявления».
struct ChatRepSheet: View {
    let person: Person
    /// Я — покупатель (подсказка о безопасности — для покупателя или для продавца).
    let buyer: Bool
    let openProfile: () -> Void
    @State private var user: PublicUser?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Avatar(name: person.name, url: person.avatar, size: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(.on(19, .heavy)).foregroundStyle(T.text).lineLimit(1)
                        if user?.badges?.phone == true {
                            Pill(icon: "checkmark", text: "Телефон подтверждён", tint: T.good, fill: AnyShapeStyle(T.goodSoft), iconFill: AnyShapeStyle(T.good))
                        }
                    }
                }
                if let user {
                    RepCard(rep: user.rep)
                } else if failed {
                    Text("Не удалось загрузить репутацию").font(.on(14)).foregroundStyle(T.muted)
                } else {
                    LoadingView()
                }
                Label(buyer ? "Не переходите в мессенджеры и не вносите предоплату — общайтесь здесь."
                            : "Не называйте коды из СМС и не переходите по ссылкам «для получения оплаты».", systemImage: "shield.fill")
                    .font(.on(13.5)).foregroundStyle(T.text2)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.surface))
                Button(action: openProfile) {
                    HStack(spacing: 4) {
                        Text("Профиль и все объявления").font(.on(15.5, .semibold))
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(T.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(T.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            do { user = try await API.shared.get("/api/users/\(person.id)", as: UserResponse.self).user }
            catch is CancellationError {}
            catch { failed = true }
        }
    }
}
