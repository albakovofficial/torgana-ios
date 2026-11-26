import SwiftUI
import PhotosUI
import AVKit
import QuickLook
import UniformTypeIdentifiers

// Вложения в переписке: загрузка фото, видео и файлов, пузыри с видео и документом, загрузка с кольцом и отменой.
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

    /// Скачать во временную папку под исходным названием (только последняя часть — без путей) и открыть.
    private func open() async {
        loading = true
        defer { loading = false }
        do {
            let data = try await API.shared.data(file.url)
            let name = (file.name as NSString).lastPathComponent
            let safe = name.isEmpty || name.hasPrefix(".") ? "файл.\((file.url as NSString).pathExtension)" : name
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
            try data.write(to: dest, options: .atomic)
            local = dest
        } catch {
            AppState.shared.fail(error)
        }
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
