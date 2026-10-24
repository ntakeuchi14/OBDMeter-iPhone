import SwiftUI
import UIKit
import PhotosUI

/// メーターの編集画面のタブ
enum EditorTab: String, CaseIterable {
    case ITEM, ITEM_AXIS, SCALE, BAR, LAMP, TABLE, VIEW, RECORD, LOOK, IMAGE, PLACE

    var label: String {
        switch self {
        case .ITEM: return "項目"
        case .ITEM_AXIS: return "項目・軸"
        case .SCALE: return "目盛り・針"
        case .BAR: return "バーの形"
        case .LAMP: return "点灯条件・色"
        case .TABLE: return "並べ方・文字"
        case .VIEW: return "表示"
        case .RECORD: return "記録"
        case .LOOK: return "色・数値"
        case .IMAGE: return "画像"
        case .PLACE: return "配置"
        }
    }
}

/// 表示形式ごとに、編集画面に出すタブと設定 (その形式の描画が使わない設定は出さない)
enum EditorTabs {
    static func forStyle(_ s: GaugeStyle) -> [EditorTab] {
        switch s {
        case .ANALOG: return [.ITEM, .SCALE, .LOOK, .IMAGE, .PLACE]
        case .BAR: return [.ITEM, .BAR, .LOOK, .IMAGE, .PLACE]
        case .DIGITAL: return [.ITEM, .LOOK, .IMAGE, .PLACE]
        case .LAMP: return [.ITEM, .LAMP, .PLACE]
        case .TABLE: return [.ITEM, .TABLE, .PLACE]
        case .CHART: return [.ITEM_AXIS, .VIEW, .RECORD, .PLACE]
        case .MONITOR: return [.ITEM, .VIEW, .PLACE]
        }
    }

    static func keepOrFirst(_ s: GaugeStyle, _ current: EditorTab) -> EditorTab {
        let tabs = forStyle(s)
        if tabs.contains(current) { return current }
        if current == .ITEM && tabs.contains(.ITEM_AXIS) { return .ITEM_AXIS }
        return tabs[0]
    }

    static func usesRange(_ s: GaugeStyle) -> Bool { s != .MONITOR }
    static func usesWarn(_ s: GaugeStyle) -> Bool { s != .CHART && s != .MONITOR }
    static func usesLabelField(_ s: GaugeStyle) -> Bool { s != .TABLE && s != .MONITOR }
    static func usesRing(_ s: GaugeStyle) -> Bool { s == .ANALOG || s == .LAMP }
    static func usesGhost(_ s: GaugeStyle) -> Bool { [.ANALOG, .BAR, .DIGITAL, .TABLE].contains(s) }
}

private enum PickerTarget: Identifiable {
    case main, fallback, chart
    var id: Int { self == .main ? 0 : (self == .fallback ? 1 : 2) }
}

private enum FontTarget: String, Identifiable {
    case value, label
    var id: String { rawValue }
}

/// メーター 1 個のデザイン編集 (全画面)。上 (横画面では左) にプレビュー、下に設定
struct GaugeEditorView: View {
    @Environment(AppModel.self) private var model
    let dashboardId: Int64
    let initial: GaugeConfig
    let onClose: () -> Void
    let onCreateCustomPid: () -> Void

    @State private var draft: GaugeConfig
    @State private var tab: EditorTab = .ITEM
    @State private var picker: PickerTarget? = nil
    @State private var fontPicker: FontTarget? = nil
    @State private var confirmDelete = false
    @State private var useLive = false
    @State private var previewFraction: Double = 0.65
    @State private var saveWork: DispatchWorkItem? = nil
    @State private var runtime = GaugeRuntime()

    init(dashboardId: Int64, initial: GaugeConfig, onClose: @escaping () -> Void, onCreateCustomPid: @escaping () -> Void) {
        self.dashboardId = dashboardId
        self.initial = initial
        self.onClose = onClose
        self.onCreateCustomPid = onCreateCustomPid
        _draft = State(initialValue: initial)
    }

    private func save() {
        saveWork?.cancel()
        model.replaceGauge(dashboardId, draft)
    }

    private func close() {
        save()
        onClose()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let d = draft
        let w = DispatchWorkItem { model.replaceGauge(dashboardId, d) }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    private func update(_ f: (inout GaugeDesign) -> Void) {
        f(&draft.design)
    }

    private func replace(_ g: GaugeConfig) { draft = g }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 18)) }
                        .padding(.horizontal, 8)
                    Text("メーターのデザイン").font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button("完了") { close() }.buttonStyle(.borderedProminent)
                }
                .padding(8)
                if wide {
                    HStack(spacing: 0) {
                        preview.frame(width: geo.size.width * 0.47)
                        settings
                    }
                } else {
                    preview.frame(height: geo.size.height * 0.36)
                    settings
                }
            }
        }
        .background(GaugeColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: draft) { _, _ in scheduleSave() }
        .sheet(item: $picker) { t in
            ItemPickerView(onPick: { picked in pick(t, picked); picker = nil },
                           onCreateCustom: { picker = nil; close(); onCreateCustomPid() })
                .environment(model)
        }
        .sheet(item: $fontPicker) { t in
            FontPickerView(title: t == .value ? "数値のフォント" : "文字のフォント",
                           selected: t == .value ? draft.design.valueFont : draft.design.labelFont) { id in
                if t == .value { draft.design.valueFont = id } else { draft.design.labelFont = id }
                fontPicker = nil
            }
            .environment(model)
        }
        .alert("このメーターを削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                saveWork?.cancel()
                model.removeGauge(dashboardId, draft.id)
                onClose()
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func pick(_ t: PickerTarget, _ picked: PidDef) {
        switch t {
        case .main:
            // 項目を変えたら、前の項目用の範囲・表示名・レッドゾーンなどはリセットする
            draft.pidKey = picked.key
            draft.design.label = nil
            draft.design.min = nil
            draft.design.max = nil
            draft.design.decimals = nil
            draft.design.useDefaultWarn = true
            draft.design.warnAbove = nil
            draft.design.warnBelow = nil
            draft.design.redZoneFrom = nil
            draft.design.redZoneTo = nil
            draft.design.majorDivisions = nil
        case .fallback:
            draft.fallbackKey = picked.key == draft.pidKey ? nil : picked.key
        case .chart:
            if !draft.chartAllKeys.contains(picked.key) { draft.chartKeys.append(picked.key) }
        }
    }

    // MARK: - プレビュー

    private var previewDef: PidDef? { draft.resolvedDef(model.catalog) }

    private var previewValue: Double? {
        guard let def = previewDef else { return nil }
        if useLive { return model.values[def.key] }
        return def.min + (def.max - def.min) * previewFraction
    }

    private var preview: some View {
        VStack(spacing: 6) {
            GeometryReader { box in
                if let def = previewDef {
                    let look = draft.look(def) { model.fontName($0) }
                    let multi = draft.style == .CHART || draft.style == .TABLE || draft.style == .MONITOR
                    let pv = previewValue
                    let live = useLive
                    let m = model
                    let key = def.key
                    // ダッシュボードで実際に表示する大きさで描いてから、枠に収まるように拡大縮小する
                    let cell = model.cellSize ?? CGSize(width: 9, height: 7)
                    let realW = Swift.max(Double(cell.width) * Double(draft.w) - 6, 10)
                    let realH = Swift.max(Double(cell.height) * Double(draft.h) - 6, 10)
                    let k = Swift.min(Double(box.size.width) / realW, Double(box.size.height) / realH)
                    let input = GaugeInput(def: def, style: draft.style, look: look, unsupported: false,
                                           series: multi ? chartSeries(draft, def, [def.key: pv ?? 0], model.catalog) : [],
                                           slot: HistorySlot.of(dashboardId, draft.id), interactive: false)
                    GaugeCardView(input: input, runtime: runtime,
                                  valueSource: { live ? m.values[key] : pv },
                                  sourceKey: "\(live)|\(pv ?? -1)")
                        .frame(width: CGFloat(realW), height: CGFloat(realH))
                        .scaleEffect(CGFloat(k))
                        .frame(width: box.size.width, height: box.size.height)
                } else {
                    Text("項目が見つかりません").foregroundColor(GaugeColors.subText)
                        .frame(width: box.size.width, height: box.size.height)
                }
            }
            HStack {
                Text("プレビュー値").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                Slider(value: Binding(get: { previewFraction }, set: { previewFraction = $0; useLive = false }))
                Toggle("実測値", isOn: $useLive).toggleStyle(.button).font(.system(size: 13))
            }
        }
        .padding(12)
    }

    // MARK: - 設定

    private var settings: some View {
        let tabs = EditorTabs.forStyle(draft.style)
        let current = EditorTabs.keepOrFirst(draft.style, tab)
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs, id: \.self) { t in
                        let sel = t == current
                        Text(t.label)
                            .font(.system(size: 14, weight: sel ? .bold : .regular))
                            .foregroundColor(sel ? GaugeColors.accent : GaugeColors.subText)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { if sel { Rectangle().fill(GaugeColors.accent).frame(height: 2) } }
                            .onTapGesture { tab = t }
                    }
                }
                .padding(.horizontal, 8)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    tabContent(current)
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder
    private func tabContent(_ t: EditorTab) -> some View {
        switch t {
        case .ITEM, .ITEM_AXIS: ItemTab(g: draft, update: update, replace: replace, pick: { picker = $0 }, reset: draft.pidKey)
        case .SCALE: ScaleTab(g: draft, update: update)
        case .BAR: BarTab(g: draft, def: previewDef, update: update)
        case .LAMP: LampTab(g: draft, update: update, pickFont: { fontPicker = $0 })
        case .TABLE: TableTab(g: draft, update: update, pickFont: { fontPicker = $0 })
        case .VIEW:
            if draft.style == .CHART { ChartViewTab(g: draft, update: update, pickFont: { fontPicker = $0 }) }
            else { MonitorViewTab(g: draft, update: update, pickFont: { fontPicker = $0 }) }
        case .RECORD: ChartRecordTab(g: draft, update: update)
        case .LOOK: LookTab(g: draft, update: update, pickFont: { fontPicker = $0 })
        case .IMAGE: ImageTab(g: draft, update: update)
        case .PLACE:
            PlaceTab(g: draft, replace: replace,
                     onCopy: { model.copyGauge(draft); model.showToast("コピーしました。下の「貼り付け」で、このページや別のページに貼り付けられます") },
                     onMoveZ: { d in save(); model.moveZ(dashboardId, draft.id, d) },
                     onDelete: { confirmDelete = true })
        }
    }
}

