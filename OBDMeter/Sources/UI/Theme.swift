import SwiftUI
import UIKit

extension Color {
    /// ARGB (0xAARRGGBB) の整数から作る
    init(argb: Int64) {
        let a = Double((argb >> 24) & 0xFF) / 255
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >> 8) & 0xFF) / 255
        let b = Double(argb & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// ARGB の整数にする
    var argb: Int64 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int64 { Int64((Swift.min(Swift.max(v, 0), 1) * 255).rounded()) }
        return (c(a) << 24) | (c(r) << 16) | (c(g) << 8) | c(b)
    }

    /// [t] (0〜1) だけ [other] に近づけた色
    func lerp(_ other: Color, _ t: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(Swift.min(Swift.max(t, 0), 1))
        return Color(.sRGB, red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k),
                     blue: Double(b1 + (b2 - b1) * k), opacity: Double(a1 + (a2 - a1) * k))
    }

    /// 明るさ (0〜1)
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Double(0.2126 * r + 0.7152 * g + 0.0722 * b)
    }
}

enum GaugeColors {
    static let background = Color(argb: 0xFF0E1116)
    static let card = Color(argb: 0xFF161A21)
    static let cardBorder = Color(argb: 0xFF242A33)
    static let track = Color(argb: 0xFF2A303A)
    static let tick = Color(argb: 0xFF8A93A0)
    static let text = Color(argb: 0xFFE8EAED)
    static let subText = Color(argb: 0xFFB3BAC5)
    static let accent = Color(argb: 0xFF4FC3F7)
    static let warn = Color(argb: 0xFFFF5A36)
    static let warnZone = Color(argb: 0x66FF5A36)
    static let ring = Color(argb: 0xFFB0B6BE)
    static let peak = Color(argb: 0xFFFFCA28)
}

/// 線の色の自動割り当て
let CHART_PALETTE: [Color] = [
    Color(argb: 0xFF4FC3F7), Color(argb: 0xFFFF9800), Color(argb: 0xFF66BB6A),
    Color(argb: 0xFFEC407A), Color(argb: 0xFFFFCA28), Color(argb: 0xFFAB47BC),
]

