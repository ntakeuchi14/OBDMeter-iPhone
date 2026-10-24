import Foundation

/// グラフ・変動監視の記録。接続した直後に全項目を 1 回読み、その後は項目ごとの間隔で読む
/// (表示中のページに無い項目も読む。端末のセンサーの項目は接続していなくても記録する)。
/// 「変化したときだけ記録する」項目は、項目の取得周期ごとに値を見て、前回記録した値から変わったときだけ記録する
final class Recorder {
    private let session: ObdSession
    private let history: HistoryStore
    private let sensors: DeviceSensors
    private let lock = NSLock()
    private var _rules: [ReadPlan.RecordTarget: ReadPlan.RecordRule] = [:]
    private var _catalog = PidCatalog()
    private var started = false

    init(session: ObdSession, history: HistoryStore, sensors: DeviceSensors) {
        self.session = session
        self.history = history
        self.sensors = sensors
    }

    var rules: [ReadPlan.RecordTarget: ReadPlan.RecordRule] {
        get { lock.lock(); defer { lock.unlock() }; return _rules }
        set { lock.lock(); _rules = newValue; lock.unlock() }
    }

    var catalog: PidCatalog {
        get { lock.lock(); defer { lock.unlock() }; return _catalog }
        set { lock.lock(); _catalog = newValue; lock.unlock() }
    }

    func start() {
        if started { return }
        started = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "obd-recorder"
        t.qualityOfService = .utility
        t.start()
    }

    private func loop() {
        var nextDue: [ReadPlan.RecordTarget: Int64] = [:]
        let changes = ChangeRecorder()
        var eventLast: [ReadPlan.RecordTarget: Double?] = [:]
        var wasConnected = false
        while true {
            Thread.sleep(forTimeInterval: Double(ReadPlan.CHANGE_MIN_MS) / 1000)
            let connected = session.state.isConnected
            if connected && !wasConnected { nextDue = nextDue.filter { $0.key.key.hasPrefix("DEV_") } }
            wasConnected = connected
            let now = nowMs()
            let rules = self.rules
            for slot in history.takeCleared() {
                eventLast = eventLast.filter { $0.key.slot != slot }
                changes.forget(slot)
            }
            history.storeRows(changes.retain(Set(rules.keys)))
            let due = rules.filter { (t, _) in (nextDue[t] ?? 0) <= now && (connected || t.key.hasPrefix("DEV_")) }
            if due.isEmpty { continue }
            let dueKeys = Set(due.keys.map { $0.key })
            let dev = sensors.values
            var live = session.latestValues
            for (k, v) in dev { live[k] = v }
            var activeKeys = Set(session.activePids.map { $0.key })
            activeKeys.formUnion(dev.keys)
            let (reuse, need) = ReadPlan.splitSample(dueKeys, live, activeKeys)
            let cat = catalog
            let defs = need.filter { !$0.hasPrefix("DEV_") }.compactMap { cat.get($0) }
            var got: [String: Double] = [:]
            if !defs.isEmpty && connected {
                guard let g = session.sampleBlocking(defs) else { continue }
                got = g
            }
            var read = reuse
            for (k, v) in got { read[k] = v }
            let needSet = Set(need)
            let time = nowMs()
            var rows: [String: [String: Double]] = [:]
            var changeRows: [HistoryRow] = []
            var eventRows: [HistoryRow] = []
            for (t, rule) in due {
                // 表示していない項目を記録のために読むときは、変化だけの記録でも 1 秒に 1 回まで
                let ms = (needSet.contains(t.key) && !t.key.hasPrefix("DEV_")) ? Swift.max(rule.intervalMs, ReadPlan.CHANGE_SAMPLE_MIN_MS) : rule.intervalMs
                nextDue[t] = now + ms
                guard let v = read[t.key] else { continue }
                if rule.events {
                    if eventLast[t] == nil { eventLast[t] = .some(history.lastRow(t.slot, t.key)?.0.v) }
                    let last: Double? = eventLast[t] ?? nil
                    if Monitor.shouldRecord(v, last) {
                        eventRows.append(HistoryRow(slot: t.slot, key: t.key, t: time, v: v, cont: false))
                        eventLast[t] = .some(v)
                    }
                } else if rule.onChangeOnly {
                    if !changes.has(t) {
                        let lr = history.lastRow(t.slot, t.key)
                        changes.seed(t, lr?.0, lr?.1 == true)
                    }
                    changeRows += changes.observe(t, v, time, ms)
                } else {
                    rows[t.slot, default: [:]][t.key] = v
                }
            }
            history.store(rows, time)
            history.storeRows(changeRows)
            history.storeEvents(eventRows)
        }
    }
}
