import SwiftUI

// Жалоба на объявление — те же причины, что у сайта.
struct ReportSheet: View {
    let listingId: Int
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var text = ""
    @State private var sending = false

    static let reasons = ["Запрещённый товар или услуга", "Мошенничество", "Неверная цена или описание", "Товар уже продан",
                          "Чужие фото или подделка", "Оскорбления или спам", "Нарушены мои права (правообладатель)"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Что не так?") {
                    ForEach(ReportSheet.reasons, id: \.self) { r in
                        Button { reason = r } label: {
                            HStack {
                                Text(r).foregroundStyle(T.text)
                                Spacer()
                                if reason == r { Image(systemName: "checkmark").foregroundStyle(T.accent) }
                            }
                        }
                    }
                }
                Section("Подробности") {
                    TextField("Например: просит предоплату на карту", text: $text, axis: .vertical).lineLimit(3...6)
                }
            }
            .font(.on(16))
            .navigationTitle("Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }.disabled(reason.isEmpty || sending).fontWeight(.semibold)
                }
            }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            _ = try await API.shared.post("/api/listings/\(listingId)/report", ["reason": reason, "text": text], as: JSONValue.self)
            app.show("Спасибо! Модератор проверит объявление")
            Haptics.play("success")
            dismiss()
        } catch {
            app.fail(error)
        }
    }
}