/// メーター 1 個の見た目をすべてまとめたもの (保存形式の GaugeDesign から作る)。
/// 角度は「3 時 = 0°、時計回り」に変換済み
struct GaugeLook {
    var accent = GaugeColors.accent
    var startAngle: Double = 150
    var sweep: Double = 240
    var majorDivisions: Int? = nil
    var minorDivisions = 0
    var showLabels = true
    var tickRadius: Double = 1
    var tickColor = GaugeColors.tick
    var labelColor = GaugeColors.subText
    var labelSize: Double = 1
    var ring: RingStyle = .NONE
    var ringColor = GaugeColors.ring
    var showTrack = true
    var showValueArc = true
    var arcWidth: Double = 1
    var redZone: ClosedRange<Double>? = nil
    var redZoneColor = GaugeColors.warnZone
    var showNeedle = true
    var needleColor = GaugeColors.text
    var needleLength: Double = 1
    var needleWidth: Double = 1
    var needleTail: Double = 0.12
    var knobColor: Color? = nil
    var knobSize: Double = 1
    var ringThickness: Double = 1
    var ringDepth: Double = 0.6
    var ringInner: Double = 0.4
    var valueOffsetX: Double = 0
    var imageOffsetX: Double = 0
    var imageOffsetY: Double = 0
    var faceColor: Color? = nil
    var faceScale: Double = 1
    var panelStyle: PanelStyle = .FLAT
    var panelDepth: Double = 0.6
    var panelGloss = false
    var needleShadow = false
    var objectShadow = false
    var shadowStrength: Double = 1
    var nameOffsetX: Double = 0
    var nameOffsetY: Double = 0
    var nameColor = GaugeColors.subText
    var unitOffsetX: Double = 0
    var unitOffsetY: Double = 0
    var unitColor = GaugeColors.subText
    var lampCondition: Condition? = nil
    var lampOnColor = GaugeColors.warn
    var lampOffColor = Color(argb: 0xFF2A2F36)
    var tableMaxRows = 5
    var tableValueBg: Color? = nil
    var tableValueImage: String? = nil
    var tableNameRatio: Double = 0.4
    var tableUnitRatio: Double = 0.2
    var tableUnitInline = false
    var tableNameInline = false
    var tableNameSize: Double = 1
    var tableUnitSize: Double = 1
    var tableMarginBottom: Double = 0
    var tableMarginRight: Double = 0
    var tableRowGap: Double = 0
    var tableColGap: Double = 0
    var chartSpanMs: Int64 = 3_600_000
    var barAngle: Double = 0
    var barSegments = 0
    var barSegmentGap: Double = 0.25
    var barArc = false
    var barTaper: Double = 0
    var barOffColor: Color? = nil
    var barZoneColors = false
    var barMidColor = Color(argb: 0xFFFFC107)
    var barMidFrom: Double? = nil
    var glow: Double = 0
    var smoothing: Double = 0.5
    var showTicks = true
    var arcRoundCap = false
    var trackColor: Color? = nil
    var arcTipDot = false
    var arcTipColor = Color.white
    var ghostDigits = false
    var ghostAlpha: Double = 0.15
    var chartIntervalMs: Int64 = 60_000
    var chartSkipGaps = true
    var chartStep = false
    var legendPosition: LegendPosition = .TOP
    var legendAlign: LegendAlign = .START
    var legendScale: Double = 1
    var monitorWindow = 1
    var legendBgAlpha: Double = 0.5
    var chartColors: [Color?] = []
    var showPeak = false
    var peakColor = GaugeColors.peak
    var showPeakValue = false
    var peakTextColor = GaugeColors.peak
    var peakTextSize: Double = 1
    var peakTextX: Double = 0
    var peakTextY: Double = 0
    var showValue = true
    var valueColor = GaugeColors.text
    var valuePosition: Double = 0.42
    var valueSize: Double = 1
    var showName = true
    var showUnit = true
    var image: String? = nil
    var imageScale: Double = 1
    var showCard = true
    /// 取り込んだフォントの PostScript 名 (nil = 既定)
    var valueFontName: String? = nil
    var labelFontName: String? = nil

    func chartColor(_ index: Int) -> Color {
        if let c = chartColors[safe: index] ?? nil { return c }
        return index == 0 ? accent : CHART_PALETTE[index % CHART_PALETTE.count]
    }

    /// 数値のフォント (既定は等幅)
    func valueFont(_ size: Double, bold: Bool = true) -> Font {
        let s = CGFloat(Swift.max(size, 1))
        if let n = valueFontName { return Font.custom(n, fixedSize: s) }
        return Font.system(size: s, weight: bold ? .bold : .regular, design: .monospaced)
    }

    /// 文字 (名前・単位・目盛りの数字) のフォント
    func labelFont(_ size: Double, weight: Font.Weight = .regular) -> Font {
        let s = CGFloat(Swift.max(size, 1))
        if let n = labelFontName { return Font.custom(n, fixedSize: s) }
        return Font.system(size: s, weight: weight)
    }
}

private func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(v, lo), hi) }
private func col(_ v: Int64?, _ d: Color) -> Color { v.map { Color(argb: $0) } ?? d }

extension GaugeConfig {
    /// メーターの設定 (表示名・範囲・警告値・桁数) を項目の定義に反映した、描画用の定義
    func resolvedDef(_ catalog: PidCatalog) -> PidDef? {
        guard var base = catalog.get(pidKey) else { return nil }
        let d = design
        let mn = d.min ?? base.min
        var mx = d.max ?? base.max
        if !(mx > mn) { mx = Swift.max(base.max, mn + 1) }
        let origWarnAbove = base.warnAbove, origWarnBelow = base.warnBelow
        if let l = d.label, !l.trimmingCharacters(in: .whitespaces).isEmpty { base.shortName = l }
        base.min = mn
        base.max = mx
        base.decimals = d.decimals ?? base.decimals
        base.warnAbove = d.useDefaultWarn ? origWarnAbove : d.warnAbove
        base.warnBelow = d.useDefaultWarn ? origWarnBelow : d.warnBelow
        return base
    }

