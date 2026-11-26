import SwiftUI
import PhotosUI
import AVKit

/// Переписка и сервер: опрос раз в 2,5 секунды, отправка текста и вложений (одна загрузка за раз, с отменой),
/// правка своего сообщения, торг, блокировка. Экран (ChatView) только показывает это состояние и передаёт действия.
@MainActor
final class ChatModel: ObservableObject {
    let kind: ChatView.Kind
    @Published private(set) var data: ChatData?
    @Published private(set) var messages: [Message] = []
    @Published private(set) var offers: [Offer] = []
    @Published private(set) var readUpTo = 0
    @Published private(set) var typing = false
    @Published private(set) var error: String?
    @Published private(set) var sending = false
    @Published var replyTo: Message?
    @Published var editing: Message?                  // правка своего сообщения
    @Published private(set) var pending: PendingUpload? // вложение, которое сейчас загружается (в ленте)

    private var uploadTask: Task<Void, Never>?
    private var uploadID = UUID()
    private var editsSince: Double = 0                 // время сервера прошлого опроса — правки после него
    private var lastTypingPing = Date.distantPast

    init(kind: ChatView.Kind) { self.kind = kind }

    var convId: Int? { if case .conv(let id) = kind { return id } else { return nil } }

    // MARK: опрос

    func poll() async {
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
            if messages.isEmpty { self.error = error.userMessage() }
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

    // MARK: текст

    /// Отправить текст или сохранить правку. true — получилось, поле ввода можно очистить.
    func sendText(_ text: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
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
            Haptics.play("light")
            return true
        } catch {
            AppState.shared.fail(error, "Не отправилось")
            return false
        }
    }

    /// Своё сообщение с текстом, не предложение цены, не старше 48 часов (как на сервере).
    func canEdit(_ m: Message) -> Bool {
        guard m.mine, convId != nil, (m.kind ?? "").isEmpty, let b = m.body, !b.isEmpty, let t = m.createdAt else { return false }
        return Date().timeIntervalSince1970 * 1000 - t < 48 * 3600 * 1000
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

    func pingTyping(_ t: String) {
        guard let id = convId, !t.isEmpty, Date().timeIntervalSince(lastTypingPing) > 3 else { return }
        lastTypingPing = Date()
        Task { _ = try? await API.shared.post("/api/conversations/\(id)/typing") }
    }

    // MARK: вложения

    /// Одна загрузка за раз; крестик на превью в ленте отменяет её (Task.cancel → запрос прерывается).
    private func startUpload(_ op: @escaping () async -> Void) {
        uploadTask?.cancel()
        let id = UUID()
        uploadID = id
        uploadTask = Task { await op(); if uploadID == id { pending = nil; uploadTask = nil } }
    }

    func cancelUpload() {
        uploadTask?.cancel()
        pending = nil
    }

    /// Фото — до 10 сразу, по очереди, в том порядке, в каком выбраны.
    func upload(photos items: [PhotosPickerItem]) {
        startUpload { [self] in
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
                    AppState.shared.fail(error, "Фото не отправилось"); return
                }
            }
            Haptics.play("light")
        }
    }

    func upload(video item: PhotosPickerItem) {
        startUpload { [self] in
            pending = PendingUpload(kind: .video, note: "Готовим видео…")
            guard let movie = try? await item.loadTransferable(type: Movie.self) else {
                if !Task.isCancelled { AppState.shared.show("Не удалось открыть видео", bad: true) }
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
                        guard self.pending?.kind == .video else { return }
                        self.pending?.progress = p
                        self.pending?.note = "Загружается · \(Int(p * 100))%"
                    }
                }
                try Task.checkCancellation()
                pending?.note = "Отправляем…"
                try await send(["body": .string(""), "video": .string(file)])
                replyTo = nil
                Haptics.play("light")
            } catch {
                AppState.shared.fail(error, "Видео не отправилось")
            }
        }
    }

    func upload(file url: URL) {
        startUpload { [self] in
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
                AppState.shared.fail(error, "Файл не отправился")
            }
        }
    }

    // MARK: торг и блокировка

    var canOffer: Bool {
        data?.conversation?.role == "buyer" && data?.listing?.status == "active" && (data?.listing?.bargain ?? true) && data?.listing?.price != nil
    }

    func makeOffer(_ price: Int) async -> String? {
        guard let id = convId else { return nil }
        do {
            let r: OfferResult = try await API.shared.post("/api/conversations/\(id)/offer", ["price": price])
            offers = r.offers ?? offers
            await poll()
            Haptics.play("success")
            return nil
        } catch { return error.userMessage() }
    }

    @discardableResult
    func act(_ o: Offer, _ action: String, price: Int? = nil) async -> String? {
        do {
            let body: [String: Int] = price.map { ["price": $0] } ?? [:]
            let r: OfferResult = try await API.shared.post("/api/offers/\(o.id)/\(action)", body)
            offers = r.offers ?? offers
            await poll()
            Haptics.play(action == "accept" ? "success" : "light")
            return nil
        } catch {
            let msg = error.userMessage()
            AppState.shared.show(msg, bad: true)
            return msg
        }
    }

    func toggleBlock() async {
        guard let o = data?.other else { return }
        do {
            if data?.block == "me" {
                _ = try await API.shared.send("DELETE", "/api/blocks/\(o.id)", body: Optional<[String: String]>.none) as JSONValue
                AppState.shared.show("Разблокирован")
            } else {
                _ = try await API.shared.post("/api/blocks", ["userId": o.id], as: JSONValue.self)
                AppState.shared.show("Заблокирован — больше не сможет вам писать")
            }
            await poll()
        } catch { AppState.shared.fail(error) }
    }
}
