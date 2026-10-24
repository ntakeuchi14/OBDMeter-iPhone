import SwiftUI
import UIKit

/// バーメーター
func drawBarGauge(_ ctx: GraphicsContext, _ size: CGSize, def: PidDef, value: Double?, f: Double, unsupported: Bool,
                  look: GaugeLook, image: UIImage?, peak: Double?) {
    let w = Double(size.width), h = Double(size.height)
    if w <= 2 || h <= 2 { return }
    let warn = isWarn(def, value)
    ctx.drawFace(look, size)
    if let img = image {
        ctx.drawImageFit(img, CGPoint(x: w / 2 + w * look.imageOffsetX, y: h / 2 + h * look.imageOffsetY), Swift.max(w, h) * look.imageScale)
    }
    let unit = Swift.min(h, w * 0.5)
    if look.showName {
        ctx.draw(Text(def.shortName).font(look.labelFont(unit * 0.16 * look.tableNameSize, weight: .medium)).foregroundColor(look.nameColor),
                 at: CGPoint(x: 4 + w * look.nameOffsetX, y: h * look.nameOffsetY), anchor: .topLeading)
    }
    if look.showValue {
        let vColor = warn ? GaugeColors.warn : look.valueColor
        let vSize = unit * (unsupported ? 0.2 : 0.34) * look.valueSize
        let valueText = Text(unsupported ? "非対応" : def.format(value)).font(look.valueFont(vSize)).foregroundColor(vColor)
        let unitText = Text(look.showUnit ? def.unitText : "").font(look.labelFont(unit * 0.14 * look.tableUnitSize)).foregroundColor(look.unitColor)
        let vs = ctx.measure(valueText)
        let us = ctx.measure(unitText)
        let valueY = h * (0.52 + (look.valuePosition - 0.42) * 0.5) - Double(vs.height) / 2
        let dx = w * look.valueOffsetX * 0.5
        ctx.draw(unitText, at: CGPoint(x: w - Double(us.width) - 4 + dx + w * look.unitOffsetX,
                                       y: valueY + Double(vs.height) - Double(us.height) * 1.15 + h * look.unitOffsetY), anchor: .topLeading)
        let valueRight = w - Double(us.width) - 10 + dx
        if look.ghostDigits && !unsupported {
            let ghost = Text(ghostText(def)).font(look.valueFont(vSize)).foregroundColor(look.valueColor.opacity(look.ghostAlpha))
            ctx.draw(ghost, at: CGPoint(x: valueRight, y: valueY), anchor: .topTrailing)
        }
        ctx.drawGlow(valueText, at: CGPoint(x: valueRight, y: valueY), anchor: .topTrailing, color: vColor, glow: look.glow, size: vSize)
    }
    drawBar(ctx, size, def: def, value: value, f: f, warn: warn, look: look, peak: peak, unit: unit)
}