typealias DesignUpdate = ((inout GaugeDesign) -> Void) -> Void

// MARK: - 項目

private struct ItemTab: View {
    @Environment(AppModel.self) private var model
    let g: GaugeConfig
    let update: DesignUpdate
    let replace: (GaugeConfig) -> Void
    fileprivate let pick: (PickerTarget) -> Void
    let reset: String

    var body: some View {
        let base = model.catalog.get(g.pidKey)
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("表示形式")
            Chips(GaugeStyle.allCases.map { ($0, $0.label) }, selected: { $0 == g.style }) { s in
                var n = g; n.style = s; replace(n)
            }
            Hint("表示形式を変えると、その形式で使う設定のタブに切り替わります (ほかの形式の設定は残っています)。")

            Head("表示する項目")
            HStack {
                VStack(alignment: .leading) {
                    Text(base?.name ?? "(見つかりません: \(g.pidKey))").font(.system(size: 15, weight: .medium))
                    if let b = base { Text("\(b.sourceLabel())  \(b.unit)").font(.system(size: 12)).foregroundColor(GaugeColors.subText) }
                }
                Spacer()
                Button("変更") { pick(.main) }.buttonStyle(.bordered)
            }

            switch g.style {
            case .TABLE:
                Head("表に並べる項目")
                Hint("上から順に並べ、1 段の最大行数を超えたら右に段を増やします。先頭は上の「表示する項目」です。")
                ItemRows(g: g, update: update, replace: replace, onAdd: { pick(.chart) })
            case .MONITOR:
                Head("監視する項目")
                Hint("各項目の値が変わった回数と時刻・値を記録し、直近の期間ごとに変動回数の多い順 (同じ回数なら登録順) に並べます。先頭は上の「表示する項目」です。")
                ItemRows(g: g, update: update, replace: replace, onAdd: { pick(.chart) })
            case .CHART:
                ChartItems(g: g, update: update, replace: replace, onAdd: { pick(.chart) })
            default:
                EmptyView()
            }

            if g.style != .MONITOR {
                Head("代替項目 (イグニッション OFF 時など)")
                Hint("上の項目が読めないときに、代わりに表示する項目です。BMW ではイグニッション OFF の間、標準の項目 (水温・電圧など) はエンジン ECU が応答を拒否します。同じ値を読むカスタム PID を指定しておくと、OFF の間はそちらの値を表示します。")
                HStack {
                    VStack(alignment: .leading) {
                        if let fk = g.fallbackKey {
                            if let fb = model.catalog.get(fk) {
                                Text(fb.name).font(.system(size: 15, weight: .medium))
                                Text("\(fb.sourceLabel())  \(fb.unit)").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                            } else {
                                Text("(見つかりません: \(fk))").foregroundColor(GaugeColors.warn)
                            }
                        } else {
                            Text("なし").foregroundColor(GaugeColors.subText)
                        }
                    }
                    Spacer()
                    Button(g.fallbackKey == nil ? "設定" : "変更") { pick(.fallback) }.buttonStyle(.bordered)
                    if g.fallbackKey != nil {
                        Button("外す") { var n = g; n.fallbackKey = nil; replace(n) }.buttonStyle(.bordered)
                    }
                }
            }

            if EditorTabs.usesLabelField(g.style) {
                Head("表示名 (空欄で「\(base?.shortName ?? "")」)")
                LabelField(value: d.label ?? "") { t in update { $0.label = t.trimmingCharacters(in: .whitespaces).isEmpty ? nil : t } }
                    .id("label-" + reset)
            }

            if EditorTabs.usesRange(g.style) {
                Head(g.style == .CHART ? "先頭の項目の範囲 (空欄で既定値)" : "目盛りの範囲 (空欄で既定値)")
                HStack(spacing: 8) {
                    NumberField("最小", d.min, base?.min) { v in update { $0.min = v } }
                    NumberField("最大", d.max, base?.max) { v in update { $0.max = v } }
                }
                .id("range-" + reset)
            }

            Head("小数点以下の桁数")
            Chips([(-1, "既定"), (0, "0"), (1, "1"), (2, "2"), (3, "3")], selected: { $0 == (d.decimals ?? -1) }) { n in
                update { $0.decimals = n < 0 ? nil : n }
            }

            if EditorTabs.usesWarn(g.style) {
                let defText = [base?.warnAbove.map { "上限 \(fmtNumber($0))" }, base?.warnBelow.map { "下限 \(fmtNumber($0))" }]
                    .compactMap { $0 }.joined(separator: " / ")
                SwitchLine("既定の警告値を使う", defText.isEmpty ? "警告なし" : defText, d.useDefaultWarn) { v in update { $0.useDefaultWarn = v } }
                if !d.useDefaultWarn {
                    Hint(g.style == .LAMP ? "条件が空欄のランプは、値がこの範囲を超えると点灯します (空欄 = 警告なし)" : "値がこの範囲を超えると針・数値が赤くなります (空欄 = 警告なし)")
                    HStack(spacing: 8) {
                        NumberField("下限", d.warnBelow, nil) { v in update { $0.warnBelow = v } }
                        NumberField("上限", d.warnAbove, nil) { v in update { $0.warnAbove = v } }
                    }
                    .id("warn-" + reset)
                }
            }
        }
    }
}

/// 1 行の文字入力 (入力中の値をそのまま持つ)
struct LabelField: View {
    let value: String
    var placeholder: String = ""
    let onChange: (String) -> Void
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, t in if loaded { onChange(t) } }
            .onAppear { if !loaded { text = value; DispatchQueue.main.async { loaded = true } } }
    }
}

/// 並べる項目の一覧 (名前の書き換え・並べ替え・外す・追加)。値テーブルと変動監視で使う
private struct ItemRows: View {
    @Environment(AppModel.self) private var model
    let g: GaugeConfig
    let update: DesignUpdate
    let replace: (GaugeConfig) -> Void
    let onAdd: () -> Void

