import SwiftUI
import UIKit
import Observation

/// メーター 1 個の表示用の状態 (ならした値・最大値)。本体と針の層で共有する
@Observable
final class GaugeRuntime {
    /// 表示用の値 (ならして丸めたもの)
    var shown: Double? = nil
    /// ならす前の最新の値
    var raw: Double? = nil
    /// ピーク値 (生の値の最大)
    var peak: Double? = nil
    @ObservationIgnored private var ema = Double.nan
    @ObservationIgnored var peakResetKey = 0

    func step(_ value: Double?, _ def: PidDef, _ smoothing: Double, trackPeak: Bool) {
        if raw != value { raw = value }
        guard let x = value else {
            ema = .nan
            if shown != nil { shown = nil }
            return
        }
        ema = ema.isNaN ? x : ema + (x - ema) * smoothingAlpha(smoothing)
        let st = def.displayStep
        let v = st > 0 ? (ema / st).rounded() * st : ema
        if shown != v { shown = v }
        if trackPeak && (peak == nil || x > peak!) { peak = x }
    }

    func resetPeak(_ key: Int) {
        if key != peakResetKey {
            peakResetKey = key
            peak = nil
        }
    }
}

/// メーターの表示に使う値の取り出し方 (ダッシュボードは最新の値、編集画面は試しの値)
struct GaugeInput {
    var def: PidDef
    var style: GaugeStyle
    var look: GaugeLook
    var unsupported: Bool
    /// 折れ線グラフ・値テーブル・変動監視の項目
    var series: [ChartSeries] = []
    var slot: String? = nil
    var interactive = false
}

/// 針の位置を補間して動かすための Canvas (Animatable)
private struct AnimatedGaugeCanvas: View, Animatable {
    var f: Double
    var draw: (GraphicsContext, CGSize, Double) -> Void

    var animatableData: Double {
        get { f }
        set { f = newValue }
    }

    var body: some View {
        Canvas { ctx, size in draw(ctx, size, f) }
    }
}

/// メーター 1 個分。スタイルに応じて描き分ける
struct GaugeCardView: View {
    let input: GaugeInput
    let runtime: GaugeRuntime
    /// 値を読む (毎回最新を返す)
    let valueSource: () -> Double?
    /// 値の読み直しのきっかけ (試しの値が変わったとき)
    var sourceKey: String = ""
    var layer: GaugeLayer = .all
    var peakResetKey = 0
    /// アナログで、針を別の層に描くか (true なら本体だけ描く)
    var needleSeparate = false

    var body: some View {
        let look = input.look
        if layer == .needle {
            if input.style == .ANALOG {
                needleCanvas(look).padding(look.showCard ? 8 : 2)
            }
        } else {
            content(look)
                .padding(look.showCard ? 8 : 2)
                .background(cardBackground(look))
                .task(id: taskKey(look)) { await loop(look) }
        }
    }

    private func taskKey(_ look: GaugeLook) -> String {
        "\(input.def.key)|\(look.smoothing)|\(look.showPeak)|\(sourceKey)|\(peakResetKey)"
    }

    private func loop(_ look: GaugeLook) async {
        runtime.resetPeak(peakResetKey)
        let ms = displayIntervalMs(look.smoothing)
        while !Task.isCancelled {
            runtime.step(valueSource(), input.def, look.smoothing, trackPeak: look.showPeak && !input.unsupported)
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
        }
    }

    @ViewBuilder
    private func cardBackground(_ look: GaugeLook) -> some View {
        ZStack {
            if look.objectShadow {
                Canvas { ctx, size in drawObjectShadow(ctx, size, input.style, look, cardInset: 2) }
                    .allowsHitTesting(false)
            }
            if look.showCard {
                RoundedRectangle(cornerRadius: 14).fill(GaugeColors.card)
                RoundedRectangle(cornerRadius: 14).stroke(GaugeColors.cardBorder, lineWidth: 1)
            }
        }
    }

