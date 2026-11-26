import SwiftUI

// Мелкие части переписки: перевёрнутая лента, свайп «ответить», точки «печатает…».
extension View {
    /// Перевернуть по вертикали — для «перевёрнутой» переписки (низ — начало прокрутки).
    func flipped() -> some View { scaleEffect(x: 1, y: -1, anchor: .center) }
}

// Свайп пузыря вправо — ответить на это сообщение.
struct SwipeToReply: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @State private var dx: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .overlay(alignment: .leading) {
                if dx > 10 {
                    Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(T.accent).opacity(Double(min(dx / 60, 1))).offset(x: -26)
                }
            }
            .simultaneousGesture(drag, including: enabled ? .all : .subviews)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5, v.translation.width > 0 else { return }
                dx = min(v.translation.width, 80)
            }
            .onEnded { _ in
                if dx > 60 { Haptics.play("light"); action() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dx = 0 }
            }
    }
}
