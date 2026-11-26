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

    @EnvironmentObject private var nav: Nav
    @Environment(\.scenePhase) private var phase
    @StateObject private var chat: ChatModel
    // Состояние интерфейса: поле ввода, окна, выбор вложений.
    @State private var text = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var offerSheet = false
    @State private var counterFor: Offer?
    @State private var confirmBlock = false
    @FocusState private var focused: Bool
    @State private var asksUsed = false
    @State private var photoPicker = false
    @State private var videoPicker = false
    @State private var videoItem: PhotosPickerItem?
    @State private var fileImporter = false
    @State private var attachOpen = false          // плитки «Фото, Видео, Файл, Своя цена» над «+»

    init(kind: Kind) {
        self.kind = kind
        _chat = StateObject(wrappedValue: ChatModel(kind: kind))
    }

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            if let l = chat.data?.listing { listingStrip(l) }
            ScrollViewReader { proxy in
                // Переписка «перевёрнута» (как в мессенджерах): начало прокрутки — это низ, самое новое. Поэтому при открытии
                // и закрытии клавиатуры, при новых сообщениях последние всегда остаются над полем ввода — без доводки и прыжков.
                // Каждая строка перевёрнута обратно, порядок строк — от новых к старым.
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if chat.typing {
                            HStack { TypingDots(); Spacer() }.flipped().id("typing")
                        }
                        if let p = chat.pending {
                            PendingBubble(upload: p) { chat.cancelUpload() }.flipped().id("pending")
                        }
                        ForEach(Array(chat.messages.enumerated()).reversed(), id: \.element.id) { i, m in
                            VStack(spacing: 6) {
                                if i == 0 || !Calendar.current.isDate(date(m), inSameDayAs: date(chat.messages[i - 1])) {
                                    Text(Fmt.day(m.createdAt).capitalizedFirst).font(.on(12, .semibold)).foregroundStyle(T.muted).padding(.vertical, 8)
                                }
                                bubble(m)
                            }
                            .flipped().id(m.id)
                        }
                        if chat.messages.isEmpty && chat.error == nil {
                            Group { if chat.data == nil && chat.convId != nil { LoadingView() } else { hint } }.flipped()
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .flipped()
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { focused = false }) // касание по переписке — убрать клавиатуру
                .onChange(of: chat.messages.last?.id) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } } // .top перевёрнутого — низ экрана
                }
                .onChange(of: chat.pending == nil) { _, done in
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
        .onChange(of: videoItem) { _, item in if let item { chat.upload(video: item); videoItem = nil } }
        .onChange(of: photoItems) { _, items in if !items.isEmpty { chat.upload(photos: items); photoItems = [] } }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: Uploader.fileTypes) { result in
            if case .success(let url) = result { chat.upload(file: url) }
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "attach") { attachOpen = true } } // снимок экрана с плитками
        #endif
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await chat.poll()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        .onChange(of: text) { _, t in chat.pingTyping(t) }
        .sheet(isPresented: $offerSheet) {
            PriceSheet(title: "Предложить цену", hint: chat.data?.listing?.price.map { "Сейчас — \(Fmt.price($0))" } ?? "") { price in await chat.makeOffer(price) }
        }
        .sheet(item: $counterFor) { o in
            PriceSheet(title: "Своя цена", hint: "Покупатель предложил \(Fmt.price(o.price))") { price in await chat.act(o, "counter", price: price) }
        }
        .sheet(isPresented: $confirmBlock) {
            if let o = chat.data?.other { BlockSheet(name: o.name, avatar: o.avatar, blocked: chat.data?.block == "me") { await chat.toggleBlock() } }
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
            BackButton()
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
                Button { if let o = chat.data?.other { nav.push(.user(o.id)) } } label: {
                    HStack(spacing: 10) {
                        if let o = chat.data?.other { Avatar(name: o.name, url: o.avatar, size: 40) } else { Circle().fill(T.surface).frame(width: 40, height: 40) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chat.data?.other?.name ?? "Переписка").font(.on(17, .bold)).foregroundStyle(T.text).lineLimit(1)
                            Text(chat.typing ? "печатает…" : (chat.data?.conversation?.role == "seller" ? "покупатель" : "продавец"))
                                .font(.on(13, chat.typing ? .semibold : .regular)).foregroundStyle(chat.typing ? T.accent : T.muted)
                                .animation(.easeOut(duration: 0.15), value: chat.typing)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let o = chat.data?.other, let id = chat.convId {
                    Menu {
                        Button { nav.push(.user(o.id)) } label: { Label("Профиль собеседника", systemImage: "person") }
                        if let l = chat.data?.listing { Button { nav.push(.listing(l.id)) } label: { Label("Объявление", systemImage: "doc.text") } }
                        Button { nav.push(.web("/messages/\(id)")) } label: { Label("Сделка и отзыв", systemImage: "hand.thumbsup") }
                        Button(role: chat.data?.block == "me" ? nil : .destructive) { confirmBlock = true } label: {
                            Label(chat.data?.block == "me" ? "Разблокировать" : "Заблокировать", systemImage: "hand.raised")
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
        let agreed = chat.offers.last { $0.status == "accepted" }
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
            if chat.canOffer {
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
        if m.kind == "offer", let oid = m.offerId, let o = chat.offers.first(where: { $0.id == oid }) {
            OfferCard(offer: o, mine: m.mine, role: chat.data?.conversation?.role ?? "") { action in
                if action == "counter" { counterFor = o } else { Task { await chat.act(o, action) } }
            }
            .frame(maxWidth: .infinity, alignment: m.mine ? .trailing : .leading)
        } else {
            HStack {
                if m.mine { Spacer(minLength: 56) }
                bubbleBody(m)
                .contentShape(bubbleShape(m.mine))
                // Своё превью меню: переписка перевёрнута, а снимок пузыря по умолчанию вышел бы вверх ногами.
                .contextMenu {
                    if kind != .support { Button { chat.editing = nil; chat.replyTo = m; focused = true } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") } }
                    if chat.canEdit(m) { Button { startEdit(m) } label: { Label("Изменить", systemImage: "pencil") } }
                    if let b = m.body, !b.isEmpty { Button { UIPasteboard.general.string = b } label: { Label("Копировать", systemImage: "doc.on.doc") } }
                } preview: {
                    bubbleBody(m).frame(maxWidth: 320)
                }
                .modifier(SwipeToReply(enabled: kind != .support) { chat.replyTo = m; focused = true })
                if !m.mine { Spacer(minLength: 56) }
            }
        }
    }

    private func bubbleBody(_ m: Message) -> some View {
        BubbleStack {
            if let r = m.reply {
                HStack(spacing: 8) {
                    Capsule().fill(m.mine ? Color.white.opacity(0.85) : T.accent).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.mine == true ? "Вы" : (chat.data?.other?.name ?? "Собеседник")).font(.on(12, .semibold)).foregroundStyle(m.mine ? .white : T.accent)
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
                Text((m.editedAt != nil ? "изменено · " : "") + Fmt.time(m.createdAt)).font(.on(11)).foregroundStyle(m.mine ? Color.white.opacity(0.75) : T.faint)
                if m.mine && kind != .support { Ticks(read: m.id <= chat.readUpTo, tint: Color.white.opacity(m.id <= chat.readUpTo ? 0.95 : 0.7)) }
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
        guard let l = chat.data?.listing, chat.data?.conversation?.role == "buyer", l.status == "active", !asksUsed, text.isEmpty else { return [] }
        return ["Здравствуйте! Ещё актуально?", "Где и когда можно посмотреть?"]
            + (l.price != nil && l.bargain == true ? ["Торг возможен?"] : [])
            + (l.delivery == true ? ["Отправите по России?"] : [])
            + ["Пришлёте ещё фото?"]
    }

    // MARK: поле ввода (.chat-form): ₽ 44 (предложить цену), фото 48, поле со скруглением 24, отправка 48
    private var composer: some View {
        VStack(spacing: 0) {
            if chat.data?.block != nil {
                Label(chat.data?.block == "me" ? "Вы заблокировали собеседника" : "Собеседник ограничил сообщения от вас", systemImage: "hand.raised.fill")
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
                if let e = chat.editing {
                    HStack(spacing: 10) {
                        Image(systemName: "pencil").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Изменение сообщения").font(.on(12, .semibold)).foregroundStyle(T.accent)
                            Text(e.body ?? "").font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        }
                        Spacer()
                        Button { chat.editing = nil; text = "" } label: { Image(systemName: "xmark").foregroundStyle(T.muted) }.buttonStyle(.plain)
                            .accessibilityLabel("Отменить изменение")
                    }
                    .padding(.horizontal, 16).padding(.top, 10)
                } else if let r = chat.replyTo {
                    HStack(spacing: 10) {
                        Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(T.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.mine ? "Ответ себе" : "Ответ \(chat.data?.other?.name ?? "")").font(.on(12, .semibold)).foregroundStyle(T.accent)
                            Text(!(r.body ?? "").isEmpty ? r.body! : r.video != nil ? "Видео" : r.file.map { "📎 " + $0.name } ?? "Фото").font(.on(13)).foregroundStyle(T.text2).lineLimit(1)
                        }
                        Spacer()
                        Button { chat.replyTo = nil } label: { Image(systemName: "xmark").foregroundStyle(T.muted) }.buttonStyle(.plain)
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
                    .disabled(chat.pending != nil || chat.editing != nil)
                    .opacity(chat.pending != nil || chat.editing != nil ? 0.4 : 1)
                    .accessibilityLabel(attachOpen ? "Закрыть" : "Фото, видео, файл")
                    TextField("Сообщение", text: $text, axis: .vertical)
                        .font(.on(16))
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.surface))
                    Button { Task { if await chat.sendText(text) { text = "" } } } label: {
                        Image(systemName: chat.editing != nil ? "checkmark" : "arrow.up").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(T.grad))
                            .opacity(canSend ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel(chat.editing != nil ? "Сохранить" : "Отправить")
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
            if chat.canOffer { attachTile("tag.fill", [0xF6C453, 0xE08A1E], "Своя цена", "продавец ответит в чате") { offerSheet = true } }
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

    private var canSend: Bool { !chat.sending && chat.pending == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func startEdit(_ m: Message) {
        chat.replyTo = nil
        chat.editing = m
        text = m.body ?? ""
        focused = true
    }
}

extension String {
    /// «вчера» → «Вчера» (разделитель дней в переписке).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Пузырь по ширине содержимого (а не на всю ширину): строки — слева, последняя строка (время) — справа.
private struct BubbleStack: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        let width = sizes.map(\.width).max() ?? 0
        let height = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let x = i == subviews.count - 1 ? bounds.maxX - size.width : bounds.minX
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            y += size.height + spacing
        }
    }
}