    private var image: UIImage? { input.look.image.flatMap { GaugeImages.load($0) } }

    private func target(_ look: GaugeLook) -> Double {
        guard let v = runtime.shown, !input.unsupported else { return lastFraction }
        return fraction(input.def, v)
    }

    /// 値が一瞬途切れても針を 0 に戻さず、最後の位置で止めておく
    @State private var lastFraction: Double = 0

    @ViewBuilder
    private func needleCanvas(_ look: GaugeLook) -> some View {
        let def = input.def
        let value = input.unsupported ? nil : runtime.shown
        let ms = displayIntervalMs(look.smoothing)
        AnimatedGaugeCanvas(f: target(look)) { ctx, size, f in
            drawAnalog(ctx, size, def: def, value: value, f: f, unsupported: input.unsupported, look: look, image: nil, peak: nil, layer: .needle)
        }
        .animation(.linear(duration: Double(ms) / 1000), value: target(look))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ look: GaugeLook) -> some View {
        let def = input.def
        let unsupported = input.unsupported
        let value = unsupported ? nil : runtime.shown
        let peak = look.showPeak ? runtime.peak : nil
        let img = image
        let ms = displayIntervalMs(look.smoothing)
        switch input.style {
        case .ANALOG:
            let lay: GaugeLayer = needleSeparate ? .body : .all
            AnimatedGaugeCanvas(f: target(look)) { ctx, size, f in
                drawAnalog(ctx, size, def: def, value: value, f: f, unsupported: unsupported, look: look, image: img, peak: peak, layer: lay)
            }
            .animation(.linear(duration: Double(ms) / 1000), value: target(look))
            .onChange(of: runtime.shown) { _, v in if let v = v { lastFraction = fraction(def, v) } }
        case .BAR:
            AnimatedGaugeCanvas(f: target(look)) { ctx, size, f in
                drawBarGauge(ctx, size, def: def, value: value, f: f, unsupported: unsupported, look: look, image: img, peak: peak)
            }
            .animation(.linear(duration: Double(ms) / 1000), value: target(look))
            .onChange(of: runtime.shown) { _, v in if let v = v { lastFraction = fraction(def, v) } }
        case .DIGITAL:
            Canvas { ctx, size in
                drawDigital(ctx, size, def: def, value: value, unsupported: unsupported, look: look, image: img, peak: peak)
            }
        case .LAMP:
            let rawV = unsupported ? nil : runtime.raw
            Canvas { ctx, size in
                drawLamp(ctx, size, def: def, value: rawV, unsupported: unsupported, look: look, image: img)
            }
        case .TABLE:
            TableGaugeView(series: input.series, look: look)
        case .CHART:
            ChartGaugeView(series: input.series, look: look, interactive: input.interactive, slot: input.slot)
        case .MONITOR:
            MonitorGaugeView(series: input.series, look: look, interactive: input.interactive, slot: input.slot)
        }
    }
}

/// 折れ線グラフ・値テーブル・変動監視の項目
struct ChartSeries {
    var def: PidDef
    var value: Double?
    var right: Bool = true
}

/// 折れ線グラフ等の項目 (先頭はメーターの項目、続いて追加した項目)
func chartSeries(_ g: GaugeConfig, _ def: PidDef, _ values: [String: Double], _ catalog: PidCatalog) -> [ChartSeries] {
    var out = [ChartSeries(def: def, value: values[def.key] ?? g.fallbackKey.flatMap { values[$0] }, right: g.isRightAxis(0, def.key))]
    for (j, k) in g.chartKeys.enumerated() {
        guard var base = catalog.get(k) else { continue }
        let key = base.key
        if let l = g.itemLabels[k], !l.trimmingCharacters(in: .whitespaces).isEmpty { base.shortName = l }
        out.append(ChartSeries(def: base, value: values[key], right: g.isRightAxis(j + 1, k)))
    }
    return out
}
