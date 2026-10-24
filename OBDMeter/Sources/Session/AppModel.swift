import Foundation
import SwiftUI
import Observation
import UIKit

/// アプリ全体の状態 (保存データ・車両との接続)。画面はすべてここを見る
@Observable
final class AppModel {
    @ObservationIgnored let repo = Repository()
    @ObservationIgnored let log: LogBuffer
    @ObservationIgnored let session: ObdSession
    @ObservationIgnored let history: HistoryStore
    @ObservationIgnored let sensors: DeviceSensors
    @ObservationIgnored let recorder: Recorder

    private(set) var settings: AppSettings
    private(set) var dashboards: [Dashboard]
    private(set) var customPids: [CustomPid]
    private(set) var fonts: [FontEntry]
    /// 標準項目 + カスタム PID (式が不正なカスタム PID は外す)
    private(set) var catalog = PidCatalog()

    private(set) var carValues: [String: Double] = [:]
    private(set) var deviceValues: [String: Double] = [:]
    private(set) var connection: ConnectionState = .disconnected
    private(set) var rate: Double = 0
    private(set) var supported: Set<Int>? = nil
    /// 記録が増えるたびに増える (グラフの読み直しに使う)
    private(set) var historyRevision = 0

    /// 表示中のページ
    private(set) var appPage: Int64? = nil
    /// コピーしたメーター
    var clipboard: [GaugeConfig]? = nil
    /// ダッシュボードの 1 マスの大きさ (pt)
    var cellSize: CGSize? = nil
    /// 画面下に少しの間出すお知らせ
    var toast: String? = nil

    // バックアップ
    var backupMessage: String? = nil
    var pendingImport: LoadedBackup? = nil
    var backupBusy = false

    @ObservationIgnored private var idleDisconnect: DispatchWorkItem?
    @ObservationIgnored private var reconnectOnReturn = false
    @ObservationIgnored private var lastId: Int64 = 0
    @ObservationIgnored private var toastWork: DispatchWorkItem?

    /// メーターに出す値 (車から読んだ値 + 端末のセンサーの値)
    var values: [String: Double] {
        if deviceValues.isEmpty { return carValues }
        var v = carValues
        for (k, x) in deviceValues { v[k] = x }
        return v
    }

    init() {
        let r = Repository()
        settings = r.loadSettings()
        dashboards = r.loadDashboards()
        customPids = r.loadCustomPids()
        fonts = r.loadFonts()
        let lg = LogBuffer()
        log = lg
        let ses = ObdSession(log: lg)
        session = ses
        let his = HistoryStore()
        history = his
        let sen = DeviceSensors()
        sensors = sen
        recorder = Recorder(session: ses, history: his, sensors: sen)

        session.onState = { [weak self] s in self?.connection = s; self?.updateIdleTimer() }
        session.onValues = { [weak self] v in self?.carValues = v }
        session.onRate = { [weak self] v in self?.rate = v }
        session.onSupported = { [weak self] s in self?.supported = s }
        sensors.onValues = { [weak self] v in
            guard let self = self else { return }
            if v != self.deviceValues { self.deviceValues = v }
        }
        history.onChange = { [weak self] in self?.historyRevision += 1 }

        rebuildCatalog()
        appPage = settings.lastPageId.flatMap { id in dashboards.contains { $0.id == id } ? id : nil } ?? dashboards.first?.id
        refreshActive()
        session.pollIntervals = settings.pollIntervalsMs.mapValues { Int64($0) }
        recorder.start()
        // フォントを使えるようにしておく
        for f in fonts { _ = GaugeFonts.postScriptName(f) }
        // どのメーターからも使われなくなった画像を消す
        let used = Set(dashboards.flatMap { $0.imageNames() })
        DispatchQueue.global(qos: .utility).async { GaugeImages.cleanup(used) }
        if settings.autoConnect { connect() }
    }

    /// 重ならない新しい id (ミリ秒の時刻ベース)
    func newId() -> Int64 {
        let t = nowMs()
        lastId = Swift.max(lastId + 1, t)
        return lastId
    }

