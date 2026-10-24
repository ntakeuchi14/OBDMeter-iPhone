import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// グラフの横軸の時間。記録の無い時間 (区間の間) を [pad] の幅に詰める
struct TimeAxis {
    let segs: [(Int64, Int64)]
    let pad: Int64
    let cs: [Int64]

    init(_ segs: [(Int64, Int64)], _ pad: Int64) {
        self.segs = segs
        self.pad = pad
        var arr: [Int64] = []
        var c: Int64 = 0
        for (a, b) in segs { arr.append(c); c += (b - a) + pad }
        cs = arr
    }

    private func segAt(_ t: Int64) -> Int {
        var lo = 0, hi = segs.count - 1, r = -1
        while lo <= hi {
            let m = (lo + hi) / 2
            if segs[m].0 <= t { r = m; lo = m + 1 } else { hi = m - 1 }
        }
        return r
    }

    func toC(_ t: Int64) -> Int64 {
        if segs.isEmpty { return t }
        let i = segAt(t)
        if i < 0 { return cs[0] - (segs[0].0 - t) }
        let (a, b) = segs[i]
        if t <= b { return cs[i] + (t - a) }
        if i == segs.count - 1 { return cs[i] + (b - a) + (t - b) }
        return cs[i] + (b - a) + Swift.min(t - b, pad)
    }

    func toReal(_ c: Int64) -> Int64 {
        if segs.isEmpty { return c }
        if c < cs[0] { return segs[0].0 - (cs[0] - c) }
        var lo = 0, hi = cs.count - 1, i = 0
        while lo <= hi {
            let m = (lo + hi) / 2
            if cs[m] <= c { i = m; lo = m + 1 } else { hi = m - 1 }
        }
        let (a, b) = segs[i]
        let off = c - cs[i]
        return off <= b - a ? a + off : b + (off - (b - a))
    }

    func overlaps(_ from: Int64, _ to: Int64) -> [(Int64, Int64)] {
        if segs.isEmpty { return [(from, to)] }
        var out: [(Int64, Int64)] = []
        for (i, (a, b)) in segs.enumerated() {
            let bb = i == segs.count - 1 ? Swift.max(b, to) : b
            let s = Swift.max(a, from), e = Swift.min(bb, to)
            if s <= e { out.append((s, e)) }
        }
        return out
    }
}

private let TIME_STEPS: [Int64] = [
    60_000, 120_000, 300_000, 600_000, 900_000, 1_800_000, 3_600_000, 7_200_000, 10_800_000, 21_600_000,
    43_200_000, 86_400_000, 172_800_000, 604_800_000, 1_209_600_000, 2_592_000_000,
]

private func timeStep(_ span: Int64) -> Int64 { TIME_STEPS.first { $0 * 5 >= span } ?? TIME_STEPS[TIME_STEPS.count - 1] }

private func nearestSample(_ pts: [Sample], _ t: Int64) -> Sample? { pts.min { Swift.abs($0.t - t) < Swift.abs($1.t - t) } }

private func gapThreshold(_ intervalMs: Int64, _ span: Int64) -> Int64 { Swift.max(intervalMs * 3, span / 200, 5_000) }

/// グラフの記録の読み込み結果
private struct ChartData {
    var segs: [(Int64, Int64)] = []
    var data: [String: [Sample]] = [:]
    var earliest: Int64? = nil
}

/// 複数項目の折れ線グラフ。記録を読み、項目ごとに記録のある時刻を線でつなぐ。
/// 左右にドラッグで記録の全期間をスクロール、ピンチで 1 画面の期間を拡大縮小、ダブルタップで現在に戻る
struct ChartGaugeView: View {
    @Environment(AppModel.self) private var model
    let series: [ChartSeries]
    let look: GaugeLook
    let interactive: Bool
    let slot: String?

    @State private var span: Int64 = 0
    @State private var endAt: Int64? = nil
    @State private var cursorAt: Int64? = nil
    @State private var now: Int64 = nowMs()
    @State private var revSeen = 0
    @State private var loaded = ChartData()
    @State private var dragStartC: Int64? = nil
    @State private var zoomStart: Int64? = nil

    private var keys: [String] { series.map { $0.def.key } }
    private var spanV: Int64 { span > 0 ? span : look.chartSpanMs }

