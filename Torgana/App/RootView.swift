import SwiftUI

struct RootView: View {
    @ObservedObject private var web = WebController.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            TorganaWebView(controller: web)
                .ignoresSafeArea()                 // сайт сам учитывает «чёлку» и полоску внизу (viewport-fit=cover)
                .opacity(web.firstLoadDone ? 1 : 0)
            if !web.firstLoadDone && !web.failed {
                SplashView()
                    .transition(.opacity)
            }
            if web.failed {
                OfflineView { web.retry() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: web.firstLoadDone)
        .animation(.easeOut(duration: 0.2), value: web.failed)
        .onAppear { web.start(router.baseURL) }
        .onReceive(router.$pendingURL.compactMap { $0 }) { url in
            web.load(url)
            router.pendingURL = nil
        }
    }
}

// Пока сайт открывается: знак Торганы на белом и индикатор.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Color(red: 0.24, green: 0.31, blue: 0.72).opacity(0.28), radius: 14, y: 8)
            ProgressView()
                .tint(Color("AccentColor"))
        }
    }
}

// Нет связи: понятный экран и кнопка «Повторить» вместо белой страницы.
struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color("AccentColor").opacity(0.1)))
            Text("Нет соединения")
                .font(.system(size: 22, weight: .bold))
            Text("Проверьте интернет и попробуйте ещё раз.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Повторить")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: 260)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color("AccentColor")))
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("LaunchBackground").ignoresSafeArea())
    }
}
