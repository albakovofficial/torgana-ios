import SwiftUI
import PhotosUI
import AVKit
import QuickLook
import UniformTypeIdentifiers

// Переписка (вариант 1, «мессенджер», выбран владельцем 13 ноября): на весь экран — шапка с собеседником и «печатает…»,
// под ней полоса с товаром; свои сообщения — фирменный градиент, чужие — серые; предложение цены — компактная карточка;
// внизу «+» — плитки над полем (фото до 10 сразу, видео, файл, своя цена; вариант B), поле и отправка.
// Пока вложение загружается — оно уже в ленте: превью, кольцо загрузки, крестик «отменить». Новые сообщения — раз в 2,5 секунды, пока чат на экране (как сайт).
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var offerSheet = false
    @State private var counterFor: Offer?
    @State private var lastTypingPing = Date.distantPast
    @State private var confirmBlock = false
    @FocusState private var focused: Bool

    private var convId: Int? { if case .conv(let id) = kind { return id } else { return nil } }

    @Environment(\.dismiss) private var dismiss
    @State private var asksUsed = false
    @State private var photoPicker = false
    @State private var videoPicker = false
    @State private var videoItem: PhotosPickerItem?
    @State private var fileImporter = false
    @State private var attachOpen = false          // плитки «Фото, Видео, Файл, Своя цена» над «+»
    @State private var pending: PendingUpload?     // вложение, которое сейчас загружается (в ленте)
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadID = UUID()
    @State private var editing: Message?           // правка своего сообщения
    @State private var editsSince: Double = 0      // время сервера прошлого опроса — правки после него

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            if let l = data?.listing { listingStrip(l) }
            ScrollViewReader { proxy in
                // Переписка «перевёрнута» (как в мессенджерах): начало прокрутки — это низ, самое новое. Поэтому при открытии
                // и закрытии клавиатуры, при новых сообщениях последние всегда остаются над полем ввода — без доводки и прыжков.
                // Каждая строка перевёрнута обратно, порядок строк — от новых к старым.
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if typing {
                            HStack { TypingDots(); Spacer() }.flipped().id("typing")
                        }
                        if let p = pending {
                            PendingBubble(upload: p) { uploadTask?.cancel(); pending = nil }.flipped().id("pending")
                        }
                        ForEach(Array(messages.enumerated()).reversed(), id: \.element.id) { i, m in
                            VStack(spacing: 6) {
                                if i == 0 || !Calendar.current.isDate(date(m), inSameDayAs: date(messages[i - 1])) {
                                    Text(Fmt.day(m.createdAt).capitalizedFirst).font(.on(12, .semibold)).foregroundStyle(T.muted).padding(.vertical, 8)
                                }
                                bubble(m)
                            }
                            .flipped().id(m.id)
                        }
                        if messages.isEmpty && error == nil {
                            Group { if data == nil && convId != nil { LoadingView() } else { hint } }.flipped()
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .flipped()
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { focused = false }) // касание по переписке — убрать клавиатуру
                .onChange(of: messages.last?.id) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } } // .top перевёрнутого — низ экрана
                }
                .onChange(of: pending == nil) { _, done in
                    if !done { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("pending", anchor: .top) } }
                }
                .onChange(of: focused) { _, f in if f { attachOpen = false } }
            }
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    if attachOpen {
                        Color.black.opacity(0.12).contentShape(Rectangle())
                            .onTapGesture { withAnimation(.spring(duration: 0.25)) { attachOpen = false } }
                            .transition(.opacity)
                    }
                    if attachOpen {
                        attachMenu.padding(10)
                            .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
            }
            composer
        }
        .background(T.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .photosPicker(isPresented: $photoPicker, selection: $photoItems, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images)
        .photosPicker(isPresented: $videoPicker, selection: $videoItem, matching: .videos)
        .onChange(of: videoItem) { _, item in if let item { startUpload { await sendVideo(item) } } }
        .onChange(of: photoItems) { _, items in if !items.isEmpty { startUpload { await sendPhotos(items) } } }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: Uploader.fileTypes) { result in
            if case .success(let url) = result { startUpload { await sendFile(url) } }
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "attach") { attachOpen = true } } // снимок экрана с плитками
        #endif
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        .onChange(of: text) { _, t in pingTyping(t) }
        .sheet(isPresented: $offerSheet) {
            PriceSheet(title: "Предложить цену", hint: data?.listing?.price.map { "Сейчас — \(Fmt.price($0))" } ?? "") { price in await makeOffer(price) }
        }
        .sheet(item: $counterFor) { o in
            PriceSheet(title: "Своя цена", hint: "Покупатель предложил \(Fmt.price(o.price))") { price in await act(o, "counter", price: price) }
        }
        .sheet(isPresented: $confirmBlock) {
            if let o = data?.other { BlockSheet(name: o.name, avatar: o.avatar, blocked: data?.block == "me") { await toggleBlock() } }
        }
    }

    private var hint: some View {
        Text(kind == .support ? "Напишите, что случилось, — модератор ответит здесь же. Можно приложить снимок экрана." : "Начните переписку — продавец получит уведомление.")
            .font(.on(14)).foregroundStyle(T.muted).multilineTextAlignment(.center).padding(30)
    }

    private func date(_ m: Message) -> Date { Date(timeIntervalSince1970: (m.createdAt ?? 0) / 1000) }

    // MARK: шапка: назад, аватар собеседника 40, имя 17/700, под ним «печатает…» (синим) или кто это; «ещё»
    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(T.accent)
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(.plain).accessibilityLabel("Назад")
            if kind == .support {
                Image("SupportAvatar").resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Поддержка Торганы").font(.on(17, .bold)).foregroundStyle(T.text)
                        Verified(size: 17)
                    }
                    Text("Отвечают люди, а не боты").font(.on(13)).foregroundStyle(T.muted)
                }
                Spacer(minLength: 0)
            } else {
                Button { if let o = data?.other { nav.push(.user(o.id)) } } label: {
                    HStack(spacing: 10) {
                        if let o = data?.other { Avatar(name: o.name, url: o.avatar, size: 40) } else { Circle().fill(T.surface).frame(width: 40, height: 40) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(data?.other?.name ?? "Переписка").font(.on(17, .bold)).foregroundStyle(T.text).lineLimit(1)
                            Text(typing ? "печатает…" : (data?.conversation?.role == "seller" ? "покупатель" : "продавец"))
                                .font(.on(13, typing ? .semibold : .regular)).foregroundStyle(typing ? T.accent : T.muted)
                                .animation(.easeOut(duration: 0.15), value: typing)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let o = data?.other, let id = convId {
                    Menu {
                        Button { nav.push(.user(o.id)) } label: { Label("Профиль собеседника", systemImage: "person") }
                        if let l = data?.listing { Button { nav.push(.listing(l.id)) } label: { Label("Объявление", systemImage: "doc.text") } }
                        Button { nav.push(.web("/messages/\(id)")) } label: { Label("Сделка и отзыв", systemImage: "hand.thumbsup") }
                        Button(role: data?.block == "me" ? nil : .destructive) { confirmBlock = true } label: {
                            Label(data?.block == "me" ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(T.text).frame(width: 40, height: 40)
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
    }

    /// Полоса с товаром под шапкой: фото 42, название, цена (или «договорились», «продано»), справа — «Своя цена» или «Объявление».
    private func listingStrip(_ l: ChatListing) -> some View {
        let agreed = offers.last { $0.status == "accepted" }
        let sub: String = {
            switch l.status {
            case "sold": return "Продано"
            case "deleted": return "Объявление удалено"
            case "archived": return "Снято с публикации"
            default: return agreed.map { "\(Fmt.price($0.price)) · договорились" } ?? Fmt.price(l.price, unit: l.priceUnit)
            }
        }()
        return HStack(spacing: 10) {
            Button { if l.status != "deleted" { nav.push(.listing(l.id)) } } label: {
                HStack(spacing: 10) {
                    RemoteImage(url: API.shared.media(l.photo)).frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.title).font(.on(15, .bold)).foregroundStyle(T.text).lineLimit(1)
                        Text(sub).font(.on(14)).foregroundStyle(T.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if canOffer {
                stripButton("Своя цена") { offerSheet = true }
            } else if l.status != "deleted" {
                stripButton("Объявление") { nav.push(.listing(l.id)) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func stripButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.on(14, .semibold)).foregroundStyle(T.accent)
                .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: пузырь: свои — фирменный градиент, белый текст, угол 6 внизу справа; чужие — серые, угол 6 внизу слева; 16/400
    @ViewBuilder private func bubble(_ m: Message) -> some View {
        if m.kind == "offer", let oid = m.offerId, let o = offers.first(where: { $0.id == oid }) {
            OfferCard(offer: o, mine: m.mine, role: data?.conversation?.role ?? "") { action in
                if action == "counter" { counterFor = o } else { Task { await act(o, action) } }
            }
            .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
        } else {
            HStack {
                if m.mine { Spacer(minLength: 56) }
                bubbleBody(m)
                .contentShape(bubbleShape(m.mine))
                // Своё превью меню: переписка перевёрнута, а снимок пузыря по умолчанию вышел бы вверх ногами.
                .contextMenu {
                    if kind != .support { Button { editing = nil; replyTo = m; focused = true } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
                    if canEdit(m) { Button { startEdit(m) } label: { Label("Изменить", systemImage: "pencil") } }
                    if let b = m.body, !b.isEmpty { Button { UIPasteboard.general.string = b } label: { Label("Копировать", systemImage: "doc.on.doc") } }
                } preview: {
                    bubbleBody(m).frame(maxWidth: 320)
                }
                .modifier(SwipeToReply(enabled: kind != .support) { replyTo = m; focused = true })
                if !m.mine { Spacer(minLength: 56) }
            }
        }
    }

    private func bubbleBody(_ m: Message) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let r = m.reply {
                HStack(spacing: 8) {
                    Capsule().fill(m.mine ? Color.white.opacity(0.85) : T.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine == true ? "Вы" : (data?.other?.name ?? "Собеседник")).font(.on(12, .semibold)).foregroundStyle(m.mine ? .white : T.accent)
                        Text(!(r.body ?? "").isEmpty ? r.body! : r.video == true ? "Видео" : r.file == true ? "Файл" : "Фото").font(.on(13)).foregroundStyle(m.mine ? Color.white.opacity(0.85) : T.text2).lineLimit(2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let p = m.photo, let u = API.shared.media(p) {
                RemoteImage(url: u).frame(width: 220, height: 220).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let v = m.video, let u = API.shared.media(v) { VideoBubble(url: u) }
            if let f = m.file { FileBubble(file: f, mine: m.mine) }
            if let b = m.body, !b.isEmpty {
                Text(b).font(.on(16)).foregroundStyle(m.mine ? .white : T.text).lineSpacing(2).textSelection(.enabled)
            }
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Text((m.editedAt != nil ? "изменено · " : "") + Fmt.time(m.createdAt)).font(.on(11)).foregroundStyle(m.mine ? Color.white.opacity(0.75) : T.faint)
                if m.mine && kind != .support { Ticks(read: m.id <= readUpTo, tint: Color.white.opacity(m.id <= readUpTo ? 0.95 : 0.7)) }
            }
        }
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 7)
        .background(bubbleShape(m.mine).fill(m.mine ? AnyShapeStyle(T.grad) : AnyShapeStyle(T.surface)))
    }

    private func bubbleShape(_ mine: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 6, bottomTrailingRadius: mine ? 6 : 20, topTrailingRadius: 20, style: .continuous)
    }

    /// Быстрые вопросы покупателя — под это объявление (как buyerAsks сайта): торг — если разрешён, доставка — если отправляет.
    private var asks: [String] {
        guard let l = data?.listing, data?.conversation?.role == "buyer", l.status == "active", !asksUsed, text.isEmpty else { return [] }
        return ["Здравствуйте! Ещё актуально?", "Где и когда можно посмотреть?"]
            + (l.price != nil && l.bargain == true ? ["Торг возможен?"] : [])
            + (l.delivery == true ? ["Отправите по России?"] : [])
            + ["Пришлёте ещё фото?"]
    }

    private var canOffer: Bool {
        data?.conversation?.role == "buyer" && data?.listing?.status == "active" && (data?.listing?.bargain ?? true) && data?.listing?.price != nil
    }

    // MARK: поле ввода (.chat-form): ₽ 44 (предложить цену), фото 48, поле со скруглением 24, отправка 48
    private var composer: some View {
        VStack(spacing: 0) {
            if data?.block != nil {
                Label(data?.block == "me" ? "Вы заблокировали собеседника" : "Собеседник ограничил сообщения от вас", systemImage: "hand.raised.fill")
                    .font(.on(14, .medium)).foregroundStyle(T.danger)
                    .frame(maxWidth: .infinity).padding(14).background(T.surface)
            } else {
                if !asks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(asks, id: \.self) { t in
                                Button { text = t; asksUsed = true; focused = true } label: {
                                    Text(t).font(.on(13, .semibold)).foregroundStyle(T.accent)
                                        .padding(.horizontal, 12).frame(height: 34)
                                        .background(Capsule().fill(T.accentSoft))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.top, 10)
                    .overlay(alignment: .top) { T.line.frame(height: 1) }
                }
                if let e = editing {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Изменение сообщения").font(.on(12, .semibold)).foregroundStyle(T.accent)
                            Text(e.body ?? "").font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        }
                        Spacer()
                        Button { editing = nil; text = "" } label: { Image(systemName: "xmark").foregroundStyle(T.muted) }.buttonStyle(.plain)
                            .accessibilityLabel("Отменить изменение")
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                } else if let r = replyTo {
                    HStack(spacing: 10) {
                        Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.mine ? "Ответ себе" : "Ответ \(data?.other?.name ?? "")").font(.on(12, .semibold)).foregroundStyle(T.accent)
                            Text(!(r.body ?? "").isEmpty ? r.body! : r.video != nil ? "Видео" : r.file.map { "📎 " + $0.name } ?? "Фото").font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        }
                        Spacer()
                        Button { replyTo = nil } label: { Image(systemName: "xmark").foregroundStyle(T.muted) }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        focused = false
                        withAnimation(.spring(duration: 0.25)) { attachOpen.toggle() }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 22, weight: attachOpen ? .semibold : .regular))
                            .foregroundStyle(attachOpen ? T.accent : T.muted)
                            .rotationEffect(.degrees(attachOpen ? 45 : 0))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(pending != nil || editing != nil)
                    .opacity(pending != nil || editing != nil ? 0.4 : 1)
                    .accessibilityLabel(attachOpen ? "Закрыть" : "Фото, видео, файл")
                    TextField("Сообщение", text: $text, axis: .vertical)
                        .font(.on(16))
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface))
                    Button { Task { await sendText() } } label: {
                        Image(systemName: editing != nil ? "checkmark" : "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(T.grad))
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel(editing != nil ? "Сохранить" : "Отправить")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .background(T.bg)
    }

    // MARK: плитки над «+» (вариант B): значок с градиентом, название, подсказка
    private var attachMenu: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            attachTile("photo.on.rectangle.angled", [0x4C86E0, 0x3D67D0], "Фото", "до 10 сразу") { photoPicker = true }
            attachTile("video.fill", [0x7B7FF0, 0x5B3DF5], "Видео", "до минуты, покажите товар в деле") { videoPicker = true }
            attachTile("doc.fill", [0x5BA7E6, 0x2D78C4], "Файл", "PDF, Word, Excel, ZIP до 10 МБ") { fileImporter = true }
            if canOffer { attachTile("tag.fill", [0xF6C453, 0xE08A1E], "Своя цена", "продавец ответит в чате") { offerSheet = true } }
        }
        .padding(10)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(T.line))
        .shadow(color: Color(hex: 0x141E50).opacity(0.22), radius: 25, y: 16)
    }

    private func attachTile(_ icon: String, _ colors: [UInt32], _ title: String, _ hint: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.2)) { attachOpen = false }
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)))
                Text(title).font(.on(15, .bold)).foregroundStyle(T.text)
                Text(hint).font(.on(12)).foregroundStyle(T.muted).lineSpacing(1).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.surface))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var canSend: Bool { !sending && pending == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Своё сообщение с текстом, не предложение цены, не старше 48 часов (как на сервере).
    private func canEdit(_ m: Message) -> Bool {
        guard m.mine, convId != nil, (m.kind ?? "").isEmpty, let b = m.body, !b.isEmpty, let t = m.createdAt else { return false }
        return Date().timeIntervalSince1970 * 1000 - t < 48 * 3600 * 1000
    }

    private func startEdit(_ m: Message) {
        replyTo = nil
        editing = m
        text = m.body ?? ""
        focused = true
    }

    // MARK: сеть
    private func poll() async {
        let after = messages.last?.id ?? 0
        do {
            switch kind {
            case .conv(let id):
                let r: ChatData = try await API.shared.get("/api/conversations/\(id)", query: ["after": String(after), "seen": "1", "edits": String(Int(editsSince))])
                data = r
                merge(r.messages)
                for e in r.edited ?? [] { apply(e.id, body: e.body, editedAt: e.editedAt) }
                if let n = r.now { editsSince = n }
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

    private func apply(_ id: Int, body: String, editedAt: Double?) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].body = body
        messages[i].editedAt = editedAt ?? Date().timeIntervalSince1970 * 1000
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
            if let e = editing, let id = convId {
                let r: SentMessage = try await API.shared.send("PATCH", "/api/conversations/\(id)/messages/\(e.id)", body: ["body": body])
                apply(e.id, body: r.message.body ?? body, editedAt: r.message.editedAt)
                editing = nil
            } else {
                try await send(["body": .string(body)])
                replyTo = nil
            }
            text = ""
            Haptics.play("light")
        } catch {
            app.show((error as? APIError)?.message ?? "Не отправилось", bad: true)
        }
    }

    /// Отправка: текст и/или вложение (photo, video, file — имя загруженного файла).
    private func send(_ fields: [String: JSONValue]) async throws {
        var payload = fields
        if let r = replyTo { payload["replyTo"] = .number(Double(r.id)) }
        let path: String
        switch kind {
        case .conv(let id): path = "/api/conversations/\(id)/messages"
        case .support: path = "/api/support/messages"
        }
        let r: SentMessage = try await API.shared.post(path, payload)
        merge([r.message])
    }

    /// Одна загрузка за раз; крестик на превью в ленте отменяет её (Task.cancel → запрос прерывается).
    private func startUpload(_ op: @escaping () async -> Void) {
        uploadTask?.cancel()
        let id = UUID()
        uploadID = id
        uploadTask = Task { await op(); if uploadID == id { pending = nil; uploadTask = nil } }
    }

    private func failed(_ error: Error, _ fallback: String) {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        app.show((error as? APIError)?.message ?? fallback, bad: true)
    }

    /// Фото — до 10 сразу, по очереди, в том порядке, в каком выбраны.
    private func sendPhotos(_ items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for (i, item) in items.enumerated() {
            guard !Task.isCancelled else { return }
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { continue }
            pending = PendingUpload(kind: .photo, preview: img.resized(maxSide: 480), note: items.count > 1 ? "Фото \(i + 1) из \(items.count)" : "Загружается")
            do {
                let file = try await Uploader.upload(img)
                try Task.checkCancellation()
                try await send(["body": .string(""), "photo": .string(file)])
                replyTo = nil
            } catch {
                failed(error, "Фото не отправилось"); return
            }
        }
        Haptics.play("light")
    }

    private func sendVideo(_ item: PhotosPickerItem) async {
        defer { videoItem = nil }
        pending = PendingUpload(kind: .video, note: "Готовим видео…")
        guard let movie = try? await item.loadTransferable(type: Movie.self) else {
            if !Task.isCancelled { app.show("Не удалось открыть видео", bad: true) }
            return
        }
        defer { try? FileManager.default.removeItem(at: movie.url) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: movie.url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 600, height: 600)
        let poster = (try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image).map { UIImage(cgImage: $0) }
        pending = PendingUpload(kind: .video, preview: poster, progress: 0, note: "Загружается · 0%")
        do {
            let file = try await Uploader.video(movie.url) { p in
                Task { @MainActor in
                    guard pending?.kind == .video else { return }
                    pending?.progress = p
                    pending?.note = "Загружается · \(Int(p * 100))%"
                }
            }
            try Task.checkCancellation()
            pending?.note = "Отправляем…"
            try await send(["body": .string(""), "video": .string(file)])
            replyTo = nil
            Haptics.play("light")
        } catch {
            failed(error, "Видео не отправилось")
        }
    }

    private func sendFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if scoped { url.stopAccessingSecurityScopedResource() }
        pending = PendingUpload(kind: .file, name: url.lastPathComponent, size: size, note: "Загружается")
        do {
            let f = try await Uploader.file(url)
            try Task.checkCancellation()
            try await send(["body": .string(""), "file": .string(f.file)])
            replyTo = nil
            Haptics.play("light")
        } catch {
            failed(error, "Файл не отправился")
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
extension View {
    /// Перевернуть по вертикали — для «перевёрнутой» переписки (низ — начало прокрутки).
    func flipped() -> some View { scaleEffect(x: 1, y: -1, anchor: .center) }
}

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
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20, style: .continuous).fill(T.surface))
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

    /// Видео (до минуты и 100 МБ, MP4 или MOV) — как видео объявления: начать загрузку, потом частями по offset.
    static func video(_ url: URL, progress: @escaping (Double) -> Void = { _ in }) async throws -> String {
        let data = try Data(contentsOf: url)
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        let name = url.lastPathComponent.lowercased().hasSuffix(".mp4") ? "video.mp4" : "video.mov"
        let start: VideoStart = try await API.shared.post("/api/videos", VideoStartBody(name: name, type: name.hasSuffix("mp4") ? "video/mp4" : "video/quicktime", size: data.count, duration: seconds))
        var offset = 0
        while offset < data.count {
            try Task.checkCancellation()
            let end = min(offset + start.chunk, data.count)
            let r: VideoPart = try await API.shared.upload("PUT", "/api/videos/\(start.file)", query: ["offset": String(offset)], data: data.subdata(in: offset..<end))
            if r.ready == true { break }
            offset = r.received ?? end
            progress(Double(offset) / Double(max(data.count, 1)))
        }
        return start.file
    }
    private struct VideoStartBody: Encodable { let name: String; let type: String; let size: Int; let duration: Double }

    /// Документ до 10 МБ одним запросом; сервер проверит формат по началу файла.
    static func file(_ url: URL) async throws -> UploadResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024 else { throw APIError(status: 413, message: "Файл больше 10 МБ — отправьте его частями или в архиве") }
        return try await API.shared.upload("POST", "/api/files", query: ["name": url.lastPathComponent], data: data)
    }

    /// Какие файлы можно выбрать (то же, что принимает сервер).
    static let fileTypes: [UTType] = [.pdf, .plainText, .commaSeparatedText, .rtf, .zip]
        + ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp"].compactMap { UTType(filenameExtension: $0) }
}

