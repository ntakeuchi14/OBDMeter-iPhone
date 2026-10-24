import SwiftUI
import UIKit

/// 角度 (度、3 時 = 0°、時計回り) の点
func polar(_ c: CGPoint, _ r: Double, _ deg: Double) -> CGPoint {
    let a = deg * Double.pi / 180
    return CGPoint(x: c.x + CGFloat(r * cos(a)), y: c.y + CGFloat(r * sin(a)))
}

/// 中心 [c]・半径 [r] の円弧 (開始角度 [start] から [sweep] 度。負なら反時計回り)
func arcPath(_ c: CGPoint, _ r: Double, _ start: Double, _ sweep: Double) -> Path {
    var p = Path()
    let n = Swift.max(2, Int(Swift.abs(sweep) / 2) + 1)
    for i in 0...n {
        let pt = polar(c, r, start + sweep * Double(i) / Double(n))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

func circlePath(_ c: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - CGFloat(r), y: c.y - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2)))
}

extension GraphicsContext {
    /// 文字を [center] を中心に描く
    func drawCentered(_ text: Text, _ center: CGPoint) {
        draw(text, at: center, anchor: .center)
    }

    /// 文字の大きさ
    func measure(_ text: Text) -> CGSize {
        resolve(text).measure(in: CGSize(width: 10_000, height: 10_000))
    }

    /// 発光 (にじみ) を付けて文字を描く
    func drawGlow(_ text: Text, at p: CGPoint, anchor: UnitPoint, color: Color, glow: Double, size: Double) {
        if glow > 0 {
            var c = self
            c.addFilter(.shadow(color: color.opacity(0.9), radius: CGFloat(size * 0.12 * glow + 2) / 2))
            c.draw(text, at: p, anchor: anchor)
        } else {
            draw(text, at: p, anchor: anchor)
        }
    }

    /// ぼかした影 ([path] を (dx, dy) ずらして、[blur] でぼかす)
    func softShadow(_ path: Path, _ dx: Double, _ dy: Double, _ blur: Double, _ alpha: Double) {
        if alpha <= 0 { return }
        var c = self
        if blur > 0.5 { c.addFilter(.blur(radius: CGFloat(blur / 2))) }
        c.translateBy(x: CGFloat(dx), y: CGFloat(dy))
        c.fill(path, with: .color(Color.black.opacity(Swift.min(Swift.max(alpha, 0), 1))))
    }

    /// 画像を縦横比を保ったまま、[center] を中心に一辺 [box] の正方形に収めて描く
    func drawImageFit(_ image: UIImage, _ center: CGPoint, _ box: Double) {
        let iw = Double(image.size.width), ih = Double(image.size.height)
        if iw <= 0 || ih <= 0 { return }
        let k = Swift.min(box / iw, box / ih)
        let w = iw * k, h = ih * k
        draw(Image(uiImage: image), in: CGRect(x: center.x - CGFloat(w / 2), y: center.y - CGFloat(h / 2), width: CGFloat(w), height: CGFloat(h)))
    }

