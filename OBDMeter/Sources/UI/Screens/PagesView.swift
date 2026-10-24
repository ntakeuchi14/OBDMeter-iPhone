import SwiftUI
import UIKit
import PhotosUI

/// ページ (ダッシュボード) の追加・名前変更・並べ替え・削除・背景
struct PagesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var nameTarget: Int64? = nil
    @State private var adding = false
    @State private var nameText = ""
    @State private var deleteTarget: Dashboard? = nil
    @State private var confirmReset = false
    @State private var backgroundFor: Int64? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("左右スワイプで切り替わるページの一覧です。「背景」でページの背景 (色・柄・画像) を変えられます。メーターの配置や見た目は、ダッシュボードの鉛筆ボタンで編集します。")
                        .font(.system(size: 13)).foregroundColor(GaugeColors.subText)
                }
                ForEach(Array(model.dashboards.enumerated()), id: \.element.id) { i, d in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(i + 1). \(d.name)").font(.system(size: 16, weight: .medium))
                        let items = d.gauges.compactMap { model.catalog.get($0.pidKey)?.shortName }.joined(separator: "・")
                        Text(items.isEmpty ? "メーターなし" : items).font(.system(size: 12)).foregroundColor(GaugeColors.subText).lineLimit(1)
                        HStack(spacing: 12) {
                            Button("背景") { backgroundFor = d.id }
                            Button("名前") { nameText = d.name; nameTarget = d.id }
                            Button { model.moveDashboard(d.id, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                            Button { model.moveDashboard(d.id, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == model.dashboards.count - 1)
                            Spacer()
                            Button(role: .destructive) { deleteTarget = d } label: { Image(systemName: "trash") }.disabled(model.dashboards.count <= 1)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button { nameText = "新しいページ"; adding = true } label: { Label("ページを追加", systemImage: "plus") }
                    Button("初期状態に戻す", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("ページ管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .alert(adding ? "ページを追加" : "名前を変更", isPresented: Binding(get: { adding || nameTarget != nil }, set: { if !$0 { adding = false; nameTarget = nil } })) {
                TextField("名前", text: $nameText)
                Button("OK") {
                    let n = nameText.trimmingCharacters(in: .whitespaces)
                    let name = n.isEmpty ? "ページ" : n
                    if adding { model.addDashboard(name) } else if let id = nameTarget { model.renameDashboard(id, name) }
                    adding = false; nameTarget = nil
                }
                Button("キャンセル", role: .cancel) { adding = false; nameTarget = nil }
            }
            .alert("「\(deleteTarget?.name ?? "")」を削除しますか？", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
                Button("削除", role: .destructive) { if let d = deleteTarget { model.deleteDashboard(d.id) }; deleteTarget = nil }
                Button("キャンセル", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("このページのメーター \(deleteTarget?.gauges.count ?? 0) 個も削除されます。")
            }
            .alert("ページとメーターを初期状態に戻しますか？", isPresented: $confirmReset) {
                Button("戻す", role: .destructive) { model.resetDashboards() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("カスタム PID の登録は消えません。")
            }
            .fullScreenCover(isPresented: Binding(get: { backgroundFor != nil }, set: { if !$0 { backgroundFor = nil } })) {
                if let id = backgroundFor, let d = model.dashboards.first(where: { $0.id == id }) {
                    PageBackgroundEditor(dashboard: d) { backgroundFor = nil }.environment(model)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// ページの背景の編集 (全画面)。変更は少し遅れて保存する
struct PageBackgroundEditor: View {
    @Environment(AppModel.self) private var model
    let dashboard: Dashboard
    let onClose: () -> Void
    @State private var bg = PageBackground()
    @State private var loaded = false
    @State private var photo: PhotosPickerItem? = nil
    @State private var loading = false
    @State private var confirmAll = false
    @State private var saveWork: DispatchWorkItem? = nil

    private func close() {
        saveWork?.cancel()
        if bg != dashboard.background { model.setPageBackground(dashboard.id, bg) }
        onClose()
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let cell = model.cellSize ?? CGSize(width: 9, height: 7)
            let ratio = Swift.min(Swift.max(Double(cell.width) * Double(Layout.COLS) / Swift.max(Double(cell.height) * Double(Layout.ROWS), 1), 0.3), 4)
            VStack(spacing: 0) {
                HStack {
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 18)) }.padding(.horizontal, 8)
                    Text("「\(dashboard.name)」の背景").font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button("完了") { close() }.buttonStyle(.borderedProminent)
                }
                .padding(8)
                if wide {
                    HStack(spacing: 0) {
                        previewView(ratio).frame(width: geo.size.width * 0.5)
                        settings
                    }
                } else {
                    previewView(ratio).frame(height: geo.size.height * 0.3)
                    settings
                }
            }
        }
        .background(GaugeColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { if !loaded { bg = dashboard.background; loaded = true } }
        .onChange(of: bg) { _, v in
            guard loaded else { return }
            saveWork?.cancel()
            let w = DispatchWorkItem { model.setPageBackground(dashboard.id, v) }
            saveWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
        }
        .alert("すべてのページにこの背景を使いますか？", isPresented: $confirmAll) {
            Button("使う") { model.applyBackgroundToAll(bg) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ほかのページの背景は、この背景に置き換わります。")
        }
    }

    private func previewView(_ ratio: Double) -> some View {
        PageBackgroundView(bg: bg)
            .aspectRatio(CGFloat(ratio), contentMode: .fit)
            .overlay(Rectangle().stroke(GaugeColors.cardBorder, lineWidth: 1))
            .padding(12)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Hint("ページのいちばん後ろに、下から 色 → 柄 → 画像 の順に重ねます。メーターは必ずこの上に表示されます。")
                Head("色")
                ColorLine("背景色 (RGB でも指定できます)", bg.color, GaugeColors.background) { c in bg.color = c }
                Head("柄")
                Chips(BgPattern.allCases.map { ($0, $0.label) }, selected: { $0 == bg.pattern }) { p in bg.pattern = p }
                if bg.pattern != .NONE {
                    let base = bg.color.map { Color(argb: $0) } ?? GaugeColors.background
                    ColorLine("柄の色 (既定 = 背景色に合わせて白か黒)", bg.patternColor, autoPatternColor(base)) { c in bg.patternColor = c }
                    SliderLine("柄の大きさ", bg.patternScale * 100, 20...600, "%.0f%%") { v in bg.patternScale = snap(v, 5) / 100 }
                    SliderLine("柄の濃さ", bg.patternAlpha * 100, 0...100, "%.0f%%") { v in bg.patternAlpha = snap(v, 1) / 100 }
                    if bg.pattern == .WOOD { Hint("木目は、背景色を茶色系にして柄の色を暗い茶色にすると木らしくなります。") }
                    if bg.pattern == .CARBON { Hint("カーボンは、黒に近い背景色に灰色の柄を 30〜60% くらいで重ねるとそれらしくなります。") }
                }
                Head("画像")
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Text(loading ? "読み込み中…" : (bg.image == nil ? "画像を選ぶ" : "画像を変更"))
                    }
                    .buttonStyle(.borderedProminent)
                    if bg.image != nil { Button("画像を外す") { bg.image = nil }.buttonStyle(.bordered) }
                }
                .padding(.vertical, 8)
                .onChange(of: photo) { _, item in
                    guard let item = item else { return }
                    loading = true
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            if let name = try? GaugeImages.importImage(data, maxSize: 2048) { bg.image = name }
                            else { model.showToast("画像を読み込めませんでした") }
                        }
                        loading = false
                        photo = nil
                    }
                }
                if bg.image != nil {
                    HStack {
                        Button("ページいっぱいに伸ばす") {
                            bg.imageX = 0.5; bg.imageY = 0.5; bg.imageWidth = 1; bg.imageHeight = 1; bg.keepAspect = false
                        }
                        .buttonStyle(.bordered)
                        Button("中央に置く") { bg.imageX = 0.5; bg.imageY = 0.5 }.buttonStyle(.bordered)
                    }
                    SliderLine("幅 (ページの幅 = 100%)", bg.imageWidth * 100, 5...300, "%.0f%%") { v in bg.imageWidth = snap(v, 1) / 100 }
                    SwitchLine("縦横比を保つ", "OFF にすると高さを別に決められます (画像が伸び縮みします)", bg.keepAspect) { v in bg.keepAspect = v }
                    if !bg.keepAspect {
                        SliderLine("高さ (ページの高さ = 100%)", bg.imageHeight * 100, 5...300, "%.0f%%") { v in bg.imageHeight = snap(v, 1) / 100 }
                    }
                    SliderLine("横の位置 (中心。左端 = 0%、右端 = 100%)", bg.imageX * 100, -50...150, "%.0f%%") { v in bg.imageX = snap(v, 1) / 100 }
                    SliderLine("縦の位置 (中心。上端 = 0%、下端 = 100%)", bg.imageY * 100, -50...150, "%.0f%%") { v in bg.imageY = snap(v, 1) / 100 }
                    SliderLine("不透明度", bg.imageAlpha * 100, 0...100, "%.0f%%") { v in bg.imageAlpha = snap(v, 1) / 100 }
                }
                Head("ほかのページ")
                Button("すべてのページにこの背景を使う") { confirmAll = true }.buttonStyle(.bordered)
                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
        }
    }
}