/// Видео из «Фото»: система отдаёт копию файла, мы переносим её во временную папку.
struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Movie(url: copy)
        }
    }
}

// MARK: - Видео и файл в пузыре
/// Видео: кадр из начала и кнопка «смотреть»; нажатие — на весь экран.
struct VideoBubble: View {
    let url: URL
    @State private var poster: UIImage?
    @State private var seconds: Double?
    @State private var playing = false

    var body: some View {
        ZStack {
            if let poster { Image(uiImage: poster).resizable().scaledToFill() } else { Color.black.opacity(0.85) }
            Image(systemName: "play.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 52, height: 52).background(Circle().fill(.black.opacity(0.45)))
        }
        .frame(width: 220, height: 260)
        .overlay(alignment: .bottomLeading) {
            if let seconds { MediaPill(icon: "video.fill", text: Fmt.duration(seconds)).padding(10) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { playing = true }
        .task(id: url) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 600, height: 600)
            if let cg = try? await gen.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image { poster = UIImage(cgImage: cg) }
            if let d = try? await gen.asset.load(.duration).seconds, d.isFinite, d > 0 { seconds = d }
        }
        .fullScreenCover(isPresented: $playing) { VideoScreen(url: url) }
        .accessibilityLabel("Видео")
    }
}

struct VideoScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .onAppear { let p = AVPlayer(url: url); player = p; p.play() }
        .onDisappear { player?.pause() }
    }
}

