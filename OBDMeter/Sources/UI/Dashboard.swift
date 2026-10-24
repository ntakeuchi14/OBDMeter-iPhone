import SwiftUI
import UIKit

/// メーターごとの表示用の状態を持つ (本体と針の層で共有)
final class RuntimeStore {
    private var map: [Int64: GaugeRuntime] = [:]
    func get(_ id: Int64) -> GaugeRuntime {
        if let r = map[id] { return r }
        let r = GaugeRuntime()
        map[id] = r
        return r
    }
}

enum AppSheet: Identifiable {
    case settings, log, pages, customPids, customPidNew, picker
    var id: Int {
        switch self {
        case .settings: return 1
        case .log: return 2
        case .pages: return 3
        case .customPids: return 4
        case .customPidNew: return 5
        case .picker: return 6
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var pageIndex = 0
    @State private var editing = false
    @State private var settingsFor: Int64? = nil
    @State private var sheet: AppSheet? = nil
    @State private var selecting = false
    @State private var selected = Set<Int64>()
    @State private var barsShown = false
    @State private var barsTimer: DispatchWorkItem? = nil
    @State private var peakResets: [Int64: Int] = [:]
    @State private var runtimes = RuntimeStore()
    @State private var slideFromRight = true

    private var current: Dashboard? { model.dashboards[safe: pageIndex] }

    var body: some View {
        let pinned = model.settings.alwaysShowToolbar
        ZStack {
            GaugeColors.background.ignoresSafeArea()
            if pinned {
                VStack(spacing: 0) {
                    topBar
                    pageArea
                    bottomBar
                }
            } else {
                pageArea
                if editing {
                    VStack(spacing: 0) {
                        topBar.background(GaugeColors.background.opacity(0.85))
                        Spacer()
                        bottomBar.background(GaugeColors.background.opacity(0.85))
                    }
                } else if barsShown {
                    Color.black.opacity(0.001).onTapGesture { barsShown = false }
                    VStack(spacing: 0) {
                        topBar.background(GaugeColors.background.opacity(0.92))
                        Spacer()
                        bottomBar.background(GaugeColors.background.opacity(0.92))
                    }
                } else {
                    VStack {
                        HStack {
                            Spacer()
                            MenuButton(state: model.connection) { showBars() }
                        }
                        Spacer()
                    }
                    .padding(.top, 8).padding(.trailing, 12)
                }
            }
            if let t = model.toast {
                VStack {
                    Spacer()
                    Text(t)
                        .font(.system(size: 14))
                        .foregroundColor(GaugeColors.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 40)
                }
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if let id = model.appPage, let i = model.dashboards.firstIndex(where: { $0.id == id }) { pageIndex = i }
            model.setActivePage(current?.id)
        }
        .onChange(of: pageIndex) { _, _ in
            selecting = false
            selected = []
            model.setActivePage(current?.id)
        }
        .onChange(of: model.dashboards.count) { _, n in
            if pageIndex >= n { pageIndex = Swift.max(0, n - 1) }
            model.setActivePage(current?.id)
        }
        .onChange(of: editing) { _, _ in selecting = false; selected = [] }
        .sheet(item: $sheet) { s in sheetContent(s) }
        .fullScreenCover(isPresented: Binding(get: { settingsFor != nil && editorGauge != nil }, set: { if !$0 { settingsFor = nil } })) {
            if let d = current, let g = editorGauge {
                GaugeEditorView(dashboardId: d.id, initial: g, onClose: { settingsFor = nil },
                                onCreateCustomPid: { settingsFor = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .customPidNew } })
                    .environment(model)
            }
        }
    }

    private var editorGauge: GaugeConfig? {
        guard let id = settingsFor else { return nil }
        return current?.gauges.first { $0.id == id }
    }

    private func showBars() {
        barsShown = true
        barsTimer?.cancel()
        let w = DispatchWorkItem { barsShown = false }
        barsTimer = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }

    @ViewBuilder
    private func sheetContent(_ s: AppSheet) -> some View {
        switch s {
        case .settings: SettingsView(onOpenCustomPids: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .customPids } }).environment(model)
        case .log: LogView().environment(model)
        case .pages: PagesView().environment(model)
        case .customPids: CustomPidListView(startNew: false).environment(model)
        case .customPidNew: CustomPidListView(startNew: true).environment(model)
        case .picker:
            ItemPickerView(onPick: { def in
                if let d = current {
                    model.addGauge(d.id, def.key, defaultStyleFor(def))
                    editing = true
                }
                sheet = nil
            }, onCreateCustom: {
                sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .customPidNew }
            }).environment(model)
        }
    }

    // MARK: - ページ

    private var pageArea: some View {
        ZStack {
            if let d = current {
                DashboardPage(dashboard: d, editing: editing, selecting: selecting, selected: selected,
                              runtimes: runtimes, peakResets: peakResets,
                              onTap: { g in if editing { settingsFor = g.id } },
                              onLongPress: { g in peakResets[g.id] = (peakResets[g.id] ?? 0) + 1 },
                              onCopy: { g in
                                  let group = Layout.groups(d.gauges)[g.layoutGroup ?? -1]
                                  if let gr = group { model.copyGauges(gr) } else { model.copyGauge(g) }
                                  model.showToast((group != nil ? "グループ (\(group!.count) 個) を" : "") + "コピーしました。下の「貼り付け」で、このページや別のページに貼り付けられます")
                              },
                              onToggleSelect: { g in
                                  let ids = Set(Layout.groups(d.gauges)[g.layoutGroup ?? -1]?.map { $0.id } ?? [g.id])
                                  if selected.contains(g.id) { selected.subtract(ids) } else { selected.formUnion(ids) }
                              })
                    .id(d.id)
                    .transition(.asymmetric(insertion: .move(edge: slideFromRight ? .trailing : .leading),
                                            removal: .move(edge: slideFromRight ? .leading : .trailing)))
            } else {
                Text("ページがありません").foregroundColor(GaugeColors.subText)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            guard !editing, model.dashboards.count > 1 else { return }
            let dx = v.translation.width, dy = v.translation.height
            if Swift.abs(dx) > Swift.abs(dy) * 1.5 && Swift.abs(dx) > 60 { goPage(dx < 0 ? 1 : -1, wrap: true) }
        }, including: editing ? .subviews : .all)
    }

    private func goPage(_ delta: Int, wrap: Bool) {
        let n = model.dashboards.count
        if n <= 1 { return }
        var next = pageIndex + delta
        if wrap { next = ((next % n) + n) % n } else { next = Swift.min(Swift.max(next, 0), n - 1) }
        if next == pageIndex { return }
        slideFromRight = delta > 0
        withAnimation(.easeInOut(duration: 0.25)) { pageIndex = next }
    }

    // MARK: - バー

    private var topBar: some View {
        HStack(spacing: 8) {
            if editing && selecting {
                Text("グループにするメーターをタップして選んでください (グループのメーターはまとめて選ばれます)")
                    .font(.system(size: 13)).foregroundColor(GaugeColors.peak).lineLimit(2)
                Spacer(minLength: 0)
            } else if editing {
                Text("レイアウト編集中: ドラッグで移動、右下の ◢ でサイズ変更、タップで設定、右上の ▲▼ で重なり順、長押しでコピー")
                    .font(.system(size: 12)).foregroundColor(GaugeColors.accent).lineLimit(2)
                Spacer(minLength: 0)
                Menu {
                    ForEach(Layout.GRID_STEPS.indices, id: \.self) { i in
                        let step = Layout.GRID_STEPS[i].0
                        Button((step == model.settings.gridStep ? "✓ " : "") + Layout.GRID_STEPS[i].1 + "ごとに吸着") {
                            model.updateSettings { $0.gridStep = step }
                        }
                    }
                } label: {
                    Text("グリッド " + (Layout.GRID_STEPS.first { $0.0 == model.settings.gridStep }?.1 ?? ""))
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                Button { editing = false } label: { Label("完了", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
            } else {
                StatusIndicator(state: model.connection, rate: model.rate)
                Spacer(minLength: 0)
                Text(modeLabel).font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                if model.connection.isDisconnected {
                    Button("接続") { model.connect() }.buttonStyle(.borderedProminent)
                } else {
                    Button("切断") { model.disconnect() }.buttonStyle(.bordered)
                }
                barIcon("pencil", "レイアウト編集") { editing = true; barsShown = false }
                barIcon("list.bullet.rectangle", "通信ログ") { sheet = .log }
                barIcon("gearshape", "設定") { sheet = .settings }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var modeLabel: String {
        switch model.settings.connectionType {
        case .SIMULATOR: return "SIM"
        case .BLE: return "BLE"
        case .WIFI: return "Wi-Fi"
        }
    }

    private func barIcon(_ name: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 22)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if editing {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.dashboards.count > 1 {
                        Button("◀") { goPage(-1, wrap: false) }.disabled(pageIndex <= 0)
                    }
                    Text(current?.name ?? "").font(.system(size: 15, weight: .bold)).lineLimit(1)
                    if model.dashboards.count > 1 {
                        Button("▶") { goPage(1, wrap: false) }.disabled(pageIndex >= model.dashboards.count - 1)
                    }
                    if selecting {
                        let groupedSelected = current?.gauges.contains { selected.contains($0.id) && $0.layoutGroup != nil } == true
                        Button("グループにする (\(selected.count))") {
                            if let d = current { model.groupGauges(d.id, selected) }
                            selecting = false; selected = []
                        }
                        .buttonStyle(.borderedProminent).disabled(selected.count < 2)
                        Button("グループ解除") {
                            if let d = current { model.ungroupGauges(d.id, selected) }
                            selecting = false; selected = []
                        }
                        .buttonStyle(.bordered).disabled(!groupedSelected)
                        Button("やめる") { selecting = false; selected = [] }.buttonStyle(.bordered)
                    } else {
                        Button("グループ") { selecting = true; selected = [] }.buttonStyle(.bordered).disabled(current == nil)
                        if model.clipboard != nil {
                            Button("貼り付け") { if let d = current { model.pasteGauge(d.id) } }.buttonStyle(.borderedProminent)
                        }
                        Button { sheet = .picker } label: { Label("メーター追加", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).disabled(current == nil)
                        Menu {
                            ForEach(1...4, id: \.self) { c in
                                Button("\(c) 列で均等に並べる") { if let d = current { model.arrangeInGrid(d.id, c) } }
                            }
                        } label: { Text("並べ直す") }
                        .buttonStyle(.bordered)
                        Button("ページ管理") { sheet = .pages }.buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        } else if model.dashboards.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.dashboards.enumerated()), id: \.element.id) { i, d in
                        let sel = i == pageIndex
                        Text(d.name)
                            .font(.system(size: 13, weight: sel ? .bold : .regular))
                            .foregroundColor(sel ? GaugeColors.text : GaugeColors.subText)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(sel ? GaugeColors.cardBorder : Color.clear, in: Capsule())
                            .onTapGesture { goPage(i - pageIndex, wrap: false) }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
        }
    }
}

/// 通常時に右上に出す小さなボタン。接続状態の色の点付き
private struct MenuButton: View {
    let state: ConnectionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(GaugeColors.text.opacity(0.8))
                    .frame(width: 52, height: 52)
                    .background(GaugeColors.card.opacity(0.55), in: Circle())
                Circle().fill(statusColor(state)).frame(width: 12, height: 12).padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

func statusColor(_ state: ConnectionState) -> Color {
    switch state {
    case .disconnected: return GaugeColors.subText
    case .connecting: return Color(argb: 0xFFFFC107)
    case .connected: return Color(argb: 0xFF4CAF50)
    case .waitingForVehicle: return Color(argb: 0xFF64B5F6)
    case .error: return GaugeColors.warn
    }
}

struct StatusIndicator: View {
    let state: ConnectionState
    let rate: Double

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor(state)).frame(width: 10, height: 10)
            Text(text).font(.system(size: 13)).foregroundColor(GaugeColors.text).lineLimit(2)
        }
    }

    private var text: String {
        switch state {
        case .disconnected: return "未接続"
        case .connecting(let m): return m
        case .connected(_, let off):
            return off ? "接続中 (イグニッション OFF: エンジンの値は ON で表示)" : String(format: "接続中  %.1f PID/s", rate)
        case .waitingForVehicle(_, let v):
            return "車両の応答待ち (イグニッション ON で自動開始)" + (v.map { String(format: "  バッテリー %.1fV", $0) } ?? "")
        case .error(let m, let retrying): return m + (retrying ? "  (再接続待ち)" : "")
        }
    }
}

// MARK: - 1 ページ分

/// メーターを COLS × ROWS のマス目に配置して描く。編集モードではドラッグで移動、右下のつまみでサイズ変更
struct DashboardPage: View {
    @Environment(AppModel.self) private var model
    let dashboard: Dashboard
    let editing: Bool
    let selecting: Bool
    let selected: Set<Int64>
    let runtimes: RuntimeStore
    let peakResets: [Int64: Int]
    let onTap: (GaugeConfig) -> Void
    let onLongPress: (GaugeConfig) -> Void
    let onCopy: (GaugeConfig) -> Void
    let onToggleSelect: (GaugeConfig) -> Void

    @State private var groupMove: (Int64, CGSize)? = nil
    @State private var groupResize: (Int64, CGSize)? = nil
    @State private var groupPending: [Int64: [Int]]? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            PageBackgroundView(bg: dashboard.background).ignoresSafeArea()
            GeometryReader { geo in
                let cellW = Double(geo.size.width) / Double(Layout.COLS)
                let cellH = Double(geo.size.height) / Double(Layout.ROWS)
                let groups = Layout.groups(dashboard.gauges)
                let preview = groupPreview(groups, cellW, cellH)
                ZStack(alignment: .topLeading) {
                    if editing { gridDots(cellW, cellH) }
                    if dashboard.gauges.isEmpty {
                        Text(editing ? "下の「メーター追加」から追加してください" : "メーターがありません。右上のボタン → 鉛筆ボタンから追加してください")
                            .foregroundColor(GaugeColors.subText)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    ForEach(dashboard.gauges) { g in
                        let gid = g.layoutGroup.flatMap { groups[$0] != nil ? $0 : nil }
                        GaugeOnGrid(gauge: g, cellW: cellW, cellH: cellH, editing: editing, selecting: selecting,
                                    selected: selected.contains(g.id), grouped: gid != nil, override: preview[g.id],
                                    gridStep: model.settings.gridStep,
                                    onCommit: { x, y, w, h in model.updateGauge(dashboard.id, g.id) { $0.x = x; $0.y = y; $0.w = w; $0.h = h } },
                                    onTap: { onTap(g) }, onLongPress: { onLongPress(g) }, onCopy: { onCopy(g) },
                                    onToggleSelect: { onToggleSelect(g) },
                                    onGroupDrag: { t in if let id = gid { groupMove = (id, t) } },
                                    onGroupDragEnd: { commitGroup(groups, cellW, cellH) },
                                    onMoveZ: { delta in model.moveZ(dashboard.id, g.id, delta) }) {
                            GaugeView(g: g, pageId: dashboard.id, runtime: runtimes.get(g.id), interactive: !editing,
                                      peakReset: peakResets[g.id] ?? 0, needleSeparate: g.style == .ANALOG)
                        }
                    }
                    // アナログの針は、ほかのメーター (中に重ねて置いたものも) より手前に描く
                    ForEach(dashboard.gauges.filter { $0.style == .ANALOG }) { g in
                        let r = preview[g.id] ?? [g.x, g.y, g.w, g.h]
                        GaugeView(g: g, pageId: dashboard.id, runtime: runtimes.get(g.id), interactive: false, peakReset: 0,
                                  layer: .needle)
                            .padding(3)
                            .frame(width: CGFloat(Double(r[2]) * cellW), height: CGFloat(Double(r[3]) * cellH))
                            .offset(x: CGFloat(Double(r[0]) * cellW), y: CGFloat(Double(r[1]) * cellH))
                            .allowsHitTesting(false)
                    }
                    if editing && !selecting {
                        ForEach(Array(groups.keys).sorted(), id: \.self) { gid in
                            groupBox(gid, groups[gid] ?? [], preview, cellW, cellH, groups)
                        }
                    }
                }
                .onAppear { model.cellSize = CGSize(width: cellW, height: cellH) }
                .onChange(of: geo.size) { _, s in
                    model.cellSize = CGSize(width: Double(s.width) / Double(Layout.COLS), height: Double(s.height) / Double(Layout.ROWS))
                }
            }
            .padding(4)
        }
        .clipped()
        .onChange(of: dashboard.gauges) { _, _ in groupPending = nil }
    }

    private func gridDots(_ cellW: Double, _ cellH: Double) -> some View {
        Canvas { ctx, _ in
            var step = Swift.max(model.settings.gridStep, 1)
            while Double(step) * cellW < 6 && step < Layout.COLS { step *= 2 }
            var major = Path()
            var minor = Path()
            for x in stride(from: 0, through: Layout.COLS, by: step) {
                for y in stride(from: 0, through: Layout.ROWS, by: step) {
                    let isMajor = x % Layout.SCALE == 0 && y % Layout.SCALE == 0
                    let r = isMajor ? 2.0 : 1.2
                    let rect = CGRect(x: Double(x) * cellW - r, y: Double(y) * cellH - r, width: r * 2, height: r * 2)
                    if isMajor { major.addEllipse(in: rect) } else { minor.addEllipse(in: rect) }
                }
            }
            ctx.fill(major, with: .color(GaugeColors.cardBorder))
            ctx.fill(minor, with: .color(GaugeColors.cardBorder))
        }
        .allowsHitTesting(false)
    }

    /// グループをドラッグ中 (または確定待ち) の各メーターの配置
    private func groupPreview(_ groups: [Int64: [GaugeConfig]], _ cellW: Double, _ cellH: Double) -> [Int64: [Int]] {
        if let p = groupPending { return p }
        let step = model.settings.gridStep
        if let gm = groupMove, let members = groups[gm.0] {
            let o = gm.1
            let b = Layout.bounds(members)
            let dx = o.width != 0 ? Layout.snap(b[0] + Int((Double(o.width) / cellW).rounded()), step) - b[0] : 0
            let dy = o.height != 0 ? Layout.snap(b[1] + Int((Double(o.height) / cellH).rounded()), step) - b[1] : 0
            return Layout.moveGroup(members, dx, dy)
        }
        if let gr = groupResize, let members = groups[gr.0] {
            let o = gr.1
            let b = Layout.bounds(members)
            let nw = o.width != 0 ? Layout.snap(b[0] + b[2] + Int((Double(o.width) / cellW).rounded()), step) - b[0] : b[2]
            let nh = o.height != 0 ? Layout.snap(b[1] + b[3] + Int((Double(o.height) / cellH).rounded()), step) - b[1] : b[3]
            return Layout.resizeGroup(members, nw, nh)
        }
        return [:]
    }

    private func commitGroup(_ groups: [Int64: [GaugeConfig]], _ cellW: Double, _ cellH: Double) {
        let p = groupPreview(groups, cellW, cellH)
        groupMove = nil
        groupResize = nil
        var changed: [Int64: [Int]] = [:]
        for (id, r) in p {
            if let g = dashboard.gauges.first(where: { $0.id == id }), g.x != r[0] || g.y != r[1] || g.w != r[2] || g.h != r[3] {
                changed[id] = r
            }
        }
        if !changed.isEmpty {
            groupPending = p
            model.placeGauges(dashboard.id, changed)
        }
    }

    private func groupBox(_ gid: Int64, _ members: [GaugeConfig], _ preview: [Int64: [Int]], _ cellW: Double, _ cellH: Double,
                          _ groups: [Int64: [GaugeConfig]]) -> some View {
        let rs = members.map { preview[$0.id] ?? [$0.x, $0.y, $0.w, $0.h] }
        let x0 = rs.map { $0[0] }.min() ?? 0, y0 = rs.map { $0[1] }.min() ?? 0
        let x1 = rs.map { $0[0] + $0[2] }.max() ?? 0, y1 = rs.map { $0[1] + $0[3] }.max() ?? 0
        let active = groupMove?.0 == gid || groupResize?.0 == gid
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? GaugeColors.warn : GaugeColors.peak, style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .allowsHitTesting(false)
            Text("グループ").font(.system(size: 11, weight: .bold)).foregroundColor(GaugeColors.background)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(GaugeColors.peak, in: Capsule())
                .padding(4)
                .allowsHitTesting(false)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ResizeHandle(color: GaugeColors.peak)
                        .gesture(DragGesture(minimumDistance: 2)
                            .onChanged { v in groupResize = (gid, v.translation) }
                            .onEnded { _ in commitGroup(groups, cellW, cellH) })
                }
            }
        }
        .frame(width: CGFloat(Double(x1 - x0) * cellW), height: CGFloat(Double(y1 - y0) * cellH))
        .offset(x: CGFloat(Double(x0) * cellW), y: CGFloat(Double(y0) * cellH))
    }
}

