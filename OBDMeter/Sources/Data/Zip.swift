import Foundation
import Compression

/// バックアップ用の最小限の zip の読み書き (Android 版のバックアップと互換)。
/// 書き出しは無圧縮、読み込みは無圧縮と deflate に対応する
enum Zip {
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func u16(_ d: Data, _ o: Int) -> Int {
        guard o + 2 <= d.count else { return 0 }
        let s = d.startIndex + o
        return Int(d[s]) | (Int(d[s + 1]) << 8)
    }

    private static func u32(_ d: Data, _ o: Int) -> Int {
        guard o + 4 <= d.count else { return 0 }
        let s = d.startIndex + o
        return Int(d[s]) | (Int(d[s + 1]) << 8) | (Int(d[s + 2]) << 16) | (Int(d[s + 3]) << 24)
    }

    private static func put16(_ d: inout Data, _ v: Int) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
    }

    private static func put32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
    }

    /// zip の中身 (名前 → データ) を読む。壊れていれば例外
    static func read(_ data: Data, maxEntrySize: Int = 64 * 1024 * 1024) throws -> [String: Data] {
        let d = Data(data)  // startIndex を 0 にする
        // 末尾の End of central directory を探す
        var eocd = -1
        var i = d.count - 22
        let limit = Swift.max(0, d.count - 22 - 65535)
        while i >= limit {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        if eocd < 0 { throw OBDError("zip ファイルではありません") }
        let count = u16(d, eocd + 10)
        var p = u32(d, eocd + 16)
        var out: [String: Data] = [:]
        for _ in 0..<count {
            if u32(d, p) != 0x02014b50 { throw OBDError("zip ファイルが壊れています") }
            let method = u16(d, p + 10)
            let compSize = u32(d, p + 20)
            let size = u32(d, p + 24)
            let nameLen = u16(d, p + 28)
            let extraLen = u16(d, p + 30)
            let commentLen = u16(d, p + 32)
            let localOffset = u32(d, p + 42)
            guard p + 46 + nameLen <= d.count else { throw OBDError("zip ファイルが壊れています") }
            let name = String(data: d.subdata(in: (p + 46)..<(p + 46 + nameLen)), encoding: .utf8) ?? ""
            p += 46 + nameLen + extraLen + commentLen
            if name.hasSuffix("/") { continue }
            if size > maxEntrySize { throw OBDError("ファイル内のデータが大きすぎます") }
            if u32(d, localOffset) != 0x04034b50 { continue }
            let start = localOffset + 30 + u16(d, localOffset + 26) + u16(d, localOffset + 28)
            guard start + compSize <= d.count else { continue }
            let comp = d.subdata(in: start..<(start + compSize))
            switch method {
            case 0: out[name] = comp
            case 8:
                if let inflated = inflate(comp, size) { out[name] = inflated }
            default: continue
            }
        }
        return out
    }

    private static func inflate(_ src: Data, _ size: Int) -> Data? {
        if size == 0 { return Data() }
        var dst = Data(count: size)
        let n = dst.withUnsafeMutableBytes { (dp: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (sp: UnsafeRawBufferPointer) -> Int in
                guard let dBase = dp.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let sBase = sp.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(dBase, size, sBase, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n == size ? dst : nil
    }

    /// 名前とデータの並びから無圧縮の zip を作る
    static func write(_ entries: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            put32(&out, 0x04034b50)
            put16(&out, 20); put16(&out, 0x0800); put16(&out, 0)   // 版・UTF-8 の名前・無圧縮
            put16(&out, 0); put16(&out, 0x21)                       // 時刻・日付 (1980/1/1)
            put32(&out, crc); put32(&out, UInt32(data.count)); put32(&out, UInt32(data.count))
            put16(&out, nameData.count); put16(&out, 0)
            out.append(nameData)
            out.append(data)

            put32(&central, 0x02014b50)
            put16(&central, 20); put16(&central, 20); put16(&central, 0x0800); put16(&central, 0)
            put16(&central, 0); put16(&central, 0x21)
            put32(&central, crc); put32(&central, UInt32(data.count)); put32(&central, UInt32(data.count))
            put16(&central, nameData.count); put16(&central, 0); put16(&central, 0)
            put16(&central, 0); put16(&central, 0); put32(&central, 0)
            put32(&central, offset)
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        put32(&out, 0x06054b50)
        put16(&out, 0); put16(&out, 0)
        put16(&out, entries.count); put16(&out, entries.count)
        put32(&out, UInt32(central.count)); put32(&out, cdOffset)
        put16(&out, 0)
        return out
    }
}