    private func reorder(_ from: Int, _ to: Int) {
        var list = g.chartAllKeys
        let k = list.remove(at: from)
        list.insert(k, at: to)
        let newMain = list[0]
        var n = g
        if newMain == g.pidKey { n.chartKeys = Array(list.dropFirst()); replace(n); return }
        var labels = g.itemLabels
        labels.removeValue(forKey: newMain)
        if let l = g.design.label, !l.trimmingCharacters(in: .whitespaces).isEmpty { labels[g.pidKey] = l }
        n.pidKey = newMain
        n.chartKeys = Array(list.dropFirst())
        n.design.label = g.itemLabels[newMain]
        n.design.min = nil
        n.design.max = nil
        n.design.decimals = nil
        n.itemLabels = labels
        replace(n)
    }

    var body: some View {
        let keys = g.chartAllKeys
        VStack(alignment: .leading, spacing: 4) {
            Hint("名前の欄に入力すると、表に出す項目名を変えられます (空欄で標準の名前)。")
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                let def = model.catalog.get(key)
                Text("\(i + 1). " + (def?.name ?? "(見つかりません: \(key))")).font(.system(size: 13)).foregroundColor(GaugeColors.subText)
                HStack {
                    LabelField(value: i == 0 ? (g.design.label ?? "") : (g.itemLabels[key] ?? ""), placeholder: def?.shortName ?? "") { v in
                        let t: String? = v.trimmingCharacters(in: .whitespaces).isEmpty ? nil : v
                        if i == 0 { update { $0.label = t } } else {
                            var n = g
                            if let t = t { n.itemLabels[key] = t } else { n.itemLabels.removeValue(forKey: key) }
                            replace(n)
                        }
                    }
                    .id("\(g.id)-\(key)-\(i)")
                    Button("▲") { reorder(i, i - 1) }.disabled(i == 0)
                    Button("▼") { reorder(i, i + 1) }.disabled(i == keys.count - 1)
                    if i > 0 {
                        Button("外す") { var n = g; n.chartKeys.remove(at: i - 1); replace(n) }
                    }
                }
            }
            if g.chartKeys.count < GaugeConfig.MAX_TABLE_EXTRA {
                Button("項目を追加", action: onAdd).buttonStyle(.bordered)
            }
        }
    }
}

/// 折れ線グラフの項目・縦軸・線の色
private struct ChartItems: View {
    @Environment(AppModel.self) private var model
    let g: GaugeConfig
    let update: DesignUpdate
    let replace: (GaugeConfig) -> Void
    let onAdd: () -> Void

