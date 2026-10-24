import SwiftUI
import UIKit

/// 変動監視。各項目の値が変わった回数を、選んだ期間で多い順に並べ、現在の値 (最新 − 初回) と最後に変わった時刻を出す
struct MonitorGaugeView: View {
    @Environment(AppModel.self) private var model
    let series: [ChartSeries]
    let look: GaugeLook
    let interactive: Bool
    let slot: String?

    @State private var window: Int = -1
    @State private var stats: [Monitor.Stat] = []
    @State private var tick = 0
    @State private var confirmReset = false

    private var keys: [String] { series.map { $0.def.key } }
    private var win: Int { window >= 0 ? window : look.monitorWindow }

    var body: some View {
        GeometryReader { geo in
            let base = Swift.min(Swift.max(Double(geo.size.height) / Double(Swift.max(keys.count + 2, 3)) * 0.45, 9), 22)
            let byKey = Dictionary(stats.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            let ordered = Monitor.rank(keys.map { k in byKey[k] ?? Monitor.Stat(key: k, first: nil, last: nil, lastChangeAt: nil, counts: []) }, win)
            let seriesByKey = Dictionary(series.map { ($0.def.key, $0) }, uniquingKeysWith: { a, _ in a })
            let fmt: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd HH:mm:ss"
                return f
            }()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(Monitor.WINDOWS.enumerated()), id: \.offset) { i, w in
                                let sel = i == win
                                Text(w.1)
                                    .font(.system(size: CGFloat(base * 0.85), weight: sel ? .bold : .regular))
                                    .foregroundColor(sel ? GaugeColors.background : GaugeColors.subText)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(sel ? look.accent : GaugeColors.track, in: RoundedRectangle(cornerRadius: 6))
                                    .onTapGesture { if interactive { window = i } }
                            }
                        }
                    }
                    if interactive, let s = slot {
                        CsvButtons(slot: s, keys: keys, extra: { confirmReset = true }, extraLabel: "リセット")
                    }
                }
                HStack(spacing: 0) {
                    let h = CGFloat(base * 0.75)
                    Text("#").frame(width: CGFloat(base * 1.8), alignment: .leading)
                    Text("項目").frame(maxWidth: .infinity, alignment: .leading)
                    Text("回数").frame(width: CGFloat(base * 3.5), alignment: .trailing)
                    Text("現在の値").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("最後の変化").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
                        .font(.system(size: h))
                }
                .font(.system(size: CGFloat(base * 0.75)))
                .foregroundColor(GaugeColors.subText)
                .padding(.top, 4)
                ForEach(Array(ordered.enumerated()), id: \.offset) { rank, st in
                    if let s = seriesByKey[st.key] {
                        let cur = Monitor.currentValue(st, s.value)
                        let count = st.count(win)
                        HStack(spacing: 0) {
                            Text("\(rank + 1)").font(look.labelFont(base * look.labelSize)).foregroundColor(GaugeColors.subText)
                                .frame(width: CGFloat(base * 1.8), alignment: .leading)
                            Text(s.def.shortName).font(look.labelFont(base * look.labelSize)).foregroundColor(look.labelColor)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(count)").font(look.valueFont(base * 1.1 * look.valueSize))
                                .foregroundColor(count > 0 ? look.accent : GaugeColors.subText)
                                .shadow(color: look.glow > 0 ? look.accent : .clear, radius: look.glow > 0 ? CGFloat(3 * look.glow + 1) : 0)
                                .frame(width: CGFloat(base * 3.5), alignment: .trailing)
                            Text(s.def.format(cur) + ((look.showUnit && cur != nil) ? " " + s.def.unitText : ""))
                                .font(look.valueFont(base * 1.1 * look.valueSize, bold: false)).foregroundColor(look.valueColor)
                                .lineLimit(1).minimumScaleFactor(0.5).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(st.lastChangeAt.map { fmt.string(from: Date(timeIntervalSince1970: Double($0) / 1000)) } ?? (st.first == nil ? "記録なし" : "変化なし"))
                                .font(.system(size: CGFloat(base * look.labelSize))).foregroundColor(GaugeColors.subText)
                                .lineLimit(1).minimumScaleFactor(0.5)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(4)
        .task(id: "\(slot ?? "")|\(keys.joined(separator: ","))|\(tick)") { await reload() }
        .task {
            // 記録が増えたら読み直す (2 秒に 1 回まで)。期間の境目が動くので一定の間隔でも読み直す
            var rev = model.historyRevision
            var last = nowMs()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let short = (Monitor.WINDOWS[safe: win]?.0 ?? 86_400_000) <= 600_000
                let t = nowMs()
                if model.historyRevision != rev || short || t - last >= 30_000 {
                    rev = model.historyRevision
                    last = t
                    tick += 1
                }
            }
        }
        .alert("記録をリセット", isPresented: $confirmReset) {
            Button("リセットする", role: .destructive) { if let s = slot { model.history.clear(s) } }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このメーターの変動の記録 (全項目の回数・変化時刻・初回の計測値) をすべて消して、次の計測からやり直します。元に戻せません。必要なら先に「書出」で CSV に保存してください。")
        }
    }

    private func reload() async {
        guard let s = slot else { stats = []; return }
        let history = model.history
        let ks = keys
        let result = await Task.detached(priority: .utility) { history.monitorStats(s, ks, nowMs()) }.value
        stats = result
    }
}

/// ページの背景 (色 → 柄 → 画像 の順に重ねる)
struct PageBackgroundView: View {
    let bg: PageBackground

