import SwiftUI

// Фото на весь экран: листание и увеличение двумя пальцами.
struct Gallery: View {
    let photos: [String]
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                    ZoomImage(url: API.shared.media(p)).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel("Закрыть")
        }
        .statusBarHidden()
    }
}

struct ZoomImage: View {
    let url: URL?
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1

    var body: some View {
        RemoteImage(url: url, contentMode: .fit)
            .scaleEffect(scale)
            .gesture(MagnificationGesture()
                .onChanged { scale = max(1, min(4, last * $0)) }
                .onEnded { _ in last = scale })
            .onTapGesture(count: 2) { withAnimation(.spring()) { scale = scale > 1 ? 1 : 2.5; last = scale } }
    }
}