    var body: some View {
        if let base = model.catalog.get(g.pidKey) {
            let look = g.look(base) { model.fontName($0) }
            VStack(alignment: .leading, spacing: 4) {
                Head("グラフに表示する項目と縦軸")
                Hint("先頭は「表示する項目」です。縦軸は左右 2 つあり、項目ごとにどちらの軸に属するか選べます (既定は奇数番目が右、偶数番目が左)。")
                ForEach(Array(g.chartAllKeys.enumerated()), id: \.offset) { i, key in
                    let def = model.catalog.get(key)
                    HStack {
                        Circle().fill(look.chartColor(i)).frame(width: 12, height: 12)
                        VStack(alignment: .leading) {
                            Text(def?.name ?? "(見つかりません: \(key))").font(.system(size: 14))
                            if let d = def { Text("\(d.unit)  範囲 \(fmtNumber(d.min))〜\(fmtNumber(d.max))").font(.system(size: 12)).foregroundColor(GaugeColors.subText) }
                        }
                        Spacer()
                        let right = g.isRightAxis(i, key)
                        Chips([(false, "左"), (true, "右")], selected: { $0 == right }) { v in var n = g; n.chartAxis[key] = v; replace(n) }
                            .frame(width: 110)
                        if i > 0 {
                            Button("外す") {
                                var n = g
                                n.chartKeys.remove(at: i - 1)
                                if i < n.design.chartColors.count { n.design.chartColors.remove(at: i) }
                                replace(n)
                            }
                        }
                    }
                }
                if g.chartKeys.count < GaugeConfig.MAX_CHART_EXTRA {
                    Button("項目を追加", action: onAdd).buttonStyle(.bordered)
                }
                Head("線の色")
                ForEach(Array(g.chartAllKeys.enumerated()), id: \.offset) { i, key in
                    let auto = i == 0 ? look.accent : CHART_PALETTE[i % CHART_PALETTE.count]
                    ColorLine(model.catalog.get(key)?.shortName ?? key, g.design.chartColors[safe: i] ?? nil, auto) { c in
                        update { d in
                            while d.chartColors.count <= i { d.chartColors.append(nil) }
                            d.chartColors[i] = c
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 配置

private struct PlaceTab: View {
    let g: GaugeConfig
    let replace: (GaugeConfig) -> Void
    let onCopy: () -> Void
    let onMoveZ: (Int) -> Void
    let onDelete: () -> Void

    private func place(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        let p = Layout.clampPlacement(x, y, w, h)
        var n = g
        n.x = p[0]; n.y = p[1]; n.w = p[2]; n.h = p[3]
        replace(n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Head("位置と大きさ")
            Text("位置 (\(g.x), \(g.y))  大きさ \(g.w) × \(g.h) (ページ全体 \(Layout.COLS) × \(Layout.ROWS)、1 マス = \(Layout.SCALE))")
                .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            Hint("ページの外にはみ出して置けます (はみ出した部分は表示されません)。大きさ変更のつまみが見えないときは、ここで調整してください。")
            let xr = Layout.xRange(g.w), yr = Layout.yRange(g.h)
            SliderLine("横の位置", Double(g.x), Double(xr.lowerBound)...Double(xr.upperBound), "%.0f") { v in place(Int(v.rounded()), g.y, g.w, g.h) }
            SliderLine("縦の位置", Double(g.y), Double(yr.lowerBound)...Double(yr.upperBound), "%.0f") { v in place(g.x, Int(v.rounded()), g.w, g.h) }
            SliderLine("幅", Double(g.w), Double(Layout.widthRange.lowerBound)...Double(Layout.widthRange.upperBound), "%.0f") { v in place(g.x, g.y, Int(v.rounded()), g.h) }
            SliderLine("高さ", Double(g.h), Double(Layout.heightRange.lowerBound)...Double(Layout.heightRange.upperBound), "%.0f") { v in place(g.x, g.y, g.w, Int(v.rounded())) }

            Head("グループ")
            if g.layoutGroup != nil {
                Hint("このメーターはグループに入っています。ダッシュボードではグループごと移動・大きさ変更・コピーされます (ここでの位置・大きさの変更とコピーは、このメーターだけ)。")
                Button("グループから外す") { var n = g; n.layoutGroup = nil; replace(n) }.buttonStyle(.bordered)
            } else {
                Hint("グループには入っていません。ダッシュボードの編集中に下の「グループ」から、複数のメーターをまとめられます。")
            }

            Head("重なりの順番")
            Hint("メーターが重なっているときに、どちらを手前に描くかです。ダッシュボードの編集中は、メーター右上の ▲ (最前面) ▼ (最背面) でも変えられます。")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("最前面へ") { onMoveZ(Int.max) }.buttonStyle(.bordered)
                    Button("1 つ手前へ") { onMoveZ(1) }.buttonStyle(.bordered)
                    Button("1 つ奥へ") { onMoveZ(-1) }.buttonStyle(.bordered)
                    Button("最背面へ") { onMoveZ(Int.min) }.buttonStyle(.bordered)
                }
            }

            Head("操作")
            HStack {
                Button(g.layoutGroup != nil ? "このメーターだけコピー" : "コピー", action: onCopy).buttonStyle(.bordered)
                Button("削除", role: .destructive, action: onDelete).buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - 目盛り・針

private struct AngleSection: View {
    let d: GaugeDesign
    let update: DesignUpdate
    var analog = false

    private var presets: [(String, Double, Double, Bool)] {
        var p: [(String, Double, Double, Bool)] = [
            ("標準 240°", -120, 120, false), ("270°", -135, 135, false), ("300°", -150, 150, false),
            ("半円 180°", -90, 90, false), ("右上 90°", 0, 90, false), ("全周 360°", -180, 180, false),
        ]
        if analog {
            p += [("下 半円 180° 左→右", -90, 90, true), ("下 240° 左→右", -60, 60, true), ("下 90° 左→右", -135, 135, true)]
        }
        return p
    }

    var body: some View {
        let presets = self.presets
        VStack(alignment: .leading, spacing: 2) {
            Head("開始・終了角度 (12 時 = 0°、時計回り)")
            Chips(presets.indices.map { ($0, presets[$0].0) }, selected: { i in
                let p = presets[i]
                return d.startAngle == p.1 && d.endAngle == p.2 && (analog && d.counterClockwise) == p.3
            }) { i in
                let p = presets[i]
                update { $0.startAngle = p.1; $0.endAngle = p.2; $0.counterClockwise = p.3 }
            }
            SliderLine("開始角度", d.startAngle, -180...180, "%.0f°") { v in update { $0.startAngle = snap(v, 5) } }
            SliderLine("終了角度", d.endAngle, -180...360, "%.0f°") { v in update { $0.endAngle = snap(v, 5) } }
            if analog {
                SwitchLine("反時計回りに進む", "ON にすると、開始角度から終了角度へ反時計回りに目盛りを振ります (下側の扇形で、左から右へ針が動くようにするときなど)",
                           d.counterClockwise) { v in update { $0.counterClockwise = v } }
            }
        }
    }
}

private struct RedZoneSection: View {
    let g: GaugeConfig
    let update: DesignUpdate

    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("レッドゾーン")
            SwitchLine("レッドゾーンを表示", nil, d.showRedZone) { v in update { $0.showRedZone = v } }
            if d.showRedZone {
                Hint("空欄なら警告値 (上限〜最大、または最小〜下限) を使います")
                HStack(spacing: 8) {
                    NumberField("開始", d.redZoneFrom, nil) { v in update { $0.redZoneFrom = v } }
                    NumberField("終了", d.redZoneTo, nil) { v in update { $0.redZoneTo = v } }
                }
                .id("rz-\(g.pidKey)")
                ColorLine("レッドゾーンの色", d.redZoneColor, GaugeColors.warnZone, extra: [("濃い赤", 0xFFD32F2F)]) { c in update { $0.redZoneColor = c } }
            }
        }
    }
}

private struct ScaleTab: View {
    let g: GaugeConfig
    let update: DesignUpdate

    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("シンプルな扇形")
            Hint("針・目盛りを消して、端の丸い太い弧と中央の大きな数値だけのシンプルなメーターにします (あとから個別に調整できます)。")
            Button("シンプルな扇形にする") {
                update { x in
                    x.startAngle = -135; x.endAngle = 135; x.showNeedle = false; x.showTicks = false; x.showLabels = false
                    x.ring = .NONE; x.showTrack = true; x.showValueArc = true; x.arcWidth = 2.2; x.tickRadius = 1
                    x.arcRoundCap = true; x.arcTipDot = true; x.trackColor = 0xFF2A2F37; x.color = x.color ?? 0xFF2F9BFF
                    x.valuePosition = 0.05; x.valueOffsetX = 0; x.valueSize = 2.2
                    x.nameOffsetX = 0; x.nameOffsetY = 0.51; x.unitOffsetX = 0; x.unitOffsetY = 0
                    x.showName = true; x.showUnit = true
                }
            }
            .buttonStyle(.bordered)

            AngleSection(d: d, update: update, analog: true)

            Head("目盛り")
            SwitchLine("目盛りの線を表示", nil, d.showTicks) { v in update { $0.showTicks = v } }
            SwitchLine("主目盛りの数を自動で決める", nil, d.majorDivisions == nil) { auto in update { $0.majorDivisions = auto ? nil : 8 } }
            if let n = d.majorDivisions {
                SliderLine("主目盛りの区間数", Double(n), 1...20, "%.0f") { v in update { $0.majorDivisions = Int(v.rounded()) } }
            }
            SliderLine("小目盛り (主目盛りの間)", Double(d.minorDivisions), 0...9, "%.0f") { v in update { $0.minorDivisions = Int(v.rounded()) } }
            SliderLine("目盛りの位置 (外周 = 100%)", d.tickRadius * 100, 40...110, "%.0f%%") { v in update { $0.tickRadius = snap(v, 1) / 100 } }
            SwitchLine("目盛りの数字を表示", nil, d.showLabels) { v in update { $0.showLabels = v } }
            if d.showLabels {
                SliderLine("数字の大きさ", d.labelSize * 100, 40...250, "%.0f%%") { v in update { $0.labelSize = snap(v, 5) / 100 } }
            }
            ColorLine("目盛りの色", d.tickColor, GaugeColors.tick) { c in update { $0.tickColor = c } }

            Head("弧")
            SwitchLine("下地の弧", nil, d.showTrack) { v in update { $0.showTrack = v } }
            if d.showTrack { ColorLine("下地の弧の色 (既定 = 灰色)", d.trackColor, GaugeColors.track) { c in update { $0.trackColor = c } } }
            SwitchLine("現在値の弧", nil, d.showValueArc) { v in update { $0.showValueArc = v } }
            SliderLine("弧の太さ (0 = なし)", d.arcWidth * 100, 0...300, "%.0f%%") { v in update { $0.arcWidth = snap(v, 5) / 100 } }
            SwitchLine("弧の端を丸くする", nil, d.arcRoundCap) { v in update { $0.arcRoundCap = v } }
            SwitchLine("弧の先に丸い点を付ける", "ピーク値を表示しているときは、点がピーク値の印になります (三角の印の代わり)", d.arcTipDot) { v in update { $0.arcTipDot = v } }
            if d.arcTipDot {
                if d.showPeak { Hint("ピーク値を表示しているので、点の色は「ピーク値の印の色」になります (「色・数値」タブ)") }
                else { ColorLine("点の色", d.arcTipColor, .white) { c in update { $0.arcTipColor = c } } }
            }

            RedZoneSection(g: g, update: update)

            Head("針 (ポインター)")
            SwitchLine("針を表示", nil, d.showNeedle) { v in update { $0.showNeedle = v } }
            if d.showNeedle {
                ColorLine("針の色", d.needleColor, GaugeColors.text) { c in update { $0.needleColor = c } }
                SliderLine("針の長さ", d.needleLength * 100, 30...130, "%.0f%%") { v in update { $0.needleLength = snap(v, 5) / 100 } }
                SliderLine("針の太さ", d.needleWidth * 100, 20...400, "%.0f%%") { v in update { $0.needleWidth = snap(v, 5) / 100 } }
                SliderLine("反対側の尾の長さ", d.needleTail * 100, 0...60, "%.0f%%") { v in update { $0.needleTail = snap(v, 1) / 100 } }
                Head("中心のノブ")
                ColorLine("ノブの色 (既定 = 針と同じ)", d.knobColor, d.needleColor.map { Color(argb: $0) } ?? GaugeColors.text) { c in update { $0.knobColor = c } }
                SliderLine("ノブの大きさ (0 = なし)", d.knobSize * 100, 0...400, "%.0f%%") { v in update { $0.knobSize = snap(v, 5) / 100 } }
            }
        }
    }
}

// MARK: - バーの形

private struct BarTab: View {
    let g: GaugeConfig
    let def: PidDef?
    let update: DesignUpdate

    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("デジパネ風")
            Hint("昔のデジタルメーターのような、弧を描いて伸びる蛍光管風のバーにします (あとから個別に調整できます)。")
            Button("デジパネ風にする") {
                let mid = def.map { $0.min + ($0.max - $0.min) * 0.7 }
                update { x in
                    x.barArc = true; x.startAngle = -100; x.endAngle = 70; x.barSegments = 32; x.barSegmentGap = 0.35
                    x.barTaper = 0.65; x.arcWidth = 1.2; x.showTrack = true; x.showValueArc = true
                    x.barZoneColors = true; x.color = 0xFF39FF7A; x.barMidColor = 0xFFFFC21A; x.barMidFrom = mid
                    x.redZoneColor = 0xFFFF3B30; x.barOffColor = nil
                    x.glow = 0.6; x.ghostDigits = true; x.ghostAlpha = 0.12
                    x.valueColor = 0xFF5CFFB0; x.faceColor = x.faceColor ?? 0xFF050805
                }
            }
            .buttonStyle(.bordered)

            Head("バーの形")
            Chips([(false, "直線"), (true, "弧")], selected: { $0 == d.barArc }) { v in update { $0.barArc = v } }
            if d.barArc {
                Hint("枠いっぱいに収まる大きさで描きます。")
                AngleSection(d: d, update: update)
            } else {
                Head("バーの角度 (時計回り)")
                Chips([(0.0, "横 (左→右)"), (-90.0, "縦 (下→上)"), (90.0, "縦 (上→下)"), (-45.0, "斜め ↗"), (45.0, "斜め ↘"), (180.0, "横 (右→左)")],
                      selected: { $0 == d.barAngle }) { a in update { $0.barAngle = a } }
                SliderLine("角度", d.barAngle, -180...180, "%.0f°") { v in update { $0.barAngle = snap(v, 5) } }
                Hint("0° 以外はメーターの中央を軸に回し、枠に収まる長さで描きます。")
            }

            Head("バーの線")
            Chips([(false, "実線"), (true, "破線")], selected: { $0 == (d.barSegments > 0) }) { v in
                update { $0.barSegments = v ? ($0.barSegments > 0 ? $0.barSegments : 20) : 0 }
            }
            if d.barSegments > 0 {
                SliderLine("マスの数", Double(d.barSegments), 3...60, "%.0f") { v in update { $0.barSegments = Int(v.rounded()) } }
                SliderLine("マスの間のすき間", d.barSegmentGap * 100, 5...80, "%.0f%%") { v in update { $0.barSegmentGap = snap(v, 1) / 100 } }
            }
            SliderLine("バーの太さ", d.arcWidth * 100, 0...300, "%.0f%%") { v in update { $0.arcWidth = snap(v, 5) / 100 } }
            SliderLine("先細り", d.barTaper * 100, 0...100, "%.0f%%") { v in update { $0.barTaper = snap(v, 5) / 100 } }
            Hint("始まりを細く、終わりに向かって太くします (デジパネのタコメーター風)。")
            SwitchLine("下地 (値の無い部分) を表示", nil, d.showTrack) { v in update { $0.showTrack = v } }
            SwitchLine("現在値のバーを表示", nil, d.showValueArc) { v in update { $0.showValueArc = v } }

            Head("マスの色")
            ColorLine("通常の色 (= メーターの色)", d.color, GaugeColors.accent) { c in update { $0.color = c } }
            SwitchLine("範囲で色分けする", "通常の色 → 中間の色 → レッドゾーンの色 の順に、位置ごとに塗り分けます", d.barZoneColors) { v in update { $0.barZoneColors = v } }
            if d.barZoneColors {
                ColorLine("中間の色", d.barMidColor, Color(argb: 0xFFFFC107)) { c in update { $0.barMidColor = c } }
                if let df = def, df.max > df.min {
                    let from = d.barMidFrom ?? (df.min + (df.max - df.min) * 0.7)
                    SliderLine("中間の色にする値", from, df.min...df.max, "%.0f") { v in update { $0.barMidFrom = v } }
                }
                Hint("レッドゾーンの範囲と色は下の「レッドゾーン」の設定を使います。")
            }
            ColorLine("消えているマス・背景の色 (既定 = 自動)", d.barOffColor, GaugeColors.track) { c in update { $0.barOffColor = c } }
            Hint("自動のときは、色分けか発光を使うと各マスの色をうっすら、それ以外は灰色で描きます。")
            ColorLine("目盛りの色", d.tickColor, GaugeColors.tick) { c in update { $0.tickColor = c } }

            RedZoneSection(g: g, update: update)
        }
    }
}

// MARK: - 色・数値

private struct FontSection: View {
    @Environment(AppModel.self) private var model
    let d: GaugeDesign
    fileprivate let pickFont: (FontTarget) -> Void

    private func name(_ id: String?, _ def: String) -> String {
        guard let id = id else { return def }
        return model.fonts.first { $0.id == id }?.name ?? "(削除されたフォント)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Head("フォント")
            Hint("取り込んだフォントは、ほかのメーターでもそのまま選べます")
            fontLine("数値", name(d.valueFont, "既定 (等幅)")) { pickFont(.value) }
            fontLine("文字 (名前・単位・目盛りの数字)", name(d.labelFont, "既定")) { pickFont(.label) }
        }
    }

    private func fontLine(_ label: String, _ current: String, _ action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                Text(current).font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            }
            Spacer()
            Button("変更", action: action).buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct GlowSection: View {
    let g: GaugeConfig
    let update: DesignUpdate
    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("蛍光管風")
            SliderLine("発光 (にじみ)", d.glow * 100, 0...100, "%.0f%%") { v in update { $0.glow = snap(v, 5) / 100 } }
            if EditorTabs.usesGhost(g.style) {
                SwitchLine("消えている 7 セグを薄く表示", "数値の後ろに「888」をうっすら出します (7 セグ風のフォントと合わせて使います)", d.ghostDigits) { v in update { $0.ghostDigits = v } }
                if d.ghostDigits {
                    SliderLine("薄さ", d.ghostAlpha * 100, 3...60, "%.0f%%") { v in update { $0.ghostAlpha = snap(v, 1) / 100 } }
                }
            }
        }
    }
}

private struct PanelSection: View {
    let d: GaugeDesign
    let update: DesignUpdate
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("背景の立体感").font(.system(size: 14)).padding(.top, 12)
            Chips(PanelStyle.allCases.map { ($0, $0.label) }, selected: { $0 == d.panelStyle }) { p in update { $0.panelStyle = p } }
            if d.panelStyle != .FLAT {
                SliderLine("立体感の強さ", d.panelDepth * 100, 0...100, "%.0f%%") { v in update { $0.panelDepth = snap(v, 5) / 100 } }
            }
            SwitchLine("ガラスの映り込み", "上半分をうっすら明るくして、表示部にガラスがはまっているように見せます", d.panelGloss) { v in update { $0.panelGloss = v } }
            Hint("「埋め込み」は計器の液晶窓のように、上の縁から内側へ短い影を落とし、ふちを細く暗くして、表示部が文字盤の奥に沈んでいるように見せます。")
        }
    }
}

