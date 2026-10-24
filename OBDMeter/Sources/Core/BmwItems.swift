import Foundation

/// BMW (MSD80/81, N54) 固有の項目。
/// - 測定値 (BMW_BLOCK): 測定値ブロック (2C F0 …) に登録して 21 F0 でまとめて読む
/// - 状態読み出し (REQUEST): 30 xx 01 / 22 xx xx
/// - 計算項目 (DERIVED): ブーストなど
enum BmwItems {
    /// BMW の DME 測定値の読み出し要求。測定値ブロック [lid] (F0〜F9) に読みたい測定値を登録してから 21 lid でまとめて読む
    static func blockRequest(_ items: [PidDef], lid: Int = 0xF0) -> PidRequest {
        var define = [0x2C, lid]
        var pos = 1
        for d in items {
            define += [0x02, pos, d.blockSize, d.blockId >> 8, d.blockId & 0xFF, 0x01]
            pos += d.blockSize
        }
        return PidRequest(mode: 0x21, pid: [lid], header: "6F1", canExtAddress: "12",
                          setup: [[0x2C, lid, 0x04], define])
    }

    static func u16(_ b: [Int]) -> Double? { b.count < 2 ? nil : Double(b[0] * 256 + b[1]) }
    static func s16(_ b: [Int]) -> Double? {
        guard b.count >= 2 else { return nil }
        let v = b[0] * 256 + b[1]
        return Double(v >= 0x8000 ? v - 0x10000 : v)
    }
    static func u8(_ b: [Int]) -> Double? { b.isEmpty ? nil : Double(b[0]) }

    static func bmw(_ key: String, _ name: String, _ short: String, _ unit: String, _ min: Double, _ max: Double,
                    _ id: Int, _ size: Int, decimals: Int = 0, warnAbove: Double? = nil, warnBelow: Double? = nil,
                    decode: @escaping ([Int]) -> Double?) -> PidDef {
        PidDef(key: key, name: name, shortName: short, unit: unit, min: min, max: max, decimals: decimals,
               warnAbove: warnAbove, warnBelow: warnBelow, kind: .bmwBlock, minBytes: size, decode: decode,
               blockId: id, blockSize: size)
    }

    /// 生涯失火数 (DME の測定値 0x4850〜0x4855 は点火順 1-5-3-6-2-4 で並ぶ)
    private static func misfireLife(_ cyl: Int) -> PidDef {
        let order = [1, 5, 3, 6, 2, 4]
        let id = 0x4850 + (order.firstIndex(of: cyl) ?? 0)
        return bmw("MISFIRE_LIFE_\(cyl)", "生涯失火数 #\(cyl) (BMW)", "生涯失火#\(cyl)", "回", 0, 100, id, 2) { u16($0) }
    }

    /// オイルセンサーのレベル (1 = 0.293 mm)
    static let oilLevelStep = 0.29296875

    private static func oilLevelNow() -> PidDef {
        PidDef(key: "OIL_LEVEL", name: "オイルレベル (BMW)", shortName: "オイル量", unit: "mm", min: 0, max: 75, decimals: 1,
               kind: .request, minBytes: 3, slow: true,
               decode: { d in d.count >= 3 ? Double(d[2]) * oilLevelStep : nil },
               request: PidRequest(mode: 0x30, pid: [0x0E, 0x01], header: "7E0"))
    }

    /// 排気フラップ (STATUS_AGK, 30 C1 01): 1 で閉、0 で開
    private static func exhaustFlap() -> PidDef {
        PidDef(key: "BMW_EXHAUST_FLAP", name: "排気フラップ 閉=1 / 開=0 (BMW)", shortName: "排気フラップ閉", unit: "",
               min: 0, max: 1, decimals: 0, kind: .request, minBytes: 1,
               decode: { d in d.isEmpty ? nil : (d[0] != 0 ? 1.0 : 0.0) },
               request: PidRequest(mode: 0x30, pid: [0xC1, 0x01], header: "7E0"))
    }