    var body: some View {
        let axisW: CGFloat = 34
        let hasLeft = series.contains { !$0.right }
        let hasRight = series.contains { $0.right }
        VStack(spacing: 2) {
            if look.legendPosition == .TOP {
                HStack(alignment: .top, spacing: 4) {
                    legend.frame(maxWidth: .infinity, alignment: legendFrameAlign)
                    if interactive, let s = slot { CsvButtons(slot: s, keys: keys) }
                }
            } else if interactive, let s = slot {
                HStack { Spacer(); CsvButtons(slot: s, keys: keys) }
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in draw(ctx, size, hasLeft ? axisW : 0, hasRight ? axisW : 0) }
                    if look.legendPosition.inside {
                        insideLegend(geo.size, hasLeft ? axisW : 0, hasRight ? axisW : 0)
                    }
                    if endAt != nil || cursorAt != nil {
                        Text(endAt != nil ? "過去を表示中 (ダブルタップで現在へ)" : "時刻を選択中 (ダブルタップで現在値へ)")
                            .font(.system(size: 10))
                            .foregroundColor(GaugeColors.text)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .contentShape(Rectangle())
                .gesture(panZoom(geo.size.width - (hasLeft ? axisW : 0) - (hasRight ? axisW : 0)), including: interactive ? .all : .subviews)
                .onTapGesture(count: 2) {
                    if interactive { endAt = nil; cursorAt = nil; span = look.chartSpanMs }
                }
                .onTapGesture(count: 1, coordinateSpace: .local) { p in
                    guard interactive else { return }
                    let padL = Double(hasLeft ? axisW : 0)
                    let pw = Double(geo.size.width) - padL - Double(hasRight ? axisW : 0)
                    if pw > 0 {
                        let ax = TimeAxis(loaded.segs, gapThreshold(look.chartIntervalMs, spanV))
                        let ec = ax.toC(endAt ?? nowMs())
                        let frac = Swift.min(Swift.max((Double(p.x) - padL) / pw, 0), 1)
                        cursorAt = ax.toReal(ec - spanV + Int64(frac * Double(spanV)))
                    }
                }
            }
            if look.legendPosition == .BOTTOM {
                legend.frame(maxWidth: .infinity, alignment: legendFrameAlign)
            }
        }
        .padding(4)
        .task(id: look.chartSpanMs) { span = look.chartSpanMs }
        .task {
            // 時刻を進め、記録が増えたら読み直す (読み直しは一定の間隔まで)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let refresh = Swift.min(Swift.max(spanV / 300, 2_000), 60_000)
                let t = nowMs()
                if t - now >= 5_000 { now = t }
                if model.historyRevision != revSeen && t - lastLoad >= refresh { revSeen = model.historyRevision }
            }
        }
        .task(id: loadKey) { await reload() }
    }

    @State private var lastLoad: Int64 = 0

    private var legendFrameAlign: Alignment {
        switch look.legendAlign {
        case .START: return .leading
        case .CENTER: return .center
        case .END: return .trailing
        }
    }

    private var hAlign: HorizontalAlignment {
        switch look.legendAlign {
        case .START: return .leading
        case .CENTER: return .center
        case .END: return .trailing
        }
    }

    // MARK: - 読み込み

    private var loadKey: String {
        let q = Swift.max(spanV / 50, 1000)
        let end = endAt ?? now
        return "\(slot ?? "")|\(keys.joined(separator: ","))|\(spanV)|\(end / q)|\(revSeen)|\(look.chartSkipGaps)|\(look.chartIntervalMs)"
    }

    private func reload() async {
        guard let s = slot else { loaded = ChartData(); return }
        let history = model.history
        let ks = keys
        let sp = spanV
        let end = endAt ?? now
        let skip = look.chartSkipGaps
        let gapMs = gapThreshold(look.chartIntervalMs, sp)
        let result = await Task.detached(priority: .utility) { () -> ChartData in
            var out = ChartData()
            let q = Swift.max(sp / 50, 1000)
            let segEnd = (end / q + 1) * q
            let segFrom = segEnd - Swift.max(sp * 10, 86_400_000)
            out.segs = skip ? history.segments(s, ks, segFrom, segEnd, gapMs) : []
            let axis = TimeAxis(out.segs, gapMs)
            let cEnd = axis.toC(end)
            let start = axis.toReal(cEnd - sp)
            let qStart = start / q * q - q
            let qEnd = (end / q + 1) * q
            let ranges = axis.overlaps(qStart, qEnd)
            for k in ks {
                let (before, after) = history.neighbors(s, k, qStart, qEnd)
                var body: [Sample] = []
                for (a, b) in ranges {
                    let pts = Swift.min(Swift.max(Int(800 * (b - a + 1) / Swift.max(sp, 1)), 20), 800)
                    body += history.load(s, k, a, b, pts)
                }
                out.data[k] = (before.map { [$0] } ?? []) + body + (after.map { [$0] } ?? [])
            }
            out.earliest = history.earliest(s, ks)
            return out
        }.value
        loaded = result
        lastLoad = nowMs()
    }

    // MARK: - 操作

    private func panZoom(_ plotW: CGFloat) -> some Gesture {
        let drag = DragGesture(minimumDistance: 6)
            .onChanged { v in
                let t = nowMs()
                let ax = TimeAxis(loaded.segs, gapThreshold(look.chartIntervalMs, spanV))
                if dragStartC == nil { dragStartC = ax.toC(endAt ?? t) }
                guard let base = dragStartC, plotW > 0 else { return }
                let oldest = loaded.earliest ?? t
                let nowC = ax.toC(t)
                let minC = Swift.min(nowC, ax.toC(oldest) + spanV)
                let next = Swift.min(Swift.max(base - Int64(Double(v.translation.width) / Double(plotW) * Double(spanV)), minC), nowC)
                endAt = next >= nowC - spanV / 100 ? nil : ax.toReal(next)
            }
            .onEnded { _ in dragStartC = nil }
        let zoom = MagnificationGesture()
            .onChanged { k in
                if zoomStart == nil { zoomStart = spanV }
                guard let s0 = zoomStart, k > 0 else { return }
                let t = nowMs()
                let oldest = loaded.earliest ?? t
                let maxSpan = Swift.max(31 * 86_400_000, t - oldest)
                span = Swift.min(Swift.max(Int64(Double(s0) / Double(k)), 60_000), maxSpan)
            }
            .onEnded { _ in zoomStart = nil }
        return SimultaneousGesture(drag, zoom)
    }

    // MARK: - 凡例

    private var cursorTime: Int64? {
        guard let c = cursorAt else { return nil }
        let near = loaded.data.values.compactMap { nearestSample($0, c) }.min { Swift.abs($0.t - c) < Swift.abs($1.t - c) }
        return near?.t ?? c
    }

    private func cursorValues(_ ct: Int64) -> [String: Double] {
        var out: [String: Double] = [:]
        for k in keys {
            let pts = loaded.data[k] ?? []
            if look.chartStep {
                if let s = pts.last(where: { $0.t <= ct }) { out[k] = s.v }
            } else if let s = nearestSample(pts, ct), Swift.abs(s.t - ct) <= Swift.max(spanV / 20, 2_000) {
                out[k] = s.v
            }
        }
        return out
    }

    private var legend: some View {
        let ls = look.legendScale
        let ct = cursorTime
        let cv = ct.map { cursorValues($0) } ?? [:]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return FlowLayout(spacing: CGFloat(10 * ls), lineSpacing: 2, alignment: hAlign) {
            if let ct = ct {
                Text(fmt.string(from: Date(timeIntervalSince1970: Double(ct) / 1000)))
                    .font(.system(size: CGFloat(11 * look.labelSize * ls), weight: .bold))
                    .foregroundColor(GaugeColors.accent)
                    .lineLimit(1)
            }
            ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                let shown: Double? = ct != nil ? cv[s.def.key] : s.value
                HStack(spacing: CGFloat(4 * ls)) {
                    Circle().fill(look.chartColor(i)).frame(width: CGFloat(8 * ls), height: CGFloat(8 * ls))
                    Text(s.def.shortName + " ").font(look.labelFont(11 * look.labelSize * ls)).foregroundColor(look.labelColor).lineLimit(1)
                    Text(s.def.format(shown) + (look.showUnit ? " " + s.def.unitText : ""))
                        .font(look.valueFont(13 * look.valueSize * ls))
                        .foregroundColor(look.chartColor(i))
                        .lineLimit(1)
                        .shadow(color: look.glow > 0 ? look.chartColor(i) : .clear, radius: look.glow > 0 ? CGFloat(3 * look.glow + 1) : 0)
                }
            }
        }
    }

    private func insideLegend(_ size: CGSize, _ padL: CGFloat, _ padR: CGFloat) -> some View {
        let pos = look.legendPosition
        let top = pos == .INSIDE_TOP_LEFT || pos == .INSIDE_TOP_RIGHT
        let left = pos == .INSIDE_TOP_LEFT || pos == .INSIDE_BOTTOM_LEFT
        let align: Alignment = top ? (left ? .topLeading : .topTrailing) : (left ? .bottomLeading : .bottomTrailing)
        return legend
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(look.legendBgAlpha), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: Swift.max(size.width - padL - padR - 4, 10), alignment: left ? .leading : .trailing)
            .padding(.leading, padL + 2).padding(.trailing, padR + 2).padding(.top, 2).padding(.bottom, 16)
            .frame(width: size.width, height: size.height, alignment: align)
            .allowsHitTesting(false)
    }

    // MARK: - 描画

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ padLc: CGFloat, _ padRc: CGFloat) {
        let labelFont = Font.system(size: 10)
        let labelH = Double(ctx.measure(Text("00:00").font(labelFont)).height)
        let plotH = Double(size.height) - labelH - 2
        let w = Double(size.width)
        let padL = Double(padLc), padR = Double(padRc)
        let pw = w - padL - padR
        if plotH <= 4 || pw <= 4 { return }
        let sp = spanV
        let gapMs = gapThreshold(look.chartIntervalMs, sp)
        let axis = TimeAxis(loaded.segs, gapMs)
        let end = endAt ?? now
        let cEnd = axis.toC(end)
        let cStart = cEnd - sp
        let start = axis.toReal(cStart)
        func xAt(_ t: Int64) -> Double { padL + Double(axis.toC(t) - cStart) / Double(sp) * pw }
        let leftSeries = series.filter { !$0.right }
        let rightSeries = series.filter { $0.right }
        let leftRange: (Double, Double)? = leftSeries.isEmpty ? nil : (leftSeries.map { $0.def.min }.min() ?? 0, leftSeries.map { $0.def.max }.max() ?? 1)
        let rightRange: (Double, Double)? = rightSeries.isEmpty ? nil : (rightSeries.map { $0.def.min }.min() ?? 0, rightSeries.map { $0.def.max }.max() ?? 1)
        func yAt(_ right: Bool, _ v: Double) -> Double {
            let r = (right ? rightRange : leftRange) ?? (0, 1)
            let range = r.1 - r.0 > 0 ? r.1 - r.0 : 1
            return plotH - Swift.min(Swift.max((v - r.0) / range, -0.02), 1.02) * plotH
        }

        // 横の補助線
        for i in 0...4 {
            let y = plotH * Double(i) / 4
            var p = Path()
            p.move(to: CGPoint(x: padL, y: y)); p.addLine(to: CGPoint(x: padL + pw, y: y))
            ctx.stroke(p, with: .color(GaugeColors.track.opacity(i == 0 || i == 4 ? 0.9 : 0.5)), lineWidth: 1)
        }
        // 左右の縦軸の目盛り
        func drawAxis(_ range: (Double, Double)?, _ right: Bool) {
            guard let r = range else { return }
            let lo = r.0, hi = r.1
            let members = series.indices.filter { series[$0].right == right }
            let color = members.count == 1 ? look.chartColor(members[0]) : GaugeColors.subText
            let step = (hi - lo) / 4
            let dec = step >= 5 ? 0 : (step >= 0.5 ? 1 : 2)
            for i in 0...4 {
                let v = hi - step * Double(i)
                let t = Text(String(format: "%.\(dec)f", v)).font(labelFont).foregroundColor(color)
                let s = ctx.measure(t)
                let y = Swift.min(Swift.max(plotH * Double(i) / 4 - Double(s.height) / 2, 0), Swift.max(0, plotH - Double(s.height)))
                let x = right ? padL + pw + 3 : Swift.max(padL - 3 - Double(s.width), 0)
                ctx.draw(t, at: CGPoint(x: x, y: y), anchor: .topLeading)
            }
        }
        drawAxis(leftRange, false)
        drawAxis(rightRange, true)
        // 時刻の目盛り
        let step = timeStep(sp)
        let fmt = DateFormatter()
        fmt.dateFormat = step >= 21_600_000 ? "M/d HH:mm" : "HH:mm"
        let tz = TimeZone.current
        var lastLabelEnd = -1.0
        for (ra, rb) in axis.overlaps(start, end) {
            let off = Int64(tz.secondsFromGMT(for: Date(timeIntervalSince1970: Double(ra) / 1000))) * 1000
            var t = ra - (((ra + off) % step) + step) % step + step
            while t <= rb {
                let x = xAt(t)
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: plotH))
                ctx.stroke(p, with: .color(GaugeColors.track.opacity(0.5)), lineWidth: 1)
                let lt = Text(fmt.string(from: Date(timeIntervalSince1970: Double(t) / 1000))).font(labelFont).foregroundColor(GaugeColors.subText)
                let ls = ctx.measure(lt)
                let lx = Swift.min(Swift.max(x - Double(ls.width) / 2, 0), Swift.max(0, w - Double(ls.width)))
                if lx > lastLabelEnd + 4 {
                    ctx.draw(lt, at: CGPoint(x: lx, y: plotH + 2), anchor: .topLeading)
                    lastLabelEnd = lx + Double(ls.width)
                }
                t += step
            }
        }
        // 記録の無い時間を詰めたところに点線
        if axis.segs.count > 1 {
            for i in 1..<axis.segs.count {
                let bc = axis.cs[i] - axis.pad / 2
                if bc >= cStart && bc <= cEnd {
                    let x = padL + Double(bc - cStart) / Double(sp) * pw
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: plotH))
                    ctx.stroke(p, with: .color(GaugeColors.subText.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                }
            }
        }
        // 項目ごとの線
        var any = false
        var clipped = ctx
        clipped.clip(to: Path(CGRect(x: padL, y: 0, width: pw, height: plotH)))
        for (i, s) in series.enumerated() {
            let pts = loaded.data[s.def.key] ?? []
            if pts.isEmpty { continue }
            any = true
            let color = look.chartColor(i)
            var path = Path()
            for (idx, p) in pts.enumerated() {
                let pt = CGPoint(x: xAt(p.t), y: yAt(s.right, p.v))
                if idx == 0 { path.move(to: pt) } else {
                    if look.chartStep { path.addLine(to: CGPoint(x: xAt(p.t), y: yAt(s.right, pts[idx - 1].v))) }
                    path.addLine(to: pt)
                }
            }
            if look.glow > 0 {
                let gw = 2 + 8 * look.glow
                clipped.stroke(path, with: .color(color.opacity(0.15 * look.glow)), style: StrokeStyle(lineWidth: CGFloat(gw * 1.8), lineCap: .round, lineJoin: .round))
                clipped.stroke(path, with: .color(color.opacity(0.30 * look.glow)), style: StrokeStyle(lineWidth: CGFloat(gw), lineCap: .round, lineJoin: .round))
            }
            clipped.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let visible = pts.filter { let c = axis.toC($0.t); return c >= cStart && c <= cEnd }
            if !visible.isEmpty && visible.count <= Int(pw / 8) {
                for p in visible { clipped.fill(circlePath(CGPoint(x: xAt(p.t), y: yAt(s.right, p.v)), 2.5), with: .color(color)) }
            }
        }
        // 選んだ時刻の縦線
        if let ct = cursorTime {
            let c = axis.toC(ct)
            if c >= cStart && c <= cEnd {
                let cx = xAt(ct)
                var p = Path()
                p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: plotH))
                ctx.stroke(p, with: .color(GaugeColors.accent), lineWidth: 1.5)
                let cv = cursorValues(ct)
                for (i, s) in series.enumerated() {
                    guard let v = cv[s.def.key] else { continue }
                    let pt = CGPoint(x: cx, y: yAt(s.right, v))
                    ctx.fill(circlePath(pt, 4), with: .color(look.chartColor(i)))
                    ctx.stroke(circlePath(pt, 4), with: .color(GaugeColors.text), lineWidth: 1)
                }
            }
        }
        if !any && slot != nil {
            ctx.drawCentered(Text("この期間の記録はありません").font(labelFont).foregroundColor(GaugeColors.subText), CGPoint(x: padL + pw / 2, y: plotH / 2))
        }
    }
}

