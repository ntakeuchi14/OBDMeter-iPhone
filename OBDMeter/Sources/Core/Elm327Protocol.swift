import Foundation

/// ELM327 互換アダプター (OBDLink CX/MX+ などの BLE、Wi-Fi の ELM327) 用の実装。
/// テキストの AT コマンドと OBD リクエストを送り、プロンプト '>' までを 1 応答として読む。
final class Elm327Protocol: ObdProtocol {
    struct Options {
        /// ATSP の値。"0" = 自動判別。E90 なら D-CAN 車は "6" (CAN 11bit 500k)
        var protocolCode: String = "0"
        /// Mode 01 要求の末尾に応答数 "1" を付けて、1 応答受信で即座に返させる
        var singleResponseHint: Bool = true
        var commandTimeoutMs: Int = 2000
        /// 最初の 0100 はプロトコル自動判別で時間がかかる
        var searchTimeoutMs: Int = 15000
    }

    private let transport: Transport
    private let options: Options
    private let logger: CommLogger
    private var hintSupported: Bool

    init(transport: Transport, options: Options, logger: CommLogger) {
        self.transport = transport
        self.options = options
        self.logger = logger
        self.hintSupported = options.singleResponseHint
        self.protocolNumber = options.protocolCode
    }

    private(set) var lastFailure: String?
    private(set) var lastResponded: Bool = false

    func initAdapter() throws -> String {
        transport.purge()
        // 途中状態をリセットするため CR を一度送ってプロンプトを待つ
        _ = sendRaw("", 1000)
        let probe = command("ATI", 2500)
        if lastTimedOut && !probe.contains(where: { $0.contains(where: { $0.isLetter }) }) {
            // もう一度だけ試す (BLE の接続直後は最初の応答を取りこぼすことがある)
            _ = sendRaw("", 1000)
            _ = command("ATI", 2500)
            if lastTimedOut { throw OBDError("アダプターが応答しません。アダプターの電源と接続を確認してください") }
        }
        let ws = command("ATWS", 5000) // ウォームスタート
        if ws.isEmpty && lastTimedOut {
            throw OBDError("アダプターが応答しません")
        }
        logger.log(.INFO, "Adapter: " + ws.joined(separator: " ").trimmingCharacters(in: .whitespaces))
        for cmd in ["ATE0", "ATL0", "ATS0", "ATH0", "ATAT1", "ATSP" + options.protocolCode] {
            let r = command(cmd)
            if !r.contains(where: { $0.contains("OK") }) {
                logger.log(.ERROR, "\(cmd) に OK が返りません: \(r)")
            }
        }
        currentHeader = ""
        currentCea = ""
        currentFcHeader = ""
        setupDone.removeAll()
        return command("ATI").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "ELM327"
    }

    func connectVehicle() throws -> String? {
        if !currentHeader.isEmpty || !currentCea.isEmpty { applyAddressing("", "") }
        let first = command("0100", options.searchTimeoutMs)
        let ok = Elm327Protocol.parseMode01(first, 0x00) != nil
        // イグニッション OFF でも ECU は起きていて否定応答 (7F 01 22) を返す。これも「接続できた」とみなす
        let refused = Elm327Protocol.negativeResponse(first, 0x01)
        if !ok && refused == nil {
            lastFailure = Elm327Protocol.checkError(first) ?? (first.isEmpty ? "応答なし" : first.joined(separator: "|"))
            lastResponded = false
            return nil
        }
        lastFailure = refused
        lastResponded = refused != nil
        let dp = command("ATDPN").last?.trimmingCharacters(in: .whitespaces) ?? "?"
        protocolNumber = dp.hasPrefix("A") ? String(dp.dropFirst()) : dp
        let desc = command("ATDP").last?.trimmingCharacters(in: .whitespaces) ?? "?"
        return "\(desc) (ATDPN=\(dp))" + (ok ? "" : " / ECU 応答あり (イグニッション OFF)")
    }

    /// ATDPN の結果 ("6" など)
    private var protocolNumber: String

    private var currentHeader = ""
    private var currentCea = ""
    private var currentFcHeader = ""

    private func defaultHeader() -> String {
        switch protocolNumber {
        case "6", "8": return "7DF"
        case "7", "9": return "18DB33F1"
        case "3": return "686AF1"
        case "4", "5": return "C133F1"
        default: return "7DF"
        }
    }

