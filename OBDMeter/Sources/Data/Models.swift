import Foundation

extension LegendPosition {
    var inside: Bool { rawValue.hasPrefix("INSIDE") }
}

extension GaugeDesign {
    /// 記録を残す期間 (ミリ秒)
    var historyRetentionMs: Int64 {
        historyHours > 0 ? Int64(historyHours) * 3_600_000 : Int64(Swift.min(Swift.max(historyMonths, 1), 24)) * 2_629_746_000
    }

    func imageNames() -> [String] { [backgroundImage, tableValueImage].compactMap { $0 } }
}

extension GaugeConfig: Identifiable {
    /// 折れ線グラフに追加できる項目の数
    static let MAX_CHART_EXTRA = 5
    /// 値テーブルに追加できる項目の数
    static let MAX_TABLE_EXTRA = 29

    /// 折れ線グラフの [index] 番目の項目が右の縦軸か (既定は奇数番目が右)
    func isRightAxis(_ index: Int, _ key: String) -> Bool { chartAxis[key] ?? (index % 2 == 0) }

    /// 折れ線グラフ・値テーブル・変動監視に出す項目すべて (先頭が [pidKey])
    var chartAllKeys: [String] { [pidKey] + chartKeys }
}

extension Dashboard: Identifiable {
    /// ページとメーターが使っている画像の名前
    func imageNames() -> [String] { gauges.flatMap { $0.design.imageNames() } + [background.image].compactMap { $0 } }
}

extension CustomPid: Identifiable {
    static let KEY_PREFIX = "CUSTOM_"

    var key: String { CustomPid.KEY_PREFIX + String(id) }

    /// 表示・読み出しに使う定義に変換する。式や PID が不正なら例外
    func toDef() throws -> PidDef {
        try Pids.custom(key: key, name: name, shortName: shortName, unit: unit, mode: mode, pid: pid, header: header,
                        canExtAddress: canExtAddress, formula: formula, min: min, max: max, decimals: decimals,
                        warnAbove: warnAbove, warnBelow: warnBelow, slow: slow)
    }

    /// 不正な場合のエラーメッセージ。正しければ nil
    func validate() -> String? {
        do { _ = try toDef(); return nil } catch { return error.localizedDescription }
    }
}

extension FontEntry: Identifiable {}

extension BackupManifest {
    static let FORMAT = "obdmeter-backup"
    static let VERSION = 1
}

/// メーターの配置 (マス目) の計算
enum Layout {
    /// 旧来の 1 マス (横 24 × 縦 12 分割) を、さらに何分割して位置・大きさを持つか
    static let SCALE = 4
    static let COLS = 24 * SCALE
    static let ROWS = 12 * SCALE
    static let MIN_SIZE = 2 * SCALE
    static let GRID_STEPS: [(Int, String)] = [(1, "1/4 マス"), (2, "1/2 マス"), (4, "1 マス"), (8, "2 マス")]

    static func snap(_ v: Int, _ step: Int) -> Int {
        step <= 1 ? v : Int((Double(v) / Double(step)).rounded()) * step
    }

    static var widthRange: ClosedRange<Int> { MIN_SIZE...(COLS * 2) }
    static var heightRange: ClosedRange<Int> { MIN_SIZE...(ROWS * 2) }
    static func xRange(_ w: Int) -> ClosedRange<Int> { (SCALE - w)...(COLS - SCALE) }
    static func yRange(_ h: Int) -> ClosedRange<Int> { (SCALE - h)...(ROWS - SCALE) }

    static func clamp(_ v: Int, _ r: ClosedRange<Int>) -> Int { Swift.min(Swift.max(v, r.lowerBound), r.upperBound) }

