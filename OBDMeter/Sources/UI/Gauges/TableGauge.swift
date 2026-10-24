import SwiftUI
import UIKit

/// 値テーブル: 「項目名 (右寄せ)・値・単位 (左寄せ)」の行を縦に並べる。行数が最大を超えたら右に段を増やす
struct TableGaugeView: View {
    let series: [ChartSeries]
    let look: GaugeLook

    var body: some View {
        GeometryReader { geo in
            let n = Swift.max(series.count, 1)
            let rows = Swift.min(Swift.max(look.tableMaxRows, 1), n)
            let cols = (n + rows - 1) / rows
            let W = Double(geo.size.width), H = Double(geo.size.height)
            let rowGap = look.tableRowGap, colGap = look.tableColGap
            let colW = Swift.min(Swift.max((W - colGap * Double(cols - 1)) / Double(cols), 1), Swift.max(W, 1))
            let rowH = Swift.min(Swift.max((H - rowGap * Double(rows - 1)) / Double(rows), 1), Swift.max(H, 1))
            ZStack(alignment: .topLeading) {
                ForEach(0..<(cols * rows), id: \.self) { i in
                    let c = i / rows, r = i % rows
                    if i < series.count {
                        TableCell(s: series[i], look: look, colW: colW, rowH: rowH)
                            .frame(width: CGFloat(colW), height: CGFloat(rowH))
                            .offset(x: CGFloat((colW + colGap) * Double(c)), y: CGFloat((rowH + rowGap) * Double(r)))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

private struct TableCell: View {
    let s: ChartSeries
    let look: GaugeLook
    let colW: Double
    let rowH: Double

    var body: some View {
        let base = rowH * (1 - look.tableMarginBottom) * 0.42
        let inlineName = look.showName && look.tableNameInline
        let nameW = (look.showName && !inlineName) ? look.tableNameRatio : 0
        let nameSize = base * 0.8 * look.labelSize * look.tableNameSize
        let unitSize = base * 0.7 * look.labelSize * look.tableUnitSize
        let inlineUnit = look.showUnit && look.tableUnitInline
        let unitW = (look.showUnit && !inlineUnit) ? look.tableUnitRatio : 0
        let valueW = Swift.max(1 - nameW - unitW, 0.15)
        let total = nameW + valueW + unitW
        let innerW = Swift.max(colW - 4 - colW * look.tableMarginRight, 1)
        let vColor = isWarn(s.def, s.value) ? GaugeColors.warn : look.valueColor
        let vSize = base * look.valueSize
        HStack(spacing: 0) {
            if nameW > 0 {
                Text(s.def.shortName)
                    .font(look.labelFont(nameSize))
                    .foregroundColor(look.nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, 4)
                    .frame(width: CGFloat(innerW * nameW / total), alignment: .trailing)
            }
            ZStack {
                if let bg = look.tableValueBg { RoundedRectangle(cornerRadius: 4).fill(bg) }
                if let name = look.tableValueImage, let img = GaugeImages.load(name) {
                    Image(uiImage: img).resizable()
                }
                if look.tableValueBg != nil || look.tableValueImage != nil {
                    Canvas { ctx, size in
                        let rect = CGRect(origin: .zero, size: size)
                        ctx.drawPanel(Path(roundedRect: rect, cornerRadius: 4), rect, look.panelStyle, look.panelDepth, look.panelGloss)
                    }
                    .allowsHitTesting(false)
                }
                if inlineName {
                    Text(s.def.shortName)
                        .font(look.labelFont(nameSize))
                        .foregroundColor(look.nameColor)
                        .lineLimit(1)
                        .padding(.leading, 4)
                        .padding(.top, 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if look.showValue || inlineUnit {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        if look.showValue {
                            ZStack(alignment: .trailing) {
                                if look.ghostDigits {
                                    Text(ghostText(s.def)).font(look.valueFont(vSize)).foregroundColor(look.valueColor.opacity(look.ghostAlpha))
                                        .lineLimit(1)
                                }
                                Text(s.def.format(s.value)).font(look.valueFont(vSize)).foregroundColor(vColor)
                                    .lineLimit(1)
                                    .shadow(color: look.glow > 0 ? vColor.opacity(0.9) : .clear, radius: CGFloat(look.glow > 0 ? vSize * 0.06 * look.glow + 1 : 0))
                            }
                        }
                        if inlineUnit && !s.def.unitText.isEmpty {
                            Text(" " + s.def.unitText).font(look.labelFont(unitSize)).foregroundColor(look.unitColor).lineLimit(1)
                        }
                    }
                    .minimumScaleFactor(0.3)
                    .padding(.horizontal, 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: CGFloat(innerW * valueW / total))
            if unitW > 0 {
                Text(s.def.unitText)
                    .font(look.labelFont(unitSize))
                    .foregroundColor(look.unitColor)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .frame(width: CGFloat(innerW * unitW / total), alignment: .leading)
            }
        }
        .frame(height: CGFloat(Swift.max(rowH * (1 - look.tableMarginBottom), 1)))
        .padding(.leading, 2)
        .padding(.trailing, CGFloat(2 + colW * look.tableMarginRight))
        .frame(width: CGFloat(colW), height: CGFloat(rowH), alignment: .topLeading)
    }
}

/// 折り返して並べるレイアウト (凡例用)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 2
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = Swift.max(lineH, s.height)
            widest = Swift.max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var lines: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > bounds.width { lines.append([]); x = 0 }
            lines[lines.count - 1].append((v, s))
            x += s.width + spacing
        }
        var y = bounds.minY
        for line in lines {
            let lineW = line.reduce(CGFloat(0)) { $0 + $1.1.width } + spacing * CGFloat(Swift.max(line.count - 1, 0))
            let lineH = line.map { $0.1.height }.max() ?? 0
            var lx: CGFloat
            switch alignment {
            case .center: lx = bounds.minX + (bounds.width - lineW) / 2
            case .trailing: lx = bounds.maxX - lineW
            default: lx = bounds.minX
            }
            for (v, s) in line {
                v.place(at: CGPoint(x: lx, y: y + (lineH - s.height) / 2), proposal: ProposedViewSize(s))
                lx += s.width + spacing
            }
            y += lineH + lineSpacing
        }
    }
}
