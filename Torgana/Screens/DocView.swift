import SwiftUI
import UIKit

// Документы (правила, соглашение, политика, согласие, реквизиты) — с сервера (GET /api/pages/:slug), тот же текст, что на сайте.
struct DocView: View {
    let slug: String
    @EnvironmentObject private var nav: Nav
    @State private var title = ""
    @State private var text: AttributedString?
    @State private var error: String?

    private struct Page: Decodable { let title: String; let html: String }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackLink()
                if let text {
                    PageTitle(text: title, size: 32).padding(.top, 8)
                    Text(text).font(.on(17)).foregroundStyle(T.text).tint(T.accent).lineSpacing(7).textSelection(.enabled).padding(.top, 20)
                } else if let error {
                    EmptyState(title: "Не открылось", text: error).padding(.top, 8)
                } else { LoadingView() }
            }
            .padding(.horizontal, 20)
            TabBarSpace()
        }
        .sitePage()
        .environment(\.openURL, OpenURLAction { url in
            if Router.shared.isInternal(url) || url.scheme == nil { nav.open(path: url.path + (url.query.map { "?" + $0 } ?? "")); return .handled }
            return .systemAction
        })
        .task {
            do {
                let p: Page = try await API.shared.get("/api/pages/\(slug)")
                title = p.title
                text = DocView.attributed(p.html)
            } catch { self.error = (error as? APIError)?.message ?? error.localizedDescription }
        }
    }

    /// HTML документа → текст с заголовками, списками и ссылками (шрифт Onest, цвета темы задаёт SwiftUI).
    static func attributed(_ html: String) -> AttributedString {
        let css = "<style>body{font-family:'Onest-Regular';font-size:17px} h2{font-family:'Onest-ExtraBold';font-size:23px} li{margin-bottom:8px} b,strong{font-family:'Onest-SemiBold'} .muted{color:#888}</style>"
        guard let data = (css + html).data(using: .utf8),
              let ns = try? NSMutableAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { return AttributedString(html) }
        // Цвет текста — от темы, а не чёрный из HTML; ссылки — относительные адреса делаем полными.
        ns.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: ns.length))
        ns.enumerateAttribute(.link, in: NSRange(location: 0, length: ns.length)) { v, r, _ in
            if let s = v as? String { ns.addAttribute(.link, value: API.shared.url(s), range: r) }
            else if let u = v as? URL, u.host == nil { ns.addAttribute(.link, value: API.shared.url(u.relativeString), range: r) }
        }
        let a = (try? AttributedString(ns, including: \.uiKit)) ?? AttributedString(ns.string)
        return a
    }
}
