import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting(String)
    /// 車両と接続中。ignitionOff = ECU は応答しているがエンジンの値を返さない (イグニッション OFF)
    case connected(String, ignitionOff: Bool)
    /// アダプターには接続済みで、車両の応答を待っている
    case waitingForVehicle(String, Double?)
    case error(String, retrying: Bool)

    var isConnected: Bool { if case .connected = self { return true } else { return false } }
    var isDisconnected: Bool { self == .disconnected }
}

/// 通信ログを直近 [capacity] 行だけ保持する
final class LogBuffer: CommLogger {
    struct Line: Identifiable {
        let id: Int
        let time: String
        let direction: LogDirection
        let text: String
    }

    private let capacity: Int
    private var lines: [Line] = []
    private var nextId = 0
    private let lock = NSLock()
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(capacity: Int = 800) { self.capacity = capacity }

    func log(_ direction: LogDirection, _ text: String) {
        lock.lock()
        lines.append(Line(id: nextId, time: fmt.string(from: Date()), direction: direction, text: text))
        nextId += 1
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        lock.unlock()
    }

    /// 変わっていれば (版, 一覧) を返す
    func snapshot(since version: Int) -> (Int, [Line])? {
        lock.lock(); defer { lock.unlock() }
        if nextId == version { return nil }
        return (nextId, lines)
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        nextId += 1
        lock.unlock()
    }

    func asText() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines.map { "\($0.time) \($0.direction.rawValue.padRight(5)) \($0.text)" }.joined(separator: "\n")
    }
}

/// アダプターへの接続と、表示中メーター項目の繰り返し読み出しを管理する。
/// 通信は専用のスレッドでブロッキング呼び出しで行い、結果はメインスレッドへ渡す
final class ObdSession {
    struct TestResult {
        var data: [Int]?
        var error: String?
    }

    let log: LogBuffer

    /// メインスレッドへの通知
    var onState: ((ConnectionState) -> Void)?
    var onValues: (([String: Double]) -> Void)?
    var onRate: ((Double) -> Void)?
    var onSupported: ((Set<Int>?) -> Void)?

    private let lock = NSLock()
    private var _activePids: [PidDef] = []
    private var _activeFallbacks: [String: PidDef] = [:]
    private var _pollIntervals: [String: Int64] = [:]
    private var _state: ConnectionState = .disconnected
    private var _latest: [String: Double] = [:]
    private var tests: [(PidRequest, (TestResult) -> Void)] = []
    private var samples: [([PidDef], ([String: Double]) -> Void)] = []
    private var samplePending: ([PidDef], [String: Double], ([String: Double]) -> Void)? = nil

    /// 実行中の接続 (切断で印を付ける)
    private final class Run {
        var cancelled = false
        var transport: Transport?
    }
    private var run: Run?

    init(log: LogBuffer) { self.log = log }

