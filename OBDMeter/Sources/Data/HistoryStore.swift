import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 折れ線グラフ・変動監視の値の記録。メーターごと ([HistorySlot])・項目ごとに「時刻・値」を端末のデータベースに保存する。
/// テーブルの形は Android 版と同じ (samples: g, k, t, v, c)
final class HistoryStore {
    static let MIN_INTERVAL_SEC = 1
    static let MAX_INTERVAL_SEC = 600
    static let MAX_MONTHS: Int64 = 24
    static let MONTH_MS: Int64 = 2_629_746_000

    private let queue = DispatchQueue(label: "obdmeter.history")
    private var db: OpaquePointer?

    /// 今あるメーターと、それぞれの保存期間 (ミリ秒)。nil = まだ分からない (何も消さない)
    var retentions: [String: Int64]? {
        get { queue.sync { _retentions } }
        set { queue.async { self._retentions = newValue } }
    }
    private var _retentions: [String: Int64]? = nil

    /// 記録が増えたとき (メインスレッドで呼ぶ)
    var onChange: (() -> Void)?

    /// 記録を消したメーター
    private var cleared = Set<String>()
    private let clearedLock = NSLock()

    init() {
        queue.sync { self.openDb() }
        // 保存期間の設定が読み込まれるのを待ってから、定期的に古い記録を消す
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in self?.cleanupLoop() }
    }

    private func openDb() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("history.db").path
        if sqlite3_open(path, &db) != SQLITE_OK { db = nil; return }
        exec("PRAGMA journal_mode=WAL")
        var version: Int64 = 0
        query("PRAGMA user_version", []) { s in version = sqlite3_column_int64(s, 0) }
        if version < 4 {
            exec("DROP TABLE IF EXISTS samples")
            exec("CREATE TABLE samples (g TEXT NOT NULL, k TEXT NOT NULL, t INTEGER NOT NULL, v REAL NOT NULL, " +
                 "c INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (g, k, t)) WITHOUT ROWID")
            exec("PRAGMA user_version = 4")
        }
    }

    // MARK: - SQLite の補助

    @discardableResult
    private func exec(_ sql: String, _ args: [Any] = []) -> Bool {
        guard let db = db else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, args)
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE || rc == SQLITE_ROW
    }

    private func query(_ sql: String, _ args: [Any], _ row: (OpaquePointer) -> Void) {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else { return }
        defer { sqlite3_finalize(s) }
        bind(s, args)
        while sqlite3_step(s) == SQLITE_ROW { row(s) }
    }

    private func bind(_ stmt: OpaquePointer?, _ args: [Any]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case let s as String: sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            case let v as Int64: sqlite3_bind_int64(stmt, idx, v)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as Bool: sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            default: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    private func transaction(_ body: () -> Void) {
        exec("BEGIN")
        body()
        exec("COMMIT")
    }

    private func notify() {
        DispatchQueue.main.async { self.onChange?() }
    }

    private func placeholders(_ n: Int) -> String { Array(repeating: "?", count: n).joined(separator: ",") }

    private func insert(_ g: String, _ k: String, _ t: Int64, _ v: Double, _ c: Bool) {
        exec("INSERT OR REPLACE INTO samples (g, k, t, v, c) VALUES (?, ?, ?, ?, ?)", [g, k, t, v, c ? 1 : 0])
    }

    // MARK: - 書き込み (記録のスレッドから呼ぶ)

    /// 「変化したときだけ記録する」グラフの行 ([ChangeRecorder] が決めたもの) を書く
    func storeRows(_ rows: [HistoryRow]) {
        if rows.isEmpty { return }
        queue.sync {
            transaction {
                for r in rows {
                    if let old = r.replaceT, old != r.t {
                        exec("DELETE FROM samples WHERE g = ? AND k = ? AND t = ?", [r.slot, r.key, old])
                    }
                    insert(r.slot, r.key, r.t / 1000 * 1000, r.v, r.cont)
                }
            }
        }
        notify()
    }

    /// 変動監視の行を書く (時刻は丸めない)
    func storeEvents(_ rows: [HistoryRow]) {
        if rows.isEmpty { return }
        queue.sync { transaction { for r in rows { insert(r.slot, r.key, r.t, r.v, false) } } }
        notify()
    }

    /// 値を記録する ([rows] はグラフ → 項目キー → 値)。時刻は秒単位に丸める
    func store(_ rows: [String: [String: Double]], _ time: Int64) {
        if rows.isEmpty { return }
        let t = time / 1000 * 1000
        queue.sync {
            transaction {
                for (g, values) in rows {
                    for (k, v) in values where !v.isNaN && !v.isInfinite { insert(g, k, t, v, false) }
                }
            }
        }
        notify()
    }

    /// メーター [slot] の項目 [key] の最後の行と、それが動かせる末尾の行か
    func lastRow(_ slot: String, _ key: String) -> (HistoryRow, Bool)? {
        queue.sync {
            var rows: [(Int64, Double, Int64)] = []
            query("SELECT t, v, c FROM samples WHERE g = ? AND k = ? ORDER BY t DESC LIMIT 2", [slot, key]) { s in
                rows.append((sqlite3_column_int64(s, 0), sqlite3_column_double(s, 1), sqlite3_column_int64(s, 2)))
            }
            guard let first = rows.first else { return nil }
            let last = HistoryRow(slot: slot, key: key, t: first.0, v: first.1, cont: first.2 == 1)
            let tail = last.cont && rows.count > 1 && rows[1].1 == last.v
            return (last, tail)
        }
    }

    /// メーター [slot] の記録をすべて消す (リセット)
    func clear(_ slot: String) {
        queue.sync { _ = exec("DELETE FROM samples WHERE g = ?", [slot]) }
        clearedLock.lock(); cleared.insert(slot); clearedLock.unlock()
        notify()
    }

    /// [clear] で記録を消したメーター (受け取ったら空になる)
    func takeCleared() -> Set<String> {
        clearedLock.lock(); defer { clearedLock.unlock() }
        let out = cleared
        cleared.removeAll()
        return out
    }

    // MARK: - 読み出し

    /// 変動監視の集計。[keys] の順に返す
    func monitorStats(_ slot: String, _ keys: [String], _ now: Int64) -> [Monitor.Stat] {
        queue.sync {
            keys.map { k in
                func one(_ order: String) -> (Int64, Double)? {
                    var r: (Int64, Double)? = nil
                    query("SELECT t, v FROM samples WHERE g = ? AND k = ? ORDER BY t \(order) LIMIT 1", [slot, k]) { s in
                        r = (sqlite3_column_int64(s, 0), sqlite3_column_double(s, 1))
                    }
                    return r
                }
                let first = one("ASC")
                let last = one("DESC")
                var counts = Monitor.WINDOWS.map { _ in 0 }
                if let f = first {
                    let sums = Monitor.WINDOWS.map { _ in "SUM(t >= ?)" }.joined(separator: ", ")
                    var args: [Any] = Monitor.WINDOWS.map { now - $0.0 }
                    args += [slot, k, f.0]
                    query("SELECT \(sums) FROM samples WHERE g = ? AND k = ? AND t > ?", args) { s in
                        for i in 0..<Monitor.WINDOWS.count { counts[i] = Int(sqlite3_column_int64(s, Int32(i))) }
                    }
                }
                var changeAt: Int64? = nil
                if let f = first, let l = last, l.0 != f.0 { changeAt = l.0 }
                return Monitor.Stat(key: k, first: first?.1, last: last?.1, lastChangeAt: changeAt, counts: counts)
            }
        }
    }

    /// [from]〜[to] の記録を読む。点が多いときは [maxPoints] 程度にまとめる (区間ごとの最小と最大を残す)
    func load(_ slot: String, _ key: String, _ from: Int64, _ to: Int64, _ maxPoints: Int) -> [Sample] {
        queue.sync {
            var out: [Sample] = []
            let bucket = Swift.max((to - from) / Int64(Swift.max(maxPoints / 2, 1)), 1000)
            query("SELECT (t - ?) / ? AS b, MIN(v), MAX(v), MIN(t), MAX(t), COUNT(*) FROM samples " +
                  "WHERE g = ? AND k = ? AND t >= ? AND t <= ? GROUP BY b ORDER BY b", [from, bucket, slot, key, from, to]) { s in
                let lo = sqlite3_column_double(s, 1)
                let hi = sqlite3_column_double(s, 2)
                let t0 = sqlite3_column_int64(s, 3)
                let t1 = sqlite3_column_int64(s, 4)
                if sqlite3_column_int64(s, 5) == 1 || lo == hi {
                    out.append(Sample(t: t0, v: lo))
                } else {
                    out.append(Sample(t: t0, v: lo))
                    out.append(Sample(t: t1, v: hi))
                }
            }
            return out
        }
    }

    /// 直前と直後の記録 (表示範囲の外とも線をつなぐため)
    func neighbors(_ slot: String, _ key: String, _ from: Int64, _ to: Int64) -> (Sample?, Sample?) {
        queue.sync {
            var before: Sample? = nil, after: Sample? = nil
            query("SELECT t, v FROM samples WHERE g = ? AND k = ? AND t < ? ORDER BY t DESC LIMIT 1", [slot, key, from]) { s in
                before = Sample(t: sqlite3_column_int64(s, 0), v: sqlite3_column_double(s, 1))
            }
            query("SELECT t, v FROM samples WHERE g = ? AND k = ? AND t > ? ORDER BY t ASC LIMIT 1", [slot, key, to]) { s in
                after = Sample(t: sqlite3_column_int64(s, 0), v: sqlite3_column_double(s, 1))
            }
            return (before, after)
        }
    }

    /// [from]〜[to] で、[keys] のどれかに記録がある時間帯 (開始, 終了) を古い順に返す
    func segments(_ slot: String, _ keys: [String], _ from: Int64, _ to: Int64, _ gapMs: Int64) -> [(Int64, Int64)] {
        if keys.isEmpty { return [] }
        return queue.sync {
            let bucket = Swift.max(gapMs / 2, 1000)
            var buckets: [(Int64, Int64)] = []
            var args: [Any] = [bucket, slot]
            args += keys.map { $0 as Any }
            args += [from, to]
            query("SELECT t / ? AS b, MIN(t), MAX(t) FROM samples WHERE g = ? AND k IN (\(placeholders(keys.count))) " +
                  "AND t >= ? AND t <= ? GROUP BY b ORDER BY b", args) { s in
                buckets.append((sqlite3_column_int64(s, 1), sqlite3_column_int64(s, 2)))
            }
            // 途切れずに値を見ていた行 (c = 1) は、1 つ前の行との間も記録のある時間に含める
            var args2: [Any] = [slot]
            args2 += keys.map { $0 as Any }
            args2.append(from)
            query("SELECT (SELECT MAX(p.t) FROM samples p WHERE p.g = s.g AND p.k = s.k AND p.t < s.t), s.t " +
                  "FROM samples s WHERE s.g = ? AND s.k IN (\(placeholders(keys.count))) AND s.c = 1 AND s.t >= ?", args2) { s in
                if sqlite3_column_type(s, 0) == SQLITE_NULL { return }
                let a = Swift.max(sqlite3_column_int64(s, 0), from)
                let b = Swift.min(sqlite3_column_int64(s, 1), to)
                if a <= b { buckets.append((a, b)) }
            }
            return HistoryCsv.mergeSegments(buckets.sorted { $0.0 < $1.0 }, gapMs)
        }
    }

    /// [keys] の記録の一番古い時刻
    func earliest(_ slot: String, _ keys: [String]) -> Int64? {
        if keys.isEmpty { return nil }
        return queue.sync {
            var r: Int64? = nil
            var args: [Any] = [slot]
            args += keys.map { $0 as Any }
            query("SELECT MIN(t) FROM samples WHERE g = ? AND k IN (\(placeholders(keys.count)))", args) { s in
                if sqlite3_column_type(s, 0) != SQLITE_NULL { r = sqlite3_column_int64(s, 0) }
            }
            return r
        }
    }

    // MARK: - CSV

    /// [keys] の記録を CSV (key,datetime,value) にする。行数と内容を返す
    func exportCsv(_ slot: String, _ keys: [String]) -> (Int, String) {
        let fmt = HistoryCsv.dateFormatter()
        return queue.sync {
            var lines = [HistoryCsv.HEADER]
            if !keys.isEmpty {
                var args: [Any] = [slot]
                args += keys.map { $0 as Any }
                query("SELECT k, t, v FROM samples WHERE g = ? AND k IN (\(placeholders(keys.count))) ORDER BY k, t", args) { s in
                    let k = sqlite3_column_text(s, 0).map { String(cString: $0) } ?? ""
                    lines.append(HistoryCsv.line(k, sqlite3_column_int64(s, 1), sqlite3_column_double(s, 2), fmt))
                }
            }
            return (lines.count - 1, lines.joined(separator: "\n") + "\n")
        }
    }

    /// CSV をメーター [slot] の記録として読み込む。読み込んだ行数と、読めなかった行数を返す
    func importCsv(_ slot: String, _ text: String) -> (Int, Int) {
        let formats = HistoryCsv.importFormats()
        var rows: [(String, Int64, Double)] = []
        var bad = 0
        for (i, raw) in text.components(separatedBy: CharacterSet.newlines).enumerated() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.isEmpty { continue }
            if i == 0 && HistoryCsv.isHeader(line) { continue }
            if let r = HistoryCsv.parseLine(line, formats) { rows.append(r) } else { bad += 1 }
        }
        queue.sync { transaction { for (k, t, v) in rows { insert(slot, k, t / 1000 * 1000, v, false) } } }
        notify()
        return (rows.count, bad)
    }

    // MARK: - 片付け

    private func cleanupLoop() {
        cleanup(nowMs())
        queue.asyncAfter(deadline: .now() + 600) { [weak self] in self?.cleanupLoop() }
    }

    private func cleanup(_ now: Int64) {
        guard let slots = _retentions else { return }
        for (g, ms) in slots where ms > 0 {
            let keep = Swift.min(Swift.max(ms, 3_600_000), HistoryStore.MAX_MONTHS * HistoryStore.MONTH_MS)
            exec("DELETE FROM samples WHERE g = ? AND t < ?", [g, now - keep])
        }
        // 消したメーター・グラフでなくなったメーターの記録
        if slots.isEmpty {
            exec("DELETE FROM samples")
        } else {
            exec("DELETE FROM samples WHERE g NOT IN (\(placeholders(slots.count)))", slots.keys.map { $0 as Any })
        }
    }
}