    func look(_ def: PidDef, _ fontName: (String?) -> String?) -> GaugeLook {
        design.toLook(def, style, fontName)
    }
}

extension GaugeDesign {
    /// 保存されたデザイン設定を描画用の [GaugeLook] にする
    func toLook(_ def: PidDef, _ style: GaugeStyle, _ fontName: (String?) -> String?) -> GaugeLook {
        var l = GaugeLook()
        let accentC = col(color, GaugeColors.accent)
        l.accent = accentC
        // 角度: 保存は「12 時 = 0°、時計回り」、描画は「3 時 = 0°」
        let s = clampD(startAngle, -360, 360)
        let e = clampD(endAngle, -360, 360)
        var cw = e - s
        if cw <= 0 { cw += 360 }
        cw = clampD(cw, 10, 360)
        var sweepV = cw
        if counterClockwise && style == .ANALOG {
            var ccw = s - e
            if ccw <= 0 { ccw += 360 }
            sweepV = -clampD(ccw, 10, 360)
        }
        l.startAngle = s - 90
        l.sweep = sweepV
        var zone: ClosedRange<Double>? = nil
        if showRedZone {
            if redZoneFrom != nil || redZoneTo != nil {
                let from = redZoneFrom ?? def.min
                let to = redZoneTo ?? def.max
                if to > from { zone = from...to }
            } else if let wa = def.warnAbove, def.max > wa {
                zone = wa...def.max
            } else if let wb = def.warnBelow, wb > def.min {
                zone = def.min...wb
            }
        }
        l.majorDivisions = majorDivisions.flatMap { (1...40).contains($0) ? $0 : nil }
        l.minorDivisions = Swift.min(Swift.max(minorDivisions, 0), 9)
        l.showLabels = showLabels
        l.tickRadius = clampD(tickRadius, 0.3, 1.2)
        l.tickColor = col(tickColor, GaugeColors.tick)
        l.labelColor = col(labelColor, GaugeColors.subText)
        l.labelSize = clampD(labelSize, 0.4, 2.5)
        l.ring = ring
        l.ringColor = col(ringColor, GaugeColors.ring)
        l.showTrack = showTrack
        l.showValueArc = showValueArc
        l.arcWidth = clampD(arcWidth, 0, 3)
        l.redZone = zone
        l.redZoneColor = col(redZoneColor, GaugeColors.warnZone)
        l.showNeedle = showNeedle
        l.needleColor = col(needleColor, GaugeColors.text)
        l.needleLength = clampD(needleLength, 0.3, 1.3)
        l.needleWidth = clampD(needleWidth, 0.2, 4)
        l.needleTail = clampD(needleTail, 0, 0.6)
        l.knobColor = knobColor.map { Color(argb: $0) }
        l.knobSize = clampD(knobSize, 0, 4)
        l.ringThickness = clampD(ringThickness, 0.2, 4)
        l.ringDepth = clampD(ringDepth, 0, 1)
        l.ringInner = clampD(ringInner, 0, 0.8)
        l.valueOffsetX = clampD(valueOffsetX, -0.95, 0.95)
        l.imageOffsetX = clampD(imageOffsetX, -0.6, 0.6)
        l.imageOffsetY = clampD(imageOffsetY, -0.6, 0.6)
        l.faceColor = faceColor.map { Color(argb: $0) }
        l.faceScale = clampD(faceScale, 0.2, 1.5)
        l.panelStyle = panelStyle
        l.panelDepth = clampD(panelDepth, 0, 1)
        l.panelGloss = panelGloss
        l.needleShadow = needleShadow
        l.objectShadow = objectShadow
        l.shadowStrength = clampD(shadowStrength, 0, 1.5)
        l.barAngle = clampD(barAngle, -180, 180)
        l.barSegments = Swift.min(Swift.max(barSegments, 0), 60)
        l.barSegmentGap = clampD(barSegmentGap, 0.05, 0.8)
        l.barArc = barArc
        l.barTaper = clampD(barTaper, 0, 1)
        l.barOffColor = barOffColor.map { Color(argb: $0) }
        l.barZoneColors = barZoneColors
        l.barMidColor = col(barMidColor, Color(argb: 0xFFFFC107))
        l.barMidFrom = barMidFrom
        l.glow = clampD(glow, 0, 1)
        l.smoothing = clampD(smoothing, 0, 1)
        l.showTicks = showTicks
        l.arcRoundCap = arcRoundCap
        l.trackColor = trackColor.map { Color(argb: $0) }
        l.arcTipDot = arcTipDot
        l.arcTipColor = col(arcTipColor, .white)
        l.ghostDigits = ghostDigits
        l.ghostAlpha = clampD(ghostAlpha, 0.03, 0.6)
        l.nameOffsetX = clampD(nameOffsetX, -0.6, 0.6)
        l.nameOffsetY = clampD(nameOffsetY, -0.6, 0.6)
        let labelDefault = col(labelColor, GaugeColors.subText)
        l.nameColor = col(nameColor, labelDefault)
        l.unitOffsetX = clampD(unitOffsetX, -0.6, 0.6)
        l.unitOffsetY = clampD(unitOffsetY, -0.6, 0.6)
        l.unitColor = col(unitColor, labelDefault)
        let cond = lampCondition.trimmingCharacters(in: .whitespaces)
        l.lampCondition = cond.isEmpty ? nil : (try? Condition.compile(cond))
        l.lampOnColor = col(lampOnColor, GaugeColors.warn)
        l.lampOffColor = col(lampOffColor, Color(argb: 0xFF2A2F36))
        l.chartSpanMs = Int64(Swift.min(Swift.max(chartSpanSec, 60), 31 * 86_400)) * 1000
        l.chartIntervalMs = recordOnChange ? 1_000 : Int64(clampD(recordIntervalSec, 1, 600) * 1000)
        l.chartSkipGaps = chartSkipGaps
        l.chartStep = recordOnChange
        l.legendPosition = legendPosition
        l.legendAlign = legendAlign
        l.legendScale = clampD(legendScale, 0.4, 3)
        l.monitorWindow = Monitor.windowIndex(monitorWindowMs)
        l.legendBgAlpha = clampD(legendBgAlpha, 0, 1)
        l.tableMaxRows = Swift.min(Swift.max(tableMaxRows, 1), 30)
        l.tableValueBg = tableValueBg.map { Color(argb: $0) }
        l.tableValueImage = tableValueImage
        l.tableNameRatio = clampD(tableNameRatio, 0, 0.7)
        l.tableUnitRatio = clampD(tableUnitRatio, 0, 0.5)
        l.tableUnitInline = tableUnitInline
        l.tableNameInline = tableNameInline
        l.tableNameSize = clampD(tableNameSize, 0.3, 3)
        l.tableUnitSize = clampD(tableUnitSize, 0.3, 3)
        l.tableMarginBottom = clampD(tableMarginBottom, 0, 0.6)
        l.tableMarginRight = clampD(tableMarginRight, 0, 0.6)
        l.tableRowGap = clampD(tableRowGap, -60, 80)
        l.tableColGap = clampD(tableColGap, -60, 120)
        l.chartColors = chartColors.map { c in c.map { Color(argb: $0) } }
        l.showPeak = showPeak
        let peakC = col(peakColor, GaugeColors.peak)
        l.peakColor = peakC
        l.showPeakValue = showPeakValue
        l.peakTextColor = col(peakTextColor, peakC)
        l.peakTextSize = clampD(peakTextSize, 0.3, 4)
        l.peakTextX = clampD(peakTextX, -1, 1)
        l.peakTextY = clampD(peakTextY, -1, 1)
        l.showValue = showValue
        // デジタル表示はメーター色を数値の色にする (以前からの動作)
        l.valueColor = col(valueColor, (style == .DIGITAL && color != nil) ? accentC : GaugeColors.text)
        l.valuePosition = clampD(valuePosition, -0.9, 0.9)
        l.valueSize = clampD(valueSize, 0.3, 3)
        l.showName = showName
        l.showUnit = showUnit
        l.image = backgroundImage
        l.imageScale = clampD(imageScale, 0.3, 2)
        l.valueFontName = fontName(valueFont)
        l.labelFontName = fontName(labelFont)
        l.showCard = showCard
        return l
    }
}

