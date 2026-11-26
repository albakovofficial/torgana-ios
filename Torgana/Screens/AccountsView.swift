import SwiftUI

// Переключение аккаунтов (решение 26.11): шторка по нажатию на своё имя в профиле
// и меню по долгому нажатию на вкладку «Профиль». Данные и переключение — Accounts.
struct AccountSheet: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var accounts = Accounts.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Аккаунты").font(.on(20, .heavy)).foregroundStyle(T.text).padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(accounts.list) { a in row(a) }
                    Button { add() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(T.accent)
                                .frame(width: 46, height: 46)
                                .overlay(Circle().strokeBorder(T.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            Text("Добавить аккаунт").font(.on(16, .bold)).foregroundStyle(T.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 12).frame(minHeight: 64).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                Text("Переключение — без пароля, одним касанием").font(.on(12.5)).foregroundStyle(T.faint).padding(.top, 6)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(T.card)   // непрозрачная: профиль под шторкой не просвечивает
        .task { await accounts.refreshUnread() }
    }

    private func row(_ a: Accounts.Saved) -> some View {
        let current = a.id == app.me?.id
        return Button {
            if current { dismiss(); return }
            dismiss()
            Task { await accounts.switchTo(a) }
        } label: {
            HStack(spacing: 12) {
                Avatar(name: a.name, url: a.avatar, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(a.name).font(.on(16, .bold)).foregroundStyle(T.text).lineLimit(1)
                        if a.verified == true { Verified(size: 15) }
                    }
                    Text(a.expired == true ? "вход истёк — войти снова" : current ? "\(a.email ?? "") · сейчас" : a.email ?? "")
                        .font(.on(13)).foregroundStyle(a.expired == true ? T.danger : T.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                if current {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(T.accentFill))
                } else {
                    CountBadge(n: accounts.unread[a.id] ?? 0)
                }
            }
            .padding(.horizontal, 12).frame(minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(current ? T.surface : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !current {
                Button(role: .destructive) { accounts.forget(a.id) } label: { Label("Убрать из списка", systemImage: "minus.circle") }
            }
        }
    }

    private func add() {
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)   // шторка аккаунтов закрылась — теперь окно входа
            await accounts.startAdding()
        }
    }
}

/// Меню по долгому нажатию на вкладку «Профиль»: аккаунты и «Добавить аккаунт».
struct AccountMenu: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var accounts = Accounts.shared

    var body: some View {
        ForEach(accounts.list) { a in
            Button { Task { await accounts.switchTo(a) } } label: {
                let n = accounts.unread[a.id] ?? 0
                Label(a.name + (n > 0 ? " · \(n)" : ""), systemImage: a.id == app.me?.id ? "checkmark.circle.fill" : "person.crop.circle")
            }
        }
        Divider()
        Button { Task { await accounts.startAdding() } } label: { Label("Добавить аккаунт", systemImage: "plus") }
    }
}
