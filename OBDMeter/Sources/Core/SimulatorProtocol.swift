import Foundation

/// 車なしで画面確認するための疑似車両。実際の OBD 応答と同じバイト列を作って返すので、デコード処理もそのまま検証できる。
/// 走行パターン: 加速 → 巡航 → 減速 → 停車 を繰り返す
final class SimulatorProtocol: ObdProtocol {
    private let start = nowMs()
    private var coolant = 25.0
    private let responseDelayMs: Int

    init(responseDelayMs: Int = 15) { self.responseDelayMs = responseDelayMs }

    /// 実車同様、0x5C (油温) と 0x46 (外気温) は非対応にしておく
    private let supportedPids: Set<Int> = [
        0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11,
        0x1F, 0x20, 0x2F, 0x33, 0x3C, 0x40, 0x42, 0x49,
    ]

    var lastFailure: String? { nil }
    var lastResponded: Bool { false }

    func initAdapter() throws -> String { "シミュレーター" }
    func connectVehicle() throws -> String? { "疑似 E90 335i (標準 PID と BMW 固有の測定値)" }
    func readSupportedPids() -> Set<Int> { readSupportedPidsDefault(self) }

    private struct State { let rpm: Double; let speed: Double; let throttle: Double; let map: Double }

    private func elapsed() -> Double { Double(nowMs() - start) / 1000.0 }

    private func state() -> State {
        let t = elapsed()
        let phase = t.truncatingRemainder(dividingBy: 40)
        var speed: Double
        var throttle: Double
        if phase < 12 { speed = phase / 12 * 100; throttle = 65 + 25 * sin(t * 1.3) }
        else if phase < 25 { speed = 100 + 4 * sin(t); throttle = 22 + 4 * sin(t * 0.7) }
        else if phase < 35 { speed = 100 * (1 - (phase - 25) / 10); throttle = 0 }
        else { speed = 0; throttle = 0 }
        // 6 速 AT 風のギア比で回転数を決める
        let gears: [Double] = [0, 25, 45, 65, 85, 110, 999]
        var gear = 1
        while gear < gears.count - 1 && speed >= gears[gear] { gear += 1 }
        let ratio: [Double] = [0, 120, 70, 50, 38, 30, 25]
        let rpm = Swift.max(750 + 30 * sin(t * 5), speed * ratio[gear] + throttle * 15)
        let map = 30 + throttle * 0.75 + 3 * sin(t * 3)
        return State(rpm: Swift.min(rpm, 7200), speed: Swift.max(speed, 0), throttle: Swift.min(Swift.max(throttle, 0), 100), map: map)
    }

    private func pause() { if responseDelayMs > 0 { Thread.sleep(forTimeInterval: Double(responseDelayMs) / 1000) } }

    func readPid(_ pid: Int) -> [Int]? {
        pause()
        let s = state()
        let t = elapsed()
        coolant = Swift.min(92, coolant + 0.05)
        func u8(_ v: Double) -> Int { Swift.min(Swift.max(Int(v), 0), 255) }
        func u16(_ v: Double) -> [Int] { let x = Swift.min(Swift.max(Int(v), 0), 65535); return [x >> 8, x & 0xFF] }
        func bitmap(_ base: Int) -> [Int] {
            var out = [0, 0, 0, 0]
            for p in supportedPids {
                let i = p - base - 1
                if i >= 0 && i < 32 { out[i / 8] |= 1 << (7 - i % 8) }
            }
            return out
        }
        switch pid {
        case 0x00, 0x20, 0x40, 0x60: return (pid == 0 || supportedPids.contains(pid)) ? bitmap(pid) : nil
        case 0x04: return [u8((15 + s.throttle * 0.8) * 255 / 100)]
        case 0x05: return [u8(coolant + 40)]
        case 0x06, 0x08: return [u8(128 + 4 * sin(t * 2 + Double(pid)))]
        case 0x07, 0x09: return [u8(131)]
        case 0x0B: return [u8(s.map)]
        case 0x0C: return u16(s.rpm * 4)
        case 0x0D: return [u8(s.speed)]
        case 0x0E: return [u8((18 + 10 * sin(t) + 64) * 2)]
        case 0x0F: return [u8(72)]
        case 0x10: return u16((4 + s.rpm / 7000 * s.throttle * 1.6) * 100)
        case 0x11: return [u8((14 + s.throttle * 0.86) * 255 / 100)]
        case 0x1F: return u16(t)
        case 0x2F: return [u8(62.0 * 255 / 100)]
        case 0x33: return [101]
        case 0x3C: return u16((450 + s.throttle * 3 + 40) * 10)
        case 0x42: return u16(14.1 * 1000 + 100 * sin(t * Double.pi / 10))
        case 0x49: return [u8(s.throttle * 255 / 100)]
        default: return nil
        }
    }

