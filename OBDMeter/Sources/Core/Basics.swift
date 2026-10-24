import Foundation

/// 現在時刻 (ミリ秒)
func nowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

/// 通信ログの出力先。TX/RX を画面に出してデバッグするために使う。
enum LogDirection: String {
    case TX, RX, INFO, ERROR
}

protocol CommLogger: AnyObject {
    func log(_ direction: LogDirection, _ text: String)
}

final class NullLogger: CommLogger {
    func log(_ direction: LogDirection, _ text: String) {}
}

/// アダプターとのバイト列通信を抽象化したもの (BLE / Wi-Fi)。
/// プロトコル層は同期 (ブロッキング) で扱うので、必ずバックグラウンドのスレッドから呼ぶ。
protocol Transport: AnyObject {
    /// 接続を開く。失敗時は例外
    func open() throws
    /// データを送信する
    func write(_ data: [UInt8]) throws
    /// 受信したバイトを返す。[timeoutMs] 以内に何も届かなければ空
    func read(timeoutMs: Int) -> [UInt8]
    /// まだつながっているか (相手が切断したら false)
    var isAlive: Bool { get }
    func close()
}

extension Transport {
    /// 受信バッファに溜まっている不要データを捨てる
    func purge() {
        var guardCount = 0
        while !read(timeoutMs: 10).isEmpty && guardCount < 50 { guardCount += 1 }
    }
}

struct OBDError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Hex {
    static func of(_ bytes: [Int]) -> String {
        bytes.map { String(format: "%02X", $0 & 0xFF) }.joined(separator: " ")
    }

    static func compact(_ bytes: [Int]) -> String {
        bytes.map { String(format: "%02X", $0 & 0xFF) }.joined()
    }

    static func isHexChar(_ c: Character) -> Bool {
        c.isASCII && (c.isNumber || ("A"..."F").contains(c) || ("a"..."f").contains(c))
    }

    static func isUpperHexChar(_ c: Character) -> Bool {
        c.isASCII && (c.isNumber || ("A"..."F").contains(c))
    }

    /// "41 0C 1A F8" や "410C1AF8" をバイト列に変換する。16進以外の文字は無視する
    static func parse(_ text: String) -> [Int] {
        let clean = Array(text.filter { isHexChar($0) })
        if clean.count % 2 != 0 { return [] }
        var out: [Int] = []
        out.reserveCapacity(clean.count / 2)
        var i = 0
        while i < clean.count {
            out.append(Int(String(clean[i...i + 1]), radix: 16) ?? 0)
            i += 2
        }
        return out
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}

extension String {
    /// 16 進文字列として整数にする
    var hexInt: Int? { Int(self, radix: 16) }

    func padRight(_ n: Int) -> String {
        count >= n ? self : self + String(repeating: " ", count: n - count)
    }
}

/// 1 回の問い合わせ内容。
/// - mode: サービス (01 = 現在値、22 = DID 読み出し など)
/// - pid: PID / DID のバイト列
/// - header: 送信ヘッダー (ATSH の値。例 "7E0")。空なら既定
/// - canExtAddress: CAN 拡張アドレス (ATCEA)。BMW の 6F1 系で使う
/// - setup: 読む前に 1 度だけ送る要求 (BMW の測定値ブロックの登録など)
struct PidRequest: Hashable, CustomStringConvertible {
    var mode: Int
    var pid: [Int]
    var header: String = ""
    var canExtAddress: String = ""
    var setup: [[Int]] = []

    var isPlainMode01: Bool { mode == 0x01 && pid.count == 1 && header.isEmpty && canExtAddress.isEmpty }

    var description: String {
        var s = String(format: "%02X ", mode) + Hex.compact(pid)
        if !header.isEmpty { s += " @" + header }
        if !canExtAddress.isEmpty { s += " CEA=" + canExtAddress }
        return s
    }

    /// "22", "1234" のような 16 進文字列から作る。不正なら例外
    static func parse(mode modeHex: String, pid pidHex: String, header: String = "", cea: String = "") throws -> PidRequest {
        guard let mode = Int(modeHex.trimmingCharacters(in: .whitespaces), radix: 16), (0x01...0x3F).contains(mode) else {
            throw OBDError("モードは 01〜3F の 16 進数で入力してください")
        }
        let p = pidHex.replacingOccurrences(of: " ", with: "")
        if p.count % 2 != 0 || p.count > 8 || p.contains(where: { !Hex.isHexChar($0) }) {
            throw OBDError("PID は 16 進数 (2〜8 桁、偶数桁) で入力してください")
        }
        let h = header.trimmingCharacters(in: .whitespaces).uppercased()
        if !h.isEmpty && (!(2...8).contains(h.count) || h.contains(where: { !Hex.isUpperHexChar($0) })) {
            throw OBDError("ヘッダーは 16 進数で入力してください (例: 7E0)")
        }
        let c = cea.trimmingCharacters(in: .whitespaces).uppercased()
        if !c.isEmpty && (c.count != 2 || c.contains(where: { !Hex.isUpperHexChar($0) })) {
            throw OBDError("拡張アドレスは 16 進 2 桁で入力してください (例: 12)")
        }
        return PidRequest(mode: mode, pid: Hex.parse(p), header: h, canExtAddress: c)
    }
}

/// OBD2 の読み出しのプロトコル共通インターフェース。すべてブロッキング呼び出し
protocol ObdProtocol: AnyObject {
    /// アダプター自体の初期化。車両が眠っていても成功する。説明文を返す
    func initAdapter() throws -> String
    /// 車両 (エンジン ECU) と通信できるか確認する。応答があれば説明文、無ければ nil
    func connectVehicle() throws -> String?
    /// Mode 01 の [pid] を問い合わせ、応答のデータ部を返す
    func readPid(_ pid: Int) -> [Int]?
    /// 直近の失敗の理由 (ログ表示用)
    var lastFailure: String? { get }
    /// 直近の失敗が「ECU は応答したが拒否した (7F xx yy)」だったか
    var lastResponded: Bool { get }
    /// 任意のモード・PID を問い合わせる (カスタム PID・BMW 項目)
    func query(_ request: PidRequest) -> [Int]?
    /// アダプター自身が測るバッテリー電圧 (ATRV)。非対応なら nil
    func readAdapterVoltage() -> Double?
    /// 対応 PID 一覧
    func readSupportedPids() -> Set<Int>
    func close()
}

/// PID 00/20/40... の 4 バイトのビットマップを PID 番号の集合に変換する
func decodeBitmap(_ base: Int, _ data: [Int]) -> Set<Int> {
    var out = Set<Int>()
    guard data.count >= 4 else { return out }
    for i in 0..<32 where (data[i / 8] >> (7 - i % 8)) & 1 == 1 {
        out.insert(base + i + 1)
    }
    return out
}

/// Mode 01 PID 00/20/40... のビットマップから対応 PID 一覧を得る (既定の実装)
func readSupportedPidsDefault(_ p: ObdProtocol) -> Set<Int> {
    var result = Set<Int>()
    var base = 0x00
    while base <= 0xA0 {
        guard let data = p.readPid(base), data.count >= 4 else { break }
        result.formUnion(decodeBitmap(base, data))
        if !result.contains(base + 0x20) { break }
        base += 0x20
    }
    return result
}