/// Документ: значок по типу, название, размер; нажатие — скачать и открыть просмотр (Quick Look).
struct FileBubble: View {
    let file: ChatFile
    let mine: Bool
    @State private var local: URL?
    @State private var loading = false

    var body: some View {
        Button { Task { await open() } } label: {
            HStack(spacing: 10) {
                DocIcon(name: file.name)
                    .overlay { if loading { ProgressView().tint(.white) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.on(15, .bold)).foregroundStyle(mine ? .white : T.text).lineLimit(2).multilineTextAlignment(.leading)
                    Text(Fmt.bytes(file.size) + (mine ? "" : " · Нажмите, чтобы открыть")).font(.on(12)).foregroundStyle(mine ? Color.white.opacity(0.8) : T.muted)
                }
            }
            .frame(maxWidth: 250, alignment: .leading)
        }
        .buttonStyle(.plain)
        .quickLookPreview($local)
        .accessibilityLabel("Файл \(file.name)")
    }

    private func open() async {
        guard let url = API.shared.media(file.url) else { return }
        loading = true
        defer { loading = false }
        guard let (tmp, _) = try? await URLSession.shared.download(from: url) else { return }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil else { return }
        local = dest
    }
}

/// Значок документа: цветной лист с загнутым углом и типом (PDF — красный, Word — синий, Excel — зелёный, PowerPoint — оранжевый, ZIP — фиолетовый).
struct DocIcon: View {
    let name: String
    private var ext: String { (name as NSString).pathExtension.lowercased() }
    private var colors: [UInt32] {
        switch ext {
        case "pdf": return [0xF06A5D, 0xD23F33]
        case "xls", "xlsx", "ods", "csv": return [0x4CC38A, 0x1E9A62]
        case "ppt", "pptx", "odp": return [0xF6A453, 0xE0721E]
        case "zip": return [0x9A8CF2, 0x6A55DE]
        default: return [0x5C8DF0, 0x2F5FD0]
        }
    }
    private var label: String {
        let l = ["docx": "DOC", "xlsx": "XLS", "pptx": "PPT"][ext] ?? String(ext.uppercased().prefix(4))
        return l.isEmpty ? "FILE" : l
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .topTrailing) {
                UnevenRoundedRectangle(bottomLeadingRadius: 6, style: .continuous).fill(.white.opacity(0.35)).frame(width: 14, height: 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottom) {
                Text(label).font(.system(size: 10, weight: .heavy)).kerning(0.3).foregroundStyle(.white).padding(.bottom, 7)
            }
            .frame(width: 44, height: 52)
            .accessibilityHidden(true)
    }
}

