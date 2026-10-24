import Foundation

/// 1 サイクルで何をどう読むかを決める計算 (通信はしない)
enum PollPlan {
    /// 表示用の測定値ブロックの最初の番号 (F0)。F0〜F8 を取得周期ごとに使う
    static let LID_FIRST = 0xF0
    /// グラフ記録用の 1 回読みで使う番号
    static let LID_SAMPLE = 0xF9
    static let MAX_GROUPS = 9

    /// 宛先の並び順のキー。標準 → ヘッダー指定 → 拡張アドレス (BMW 方式) の順
    static func addressKey(_ d: PidDef) -> String {
        guard let r = d.request else { return "" }
        if r.header.isEmpty && r.canExtAddress.isEmpty { return "" }
        return (r.canExtAddress.isEmpty ? "1/" : "2/") + r.header + "/" + r.canExtAddress
    }

    /// 項目ごとの取得周期を、派生項目の依存先にも当てたもの
    static func effectiveIntervals(_ defs: [PidDef], _ intervals: [String: Int64]) -> [String: Int64] {
        if intervals.isEmpty { return [:] }
        var m = intervals
        for d in defs where d.kind == .derived {
            guard let iv = intervals[d.key] else { continue }
            for dep in d.deps where intervals[dep] == nil {
                m[dep] = Swift.min(m[dep] ?? Int64.max, iv)
            }
        }
        return m
    }

    /// BMW の測定値を取得周期ごとのまとまりに分け、番号 (F0, F1, …) を割り当てる。周期の短い順
    static func blockGroups(_ block: [PidDef], _ intervals: [String: Int64]) -> [(Int, [PidDef])] {
        var byInterval: [Int64: [PidDef]] = [:]
        var order: [Int64] = []
        for d in block {
            let iv = intervals[d.key] ?? 0
            if byInterval[iv] == nil { order.append(iv) }
            byInterval[iv, default: []].append(d)
        }
        var groups = order.sorted().map { byInterval[$0] ?? [] }
        if groups.count > MAX_GROUPS {
            groups = Array(groups.prefix(MAX_GROUPS - 1)) + [groups.dropFirst(MAX_GROUPS - 1).flatMap { $0 }]
        }
        return groups.enumerated().map { (LID_FIRST + $0.offset, $0.element) }
    }
}

/// プロトコルを使って、表示中の項目を 1 サイクル分読み出す。
/// - 一時的な読み出し失敗では直前の値を保持する。[HOLD_FAILS] 回連続で失敗したら値を消す
/// - 対応 PID 一覧で「非対応」の項目も、画面に置かれていれば時々試す
/// - 成功⇔失敗が切り替わったときだけ、理由付きでログに出す
final class ObdReader {
    static let HOLD_FAILS = 3

    struct PollResult {
        var ok: Int
        var failed: Int
        var refused: Int = 0
        var stdOk: Int = 0
        var stdRefused: Int = 0
        /// ECU から何らかの応答があった
        var vehicleAlive: Bool { ok > 0 || refused > 0 }
        /// 標準 PID がすべて拒否されている (= イグニッション OFF)
        var ignitionOffResult: Bool { stdOk == 0 && stdRefused > 0 }
    }

    private final class Counter {
        var ok = 0, failed = 0, refused = 0, stdOk = 0, stdRefused = 0
    }

    private let proto: ObdProtocol
    private let logger: CommLogger

    /// 車両が対応している Mode 01 PID。取得できなかった場合は nil (= 全部試す)
    private(set) var supported: Set<Int>? = nil

    private var failStreak: [String: Int] = [:]
    private var failing = Set<String>()
    private var refusedKeys = Set<String>()
    private var cycle: Int64 = 0
    private var requestCache: [PidRequest: [Int]?] = [:]
    private var adapterVoltageSupported = true
    /// 項目ごとの取得周期 (ミリ秒)
    var intervals: [String: Int64] = [:]
    private var lastRead: [String: Int64] = [:]
    private var effIntervals: [String: Int64] = [:]

    init(proto: ObdProtocol, logger: CommLogger) {
        self.proto = proto
        self.logger = logger
    }

    private func notDue(_ key: String, _ values: [String: Double], _ now: Int64) -> Bool {
        guard let iv = effIntervals[key], iv > 0, values[key] != nil, let last = lastRead[key] else { return false }
        return now - last < iv
    }

    func detectSupported() {
        let s = proto.readSupportedPids()
        supported = s.isEmpty ? nil : s
        if let s = supported {
            logger.log(.INFO, "対応 PID: " + s.sorted().map { String(format: "%02X", $0) }.joined(separator: " "))
        }
    }

    func isAvailable(_ def: PidDef) -> Bool {
        switch def.kind {
        case .mode01: return supported?.contains(def.pid) ?? true
        case .adapterVoltage: return adapterVoltageSupported
        case .derived: return def.deps.compactMap { Pids.get($0) }.allSatisfy { isAvailable($0) }
        default: return true
        }
    }