    var body: some View {
        Canvas { ctx, size in drawPageBackground(ctx, size, bg) }
    }
}

func autoPatternColor(_ base: Color) -> Color { base.luminance < 0.4 ? .white : .black }

func drawPageBackground(_ ctx: GraphicsContext, _ size: CGSize, _ bg: PageBackground) {
    let base = bg.color.map { Color(argb: $0) } ?? GaugeColors.background
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
    if bg.pattern != .NONE {
        let pc = (bg.patternColor.map { Color(argb: $0) } ?? autoPatternColor(base)).opacity(Swift.min(Swift.max(bg.patternAlpha, 0), 1))
        drawPattern(ctx, size, bg.pattern, pc, 24 * Swift.min(Swift.max(bg.patternScale, 0.2), 6))
    }
    if let name = bg.image, let img = GaugeImages.load(name), img.size.width > 0 {
        let w = Double(size.width) * bg.imageWidth
        let h = bg.keepAspect ? w * Double(img.size.height) / Double(img.size.width) : Double(size.height) * bg.imageHeight
        let cx = Double(size.width) * bg.imageX
        let cy = Double(size.height) * bg.imageY
        var c = ctx
        c.opacity = Swift.min(Swift.max(bg.imageAlpha, 0), 1)
        c.draw(Image(uiImage: img), in: CGRect(x: cx - w / 2, y: cy - h / 2, width: Swift.max(w, 1), height: Swift.max(h, 1)))
    }
}

/// 柄を [s] (pt) の大きさで敷き詰める
private func drawPattern(_ ctx: GraphicsContext, _ size: CGSize, _ p: BgPattern, _ c: Color, _ s: Double) {
    let w = Double(size.width), h = Double(size.height)
    switch p {
    case .NONE:
        break
    case .GRID:
        let sw = Swift.max(1, s * 0.05)
        var path = Path()
        var x = 0.0
        while x <= w { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h)); x += s }
        var y = 0.0
        while y <= h { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y)); y += s }
        ctx.stroke(path, with: .color(c), lineWidth: CGFloat(sw))
    case .CHECK:
        var path = Path()
        var row = 0
        var y = 0.0
        while y < h {
            var x = row % 2 == 0 ? 0 : s
            while x < w { path.addRect(CGRect(x: x, y: y, width: s, height: s)); x += s * 2 }
            y += s; row += 1
        }
        ctx.fill(path, with: .color(c))
    case .STRIPE:
        var path = Path()
        var x = -h
        while x < w + h { path.move(to: CGPoint(x: x, y: h)); path.addLine(to: CGPoint(x: x + h, y: 0)); x += s }
        ctx.stroke(path, with: .color(c), lineWidth: CGFloat(s * 0.35))
    case .DOT:
        let r = s * 0.12
        var path = Path()
        var row = 0
        var y = s / 2
        while y < h + s {
            var x = row % 2 == 0 ? s / 2 : s
            while x < w + s { path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)); x += s }
            y += s * 0.866; row += 1
        }
        ctx.fill(path, with: .color(c))
    case .CARBON:
        // 2×2 の織り目: 縦の糸と横の糸を交互に、それぞれ明暗のグラデーションで描く
        let t = s / 2
        var j = 0
        var y = 0.0
        while y < h {
            var i = 0
            var x = 0.0
            while x < w {
                let rect = Path(CGRect(x: x, y: y, width: t, height: t))
                if (i + j) % 2 == 0 {
                    ctx.fill(rect, with: .linearGradient(Gradient(colors: [c.opacity(0.25), c, c.opacity(0.25)]),
                                                         startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + t, y: y)))
                } else {
                    ctx.fill(rect, with: .linearGradient(Gradient(colors: [c.opacity(0.15), c.opacity(0.7), c.opacity(0.15)]),
                                                         startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + t)))
                }
                x += t; i += 1
            }
            y += t; j += 1
        }
    case .HONEYCOMB:
        let r = s * 0.6
        let hw = sqrt(3.0) * r
        var path = Path()
        var row = 0
        var cy = 0.0
        while cy < h + r * 2 {
            var cx = row % 2 == 0 ? 0 : hw / 2
            while cx < w + hw {
                for k in 0...5 {
                    let a = Double.pi / 3 * Double(k) - Double.pi / 6
                    let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                    if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.closeSubpath()
                cx += hw
            }
            cy += r * 1.5; row += 1
        }
        ctx.stroke(path, with: .color(c), lineWidth: CGFloat(Swift.max(1, s * 0.05)))
    case .WOOD:
        // 木目: ゆるく波打つ線を、太さと濃さを変えながら重ねる (毎回同じ模様)
        let step = Swift.max(2, s * 0.12)
        var y = -s
        var k = 0
        while y < h + s {
            var path = Path()
            var x = 0.0
            let kd = Double(k)
            let amp = s * (0.25 + 0.2 * sin(kd * 1.7))
            let phase = kd * 0.9
            path.move(to: CGPoint(x: 0, y: y))
            while x <= w {
                let yy = y + amp * sin(x / (s * 6) + phase) + amp * 0.4 * sin(x / (s * 1.9) + phase * 2.3)
                path.addLine(to: CGPoint(x: x, y: yy))
                x += Swift.max(4, s * 0.25)
            }
            let a = 0.35 + 0.65 * ((sin(kd * 2.39) + 1) / 2)
            ctx.stroke(path, with: .color(c.opacity(a)), lineWidth: CGFloat(Swift.max(1, step * (0.3 + 0.7 * a))))
            y += step * (1.2 + (sin(kd * 0.73) + 1))
            k += 1
        }
    }
}