    /// BMW の測定値 ID → 項目
    private lazy var blockDefs: [Int: PidDef] = {
        var m: [Int: PidDef] = [:]
        for d in Pids.all where d.kind == .bmwBlock && m[d.blockId] == nil { m[d.blockId] = d }
        return m
    }()

    private func blockRaw(_ id: Int, _ size: Int, _ s: State, _ t: Double) -> Int64 {
        func phys(_ v: Double, _ mul: Double, _ add: Double = 0) -> Int64 { Int64(((v - add) / mul).rounded()) }
        switch id {
        case 0x4807: return phys(s.rpm, 1)
        case 0x581F: return phys(coolant, 0.75, -48)
        case 0x460A: return phys(14.1 + 0.1 * sin(t * 0.5), 0.015)
        case 0x4200: return phys(32 + 2 * sin(t * 0.05), 0.75, -48)
        case 0x58D5: return phys(35 + s.throttle * 0.3, 1, -48)
        case 0x5A50, 0x5A51: return phys(s.throttle > 60 ? 0.82 : 1.0 + 0.02 * sin(t * 3 + Double(id)), 1 / 1024.0)
        case 0x5A29: return phys(s.throttle, 0.390625)
        case 0x5A25: return phys((1.2 + s.rpm / 2500) * 1000, 1)
        case 0x5A2C: return phys(1013 + s.throttle * 10 + 20 * sin(t * 2), 0.0390625)
        case 0x4201: return phys(1013, 0.08291752636432648)
        default:
            // 項目の換算式 (1 次式) を逆算して、範囲の 35〜65% あたりで値を動かす
            guard let d = blockDefs[id] else { return Int64(128 + 60 * sin(t * 0.3 + Double(id))) }
            let zero = [Int](repeating: 0, count: size)
            var one = [Int](repeating: 0, count: size)
            one[size - 1] = 1
            guard let v0 = d.decode(zero), let v1 = d.decode(one) else { return 0 }
            let a = v1 - v0
            if a == 0 { return 0 }
            let target = d.min + (d.max - d.min) * (0.5 + 0.15 * sin(t * 0.25 + Double(id % 17)))
            return Int64(((target - v0) / a).rounded())
        }
    }

    /// 生の値を [size] バイト (ビッグエンディアン、負の値は 2 の補数) にする
    private func bytesOf(_ raw: Int64, _ size: Int) -> [Int] {
        let bits = 8 * size
        let v = bits >= 63 ? raw : raw & ((Int64(1) << Int64(bits)) - 1)
        return (0..<size).reversed().map { Int((v >> Int64(8 * $0)) & 0xFF) }
    }

    func query(_ request: PidRequest) -> [Int]? {
        if request.mode == 0x01 && request.pid.count == 1 { return readPid(request.pid[0]) }
        pause()
        let t = elapsed()
        if request.mode == 0x21, let def = request.setup.last {
            if def.count < 2 || def[0] != 0x2C { return nil }
            let s = state()
            var out: [Int] = []
            var i = 2
            while i + 4 < def.count {
                let size = def[i + 2]
                let id = (def[i + 3] << 8) | def[i + 4]
                out += bytesOf(blockRaw(id, size, s, t), size)
                i += 6
            }
            return out
        }
        if (request.mode == 0x30 || request.mode == 0x22) && request.header == "7E0" {
            return (0..<48).map { i in Swift.min(Swift.max(Int(128 + 60 * sin(t * 0.15 + Double(i) * 0.7)), 0), 255) }
        }
        if request.mode == 0x06 {
            // 失火カウンタ (TID 0C = 今回の運転の回数)
            let n = Int(t / 20) % 5
            return [0x0C, 0x24, n >> 8, n & 0xFF, 0, 0, 0xFF, 0xFF]
        }
        let tick = Int((nowMs() - start) / 100 % 256)
        let p0 = request.pid[safe: 0] ?? 0
        let p1 = request.pid[safe: 1] ?? 0
        return [p0, p1, tick, (tick * 7) & 0xFF]
    }

    func readAdapterVoltage() -> Double? { 14.2 }

    func close() {}
}
