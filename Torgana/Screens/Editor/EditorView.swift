import SwiftUI
import PhotosUI

// Подать или изменить объявление в три шага: фото (до 10, первое — обложка); категория, название, характеристики,
// цена, описание, состояние, город; превью страницы объявления с торгом, обменом и доставкой.
// Если подключён ИИ — заполняем по первому фото. Публикуется после проверки модератором (как на сайте).
// Данные и действия — EditorModel, шаги — EditorPhotosStep, EditorWhatStep, EditorSendStep.
struct EditorView: View {
    let editId: Int?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @Environment(\.dismiss) private var dismiss
    @StateObject private var m: EditorModel
    @State private var picked: [PhotosPickerItem] = []
    @State private var gridW: CGFloat = 0
    @State private var cityPicker = false
    /// Длинный список (марка) или модель из списка марки — выбор с поиском.
    @State private var listField: FieldDef?

    init(editId: Int? = nil) {
        self.editId = editId
        _m = StateObject(wrappedValue: EditorModel(editId: editId))
    }

    var body: some View {
        Group {
            if let id = m.done {
                success(id)
            } else if editId != nil && !m.loaded {
                editLoading
            } else {
                wizard
            }
        }
        .sitePage()
        .task { await m.prefill() }
        .onAppear { syncDock() }
        .onChange(of: m.done) { _, _ in syncDock() }
        .onChange(of: app.me?.id) { _, _ in syncDock() }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await m.add(items) }
        }
        #if DEBUG
        .onAppear { m.demoStep() }
        .onChange(of: app.config?.categories.count ?? 0) { _, _ in m.demoStep() }
        #endif
        .sheet(item: $listField) { f in
            OptionPicker(title: f.label, options: m.listOptions(f) ?? [], value: m.attrBinding(f))
        }
        .sheet(isPresented: $cityPicker) { OptionPicker(title: "Город", options: app.config?.cities ?? [], value: $m.city) }
    }

    /// Изменение: пока объявление не пришло — загрузка; не пришло — понятная ошибка, а не пустая форма.
    private var editLoading: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: m.stepTitle) { dismiss() }
            if let loadError = m.loadError {
                LoadFailed(title: "Не открылось", error: loadError, retry: m.prefill).padding(.top, 8)
            } else { LoadingView() }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    /// Пока заполняют форму, вместо нижнего меню — панель «Далее» / «Опубликовать».
    private func syncDock() { if editId == nil { nav.editorDock = app.me != nil && m.done == nil } }

    // MARK: шаги (решение 26.11): стрелка и заголовок шага, тонкие полоски, без пояснений; шаг 3 — превью страницы объявления.
    private var wizard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: m.stepTitle) {
                        if m.step > 0 { m.go(m.step - 1) } else if editId != nil { dismiss() } else { nav.open(path: "/profile/listings") }
                    }
                    .id("top")
                    stepsBar.padding(.top, 12)
                    if let stepError = m.stepError {
                        Label(stepError, systemImage: "exclamationmark.circle").font(.on(14, .semibold)).foregroundStyle(T.danger)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.dangerSoft))
                            .padding(.top, 14)
                    }
                    Group {
                        switch m.step {
                        case 0: EditorPhotosStep(m: m, picked: $picked, gridW: $gridW)
                        case 1: EditorWhatStep(m: m, listField: $listField, cityPicker: $cityPicker)
                        default: EditorSendStep(m: m)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                Color.clear.frame(height: 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: m.step) { _, _ in
                let to = m.jump ?? "top"
                m.jump = nil
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(60)); withAnimation { proxy.scrollTo(to, anchor: .top) } }
            }
        }
        .overlay(alignment: .bottom) { dock }
    }

    private var stepsBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<EditorModel.stepCount, id: \.self) { i in
                Capsule().fill(i <= m.step ? T.accent : Color.dyn(0xE6E9F5, 0x272D3E)).frame(height: 4)
                    .padding(.vertical, 8).contentShape(Rectangle())
                    .onTapGesture { m.go(i) }
            }
        }
    }

    // Нижняя панель: «Далее» (тёмная) / «Опубликовать» (синяя). Назад — стрелкой в шапке.
    private var dock: some View {
        Group {
            if m.step < EditorModel.stepCount - 1 {
                Button("Далее") { m.go(m.step + 1) }.buttonStyle(TButton(kind: .dark, height: 50))
            } else {
                Button { Task { await m.submit() } } label: {
                    if m.busy { ProgressView().tint(.white) } else { Text(editId == nil ? "Опубликовать" : "Сохранить") }
                }
                .buttonStyle(TButton(kind: .accent, height: 50))
                .disabled(m.busy || m.uploading)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(T.card.opacity(0.96)).shadow(color: Color(hex: 0x101010).opacity(0.14), radius: 18, y: 12))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(T.line, lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private func success(_ id: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                .frame(width: 84, height: 84).background(Circle().fill(T.grad))
            Text(editId == nil ? "Отправили на проверку" : "Изменения отправлены").font(.on(26, .heavy)).foregroundStyle(T.text)
            Text("Модератор проверит объявление и опубликует его. Мы пришлём уведомление.")
                .font(.on(16)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            Button("Мои объявления") { reset(); nav.open(path: "/profile/listings") }.buttonStyle(TButton(kind: .dark))
            if editId == nil { Button("Подать ещё") { reset() }.buttonStyle(TButton(kind: .soft)) }
        }
        .padding(28)
        .frame(maxHeight: .infinity)
    }

    private func reset() {
        m.reset()
        if editId != nil { dismiss() }
    }
}
