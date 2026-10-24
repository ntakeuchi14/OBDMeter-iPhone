import Foundation
import UIKit
import CoreText
import CryptoKit

/// アプリの保存場所
enum AppDirs {
    static var support: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func sub(_ name: String) -> URL {
        let d = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 書き出したファイルを置く場所 (「ファイル」アプリの「このiPhone内 → OBDMeter」から見える)
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static var temp: URL { FileManager.default.temporaryDirectory }
}

/// 設定とダッシュボード構成を端末内 (JSON ファイル) に保存する
final class Repository {
    private let queue = DispatchQueue(label: "obdmeter.repo")
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private func url(_ name: String) -> URL { AppDirs.support.appendingPathComponent(name) }

    private func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? encoder.encode(value) else { return }
        let u = url(name)
        queue.async { try? data.write(to: u, options: .atomic) }
    }

    func loadSettings() -> AppSettings { load(AppSettings.self, "settings.json") ?? AppSettings() }
    func saveSettings(_ s: AppSettings) { save(s, "settings.json") }

    func loadDashboards() -> [Dashboard] {
        guard let list = load([Dashboard].self, "dashboards.json"), !list.isEmpty else { return Defaults.dashboards }
        return list.map { Layout.normalize($0) }
    }
    func saveDashboards(_ list: [Dashboard]) { save(list, "dashboards.json") }

    func loadCustomPids() -> [CustomPid] { load([CustomPid].self, "custom_pids.json") ?? [] }
    func saveCustomPids(_ list: [CustomPid]) { save(list, "custom_pids.json") }

    func loadFonts() -> [FontEntry] { load([FontEntry].self, "fonts.json") ?? [] }
    func saveFonts(_ list: [FontEntry]) { save(list, "fonts.json") }
}

/// メーターやページの背景画像の保存と読み込み。選んだ画像はアプリ内にコピーして持つ
enum GaugeImages {
    private static let cache = NSCache<NSString, UIImage>()
    private static var dir: URL { AppDirs.sub("gauge_images") }

