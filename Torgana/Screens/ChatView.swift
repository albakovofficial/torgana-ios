import SwiftUI
import PhotosUI

// Переписка: по объявлению или с поддержкой. Пузыри, ответы на сообщение, фото, галочки «прочитано», «печатает…»,
// предложение цены. Новые сообщения — раз в 2,5 секунды, пока чат на экране (как сайт).
struct ChatView: View {
    enum Kind: Hashable { case conv(Int), support }
    let kind: Kind

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.scenePhase) private var phase
    @State private var data: ChatData?
    @State private var messages: [Message] = []
    @State private var offers: [Offer] = []
    @State private var readUpTo = 0
    @State private var typing = false
    @State private var error: String?
    @State private var text = ""
    @State private var replyTo: Message?
    @State private var sending = false
    @State private var photoItem: PhotosPickerItem?
    @State private var offerSheet = false
    @State private var counterFor: Offer?
    @State private var lastTypingPing = Date.distantPast
    @State private var confirmBlock = false
    @FocusState private var focused: Bool

    private var convId: Int? { if case .conv(let id) = kind { return id } else { return nil } }

    var body: some View {
        VStack(spacing: 0) {
            if let l = data?.listing { listingBar(l) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if messages.isEmpty && error == nil {
                            if data == nil && convId != nil { LoadingView() } else { hint }
                        }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            if i == 0 || !Calendar.current.isDate(date(m), inSameDayAs: date(messages[i - 1])) {
                                Text(Fmt.day(m.createdAt).capitalizedFirst).font(.on(12, .semibold)).foregroundStyle(T.faint).padding(.vertical, 8)
                            }
                            bubble(m).id(m.id)
                        }
                        if typing {
                            HStack { TypingDots().padding(.leading, 6); Spacer() }.id("typing")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
                }
                .onChange(of: focused) { _, f in
                    if f, let id = messages.last?.id { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
            }
            composer
        }
        .background(T.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .hidesTabBar()
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        .onChange(of: photoItem) { _, item in if let item { Task { await sendPhoto(item) } } }
        .onChange(of: text) { _, t in pingTyping(t) }
        .sheet(isPresented: $offerSheet) {
            PriceSheet(title: "Предложить цену", hint: data?.listing?.price.map { "Сейчас — \(Fmt.price($0))" } ?? "") { price in await makeOffer(price) }
        }
        .sheet(item: $counterFor) { o in
            PriceSheet(title: "Своя цена", hint: "Покупатель предложил \(Fmt.price(o.price))") { price in await act(o, "counter", price: price) }
        }
        .confirmationDialog(data?.block == "me" ? "Разблокировать?" : "Заблокировать собеседника?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button(data?.block == "me" ? "Разблокировать" : "Заблокировать", role: data?.block == "me" ? nil : .destructive) { Task { await toggleBlock() } }
        } message: {
            Text(data?.block == "me" ? "Он снова сможет вам писать." : "Он не сможет вам писать, а его объявления пропадут из вашей выдачи.")
        }
    }

    private var title: String {
        switch kind {
        case .support: return "Поддержка"
        case .conv: return data?.other?.name ?? "Переписка"
        }
    }

    private var hint: some View {
        Text(kind == .support ? "Напишите, что случилось, — модератор ответит здесь же. Можно приложить снимок экрана." : "Начните переписку — продавец получит уведомление.")
            .font(.on(14)).foregroundStyle(T.muted).multilineTextAlignment(.center).padding(30)
    }

    private func date(_ m: Message) -> Date { Date(timeIntervalSince1970: (m.createdAt ?? 0) / 1000) }

    // MARK: шапка с объявлением
    private func listingBar(_ l: ChatListing) -> some View {
        Button { nav.push(.listing(l.id)) } label: {
            HStack(spacing: 12) {
                RemoteImage(url: API.shared.media(l.photo)).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.title).font(.on(15, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    Text(l.status == "active" || l.status == nil ? Fmt.price(l.price, unit: l.priceUnit) : (l.status == "sold" ? "Продано" : "Снято с публикации"))
                        .font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
                }
                Spacer()
                if data?.conversation?.role == "buyer" && l.status == "active" && (l.bargain ?? true) && data?.block == nil {
                    Button("Своя цена") { offerSheet = true }
                        .font(.on(14, .semibold)).foregroundStyle(T.accent)
                        .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.accentSoft))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(T.card)
            .overlay(alignment: .bottom) { Divider().overlay(T.line) }
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let o = data?.other, convId != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { nav.push(.user(o.id)) } label: { Label("Профиль собеседника", systemImage: "person") }
                    if let id = convId { Button { nav.push(.web("/messages/\(id)")) } label: { Label("Сделка и отзыв", systemImage: "hand.thumbsup") } }
                    Button(role: data?.block == "me" ? nil : .destructive) { confirmBlock = true } label: {
                        Label(data?.block == "me" ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    // MARK: пузырь
    @ViewBuilder private func bubble(_ m: Message) -> some View {
        if m.kind == "offer", let oid = m.offerId, let o = offers.first(where: { $0.id == oid }) {
            OfferCard(offer: o, mine: m.mine, role: data?.conversation?.role ?? "") { action in
                if action == "counter" { counterFor = o } else { Task { await act(o, action) } }
            }
            .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
        } else {
            HStack {
                if m.mine { Spacer(minLength: 50) }
                VStack(alignment: .leading, spacing: 6) {
                    if let r = m.reply {
                        HStack(spacing: 8) {
                            Capsule().fill(T.accent).frame(width: 3)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.mine == true ? "Вы" : (data?.other?.name ?? "Собеседник")).font(.on(12, .semibold)).foregroundStyle(T.accent)
                                Text((r.body ?? "").isEmpty ? "Фото" : r.body!).font(.on(13)).foregroundStyle(T.text2).lineLimit(2)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if let p = m.photo, let u = API.shared.media(p) {
                        RemoteImage(url: u).frame(width: 220, height: 220).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if let b = m.body, !b.isEmpty {
                        Text(b).font(.on(16)).foregroundStyle(T.text).textSelection(.enabled)
                    }
                    HStack(spacing: 3) {
                        Spacer(minLength: 0)
                        Text(Fmt.time(m.createdAt)).font(.on(11)).foregroundStyle(T.faint)
                        if m.mine && kind != .support {
                            Image(systemName: m.id <= readUpTo ? "checkmark.circle.fill" : "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(m.id <= readUpTo ? T.accent : T.faint)
                                .accessibilityLabel(m.id <= readUpTo ? "Прочитано" : "Доставлено")
                        }
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(m.mine ? T.msgOut : T.surface))
                .contextMenu {
                    if kind != .support { Button { replyTo = m; focused = true } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
                    if let b = m.body, !b.isEmpty { Button { UIPasteboard.general.string = b } label: { Label("Копировать", systemImage: "doc.on.doc") } }
                }
                .modifier(SwipeToReply(enabled: kind != .support) { replyTo = m; focused = true })
                if !m.mine { Spacer(minLength: 50) }
            }
        }
    }

    // MARK: поле ввода
    private var composer: some View {
        VStack(spacing: 0) {
            if data?.block != nil {
                Label(data?.block == "me" ? "Вы заблокировали собеседника" : "Собеседник ограничил сообщения от вас", systemImage: "hand.raised.fill")
                    .font(.on(14, .medium)).foregroundStyle(T.danger)
                    .frame(maxWidth: .infinity).padding(14).background(T.surface)
            } else {
                if let r = replyTo {
                    HStack(spacing: 10) {
                        Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.mine ? "Ответ себе" : "Ответ \(data?.other?.name ?? "")").font(.on(12, .semibold)).foregroundStyle(T.accent)
                            Text((r.body ?? "").isEmpty ? "Фото" : r.body!).font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        }
                        Spacer()
                        Button { replyTo = nil } label: { Image(systemName: "xmark").foregroundStyle(T.muted) }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(T.card)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo").font(.system(size: 19, weight: .semibold)).foregroundStyle(T.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Отправить фото")
                    TextField("Сообщение", text: $text, axis: .vertical)
                        .font(.on(16))
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface))
                    Button { Task { await sendText() } } label: {
                        Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Circle().fill(T.grad))
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("Отправить")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(T.card)
            }
        }
        .overlay(alignment: .top) { Divider().overlay(T.line) }
    }

    private var canSend: Bool { !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: сеть
    private func poll() async {
        let after = messages.last?.id ?? 0
        do {
            switch kind {
            case .conv(let id):
                let r: ChatData = try await API.shared.get("/api/conversations/\(id)", query: ["after": String(after), "seen": "1"])
                data = r
                merge(r.messages)
                offers = r.offers ?? offers
                readUpTo = r.readUpTo ?? readUpTo
                typing = r.typing ?? false
            case .support:
                let r: SupportData = try await API.shared.get("/api/support", query: ["after": String(after)])
                merge(r.messages)
            }
            error = nil
        } catch {
            if messages.isEmpty { self.error = (error as? APIError)?.message }
        }
    }

    private func merge(_ new: [Message]) {
        guard !new.isEmpty else { return }
        var all = messages
        for m in new where !all.contains(where: { $0.id == m.id }) { all.append(m) }
        messages = all.sorted { $0.id < $1.id }
    }

    private func sendText() async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            try await send(body: body, photo: nil)
            text = ""
            replyTo = nil
            Haptics.play("light")
        } catch {
            app.show((error as? APIError)?.message ?? "Не отправилось", bad: true)
        }
    }

    private func send(body: String, photo: String?) async throws {
        var payload: [String: JSONValue] = ["body": .string(body)]
        if let photo { payload["photo"] = .string(photo) }
        if let r = replyTo { payload["replyTo"] = .number(Double(r.id)) }
        let path: String
        switch kind {
        case .conv(let id): path = "/api/conversations/\(id)/messages"
        case .support: path = "/api/support/messages"
        }
        let r: SentMessage = try await API.shared.post(path, payload)
        merge([r.message])
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        sending = true
        defer { sending = false }
        do {
            let file = try await Uploader.upload(img)
            try await send(body: "", photo: file)
        } catch {
            app.show((error as? APIError)?.message ?? "Фото не отправилось", bad: true)
        }
    }

    private func pingTyping(_ t: String) {
        guard let id = convId, !t.isEmpty, Date().timeIntervalSince(lastTypingPing) > 3 else { return }
        lastTypingPing = Date()
        Task { _ = try? await API.shared.post("/api/conversations/\(id)/typing") }
    }

    private func makeOffer(_ price: Int) async -> String? {
        guard let id = convId else { return nil }
        do {
            let r: OfferResult = try await API.shared.post("/api/conversations/\(id)/offer", ["price": price])
            offers = r.offers ?? offers
            await poll()
            Haptics.play("success")
            return nil
        } catch { return (error as? APIError)?.message ?? "Не получилось" }
    }

    @discardableResult
    private func act(_ o: Offer, _ action: String, price: Int? = nil) async -> String? {
        do {
            let body: [String: Int] = price.map { ["price": $0] } ?? [:]
            let r: OfferResult = try await API.shared.post("/api/offers/\(o.id)/\(action)", body)
            offers = r.offers ?? offers
            await poll()
            Haptics.play(action == "accept" ? "success" : "light")
            return nil
        } catch {
            let msg = (error as? APIError)?.message ?? "Не получилось"
            app.show(msg, bad: true)
            return msg
        }
    }

    private func toggleBlock() async {
        guard let o = data?.other else { return }
        do {
            if data?.block == "me" {
                _ = try await API.shared.send("DELETE", "/api/blocks/\(o.id)", body: Optional<[String: String]>.none) as JSONValue
                app.show("Разблокирован")
            } else {
                _ = try await API.shared.post("/api/blocks", ["userId": o.id], as: JSONValue.self)
                app.show("Заблокирован — больше не сможет вам писать")
            }
            await poll()
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// Свайп пузыря вправо — ответить на это сообщение.
struct SwipeToReply: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @State private var dx: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .overlay(alignment: .leading) {
                if dx > 10 {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(T.accent).opacity(Double(min(dx / 60, 1))).offset(x: -26)
                }
            }
            .simultaneousGesture(drag, including: enabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5, v.translation.width > 0 else { return }
                dx = min(v.translation.width, 80)
            }
            .onEnded { _ in
                if dx > 60 { Haptics.play("light"); action() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dx = 0 }
            }
    }
}

// Предложение цены в переписке: сумма, статус, кнопки для того, кому предложили.
struct OfferCard: View {
    let offer: Offer
    let mine: Bool
    let role: String
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(offer.bySeller == true ? "Встречная цена" : "Предложение цены", systemImage: "tag.fill")
                .font(.on(13, .semibold)).foregroundStyle(T.accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.price(offer.price)).font(.on(22, .heavy)).foregroundStyle(T.text)
                if let lp = offer.listingPrice { Text(Fmt.price(lp)).font(.on(14)).strikethrough().foregroundStyle(T.faint) }
            }
            Text(statusText).font(.on(13, .medium)).foregroundStyle(statusColor)
            if offer.status == "pending" {
                if mine {
                    Button("Отозвать") { onAction("withdraw") }.buttonStyle(TButton(kind: .line, height: 40))
                } else {
                    HStack(spacing: 8) {
                        Button("Принять") { onAction("accept") }.buttonStyle(TButton(kind: .accent, height: 40))
                        Button("Отклонить") { onAction("decline") }.buttonStyle(TButton(kind: .soft, height: 40))
                    }
                    if role == "seller" && offer.bySeller != true {
                        Button("Предложить свою цену") { onAction("counter") }.buttonStyle(TButton(kind: .line, height: 40))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 290, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(T.accentSoft2, lineWidth: 1.5))
    }

    private var statusText: String {
        switch offer.status {
        case "accepted": return "Принято"
        case "declined": return "Отклонено"
        case "withdrawn": return "Отозвано"
        case "countered": return "Ответили своей ценой"
        default: return mine ? "Ждём ответа" : "Ждёт вашего ответа"
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

// Три точки «печатает…».
struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(T.muted).frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: on)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
        .onAppear { on = true }
        .accessibilityLabel("Печатает")
    }
}

// Загрузка фото на сервер: уменьшаем до 1600 px, JPEG, base64 (как сайт: POST /api/uploads).
enum Uploader {
    static func upload(_ image: UIImage) async throws -> String {
        let small = image.resized(maxSide: 1600)
        guard let jpeg = small.jpegData(compressionQuality: 0.82) else { throw APIError(status: 0, message: "Не удалось прочитать фото") }
        let thumb = image.resized(maxSide: 480).jpegData(compressionQuality: 0.75)
        var body = ["data": "data:image/jpeg;base64," + jpeg.base64EncodedString()]
        if let thumb { body["thumb"] = "data:image/jpeg;base64," + thumb.base64EncodedString() }
        let r: UploadResult = try await API.shared.post("/api/uploads", body)
        return r.file
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let side = max(size.width, size.height)
        guard side > maxSide else { return self }
        let k = maxSide / side
        let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: target, format: fmt).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