    private func applyAddressing(_ header: String, _ cea: String) {
        if header != currentHeader {
            _ = command("ATSH" + (header.isEmpty ? defaultHeader() : header))
            currentHeader = header
        }
        if cea != currentCea || (!cea.isEmpty && header != currentFcHeader) {
            if cea.isEmpty {
                _ = command("ATCEA")
                _ = command("ATCRA")
                _ = command("ATFCSM0")
                _ = command("ATH0")
                currentFcHeader = ""
            } else {
                _ = command("ATCEA" + cea)
                // BMW 方式 (6F1 + 拡張アドレス): ECU (0x6xx) からの応答だけを受け、拡張アドレス付きのフロー制御を送る
                if let ecu = Int(cea, radix: 16) { _ = command(String(format: "ATCRA%03X", 0x600 + ecu)) }
                let fcHeader = header.isEmpty ? defaultHeader() : header
                _ = command("ATFCSH" + fcHeader)
                _ = command("ATFCSD" + cea + "300000")
                _ = command("ATFCSM1")
                _ = command("ATH1")
                currentFcHeader = header
            }
            currentCea = cea
        }
    }

    func query(_ request: PidRequest) -> [Int]? {
        if request.isPlainMode01 && currentHeader.isEmpty && currentCea.isEmpty { return readPid(request.pid[0]) }
        applyAddressing(request.header, request.canExtAddress)
        let addr = request.header + "/" + request.canExtAddress + "/" + Hex.of(request.pid)
        let key = setupKey(request)
        if !request.setup.isEmpty && setupDone[addr] != key {
            setupDone.removeValue(forKey: addr)
            if !runSetup(request.setup) { return nil }
            setupDone[addr] = key
        }
        let cmd = String(format: "%02X", request.mode) + Hex.compact(request.pid)
        let lines = command(cmd, options.commandTimeoutMs)
        if !currentCea.isEmpty {
            let msg = ValueSearch.assemble(lines)
            let echo = [request.mode + 0x40] + request.pid
            if let msg = msg, msg.count >= echo.count, echo.indices.allSatisfy({ msg[$0] == echo[$0] }) {
                return ok(Array(msg[echo.count...]))
            }
            if !request.setup.isEmpty { setupDone.removeValue(forKey: addr) }
            if let msg = msg, !msg.isEmpty, msg[0] == 0x7F {
                lastResponded = true
                lastFailure = "否定応答 \(Hex.of(msg)) (NRC=" + String(format: "%02X", msg[safe: 2] ?? 0) + ")"
                return nil
            }
            return fail(lines, request.mode)
        }
        if let data = Elm327Protocol.parseResponseAll(lines, request.mode, request.pid).first {
            return ok(data)
        }
        if !request.setup.isEmpty { setupDone.removeValue(forKey: addr) }
        return fail(lines, request.mode)
    }

    /// 宛先ごとに、いま ECU に送ってある準備の要求
    private var setupDone: [String: String] = [:]

    private func setupKey(_ r: PidRequest) -> String {
        r.header + "/" + r.canExtAddress + "/" + r.setup.map { Hex.of($0) }.joined(separator: ";")
    }

    private func runSetup(_ setup: [[Int]]) -> Bool {
        for (i, p) in setup.enumerated() {
            let resp = sendPayload(p)
            let positive = resp != nil && !(resp!.isEmpty) && resp![0] == p[0] + 0x40
            if !positive && i == setup.count - 1 {
                lastResponded = resp != nil
                let r = resp.map { Hex.of($0) } ?? "応答なし"
                lastFailure = "準備の要求 \(Hex.of(p)) が通りませんでした: \(r)"
                logger.log(.ERROR, lastFailure ?? "")
                return false
            }
        }
        return true
    }

    private func hex(_ b: [Int]) -> String { Hex.compact(b) }

