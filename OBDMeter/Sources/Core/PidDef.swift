import Foundation

/// 項目の種類。
/// MODE01: 標準 PID / ADAPTER_VOLTAGE: アダプター測定 / DERIVED: 計算値 / CUSTOM: カスタム PID /
/// REQUEST: Mode 01 以外の要求 (失火カウンタ・BMW の状態読み出し) / BMW_BLOCK: DME の測定値 / DEVICE: 端末のセンサー
enum PidKind {
    case mode01, adapterVoltage, derived, custom, request, bmwBlock, device
}

/// メーターに表示できる項目の定義
struct PidDef {
    var key: String
    var name: String
    var shortName: String
    var unit: String
    var min: Double
    var max: Double
    var decimals: Int = 0
    var warnAbove: Double? = nil
    var warnBelow: Double? = nil
    var kind: PidKind = .mode01
    var pid: Int = -1
    var minBytes: Int = 1
    /// 表示の丸め単位 (0 なら丸めない)。回転数は 10rpm 単位にして数字の震えを抑える
    var displayStep: Double = 0
    /// 変化が遅い項目は数サイクルに 1 回だけ読む
    var slow: Bool = false
    /// 応答データを物理値に変換する (読めなければ nil)
    var decode: ([Int]) -> Double? = { _ in 0 }
    var deps: [String] = []
    var derive: ([String: Double]) -> Double? = { _ in nil }
    /// CUSTOM / REQUEST のときの問い合わせ内容
    var request: PidRequest? = nil
    /// BMW_BLOCK: DME の測定値 ID とバイト数
    var blockId: Int = 0
    var blockSize: Int = 0

    var isCustom: Bool { kind == .custom }

    func format(_ value: Double?) -> String {
        guard let v = value else { return blankText() }
        return String(format: "%.\(decimals)f", v)
    }

    /// 表示の最大の桁の形 (例: 0〜9 → "0"、-40〜150 → "000"、10〜16 小数 1 桁 → "00.0")
    func digitTemplate() -> String {
        let m = Swift.max(Swift.abs(min), Swift.abs(max))
        let s = String(format: "%.\(decimals)f", m)
        return String(s.map { $0.isNumber ? "0" : $0 })
    }

    /// 値が無いときの表示。最大の桁数に合わせて数字を "-" にしたもの
    func blankText() -> String { digitTemplate().replacingOccurrences(of: "0", with: "-") }

    /// 表示用の単位 (全角の ℃ を °C に)
    var unitText: String { unit.replacingOccurrences(of: "℃", with: "°C").replacingOccurrences(of: "℉", with: "°F") }

    /// 一覧などで使う短い説明
    func sourceLabel() -> String {
        switch kind {
        case .mode01: return String(format: "PID %02X", pid)
        case .custom: return "カスタム " + (request?.description ?? "")
        case .request:
            let r = request
            return String(format: "OBD Mode %02X ", r?.mode ?? 0) + "MID " + Hex.compact(r?.pid ?? [])
        case .bmwBlock: return String(format: "BMW DME 測定値 %04X", blockId)
        case .adapterVoltage: return "アダプター測定"
        case .derived: return "計算値"
        case .device: return "端末のセンサー"
        }
    }
}

/// 標準項目とカスタム PID をまとめた一覧。キーで引ける
struct PidCatalog {
    var custom: [PidDef] = []
    private var customByKey: [String: PidDef] = [:]

    init(custom: [PidDef] = []) {
        self.custom = custom
        var m: [String: PidDef] = [:]
        for d in custom { m[d.key] = d }
        self.customByKey = m
    }

    var all: [PidDef] { Pids.all + custom }

    func get(_ key: String) -> PidDef? { customByKey[key] ?? Pids.get(key) }
}

private func a(_ d: [Int]) -> Double? { d.isEmpty ? nil : Double(d[0]) }
private func ab(_ d: [Int]) -> Double? { d.count < 2 ? nil : Double(d[0] * 256 + d[1]) }

enum Pids {
    /// 全項目 (標準 + BMW + 端末のセンサー)
    static let all: [PidDef] = standard() + BmwItems.all + DeviceItems.all

    private static let byKey: [String: PidDef] = {
        var m: [String: PidDef] = [:]
        for d in all where m[d.key] == nil { m[d.key] = d }
        return m
    }()

    static func get(_ key: String) -> PidDef? { byKey[key] }

    static func isBmwSpecific(_ d: PidDef) -> Bool { d.kind == .bmwBlock || d.name.contains("BMW") }

