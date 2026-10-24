import SwiftUI
import UIKit

/// メーターのどの部分を描くか (アナログの針だけ別の層にして、ほかのメーターより手前に出す)
enum GaugeLayer { case all, body, needle }

/// アナログ (針) メーター。[f] は針の位置 (0〜1、なめらかに動かしたもの)
func drawAnalog(_ ctx: GraphicsContext, _ size: CGSize, def: PidDef, value: Double?, f: Double, unsupported: Bool,
                look: GaugeLook, image: UIImage?, peak: Double?, layer: GaugeLayer) {
    let w = Double(size.width), h = Double(size.height)
    let d = Swift.min(w, h)
    if d <= 2 { return }
    let center = CGPoint(x: w / 2, y: h / 2)
    let outer = d / 2
    let warn = isWarn(def, value)

    let ringW = ringWidthFor(look, d)
    let gaugeR = (outer - ringW - d * 0.01) * look.tickRadius
    let rawStroke = d * 0.045 * look.arcWidth
    let arcHidden = !look.showValueArc || rawStroke <= 0
    let stroke = (arcHidden && !look.showTrack) ? 0 : rawStroke
    let arcR = gaugeR - stroke / 2
    let capInset: Double = (look.arcRoundCap && arcR > 0) ? Swift.min((stroke / 2 / arcR) * 180 / Double.pi, Swift.abs(look.sweep) / 4) : 0
    let dir: Double = look.sweep < 0 ? -1 : 1
    let start = look.startAngle + capInset * dir
    let sweep = look.sweep - capInset * 2 * dir
    let cap: CGLineCap = look.arcRoundCap ? .round : .butt
    let tickOuter = gaugeR - stroke - d * 0.008

    if layer != .needle {
        // 背景色で文字盤を塗り、その上に背景画像
        if let fc = look.faceColor {
            let fcC = image != nil ? CGPoint(x: center.x + CGFloat(d * look.imageOffsetX), y: center.y + CGFloat(d * look.imageOffsetY)) : center
            let fr = (outer - ringW / 2) * look.faceScale
            let path = circlePath(fcC, fr)
            ctx.fill(path, with: .color(fc))
            ctx.drawPanel(path, CGRect(x: fcC.x - CGFloat(fr), y: fcC.y - CGFloat(fr), width: CGFloat(fr * 2), height: CGFloat(fr * 2)),
                          look.panelStyle, look.panelDepth, look.panelGloss)
        }
        if let img = image {
            ctx.drawImageFit(img, CGPoint(x: center.x + CGFloat(d * look.imageOffsetX), y: center.y + CGFloat(d * look.imageOffsetY)), d * look.imageScale)
        }
        if ringW > 0 { ctx.drawRing(look, center, outer, ringW) }

        if look.showTrack && stroke > 0 {
            ctx.stroke(arcPath(center, arcR, start, sweep), with: .color(look.trackColor ?? GaugeColors.track),
                       style: StrokeStyle(lineWidth: CGFloat(stroke), lineCap: cap))
        }
        let majorLen = d * 0.05
        let minorLen = d * 0.025
        let zoneInsideW = d * 0.025
        if let z = look.redZone {
            let s = fraction(def, z.lowerBound)
            let e = fraction(def, z.upperBound)
            if e > s {
                if arcHidden {
                    let zr = tickOuter - zoneInsideW / 2
                    ctx.stroke(arcPath(center, zr, start + sweep * s, sweep * (e - s)), with: .color(look.redZoneColor),
                               style: StrokeStyle(lineWidth: CGFloat(zoneInsideW), lineCap: .butt))
                } else {
                    ctx.stroke(arcPath(center, arcR, start + sweep * s, sweep * (e - s)), with: .color(look.redZoneColor),
                               style: StrokeStyle(lineWidth: CGFloat(Swift.max(stroke, d * 0.02)), lineCap: .butt))
                }
            }
        }
        if value != nil && look.showValueArc && stroke > 0 {
            let arcColor = warn ? GaugeColors.warn : look.accent
            if f > 0.0005 {
                ctx.stroke(arcPath(center, arcR, start, sweep * f), with: .color(arcColor),
                           style: StrokeStyle(lineWidth: CGFloat(stroke), lineCap: cap))
            }
            if look.arcTipDot && peak == nil {
                ctx.fill(circlePath(polar(center, arcR, start + sweep * f), stroke * 0.32), with: .color(look.arcTipColor))
            }
        }

        // 目盛り (主・小) と数字
        let scale = TickScale.of(def.min, def.max, look.majorDivisions)
        let labelSize = d * 0.07 * look.labelSize
        let majors = scale.values(def.max)
        for (i, t) in majors.enumerated() {
            let a = start + sweep * fraction(def, t)
            if look.showTicks {
                var p = Path()
                p.move(to: polar(center, tickOuter - majorLen, a))
                p.addLine(to: polar(center, tickOuter, a))
                ctx.stroke(p, with: .color(look.tickColor), lineWidth: CGFloat(d * 0.012))
            }
            if look.showLabels {
                let labelR = tickOuter - majorLen - d * 0.06 * look.labelSize
                ctx.drawCentered(Text(scale.label(t)).font(look.labelFont(labelSize)).foregroundColor(look.labelColor),
                                 polar(center, labelR, a))
            }
            if look.showTicks && look.minorDivisions > 0 && i < majors.count - 1 {
                let next = majors[i + 1]
                for k in 1...look.minorDivisions {
                    let tv = t + (next - t) * Double(k) / Double(look.minorDivisions + 1)
                    let b = start + sweep * fraction(def, tv)
                    var p = Path()
                    p.move(to: polar(center, tickOuter - minorLen, b))
                    p.addLine(to: polar(center, tickOuter, b))
                    ctx.stroke(p, with: .color(look.tickColor), lineWidth: CGFloat(d * 0.006))
                }
            }
        }

        // ピーク値の印
        if let pk = peak {
            let pa = start + sweep * fraction(def, pk)
            if look.arcTipDot && stroke > 0 {
                ctx.fill(circlePath(polar(center, arcR, pa), stroke * 0.32), with: .color(look.peakColor))
            } else {
                let ca = cos(pa * Double.pi / 180), sa = sin(pa * Double.pi / 180)
                let tip = gaugeR - stroke - d * 0.01
                let base = gaugeR + d * 0.005
                let half = d * 0.022
                var path = Path()
                path.move(to: CGPoint(x: center.x + CGFloat(tip * ca), y: center.y + CGFloat(tip * sa)))
                path.addLine(to: CGPoint(x: center.x + CGFloat(base * ca - half * sa), y: center.y + CGFloat(base * sa + half * ca)))
                path.addLine(to: CGPoint(x: center.x + CGFloat(base * ca + half * sa), y: center.y + CGFloat(base * sa - half * ca)))
                path.closeSubpath()
                ctx.fill(path, with: .color(look.peakColor))
            }
        }

        // 名前・数値・単位
        if look.showName {
            ctx.drawCentered(Text(def.shortName).font(look.labelFont(d * 0.07 * look.tableNameSize, weight: .medium)).foregroundColor(look.nameColor),
                             CGPoint(x: center.x + CGFloat(d * look.nameOffsetX), y: center.y - CGFloat(gaugeR * 0.38) + CGFloat(d * look.nameOffsetY)))
        }
        let valueY = Double(center.y) + gaugeR * look.valuePosition
        let valueX = Double(center.x) + gaugeR * look.valueOffsetX
        if look.showValue {
            let valueText = unsupported ? "非対応" : def.format(value)
            let vColor = warn ? GaugeColors.warn : look.valueColor
            let vSize = d * (unsupported ? 0.09 : 0.13) * look.valueSize
            let txt = Text(valueText).font(look.valueFont(vSize)).foregroundColor(vColor)
            if look.ghostDigits && !unsupported {
                let ghost = Text(ghostText(def)).font(look.valueFont(vSize)).foregroundColor(look.valueColor.opacity(look.ghostAlpha))
                let gs = ctx.measure(ghost)
                let gx = valueX - Double(gs.width) / 2
                ctx.draw(ghost, at: CGPoint(x: gx, y: valueY), anchor: .leading)
                ctx.drawGlow(txt, at: CGPoint(x: gx + Double(gs.width), y: valueY), anchor: .trailing, color: vColor, glow: look.glow, size: vSize)
            } else {
                ctx.drawGlow(txt, at: CGPoint(x: valueX, y: valueY), anchor: .center, color: vColor, glow: look.glow, size: vSize)
            }
        }
        if look.showUnit {
            ctx.drawCentered(Text(def.unitText + scale.unitSuffix).font(look.labelFont(d * 0.055 * look.tableUnitSize)).foregroundColor(look.unitColor),
                             CGPoint(x: valueX + d * look.unitOffsetX, y: valueY + d * 0.1 * Swift.max(look.valueSize, 0.6) + d * look.unitOffsetY))
        }
        if let pk = peak, look.showPeakValue {
            ctx.drawCentered(Text("MAX " + def.format(pk)).font(look.valueFont(d * 0.05 * look.peakTextSize, bold: false)).foregroundColor(look.peakTextColor),
                             CGPoint(x: valueX + d * look.peakTextX, y: valueY + d * 0.17 * Swift.max(look.valueSize, 0.6) + d * look.peakTextY))
        }
    }

    // 針 (根元が太く先が細い形) と中心のノブ
    if layer != .body {
        if value != nil && look.showNeedle {
            let a = (start + sweep * f) * Double.pi / 180
            let ca = cos(a), sa = sin(a)
            let len = tickOuter * look.needleLength
            let tail = len * look.needleTail
            let baseW = d * 0.016 * look.needleWidth
            let tipW = baseW * 0.35
            let color = warn ? GaugeColors.warn : look.needleColor
            let cx = Double(center.x), cy = Double(center.y)
            var needle = Path()
            needle.move(to: CGPoint(x: cx - tail * ca - baseW * sa, y: cy - tail * sa + baseW * ca))
            needle.addLine(to: CGPoint(x: cx + len * ca - tipW * sa, y: cy + len * sa + tipW * ca))
            needle.addLine(to: CGPoint(x: cx + len * ca + tipW * sa, y: cy + len * sa - tipW * ca))
            needle.addLine(to: CGPoint(x: cx - tail * ca + baseW * sa, y: cy - tail * sa - baseW * ca))
            needle.closeSubpath()
            if look.needleShadow { ctx.softShadow(needle, d * 0.012, d * 0.02, d * 0.012, 0.45 * look.shadowStrength) }
            ctx.fill(needle, with: .color(color))
        }
        if look.showNeedle && look.knobSize > 0 {
            let kr = d * 0.035 * look.knobSize
            if look.needleShadow { ctx.softShadow(circlePath(center, kr), d * 0.01, d * 0.016, d * 0.012, 0.45 * look.shadowStrength) }
            let kc = look.knobColor ?? look.needleColor
            ctx.fill(circlePath(center, kr), with: .color(kc))
            ctx.fill(circlePath(center, kr),
                     with: .linearGradient(Gradient(colors: [Color.white.opacity(0.35), .clear, Color.black.opacity(0.35)]),
                                           startPoint: CGPoint(x: center.x - CGFloat(kr), y: center.y - CGFloat(kr)),
                                           endPoint: CGPoint(x: center.x + CGFloat(kr), y: center.y + CGFloat(kr))))
            ctx.fill(circlePath(center, kr * 0.4), with: .color(Color(argb: 0xFF20242B)))
        }
    }
}