private struct FaceSection: View {
    let d: GaugeDesign
    let update: DesignUpdate
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ColorLine("メーターの背景色 (既定 = なし)", d.faceColor, .clear) { c in update { $0.faceColor = c } }
            if d.faceColor != nil {
                SliderLine("背景色の大きさ", d.faceScale * 100, 20...150, "%.0f%%") { v in update { $0.faceScale = snap(v, 1) / 100 } }
                if d.backgroundImage != nil {
                    Hint("背景色は背景画像の下に塗ります。画像の透過した部分から見えるので、大きさを画像の内側に合わせてください。")
                }
                PanelSection(d: d, update: update)
            }
        }
    }
}

private struct RingSection: View {
    let d: GaugeDesign
    let update: DesignUpdate
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Head("外周リング")
            Chips(RingStyle.allCases.map { ($0, $0.label) }, selected: { $0 == d.ring }) { r in update { $0.ring = r } }
            if d.ring != .NONE {
                ColorLine("リングの色", d.ringColor, GaugeColors.ring) { c in update { $0.ringColor = c } }
                SliderLine("リングの太さ", d.ringThickness * 100, 30...300, "%.0f%%") { v in update { $0.ringThickness = snap(v, 5) / 100 } }
                if d.ring == .METAL || d.ring == .BOLD {
                    SliderLine("立体感 (陰影の強さ)", d.ringDepth * 100, 0...100, "%.0f%%") { v in update { $0.ringDepth = snap(v, 5) / 100 } }
                }
                if d.ring == .METAL {
                    SliderLine("内側の段の幅 (凹んだ部分)", d.ringInner * 100, 0...80, "%.0f%%") { v in update { $0.ringInner = snap(v, 5) / 100 } }
                }
            }
        }
    }
}