/// サイズ変更のつまみ (右下の三角)
struct ResizeHandle: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: size.width - 4, y: 10))
            p.addLine(to: CGPoint(x: size.width - 4, y: size.height - 4))
            p.addLine(to: CGPoint(x: 10, y: size.height - 4))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
}

/// マス目の上のメーター 1 個 (編集中のドラッグ・大きさ変更を含む)
struct GaugeOnGrid<Content: View>: View {
    let gauge: GaugeConfig
    let cellW: Double
    let cellH: Double
    let editing: Bool
    let selecting: Bool
    let selected: Bool
    let grouped: Bool
    let override: [Int]?
    let gridStep: Int
    let onCommit: (Int, Int, Int, Int) -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onCopy: () -> Void
    let onToggleSelect: () -> Void
    let onGroupDrag: (CGSize) -> Void
    let onGroupDragEnd: () -> Void
    let onMoveZ: (Int) -> Void
    @ViewBuilder let content: () -> Content

    @State private var move: CGSize = .zero
    @State private var resize: CGSize = .zero
    @State private var pending: [Int]? = nil

    private func preview() -> [Int] {
        if let o = override { return o }
        if let p = pending { return p }
        let g = gauge
        let x = move.width != 0 ? Layout.snap(g.x + Int((Double(move.width) / cellW).rounded()), gridStep) : g.x
        let y = move.height != 0 ? Layout.snap(g.y + Int((Double(move.height) / cellH).rounded()), gridStep) : g.y
        let w = resize.width != 0 ? Layout.snap(g.x + g.w + Int((Double(resize.width) / cellW).rounded()), gridStep) - g.x : g.w
        let h = resize.height != 0 ? Layout.snap(g.y + g.h + Int((Double(resize.height) / cellH).rounded()), gridStep) - g.y : g.h
        return Layout.clampPlacement(x, y, w, h)
    }