    /// 背景の立体感 ([path] の形、[b] はその外接矩形)
    func drawPanel(_ path: Path, _ b: CGRect, _ style: PanelStyle, _ depth: Double, _ gloss: Bool) {
        if style == .FLAT && !gloss { return }
        if b.width <= 0 || b.height <= 0 { return }
        let k = Swift.min(Swift.max(depth, 0), 1)
        let m = Double(Swift.min(b.width, b.height))
        var c = self
        c.clip(to: path)
        switch style {
        case .INSET:
            let sh = CGFloat(Swift.max(m * 0.16 * (0.4 + k), 2))
            c.fill(Path(CGRect(x: b.minX, y: b.minY, width: b.width, height: sh)),
                   with: .linearGradient(Gradient(colors: [Color.black.opacity(0.55 * k), Color.black.opacity(0.18 * k), .clear]),
                                         startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.minX, y: b.minY + sh)))
            let sw = sh * 0.45
            c.fill(Path(CGRect(x: b.minX, y: b.minY, width: sw, height: b.height)),
                   with: .linearGradient(Gradient(colors: [Color.black.opacity(0.30 * k), .clear]),
                                         startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.minX + sw, y: b.minY)))
            let bh = sh * 0.3
            c.fill(Path(CGRect(x: b.minX, y: b.maxY - bh, width: b.width, height: bh)),
                   with: .linearGradient(Gradient(colors: [.clear, Color.black.opacity(0.12 * k)]),
                                         startPoint: CGPoint(x: b.minX, y: b.maxY - bh), endPoint: CGPoint(x: b.minX, y: b.maxY)))
            c.stroke(path, with: .color(Color.black.opacity(0.45 * k)), lineWidth: CGFloat(Swift.max(1.5, m * 0.02)))
        case .RAISED:
            let sh = CGFloat(Swift.max(m * 0.12 * (0.4 + k), 2))
            c.fill(Path(CGRect(x: b.minX, y: b.minY, width: b.width, height: sh)),
                   with: .linearGradient(Gradient(colors: [Color.white.opacity(0.30 * k), .clear]),
                                         startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.minX, y: b.minY + sh)))
            c.fill(Path(CGRect(x: b.minX, y: b.maxY - sh, width: b.width, height: sh)),
                   with: .linearGradient(Gradient(colors: [.clear, Color.black.opacity(0.35 * k)]),
                                         startPoint: CGPoint(x: b.minX, y: b.maxY - sh), endPoint: CGPoint(x: b.minX, y: b.maxY)))
        case .FLAT:
            break
        }
        if gloss {
            let h = b.height * 0.5
            c.fill(Path(CGRect(x: b.minX, y: b.minY, width: b.width, height: h)),
                   with: .linearGradient(Gradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04), .clear]),
                                         startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.minX, y: b.minY + h)))
        }
        if style == .INSET {
            var line = Path()
            line.move(to: CGPoint(x: b.minX + CGFloat(m * 0.04), y: b.maxY + 1))
            line.addLine(to: CGPoint(x: b.maxX - CGFloat(m * 0.04), y: b.maxY + 1))
            stroke(line, with: .color(Color.white.opacity(0.25 * k)), lineWidth: 1.2)
        }
    }

    /// バー・デジタル・ランプの背景色 (角丸の四角)
    func drawFace(_ look: GaugeLook, _ size: CGSize) {
        guard let c = look.faceColor else { return }
        let s = CGFloat(look.faceScale)
        let r = Swift.min(size.width, size.height) * 0.08 * s
        let sz = CGSize(width: size.width * s, height: size.height * s)
        let rect = CGRect(x: (size.width - sz.width) / 2, y: (size.height - sz.height) / 2, width: sz.width, height: sz.height)
        let path = Path(roundedRect: rect, cornerRadius: r)
        fill(path, with: .color(c))
        drawPanel(path, rect, look.panelStyle, look.panelDepth, look.panelGloss)
    }

    /// 外周リング (メタル・太線・細線)
    func drawRing(_ look: GaugeLook, _ center: CGPoint, _ outer: Double, _ w: Double) {
        let c = look.ringColor
        let depth = Swift.min(Swift.max(look.ringDepth, 0), 1)
        let top = CGPoint(x: center.x - CGFloat(outer * 0.25), y: center.y - CGFloat(outer))
        let bottom = CGPoint(x: center.x + CGFloat(outer * 0.25), y: center.y + CGFloat(outer))
        switch look.ring {
        case .NONE:
            return
        case .LINE:
            stroke(circlePath(center, outer - w / 2), with: .color(c), lineWidth: CGFloat(w))
            return
        case .BOLD:
            stroke(circlePath(center, outer - w / 2), with: .color(c), lineWidth: CGFloat(w))
            if depth > 0 {
                stroke(circlePath(center, outer - w / 2),
                       with: .linearGradient(Gradient(colors: [Color.white.opacity(0.45 * depth), .clear, Color.black.opacity(0.55 * depth)]),
                                             startPoint: top, endPoint: bottom), lineWidth: CGFloat(w))
            }
        case .METAL:
            let innerW = w * Swift.min(Swift.max(look.ringInner, 0), 0.8)
            let outerW = w - innerW
            stroke(circlePath(center, outer - outerW / 2),
                   with: .linearGradient(Gradient(colors: [c.lerp(.white, 0.85 * depth), c.lerp(.white, 0.35 * depth), c,
                                                           c.lerp(.black, 0.25 * depth), c.lerp(.white, 0.25 * depth)]),
                                         startPoint: top, endPoint: bottom), lineWidth: CGFloat(outerW))
            stroke(circlePath(center, outer - outerW * 0.03), with: .color(Color.black.opacity(0.5 * depth)),
                   lineWidth: CGFloat(Swift.max(1, outerW * 0.06)))
            if innerW > 0 {
                let ci = c.lerp(.black, 0.45)
                stroke(circlePath(center, outer - outerW - innerW / 2),
                       with: .linearGradient(Gradient(colors: [ci.lerp(.black, 0.5 * depth), ci, ci.lerp(.white, 0.35 * depth)]),
                                             startPoint: top, endPoint: bottom), lineWidth: CGFloat(innerW))
                stroke(circlePath(center, outer - outerW), with: .color(Color.black.opacity(0.45 * depth)),
                       lineWidth: CGFloat(Swift.max(1, w * 0.025)))
            }
        }
        if depth <= 0 { return }
        // 文字盤への落ち影 (リングの内側をうっすら暗く)
        let inner = outer - w
        if inner > 0 {
            fill(circlePath(center, inner),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .clear, location: 0.88),
                    .init(color: Color.black.opacity(0.55 * depth), location: 1),
                 ]), center: center, startRadius: 0, endRadius: CGFloat(inner)))
        }
    }
}

/// 外周リングの幅 (メーターの直径 [d] に対して)
func ringWidthFor(_ look: GaugeLook, _ d: Double) -> Double {
    let base: Double
    switch look.ring {
    case .NONE: base = 0
    case .LINE: base = d * 0.012
    case .BOLD: base = d * 0.035
    case .METAL: base = d * 0.05
    }
    return base * look.ringThickness
}