private struct PeakSection: View {
    let g: GaugeConfig
    let update: DesignUpdate
    var body: some View {
        let d = g.design
        let digital = g.style == .DIGITAL
        VStack(alignment: .leading, spacing: 2) {
            Head("ピーク値 (最大値)")
            SwitchLine(digital ? "最大値を表示する" : "最大値の位置に印を付ける", "ダッシュボードでメーターを長押しするとリセットします", d.showPeak) { v in update { $0.showPeak = v } }
            if d.showPeak {
                if !digital {
                    SwitchLine("最大値を数字でも表示", nil, d.showPeakValue) { v in update { $0.showPeakValue = v } }
                    ColorLine("印の色", d.peakColor, GaugeColors.peak) { c in update { $0.peakColor = c } }
                }
                if d.showPeakValue || digital {
                    let def = d.peakColor.map { Color(argb: $0) } ?? GaugeColors.peak
                    ColorLine(digital ? "最大値の文字の色" : "最大値の文字の色 (既定 = 印の色)", d.peakTextColor, def) { c in update { $0.peakTextColor = c } }
                    SliderLine("最大値の文字の大きさ", d.peakTextSize * 100, 30...400, "%.0f%%") { v in update { $0.peakTextSize = snap(v, 5) / 100 } }
                    SliderLine("最大値の文字の横位置 (右が +)", d.peakTextX * 100, -100...100, "%.0f") { v in update { $0.peakTextX = snap(v, 1) / 100 } }
                    SliderLine("最大値の文字の縦位置 (下が +)", d.peakTextY * 100, -100...100, "%.0f") { v in update { $0.peakTextY = snap(v, 1) / 100 } }
                }
            }
        }
    }
}

private struct ValueNameUnitSection: View {
    let g: GaugeConfig
    let update: DesignUpdate
    var body: some View {
        let d = g.design
        let positions = g.style != .LAMP
        let labelDefault = d.labelColor.map { Color(argb: $0) } ?? GaugeColors.subText
        VStack(alignment: .leading, spacing: 2) {
            Head("数値")
            SwitchLine("数値を表示", nil, d.showValue) { v in update { $0.showValue = v } }
            if d.showValue {
                ColorLine("数値の色", d.valueColor, GaugeColors.text) { c in update { $0.valueColor = c } }
                SliderLine("数値の大きさ", d.valueSize * 100, 30...300, "%.0f%%") { v in update { $0.valueSize = snap(v, 5) / 100 } }
                if positions {
                    SliderLine("数値の縦位置 (中心 = 0、下が +)", d.valuePosition * 100, -90...90, "%.0f") { v in update { $0.valuePosition = snap(v, 1) / 100 } }
                    SliderLine("数値の横位置 (中心 = 0、右が +)", d.valueOffsetX * 100, -90...90, "%.0f") { v in update { $0.valueOffsetX = snap(v, 1) / 100 } }
                }
            }
            Head("名前・単位")
            ColorLine("文字の色 (名前・単位・目盛りの数字の既定)", d.labelColor, GaugeColors.subText) { c in update { $0.labelColor = c } }
            SwitchLine("名前を表示", nil, d.showName) { v in update { $0.showName = v } }
            if d.showName {
                ColorLine("名前の色 (既定 = 文字の色)", d.nameColor, labelDefault) { c in update { $0.nameColor = c } }
                SliderLine("名前の大きさ", d.tableNameSize * 100, 30...300, "%.0f%%") { v in update { $0.tableNameSize = snap(v, 5) / 100 } }
                SliderLine("名前の横位置 (右が +)", d.nameOffsetX * 100, -60...60, "%.0f") { v in update { $0.nameOffsetX = snap(v, 1) / 100 } }
                SliderLine("名前の縦位置 (下が +)", d.nameOffsetY * 100, -60...60, "%.0f") { v in update { $0.nameOffsetY = snap(v, 1) / 100 } }
            }
            SwitchLine("単位を表示", nil, d.showUnit) { v in update { $0.showUnit = v } }
            if d.showUnit && positions {
                ColorLine("単位の色 (既定 = 文字の色)", d.unitColor, labelDefault) { c in update { $0.unitColor = c } }
                SliderLine("単位の大きさ", d.tableUnitSize * 100, 30...300, "%.0f%%") { v in update { $0.tableUnitSize = snap(v, 5) / 100 } }
                SliderLine("単位の横位置 (右が +)", d.unitOffsetX * 100, -60...60, "%.0f") { v in update { $0.unitOffsetX = snap(v, 1) / 100 } }
                SliderLine("単位の縦位置 (下が +)", d.unitOffsetY * 100, -60...60, "%.0f") { v in update { $0.unitOffsetY = snap(v, 1) / 100 } }
                Hint("単位の位置は数値の位置からのずれです (数値を動かすと一緒に動きます)")
            }
        }
    }
}

private struct CardSwitch: View {
    let d: GaugeDesign
    let update: DesignUpdate
    var style: GaugeStyle? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Head("カード")
            SwitchLine("四角いカードの背景を表示", "丸い背景画像を使うときや、背景を透かしたいときは OFF にします", d.showCard) { v in update { $0.showCard = v } }
            Head("影")
            if style == .ANALOG {
                SwitchLine("針に影を付ける", "針とノブが文字盤から少し浮いているように、右下に影を落とします", d.needleShadow) { v in update { $0.needleShadow = v } }
            }
            let note: String = style == .ANALOG ? "カードを出していなければ、丸い文字盤 (背景色・リング・画像があるとき) の形に付けます" :
                ((style == .BAR || style == .DIGITAL || style == .LAMP) ? "カードを出していなければ、背景色の形に付けます" : "カードを出しているときに、カードの形に付けます")
            SwitchLine("メーター自体に影を付ける", note, d.objectShadow) { v in update { $0.objectShadow = v } }
            if d.needleShadow || d.objectShadow {
                SliderLine("影の濃さ", d.shadowStrength * 100, 0...150, "%.0f%%") { v in update { $0.shadowStrength = snap(v, 5) / 100 } }
            }
        }
    }
}

private struct LookTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    fileprivate let pickFont: (FontTarget) -> Void
    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            FontSection(d: d, pickFont: pickFont)
            if g.style == .ANALOG {
                ColorLine("メーターの色 (現在値の弧)", d.color, GaugeColors.accent) { c in update { $0.color = c } }
            }
            if g.style == .DIGITAL {
                ColorLine("メーターの色 (数値の既定の色)", d.color, GaugeColors.accent) { c in update { $0.color = c } }
            }
            GlowSection(g: g, update: update)
            FaceSection(d: d, update: update)
            if EditorTabs.usesRing(g.style) { RingSection(d: d, update: update) }
            Head("値の動き")
            SliderLine("なめらかさ", d.smoothing * 100, 0...100, "%.0f%%") { v in update { $0.smoothing = snap(v, 5) / 100 } }
            Hint("小さくするほど値の変化にすぐ追従し (反応が速い)、大きくするほど針や数値がなめらかに動きます (少し遅れます)。50% が標準です。")
            PeakSection(g: g, update: update)
            ValueNameUnitSection(g: g, update: update)
            CardSwitch(d: d, update: update, style: g.style)
        }
    }
}

// MARK: - ランプ・値テーブル・グラフ・変動監視

private struct LampTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    fileprivate let pickFont: (FontTarget) -> Void
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        let d = g.design
        let error = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Condition.check(text)
        VStack(alignment: .leading, spacing: 2) {
            Head("点灯条件")
            Hint("計測値を x として条件を書きます。例: x >= 100 / x > 90 && x < 110 / x < 11.5 || x > 14.8 / abs(x) > 5。空欄のときは警告値 (「項目」タブ) を超えたら点灯します。")
            TextField("例: x >= 100", text: $text)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text) { _, t in
                    if !loaded { return }
                    if t.trimmingCharacters(in: .whitespaces).isEmpty || Condition.check(t) == nil {
                        update { $0.lampCondition = t.trimmingCharacters(in: .whitespaces) }
                    }
                }
            if let e = error { Text(e).font(.system(size: 12)).foregroundColor(GaugeColors.warn) }
            ColorLine("点灯時の色", d.lampOnColor, GaugeColors.warn) { c in update { $0.lampOnColor = c } }
            ColorLine("消灯時の色", d.lampOffColor, Color(argb: 0xFF2A2F36)) { c in update { $0.lampOffColor = c } }
            FontSection(d: d, pickFont: pickFont)
            FaceSection(d: d, update: update)
            RingSection(d: d, update: update)
            ValueNameUnitSection(g: g, update: update)
            CardSwitch(d: d, update: update, style: g.style)
            Head("背景画像")
            ImageTab(g: g, update: update)
        }
        .onAppear { if !loaded { text = d.lampCondition; DispatchQueue.main.async { loaded = true } } }
    }
}