    var activePids: [PidDef] {
        get { lock.lock(); defer { lock.unlock() }; return _activePids }
        set { lock.lock(); _activePids = newValue; lock.unlock() }
    }
    var activeFallbacks: [String: PidDef] {
        get { lock.lock(); defer { lock.unlock() }; return _activeFallbacks }
        set { lock.lock(); _activeFallbacks = newValue; lock.unlock() }
    }
    var pollIntervals: [String: Int64] {
        get { lock.lock(); defer { lock.unlock() }; return _pollIntervals }
        set { lock.lock(); _pollIntervals = newValue; lock.unlock() }
    }
    var state: ConnectionState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }
    /// 最新の値 (どのスレッドからでも読める)
    var latestValues: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return _latest
    }

    private func setState(_ s: ConnectionState, _ r: Run) {
        lock.lock()
        let live = !r.cancelled
        if live { _state = s }
        lock.unlock()
        if live { let cb = onState; DispatchQueue.main.async { cb?(s) } }
    }

    private func publishValues(_ v: [String: Double], _ r: Run) {
        lock.lock()
        let live = !r.cancelled
        if live { _latest = v }
        lock.unlock()
        if live { let cb = onValues; DispatchQueue.main.async { cb?(v) } }
    }

    private func publishRate(_ v: Double) { let cb = onRate; DispatchQueue.main.async { cb?(v) } }
    private func publishSupported(_ s: Set<Int>?) { let cb = onSupported; DispatchQueue.main.async { cb?(s) } }

    // MARK: - 外から

    /// カスタム PID 編集画面の「車両から読む」用
    func testQuery(_ request: PidRequest, completion: @escaping (TestResult) -> Void) {
        let st = state
        switch st {
        case .connected, .waitingForVehicle: break
        default:
            completion(TestResult(data: nil, error: "未接続です。先にダッシュボードで「接続」してください"))
            return
        }
        var done = false
        let doneLock = NSLock()
        let finish: (TestResult) -> Void = { r in
            doneLock.lock()
            let first = !done
            done = true
            doneLock.unlock()
            if first { DispatchQueue.main.async { completion(r) } }
        }
        lock.lock(); tests.append((request, finish)); lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { finish(TestResult(data: nil, error: "タイムアウトしました")) }
    }

    /// [defs] の値を 1 回だけ読む (記録用。呼び出したスレッドで待つ)。接続していなければ nil
    func sampleBlocking(_ defs: [PidDef], timeoutSec: Double = 20) -> [String: Double]? {
        if !state.isConnected || defs.isEmpty { return nil }
        let sem = DispatchSemaphore(value: 0)
        var result: [String: Double]? = nil
        let resultLock = NSLock()
        lock.lock()
        samples.append((defs, { v in resultLock.lock(); result = v; resultLock.unlock(); sem.signal() }))
        lock.unlock()
        if sem.wait(timeout: .now() + timeoutSec) == .timedOut { return nil }
        resultLock.lock(); defer { resultLock.unlock() }
        return result
    }

    func connect(_ settings: AppSettings) {
        disconnect()
        let r = Run()
        lock.lock(); run = r; lock.unlock()
        let t = Thread { [weak self] in self?.main(settings, r) }
        t.name = "obd-session"
        t.qualityOfService = .userInitiated
        t.start()
    }

    func disconnect() {
        lock.lock()
        let r = run
        run = nil
        r?.cancelled = true
        let pendingTests = tests
        tests.removeAll()
        let pendingSamples = samples
        samples.removeAll()
        _state = .disconnected
        _latest = [:]
        lock.unlock()
        r?.transport?.close()
        for (_, cb) in pendingTests { cb(TestResult(data: nil, error: "切断しました")) }
        for (_, cb) in pendingSamples { cb([:]) }
        let s = onState, v = onValues, rt = onRate
        DispatchQueue.main.async { s?(.disconnected); v?([:]); rt?(0) }
    }

    // MARK: - 通信スレッド

    private enum SessionEnd { case noAdapter, lost, stop }
    private struct StopSession: Error { let message: String }

    /// 中断されていれば例外にする
    private func check(_ r: Run) throws {
        if r.cancelled { throw CancellationError() }
    }

    /// [ms] だけ待つ (中断されたらすぐ戻る)
    private func sleep(_ ms: Int, _ r: Run) {
        var left = ms
        while left > 0 && !r.cancelled {
            let s = Swift.min(left, 100)
            Thread.sleep(forTimeInterval: Double(s) / 1000)
            left -= s
        }
    }

    private func main(_ settings: AppSettings, _ r: Run) {
        var attempt = 0
        while !r.cancelled {
            attempt += 1
            let end = runSession(settings, r)
            if r.cancelled || end == .stop { break }
            if !settings.autoReconnect || (end == .noAdapter && attempt >= 50) { break }
            sleep(3000, r)
        }
    }

    private func createProtocol(_ settings: AppSettings, _ r: Run) throws -> ObdProtocol {
        let opts = Elm327Protocol.Options(protocolCode: settings.elmProtocol, singleResponseHint: settings.elmSingleResponseHint)
        switch settings.connectionType {
        case .SIMULATOR:
            return SimulatorProtocol()
        case .WIFI:
            setState(.connecting("Wi-Fi のアダプター (\(settings.wifiHost):\(settings.wifiPort)) に接続しています…"), r)
            let t = TcpTransport(host: settings.wifiHost, port: settings.wifiPort)
            r.transport = t
            try t.open()
            log.log(.INFO, "Wi-Fi: \(settings.wifiHost):\(settings.wifiPort) に接続しました")
            return Elm327Protocol(transport: t, options: opts, logger: log)
        case .BLE:
            guard let idText = settings.bleDeviceId, let id = UUID(uuidString: idText) else {
                throw StopSession(message: "Bluetooth のアダプターが選ばれていません。設定でアダプターを選んでください")
            }
            let name = settings.bleDeviceName.isEmpty ? "アダプター" : settings.bleDeviceName
            setState(.connecting("「\(name)」に接続しています…"), r)
            let t = BleTransport(deviceId: id, name: name)
            r.transport = t
            try t.open()
            log.log(.INFO, "Bluetooth: 「\(name)」に接続しました")
            return Elm327Protocol(transport: t, options: opts, logger: log)
        }
    }

    private func runSession(_ settings: AppSettings, _ r: Run) -> SessionEnd {
        var proto: ObdProtocol? = nil
        var adapterReady = false
        defer {
            proto?.close()
            r.transport?.close()
            r.transport = nil
        }
        do {
            setState(.connecting("アダプターを探しています…"), r)
            let p = try createProtocol(settings, r)
            proto = p
            try check(r)
            setState(.connecting("アダプターを初期化しています…"), r)
            let adapter = try p.initAdapter()
            adapterReady = true
            log.log(.INFO, "アダプター: \(adapter)")
            while !r.cancelled {
                let vehicle = try waitForVehicle(p, adapter, settings, r)
                log.log(.INFO, "車両に接続: \(vehicle)")
                try pollVehicle(p, "\(adapter) / \(vehicle)", r)
                try check(r)
                if !settings.waitForVehicle {
                    throw OBDError("車両からの応答が途絶えました (イグニッション OFF?)")
                }
                log.log(.INFO, "車両からの応答が途絶えました。イグニッション ON を待ちます")
            }
            return .lost
        } catch is CancellationError {
            return .stop
        } catch let e as StopSession {
            log.log(.INFO, e.message)
            setState(.error(e.message, retrying: false), r)
            publishValues([:], r)
            publishRate(0)
            return .stop
        } catch {
            if r.cancelled { return .stop }
            let msg = error.localizedDescription
            log.log(.ERROR, msg)
            setState(.error(msg, retrying: settings.autoReconnect), r)
            publishValues([:], r)
            publishRate(0)
            return adapterReady ? .lost : .noAdapter
        }
    }

    private func drainTests(_ p: ObdProtocol) {
        while true {
            lock.lock()
            var item: (PidRequest, (TestResult) -> Void)? = nil
            if !tests.isEmpty { item = tests.removeFirst() }
            lock.unlock()
            guard let it = item else { return }
            let (req, cb) = it
            log.log(.INFO, "テスト読み出し: \(req)")
            let data = p.query(req)
            cb(TestResult(data: data, error: data == nil ? (p.lastFailure ?? "応答なし") : nil))
        }
    }

    /// 記録用の読み出しを少しずつ進める。1 サイクルに数項目だけ読み、表示中のメーターの更新を止めない
    private func drainSamples(_ reader: ObdReader) {
        var cur = samplePending
        if cur == nil {
            lock.lock()
            if !samples.isEmpty {
                let (defs, cb) = samples.removeFirst()
                cur = (defs, [:], cb)
            }
            lock.unlock()
        }
        guard let c = cur else { return }
        var defs = c.0
        var got = c.1
        let cb = c.2
        let block = defs.filter { $0.kind == .bmwBlock }
        let others = defs.filter { $0.kind != .bmwBlock }
        let chunk = block + others.prefix(3)
        let rest = Array(others.dropFirst(3))
        _ = reader.poll(chunk, &got, forceAll: true)
        if rest.isEmpty {
            samplePending = nil
            cb(got)
        } else {
            defs = rest
            samplePending = (defs, got, cb)
        }
    }

    /// 車両が応答するまで 5 秒ごとに確認する。車両の説明文を返す
    private func waitForVehicle(_ p: ObdProtocol, _ adapter: String, _ settings: AppSettings, _ r: Run) throws -> String {
        let start = nowMs()
        var first = true
        while true {
            try check(r)
            drainTests(p)
            if first { setState(.connecting("車両と通信を確立しています…"), r) }
            if let v = try p.connectVehicle() { return v }
            try check(r)
            if let t = r.transport, !t.isAlive { throw OBDError("アダプターとの接続が切れました") }
            let reason = p.lastFailure ?? "応答なし"
            if !settings.waitForVehicle {
                throw OBDError("車両に接続できません: \(reason) (イグニッション ON を確認してください)")
            }
            if first { log.log(.INFO, "車両が応答しません (\(reason))。イグニッション ON を待ちます") }
            first = false
            let volt = p.readAdapterVoltage()
            publishValues(volt.map { ["BATTERY": $0] } ?? [:], r)
            publishRate(0)
            setState(.waitingForVehicle(adapter, volt), r)
            let limitMin = settings.waitTimeoutMin
            if limitMin > 0 && nowMs() - start > Int64(limitMin) * 60_000 {
                throw StopSession(message: "\(limitMin) 分間車両が応答しなかったため、バッテリー保護のため待機を終了しました")
            }
            for _ in 0..<25 {
                sleep(200, r)
                try check(r)
                drainTests(p)
            }
        }
    }

    /// メーター表示中の読み出しループ。車両の応答が途絶えたら戻る
    private func pollVehicle(_ p: ObdProtocol, _ desc: String, _ r: Run) throws {
        let reader = ObdReader(proto: p, logger: log)
        setState(.connecting("対応項目を確認しています…"), r)
        reader.detectSupported()
        publishSupported(reader.supported)
        var ignitionOff = reader.supported == nil && p.lastResponded
        reader.ignitionOff = ignitionOff
        setState(.connected(desc, ignitionOff: ignitionOff), r)

        var values: [String: Double] = [:]
        var deadCycles = 0
        var count = 0
        var windowStart = nowMs()
        var lastPublish: Int64 = 0
        var lastSupported = reader.supported
        while !r.cancelled {
            drainTests(p)
            drainSamples(reader)
            if let t = r.transport, !t.isAlive { throw OBDError("アダプターとの接続が切れました") }
            let defs = activePids
            if defs.isEmpty { sleep(100, r); continue }
            reader.intervals = pollIntervals
            let res = reader.poll(defs, &values, fallbacks: activeFallbacks)
            try check(r)
            let t = nowMs()
            if t - lastPublish >= 100 {
                publishValues(values, r)
                lastPublish = t
            }
            if reader.supported != lastSupported {
                lastSupported = reader.supported
                publishSupported(reader.supported)
            }
            count += res.ok + res.failed
            deadCycles = (!res.vehicleAlive && res.failed > 0) ? deadCycles + 1 : 0
            if deadCycles >= 5 {
                publishValues([:], r)
                publishRate(0)
                return
            }
            let nowOff = res.ignitionOffResult
            let anyOk = res.stdOk > 0 || (res.stdRefused == 0 && res.ok > 0)
            if nowOff != ignitionOff && (nowOff || anyOk) {
                ignitionOff = nowOff
                if ignitionOff { reader.ignitionOff = true } else { reader.onIgnitionOn() }
                log.log(.INFO, ignitionOff ? "ECU は応答していますが値を返しません (イグニッション OFF)" : "イグニッション ON を検出しました")
                if !ignitionOff && reader.supported == nil {
                    reader.detectSupported()
                    publishSupported(reader.supported)
                }
                setState(.connected(desc, ignitionOff: ignitionOff), r)
            }
            if ignitionOff {
                publishRate(0)
                for _ in 0..<5 {
                    sleep(200, r)
                    try check(r)
                    drainTests(p)
                    drainSamples(reader)
                }
                continue
            }
            let now = nowMs()
            if now - windowStart >= 1000 {
                publishRate(Double(count) * 1000 / Double(now - windowStart))
                count = 0
                windowStart = now
            }
            if res.ok + res.failed == 0 { sleep(20, r) }
        }
    }
}
