import SwiftUI
import UIKit

/// カスタム PID の一覧と編集
struct CustomPidListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let startNew: Bool
    @State private var editing: CustomPid? = nil
    @State private var isNew = false
    @State private var deleting: CustomPid? = nil
    @State private var started = false

    private func newPid() -> CustomPid {
        var p = CustomPid()
        p.id = 0
        p.name = ""
        p.mode = "22"
        p.header = "7E0"
        p.formula = "A"
        return p
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("標準にない値 (メーカー独自の値など) を、モード・PID と換算式を指定して読み出します。登録した項目は、メーター追加の一覧に「カスタム PID」として出てきます。")
                        .font(.system(size: 13)).foregroundColor(GaugeColors.subText)
                }
                ForEach(model.customPids) { p in
                    let error = p.validate()
                    Button { isNew = false; editing = p } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name.isEmpty ? "(名前なし)" : p.name).foregroundColor(GaugeColors.text)
                            Text("Mode \(p.mode)  PID \(p.pid)" + (p.header.isEmpty ? "" : "  @\(p.header)") + "   式: \(p.formula)   \(p.unit)")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(GaugeColors.subText)
                            if let e = error { Text("⚠ " + e).font(.system(size: 12)).foregroundColor(GaugeColors.warn) }
                        }
                    }
                    .swipeActions {
                        Button("削除", role: .destructive) { deleting = p }
                        Button("複製") {
                            var c = p
                            c.id = 0
                            c.name = p.name + " のコピー"
                            isNew = true
                            editing = c
                        }
                    }
                }
                if model.customPids.isEmpty {
                    Text("まだ登録されていません").foregroundColor(GaugeColors.subText)
                }
                Section {
                    Button { isNew = true; editing = newPid() } label: { Label("カスタム PID を追加", systemImage: "plus") }
                } footer: {
                    Text("左にスワイプで複製・削除できます。")
                }
            }
            .navigationTitle("カスタム PID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
            .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let p = editing {
                    CustomPidEditor(initial: p, isNew: isNew, onSave: { saved in
                        var s = saved
                        if s.id == 0 { s.id = model.newId() }
                        model.saveCustomPid(s)
                        editing = nil
                    }, onDelete: { model.deleteCustomPid(p.id); editing = nil })
                    .environment(model)
                }
            }
            .alert("「\(deleting?.name ?? "")」を削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("削除", role: .destructive) { if let p = deleting { model.deleteCustomPid(p.id) }; deleting = nil }
                Button("キャンセル", role: .cancel) { deleting = nil }
            } message: {
                Text("この項目を表示しているメーターも削除されます。")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if startNew && !started { started = true; isNew = true; editing = newPid() }
        }
    }
}

struct CustomPidEditor: View {
    @Environment(AppModel.self) private var model
    let initial: CustomPid
    let isNew: Bool
    let onSave: (CustomPid) -> Void
    let onDelete: () -> Void

    @State private var p = CustomPid()
    @State private var minText = ""
    @State private var maxText = ""
    @State private var warnAboveText = ""
    @State private var warnBelowText = ""
    @State private var loaded = false
    @State private var testResult: String? = nil
    @State private var testing = false
    @State private var confirmDelete = false

    private var candidate: CustomPid {
        var c = p
        c.min = Double(minText) ?? 0
        c.max = Double(maxText) ?? 100
        c.warnAbove = Double(warnAboveText)
        c.warnBelow = Double(warnBelowText)
        return c
    }

    private var formError: String? {
        if p.name.trimmingCharacters(in: .whitespaces).isEmpty { return "名前を入力してください" }
        if Double(minText) == nil || Double(maxText) == nil { return "最小・最大を数値で入力してください" }
        return candidate.validate()
    }