/// バー本体。直線 (角度付き) か弧、実線か破線 (マス)、先細り、範囲ごとの色分け、発光に対応する
private func drawBar(_ ctx: GraphicsContext, _ size: CGSize, def: PidDef, value: Double?, f: Double, warn: Bool,
                     look: GaugeLook, peak: Double?, unit: Double) {
    let w = Double(size.width), h = Double(size.height)
    let barHidden = !look.showValueArc || look.arcWidth <= 0
    let arc = look.barArc
    let baseThick: Double = look.arcWidth <= 0 ? 0 :
        (arc ? Swift.max(Swift.min(w, h) * 0.14 * look.arcWidth, 4) : Swift.max(h * 0.12 * look.arcWidth, 4))
    let zoneH = barHidden ? Swift.max(h * 0.04, 3) : baseThick
    let thick = Swift.max(baseThick, zoneH)
    let taper = Swift.min(Swift.max(look.barTaper, 0), 1)
    func th(_ p: Double) -> Double { baseThick * (1 - taper * (1 - p)) }
    let segs = look.barSegments
    let gapFrac = segs > 0 ? look.barSegmentGap / Double(segs) : 0

    // ---- 形ごとの帯 ----
    var pointAt: (Double, Double) -> CGPoint
    var bandPath: (Double, Double, Double?) -> Path
    var lineLen = w
    if !arc {
        let angle = look.barAngle
        let rad = angle * Double.pi / 180
        let pivot = angle == 0 ? CGPoint(x: w / 2, y: h - thick / 2 - h * 0.08) : CGPoint(x: w / 2, y: h / 2)
        if angle != 0 {
            let c = Swift.abs(cos(rad)), sn = Swift.abs(sin(rad))
            let byW = c > 1e-3 ? (w - thick * sn) / c : Double.greatestFiniteMagnitude
            let byH = sn > 1e-3 ? (h - thick * c) / sn : Double.greatestFiniteMagnitude
            lineLen = Swift.max(Swift.min(byW, byH) * 0.94, 4)
        }
        let len = lineLen
        let ux = cos(rad), uy = sin(rad)
        let nx = -uy, ny = ux
        let ox = Double(pivot.x) - ux * len / 2 + nx * thick / 2
        let oy = Double(pivot.y) - uy * len / 2 + ny * thick / 2
        pointAt = { p, d in CGPoint(x: ox + ux * len * p - nx * d, y: oy + uy * len * p - ny * d) }
        let pa = pointAt
        bandPath = { p0, p1, fixed in
            var path = Path()
            let t0 = fixed ?? th(p0), t1 = fixed ?? th(p1)
            let off0 = (thick - (fixed ?? baseThick)) / 2
            let o0 = (taper > 0 && fixed == nil) ? 0 : off0
            path.move(to: pa(p0, o0))
            path.addLine(to: pa(p1, o0))
            path.addLine(to: pa(p1, o0 + t1))
            path.addLine(to: pa(p0, o0 + t0))
            path.closeSubpath()
            return path
        }
    } else {
        // 弧: 開始〜終了角度の範囲が枠いっぱいに収まる中心と半径を求める
        let start = look.startAngle
        let sweep = look.sweep
        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for k in 0...90 {
            let a = (start + sweep * Double(k) / 90) * Double.pi / 180
            let x = cos(a), y = sin(a)
            minX = Swift.min(minX, x); maxX = Swift.max(maxX, x); minY = Swift.min(minY, y); maxY = Swift.max(maxY, y)
        }
        let bw = Swift.max(maxX - minX, 0.2)
        let bh = Swift.max(maxY - minY, 0.2)
        let margin = thick * 0.6 + 2
        let r = Swift.max(Swift.min((w - margin * 2) / bw, (h - margin * 2) / bh), 8)
        let cx = w / 2 - (minX + maxX) / 2 * r
        let cy = h / 2 - (minY + maxY) / 2 * r
        let rIn = r - thick / 2
        pointAt = { p, d in
            let a = (start + sweep * p) * Double.pi / 180
            return CGPoint(x: cx + cos(a) * (rIn + d), y: cy + sin(a) * (rIn + d))
        }
        let pa = pointAt
        bandPath = { p0, p1, fixed in
            var path = Path()
            let n = Swift.max(2, Int((p1 - p0) * Swift.abs(sweep) / 3) + 1)
            let o0 = (taper > 0 && fixed == nil) ? 0 : (thick - (fixed ?? baseThick)) / 2
            for i in 0...n {
                let p = p0 + (p1 - p0) * Double(i) / Double(n)
                let pt = pa(p, o0)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            for i in stride(from: n, through: 0, by: -1) {
                let p = p0 + (p1 - p0) * Double(i) / Double(n)
                path.addLine(to: pa(p, o0 + (fixed ?? th(p))))
            }
            path.closeSubpath()
            return path
        }
    }

    // ---- 色 ----
    let litBase = (warn && !look.barZoneColors) ? GaugeColors.warn : look.accent
    func zoneColor(_ p: Double) -> Color {
        if !look.barZoneColors { return litBase }
        let v = def.min + (def.max - def.min) * p
        if let z = look.redZone, v >= z.lowerBound, v <= z.upperBound { return look.redZoneColor }
        if let m = look.barMidFrom, v >= m { return look.barMidColor }
        return look.accent
    }
    func offColor(_ p: Double) -> Color {
        if let c = look.barOffColor { return c }
        return (look.barZoneColors || look.glow > 0) ? zoneColor(p).opacity(0.13) : GaugeColors.track
    }
    func lit(_ path: Path, _ color: Color) {
        if look.glow > 0 {
            let gw = baseThick * 0.5 * look.glow + 2
            ctx.stroke(path, with: .color(color.opacity(0.18 * look.glow)), style: StrokeStyle(lineWidth: CGFloat(gw * 2), lineJoin: .round))
            ctx.stroke(path, with: .color(color.opacity(0.30 * look.glow)), style: StrokeStyle(lineWidth: CGFloat(gw), lineJoin: .round))
        }
        ctx.fill(path, with: .color(color))
    }
    /// [lo, hi] を塗る (破線ならマスごと)
    func fillRange(_ lo0: Double, _ hi0: Double, _ colorAt: (Double) -> Color, _ glowOn: Bool, _ fixed: Double? = nil) {
        let lo = Swift.min(lo0, hi0), hi = Swift.max(lo0, hi0)
        if segs > 0 {
            for i in 0..<segs {
                let mid = (Double(i) + 0.5) / Double(segs)
                if mid < lo || mid > hi { continue }
                let path = bandPath(Double(i) / Double(segs) + gapFrac / 2, Double(i + 1) / Double(segs) - gapFrac / 2, fixed)
                if glowOn { lit(path, colorAt(mid)) } else { ctx.fill(path, with: .color(colorAt(mid))) }
            }
        } else if hi > lo {
            var cuts = [lo, hi]
            if look.barZoneColors {
                if let m = look.barMidFrom { cuts.append(fraction(def, m)) }
                if let z = look.redZone { cuts.append(fraction(def, z.lowerBound)); cuts.append(fraction(def, z.upperBound)) }
            }
            let pts = Array(Set(cuts.filter { $0 >= lo && $0 <= hi })).sorted()
            if pts.count >= 2 {
                for j in 0..<(pts.count - 1) {
                    if pts[j + 1] - pts[j] <= 1e-4 { continue }
                    let path = bandPath(pts[j], pts[j + 1], fixed)
                    let c = colorAt((pts[j] + pts[j + 1]) / 2)
                    if glowOn { lit(path, c) } else { ctx.fill(path, with: .color(c)) }
                }
            }
        }
    }

    let simpleLine = !arc && segs <= 0 && taper <= 0
    if simpleLine {
        let angle = look.barAngle
        let pivot = angle == 0 ? CGPoint(x: w / 2, y: h - thick / 2 - h * 0.08) : CGPoint(x: w / 2, y: h / 2)
        let len = lineLen
        let r = baseThick / 2
        var c = ctx
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: Angle(degrees: angle))
        c.translateBy(x: CGFloat(-len / 2), y: CGFloat(-thick / 2))
        let top = (thick - baseThick) / 2
        func rr(_ x: Double, _ y: Double, _ ww: Double, _ hh: Double, _ rad: Double) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: Swift.max(ww, 0), height: Swift.max(hh, 0)), cornerRadius: CGFloat(Swift.max(Swift.min(rad, ww / 2, hh / 2), 0)))
        }
        if look.showTrack && baseThick > 0 { c.fill(rr(0, top, len, baseThick, r), with: .color(look.barOffColor ?? GaugeColors.track)) }
        if let z = look.redZone, !look.barZoneColors {
            let s0 = fraction(def, z.lowerBound), e0 = fraction(def, z.upperBound)
            if e0 > s0 { c.fill(Path(CGRect(x: len * s0, y: (thick - zoneH) / 2, width: len * (e0 - s0), height: zoneH)), with: .color(look.redZoneColor)) }
        }
        if value != nil && !barHidden {
            if def.min < 0 && def.max > 0 {
                let zero = fraction(def, 0)
                let x0 = len * Swift.min(zero, f)
                c.fill(rr(x0, top, Swift.max(len * Swift.abs(f - zero), 3), baseThick, r), with: .color(litBase))
                var zl = Path()
                zl.move(to: CGPoint(x: len * zero, y: top - 4))
                zl.addLine(to: CGPoint(x: len * zero, y: top + baseThick + 4))
                c.stroke(zl, with: .color(look.tickColor), lineWidth: 2)
            } else if look.barZoneColors {
                // 色分けは帯ごと (下で描く)
            } else {
                if look.glow > 0 {
                    c.fill(rr(-4, top - 4, len * f + 8, baseThick + 8, baseThick / 2 + 4), with: .color(litBase.opacity(0.25 * look.glow)))
                }
                if f > 0 { c.fill(rr(0, top, len * f, baseThick, r), with: .color(litBase)) }
            }
        }
        if value != nil && !barHidden && look.barZoneColors && !(def.min < 0 && def.max > 0) { fillRange(0, f, zoneColor, true) }
    } else {
        if look.showTrack && baseThick > 0 { fillRange(0, 1, offColor, false) }
        if !look.barZoneColors, let z = look.redZone {
            let s0 = fraction(def, z.lowerBound), e0 = fraction(def, z.upperBound)
            if e0 > s0 {
                if barHidden { fillRange(s0, e0, { _ in look.redZoneColor }, false, zoneH) }
                else if segs <= 0 { fillRange(s0, e0, { _ in look.redZoneColor.opacity(0.55) }, false) }
                else { fillRange(s0, e0, { _ in look.redZoneColor.opacity(0.35) }, false) }
            }
        }
        if value != nil && !barHidden {
            if def.min < 0 && def.max > 0 {
                let zero = fraction(def, 0)
                fillRange(zero, f, zoneColor, true)
                var zl = Path()
                zl.move(to: pointAt(zero, -4))
                zl.addLine(to: pointAt(zero, thick + 4))
                ctx.stroke(zl, with: .color(look.tickColor), lineWidth: 2)
            } else {
                fillRange(0, f, zoneColor, true)
            }
        }
    }
    if let pk = peak {
        let pp = fraction(def, pk)
        let hh = Swift.max(th(pp), 2)
        let o = taper > 0 ? 0 : (thick - baseThick) / 2
        var pl = Path()
        pl.move(to: pointAt(pp, o - hh * 0.35))
        pl.addLine(to: pointAt(pp, o + hh * 1.35))
        ctx.stroke(pl, with: .color(look.peakColor), lineWidth: CGFloat(Swift.max(2, hh * 0.25)))
        if look.showPeakValue {
            ctx.draw(Text("MAX " + def.format(pk)).font(look.valueFont(unit * 0.12 * look.peakTextSize, bold: false)).foregroundColor(look.peakTextColor),
                     at: CGPoint(x: 4 + w * look.peakTextX, y: h * look.peakTextY), anchor: .topLeading)
        }
    }
}