private struct TableTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    fileprivate let pickFont: (FontTarget) -> Void
    @State private var photo: PhotosPickerItem? = nil
    @State private var loading = false

    var body: some View {
        let d = g.design
        let labelDefault = d.labelColor.map { Color(argb: $0) } ?? GaugeColors.subText
        VStack(alignment: .leading, spacing: 2) {
            Head("並べ方")
            SliderLine("1 段の最大行数", Double(d.tableMaxRows), 1...15, "%.0f 行") { v in update { $0.tableMaxRows = Swift.min(Swift.max(Int(v.rounded()), 1), 15) } }
            SwitchLine("項目名を表示", "OFF にすると値と単位だけを並べます", d.showName) { v in update { $0.showName = v } }
            if d.showName {
                SwitchLine("項目名を値の枠の左上に表示", "ON にすると項目名の欄をなくして、値の枠の左上に小さく表示します", d.tableNameInline) { v in update { $0.tableNameInline = v } }
                if !d.tableNameInline {
                    SliderLine("項目名の幅", d.tableNameRatio * 100, 0...70, "%.0f%%") { v in update { $0.tableNameRatio = snap(v, 1) / 100 } }
                }
                SliderLine("項目名の文字の大きさ", d.tableNameSize * 100, 30...300, "%.0f%%") { v in update { $0.tableNameSize = snap(v, 5) / 100 } }
            }
            SwitchLine("単位を表示", "OFF にすると単位の欄をなくして、値の部分を広げます", d.showUnit) { v in update { $0.showUnit = v } }
            if d.showUnit {
                SwitchLine("単位を値に付ける", "ON にすると単位の欄をなくして、値のすぐ後ろに単位を表示します", d.tableUnitInline) { v in update { $0.tableUnitInline = v } }
                if !d.tableUnitInline {
                    SliderLine("単位の幅", d.tableUnitRatio * 100, 0...50, "%.0f%%") { v in update { $0.tableUnitRatio = snap(v, 1) / 100 } }
                }
                SliderLine("単位の文字の大きさ", d.tableUnitSize * 100, 30...300, "%.0f%%") { v in update { $0.tableUnitSize = snap(v, 5) / 100 } }
            }
            SliderLine("値の文字の大きさ", d.valueSize * 100, 30...300, "%.0f%%") { v in update { $0.valueSize = snap(v, 5) / 100 } }
            SliderLine("各行の下の余白", d.tableMarginBottom * 100, 0...60, "%.0f%%") { v in update { $0.tableMarginBottom = snap(v, 1) / 100 } }
            SliderLine("各段の右の余白", d.tableMarginRight * 100, 0...60, "%.0f%%") { v in update { $0.tableMarginRight = snap(v, 1) / 100 } }
            SliderLine("値と値の間 (上下)", d.tableRowGap, -60...80, "%.0f pt") { v in update { $0.tableRowGap = snap(v, 1) } }
            if d.tableMaxRows < g.chartAllKeys.count {
                SliderLine("段と段の間 (左右)", d.tableColGap, -60...120, "%.0f pt") { v in update { $0.tableColGap = snap(v, 1) } }
            }
            Hint("「値と値の間」は行と行・段と段の間だけに空け、外側には空けません。0 で枠どうしがすき間なく並びます。マイナスにすると、文字の上下の空きを重ねてさらに詰められます。「余白」は各行・各段の内側に空けます (文字も小さくなります)。")

            Head("値の部分の背景")
            ColorLine("背景色 (既定 = なし)", d.tableValueBg, .clear) { c in update { $0.tableValueBg = c } }
            if d.tableValueBg != nil || d.tableValueImage != nil { PanelSection(d: d, update: update) }
            HStack {
                PhotosPicker(selection: $photo, matching: .images) {
                    Text(loading ? "読み込み中…" : (d.tableValueImage == nil ? "背景画像を選ぶ" : "背景画像を変更"))
                }
                .buttonStyle(.bordered)
                if d.tableValueImage != nil {
                    Button("画像を外す") { update { $0.tableValueImage = nil } }.buttonStyle(.bordered)
                }
            }
            .onChange(of: photo) { _, item in
                guard let item = item else { return }
                loading = true
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let name = try? GaugeImages.importImage(data) {
                        update { $0.tableValueImage = name }
                    }
                    loading = false
                    photo = nil
                }
            }
            Hint("背景画像は値の部分いっぱいに伸ばして表示します (背景色の上に重ねます)。")

            FontSection(d: d, pickFont: pickFont)
            Head("文字の色")
            ColorLine("値の色", d.valueColor, GaugeColors.text) { c in update { $0.valueColor = c } }
            ColorLine("文字の色 (項目名・単位の既定)", d.labelColor, GaugeColors.subText) { c in update { $0.labelColor = c } }
            if d.showName { ColorLine("項目名の色 (既定 = 文字の色)", d.nameColor, labelDefault) { c in update { $0.nameColor = c } } }
            if d.showUnit { ColorLine("単位の色 (既定 = 文字の色)", d.unitColor, labelDefault) { c in update { $0.unitColor = c } } }
            GlowSection(g: g, update: update)
            CardSwitch(d: d, update: update)
        }
    }
}

private struct ChartViewTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    fileprivate let pickFont: (FontTarget) -> Void
    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("1 画面に表示する期間")
            Chips([(600, "10分"), (1800, "30分"), (3600, "1時間"), (10800, "3時間"), (21600, "6時間"), (43200, "12時間"),
                   (86400, "1日"), (259200, "3日"), (604800, "1週間"), (2592000, "1か月")], selected: { $0 == d.chartSpanSec }) { s in
                update { $0.chartSpanSec = s }
            }
            Hint("記録の全期間を表示できます。左右にドラッグでスクロール、ピンチで期間を拡大縮小、ダブルタップで現在の表示に戻ります。")
            SwitchLine("記録の無い時間を詰めて表示", "どの項目にも記録が無い時間 (エンジン停止中など) を飛ばして、切れ目に点線を出します", d.chartSkipGaps) { v in update { $0.chartSkipGaps = v } }
            Head("凡例 (項目名と現在値)")
            Chips(LegendPosition.allCases.map { ($0, $0.label) }, selected: { $0 == d.legendPosition }) { p in update { $0.legendPosition = p } }
            if d.legendPosition != .HIDDEN {
                if !d.legendPosition.inside {
                    Chips(LegendAlign.allCases.map { ($0, $0.label) }, selected: { $0 == d.legendAlign }) { a in update { $0.legendAlign = a } }
                }
                SliderLine("大きさ", d.legendScale, 0.4...3, "×%.2f") { v in update { $0.legendScale = snap(v, 0.05) } }
                if d.legendPosition.inside {
                    SliderLine("背景の濃さ", d.legendBgAlpha, 0...1, "%.2f") { v in update { $0.legendBgAlpha = snap(v, 0.05) } }
                }
                SwitchLine("単位を表示", nil, d.showUnit) { v in update { $0.showUnit = v } }
                ColorLine("項目名の色", d.labelColor, GaugeColors.subText) { c in update { $0.labelColor = c } }
                Hint("タップした時刻の日時と値もここに出ます。値は線の色で表示します。")
            }
            FontSection(d: d, pickFont: pickFont)
            GlowSection(g: g, update: update)
            CardSwitch(d: d, update: update)
        }
    }
}

