import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 表示する項目を選ぶ。カスタム PID と標準項目を同じ一覧から選べる
struct ItemPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (PidDef) -> Void
    let onCreateCustom: () -> Void
    @State private var query = ""

    private func matches(_ d: PidDef) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        return d.name.localizedCaseInsensitiveContains(q) || d.shortName.localizedCaseInsensitiveContains(q) ||
            d.unit.localizedCaseInsensitiveContains(q) || d.key.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        let all = Pids.all.filter(matches)
        let device = all.filter { DeviceItems.isDevice($0) }
        let car = all.filter { !DeviceItems.isDevice($0) }
        let bmw = car.filter { Pids.isBmwSpecific($0) }
        let std = car.filter { !Pids.isBmwSpecific($0) }
        NavigationStack {
            List {
                Section("カスタム PID") {
                    ForEach(model.catalog.custom.filter(matches), id: \.key) { d in row(d, false) }
                    Button { onCreateCustom() } label: { Label("カスタム PID を作成", systemImage: "plus") }
                }
                Section("標準の項目") {
                    ForEach(std, id: \.key) { d in row(d, isUnsupported(d, model.supported)) }
                }
                if !bmw.isEmpty {
                    Section("BMW 固有の項目") {
                        ForEach(bmw, id: \.key) { d in row(d, isUnsupported(d, model.supported)) }
                    }
                }
                if !device.isEmpty {
                    Section("端末のセンサー (車につながなくても動く・反応の確認用)") {
                        ForEach(device, id: \.key) { d in row(d, false) }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "絞り込み (例: 温度、5A2C)")
            .navigationTitle("表示する項目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ d: PidDef, _ unsupported: Bool) -> some View {
        Button { onPick(d) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).foregroundColor(unsupported ? GaugeColors.subText : GaugeColors.text)
                Text("\(d.sourceLabel())  \(d.unit)" + (unsupported ? "  ・この車両は非対応" : ""))
                    .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            }
        }
    }
}

/// フォントの選択。ライブラリのフォントを見本付きで一覧する。「フォントを追加」で .ttf / .otf を取り込む
struct FontPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let selected: String?
    let onPick: (String?) -> Void
    @State private var importing = false
    @State private var error: String? = nil
    @State private var renaming: FontEntry? = nil
    @State private var renameText = ""
    @State private var deleting: FontEntry? = nil

    var body: some View {
        NavigationStack {
            List {
                fontRow("既定", nil, selected == nil) { onPick(nil) }
                ForEach(model.fonts) { f in
                    fontRow(f.name, GaugeFonts.postScriptName(f), selected == f.id) { onPick(f.id) }
                        .swipeActions {
                            Button("削除", role: .destructive) { deleting = f }
                            Button("名前変更") { renameText = f.name; renaming = f }
                        }
                }
                Section {
                    Button("フォントを追加 (.ttf / .otf)") { importing = true }
                    if let e = error { Text("⚠ " + e).foregroundColor(GaugeColors.warn) }
                } footer: {
                    Text("日本語を表示する場合は、日本語を含むフォントを選んでください。含まれない文字は既定のフォントで表示されます。左にスワイプで名前変更・削除できます。")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.font, .data]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let entry = try model.importFont(data, name: url.lastPathComponent)
                    error = nil
                    onPick(entry.id)
                } catch let e {
                    error = e.localizedDescription
                }
            }
            .alert("フォント名を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名前", text: $renameText)
                Button("OK") {
                    if let f = renaming {
                        let n = renameText.trimmingCharacters(in: .whitespaces)
                        model.renameFont(f.id, n.isEmpty ? f.name : n)
                    }
                    renaming = nil
                }
                Button("キャンセル", role: .cancel) { renaming = nil }
            }
            .alert("「\(deleting?.name ?? "")」を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("削除", role: .destructive) {
                    if let f = deleting {
                        if selected == f.id { onPick(nil) }
                        model.deleteFont(f.id)
                    }
                    deleting = nil
                }
                Button("キャンセル", role: .cancel) { deleting = nil }
            } message: {
                Text("このフォントを使っているメーターは既定のフォントに戻ります。")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fontRow(_ name: String, _ ps: String?, _ sel: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: sel ? "largecircle.fill.circle" : "circle").foregroundColor(GaugeColors.accent)
                VStack(alignment: .leading) {
                    Text(name).font(.system(size: 13)).foregroundColor(GaugeColors.subText)
                    Text("0123 回転数").font(ps.map { Font.custom($0, fixedSize: 22) } ?? .system(size: 22)).foregroundColor(GaugeColors.text)
                }
            }
        }
    }
}
