import SwiftUI
import PhotosUI

// Настройки — родные экраны (запросы те же, что у страницы настроек сайта: PATCH /api/me, /api/blocks, /api/me/erase…).
// «Пароль и вход» и «Для бизнеса» пока открываются разделами сайта (привязка Яндекса/VK, документы ИП).
enum SettingsSection: String, Hashable {
    case profile, notify, look, blocks, account

    /// Якорь раздела на странице настроек сайта.
    init?(hash: String) {
        switch hash {
        case "sf": self = .profile
        case "sn": self = .notify
        case "s-look": self = .look
        case "s-block": self = .blocks
        case "s-acc": self = .account
        default: return nil
        }
    }
}

struct SettingsScreen: View {
    let section: SettingsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink(title: "Профиль")
                PageTitle(text: title, size: 30).padding(.top, 4).padding(.bottom, 18)
                switch section {
                case .profile: ProfileEditForm()
                case .notify: NotifySettings()
                case .look: LookSettings()
                case .blocks: BlocksSettings()
                case .account: AccountSettings()
                }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .scrollDismissesKeyboard(.interactively)
        .sitePage()
    }

    private var title: String {
        switch section {
        case .profile: return "Профиль"
        case .notify: return "Уведомления"
        case .look: return "Оформление"
        case .blocks: return "Чёрный список"
        case .account: return "Аккаунт"
        }
    }
}

/// Сохранить поля профиля: PATCH /api/me, в ответ — обновлённый пользователь.
@MainActor
private func patchMe(_ body: [String: JSONValue]) async throws {
    let r: MeResponse = try await API.shared.send("PATCH", "/api/me", body: body)
    if let u = r.user { AppState.shared.me = u }
}

// MARK: - Профиль: фото, имя, город, телефон