    var body: some View {
        let r = preview()
        let dragging = move != .zero || resize != .zero || override != nil
        ZStack {
            content()
            if editing { editOverlay(dragging) }
        }
        .padding(3)
        .frame(width: CGFloat(Double(r[2]) * cellW), height: CGFloat(Double(r[3]) * cellH))
        .contentShape(Rectangle())
        .modifier(GestureModifier(editing: editing, selecting: selecting, onTap: onTap, onLongPress: onLongPress, onCopy: onCopy,
                                  onToggleSelect: onToggleSelect, drag: dragGesture))
        .offset(x: CGFloat(Double(r[0]) * cellW), y: CGFloat(Double(r[1]) * cellH))
        .onChange(of: [gauge.x, gauge.y, gauge.w, gauge.h]) { _, _ in pending = nil }
    }

    private var dragGesture: AnyGesture<Void> {
        AnyGesture(DragGesture(minimumDistance: 4)
            .onChanged { v in
                if grouped { onGroupDrag(v.translation) } else { move = v.translation }
            }
            .onEnded { _ in
                if grouped { onGroupDragEnd(); return }
                let p = preview()
                pending = p
                move = .zero
                if p[0] != gauge.x || p[1] != gauge.y { onCommit(p[0], p[1], p[2], p[3]) } else { pending = nil }
            }
            .map { _ in () })
    }