    /// 位置・大きさを置ける範囲に収める。戻り値は (x, y, w, h)
    static func clampPlacement(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [Int] {
        let cw = clamp(w, widthRange)
        let ch = clamp(h, heightRange)
        return [clamp(x, xRange(cw)), clamp(y, yRange(ch)), cw, ch]
    }

    /// 位置が未設定のメーターに id と配置を与える (旧データの移行・初期データ用)
    static func normalize(_ d: Dashboard) -> Dashboard {
        var nextId = (d.gauges.map { $0.id }.max() ?? 0) + 1
        var withIds = d.gauges
        for i in withIds.indices where withIds[i].id == 0 {
            withIds[i].id = nextId
            nextId += 1
        }
        // 以前の版の単位 (24 × 12 マス) なら細かい単位に直す
        if d.unitScale < SCALE {
            let f = SCALE / Swift.max(d.unitScale, 1)
            for i in withIds.indices where withIds[i].w > 0 && withIds[i].h > 0 {
                withIds[i].x *= f; withIds[i].y *= f; withIds[i].w *= f; withIds[i].h *= f
            }
        }
        let placed = withIds.allSatisfy { $0.w > 0 && $0.h > 0 } ? withIds : arrangeInGrid(withIds, d.columns)
        var out = d
        out.gauges = placed
        out.unitScale = SCALE
        return out
    }

    /// [columns] 列で均等に並べ直す
    static func arrangeInGrid(_ gauges: [GaugeConfig], _ columns: Int) -> [GaugeConfig] {
        let cols = Swift.min(Swift.max(columns, 1), 6)
        let rows = Swift.max(1, (gauges.count + cols - 1) / cols)
        return gauges.enumerated().map { (i, g) in
            let c = i % cols
            let r = i / cols
            let x0 = c * COLS / cols, x1 = (c + 1) * COLS / cols
            let y0 = r * ROWS / rows, y1 = (r + 1) * ROWS / rows
            var n = g
            n.x = x0; n.y = y0; n.w = Swift.max(1, x1 - x0); n.h = Swift.max(1, y1 - y0)
            return n
        }
    }

    /// 配置のグループ (2 つ以上のメーターがあるものだけ)。グループ id → メーター
    static func groups(_ gauges: [GaugeConfig]) -> [Int64: [GaugeConfig]] {
        var m: [Int64: [GaugeConfig]] = [:]
        for g in gauges { if let lg = g.layoutGroup { m[lg, default: []].append(g) } }
        return m.filter { $0.value.count >= 2 }
    }

    /// メーターをまとめて囲む範囲 (x, y, w, h)
    static func bounds(_ gauges: [GaugeConfig]) -> [Int] {
        let x0 = gauges.map { $0.x }.min() ?? 0
        let y0 = gauges.map { $0.y }.min() ?? 0
        let x1 = gauges.map { $0.x + $0.w }.max() ?? 0
        let y1 = gauges.map { $0.y + $0.h }.max() ?? 0
        return [x0, y0, x1 - x0, y1 - y0]
    }

    /// グループを (dx, dy) 動かした配置
    static func moveGroup(_ gauges: [GaugeConfig], _ dx: Int, _ dy: Int) -> [Int64: [Int]] {
        let b = bounds(gauges)
        let nx = clamp(b[0] + dx, (SCALE - b[2])...(COLS - SCALE))
        let ny = clamp(b[1] + dy, (SCALE - b[3])...(ROWS - SCALE))
        var m: [Int64: [Int]] = [:]
        for g in gauges { m[g.id] = [g.x + nx - b[0], g.y + ny - b[1], g.w, g.h] }
        return m
    }

    /// グループの囲む範囲を幅 [w]・高さ [h] にしたときの各メーターの配置
    static func resizeGroup(_ gauges: [GaugeConfig], _ w: Int, _ h: Int) -> [Int64: [Int]] {
        let b = bounds(gauges)
        let minGW = gauges.map { $0.w }.min() ?? 1
        let minGH = gauges.map { $0.h }.min() ?? 1
        let minW = Int((Double(b[2] * MIN_SIZE) / Double(Swift.max(minGW, 1))).rounded(.up))
        let minH = Int((Double(b[3] * MIN_SIZE) / Double(Swift.max(minGH, 1))).rounded(.up))
        let nw = clamp(w, Swift.min(minW, b[2])...Swift.max(COLS * 2, b[2]))
        let nh = clamp(h, Swift.min(minH, b[3])...Swift.max(ROWS * 2, b[3]))
        let sx = Double(nw) / Double(Swift.max(b[2], 1))
        let sy = Double(nh) / Double(Swift.max(b[3], 1))
        func sc(_ v: Int, _ s: Double) -> Int { Int((Double(v) * s).rounded()) }
        var m: [Int64: [Int]] = [:]
        for g in gauges {
            let l = sc(g.x - b[0], sx)
            let t = sc(g.y - b[1], sy)
            let r = sc(g.x + g.w - b[0], sx)
            let bt = sc(g.y + g.h - b[1], sy)
            m[g.id] = [b[0] + l, b[1] + t, Swift.max(MIN_SIZE, r - l), Swift.max(MIN_SIZE, bt - t)]
        }
        return m
    }

    /// コピーしたメーター [src] を [existing] のページに貼り付ける位置のずらし量 (dx, dy)
    static func pasteOffset(_ existing: [GaugeConfig], _ src: [GaugeConfig]) -> (Int, Int) {
        let b = bounds(src)
        func free(_ x: Int, _ y: Int) -> Bool {
            !existing.contains { g in x < g.x + g.w && g.x < x + b[2] && y < g.y + g.h && g.y < y + b[3] }
        }
        func fits(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x + b[2] <= COLS && y + b[3] <= ROWS }
        if free(b[0], b[1]) { return (0, 0) }
        let spot = findFreeSpot(existing, b[2], b[3])
        if free(spot.0, spot.1) && fits(spot.0, spot.1) { return (spot.0 - b[0], spot.1 - b[1]) }
        let x = Swift.max(Swift.min(b[0] + SCALE, COLS - b[2]), 0)
        let y = Swift.max(Swift.min(b[1] + SCALE, ROWS - b[3]), 0)
        return (x - b[0], y - b[1])
    }

    /// 新しいメーターを置く空き場所を探す。見つからなければ左上
    static func findFreeSpot(_ existing: [GaugeConfig], _ w: Int, _ h: Int) -> (Int, Int) {
        if ROWS - h >= 0 && COLS - w >= 0 {
            for y in 0...(ROWS - h) {
                for x in 0...(COLS - w) {
                    let overlaps = existing.contains { g in x < g.x + g.w && g.x < x + w && y < g.y + g.h && g.y < y + h }
                    if !overlaps { return (x, y) }
                }
            }
        }
        return (0, 0)
    }

    /// 見た目の選択肢 (メーターの色)
    static let COLORS: [(String, Int64)] = [
        ("水色", 0xFF4FC3F7), ("緑", 0xFF66BB6A), ("黄", 0xFFFFCA28), ("オレンジ", 0xFFFF9800),
        ("赤", 0xFFFF1A1A), ("濃い赤", 0xFFC62828), ("淡い赤", 0xFFEF5350), ("紫", 0xFFAB47BC),
        ("ピンク", 0xFFEC407A), ("白", 0xFFE8EAED),
    ]
}

enum Defaults {
    static var dashboards: [Dashboard] {
        [
            Dashboard(id: 1, name: "メイン", columns: 2, gauges: [
                GaugeConfig(pidKey: "RPM", style: .ANALOG, id: 1, x: 0, y: 0, w: 12, h: 12),
                GaugeConfig(pidKey: "SPEED", style: .ANALOG, id: 2, x: 12, y: 0, w: 12, h: 8),
                GaugeConfig(pidKey: "COOLANT", style: .BAR, id: 3, x: 12, y: 8, w: 6, h: 4),
                GaugeConfig(pidKey: "BATTERY", style: .DIGITAL, id: 4, x: 18, y: 8, w: 6, h: 4),
            ]),
            Dashboard(id: 2, name: "エンジン", columns: 3, gauges: [
                GaugeConfig(pidKey: "LOAD", style: .ANALOG),
                GaugeConfig(pidKey: "THROTTLE", style: .ANALOG),
                GaugeConfig(pidKey: "TIMING", style: .ANALOG),
                GaugeConfig(pidKey: "MAF", style: .DIGITAL),
                GaugeConfig(pidKey: "MAP", style: .DIGITAL),
                GaugeConfig(pidKey: "IAT", style: .DIGITAL),
            ]),
            Dashboard(id: 3, name: "燃調・燃費", columns: 2, gauges: [
                GaugeConfig(pidKey: "STFT1", style: .BAR),
                GaugeConfig(pidKey: "STFT2", style: .BAR),
                GaugeConfig(pidKey: "LTFT1", style: .BAR),
                GaugeConfig(pidKey: "LTFT2", style: .BAR),
                GaugeConfig(pidKey: "FUEL_RATE", style: .DIGITAL),
                GaugeConfig(pidKey: "ECONOMY", style: .DIGITAL),
            ]),
        ].map { Layout.normalize($0) }
    }
}

/// 折れ線グラフ・変動監視の記録の置き場所 (メーターごと)
enum HistorySlot {
    static func of(_ pageId: Int64, _ gaugeId: Int64) -> String { "\(pageId):\(gaugeId)" }
}

/// どの項目を読むか・記録するかを決める計算
enum ReadPlan {
    /// メーターが使う項目のキー (グラフ・値テーブル・変動監視は追加した項目も)
    static func gaugeKeys(_ g: GaugeConfig) -> [String] {
        (g.style == .CHART || g.style == .TABLE || g.style == .MONITOR) ? g.chartAllKeys : [g.pidKey]
    }