/// 記録の CSV の書き出し・読み込みボタン (アプリの画面でだけ出す)
struct CsvButtons: View {
    @Environment(AppModel.self) private var model
    let slot: String
    let keys: [String]
    var extra: (() -> Void)? = nil
    var extraLabel: String = ""
    @State private var shareURL: URL? = nil
    @State private var importing = false

    var body: some View {
        HStack(spacing: 4) {
            SmallButton("書出") {
                let (n, text) = model.history.exportCsv(slot, keys)
                let stamp = DateFormatter()
                stamp.locale = Locale(identifier: "en_US_POSIX")
                stamp.dateFormat = "yyyyMMdd_HHmm"
                let url = AppDirs.documents.appendingPathComponent("obdmeter_chart_\(stamp.string(from: Date())).csv")
                do {
                    try text.data(using: .utf8)?.write(to: url, options: .atomic)
                    model.showToast("\(n) 件を書き出しました")
                    shareURL = url
                } catch {
                    model.showToast("書き出しに失敗しました: \(error.localizedDescription)")
                }
            }
            SmallButton("読込") { importing = true }
            if let e = extra { SmallButton(extraLabel, action: e) }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                model.showToast("読み込みに失敗しました")
                return
            }
            let (ok, bad) = model.history.importCsv(slot, text)
            model.showToast("\(ok) 件を読み込みました" + (bad > 0 ? " (読めない行 \(bad) 件)" : ""))
        }
    }
}

struct SmallButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(GaugeColors.text)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(GaugeColors.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// 共有シート
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
