import SwiftUI

// Переключение аккаунтов (решение 26.11; вид — вариант A от 27.11): шторка по нажатию на своё имя в профиле
// и по долгому нажатию на вкладку «Профиль». Крупные аватарки и почта; текущий — с кольцом и «Сейчас»,
// у остальных — число новых сообщений. Данные и переключение — Accounts.
struct AccountSheet: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var accounts = Accounts.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Аккаунты").font(.on(24, .heavy)).foregroundStyle(T.text).padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(accounts.list) { a in row(a) }
                    Button { add() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(T.accent)
                                .frame(width: 54, height: 54)
                                .overlay(Circle().strokeBorder(T.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                            Text("Добавить аккаунт").font(.on(16.5, .bold)).foregroundStyle(T.accent)
                            Spacer()
                        }
                        .padding(12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                Text("Переключение — без пароля, одним касанием").font(.on(12.5)).foregroundStyle(T.faint).padding(.top, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(T.card)   // непрозрачная: профиль под шторкой не просвечивает
        .task { await accounts.refreshUnread() }
    }

    private func row(_ a: Accounts.Saved) -> some View {
        let current = a.id == app.me?.id
        let unread = accounts.unread[a.id] ?? 0
        return Button {
            dismiss()
            if !current { Task { await accounts.switchTo(a) } }
        } label: {
            HStack(spacing: 14) {
                if current {
                    Avatar(name: a.name, url: a.avatar, size: 46)
                        .overlay(Circle().strokeBorder(T.card, lineWidth: 2.5))
                        .padding(4).background(Circle().fill(T.grad))
                } else {
                    Avatar(name: a.name, url: a.avatar, size: 54)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(a.name).font(.on(16.5, .bold)).foregroundStyle(T.text).lineLimit(1)
                        if a.verified == true { Verified(size: 16) }
                    }
                    if let e = a.email, !e.isEmpty { Text(e).font(.on(13)).foregroundStyle(T.muted).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if current {
                    Text("Сейчас").font(.on(11.5, .heavy)).foregroundStyle(T.accent)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(T.card)).shadow(color: T.accent.opacity(0.18), radius: 5, y: 2)
                } else if unread > 0 {
                    CountBadge(n: unread)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(T.faint)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(current ? T.accentSoft : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(current ? "\(a.name), сейчас" : "Перейти в \(a.name)")
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