/// デジタル (数値) 表示
func drawDigital(_ ctx: GraphicsContext, _ size: CGSize, def: PidDef, value: Double?, unsupported: Bool,
                 look: GaugeLook, image: UIImage?, peak: Double?) {
    let w = Double(size.width), h = Double(size.height)
    if w <= 2 || h <= 2 { return }
    let warn = isWarn(def, value)
    ctx.drawFace(look, size)
    if let img = image {
        ctx.drawImageFit(img, CGPoint(x: w * (0.5 + look.imageOffsetX), y: h * (0.5 + look.imageOffsetY)), Swift.max(w, h) * look.imageScale)
    }
    let unit = Swift.min(h, w * 0.6)
    if look.showName {
        ctx.draw(Text(def.shortName).font(look.labelFont(unit * 0.14 * look.tableNameSize, weight: .medium)).foregroundColor(look.nameColor),
                 at: CGPoint(x: 4 + w * look.nameOffsetX, y: h * look.nameOffsetY), anchor: .topLeading)
    }
    let cy = h * (0.5 + (look.valuePosition - 0.42) * 0.5)
    let cx = w * (0.5 + look.valueOffsetX * 0.5)
    if look.showValue {
        let vColor = warn ? GaugeColors.warn : look.valueColor
        var vSize = unit * (unsupported ? 0.2 : 0.38) * look.valueSize
        let text = unsupported ? "非対応" : def.format(value)
        let maxW = w * 0.96
        if look.ghostDigits && !unsupported {
            var ghost = Text(ghostText(def)).font(look.valueFont(vSize)).foregroundColor(look.valueColor.opacity(look.ghostAlpha))
            var gs = ctx.measure(ghost)
            if Double(gs.width) > maxW && maxW > 0 {
                vSize *= maxW / Double(gs.width)
                ghost = Text(ghostText(def)).font(look.valueFont(vSize)).foregroundColor(look.valueColor.opacity(look.ghostAlpha))
                gs = ctx.measure(ghost)
            }
            let gx = cx - Double(gs.width) / 2
            ctx.draw(ghost, at: CGPoint(x: gx, y: cy), anchor: .leading)
            ctx.drawGlow(Text(text).font(look.valueFont(vSize)).foregroundColor(vColor),
                         at: CGPoint(x: gx + Double(gs.width), y: cy), anchor: .trailing, color: vColor, glow: look.glow, size: vSize)
        } else {
            var t = Text(text).font(look.valueFont(vSize)).foregroundColor(vColor)
            let ts = ctx.measure(t)
            if Double(ts.width) > maxW && maxW > 0 {
                vSize *= maxW / Double(ts.width)
                t = Text(text).font(look.valueFont(vSize)).foregroundColor(vColor)
            }
            ctx.drawGlow(t, at: CGPoint(x: cx, y: cy), anchor: .center, color: vColor, glow: look.glow, size: vSize)
        }
    }
    if look.showUnit {
        ctx.drawCentered(Text(def.unitText).font(look.labelFont(unit * 0.13 * look.tableUnitSize)).foregroundColor(look.unitColor),
                         CGPoint(x: cx + w * look.unitOffsetX, y: cy + unit * 0.3 * Swift.max(look.valueSize, 0.6) + h * look.unitOffsetY))
    }
    if let pk = peak {
        ctx.draw(Text("MAX " + def.format(pk)).font(look.valueFont(unit * 0.12 * look.peakTextSize, bold: false)).foregroundColor(look.peakTextColor),
                 at: CGPoint(x: w - 4 + w * look.peakTextX, y: h * look.peakTextY), anchor: .topTrailing)
    }
}