// MARK: - メーターの計算

/// 表示値を更新する間隔 (なめらかさに応じて 60〜320ms。0.5 で 200ms)
func displayIntervalMs(_ smoothing: Double) -> Int { Int(60 + 280 * clampD(smoothing, 0, 1)) }

/// 表示値をならす割合 (指数移動平均の係数)
func smoothingAlpha(_ smoothing: Double) -> Double { clampD(1.0 - smoothing * 0.85, 0.15, 1.0) }

func isWarn(_ def: PidDef, _ v: Double?) -> Bool {
    guard let v = v else { return false }
    if let a = def.warnAbove, v >= a { return true }
    if let b = def.warnBelow, v <= b { return true }
    return false
}

func fraction(_ def: PidDef, _ v: Double) -> Double {
    let r = def.max - def.min
    if r <= 0 { return 0 }
    return clampD((v - def.min) / r, 0, 1)
}

/// 消えている 7 セグ表示の文字列
func ghostText(_ def: PidDef) -> String { def.digitTemplate().replacingOccurrences(of: "0", with: "8") }

/// 範囲から見やすい目盛り間隔を決める。1000 以上は ×1000 表記
struct TickScale {
    let first: Double
    let step: Double
    let divisor: Double

    var unitSuffix: String { divisor > 1 ? " ×1000" : "" }