    func showToast(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: w)
    }

    private func rebuildCatalog() {
        catalog = PidCatalog(custom: customPids.compactMap { try? $0.toDef() })
        recorder.catalog = catalog
    }

    /// 表示中のページの項目だけを読み出すようにし、記録のしかたも更新する
    private func refreshActive() {
        let shown = dashboards.filter { $0.id == appPage }
        let (pids, fallbacks) = ReadPlan.activeItems(shown.isEmpty ? Array(dashboards.prefix(1)) : shown, catalog)
        session.activePids = pids.filter { !DeviceItems.isDevice($0) }
        session.activeFallbacks = fallbacks
        let poll = settings.pollIntervalsMs.mapValues { Int64($0) }
        let rules = ReadPlan.recordRules(dashboards, shownPage: appPage, pollIntervals: poll)
        recorder.rules = rules
        history.retentions = ReadPlan.retentions(dashboards)
        var dev = Set(pids.filter { DeviceItems.isDevice($0) }.map { $0.key })
        for t in rules.keys where t.key.hasPrefix("DEV_") { dev.insert(t.key) }
        sensors.setActive(dev)
    }

    private func updateIdleTimer() {
        let on = settings.keepScreenOn && !connection.isDisconnected
        if UIApplication.shared.isIdleTimerDisabled != on { UIApplication.shared.isIdleTimerDisabled = on }
    }

    // MARK: - 接続

    func connect() { session.connect(settings) }

    func disconnect() {
        reconnectOnReturn = false
        session.disconnect()
    }

    /// アプリが前面に出た / 裏に回った
    func setForeground(_ fg: Bool) {
        if fg {
            idleDisconnect?.cancel()
            idleDisconnect = nil
            if reconnectOnReturn {
                reconnectOnReturn = false
                if connection.isDisconnected { connect() }
            }
        } else if !connection.isDisconnected {
            // しばらく (1 分) 戻ってこなければ切断し、次に前面に来たときに再接続する
            idleDisconnect?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self = self, !self.connection.isDisconnected else { return }
                self.session.disconnect()
                self.reconnectOnReturn = true
            }
            idleDisconnect = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: w)
        }
    }

    /// 表示中のページが変わった
    func setActivePage(_ id: Int64?) {
        if appPage == id { return }
        appPage = id
        refreshActive()
        if let id = id, settings.lastPageId != id {
            settings.lastPageId = id
            repo.saveSettings(settings)
        }
    }

    // MARK: - 設定

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var s = settings
        transform(&s)
        if s == settings { return }
        let pollChanged = s.pollIntervalsMs != settings.pollIntervalsMs
        settings = s
        repo.saveSettings(s)
        if pollChanged {
            session.pollIntervals = s.pollIntervalsMs.mapValues { Int64($0) }
            refreshActive()
        }
        updateIdleTimer()
    }

    // MARK: - ダッシュボード編集

    func editDashboards(_ transform: (inout [Dashboard]) -> Void) {
        var list = dashboards
        transform(&list)
        if list == dashboards { return }
        dashboards = list
        repo.saveDashboards(list)
        if appPage == nil || !list.contains(where: { $0.id == appPage }) { appPage = list.first?.id }
        refreshActive()
    }

    func editDashboard(_ id: Int64, _ transform: (inout Dashboard) -> Void) {
        editDashboards { list in
            if let i = list.firstIndex(where: { $0.id == id }) { transform(&list[i]) }
        }
    }

    func addDashboard(_ name: String) {
        let id = newId()
        editDashboards { $0.append(Dashboard(id: id, name: name)) }
    }

    func renameDashboard(_ id: Int64, _ name: String) { editDashboard(id) { $0.name = name } }

    func setPageBackground(_ id: Int64, _ bg: PageBackground) { editDashboard(id) { $0.background = bg } }

    func applyBackgroundToAll(_ bg: PageBackground) {
        editDashboards { list in for i in list.indices { list[i].background = bg } }
    }

    func deleteDashboard(_ id: Int64) { editDashboards { $0.removeAll { $0.id == id } } }

    func moveDashboard(_ id: Int64, _ delta: Int) {
        editDashboards { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            let t = i + delta
            if t < 0 || t >= list.count { return }
            let d = list.remove(at: i)
            list.insert(d, at: t)
        }
    }

    func arrangeInGrid(_ id: Int64, _ columns: Int) {
        editDashboard(id) { d in
            d.columns = columns
            d.gauges = Layout.arrangeInGrid(d.gauges, columns)
        }
    }

    /// 空いている場所にメーターを追加し、その id を返す
    @discardableResult
    func addGauge(_ dashboardId: Int64, _ pidKey: String, _ style: GaugeStyle) -> Int64 {
        let gid = newId()
        editDashboard(dashboardId) { d in
            let w = (style == .ANALOG ? 8 : 6) * Layout.SCALE
            let h = (style == .ANALOG ? 6 : 3) * Layout.SCALE
            let (x, y) = Layout.findFreeSpot(d.gauges, w, h)
            d.gauges.append(GaugeConfig(pidKey: pidKey, style: style, id: gid, x: x, y: y, w: w, h: h))
        }
        return gid
    }

    func updateGauge(_ dashboardId: Int64, _ gaugeId: Int64, _ transform: (inout GaugeConfig) -> Void) {
        editDashboard(dashboardId) { d in
            if let i = d.gauges.firstIndex(where: { $0.id == gaugeId }) { transform(&d.gauges[i]) }
        }
    }

    func replaceGauge(_ dashboardId: Int64, _ g: GaugeConfig) {
        updateGauge(dashboardId, g.id) { $0 = g }
    }

    func removeGauge(_ dashboardId: Int64, _ gaugeId: Int64) {
        editDashboard(dashboardId) { $0.gauges.removeAll { $0.id == gaugeId } }
    }

    func copyGauge(_ g: GaugeConfig) {
        var c = g
        c.layoutGroup = nil
        clipboard = [c]
    }

    func copyGauges(_ gs: [GaugeConfig]) { clipboard = gs.isEmpty ? nil : gs }

    func pasteGauge(_ dashboardId: Int64) {
        guard let src = clipboard else { return }
        let base = newId()
        lastId = base + Int64(src.count)
        let group: Int64? = src.count >= 2 ? base : nil
        editDashboard(dashboardId) { d in
            let (dx, dy) = Layout.pasteOffset(d.gauges, src)
            for (i, g) in src.enumerated() {
                var n = g
                n.id = base + Int64(i)
                n.x = g.x + dx
                n.y = g.y + dy
                n.layoutGroup = group
                d.gauges.append(n)
            }
        }
    }

    func placeGauges(_ dashboardId: Int64, _ placements: [Int64: [Int]]) {
        editDashboard(dashboardId) { d in
            for i in d.gauges.indices {
                if let p = placements[d.gauges[i].id] {
                    d.gauges[i].x = p[0]; d.gauges[i].y = p[1]; d.gauges[i].w = p[2]; d.gauges[i].h = p[3]
                }
            }
        }
    }

    func groupGauges(_ dashboardId: Int64, _ ids: Set<Int64>) {
        if ids.count < 2 { return }
        let group = newId()
        editDashboard(dashboardId) { d in
            for i in d.gauges.indices where ids.contains(d.gauges[i].id) { d.gauges[i].layoutGroup = group }
        }
    }

    func ungroupGauges(_ dashboardId: Int64, _ ids: Set<Int64>) {
        editDashboard(dashboardId) { d in
            let groups = Set(d.gauges.filter { ids.contains($0.id) }.compactMap { $0.layoutGroup })
            for i in d.gauges.indices {
                if let g = d.gauges[i].layoutGroup, groups.contains(g) { d.gauges[i].layoutGroup = nil }
            }
        }
    }

    /// 重なりの順番を変える。+1 で 1 つ手前、-1 で 1 つ奥、Int.max で最前面、Int.min で最背面
    func moveZ(_ dashboardId: Int64, _ gaugeId: Int64, _ delta: Int) {
        editDashboard(dashboardId) { d in
            guard let i = d.gauges.firstIndex(where: { $0.id == gaugeId }) else { return }
            let g = d.gauges.remove(at: i)
            let to: Int
            if delta == Int.max { to = d.gauges.count }
            else if delta == Int.min { to = 0 }
            else { to = Swift.min(Swift.max(i + delta, 0), d.gauges.count) }
            d.gauges.insert(g, at: to)
        }
    }

    func resetDashboards() { editDashboards { $0 = Defaults.dashboards } }

    // MARK: - カスタム PID

    private func saveCustom(_ list: [CustomPid]) {
        customPids = list
        repo.saveCustomPids(list)
        rebuildCatalog()
        refreshActive()
    }

    func saveCustomPid(_ pid: CustomPid) {
        var list = customPids
        if let i = list.firstIndex(where: { $0.id == pid.id }) { list[i] = pid } else { list.append(pid) }
        saveCustom(list)
    }

    func deleteCustomPid(_ id: Int64) {
        let key = CustomPid.KEY_PREFIX + String(id)
        saveCustom(customPids.filter { $0.id != id })
        editDashboards { list in
            for i in list.indices {
                list[i].gauges.removeAll { $0.pidKey == key }
                for j in list[i].gauges.indices where list[i].gauges[j].fallbackKey == key {
                    list[i].gauges[j].fallbackKey = nil
                }
            }
        }
    }

    func testCustomPid(_ pid: CustomPid, completion: @escaping (ObdSession.TestResult) -> Void) {
        do {
            let def = try pid.toDef()
            guard let req = def.request else { completion(.init(data: nil, error: "要求を作れません")); return }
            session.testQuery(req, completion: completion)
        } catch {
            completion(.init(data: nil, error: error.localizedDescription))
        }
    }

    // MARK: - フォント

    private func saveFonts(_ list: [FontEntry]) {
        fonts = list
        repo.saveFonts(list)
    }

    func importFont(_ data: Data, name: String) throws -> FontEntry {
        let entry = try GaugeFonts.save(data, displayName: name, existing: fonts)
        if !fonts.contains(where: { $0.id == entry.id }) { saveFonts(fonts + [entry]) }
        _ = GaugeFonts.postScriptName(entry)
        return entry
    }

    func renameFont(_ id: String, _ name: String) {
        saveFonts(fonts.map { f in var n = f; if f.id == id { n.name = name }; return n })
    }

    /// フォントを削除する。使っていたメーターは既定のフォントに戻す
    func deleteFont(_ id: String) {
        if let f = fonts.first(where: { $0.id == id }) { GaugeFonts.delete(f) }
        saveFonts(fonts.filter { $0.id != id })
        editDashboards { list in
            for i in list.indices {
                for j in list[i].gauges.indices {
                    if list[i].gauges[j].design.valueFont == id { list[i].gauges[j].design.valueFont = nil }
                    if list[i].gauges[j].design.labelFont == id { list[i].gauges[j].design.labelFont = nil }
                }
            }
        }
    }

    /// フォントの id → PostScript 名
    func fontName(_ id: String?) -> String? {
        guard let id = id, let f = fonts.first(where: { $0.id == id }) else { return nil }
        return GaugeFonts.postScriptName(f)
    }

    // MARK: - バックアップ

    /// 設定を zip に書き出し、そのファイルの場所を返す
    func exportBackup() -> URL? {
        backupBusy = true
        defer { backupBusy = false }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ja_JP")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let manifest = BackupManifest(appVersion: "iOS " + version, exportedAt: fmt.string(from: Date()),
                                      dashboards: dashboards, customPids: customPids, fonts: fonts,
                                      pollIntervalsMs: settings.pollIntervalsMs)
        do {
            let (zip, images) = try BackupLogic.makeZip(manifest)
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyyMMdd_HHmm"
            let url = AppDirs.documents.appendingPathComponent("obdmeter_backup_\(stamp.string(from: Date())).zip")
            try zip.write(to: url, options: .atomic)
            backupMessage = "エクスポートしました (ページ \(manifest.dashboards.count)、カスタム PID \(manifest.customPids.count)、" +
                "画像 \(images)、フォント \(manifest.fonts.count))\n「ファイル」アプリの「このiPhone内 → OBDMeter」にも保存しました"
            return url
        } catch {
            backupMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
            return nil
        }
    }

    func loadBackup(_ url: URL) {
        backupBusy = true
        defer { backupBusy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingImport = try BackupLogic.readZip(data)
        } catch {
            backupMessage = "読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func applyImport(_ mode: ImportMode) {
        guard let backup = pendingImport else { return }
        pendingImport = nil
        // 画像を保存
        let used = BackupLogic.referencedImages(backup.manifest.dashboards)
        var rename: [String: String] = [:]
        for (name, bytes) in backup.images where used.contains(name) {
            if let saved = GaugeImages.saveBytes(bytes) { rename[name] = saved }
        }
        // フォントはライブラリに追加する
        var fontRename: [String: String] = [:]
        var library = fonts
        for entry in backup.manifest.fonts {
            guard let bytes = backup.fonts[entry.file] else { continue }
            let ext = (entry.file as NSString).pathExtension
            if let saved = try? GaugeFonts.save(bytes, displayName: entry.name + "." + ext, existing: library) {
                fontRename[entry.id] = saved.id
                if !library.contains(where: { $0.id == saved.id }) {
                    var s = saved
                    s.name = entry.name
                    library.append(s)
                }
            }
        }
        if library != fonts { saveFonts(library) }
        for f in library { _ = GaugeFonts.postScriptName(f) }
        let result = BackupLogic.apply(current: dashboards, currentPids: customPids, incoming: backup.manifest,
                                       imageRename: rename, mode: mode, newId: { self.newId() },
                                       fontRename: fontRename, currentIntervals: settings.pollIntervalsMs)
        saveCustom(result.customPids)
        editDashboards { $0 = result.dashboards }
        updateSettings { $0.pollIntervalsMs = result.pollIntervalsMs }
        let missing = used.count - rename.count
        var msg = (mode == .replace ? "置き換えました" : "追加しました") +
            " (ページ \(backup.pageCount)、カスタム PID \(backup.customPidCount)、画像 \(rename.count)、フォント \(fontRename.count)"
        if let iv = backup.manifest.pollIntervalsMs { msg += "、取得周期 \(iv.count) 項目" }
        msg += ")"
        if missing > 0 { msg += "。画像 \(missing) 枚はファイルに含まれていなかったため外しました" }
        backupMessage = msg
    }
}