    /// サービスデータを送り、応答のサービスデータを返す。1 フレームに収まらなければ手で分割して送る
    private func sendPayload(_ p: [Int]) -> [Int]? {
        let ea = Int(currentCea, radix: 16)
        let maxSingle = ea != nil ? 6 : 7
        if p.count <= maxSingle {
            let lines = command(hex(p), options.commandTimeoutMs)
            if ea != nil { return ValueSearch.assemble(lines) }
            let l = lines.map { $0.replacingOccurrences(of: " ", with: "") }
                .first(where: { line in !line.isEmpty && line.allSatisfy { Hex.isUpperHexChar($0) } })
            return l.map { Hex.parse($0) }
        }
        return sendSegmented(p, ea)
    }

    /// 1 フレームに収まらない要求を、ISO-TP の先頭フレーム・続きのフレームを手で組み立てて送る
    private func sendSegmented(_ p: [Int], _ ea: Int?) -> [Int]? {
        let pre: [Int] = ea.map { [$0] } ?? []
        _ = command("ATCAF0")
        if ea != nil { _ = command("ATCEA") } else { _ = command("ATH1") }
        defer {
            _ = command("ATCAF1")
            if ea != nil { _ = command("ATCEA" + currentCea) } else { _ = command("ATH0") }
        }
        let ffData = 8 - pre.count - 2
        let cfData = 8 - pre.count - 1
        var lines = command(hex(pre + [0x10 | ((p.count >> 8) & 0x0F), p.count & 0xFF] + Array(p.prefix(ffData))))
        var idx = ffData
        var sn = 1
        while idx < p.count {
            let part = Array(p[idx..<min(p.count, idx + cfData)])
            let frame = pre + [0x20 | (sn & 0x0F)] + part
            lines = command(hex(frame + Array(repeating: 0, count: max(0, 8 - frame.count))))
            idx += cfData
            sn += 1
        }
        if ea != nil { return ValueSearch.assemble(lines) }
        guard let l = lines.map({ $0.replacingOccurrences(of: " ", with: "") }).first(where: { $0.count >= 5 }) else { return nil }
        let b = Hex.parse(String(l.dropFirst(3)))
        if b.isEmpty { return nil }
        let end = min(b.count, 1 + (b[0] & 0x0F))
        return end > 1 ? Array(b[1..<end]) : []
    }