    @ViewBuilder
    private func editOverlay(_ dragging: Bool) -> some View {
        if selecting {
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? GaugeColors.peak : GaugeColors.cardBorder, lineWidth: selected ? 4 : 2)
                .allowsHitTesting(false)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(GaugeColors.background)
                    .frame(width: 36, height: 36)
                    .background(GaugeColors.peak, in: Circle())
                    .allowsHitTesting(false)
            }
        } else {
            RoundedRectangle(cornerRadius: 14)
                .stroke(dragging ? GaugeColors.warn : GaugeColors.accent, lineWidth: 2)
                .allowsHitTesting(false)
            VStack {
                HStack(spacing: 4) {
                    Spacer()
                    zButton("▲", Int.max)
                    zButton("▼", Int.min)
                }
                Spacer()
                if !grouped {
                    HStack {
                        Spacer()
                        ResizeHandle(color: GaugeColors.accent)
                            .highPriorityGesture(DragGesture(minimumDistance: 2)
                                .onChanged { v in resize = v.translation }
                                .onEnded { _ in
                                    let p = preview()
                                    pending = p
                                    resize = .zero
                                    if p[2] != gauge.w || p[3] != gauge.h { onCommit(p[0], p[1], p[2], p[3]) } else { pending = nil }
                                })
                    }
                }
            }
            .padding(4)
        }
    }

    private func zButton(_ label: String, _ delta: Int) -> some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(GaugeColors.accent)
            .frame(width: 30, height: 30)
            .background(GaugeColors.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(GaugeColors.accent, lineWidth: 1))
            .highPriorityGesture(TapGesture().onEnded { onMoveZ(delta) })
    }
}

