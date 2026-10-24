import SwiftUI
import UIKit
import UniformTypeIdentifiers

let ELM_PROTOCOLS: [(String, String)] = [
    ("0", "自動判別"),
    ("6", "ISO 15765-4 CAN 11bit 500k (2007/03 以降の E90)"),
    ("5", "ISO 14230-4 KWP 高速初期化 (2007/03 以前の E90)"),
    ("4", "ISO 14230-4 KWP 5baud 初期化"),
    ("3", "ISO 9141-2"),
]

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onOpenCustomPids: () -> Void

    @State private var devices: [BleDevice] = []
    @State private var scanning = false
    @State private var shareURL: URL? = nil
    @State private var importing = false
    @State private var hostText = ""
    @State private var portText = ""
    @State private var loaded = false

    private func upd(_ f: (inout AppSettings) -> Void) { model.updateSettings(f) }

    var body: some View {
        let s = model.settings
        NavigationStack {
            Form {
                if !model.connection.isDisconnected {
                    Section {
                        HStack {
                            Text("変更は次の接続から反映されます").foregroundColor(GaugeColors.subText)
                            Spacer()
                            Button("再接続") { model.connect() }.buttonStyle(.borderedProminent)
                        }
                    }
                }

                Section("表示項目") {
                    Button { onOpenCustomPids() } label: {
                        VStack(alignment: .leading) {
                            Text("カスタム PID").foregroundColor(GaugeColors.text)
                            Text("標準にない値を、モード・PID と換算式で登録 (登録済み \(model.customPids.count) 件)")
                                .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                        }
                    }
                    NavigationLink("項目ごとの取得周期") { PollIntervalView().environment(model) }
                }

                Section {
                    Picker("接続方式", selection: Binding(get: { s.connectionType }, set: { v in upd { $0.connectionType = v } })) {
                        ForEach(ConnectionType.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("接続方式")
                } footer: {
                    Text("iPhone では USB のアダプター (OBDLink SX・K+DCAN ケーブル) は使えません。Bluetooth LE 対応のアダプター (OBDLink CX / MX+ など) か、Wi-Fi の ELM327 を使ってください。Bluetooth クラシック (SPP) のアダプターは iPhone からは使えません。")
                }

                if s.connectionType == .BLE {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("使うアダプター")
                                Text(s.bleDeviceId == nil ? "未選択" : (s.bleDeviceName.isEmpty ? "(名前なし)" : s.bleDeviceName))
                                    .font(.system(size: 13)).foregroundColor(GaugeColors.subText)
                            }
                            Spacer()
                            Button(scanning ? "探すのをやめる" : "アダプターを探す") { toggleScan() }.buttonStyle(.bordered)
                        }
                        ForEach(devices) { d in
                            Button {
                                upd { $0.bleDeviceId = d.id.uuidString; $0.bleDeviceName = d.name }
                                stopScan()
                            } label: {
                                HStack {
                                    Text(d.name).foregroundColor(GaugeColors.text)
                                    Spacer()
                                    Text("\(d.rssi) dBm").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                                    if s.bleDeviceId == d.id.uuidString { Image(systemName: "checkmark").foregroundColor(GaugeColors.accent) }
                                }
                            }
                        }
                    } header: {
                        Text("Bluetooth LE アダプター")
                    } footer: {
                        Text("車のイグニッションを ON にして (アダプターに電源が入った状態で)「アダプターを探す」を押し、一覧からアダプターを選んでください。OBDLink は「OBDLink CX」などの名前で出ます。")
                    }
                }

                if s.connectionType == .WIFI {
                    Section {
                        HStack {
                            Text("アドレス")
                            TextField("192.168.0.10", text: $hostText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: hostText) { _, t in
                                    let v = t.trimmingCharacters(in: .whitespaces)
                                    if loaded && !v.isEmpty { upd { $0.wifiHost = v } }
                                }
                        }
                        HStack {
                            Text("ポート")
                            TextField("35000", text: $portText)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                                .onChange(of: portText) { _, t in
                                    if loaded, let p = Int(t), p > 0, p < 65536 { upd { $0.wifiPort = p } }
                                }
                        }
                    } header: {
                        Text("Wi-Fi アダプター")
                    } footer: {
                        Text("iPhone の Wi-Fi 設定で、アダプターのネットワーク (WiFi_OBDII など) に接続してから「接続」を押してください。多くのアダプターは 192.168.0.10 / 35000 です。")
                    }
                }

                if s.connectionType != .SIMULATOR {
                    Section("ELM327 詳細") {
                        Picker("通信プロトコル", selection: Binding(get: { s.elmProtocol }, set: { v in upd { $0.elmProtocol = v } })) {
                            ForEach(ELM_PROTOCOLS.indices, id: \.self) { i in Text(ELM_PROTOCOLS[i].1 + " (ATSP" + ELM_PROTOCOLS[i].0 + ")").tag(ELM_PROTOCOLS[i].0) }
                        }
                        Toggle(isOn: Binding(get: { s.elmSingleResponseHint }, set: { v in upd { $0.elmSingleResponseHint = v } })) {
                            VStack(alignment: .leading) {
                                Text("高速応答モード")
                                Text("要求に応答数を付けて待ち時間を減らす。値が出ない場合は OFF に").font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                            }
                        }
                    }
                }

                Section("バックアップ") {
                    Button("エクスポート (設定を zip に書き出す)") {
                        if let url = model.exportBackup() { shareURL = url }
                    }
                    Button("インポート (Android 版の zip も読めます)") { importing = true }
                }

                Section("その他") {
                    toggle("ダッシュボードのバーを常に表示", "OFF のときは、接続状態や編集・設定のボタンを隠してメーターを全画面に表示し、右上のボタンで呼び出します", s.alwaysShowToolbar) { v in upd { $0.alwaysShowToolbar = v } }
                    toggle("起動時に自動接続", "アプリを開いたら「接続」を押さなくても接続を始めます", s.autoConnect) { v in upd { $0.autoConnect = v } }
                    toggle("自動再接続", "通信が切れたら 3 秒後に再接続", s.autoReconnect) { v in upd { $0.autoReconnect = v } }
                    toggle("イグニッション OFF でも接続して待機", "アダプターに接続したまま 5 秒ごとに車両を確認し、イグニッション ON で自動的に表示を始めます。待機中もバッテリー電圧は表示されます", s.waitForVehicle) { v in upd { $0.waitForVehicle = v } }
                    if s.waitForVehicle {
                        Picker("待機の上限", selection: Binding(get: { s.waitTimeoutMin }, set: { v in upd { $0.waitTimeoutMin = v } })) {
                            ForEach([5, 15, 30, 60, 0], id: \.self) { m in Text(m == 0 ? "無制限" : "\(m)分").tag(m) }
                        }
                    }
                    toggle("接続中は画面を消灯しない", nil, s.keepScreenOn) { v in upd { $0.keepScreenOn = v } }
                }

                Section {
                    Text("バージョン " + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"))
                        .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !loaded {
                hostText = s.wifiHost
                portText = String(s.wifiPort)
                DispatchQueue.main.async { loaded = true }
            }
        }
        .onDisappear { stopScan() }
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result { model.loadBackup(url) }
        }
        .confirmationDialog("設定ファイルを読み込みます", isPresented: Binding(get: { model.pendingImport != nil }, set: { if !$0 { model.pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("追加 (今の内容は残す)") { model.applyImport(.merge) }
            Button("置き換え (今のページとカスタム PID を消す)", role: .destructive) { model.applyImport(.replace) }
            Button("キャンセル", role: .cancel) { model.pendingImport = nil }
        } message: {
            if let b = model.pendingImport {
                Text("ページ \(b.pageCount) (メーター \(b.gaugeCount))、カスタム PID \(b.customPidCount)、画像 \(b.imageCount)、フォント \(b.fontCount)")
            }
        }
        .alert(model.backupMessage ?? "", isPresented: Binding(get: { model.backupMessage != nil && model.pendingImport == nil },
                                                               set: { if !$0 { model.backupMessage = nil } })) {
            Button("OK") { model.backupMessage = nil }
        }
    }

    private func toggle(_ label: String, _ detail: String?, _ value: Bool, _ onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: onChange)) {
            VStack(alignment: .leading) {
                Text(label)
                if let d = detail { Text(d).font(.system(size: 12)).foregroundColor(GaugeColors.subText) }
            }
        }
    }

    private func toggleScan() { if scanning { stopScan() } else { startScan() } }

    private func startScan() {
        scanning = true
        devices = []
        BLEManager.shared.onDiscover = { d in
            if let i = devices.firstIndex(where: { $0.id == d.id }) { devices[i] = d } else { devices.append(d) }
            devices.sort { $0.rssi > $1.rssi }
        }
        BLEManager.shared.startScan()
    }

    private func stopScan() {
        if !scanning { return }
        scanning = false
        BLEManager.shared.onDiscover = nil
        BLEManager.shared.stopScan()
    }
}

/// ページで使っている項目ごとに、車から読む周期を選ぶ
struct PollIntervalView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    private let options: [(Int, String)] = [(0, "毎回"), (500, "0.5秒"), (1000, "1秒"), (2000, "2秒"), (5000, "5秒"), (10000, "10秒"), (30000, "30秒")]

    var body: some View {
        let s = model.settings
        var used: [String] = []
        for g in model.dashboards.flatMap({ $0.gauges }) {
            for k in ReadPlan.gaugeKeys(g) + [g.fallbackKey].compactMap({ $0 }) where !used.contains(k) { used.append(k) }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        var shown: [String] = []
        if q.isEmpty {
            shown = used
            for k in s.pollIntervalsMs.keys.sorted() where !shown.contains(k) { shown.append(k) }
        } else {
            shown = Array(model.catalog.all.filter {
                $0.name.localizedCaseInsensitiveContains(q) || $0.shortName.localizedCaseInsensitiveContains(q) || $0.key.localizedCaseInsensitiveContains(q)
            }.map { $0.key }.prefix(40))
        }
        return List {
            Section {
                Text("変化が遅い項目 (水温・油温・電圧など) は周期を長くすると、回転数などの速い項目の更新が速くなります。「毎回」は表示中は毎サイクル読みます。設定はその項目を使うすべてのメーター・グラフに共通です。")
                    .font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            }
            ForEach(shown, id: \.self) { key in
                let def = model.catalog.get(key)
                let cur = s.pollIntervalsMs[key] ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    Text(def?.name ?? key).font(.system(size: 14))
                    if def?.slow == true && cur == 0 {
                        Text("既定では 8 サイクルに 1 回読みます").font(.system(size: 11)).foregroundColor(GaugeColors.subText)
                    }
                    Chips(options, selected: { $0 == cur }) { ms in
                        model.updateSettings { st in
                            if ms == 0 { st.pollIntervalsMs.removeValue(forKey: key) } else { st.pollIntervalsMs[key] = ms }
                        }
                    }
                }
            }
            if !q.isEmpty && shown.isEmpty {
                Text("見つかりません").foregroundColor(GaugeColors.subText)
            }
        }
        .searchable(text: $query, prompt: "ほかの項目を探す (例: ブースト、水温、5A2C)")
        .navigationTitle("項目ごとの取得周期")
        .navigationBarTitleDisplayMode(.inline)
    }
}