    func readPid(_ pid: Int) -> [Int]? {
        if !currentHeader.isEmpty || !currentCea.isEmpty { applyAddressing("", "") }
        let base = String(format: "01%02X", pid)
        if hintSupported {
            let lines = command(base + " 1")
            if let data = Elm327Protocol.parseMode01(lines, pid) { return ok(data) }
            if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "?" }) {
                logger.log(.INFO, "応答数ヒントに非対応のため無効化")
                hintSupported = false
            } else {
                return fail(lines)
            }
        }
        let lines = command(base)
        if let data = Elm327Protocol.parseMode01(lines, pid) { return ok(data) }
        return fail(lines)
    }

    private func ok(_ data: [Int]) -> [Int] { lastFailure = nil; lastResponded = false; return data }

    private func fail(_ lines: [String], _ mode: Int = 0x01) -> [Int]? {
        let refused = Elm327Protocol.negativeResponse(lines, mode)
        lastResponded = refused != nil
        lastFailure = refused ?? Elm327Protocol.checkError(lines) ?? (lines.isEmpty ? "応答なし" : lines.joined(separator: "|"))
        return nil
    }

    /// 対応 PID 一覧は複数 ECU が返すので、応答数ヒントを付けずに全 ECU 分を受け取り合算する
    func readSupportedPids() -> Set<Int> {
        var result = Set<Int>()
        var base = 0x00
        while base <= 0xA0 {
            let lines = command(String(format: "01%02X", base), 4000)
            let bitmaps = Elm327Protocol.parseMode01All(lines, base).filter { $0.count >= 4 }
            if bitmaps.isEmpty { break }
            logger.log(.INFO, String(format: "PID %02X: %d 台の ECU が応答", base, bitmaps.count))
            for data in bitmaps { result.formUnion(decodeBitmap(base, data)) }
            if !result.contains(base + 0x20) { break }
            base += 0x20
        }
        return result
    }

    func readAdapterVoltage() -> Double? { Elm327Protocol.parseVoltage(command("ATRV")) }

    func close() { transport.close() }

    // ---------------------------------------------------------------------

    /// コマンドを送り、'>' までの応答を行単位で返す (空行・エコー行は除去)
    func command(_ cmd: String, _ timeoutMs: Int? = nil) -> [String] {
        let raw = sendRaw(cmd, timeoutMs ?? options.commandTimeoutMs)
        return raw.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare(cmd) != .orderedSame }
    }

    private var needsResync = false
    private var lastTimedOut = false

    private func sendRaw(_ cmd: String, _ timeoutMs: Int) -> String {
        lastTimedOut = false
        if needsResync {
            transport.purge()
            needsResync = false
        }
        logger.log(.TX, cmd.isEmpty ? "<CR>" : cmd)
        do {
            try transport.write(Array((cmd + "\r").utf8))
        } catch {
            logger.log(.ERROR, "送信できません: \(error.localizedDescription)")
            lastTimedOut = true
            return ""
        }
        var sb = ""
        let deadline = nowMs() + Int64(timeoutMs)
        while true {
            let remaining = Int(deadline - nowMs())
            if remaining <= 0 {
                logger.log(.ERROR, "タイムアウト: \(cmd) (受信: \(sb.replacingOccurrences(of: "\r", with: "|")))")
                needsResync = true
                lastTimedOut = true
                break
            }
            let bytes = transport.read(timeoutMs: min(remaining, 100))
            if bytes.isEmpty { continue }
            for b in bytes {
                if b == UInt8(ascii: ">") {
                    logger.log(.RX, sb.replacingOccurrences(of: "\r", with: "|").trimmingCharacters(in: CharacterSet(charactersIn: "|")))
                    return sb
                }
                if b != 0 { sb.append(Character(UnicodeScalar(b))) }
            }
        }
        return sb
    }

    // MARK: - 応答の解析

    static let errors = [
        "NO DATA", "UNABLE TO CONNECT", "CAN ERROR", "BUS ERROR", "BUS INIT: ...ERROR",
        "BUS INIT: ERROR", "FB ERROR", "DATA ERROR", "STOPPED", "ERR", "LV RESET", "ACT ALERT",
    ]

    static func checkError(_ lines: [String]) -> String? {
        lines.first { l in errors.contains { l.uppercased().contains($0) } }
    }

    /// ATRV の応答 ("14.1V") を読む。5〜20V 以外は無効扱い
    static func parseVoltage(_ lines: [String]) -> Double? {
        for line in lines {
            let upper = line.uppercased()
            guard let vIdx = upper.firstIndex(of: "V") else { continue }
            let numPart = upper[..<vIdx].trimmingCharacters(in: .whitespaces)
            if let v = Double(numPart), v >= 5.0, v <= 20.0 { return v }
        }
        return nil
    }

    static func parseMode01(_ lines: [String], _ pid: Int) -> [Int]? {
        parseMode01All(lines, pid).first
    }

    private static let prefixOffsets = [0, 3, 5, 8, 10]

    private static func hasPrefix(_ s: [Character], _ prefix: [Character], at offset: Int) -> Bool {
        if offset + prefix.count > s.count { return false }
        for i in 0..<prefix.count where s[offset + i] != prefix[i] { return false }
        return true
    }

    /// "7F 22 31" のような否定応答を説明付きの文字列にする
    static func negativeResponse(_ lines: [String], _ mode: Int) -> String? {
        let pattern = Array(String(format: "7F%02X", mode))
        for line in lines {
            let c = Array(line.replacingOccurrences(of: " ", with: "").uppercased())
            for idx in prefixOffsets where hasPrefix(c, pattern, at: idx) && c.count >= idx + 6 {
                let nrc = Int(String(c[(idx + 4)..<(idx + 6)]), radix: 16) ?? 0
                let reason: String
                switch nrc {
                case 0x11: reason = "サービス非対応"
                case 0x12: reason = "サブ機能非対応"
                case 0x13: reason = "長さ・形式が不正"
                case 0x22: reason = "条件が整っていない"
                case 0x31: reason = "この PID / DID は範囲外 (非対応)"
                case 0x33: reason = "セキュリティ拒否"
                case 0x7F: reason = "このセッションでは非対応"
                default: reason = String(format: "NRC %02X", nrc)
                }
                return String(format: "否定応答 7F %02X %02X: ", mode, nrc) + reason
            }
        }
        return nil
    }

    private static func frameIndex(_ line: String) -> String.Index? {
        // "0:" 〜 "F:" で始まる行なら、その後ろの位置
        let chars = Array(line)
        guard chars.count >= 2, Hex.isUpperHexChar(chars[0]), chars[1] == ":" else { return nil }
        return line.index(line.startIndex, offsetBy: 2)
    }

    /// 任意モードの応答を解析し、[mode]+0x40 と [pid] のエコーの後ろのデータ部を返す (ECU ごとに 1 件)。
    /// ELM327 が ISO-TP の複数フレームを組み立てて出す形式 ("00A" / "0:62..." / "1:02...") にも対応する
    static func parseResponseAll(_ lines: [String], _ mode: Int, _ pid: [Int]) -> [[Int]] {
        let prefix = Array(String(format: "%02X", mode + 0x40) + Hex.compact(pid))
        let compact = lines.map { $0.replacingOccurrences(of: " ", with: "").uppercased() }
        var messages: [String] = []
        if compact.contains(where: { frameIndex($0) != nil }) {
            var total = -1
            var sb = ""
            for line in compact {
                if let i = frameIndex(line) {
                    sb += line[i...]
                } else if line.count == 3 && line.allSatisfy({ Hex.isUpperHexChar($0) }) {
                    if !sb.isEmpty { messages.append(trimTo(sb, total)); sb = "" }
                    total = Int(line, radix: 16) ?? -1
                }
            }
            if !sb.isEmpty { messages.append(trimTo(sb, total)) }
        } else {
            messages += compact.filter { l in !l.isEmpty && l.allSatisfy { Hex.isUpperHexChar($0) } }
        }
        var result: [[Int]] = []
        for msg in messages {
            let chars = Array(msg)
            guard let idx = prefixOffsets.first(where: { hasPrefix(chars, prefix, at: $0) }) else { continue }
            let bytes = Hex.parse(String(chars[idx...]))
            let skip = 1 + pid.count
            if bytes.count < skip { continue }
            result.append(Array(bytes[skip...]))
        }
        return result
    }

    private static func trimTo(_ hex: String, _ bytes: Int) -> String {
        bytes > 0 && hex.count > bytes * 2 ? String(hex.prefix(bytes * 2)) : hex
    }

    /// 全 ECU 分の Mode 01 の応答を返す。ヘッダー表示が有効なままの場合にも対応する
    static func parseMode01All(_ lines: [String], _ pid: Int) -> [[Int]] {
        let prefix = Array(String(format: "41%02X", pid))
        var result: [[Int]] = []
        for line in lines {
            let compact = Array(line.replacingOccurrences(of: " ", with: "").uppercased())
            if compact.contains(where: { !Hex.isUpperHexChar($0) }) { continue }
            guard let idx = prefixOffsets.first(where: { hasPrefix(compact, prefix, at: $0) }) else { continue }
            let bytes = Hex.parse(String(compact[idx...]))
            if bytes.count < 3 { continue }
            result.append(Array(bytes[2...]))
        }
        return result
    }
}