/// 編集中かどうかで付けるジェスチャーを変える
private struct GestureModifier: ViewModifier {
    let editing: Bool
    let selecting: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onCopy: () -> Void
    let onToggleSelect: () -> Void
    let drag: AnyGesture<Void>

    @ViewBuilder
    func body(content: Content) -> some View {
        if editing && selecting {
            content.onTapGesture { onToggleSelect() }
        } else if editing {
            content
                .onTapGesture { onTap() }
                .onLongPressGesture(minimumDuration: 0.6) { onCopy() }
                .gesture(drag)
        } else {
            content.onLongPressGesture(minimumDuration: 0.6) { onLongPress() }
        }
    }
}

/// メーター 1 つ (ダッシュボードと編集画面で共通)
struct GaugeView: View {
    @Environment(AppModel.self) private var model
    let g: GaugeConfig
    let pageId: Int64
    let runtime: GaugeRuntime
    var interactive = false
    var peakReset = 0
    var layer: GaugeLayer = .all
    var needleSeparate = false

    var body: some View {
        if let def = g.resolvedDef(model.catalog) {
            let look = g.look(def) { model.fontName($0) }
            let multi = g.style == .CHART || g.style == .TABLE || g.style == .MONITOR
            let key = def.key
            let fb = g.fallbackKey
            let input = GaugeInput(def: def, style: g.style, look: look,
                                   unsupported: isUnsupported(def, model.supported) && g.fallbackKey == nil,
                                   series: multi ? chartSeries(g, def, model.values, model.catalog) : [],
                                   slot: HistorySlot.of(pageId, g.id), interactive: interactive)
            let m = model
            GaugeCardView(input: input, runtime: runtime,
                          valueSource: { m.values[key] ?? fb.flatMap { m.values[$0] } },
                          layer: layer, peakResetKey: peakReset, needleSeparate: needleSeparate)
        } else if layer != .needle {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(GaugeColors.card)
                Text("項目が見つかりません\n(\(g.pidKey))").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