    /// 表示中のページで読む項目 (重複なし) と、代替項目 (メイン項目のキー → 代替項目)
    static func activeItems(_ shown: [Dashboard], _ catalog: PidCatalog) -> ([PidDef], [String: PidDef]) {
        let gauges = shown.flatMap { $0.gauges }
        var seen = Set<String>()
        var pids: [PidDef] = []
        for k in gauges.flatMap({ gaugeKeys($0) }) {
            guard !seen.contains(k), let d = catalog.get(k) else { continue }
            seen.insert(k)
            pids.append(d)
        }
        var fallbacks: [String: PidDef] = [:]
        for g in gauges {
            if let fb = g.fallbackKey, let d = catalog.get(fb) { fallbacks[g.pidKey] = d }
        }
        return (pids, fallbacks)
    }

    static let CHANGE_MIN_MS: Int64 = 200
    static let CHANGE_SAMPLE_MIN_MS: Int64 = 1_000

    struct RecordRule: Equatable {
        var intervalMs: Int64
        var onChangeOnly: Bool
        var events: Bool = false
    }

    struct RecordTarget: Hashable {
        var slot: String
        var key: String
    }

    /// 記録するもの (グラフごと・項目ごと) と記録のしかた
    static func recordRules(_ pages: [Dashboard], shownPage: Int64?, pollIntervals: [String: Int64]) -> [RecordTarget: RecordRule] {
        var out: [RecordTarget: RecordRule] = [:]
        for p in pages {
            for g in p.gauges where g.style == .CHART {
                if g.design.recordOnlyWhenShown && p.id != shownPage { continue }
                let sec = Swift.min(Swift.max(Int(g.design.recordIntervalSec), HistoryStore.MIN_INTERVAL_SEC), HistoryStore.MAX_INTERVAL_SEC)
                let slot = HistorySlot.of(p.id, g.id)
                for k in g.chartAllKeys {
                    let ms = g.design.recordOnChange ? Swift.max(pollIntervals[k] ?? 0, CHANGE_MIN_MS) : Int64(sec) * 1000
                    out[RecordTarget(slot: slot, key: k)] = RecordRule(intervalMs: ms, onChangeOnly: g.design.recordOnChange)
                }
            }
        }
        // 変動監視は、表示中かどうかに関係なく、項目の取得周期ごとに値を見て変わったときだけ記録する
        for p in pages {
            for g in p.gauges where g.style == .MONITOR {
                let slot = HistorySlot.of(p.id, g.id)
                for k in g.chartAllKeys {
                    out[RecordTarget(slot: slot, key: k)] = RecordRule(intervalMs: Swift.max(pollIntervals[k] ?? 0, CHANGE_MIN_MS),
                                                                       onChangeOnly: false, events: true)
                }
            }
        }
        return out
    }