    static func std(_ key: String, _ name: String, _ short: String, _ unit: String, _ min: Double, _ max: Double,
                    decimals: Int = 0, warnAbove: Double? = nil, warnBelow: Double? = nil,
                    pid: Int, minBytes: Int = 1, slow: Bool = false, displayStep: Double = 0,
                    decode: @escaping ([Int]) -> Double?) -> PidDef {
        PidDef(key: key, name: name, shortName: short, unit: unit, min: min, max: max, decimals: decimals,
               warnAbove: warnAbove, warnBelow: warnBelow, kind: .mode01, pid: pid, minBytes: minBytes,
               displayStep: displayStep, slow: slow, decode: decode)
    }

    /// OBD Mode 06 の失火モニター。MID A1 = 全体、A2〜AD = 気筒 1〜12
    static func misfire(_ key: String, _ name: String, _ short: String, _ mid: Int) -> PidDef {
        PidDef(key: key, name: name, shortName: short, unit: "回", min: 0, max: 50, kind: .request,
               minBytes: 8, slow: true, decode: { decodeMisfire($0) },
               request: PidRequest(mode: 0x06, pid: [mid]))
    }

    /// TID 0C = 今回の運転サイクルの失火回数、0B = 直近 10 サイクルの平均
    static func decodeMisfire(_ d: [Int]) -> Double? {
        var ewma: Double? = nil
        var i = 0
        while i + 8 <= d.count {
            let value = Double(d[i + 2] * 256 + d[i + 3])
            if d[i] == 0x0C { return value }
            if d[i] == 0x0B { ewma = value }
            i += 8
            // 次の件の前に付いた MID (A1〜AD) を飛ばす
            if i < d.count && (0xA1...0xAD).contains(d[i]) && d.count - i >= 9 { i += 1 }
        }
        return ewma
    }