    var body: some View {
        Form {
            Section("名前") {
                TextField("名前 (例: 油温 BMW)", text: $p.name)
                TextField("短い名前 (メーターに表示。空欄で名前の先頭)", text: $p.shortName)
                TextField("単位 (例: °C)", text: $p.unit)
            }
            Section {
                HStack {
                    Text("モード").frame(width: 90, alignment: .leading)
                    TextField("22", text: $p.mode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                HStack {
                    Text("PID / DID").frame(width: 90, alignment: .leading)
                    TextField("例: 4205", text: $p.pid).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                HStack {
                    Text("ヘッダー").frame(width: 90, alignment: .leading)
                    TextField("例: 7E0 (空欄で既定)", text: $p.header).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                HStack {
                    Text("拡張アドレス").frame(width: 90, alignment: .leading)
                    TextField("例: 12 (BMW 6F1 方式。空欄で使わない)", text: $p.canExtAddress).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
            } header: {
                Text("問い合わせ")
            } footer: {
                Text("16 進数で入力します。Mode 01 の標準 PID は「01」「0C」のように、BMW の DME の DID は「22」「4205」とヘッダー「7E0」のように指定します。")
            }
            Section {
                TextField("A", text: $p.formula).font(.system(.body, design: .monospaced)).textInputAutocapitalization(.characters).autocorrectionDisabled()
            } header: {
                Text("換算式")
            } footer: {
                Text("応答データの 1 バイト目を A、2 バイト目を B … として書きます。例: (A*256+B)/4、A-40、signed(A)*0.5、signed16(A*256+B)/10、bit(A,3)。関数: abs min max signed signed16 bit round floor。")
            }
            Section("表示") {
                HStack {
                    Text("最小")
                    TextField("0", text: $minText).keyboardType(.numbersAndPunctuation)
                    Text("最大")
                    TextField("100", text: $maxText).keyboardType(.numbersAndPunctuation)
                }
                Picker("小数点以下の桁数", selection: $p.decimals) {
                    ForEach(0...3, id: \.self) { n in Text("\(n)").tag(n) }
                }
                HStack {
                    Text("警告 下限")
                    TextField("なし", text: $warnBelowText).keyboardType(.numbersAndPunctuation)
                    Text("上限")
                    TextField("なし", text: $warnAboveText).keyboardType(.numbersAndPunctuation)
                }
                Toggle(isOn: $p.slow) {
                    VStack(alignment: .leading) {
                        Text("変化が遅い値")
                        Text("温度など。読む頻度を下げて、ほかのメーターの更新を速くします").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                    }
                }
            }
            Section {
                Button(testing ? "読み出し中…" : "車両から 1 回読んでみる") {
                    testing = true
                    testResult = nil
                    let c = candidate
                    model.testCustomPid(c) { r in
                        testing = false
                        if let d = r.data {
                            var t = "応答: " + Hex.of(d)
                            if let def = try? c.toDef(), let v = def.decode(d) { t += "\n換算値: " + def.format(v) + " " + def.unit }
                            else { t += "\n換算できませんでした (式とバイト数を確認してください)" }
                            testResult = t
                        } else {
                            testResult = "✗ " + (r.error ?? "応答なし")
                        }
                    }
                }
                .disabled(testing || formError != nil)
                if let t = testResult { Text(t).font(.system(size: 13, design: .monospaced)) }
            } footer: {
                Text("ダッシュボードで「接続」してから試してください。")
            }
            if let e = formError {
                Section { Text("⚠ " + e).foregroundColor(GaugeColors.warn) }
            }
            if !isNew {
                Section { Button("削除", role: .destructive) { confirmDelete = true } }
            }
        }
        .navigationTitle(isNew ? "カスタム PID を追加" : "カスタム PID を編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { onSave(candidate) }.disabled(formError != nil)
            }
        }
        .alert("「\(initial.name)」を削除しますか？", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) { onDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この項目を表示しているメーターも削除されます。")
        }
        .onAppear {
            if loaded { return }
            loaded = true
            p = initial
            minText = fmtNumber(initial.min)
            maxText = fmtNumber(initial.max)
            warnAboveText = initial.warnAbove.map { fmtNumber($0) } ?? ""
            warnBelowText = initial.warnBelow.map { fmtNumber($0) } ?? ""
        }
    }
}

/// 送受信の生データを表示する (実車でうまく動かないときの調査用)
struct LogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [LogBuffer.Line] = []
    @State private var version = -1
    @State private var follow = true
    @State private var shareText: String? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(lines) { l in
                    HStack(alignment: .top, spacing: 4) {
                        Text(String(l.time.dropFirst(3)) + " " + l.direction.rawValue.padRight(5))
                            .foregroundColor(GaugeColors.subText)
                        Text(l.text).foregroundColor(color(l.direction))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                    .id(l.id)
                }
                .listStyle(.plain)
                .onChange(of: version) { _, _ in
                    if follow, let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .navigationTitle("通信ログ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("自動スクロール", isOn: $follow).toggleStyle(.button)
                    Button { shareText = model.log.asText() } label: { Image(systemName: "square.and.arrow.up") }
                    Button { model.log.clear() } label: { Image(systemName: "trash") }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            while !Task.isCancelled {
                if let snap = model.log.snapshot(since: version) {
                    lines = snap.1
                    version = snap.0
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            ShareSheet(items: [shareText ?? ""])
        }
    }

    private func color(_ d: LogDirection) -> Color {
        switch d {
        case .TX: return GaugeColors.accent
        case .RX: return Color(argb: 0xFF81C784)
        case .INFO: return GaugeColors.text
        case .ERROR: return GaugeColors.warn
        }
    }
}