    static func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// 画像データを取り込み、保存したファイル名を返す。読めない画像なら例外。長辺 [maxSize] に縮小する
    static func importImage(_ data: Data, maxSize: CGFloat = 1024) throws -> String {
        guard var img = UIImage(data: data) else { throw OBDError("画像を読み込めませんでした") }
        let longest = Swift.max(img.size.width * img.scale, img.size.height * img.scale)
        if longest > maxSize {
            let k = maxSize / longest
            let size = CGSize(width: (img.size.width * img.scale * k).rounded(), height: (img.size.height * img.scale * k).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            img = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        }
        guard let png = img.pngData() else { throw OBDError("画像を保存できませんでした") }
        let name = "bg_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased() + ".png"
        try png.write(to: file(name), options: .atomic)
        return name
    }

    /// バックアップから取り出した画像を保存し、新しいファイル名を返す。画像として読めなければ nil
    static func saveBytes(_ data: Data) -> String? {
        guard UIImage(data: data) != nil else { return nil }
        let name = "bg_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased() + ".png"
        do { try data.write(to: file(name), options: .atomic) } catch { return nil }
        return name
    }

    static func load(_ name: String) -> UIImage? {
        if let c = cache.object(forKey: name as NSString) { return c }
        guard let img = UIImage(contentsOfFile: file(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    /// どのメーターからも使われていない画像を削除する
    static func cleanup(_ used: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where !used.contains(f) {
            try? FileManager.default.removeItem(at: file(f))
            cache.removeObject(forKey: f as NSString)
        }
    }
}

/// 取り込んだフォント (.ttf / .otf) の保存と登録
enum GaugeFonts {
    private static var dir: URL { AppDirs.sub("fonts") }
    /// フォントの id → PostScript 名 (登録済みのもの)
    private static var registered: [String: String] = [:]
    private static let lock = NSLock()

    static func file(_ entry: FontEntry) -> URL { dir.appendingPathComponent(entry.file) }

    /// ライブラリのフォントを使えるようにして、PostScript 名を返す。読めなければ nil
    static func postScriptName(_ entry: FontEntry) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let n = registered[entry.id] { return n }
        guard let data = try? Data(contentsOf: file(entry)),
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider) else { return nil }
        var err: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(font, &err)
        guard let ps = font.postScriptName as String? else { return nil }
        registered[entry.id] = ps
        return ps
    }

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// バイト列からフォントを保存する。同じ内容のフォントが [existing] にあればそれを返す
    static func save(_ data: Data, displayName: String, existing: [FontEntry]) throws -> FontEntry {
        if data.count > 40 * 1024 * 1024 { throw OBDError("フォントファイルが大きすぎます (40MB まで)") }
        let sha = sha1(data)
        if let e = existing.first(where: { $0.sha == sha && FileManager.default.fileExists(atPath: file($0).path) }) { return e }
        guard let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil else {
            throw OBDError("フォントとして読み込めませんでした (.ttf / .otf を選んでください)")
        }
        let lower = displayName.lowercased()
        let ext = lower.hasSuffix(".otf") ? "otf" : "ttf"
        let id = "font_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
        let fileName = id + "." + ext
        try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        var base = displayName
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        return FontEntry(id: id, name: base.isEmpty ? id : base, file: fileName, sha: sha)
    }

    static func delete(_ entry: FontEntry) {
        lock.lock()
        registered.removeValue(forKey: entry.id)
        lock.unlock()
        try? FileManager.default.removeItem(at: file(entry))
    }
}

/// インポートの方法
enum ImportMode {
    /// 今のページとカスタム PID をすべて消して、ファイルの内容に置き換える
    case replace
    /// 今の内容を残したまま、ファイルのページとカスタム PID を追加する
    case merge
}

/// 読み込んだバックアップ (適用前)
struct LoadedBackup {
    var manifest: BackupManifest
    var images: [String: Data]
    var fonts: [String: Data]
    var pageCount: Int { manifest.dashboards.count }
    var gaugeCount: Int { manifest.dashboards.reduce(0) { $0 + $1.gauges.count } }
    var customPidCount: Int { manifest.customPids.count }
    var imageCount: Int { images.count }
    var fontCount: Int { manifest.fonts.filter { fonts[$0.file] != nil }.count }
}

struct MergeResult {
    var dashboards: [Dashboard]
    var customPids: [CustomPid]
    var pollIntervalsMs: [String: Int]
}

/// 設定のバックアップ (Android 版と同じ zip: manifest.json + images/ + fonts/)
enum BackupLogic {
    static func isSafeImageName(_ n: String) -> Bool {
        n.range(of: "^[A-Za-z0-9_.-]{1,80}\\.png$", options: .regularExpression) != nil
    }

    static func isSafeFontName(_ n: String) -> Bool {
        n.range(of: "^[A-Za-z0-9_-]{1,60}\\.(ttf|otf)$", options: .regularExpression) != nil
    }

    static func encode(_ m: BackupManifest) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(m)
    }

    static func decode(_ data: Data) throws -> BackupManifest {
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if (obj?["format"] as? String) != BackupManifest.FORMAT {
            throw OBDError("OBD Meter の設定ファイルではありません")
        }
        guard let m = try? JSONDecoder().decode(BackupManifest.self, from: data) else {
            throw OBDError("設定ファイルの形式が正しくありません")
        }
        if m.version > BackupManifest.VERSION {
            throw OBDError("新しいバージョンのアプリで作られたファイルです。アプリを更新してください")
        }
        return m
    }

    static func referencedImages(_ dashboards: [Dashboard]) -> Set<String> {
        Set(dashboards.flatMap { $0.imageNames() })
    }

    /// バックアップ zip を作る (画像・フォントも入れる)
    static func makeZip(_ manifest: BackupManifest) throws -> (Data, Int) {
        var entries: [(String, Data)] = [("manifest.json", try encode(manifest))]
        var images = 0
        for name in referencedImages(manifest.dashboards).sorted() where isSafeImageName(name) {
            if let d = try? Data(contentsOf: GaugeImages.file(name)) {
                entries.append(("images/" + name, d))
                images += 1
            }
        }
        for f in manifest.fonts where isSafeFontName(f.file) {
            if let d = try? Data(contentsOf: GaugeFonts.file(f)) { entries.append(("fonts/" + f.file, d)) }
        }
        return (Zip.write(entries), images)
    }

    static func readZip(_ data: Data) throws -> LoadedBackup {
        let files = try Zip.read(data)
        guard let manifestData = files["manifest.json"] else {
            throw OBDError("OBD Meter の設定ファイルではありません (manifest.json がありません)")
        }
        let m = try decode(manifestData)
        var images: [String: Data] = [:]
        var fonts: [String: Data] = [:]
        for (name, d) in files {
            if name.hasPrefix("images/") {
                let n = String(name.dropFirst("images/".count))
                if isSafeImageName(n) { images[n] = d }
            } else if name.hasPrefix("fonts/") {
                let n = String(name.dropFirst("fonts/".count))
                if isSafeFontName(n) { fonts[n] = d }
            }
        }
        return LoadedBackup(manifest: m, images: images, fonts: fonts)
    }

    /// 読み込んだ内容を今の内容に適用した結果を作る
    static func apply(current: [Dashboard], currentPids: [CustomPid], incoming: BackupManifest,
                      imageRename: [String: String], mode: ImportMode, newId: () -> Int64,
                      fontRename: [String: String], currentIntervals: [String: Int]) -> MergeResult {
        func fixImages(_ d: Dashboard) -> Dashboard {
            var x = d
            x.background.image = d.background.image.flatMap { imageRename[$0] }
            for i in x.gauges.indices {
                var g = x.gauges[i].design
                g.backgroundImage = g.backgroundImage.flatMap { imageRename[$0] }
                g.tableValueImage = g.tableValueImage.flatMap { imageRename[$0] }
                g.valueFont = g.valueFont.flatMap { fontRename[$0] }
                g.labelFont = g.labelFont.flatMap { fontRename[$0] }
                x.gauges[i].design = g
            }
            return x
        }

        if mode == .replace {
            let pages = incoming.dashboards.map { Layout.normalize(fixImages($0)) }
            return MergeResult(dashboards: pages.isEmpty ? Defaults.dashboards : pages,
                               customPids: incoming.customPids,
                               pollIntervalsMs: incoming.pollIntervalsMs ?? currentIntervals)
        }

        // ---- 追加 ----
        var pids = currentPids
        var keyRename: [String: String] = [:]
        for p in incoming.customPids {
            var a = p; a.id = 0
            if let same = pids.first(where: { var b = $0; b.id = 0; return b == a }) {
                keyRename[p.key] = same.key
            } else {
                var n = p
                n.id = newId()
                pids.append(n)
                keyRename[p.key] = n.key
            }
        }
        var existingNames = Set(current.map { $0.name })
        var added: [Dashboard] = []
        for d in incoming.dashboards {
            var name = d.name
            if existingNames.contains(name) {
                var n = 2
                while existingNames.contains("\(name) (\(n))") { n += 1 }
                name = "\(name) (\(n))"
            }
            existingNames.insert(name)
            var fixed = fixImages(d)
            for i in fixed.gauges.indices {
                var g = fixed.gauges[i]
                g.pidKey = keyRename[g.pidKey] ?? g.pidKey
                g.fallbackKey = g.fallbackKey.map { keyRename[$0] ?? $0 }
                g.chartKeys = g.chartKeys.map { keyRename[$0] ?? $0 }
                var labels: [String: String] = [:]
                for (k, v) in g.itemLabels { labels[keyRename[k] ?? k] = v }
                g.itemLabels = labels
                var axis: [String: Bool] = [:]
                for (k, v) in g.chartAxis { axis[keyRename[k] ?? k] = v }
                g.chartAxis = axis
                fixed.gauges[i] = g
            }
            fixed.id = newId()
            fixed.name = name
            added.append(Layout.normalize(fixed))
        }
        var iv: [String: Int] = [:]
        for (k, v) in incoming.pollIntervalsMs ?? [:] { iv[keyRename[k] ?? k] = v }
        for (k, v) in currentIntervals { iv[k] = v }
        return MergeResult(dashboards: current + added, customPids: pids, pollIntervalsMs: iv)
    }
}