private struct ProfileEditForm: View {
    @EnvironmentObject private var app: AppState
    @State private var name = ""
    @State private var city = ""
    @State private var phone = ""
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var saving = false
    @State private var cityPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Avatar(name: app.me?.name ?? "", url: app.me?.avatar, size: 84)
                    .overlay { if uploading { ProgressView().tint(.white).frame(width: 84, height: 84).background(Circle().fill(.black.opacity(0.35))) } }
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(app.me?.avatar == nil ? "Добавить фото" : "Сменить фото", systemImage: "camera")
                            .font(.on(15, .semibold)).foregroundStyle(T.accent)
                    }
                    if app.me?.avatar != nil {
                        Button("Убрать фото") { Task { await removePhoto() } }.font(.on(14, .medium)).foregroundStyle(T.danger).buttonStyle(.plain)
                    }
                }
            }
            field("Имя") { TextField("Как к вам обращаться", text: $name).textContentType(.name).modifier(InputBox()) }
            field("Город") {
                Button { cityPicker = true } label: {
                    HStack {
                        Text(city.isEmpty ? "Выберите город" : city).foregroundStyle(city.isEmpty ? T.faint : T.text)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.muted)
                    }
                    .modifier(InputBox())
                }
                .buttonStyle(.plain)
            }
            field("Телефон") {
                TextField("+7 900 000-00-00", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).modifier(InputBox())
            }
            Text("Телефон виден только вам и модераторам — покупателям его не показываем.").font(.on(13)).foregroundStyle(T.muted)
            Button { Task { await save() } } label: { if saving { ProgressView().tint(.white) } else { Text("Сохранить") } }
                .buttonStyle(TButton(kind: .accent, height: 52))
                .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { name = app.me?.name ?? ""; city = app.me?.city ?? ""; phone = app.me?.phone ?? "" }
        .onChange(of: photo) { _, item in if let item { Task { await upload(item) } } }
        .sheet(isPresented: $cityPicker) { CityPicker(city: $city) }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.on(14, .semibold)).foregroundStyle(T.text)
            c()
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await patchMe(["name": .string(name.trimmingCharacters(in: .whitespaces)), "city": .string(city), "phone": .string(phone)])
            Haptics.play("success")
            app.show("Сохранено")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось сохранить", bad: true) }
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photo = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
            let file = try await Uploader.upload(img)
            try await patchMe(["avatar": .string(file)])
            app.show("Фото обновлено")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось загрузить фото", bad: true) }
    }

    private func removePhoto() async {
        do { try await patchMe(["avatar": .string("")]); app.show("Фото убрано") }
        catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// MARK: - Уведомления: push на этом iPhone и что присылать

private struct NotifySettings: View {
    @EnvironmentObject private var app: AppState

    // Как NOTIFY_ROWS сайта: название, пояснение, поле push, поле письма.
    private static let rows: [(String, String, String?, String?)] = [
        ("Сообщения", "Чаты и ответы поддержки. Письмо — если не прочитали за 5 минут", "pushMessages", "notifyMessages"),
        ("Подписки", "Новые объявления продавцов, на которых вы подписаны", "pushSearches", nil),
        ("Снижение цены", "Подешевело то, что у вас в избранном", "pushPrices", nil),
        ("Подборка за день", "Новое у продавцов и снижение цен — одним письмом", nil, "notifyDigest"),
        ("Объявления и сделки", "Решения модерации, срок публикации, сделки и репутация", "pushModeration", "notifyModeration")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PushCard()
            SettingsGroup(title: "Что присылать") {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { i, r in
                    if r.2 != nil || (r.3 != nil && app.config?.mail == true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(r.0).font(.on(15.5, .semibold)).foregroundStyle(T.text)
                            Text(r.1).font(.on(13)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 16) {
                                if let k = r.2 { toggle("Push", k) }
                                if let k = r.3, app.config?.mail == true { toggle("Почта", k) }
                                Spacer()
                            }
                        }
                        .padding(14)
                        .overlay(alignment: .bottom) { if i < Self.rows.count - 1 { T.line.opacity(0.6).frame(height: 1) } }
                    }
                }
            }
        }
    }

    private func value(_ key: String) -> Bool {
        guard let me = app.me else { return false }
        switch key {
        case "pushMessages": return me.pushMessages ?? false
        case "pushSearches": return me.pushSearches ?? false
        case "pushPrices": return me.pushPrices ?? false
        case "pushModeration": return me.pushModeration ?? false
        case "notifyMessages": return me.notifyMessages ?? false
        case "notifyDigest": return me.notifyDigest ?? false
        case "notifyModeration": return me.notifyModeration ?? false
        default: return false
        }
    }

    private func toggle(_ label: String, _ key: String) -> some View {
        Toggle(isOn: Binding(get: { value(key) }, set: { on in
            Task {
                do { try await patchMe([key: .bool(on)]) } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
            }
        })) { Text(label).font(.on(14, .medium)).foregroundStyle(T.text2) }
        .toggleStyle(.switch)
        .tint(T.accentFill)
        .fixedSize()
    }
}

// MARK: - Оформление: как на устройстве, светлое, тёмное

struct LookSettings: View {
    @AppStorage("theme") private var theme = ""

    static var title: String {
        switch UserDefaults.standard.string(forKey: "theme") ?? "" {
        case "light": return "Светлое"
        case "dark": return "Тёмное"
        default: return "Как на устройстве"
        }
    }

    /// Тема на всё приложение — через окна (preferredColorScheme(nil) не возвращает «как на устройстве» без перезапуска).
    static func apply() {
        let style: UIUserInterfaceStyle = switch UserDefaults.standard.string(forKey: "theme") ?? "" {
        case "light": .light
        case "dark": .dark
        default: .unspecified
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in scene.windows { w.overrideUserInterfaceStyle = style }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Seg(items: [("", "Как на iPhone"), ("light", "Светлое"), ("dark", "Тёмное")], value: $theme)
                .onChange(of: theme) { _, _ in LookSettings.apply() }
            Text("«Как на iPhone» — тема меняется вместе с настройкой устройства.").font(.on(13)).foregroundStyle(T.muted)
        }
    }
}