private struct MonitorViewTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    fileprivate let pickFont: (FontTarget) -> Void
    var body: some View {
        let d = g.design
        VStack(alignment: .leading, spacing: 2) {
            Head("最初に表示する期間")
            Chips(Monitor.WINDOWS.map { ($0.0, "直近" + $0.1) }, selected: { Monitor.windowIndex($0) == Monitor.windowIndex(d.monitorWindowMs) }) { ms in
                update { $0.monitorWindowMs = ms }
            }
            Hint("ダッシュボードでは、上の期間の欄をタップして切り替えられます。現在の値は「最新の計測値 − 初回の計測値」です。値は項目の取得周期 (設定画面) ごとに見て、このページを表示していないときも記録します。記録はこのメーターを削除するまで残ります。メーター右上の「書出」「読込」で記録を CSV で書き出し・読み込み、「リセット」で記録を消せます。")
            Head("文字")
            ColorLine("回数・選んだ期間の色 (= メーターの色)", d.color, GaugeColors.accent) { c in update { $0.color = c } }
            ColorLine("現在の値の色", d.valueColor, GaugeColors.text) { c in update { $0.valueColor = c } }
            ColorLine("項目名の色", d.labelColor, GaugeColors.subText) { c in update { $0.labelColor = c } }
            SliderLine("回数・値の大きさ", d.valueSize * 100, 30...300, "%.0f%%") { v in update { $0.valueSize = snap(v, 5) / 100 } }
            SliderLine("項目名の大きさ", d.labelSize * 100, 40...250, "%.0f%%") { v in update { $0.labelSize = snap(v, 5) / 100 } }
            SwitchLine("単位を表示", nil, d.showUnit) { v in update { $0.showUnit = v } }
            FontSection(d: d, pickFont: pickFont)
            GlowSection(g: g, update: update)
            CardSwitch(d: d, update: update)
        }
    }
}

private struct ChartRecordTab: View {
    @Environment(AppModel.self) private var model
    let g: GaugeConfig
    let update: DesignUpdate
    var body: some View {
        let d = g.design
        let interval = Swift.min(Swift.max(Int(d.recordIntervalSec), HistoryStore.MIN_INTERVAL_SEC), HistoryStore.MAX_INTERVAL_SEC)
        VStack(alignment: .leading, spacing: 2) {
            Head("記録するタイミング")
            SwitchLine("このページを表示している間だけ記録する", "ON にすると、ほかのページを表示している間はこのグラフの項目を記録しません (車との通信が減り、ほかのメーターの反応が良くなります)", d.recordOnlyWhenShown) { v in update { $0.recordOnlyWhenShown = v } }
            Head("記録する間隔")
            Hint("記録はグラフごとに別々です。同じ項目をほかのグラフでも使っていても、このグラフの設定で記録します (新しく置いたグラフは空から始まります)。")
            SwitchLine("変化したときだけ記録する", "記録する間隔を使わず、項目の取得周期 (設定画面) ごとに値を見て、前回記録した値から変わったときだけ記録します。グラフは次に変わるまで前の値が続く階段状の線で描きます", d.recordOnChange) { v in update { $0.recordOnChange = v } }
            if d.recordOnChange {
                Hint("取得周期を設定していない項目は 0.2 秒ごとに値を見ます。このページを表示していない間に記録のために読む項目は、1 秒に 1 回までにします。")
            } else {
                SliderLine("間隔 (秒)", Double(interval), Double(HistoryStore.MIN_INTERVAL_SEC)...Double(HistoryStore.MAX_INTERVAL_SEC), "%.0f 秒") { v in
                    update { $0.recordIntervalSec = Swift.max(v < 60 ? snap(v, 1) : snap(v, 10), 1) }
                }
                Hint("接続した直後にすべての項目を 1 回記録し、その後はこの間隔で記録します (グラフのページを表示していなくても記録します)。")
            }
            Head("記録を残す期間")
            Chips([(1, "1時間"), (24, "1日"), (168, "1週間"), (-1, "1か月"), (-2, "2か月"), (-3, "3か月"), (-6, "6か月"), (-12, "12か月"), (-24, "24か月")],
                  selected: { v in v > 0 ? d.historyHours == v : (d.historyHours <= 0 && d.historyMonths == -v) }) { v in
                update { x in
                    if v > 0 { x.historyHours = v } else { x.historyHours = 0; x.historyMonths = -v }
                }
            }
            let days = Double(d.historyRetentionMs) / 86_400_000
            let mb = days * 86_400 / Double(interval) * Double(g.chartAllKeys.count) * 40 / 1_000_000
            Hint("期間を過ぎた記録は自動で消えます。" + (d.recordOnChange ? "変化したときだけ記録するので、使う容量は値の変わり方しだいです。" : String(format: "この設定で最大約 %.1f MB を使います。", mb)))
            Head("記録の CSV")
            Hint("ダッシュボードのグラフ内の「書出」「読込」ボタンで、このグラフの項目の記録を CSV で書き出し・読み込みできます。形式は 1 行に「項目キー, 年月日時分秒, 値」(例: COOLANT,2026-10-18 00:46:00,88)。読み込みでは、同じ項目・同じ時刻の記録は上書きされます。")
            Text(g.chartAllKeys.map { k in "\(model.catalog.get(k)?.shortName ?? k) = \(k)" }.joined(separator: "  "))
                .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
        }
    }
}

// MARK: - 画像

private struct ImageTab: View {
    let g: GaugeConfig
    let update: DesignUpdate
    @State private var photo: PhotosPickerItem? = nil
    @State private var loading = false
    @State private var error: String? = nil

    var body: some View {
        let d = g.design
        let analog = g.style == .ANALOG
        VStack(alignment: .leading, spacing: 2) {
            Hint(analog ? "メーターの文字盤 (目盛りや数字のない画像) を背景に使えます。目盛り・数字・針は画像の上に描かれます。透過 PNG も使えます。正方形に近い画像がおすすめです。"
                 : "メーターの背景に画像を使えます。数値などは画像の上に描かれます。透過 PNG も使えます。")
            HStack {
                PhotosPicker(selection: $photo, matching: .images) {
                    Text(loading ? "読み込み中…" : (d.backgroundImage == nil ? "画像を選ぶ" : "画像を変更"))
                }
                .buttonStyle(.borderedProminent)
                if d.backgroundImage != nil {
                    Button("画像を外す") { update { $0.backgroundImage = nil } }.buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 8)
            .onChange(of: photo) { _, item in
                guard let item = item else { return }
                loading = true
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw OBDError("画像を読み込めませんでした") }
                        let name = try GaugeImages.importImage(data)
                        error = nil
                        update { x in
                            if x.backgroundImage == nil && analog {
                                // 初めて画像を付けたときは、画像が映えるように枠や下地の弧を消し、目盛りを少し内側へ
                                x.backgroundImage = name; x.showCard = false; x.ring = .NONE; x.showTrack = false
                                x.tickRadius = Swift.min(x.tickRadius, 0.85)
                            } else {
                                x.backgroundImage = name
                            }
                        }
                    } catch let e {
                        error = e.localizedDescription
                    }
                    loading = false
                    photo = nil
                }
            }
            if let e = error { Text("⚠ " + e).font(.system(size: 13)).foregroundColor(GaugeColors.warn) }
            if d.backgroundImage != nil {
                SliderLine("画像の大きさ", d.imageScale * 100, 30...200, "%.0f%%") { v in update { $0.imageScale = snap(v, 1) / 100 } }
                SliderLine("画像の横位置 (右が +)", d.imageOffsetX * 100, -50...50, "%.0f%%") { v in update { $0.imageOffsetX = snap(v, 1) / 100 } }
                SliderLine("画像の縦位置 (下が +)", d.imageOffsetY * 100, -50...50, "%.0f%%") { v in update { $0.imageOffsetY = snap(v, 1) / 100 } }
                if g.style != .LAMP {
                    Head("画像に合わせる")
                    if analog {
                        Hint("目盛りが画像の枠と重なる場合は「目盛りの位置」を、数値を画像の表示窓に入れたい場合は「数値の縦位置・横位置」を調整してください。")
                        SliderLine("目盛りの位置 (外周 = 100%)", d.tickRadius * 100, 40...110, "%.0f%%") { v in update { $0.tickRadius = snap(v, 1) / 100 } }
                    }
                    SliderLine("数値の縦位置 (中心 = 0、下が +)", d.valuePosition * 100, -90...90, "%.0f") { v in update { $0.valuePosition = snap(v, 1) / 100 } }
                    SliderLine("数値の横位置 (中心 = 0、右が +)", d.valueOffsetX * 100, -90...90, "%.0f") { v in update { $0.valueOffsetX = snap(v, 1) / 100 } }
                    SwitchLine("四角いカードの背景を表示", nil, d.showCard) { v in update { $0.showCard = v } }
                    if g.style != .DIGITAL { SwitchLine("下地の弧・バー", nil, d.showTrack) { v in update { $0.showTrack = v } } }
                }
            }
        }
    }
}
