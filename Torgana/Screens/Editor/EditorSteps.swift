import SwiftUI
import PhotosUI

// Три шага подачи объявления. Данные — в EditorModel, здесь только вид.

// MARK: - Шаг 1: фото
// Сетка — крупная обложка 2×2, справа и ниже маленькие ячейки; пустые ячейки тоже открывают галерею.
struct EditorPhotosStep: View {
    @ObservedObject var m: EditorModel
    @Binding var picked: [PhotosPickerItem]
    @Binding var gridW: CGFloat

    private typealias Photo = EditorModel.EditorPhoto
    private enum Slot { case photo(Photo), add, empty }

    var body: some View {
        let cell = max(0, (gridW - 16) / 3)
        var rest: [Slot] = m.photos.dropFirst().map { .photo($0) }
        if !m.photos.isEmpty && m.photos.count < 10 { rest.append(.add) }
        while rest.count < 5 { rest.append(.empty) }
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    if let first = m.photos.first { thumb(first, cell * 2 + 8) } else { picker { Self.bigAdd(cell * 2 + 8) } }
                    VStack(spacing: 8) { slot(rest[0], cell); slot(rest[1], cell) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 8), count: 3), alignment: .leading, spacing: 8) {
                    ForEach(Array(rest.dropFirst(2).enumerated()), id: \.offset) { _, sl in slot(sl, cell) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridW = $0 }
            Text(m.photos.isEmpty ? "до 10 фото · первое — обложка" : "\(m.photos.count) из 10 · обложку можно сменить долгим нажатием")
                .font(.on(13)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            if m.aiBusy { Label("Заполняем по фото…", systemImage: "sparkles").font(.on(14, .semibold)).foregroundStyle(T.accent) }
        }
    }

    // Подпись кнопки галереи PhotosPicker собирается вне главного потока (@Sendable) — только из готовых значений.
    private func picker<L: View>(@ViewBuilder _ label: @escaping @Sendable () -> L) -> some View {
        PhotosPicker(selection: $picked, maxSelectionCount: max(1, 10 - m.photos.count), matching: .images, label: label)
    }

    private nonisolated static func bigAdd(_ size: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera").font(.system(size: 30, weight: .medium))
            Text("Добавить фото").font(.on(16, .bold))
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(T.accentFill))
    }

    @ViewBuilder private func slot(_ sl: Slot, _ size: CGFloat) -> some View {
        switch sl {
        case .photo(let p): thumb(p, size)
        case .add:
            picker {
                Image(systemName: "camera").font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.accentFill))
            }
        case .empty:
            if m.photos.count < 10 {
                picker {
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(T.faint)
                        .frame(width: size, height: size)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line2, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
            } else { Color.clear.frame(width: size, height: size) }
        }
    }

    private func thumb(_ p: Photo, _ size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size > 150 ? 22 : 16, style: .continuous)
        let cover = m.photos.first?.id == p.id
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = p.image { Image(uiImage: img).resizable().scaledToFill() } else { RemoteImage(url: p.url) }
            }
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if p.file == nil && !p.failed { ProgressView().tint(.white).frame(width: size, height: size).background(.black.opacity(0.3)).clipShape(shape) }
                if p.failed { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white).frame(width: size, height: size).background(T.danger.opacity(0.6)).clipShape(shape) }
            }
            .overlay(alignment: .bottomLeading) {
                if cover { Text("Обложка").font(.on(11, .bold)).foregroundStyle(.white).padding(.horizontal, 8).frame(height: 22).background(Capsule().fill(.black.opacity(0.55))).padding(8) }
            }
            .contentShape(.contextMenuPreview, shape)
            .contextMenu {
                if !cover { Button { m.makeCover(p) } label: { Label("Сделать обложкой", systemImage: "star") } }
                Button(role: .destructive) { m.remove(p) } label: { Label("Удалить", systemImage: "trash") }
            }
            Button { m.remove(p) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .padding(5)
            .accessibilityLabel("Удалить фото")
        }
    }
}