/// ECU の応答の組み立て (BMW 方式の拡張アドレス付きフレーム)
enum ValueSearch {
    /// ヘッダー表示 ON・拡張アドレス付きの ELM の応答行をつなげて、1 つのメッセージにする
    static func assemble(_ lines: [String]) -> [Int]? {
        var out: [Int] = []
        var total = -1
        for raw in lines {
            let hex = raw.replacingOccurrences(of: " ", with: "").uppercased()
            if hex.count < 3 + 4 || !hex.allSatisfy({ Hex.isUpperHexChar($0) }) { continue }
            let b = Hex.parse(String(hex.dropFirst(3)))  // 先頭 3 文字は CAN ID (612 など)
            if b.count < 2 { continue }
            let f = Array(b[1...])                        // 拡張アドレス (F1) を除く
            let pci = f[0]
            switch pci >> 4 {
            case 0:
                total = pci & 0x0F
                out.removeAll()
                if f.count > 1 { out += f[1...] }
            case 1:
                total = ((pci & 0x0F) << 8) | (f[safe: 1] ?? 0)
                out.removeAll()
                if f.count > 2 { out += f[2...] }
            case 2:
                if f.count > 1 { out += f[1...] }
            default:
                break
            }
        }
        if out.isEmpty { return nil }
        return (total >= 1 && total <= out.count) ? Array(out[0..<total]) : out
    }
}
