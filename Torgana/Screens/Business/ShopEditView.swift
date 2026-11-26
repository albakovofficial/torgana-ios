import SwiftUI
import PhotosUI

// Витрина: обложка, описание, адрес, часы, сайт, доставка; закреплённые
struct ShopEditView: View {
    let h: BizHub
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var about = ""
    @State private var address = ""
    @State private var hours = ""
    @State private var site = ""
    @State private var delivery = ""
    /// nil — обложку не трогали, "" — убрать, имя файла — новая.
    @State private var newCover: String?
    @State private var coverImage: UIImage?
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var filled = false

    private var coverURL: URL? { newCover == "" ? nil : API.shared.media(h.shop.cover) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            cover
            LabeledField(label: "О магазине", hint: "Видят покупатели на вашей странице, под именем.") {
                TextField("Что продаёте, гарантия, доставка, самовывоз", text: $about, axis: .vertical).lineLimit(4...12).modifier(InputBox(multiline: true))
            }
            LabeledField(label: "Адрес") { TextField("Город, улица, дом", text: $address).modifier(InputBox()) }
            HStack(alignment: .top, spacing: 10) {
                LabeledField(label: "Часы работы") { TextField("10:00–21:00", text: $hours).modifier(InputBox()) }
                LabeledField(label: "Сайт") { TextField("shop.ru", text: $site).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().modifier(InputBox()) }
            }
            LabeledField(label: "Доставка") { TextField("СДЭК, Почта, курьер по городу", text: $delivery).modifier(InputBox()) }
            if let pinned = h.pinned, !pinned.isEmpty {
                SettingsGroup(title: "Закреплённые — первыми на витрине") {
                    ForEach(Array(pinned.enumerated()), id: \.element.id) { i, p in
                        HStack {
                            Image(systemName: "pin.fill").foregroundStyle(T.accent)
                            Text(p.title).font(.on(15, .medium)).foregroundStyle(T.text).lineLimit(1)
                            Spacer()
                            Button("Открепить") { Task { await unpin(p.id) } }.font(.on(14, .semibold)).foregroundStyle(T.danger).buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).frame(height: 50)
                        .overlay(alignment: .bottom) { if i < pinned.count - 1 { T.line.frame(height: 1).padding(.leading, 14) } }
                    }
                }
            }
            Button { Task { await save() } } label: { if saving { ProgressView().tint(.white) } else { Text("Сохранить") } }
                .buttonStyle(TButton(kind: .accent, height: 52)).disabled(saving || uploading)
            Button { if let id = app.me?.id { nav.push(.user(id)) } } label: { Label("Как видят покупатели", systemImage: "eye") }
                .buttonStyle(TButton(kind: .soft, height: 48))
        }
        .onAppear {
            guard !filled else { return }
            filled = true
            about = h.shop.about ?? ""; address = h.shop.address ?? ""; hours = h.shop.hours ?? ""; site = h.shop.site ?? ""; delivery = h.shop.delivery ?? ""
        }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
    }

    private var cover: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Широкая обложка не должна раздвигать страницу: размер задаёт пустая рамка, картинка — поверх неё.
        return Color.clear.frame(maxWidth: .infinity).frame(height: 150)
        .overlay {
            if let coverImage { Image(uiImage: coverImage).resizable().scaledToFill() }
            else if let coverURL { RemoteImage(url: coverURL) }
            else { T.gradSoft.overlay(Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(T.accent.opacity(0.6))) }
        }
        .clipShape(shape)
        .overlay { if uploading { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.3)).clipShape(shape) } }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                if coverURL != nil || coverImage != nil {
                    Button { newCover = ""; coverImage = nil } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.danger).frame(width: 34, height: 34).background(Circle().fill(T.card))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Убрать обложку")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Обложка", systemImage: "camera").font(.on(13, .semibold)).foregroundStyle(T.text)
                        .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(T.card))
                }
            }
            .padding(10)
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
            newCover = try await Uploader.upload(img)
            coverImage = img
        } catch { app.fail(error, "Не получилось загрузить фото") }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: [String: JSONValue] = ["about": .string(about), "address": .string(address), "hours": .string(hours), "site": .string(site), "delivery": .string(delivery)]
        if let newCover { body["cover"] = .string(newCover) }
        do {
            let _: JSONValue = try await API.shared.send("PUT", "/api/my/shop", body: body)
            newCover = nil; coverImage = nil
            await BizStore.shared.load()
            await app.refreshMe()
            Haptics.play("success")
            app.show("Витрина сохранена")
        } catch { app.fail(error, "Не получилось сохранить") }
    }

    private func unpin(_ id: Int) async {
        do {
            let _: JSONValue = try await API.shared.send("PUT", "/api/my/shop/pins", body: ["id": JSONValue.number(Double(id)), "pin": .bool(false)])
            await BizStore.shared.load()
            app.show("Откреплено")
        } catch { app.fail(error) }
    }
}