    func label(_ v: Double) -> String {
        let x = v / divisor
        if Swift.abs(x - x.rounded()) < 1e-6 { return String(Int64(x.rounded())) }
        return String(format: "%.1f", x)
    }

    func values(_ max: Double) -> [Double] {
        var out: [Double] = []
        var t = first
        if step <= 0 { return [first] }
        while t <= max + step * 0.001 && out.count < 100 { out.append(t); t += step }
        return out
    }

    static func of(_ min: Double, _ max: Double, _ divisions: Int? = nil) -> TickScale {
        let range = max - min
        if let n = divisions, n > 0 {
            let step = range / Double(n)
            let divisor: Double = (Swift.max(Swift.abs(min), Swift.abs(max)) >= 1000 && step >= 500) ? 1000 : 1
            return TickScale(first: min, step: step, divisor: divisor)
        }
        let raw = range / 8
        if raw <= 0 { return TickScale(first: min, step: 1, divisor: 1) }
        let mag = pow(10, floor(log10(raw)))
        let step = [1.0, 2.0, 2.5, 5.0, 10.0].map { $0 * mag }.first { $0 >= raw } ?? (10 * mag)
        let first = (min / step).rounded(.up) * step
        let divisor: Double = (Swift.max(Swift.abs(min), Swift.abs(max)) >= 1000 && step >= 500) ? 1000 : 1
        return TickScale(first: first, step: step, divisor: divisor)
    }
}

func fmtNumber(_ v: Double) -> String {
    v == v.rounded(.down) && Swift.abs(v) < 1e15 ? String(Int64(v)) : String(v)
}

/// 項目の既定の表示形式
func defaultStyleFor(_ def: PidDef) -> GaugeStyle {
    switch def.key {
    case "RPM", "SPEED", "LOAD", "THROTTLE", "PEDAL", "BOOST", "TIMING": return .ANALOG
    case "STFT1", "STFT2", "LTFT1", "LTFT2", "FUEL_LEVEL", "COOLANT", "OIL_TEMP": return .BAR
    default: return .DIGITAL
    }
}

/// この車両では読めない項目か
func isUnsupported(_ def: PidDef, _ supported: Set<Int>?) -> Bool {
    guard let s = supported else { return false }
    switch def.kind {
    case .mode01: return !s.contains(def.pid)
    case .derived: return def.deps.compactMap { Pids.get($0) }.contains { isUnsupported($0, s) }
    default: return false
    }
}