    /// 記録の保存期間 (ミリ秒、グラフ・変動監視ごと)。0 = 消さない (変動監視)
    static func retentions(_ pages: [Dashboard]) -> [String: Int64] {
        var m: [String: Int64] = [:]
        for p in pages {
            for g in p.gauges {
                if g.style == .CHART { m[HistorySlot.of(p.id, g.id)] = g.design.historyRetentionMs }
                if g.style == .MONITOR { m[HistorySlot.of(p.id, g.id)] = 0 }
            }
        }
        return m
    }

    /// 記録する項目 [due] を、表示用にすでに読んでいて値がある項目と、記録のために読む項目に分ける
    static func splitSample(_ due: Set<String>, _ live: [String: Double], _ activeKeys: Set<String>) -> ([String: Double], [String]) {
        var reuse: [String: Double] = [:]
        var need: [String] = []
        for k in due {
            if activeKeys.contains(k), let v = live[k] { reuse[k] = v } else { need.append(k) }
        }
        return (reuse, need)
    }
}

/// 変動監視の集計
enum Monitor {
    static let WINDOWS: [(Int64, String)] = [
        (10_000, "10秒"), (60_000, "1分"), (600_000, "10分"), (3_600_000, "1時間"), (86_400_000, "1日"),
        (7 * 86_400_000, "1週間"), (HistoryStore.MONTH_MS, "1か月"), (3 * HistoryStore.MONTH_MS, "3か月"),
        (6 * HistoryStore.MONTH_MS, "6か月"), (24 * HistoryStore.MONTH_MS, "24か月"),
    ]