    private static func standard() -> [PidDef] {
        var list: [PidDef] = [
            std("RPM", "エンジン回転数", "回転数", "rpm", 0, 8000, warnAbove: 7000, pid: 0x0C, minBytes: 2, displayStep: 10,
                decode: { ab($0).map { $0 / 4.0 } }),
            std("SPEED", "車速", "車速", "km/h", 0, 260, pid: 0x0D, decode: { a($0) }),
            std("COOLANT", "冷却水温", "水温", "°C", 40, 130, warnAbove: 110, pid: 0x05, slow: true, decode: { a($0).map { $0 - 40 } }),
            std("IAT", "吸気温度", "吸気温", "°C", -20, 80, warnAbove: 60, pid: 0x0F, slow: true, decode: { a($0).map { $0 - 40 } }),
            std("OIL_TEMP", "油温", "油温", "°C", 40, 150, warnAbove: 130, pid: 0x5C, slow: true, decode: { a($0).map { $0 - 40 } }),
            std("LOAD", "エンジン負荷", "負荷", "%", 0, 100, pid: 0x04, decode: { a($0).map { $0 * 100 / 255 } }),
            std("THROTTLE", "スロットル開度", "スロットル", "%", 0, 100, pid: 0x11, decode: { a($0).map { $0 * 100 / 255 } }),
            std("PEDAL", "アクセル開度", "アクセル", "%", 0, 100, pid: 0x49, decode: { a($0).map { $0 * 100 / 255 } }),
            std("MAP", "吸気管圧力", "MAP", "kPa", 0, 255, pid: 0x0B, decode: { a($0) }),
            std("BARO", "大気圧", "大気圧", "kPa", 70, 110, pid: 0x33, slow: true, decode: { a($0) }),
            std("MAF", "吸入空気量", "MAF", "g/s", 0, 250, decimals: 1, pid: 0x10, minBytes: 2, decode: { ab($0).map { $0 / 100 } }),
            std("TIMING", "点火時期", "点火時期", "°", -20, 60, decimals: 1, pid: 0x0E, decode: { a($0).map { $0 / 2 - 64 } }),
            std("STFT1", "短期燃調 B1", "STFT1", "%", -25, 25, decimals: 1, pid: 0x06, decode: { a($0).map { ($0 - 128) * 100 / 128 } }),
            std("LTFT1", "長期燃調 B1", "LTFT1", "%", -25, 25, decimals: 1, pid: 0x07, slow: true, decode: { a($0).map { ($0 - 128) * 100 / 128 } }),
            std("STFT2", "短期燃調 B2", "STFT2", "%", -25, 25, decimals: 1, pid: 0x08, decode: { a($0).map { ($0 - 128) * 100 / 128 } }),
            std("LTFT2", "長期燃調 B2", "LTFT2", "%", -25, 25, decimals: 1, pid: 0x09, slow: true, decode: { a($0).map { ($0 - 128) * 100 / 128 } }),
            std("FUEL_LEVEL", "燃料残量", "燃料", "%", 0, 100, warnBelow: 12, pid: 0x2F, slow: true, decode: { a($0).map { $0 * 100 / 255 } }),
            std("CAT_TEMP", "触媒温度 B1S1", "触媒温", "°C", 0, 1000, warnAbove: 900, pid: 0x3C, minBytes: 2, slow: true,
                decode: { ab($0).map { $0 / 10 - 40 } }),
            std("AMBIENT", "外気温", "外気温", "°C", -20, 50, pid: 0x46, slow: true, decode: { a($0).map { $0 - 40 } }),
            std("ECU_VOLT", "ECU 電圧", "ECU電圧", "V", 10, 16, decimals: 1, warnBelow: 12, pid: 0x42, minBytes: 2, slow: true,
                decode: { ab($0).map { $0 / 1000 } }),
            std("RUNTIME", "始動後経過時間", "経過時間", "s", 0, 3600, pid: 0x1F, minBytes: 2, slow: true, decode: { ab($0) }),
            misfire("MISFIRE_TOTAL", "失火カウンタ 今回の運転 合計", "失火計", 0xA1),
        ]
        for c in 1...6 {
            list.append(misfire("MISFIRE_\(c)", "失火カウンタ 今回の運転 #\(c)", "失火#\(c)", 0xA1 + c))
        }
        list.append(PidDef(key: "BATTERY", name: "バッテリー電圧 (アダプター)", shortName: "バッテリー", unit: "V", min: 10, max: 16,
                           decimals: 1, warnBelow: 12, kind: .adapterVoltage, slow: true))
        list.append(PidDef(key: "BOOST", name: "ブースト圧 (MAP−大気圧)", shortName: "ブースト", unit: "bar", min: -1, max: 1.5,
                           decimals: 2, kind: .derived, deps: ["MAP", "BARO"],
                           derive: { v in
                               guard let m = v["MAP"] else { return nil }
                               let b = v["BARO"] ?? 101.3
                               return (m - b) / 100
                           }))
        // ガソリン: 空燃比 14.7、密度 745 g/L
        list.append(PidDef(key: "FUEL_RATE", name: "燃料消費量 (MAF 推定)", shortName: "燃費量", unit: "L/h", min: 0, max: 40,
                           decimals: 1, kind: .derived, deps: ["MAF"],
                           derive: { v in v["MAF"].map { $0 * 3600 / 14.7 / 745 } }))
        list.append(PidDef(key: "ECONOMY", name: "瞬間燃費 (MAF 推定)", shortName: "瞬間燃費", unit: "km/L", min: 0, max: 30,
                           decimals: 1, kind: .derived, deps: ["MAF", "SPEED"],
                           derive: { v in
                               guard let maf = v["MAF"], let spd = v["SPEED"], maf >= 0.1 else { return nil }
                               return Swift.min(spd / (maf * 3600 / 14.7 / 745), 99.9)
                           }))
        return list
    }

    /// カスタム PID の定義を作る。式・モード・PID・ヘッダーが不正なら例外
    static func custom(key: String, name: String, shortName: String, unit: String,
                       mode: String, pid: String, header: String, canExtAddress: String,
                       formula: String, min: Double, max: Double, decimals: Int,
                       warnAbove: Double?, warnBelow: Double?, slow: Bool) throws -> PidDef {
        let expr = try Expression.compile(formula)
        let req = try PidRequest.parse(mode: mode, pid: pid, header: header, cea: canExtAddress)
        if !(max > min) { throw OBDError("最大値は最小値より大きくしてください") }
        let n = name.trimmingCharacters(in: .whitespaces)
        let s = shortName.trimmingCharacters(in: .whitespaces)
        return PidDef(key: key, name: n.isEmpty ? "カスタム PID" : name,
                      shortName: s.isEmpty ? String(name.prefix(6)) : shortName,
                      unit: unit, min: min, max: max, decimals: Swift.min(Swift.max(decimals, 0), 3),
                      warnAbove: warnAbove, warnBelow: warnBelow, kind: .custom,
                      pid: (req.mode == 0x01 && req.pid.count == 1) ? req.pid[0] : -1,
                      minBytes: expr.requiredBytes, slow: slow,
                      decode: { try? expr.evaluate($0) }, request: req)
    }
}