    /// [defs] の値を読み、[values] を更新する。[fallbacks] は「メイン項目のキー → 代替項目」
    func poll(_ defs: [PidDef], _ values: inout [String: Double], fallbacks: [String: PidDef] = [:], forceAll: Bool = false) -> PollResult {
        cycle += 1
        requestCache.removeAll()
        var direct: [PidDef] = []
        var seen = Set<String>()
        func add(_ d: PidDef) { if !seen.contains(d.key) { seen.insert(d.key); direct.append(d) } }
        for d in defs {
            switch d.kind {
            case .derived: d.deps.compactMap { Pids.get($0) }.forEach(add)
            case .device: break
            default: add(d)
            }
        }
        let c = Counter()
        effIntervals = forceAll ? [:] : PollPlan.effectiveIntervals(defs, intervals)
        let now = nowMs()
        let block = direct.filter { $0.kind == .bmwBlock }
        // アダプターの宛先の切り替えを減らすよう、宛先ごとにまとめて読む (並びは安定)
        let ordered = direct.enumerated().sorted { l, r in
            let a = PollPlan.addressKey(l.element), b = PollPlan.addressKey(r.element)
            return a == b ? l.offset < r.offset : a < b
        }.map { $0.element }
        for d in ordered where d.kind != .bmwBlock {
            if !forceAll && notDue(d.key, values, now) { continue }
            readItem(d, &values, c, forceAll: forceAll)
            lastRead[d.key] = now
        }
        if !block.isEmpty {
            if forceAll {
                readBlock(block, &values, c, forceAll: true, lid: multiBlockUnsupported ? PollPlan.LID_FIRST : PollPlan.LID_SAMPLE)
            } else if multiBlockUnsupported || effIntervals.isEmpty {
                if block.contains(where: { !notDue($0.key, values, now) }) {
                    readBlock(block, &values, c, forceAll: false)
                    for d in block { lastRead[d.key] = now }
                }
            } else {
                for (lid, g) in PollPlan.blockGroups(block, effIntervals) where g.contains(where: { !notDue($0.key, values, now) }) {
                    readBlock(g, &values, c, forceAll: false, lid: lid)
                    for d in g { lastRead[d.key] = now }
                }
            }
        }
        for d in defs where d.kind == .derived {
            if let v = d.derive(values) { values[d.key] = v } else { values.removeValue(forKey: d.key) }
        }
        // 代替項目: メインの値が無いときだけ読む
        var fallbackOk = 0
        for (primary, fb) in fallbacks {
            if values[primary] != nil {
                values.removeValue(forKey: fb.key)
                continue
            }
            let fc = Counter()
            readItem(fb, &values, fc)
            fallbackOk += fc.ok
            c.failed += fc.failed
            c.refused += fc.refused
        }
        return PollResult(ok: c.ok + fallbackOk, failed: c.failed, refused: c.refused, stdOk: c.stdOk, stdRefused: c.stdRefused)
    }

    /// DME が登録を断った測定値 (キー → 断られたサイクル)
    private var blockRejected: [String: Int64] = [:]
    /// DME が F0 以外の番号で読めなかった (1 つしか登録できない)
    private(set) var multiBlockUnsupported = false
    private var lidOk = Set<Int>()
    /// イグニッション OFF 中かどうか (セッションが設定する)
    var ignitionOff = false

    /// イグニッション ON になったら、OFF 中に覚えた「非対応」を忘れてやり直す
    func onIgnitionOn() {
        ignitionOff = false
        multiBlockUnsupported = false
        lidOk.removeAll()
        blockRejected.removeAll()
        failStreak.removeAll()
    }

    private func giveUpMultiBlock(_ reason: String) {
        if multiBlockUnsupported { return }
        multiBlockUnsupported = true
        lidOk.removeAll()
        logger.log(.INFO, "測定値の登録を複数持てない DME のため、まとめて読みます (\(reason))")
    }