    struct Stat: Equatable {
        var key: String
        var first: Double?
        var last: Double?
        var lastChangeAt: Int64?
        var counts: [Int]
        func count(_ window: Int) -> Int { counts[safe: window] ?? 0 }
    }

    static func windowIndex(_ ms: Int64) -> Int {
        if let i = WINDOWS.firstIndex(where: { $0.0 == ms }) { return i }
        return WINDOWS.firstIndex(where: { $0.0 == 86_400_000 }) ?? 0
    }

    /// 期間 [window] の変動回数が多い順。同じ回数なら登録順
    static func rank(_ stats: [Stat], _ window: Int) -> [Stat] {
        stats.enumerated().sorted { a, b in
            let ca = a.element.count(window), cb = b.element.count(window)
            return ca == cb ? a.offset < b.offset : ca > cb
        }.map { $0.element }
    }

    /// 現在の値 = 最新の計測値 - 初回の計測値
    static func currentValue(_ stat: Stat?, _ live: Double?) -> Double? {
        guard let first = stat?.first else { return nil }
        guard let latest = live ?? stat?.last else { return nil }
        return latest - first
    }

    static func shouldRecord(_ v: Double, _ last: Double?) -> Bool { !v.isNaN && !v.isInfinite && v != last }
}

/// 記録に書く 1 行
struct HistoryRow {
    var slot: String
    var key: String
    var t: Int64
    var v: Double
    var cont: Bool
    var replaceT: Int64? = nil
}

/// 「変化したときだけ記録する」グラフの記録の決め方 (Android 版と同じ)
final class ChangeRecorder {
    static let TAIL_FLUSH_MS: Int64 = 5_000
    static let MIN_GAP_MS: Int64 = 5_000

    private final class State {
        var value: Double
        var seen: Int64
        var stored: Int64
        var tail: Int64?
        init(_ value: Double, _ seen: Int64, _ stored: Int64, _ tail: Int64?) {
            self.value = value; self.seen = seen; self.stored = stored; self.tail = tail
        }
    }

    private var states: [ReadPlan.RecordTarget: State] = [:]

    func forget(_ slot: String) { states = states.filter { $0.key.slot != slot } }

    func has(_ target: ReadPlan.RecordTarget) -> Bool { states[target] != nil }

    func seed(_ target: ReadPlan.RecordTarget, _ last: HistoryRow?, _ lastIsTail: Bool) {
        guard let last = last, states[target] == nil else { return }
        states[target] = State(last.v, last.t, last.t, lastIsTail ? last.t : nil)
    }

    private func sec(_ t: Int64) -> Int64 { t / 1000 * 1000 }

