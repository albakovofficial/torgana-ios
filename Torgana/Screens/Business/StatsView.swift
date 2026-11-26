import SwiftUI
import Charts

// Статистика магазина: 7/30/90 дней, график просмотров, лучшие объявления, выгрузка в Excel
struct StatsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var nav: Nav
    @State private var days = "30"
    @State private var s: ShopStats?
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Seg(items: [("7", "7 дней"), ("30", "30 дней"), ("90", "90 дней")], value: $days)
            if let s {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metric("Показы в ленте", s.totals.impressions, s.prev.impressions)
                    metric("Просмотры", s.totals.views, s.prev.views)
                    metric("В избранное", s.totals.favs, s.prev.favs)
                    metric("Объявлений", s.active ?? 0, nil)
                }
                Chart(Array(s.daily.enumerated()), id: \.offset) { _, d in
                    BarMark(x: .value("День", d.day), y: .value("Просмотры", d.views)).foregroundStyle(T.accent).cornerRadius(3)
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
                .frame(height: 150)
                .panel(radius: 20, padding: 14)
                if !s.listings.isEmpty {
                    SettingsGroup(title: "Лучшие объявления") {
                        ForEach(Array(s.listings.prefix(5).enumerated()), id: \.element.id) { i, l in
                            Button { nav.push(.listing(l.id)) } label: {
                                HStack(spacing: 12) {
                                    RemoteImage(url: API.shared.media(l.photo)).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(l.title).font(.on(14.5, .semibold)).foregroundStyle(T.text).lineLimit(1)
                                        Text("\(Fmt.number(l.views)) \(Fmt.plural(l.views, "просмотр", "просмотра", "просмотров")) · \(l.favs) в избранном").font(.on(12.5)).foregroundStyle(T.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 14).frame(minHeight: 60).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { if i < min(5, s.listings.count) - 1 { T.line.opacity(0.6).frame(height: 1).padding(.leading, 70) } }
                        }
                    }
                }
                Button { Task { await export() } } label: {
                    if exporting { ProgressView() } else { Label("Выгрузить в Excel", systemImage: "tablecells") }
                }
                .buttonStyle(TButton(kind: .soft, height: 48)).disabled(exporting)
            } else { LoadingView() }
        }
        .task(id: days) { await load() }
    }

    // Плитка: число, стрелка вверх (зелёная) или вниз (красная) с процентом и «было N за прошлую неделю» — как на сайте.
    private func metric(_ title: String, _ n: Int, _ prev: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.on(12.5)).foregroundStyle(T.muted)
            Text(Fmt.number(n)).font(.on(22, .heavy)).foregroundStyle(T.text)
            if let prev {
                TrendBadge(now: n, was: prev)
                Text("было \(Fmt.number(prev)) \(Self.past[days] ?? "раньше")").font(.on(11.5)).foregroundStyle(T.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("активных сейчас").font(.on(11.5)).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .panel(radius: 18, padding: 14)
    }
    private static let past = ["7": "за прошлую неделю", "30": "за прошлые 30 дней", "90": "за прошлые 90 дней"]

    private func load() async {
        do { s = try await API.shared.get("/api/my/shop/stats", query: ["days": days]) }
        catch is CancellationError {} catch { app.fail(error, "Не удалось загрузить") }
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        do {
            let data = try await API.shared.data("/api/my/shop/stats.csv", query: ["days": days])
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("torgana-stats-\(days).csv")
            try data.write(to: url)
            Bridge.present([url])
        } catch { app.fail(error, "Не получилось выгрузить") }
    }
}

/// Стрелка вверх (зелёная), вниз (красная) или вправо (без изменений) и процент к прошлому периоду.
struct TrendBadge: View {
    let now: Int
    let was: Int

    private var tone: RowStatus.Tone { now == was ? .off : now > was ? .ok : .bad }
    private var icon: String { now == was ? "arrow.right" : now > was ? "arrow.up" : "arrow.down" }
    private var label: String {
        if now == was { return "0%" }
        guard was > 0 else { return "новое" }
        let pct = (Double(now) - Double(was)) / Double(was) * 100
        return "\(abs(Int(pct.rounded())))%"
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy))
            Text(label).font(.on(12.5, .heavy))
        }
        .foregroundStyle(tone.ink)
        .padding(.leading, 6).padding(.trailing, 8).frame(height: 22)
        .background(Capsule().fill(tone.fill))
    }
}