/// 2 値ランプ。条件式を満たすと点灯する (条件が空なら警告値を超えたとき)
func drawLamp(_ ctx: GraphicsContext, _ size: CGSize, def: PidDef, value: Double?, unsupported: Bool,
              look: GaugeLook, image: UIImage?) {
    let w = Double(size.width), h = Double(size.height)
    if w <= 2 || h <= 2 { return }
    var on = false
    if !unsupported, let v = value {
        if let cond = look.lampCondition { on = cond.test(v) } else { on = isWarn(def, v) }
    }
    ctx.drawFace(look, size)
    if let img = image {
        ctx.drawImageFit(img, CGPoint(x: w * (0.5 + look.imageOffsetX), y: h * (0.5 + look.imageOffsetY)), Swift.max(w, h) * look.imageScale)
    }
    let nameH = look.showName ? h * 0.2 : 0
    let valueH = look.showValue ? h * 0.2 : 0
    let areaH = h - nameH - valueH
    let outer = Swift.min(w, areaH) * 0.4
    let ringW = ringWidthFor(look, outer * 2)
    let r = Swift.max(outer - ringW, 1)
    let c = CGPoint(x: w / 2, y: nameH + areaH / 2)
    let color = on ? look.lampOnColor : look.lampOffColor
    if on {
        ctx.fill(circlePath(c, r * 1.7), with: .radialGradient(Gradient(colors: [color.opacity(0.6), color.opacity(0)]),
                                                             center: c, startRadius: 0, endRadius: CGFloat(r * 1.7)))
    }
    let hl = CGPoint(x: c.x - CGFloat(r * 0.35), y: c.y - CGFloat(r * 0.35))
    ctx.fill(circlePath(c, r), with: .radialGradient(Gradient(colors: [color.lerp(.white, on ? 0.6 : 0.2), color, color.lerp(.black, 0.4)]),
                                                     center: hl, startRadius: 0, endRadius: CGFloat(r * 1.5)))
    ctx.stroke(circlePath(c, r), with: .color(Color.black.opacity(0.55)), lineWidth: CGFloat(Swift.max(1, r * 0.08)))
    if ringW > 0 { ctx.drawRing(look, c, outer, ringW) }
    let unit = Swift.min(w, h)
    if look.showName {
        ctx.drawCentered(Text(def.shortName).font(look.labelFont(unit * 0.11 * look.labelSize * look.tableNameSize, weight: .medium)).foregroundColor(look.nameColor),
                         CGPoint(x: w * (0.5 + look.nameOffsetX), y: nameH / 2 + h * look.nameOffsetY))
    }
    if look.showValue {
        let text = unsupported ? "非対応" : def.format(value) + (look.showUnit ? " " + def.unitText : "")
        ctx.drawCentered(Text(text).font(look.valueFont(unit * 0.11 * look.valueSize, bold: false)).foregroundColor(look.valueColor),
                         CGPoint(x: w / 2, y: h - valueH / 2))
    }
}
