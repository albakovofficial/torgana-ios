import SwiftUI

// Доверие: как видят покупатели, проверка ИП или компании, переход к галочке
struct TrustView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var name = ""
    @State private var inn = ""
    @State private var ogrn = ""
    @State private var busy = false

    static func status(of b: BizCheck?) -> RowStatus {
        switch b?.status {
        case "verified": return RowStatus(text: "Готово", tone: .ok)
        case "pending": return RowStatus(text: "На проверке", tone: .wait)
        case "rejected": return RowStatus(text: "Исправить", tone: .bad)
        default: return RowStatus(text: "Не начато", tone: .off)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preview
            switch h.biz?.status {
            case "verified": verified
            case "pending": pending
            default: form
            }
            SettingsGroup {
                SettingsRow(icon: "checkmark.seal.fill", color: Tint.sky, title: "Галочка бренда",
                            sub: sent ? "для владельцев товарного знака" : "после отправки данных ИП или компании",
                            status: app.me?.badges?.tm != nil ? RowStatus(text: "Готово", tone: .ok) : nil, locked: !sent, last: true) {
                    if sent { nav.push(.business(.brand)) }
                }
            }
        }
        .onAppear { if name.isEmpty, let b = h.biz { name = b.name ?? ""; inn = b.inn ?? ""; ogrn = b.ogrn ?? "" } }
    }

    private var sent: Bool { ["pending", "verified"].contains(h.biz?.status ?? "") }

    // Как значки выглядят у имени.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Так видят покупатели").font(.on(13)).foregroundStyle(T.muted)
            HStack(spacing: 12) {
                Avatar(name: app.me?.name ?? "", url: app.me?.avatar, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(app.me?.name ?? "").font(.on(16, .heavy)).foregroundStyle(T.text)
                        if app.me?.badges?.tm != nil || app.me?.badges?.official == true { Verified(size: 17) }
                    }
                    if h.biz?.status == "verified" {
                        Label(h.biz?.kind == "org" ? "Компания проверена" : "ИП проверен", systemImage: "checkmark.shield.fill")
                            .font(.on(13, .semibold)).foregroundStyle(T.good)
                    } else {
                        Text("значков пока нет").font(.on(13)).foregroundStyle(T.faint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
    }

    private var verified: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundStyle(T.good)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(h.biz?.name ?? "") — \(h.biz?.kind == "org" ? "компания проверена" : "ИП проверен")").font(.on(15, .bold)).foregroundStyle(T.text)
                Text("ИНН \(h.biz?.inn ?? "") · значок стоит у вашего имени").font(.on(13)).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.goodSoft))
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(h.biz?.name ?? "") — на проверке", systemImage: "clock.fill").font(.on(15, .bold)).foregroundStyle(T.text)
            Text("Отправлено \(Fmt.day(h.biz?.at)). Обычно проверяем за день — пришлём уведомление.").font(.on(13.5)).foregroundStyle(T.text2)
            Button("Отозвать заявку") { Task { await withdraw() } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.warnSoft))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ИП или компания").font(.on(18, .heavy)).foregroundStyle(T.text)
                Text("Сверим с ЕГРЮЛ или ЕГРИП — у имени появится значок «ИП проверен» или «Компания проверена».")
                    .font(.on(13.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            }
            if h.biz?.status == "rejected", let note = h.biz?.note, !note.isEmpty {
                Label(note, systemImage: "exclamationmark.circle.fill").font(.on(14, .semibold)).foregroundStyle(T.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            }
            LabeledField(label: "Название") { TextField("ИП Иванов И. И. или ООО «Ромашка»", text: $name).modifier(InputBox()) }
            HStack(alignment: .top, spacing: 10) {
                LabeledField(label: "ИНН") { TextField("10 или 12 цифр", text: $inn).keyboardType(.numberPad).modifier(InputBox()) }
                LabeledField(label: "ОГРН или ОГРНИП") { TextField("13 или 15 цифр", text: $ogrn).keyboardType(.numberPad).modifier(InputBox()) }
            }
            Text("ИНН видит только модератор.").font(.on(12.5)).foregroundStyle(T.muted)
            Button { Task { await send() } } label: { if busy { ProgressView().tint(T.onInk) } else { Text("Отправить на проверку") } }
                .buttonStyle(TButton(kind: .dark, height: 52)).disabled(busy)
        }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        do {
            let _: JSONValue = try await API.shared.post("/api/me/business", ["name": name, "inn": inn, "ogrn": ogrn])
            await BizStore.shared.load()
            Haptics.play("success")
            app.show("Отправлено на проверку")
        } catch { app.fail(error, "Не получилось отправить") }
    }

    private func withdraw() async {
        do {
            let _: JSONValue = try await API.shared.send("DELETE", "/api/me/business", body: Optional<[String: String]>.none)
            await BizStore.shared.load()
            await app.refreshMe()
            app.show("Заявка отозвана")
        } catch { app.fail(error) }
    }
}