    private func readBlock(_ items: [PidDef], _ values: inout [String: Double], _ c: Counter, forceAll: Bool, lid: Int = PollPlan.LID_FIRST) {
        let use = items.filter { d in
            guard let r = blockRejected[d.key] else { return true }
            return forceAll || cycle - r >= 300
        }
        let useKeys = Set(use.map { $0.key })
        for d in items where !useKeys.contains(d.key) { values.removeValue(forKey: d.key) }
        if use.isEmpty { return }
        // 同じ測定値は 1 回だけ登録し、ID 順に並べる
        var idSeen = Set<Int>()
        var ids: [PidDef] = []
        for d in use where !idSeen.contains(d.blockId) { idSeen.insert(d.blockId); ids.append(d) }
        ids.sort { $0.blockId < $1.blockId }
        var offsets: [Int: Int] = [:]
        var total = 0
        for d in ids { offsets[d.blockId] = total; total += d.blockSize }
        let data = proto.query(BmwItems.blockRequest(ids, lid: lid))
        if let data = data, data.count >= total {
            lidOk.insert(lid)
            for d in use {
                let off = offsets[d.blockId] ?? 0
                let v = d.decode(Array(data[off..<(off + d.blockSize)]))
                if let v = v {
                    values[d.key] = v
                    blockRejected.removeValue(forKey: d.key)
                    failStreak[d.key] = 0
                    c.ok += 1
                } else {
                    values.removeValue(forKey: d.key)
                    c.failed += 1
                }
            }
            return
        }
        let refused = proto.lastResponded
        if ignitionOff {
            for d in use { values.removeValue(forKey: d.key) }
            if refused { c.refused += use.count } else { c.failed += use.count }
            return
        }
        if !multiBlockUnsupported && ((lid != PollPlan.LID_FIRST && !lidOk.contains(lid)) ||
            (lid == PollPlan.LID_FIRST && lidOk.contains(where: { $0 != PollPlan.LID_FIRST }))) {
            giveUpMultiBlock(refused ? "否定応答" : "応答なし")
            return
        }
        if !refused {
            // 応答なし (通信の一時的な失敗など): 直前の値は残し、次のサイクルでまた試す
            for d in use {
                let s = (failStreak[d.key] ?? 0) + 1
                failStreak[d.key] = s
                if s >= ObdReader.HOLD_FAILS { values.removeValue(forKey: d.key) }
            }
            c.failed += use.count
            return
        }
        if lid != PollPlan.LID_FIRST { return }
        c.refused += use.count
        if use.count == 1 {
            blockRejected[use[0].key] = cycle
            values.removeValue(forKey: use[0].key)
            logger.log(.ERROR, use[0].shortName + String(format: ": この DME は測定値 %04X に対応していません", use[0].blockId))
            return
        }
        // どれが断られたかを 1 つずつ確かめる
        for d in use { readBlock([d], &values, c, forceAll: forceAll, lid: lid) }
    }

    private func readItem(_ d: PidDef, _ values: inout [String: Double], _ c: Counter, forceAll: Bool = false) {
        if d.kind == .bmwBlock { readBlock([d], &values, c, forceAll: forceAll); return }
        let streak = failStreak[d.key] ?? 0
        if forceAll {
            // 間引きなし
        } else if !isAvailable(d) {
            // 非対応扱いでも、最初と 50 サイクルごとに一度だけ試す
            if d.kind != .mode01 || (cycle != 1 && cycle % 50 != 0) {
                values.removeValue(forKey: d.key)
                return
            }
        } else {
            // 遅い項目は 8 サイクルに 1 回 (値が無いうちは毎回)
            if d.slow && effIntervals[d.key] == nil && values[d.key] != nil && cycle % 8 != 0 { return }
            // 連続で失敗した項目は 20 サイクルに 1 回だけ再試行 (ECU の拒否なら毎回)
            if streak >= ObdReader.HOLD_FAILS && !refusedKeys.contains(d.key) && cycle % 20 != 0 { return }
        }

        var v: Double? = nil
        switch d.kind {
        case .mode01:
            if let data = proto.readPid(d.pid), data.count >= d.minBytes { v = d.decode(data) }
        case .adapterVoltage:
            v = proto.readAdapterVoltage()
            if v == nil && values["BATTERY"] == nil && streak >= 2 { adapterVoltageSupported = false }
        case .custom, .request:
            if let req = d.request {
                let data: [Int]?
                if let cached = requestCache[req] { data = cached } else {
                    data = proto.query(req)
                    requestCache[req] = .some(data)
                }
                if let data = data {
                    if data.count >= d.minBytes { v = d.decode(data) }
                    if v == nil && !failing.contains(d.key) {
                        logger.log(.ERROR, "\(d.shortName): 応答 \(Hex.of(data)) を換算できません")
                    }
                }
            }
        default:
            v = nil
        }
        let std = d.kind == .mode01
        if let v = v {
            values[d.key] = v
            failStreak[d.key] = 0
            refusedKeys.remove(d.key)
            if std, let s = supported, !s.contains(d.pid) {
                supported = s.union([d.pid])
                logger.log(.INFO, d.shortName + String(format: " (PID %02X) は読めたので対応扱いにします", d.pid))
            }
            if failing.remove(d.key) != nil { logger.log(.INFO, "\(d.shortName): 復帰") }
            c.ok += 1
            if std { c.stdOk += 1 }
        } else {
            if (std || d.kind == .custom || d.kind == .request) && proto.lastResponded {
                c.refused += 1
                if std { c.stdRefused += 1 }
                refusedKeys.insert(d.key)
            } else {
                refusedKeys.remove(d.key)
            }
            failStreak[d.key] = streak + 1
            if streak + 1 >= ObdReader.HOLD_FAILS { values.removeValue(forKey: d.key) }
            if !failing.contains(d.key) {
                failing.insert(d.key)
                var pidText = ""
                if d.kind == .mode01 { pidText = String(format: " (PID %02X)", d.pid) }
                else if d.kind == .custom || d.kind == .request { pidText = " (\(d.request?.description ?? ""))" }
                logger.log(.ERROR, "\(d.shortName)\(pidText) 読み出し失敗: \(proto.lastFailure ?? "応答なし")")
            }
            c.failed += 1
        }
    }
}