// MARK: - Чёрный список

private struct BlocksSettings: View {
    @EnvironmentObject private var app: AppState
    @State private var items: [BlockedUser] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading && items.isEmpty {
                LoadingView()
            } else if items.isEmpty {
                EmptyState(title: "Список пуст", text: "Заблокировать можно в переписке или на странице продавца: он не сможет вам писать, а его объявления пропадут из выдачи.")
            } else {
                SettingsGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, u in
                        HStack(spacing: 12) {
                            Avatar(name: u.name ?? "?", url: u.avatar, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(u.name ?? "Удалённый профиль").font(.on(15.5, .medium)).foregroundStyle(T.text)
                                if let at = u.at { Text("с \(Fmt.day(at))").font(.on(12.5)).foregroundStyle(T.muted) }
                            }
                            Spacer()
                            Button("Разблокировать") { Task { await unblock(u) } }
                                .font(.on(14, .semibold)).foregroundStyle(T.accent).buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 60)
                        .overlay(alignment: .bottom) { if i < items.count - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 66) } }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let r: BlockList = try? await API.shared.get("/api/blocks") { items = r.items }
        loading = false
    }

    private func unblock(_ u: BlockedUser) async {
        do {
            _ = try await API.shared.send("DELETE", "/api/blocks/\(u.id)", body: Optional<[String: String]>.none) as JSONValue
            items.removeAll { $0.id == u.id }
            app.show("Разблокирован")
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}

// MARK: - Аккаунт: почта, удаление профиля (правило Apple 5.1.1(v) — удалить можно в самом приложении)

private struct AccountSettings: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var askOff = false
    @State private var askErase = false
    @State private var word = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Tint.violet))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.me?.email ?? "Почта не указана").font(.on(15.5, .medium)).foregroundStyle(T.text)
                        Text(app.me?.emailVerified == true ? "Подтверждена" : "Не подтверждена").font(.on(12.5)).foregroundStyle(app.me?.emailVerified == true ? T.good : T.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).frame(minHeight: 60)
            }
            SettingsGroup(title: "Удаление профиля") {
                SettingsRow(icon: "pause.fill", color: Tint.gray, title: "Удалить временно", sub: "Профиль и объявления скроются; вернуться — просто войти") { askOff = true }
                SettingsRow(icon: "trash.fill", color: Tint.red, title: "Удалить навсегда", sub: "Объявления, фото, избранное — без восстановления", last: true) { askErase = true }
            }
        }
        .confirmationDialog("Удалить профиль временно?", isPresented: $askOff, titleVisibility: .visible) {
            Button("Удалить временно", role: .destructive) { Task { await run("/api/me/deactivate", [:], "Профиль удалён временно. Чтобы вернуться — просто войдите") } }
        } message: { Text("Профиль и объявления скроются, вы выйдете на всех устройствах. Вернуться можно в любой момент: просто войдите.") }
        .alert("Удалить профиль навсегда?", isPresented: $askErase) {
            TextField("Напишите УДАЛИТЬ", text: $word)
            Button("Удалить навсегда", role: .destructive) {
                let w = word.trimmingCharacters(in: .whitespaces)
                word = ""
                guard w.uppercased() == "УДАЛИТЬ" else { app.show("Чтобы удалить, напишите слово УДАЛИТЬ", bad: true); return }
                Task { await run("/api/me/erase", ["confirm": w], "Профиль удалён") }
            }
            Button("Отмена", role: .cancel) { word = "" }
        } message: { Text("Объявления, фото, избранное, подписки и данные профиля удалятся. Восстановить их будет нельзя.") }
    }

    private func run(_ path: String, _ body: [String: String], _ done: String) async {
        do {
            _ = try await API.shared.post(path, body, as: JSONValue.self)
            await PushManager.shared.forget()
            await app.refreshMe()
            nav.open(path: "/")
            app.show(done)
        } catch { app.show((error as? APIError)?.message ?? "Не получилось", bad: true) }
    }
}
