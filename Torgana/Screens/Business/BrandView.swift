import SwiftUI
import UniformTypeIdentifiers

// Галочка бренда: номер свидетельства, название, срок, документы (видит только модератор)
struct BrandView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @State private var d: TrademarkResponse?
    @State private var number = ""
    @State private var name = ""
    @State private var until = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    @State private var importing: String?
    @State private var busy = false
    @State private var letterOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Для владельцев товарного знака из реестра Роспатента. Галочка стоит рядом с именем везде на Торгане.")
                .font(.on(14)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
            if let d {
                if d.trademark?.live == true { live(d) }
                else if d.trademark?.status == "pending" { pending(d) }
                else { form(d) }
            } else { LoadingView() }
        }
        .task { await load() }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }), allowedContentTypes: [.pdf, .jpeg, .png, .webP]) { r in
            let kind = importing
            if case .success(let url) = r, let kind { Task { await upload(url, kind: kind) } }
        }
    }

    private func live(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Verified(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("«\(d.trademark?.name ?? "")» — бренд подтверждён").font(.on(15, .bold)).foregroundStyle(T.text)
                    Text("Свидетельство № \(d.trademark?.number ?? "") · действует до \(Fmt.day(d.trademark?.until))").font(.on(13)).foregroundStyle(T.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.accentSoft))
            Button("Убрать галочку") { Task { await withdraw("Галочка убрана") } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
    }

    private func pending(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("«\(d.trademark?.name ?? "")», № \(d.trademark?.number ?? "") — на проверке", systemImage: "clock.fill").font(.on(15, .bold)).foregroundStyle(T.text)
                Text("Модератор сверит реестр Роспатента и документы. Пока заявка на проверке, её нельзя менять.").font(.on(13.5)).foregroundStyle(T.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.warnSoft))
            docs(d, locked: true)
            Button("Отозвать заявку") { Task { await withdraw("Заявка отозвана") } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
        }
    }

    private func form(_ d: TrademarkResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tm = d.trademark, tm.status == "rejected", let note = tm.note, !note.isEmpty {
                Label(note, systemImage: "exclamationmark.circle.fill").font(.on(14, .semibold)).foregroundStyle(T.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            } else if d.trademark?.status == "verified" {
                Label("Срок регистрации истёк — галочка снята. Продлите её в Роспатенте и отправьте заново.", systemImage: "exclamationmark.circle.fill")
                    .font(.on(14, .semibold)).foregroundStyle(T.danger).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
            }
            LabeledField(label: "Номер свидетельства") { TextField("Например, 912345", text: $number).keyboardType(.numberPad).modifier(InputBox()) }
            LabeledField(label: "Название бренда, как в свидетельстве") { TextField("Например, ЯБЛОКОФФ", text: $name).modifier(InputBox()) }
            LabeledField(label: "Действует до") {
                DatePicker("", selection: $until, in: Date()..., displayedComponents: .date).labelsHidden().environment(\.locale, Locale(identifier: "ru_RU"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            docs(d, locked: false)
            Button { Task { await send() } } label: { if busy { ProgressView().tint(T.onInk) } else { Text("Отправить на проверку") } }
                .buttonStyle(TButton(kind: .dark, height: 52)).disabled(busy)
        }
    }

    // Документы: свидетельство и письмо с кодом — обязательны, доверенность — если подписывает не руководитель.
    private func docs(_ d: TrademarkResponse, locked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ДОКУМЕНТЫ · ВИДИТ ТОЛЬКО МОДЕРАТОР").font(.on(12, .semibold)).kerning(0.5).foregroundStyle(T.muted).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(["cert", "letter", "power"].enumerated()), id: \.offset) { i, kind in
                    let have = d.docs.filter { $0.kind == kind }
                    HStack(spacing: 12) {
                        Image(systemName: have.isEmpty ? "doc.badge.plus" : "doc.text.fill").font(.system(size: 17)).foregroundStyle(have.isEmpty ? T.muted : T.good)
                            .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(have.isEmpty ? T.surface : T.goodSoft))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind == "letter" ? "Письмо с кодом \(d.code ?? "")" : d.kinds[kind] ?? kind).font(.on(14.5, .semibold)).foregroundStyle(T.text)
                            Text(have.isEmpty ? (kind == "power" ? "если подписывает не руководитель" : "обязательно") : have.map { $0.name ?? "файл" }.joined(separator: ", "))
                                .font(.on(12.5)).foregroundStyle(T.muted).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        if !locked {
                            if let doc = have.first {
                                Button("Удалить") { Task { await remove(doc.id) } }.font(.on(13.5, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
                            } else {
                                Button("Добавить") { importing = kind }.font(.on(13.5, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 14).frame(minHeight: 58)
                    .overlay(alignment: .bottom) { if i < 2 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 60) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            if !locked, let letter = d.letter {
                DisclosureGroup(isExpanded: $letterOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(letter).font(.on(13.5)).foregroundStyle(T.text2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button { UIPasteboard.general.string = letter; app.show("Текст скопирован") } label: { Label("Скопировать текст", systemImage: "doc.on.doc") }
                            .font(.on(14, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                } label: { Text("Текст письма — распечатать, подписать, сфотографировать").font(.on(14, .semibold)).foregroundStyle(T.text) }
                .tint(T.accent)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.surface))
            }
        }
    }

    private func load() async {
        do {
            let r: TrademarkResponse = try await API.shared.get("/api/me/trademark")
            d = r
            if let tm = r.trademark, number.isEmpty {
                number = tm.number ?? ""; name = tm.name ?? ""
                if let u = tm.until, u > Date().timeIntervalSince1970 * 1000 { until = Date(timeIntervalSince1970: u / 1000) }
            }
        } catch is CancellationError {} catch { app.fail(error, "Не удалось загрузить") }
    }

    private func upload(_ url: URL, kind: String) async {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { app.show("Не получилось открыть файл", bad: true); return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            let _: JSONValue = try await API.shared.post("/api/me/verify-docs", ["kind": kind, "name": url.lastPathComponent, "data": "data:\(mime);base64,\(data.base64EncodedString())"])
            await load()
        } catch { app.fail(error, "Не получилось загрузить") }
    }

    private func remove(_ id: Int) async {
        do { let _: JSONValue = try await API.shared.send("DELETE", "/api/me/verify-docs/\(id)", body: Optional<[String: String]>.none); await load() }
        catch { app.fail(error) }
    }

    private func send() async {
        busy = true
        defer { busy = false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        do {
            let _: JSONValue = try await API.shared.post("/api/me/trademark", ["number": number, "name": name, "until": f.string(from: until)])
            await load()
            Haptics.play("success")
            app.show("Отправлено на проверку")
        } catch { app.fail(error, "Не получилось отправить") }
    }

    private func withdraw(_ done: String) async {
        do {
            let _: JSONValue = try await API.shared.send("DELETE", "/api/me/trademark", body: Optional<[String: String]>.none)
            await load()
            await app.refreshMe()
            app.show(done)
        } catch { app.fail(error) }
    }
}