    private func flush(_ target: ReadPlan.RecordTarget, _ s: State, _ out: inout [HistoryRow]) {
        if sec(s.seen) <= sec(s.stored) { return }
        out.append(HistoryRow(slot: target.slot, key: target.key, t: sec(s.seen), v: s.value, cont: true, replaceT: s.tail))
        s.stored = s.seen
        s.tail = sec(s.seen)
    }

    func observe(_ target: ReadPlan.RecordTarget, _ v: Double, _ time: Int64, _ intervalMs: Int64) -> [HistoryRow] {
        if v.isNaN || v.isInfinite { return [] }
        var out: [HistoryRow] = []
        let s = states[target]
        let gap = Swift.max(intervalMs * 3, ChangeRecorder.MIN_GAP_MS)
        if s == nil || (time - s!.seen > gap && v != s!.value) {
            if let s = s { flush(target, s, &out) }
            out.append(HistoryRow(slot: target.slot, key: target.key, t: sec(time), v: v, cont: false))
            states[target] = State(v, time, time, nil)
        } else if let s = s, v != s.value {
            out.append(HistoryRow(slot: target.slot, key: target.key, t: sec(time), v: v, cont: true, replaceT: s.tail))
            s.value = v; s.seen = time; s.stored = time; s.tail = nil
        } else if let s = s {
            s.seen = time
            if time - s.stored >= ChangeRecorder.TAIL_FLUSH_MS { flush(target, s, &out) }
        }
        return out
    }

    func retain(_ targets: Set<ReadPlan.RecordTarget>) -> [HistoryRow] {
        var out: [HistoryRow] = []
        for (t, s) in states where !targets.contains(t) {
            flush(t, s, &out)
            states.removeValue(forKey: t)
        }
        return out
    }
}

/// 記録した値 1 つ (時刻はミリ秒)
struct Sample: Equatable {
    var t: Int64
    var v: Double
}

/// 折れ線グラフの記録の CSV (key,datetime,value)
enum HistoryCsv {
    static let HEADER = "key,datetime,value"

    static func dateFormatter(_ format: String = "yyyy-MM-dd HH:mm:ss") -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = format
        f.isLenient = false
        return f
    }

    static func importFormats() -> [DateFormatter] {
        [dateFormatter(), dateFormatter("yyyy/MM/dd HH:mm:ss"), dateFormatter("yyyy-MM-dd'T'HH:mm:ss")]
    }

    static func isHeader(_ line: String) -> Bool { line.lowercased().hasPrefix("key") }

    static func parseLine(_ line: String, _ formats: [DateFormatter]) -> (String, Int64, Double)? {
        let cols = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        if cols.count < 3 { return nil }
        let key = cols[0]
        if key.isEmpty { return nil }
        var t: Int64? = nil
        for f in formats {
            if let d = f.date(from: cols[1]) { t = Int64((d.timeIntervalSince1970 * 1000).rounded()); break }
        }
        guard let time = t, let v = Double(cols[2]), !v.isNaN, !v.isInfinite else { return nil }
        return (key, time, v)
    }

    static func formatValue(_ v: Double) -> String {
        if v == v.rounded() && Swift.abs(v) < 1e15 { return String(Int64(v)) }
        return String(v)
    }

    static func line(_ key: String, _ time: Int64, _ value: Double, _ fmt: DateFormatter) -> String {
        key + "," + fmt.string(from: Date(timeIntervalSince1970: Double(time) / 1000)) + "," + formatValue(value)
    }

    /// 記録のある短い区間を、間が [gapMs] 以下ならつないで、記録のある時間帯にまとめる
    static func mergeSegments(_ buckets: [(Int64, Int64)], _ gapMs: Int64) -> [(Int64, Int64)] {
        var out: [(Int64, Int64)] = []
        var a: Int64 = -1, b: Int64 = -1
        for (lo, hi) in buckets {
            if a < 0 { a = lo; b = hi }
            else if lo - b <= gapMs { b = Swift.max(b, hi) }
            else { out.append((a, b)); a = lo; b = hi }
        }
        if a >= 0 { out.append((a, b)) }
        return out
    }
}