    private static func loadLines(_ name: String) -> [String] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n")
    }

    private static func shortOf(_ name: String) -> String {
        name.count <= 14 ? name : String(name.prefix(13)) + "…"
    }

    /// MSD80 の測定値一覧をすべて項目にする (キーは MSD80_xxxx)
    static func msd80Items() -> [PidDef] {
        var out: [PidDef] = []
        for line in loadLines("msd80_table") {
            let f = line.components(separatedBy: "|")
            if f.count < 9 { continue }
            guard let id = Int(f[0], radix: 16), let mul = Double(f[4]) else { continue }
            let name = f[1]
            let add = Double(f[5]) ?? 0
            let size: Int
            let raw: ([Int]) -> Double?
            switch f[3] {
            case "u8": size = 1; raw = { u8($0) }
            case "s8": size = 1; raw = { b in b.isEmpty ? nil : Double(b[0] >= 0x80 ? b[0] - 0x100 : b[0]) }
            case "u16": size = 2; raw = { u16($0) }
            case "s16": size = 2; raw = { s16($0) }
            case "u32":
                size = 4
                raw = { b in
                    guard b.count >= 4 else { return nil }
                    let v = (Int64(b[0]) << 24) | (Int64(b[1]) << 16) | (Int64(b[2]) << 8) | Int64(b[3])
                    return Double(v)
                }
            default: continue
            }
            out.append(bmw(String(format: "MSD80_%04X", id), name + String(format: " (BMW %04X)", id), shortOf(name), f[2],
                           Double(f[6]) ?? 0, Double(f[7]) ?? 100, id, size, decimals: Int(f[8]) ?? 0,
                           decode: { b in raw(b).map { $0 * mul + add } }))
        }
        return out
    }

    /// MSD80 の状態読み出しジョブの結果をすべて項目にする (キーは MSD80S_ジョブ_結果)
    static func msd80StatusItems() -> [PidDef] {
        var requests: [String: PidRequest] = [:]
        var out: [PidDef] = []
        for line in loadLines("msd80_status") {
            let f = line.components(separatedBy: "|")
            if f.count < 14 { continue }
            let req = f[1]
            let chars = Array(req)
            var bytes: [Int] = []
            var i = 0
            while i + 1 < chars.count {
                if let v = Int(String(chars[i...i + 1]), radix: 16) { bytes.append(v) }
                i += 2
            }
            if bytes.count != 3 { continue }
            let request: PidRequest
            if let r = requests[req] { request = r } else {
                request = PidRequest(mode: bytes[0], pid: [bytes[1], bytes[2]], header: "7E0")
                requests[req] = request
            }
            guard let pos = Int(f[5]), let size = Int(f[6]), let mul = Double(f[8]) else { continue }
            let signed = f[7] == "S"
            let add = Double(f[9]) ?? 0
            let name = f[2]
            out.append(PidDef(
                key: "MSD80S_\(f[0])_\(f[3])", name: "\(name) (BMW \(req))", shortName: shortOf(name), unit: f[4],
                min: Double(f[10]) ?? 0, max: Double(f[11]) ?? 100, decimals: Int(f[12]) ?? 0,
                kind: .request, minBytes: pos + size,
                decode: { d in
                    guard d.count >= pos + size else { return nil }
                    var raw: Int64 = 0
                    for k in 0..<size { raw = (raw << 8) | Int64(d[pos + k]) }
                    if signed && raw >= (Int64(1) << (8 * size - 1)) { raw -= Int64(1) << (8 * size) }
                    return Double(raw) * mul + add
                },
                request: request))
        }
        return out
    }

    /// BMW 固有の項目すべて
    static let all: [PidDef] = {
        var list: [PidDef] = [oilLevelNow(), exhaustFlap()]
        for c in 1...6 { list.append(misfireLife(c)) }
        list += [
            bmw("OIL_LEVEL_LONG", "オイルレベル 長期平均 (BMW)", "オイル量平均", "mm", 0, 75, 0x4400, 1, decimals: 1) { u8($0).map { $0 * oilLevelStep } },
            bmw("BMW_COOLANT", "水温 (BMW)", "水温", "°C", 40, 130, 0x581F, 1, warnAbove: 112) { u8($0).map { $0 * 0.75 - 48 } },
            bmw("BMW_BATTERY", "バッテリー電圧 (BMW)", "電圧", "V", 10, 16, 0x460A, 2, decimals: 1, warnBelow: 12) { u16($0).map { $0 * 0.015 } },
            bmw("BMW_RPM", "エンジン回転数 (BMW)", "回転数", "rpm", 0, 8000, 0x4807, 2, warnAbove: 7000) { u16($0) },
            bmw("BMW_IAT", "吸気温度 (BMW)", "吸気温", "°C", -20, 80, 0x4200, 1, warnAbove: 60) { u8($0).map { $0 * 0.75 - 48 } },
            bmw("BMW_IAT_CHARGE", "吸気温度 過給側 (BMW)", "吸気温(過給)", "°C", -20, 100, 0x58D5, 1, warnAbove: 70) { u8($0).map { $0 - 48 } },
            bmw("BMW_AFR1", "空燃比 バンク1 (BMW)", "AFR1", "", 10, 20, 0x5A50, 2, decimals: 1) { u16($0).map { $0 / 1024 * 14.7 } },
            bmw("BMW_AFR2", "空燃比 バンク2 (BMW)", "AFR2", "", 10, 20, 0x5A51, 2, decimals: 1) { u16($0).map { $0 / 1024 * 14.7 } },
            bmw("BMW_LAMBDA1", "ラムダ バンク1 (BMW)", "λ1", "λ", 0.7, 1.3, 0x5A50, 2, decimals: 2) { u16($0).map { $0 / 1024 } },
            bmw("BMW_LAMBDA2", "ラムダ バンク2 (BMW)", "λ2", "λ", 0.7, 1.3, 0x5A51, 2, decimals: 2) { u16($0).map { $0 / 1024 } },
            bmw("BMW_PEDAL", "アクセルペダル開度 (BMW)", "アクセル", "%", 0, 100, 0x5A29, 1) { u8($0).map { $0 * 0.390625 } },
            bmw("BMW_OIL_PRESSURE", "油圧 (BMW)", "油圧", "bar", 0, 6, 0x5A25, 2, decimals: 1) { s16($0).map { $0 / 1000 } },
        ]
        list += msd80Items()
        list += msd80StatusItems()
        // ブースト = スロットル前の圧力 (過給圧、絶対圧) − 大気圧
        list.append(PidDef(key: "BMW_BOOST_BAR", name: "ブースト (BMW, bar)", shortName: "ブースト", unit: "bar", min: -1, max: 1.5,
                           decimals: 2, kind: .derived, deps: ["MSD80_5A2C", "MSD80_4201"],
                           derive: { v in boostHpa(v).map { $0 / 1000 } }))
        list.append(PidDef(key: "BMW_BOOST_PSI", name: "ブースト (BMW, psi)", shortName: "ブースト", unit: "psi", min: -15, max: 22,
                           decimals: 1, kind: .derived, deps: ["MSD80_5A2C", "MSD80_4201"],
                           derive: { v in boostHpa(v).map { $0 / 1000 * 14.503774 } }))
        return list
    }()

    /// ブースト (hPa)。大気圧が読めていなければ 1013 hPa とみなす
    static func boostHpa(_ v: [String: Double]) -> Double? {
        guard let p = v["MSD80_5A2C"] else { return nil }
        var baro = 1013.25
        if let b = v["MSD80_4201"], b >= 500, b <= 1200 { baro = b }
        return p - baro
    }
}