/// Плашка на превью: «▶ 0:24», «Загружается · 60%».
struct MediaPill: View {
    var icon: String?
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.on(11, .bold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(.black.opacity(0.5)))
    }
}

// MARK: - Загрузка вложения: уже в ленте, с кольцом и крестиком «отменить»
struct PendingUpload {
    enum Kind { case photo, video, file }
    let kind: Kind
    var preview: UIImage?
    var name = ""
    var size = 0
    var progress: Double?          // nil — сколько осталось, неизвестно (кольцо крутится)
    var note = ""
}

struct PendingBubble: View {
    let upload: PendingUpload
    let cancel: () -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 56)
            Group {
                if upload.kind == .file {
                    HStack(spacing: 11) {
                        DocIcon(name: upload.name)
                            .overlay { Color.black.opacity(0.25).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) }
                            .overlay { UploadRing(progress: upload.progress, size: 34, action: cancel) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(upload.name).font(.on(15, .bold)).foregroundStyle(.white).lineLimit(2)
                            Text((upload.size > 0 ? Fmt.bytes(upload.size) + " · " : "") + upload.note).font(.on(12)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: 250, alignment: .leading)
                    .padding(10)
                } else {
                    ZStack {
                        if let p = upload.preview { Image(uiImage: p).resizable().scaledToFill() } else { Color.black.opacity(0.6) }
                        Color.black.opacity(0.35)
                        UploadRing(progress: upload.progress, size: 58, action: cancel)
                    }
                    .frame(width: 220, height: upload.kind == .video ? 260 : 220)
                    .overlay(alignment: .bottomLeading) { MediaPill(icon: upload.kind == .video ? "video.fill" : nil, text: upload.note).padding(10) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(6)
                }
            }
            .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous).fill(T.grad))
        }
        .transition(.opacity)
    }
}

/// Кольцо загрузки с крестиком посередине; нажатие — отменить.
struct UploadRing: View {
    let progress: Double?
    let size: CGFloat
    let action: () -> Void
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white.opacity(0.35), lineWidth: size > 40 ? 4 : 3)
                Circle().trim(from: 0, to: max(0.04, min(progress ?? 0.28, 1)))
                    .stroke(.white, style: StrokeStyle(lineWidth: size > 40 ? 4 : 3, lineCap: .round))
                    .rotationEffect(.degrees(progress == nil && spin ? 270 : -90))
                    .animation(progress == nil ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .easeOut(duration: 0.2), value: spin)
                    .animation(.easeOut(duration: 0.2), value: progress)
                Image(systemName: "xmark").font(.system(size: size * 0.28, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear { spin = true }
        .accessibilityLabel("Отменить загрузку")
    }
}

extension Fmt {
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
    /// «вчера» → «Вчера» (разделитель дней в переписке).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