// MARK: - Шаг 2: категория (выбрали — сворачивается в строку), название, характеристики, цена, описание, состояние и город
struct EditorWhatStep: View {
    @ObservedObject var m: EditorModel
    @Binding var listField: FieldDef?
    @Binding var cityPicker: Bool
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.pickingCat || m.category.isEmpty || (!m.subs.isEmpty && m.sub.isEmpty) { categoryPicker.padding(.bottom, 6) } else { categoryField }
            if !m.autoTitle {
                EditorBox("Название") { TextField("Например: iPhone 15 Pro, 256 ГБ", text: $m.title).font(.on(16, .semibold)) }
            }
            ForEach(m.fields, id: \.key) { f in fieldRow(f) }
            EditorBox("Цена") {
                HStack {
                    TextField("0", text: $m.price).keyboardType(.numberPad).font(.on(24, .heavy))
                    Text("₽").font(.on(24, .heavy)).foregroundStyle(T.muted)
                }
            }
            .id("price")
            let units = app.config?.priceUnits ?? []
            if units.count > 1 { Seg(items: units.map { ($0, $0.isEmpty ? "за всё" : "за \($0)") }, value: $m.priceUnit) }
            EditorBox("Описание") {
                TextField("Состояние, комплектация, особенности", text: $m.text, axis: .vertical).lineLimit(3...14).font(.on(15))
            }
            .id("text")
            FlowLayout(spacing: 8) {
                if !m.category.isEmpty {
                    Chip(title: "Новое", on: m.condition == "new") { m.condition = m.condition == "new" ? "" : "new" }
                    Chip(title: "Б/у", on: m.condition == "used") { m.condition = m.condition == "used" ? "" : "used" }
                }
                Chip(title: m.city.isEmpty ? "Город" : m.city, icon: "mappin", on: !m.city.isEmpty) { cityPicker = true }
            }
            .padding(.top, 4)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Категория").font(.on(13, .semibold)).foregroundStyle(T.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(app.config?.categories ?? []) { c in
                    let on = m.category == c.id
                    Button { m.pick(category: c.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: CatIcon.of(c.id)).font(.system(size: 17)).foregroundStyle(on ? T.accent : T.text2).frame(width: 24)
                            Text(c.name).font(.on(14, .semibold)).foregroundStyle(T.text).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? T.accentSoft : T.card))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? T.accent : T.line, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !m.subs.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(m.subs) { sc in
                        Chip(title: sc.name, on: m.sub == sc.id) { m.pick(sub: sc.id) }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var categoryField: some View {
        Button { m.pickingCat = true } label: {
            EditorBox("Категория") {
                HStack(spacing: 8) {
                    Image(systemName: CatIcon.of(m.category)).font(.system(size: 15)).foregroundStyle(T.accent)
                    Text([app.config?.category(m.category)?.name, m.subs.first { $0.id == m.sub }?.name].compactMap { $0 }.joined(separator: " · "))
                        .font(.on(16, .semibold)).foregroundStyle(T.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Изменить").font(.on(14, .semibold)).foregroundStyle(T.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func fieldRow(_ f: FieldDef) -> some View {
        let binding = m.attrBinding(f)
        if m.listOptions(f) != nil {
            Button { listField = f } label: {
                EditorBox(f.label) { choice(binding.wrappedValue, icon: "chevron.right") }
            }
            .buttonStyle(.plain)
        } else {
            switch f.type {
            case "select":
                Menu {
                    Picker(f.label, selection: binding) {
                        Text("Не указывать").tag("")
                        ForEach(f.options ?? [], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    EditorBox(f.label) { choice(binding.wrappedValue, icon: "chevron.up.chevron.down") }
                }
            case "number":
                EditorBox(f.label) {
                    HStack {
                        TextField(f.placeholder ?? "", text: binding).keyboardType(f.step != nil ? .decimalPad : .numberPad).font(.on(16, .semibold))
                        if let u = f.unit { Text(u).foregroundStyle(T.muted) }
                    }
                }
            default:
                EditorBox(f.label) { TextField(f.placeholder ?? "", text: binding).font(.on(16, .semibold)) }
            }
        }
    }

    /// Выбранное значение (или серое «Выберите») и значок справа.
    private func choice(_ value: String, icon: String) -> some View {
        HStack {
            Text(value.isEmpty ? "Выберите" : value).font(.on(16, .semibold)).foregroundStyle(value.isEmpty ? T.faint : T.text)
            Spacer()
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.muted)
        }
    }
}

/// Поле шага 2: белая плашка, подпись мелко сверху, ввод под ней.
private struct EditorBox<C: View>: View {
    let label: String
    let content: C
    init(_ label: String, @ViewBuilder _ content: () -> C) { self.label = label; self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.on(12, .medium)).foregroundStyle(T.muted)
            content
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(T.line, lineWidth: 1))
    }
}

// MARK: - Шаг 3: страница объявления как у покупателя (ListingView в режиме превью), условия, отправка
struct EditorSendStep: View {
    @ObservedObject var m: EditorModel
    @EnvironmentObject private var nav: Nav

    var body: some View {
        VStack(spacing: 16) {
            Text("так увидят покупатели").font(.on(13)).foregroundStyle(T.muted)
            ListingView(id: m.editId ?? 0, draft: .init(data: m.draftData, images: m.photos.map(\.image), edit: { m.edit($0) }))
            VStack(spacing: 0) {
                toggleRow("Торг", "tag", $m.bargain)
                toggleRow("Обмен", "arrow.left.arrow.right", $m.exchange)
                toggleRow("Доставка", "truck.box", $m.delivery, last: true)
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(T.line, lineWidth: 1))
            Button { nav.push(.web("/page/rules")) } label: {
                (Text("Проверка модератором — обычно пара часов. Публикуя, вы принимаете ") + Text("правила").foregroundColor(T.accent))
                    .font(.on(12.5)).foregroundStyle(T.muted).multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
        }
    }

    private func toggleRow(_ t: String, _ icon: String, _ on: Binding<Bool>, last: Bool = false) -> some View {
        Toggle(isOn: on) {
            Label(t, systemImage: icon).font(.on(15, .medium)).foregroundStyle(T.text)
        }
        .tint(T.accentFill)
        .padding(.horizontal, 14).frame(height: 50)
        .overlay(alignment: .bottom) { if !last { T.line.frame(height: 1).padding(.leading, 14) } }
    }
}