/// メーター自体の影 (カードを出していればカードの形、なければ文字盤・背景色の形)
func drawObjectShadow(_ ctx: GraphicsContext, _ size: CGSize, _ style: GaugeStyle, _ look: GaugeLook, cardInset: Double) {
    let w = Double(size.width), h = Double(size.height)
    let m = Swift.min(w, h)
    var path = Path()
    if look.showCard {
        path = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
    } else {
        let pad = cardInset
        let inner = CGRect(x: pad, y: pad, width: w - pad * 2, height: h - pad * 2)
        switch style {
        case .ANALOG:
            if look.faceColor == nil && look.ring == .NONE && look.image == nil { return }
            let d = Double(Swift.min(inner.width, inner.height))
            let fr = (look.ring == .NONE && look.faceColor != nil) ? d / 2 * look.faceScale : d / 2
            path = circlePath(CGPoint(x: inner.midX, y: inner.midY), fr)
        case .BAR, .DIGITAL, .LAMP:
            if look.faceColor == nil { return }
            let sc = CGFloat(look.faceScale)
            let sz = CGSize(width: inner.width * sc, height: inner.height * sc)
            let r = Swift.min(inner.width, inner.height) * 0.08 * sc
            path = Path(roundedRect: CGRect(x: inner.midX - sz.width / 2, y: inner.midY - sz.height / 2, width: sz.width, height: sz.height), cornerRadius: r)
        default:
            return
        }
    }
    ctx.softShadow(path, m * 0.01, m * 0.035, m * 0.045, 0.55 * look.shadowStrength)
}
