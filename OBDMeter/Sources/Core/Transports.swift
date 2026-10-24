import Foundation
import CoreBluetooth

// MARK: - Wi-Fi (TCP)

/// Wi-Fi の ELM327 アダプター (多くは 192.168.0.10:35000) と TCP で通信する
final class TcpTransport: Transport {
    private let host: String
    private let port: Int
    private var fd: Int32 = -1

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func open() throws {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let rc = getaddrinfo(host, String(port), &hints, &res)
        guard rc == 0, let first = res else {
            throw OBDError("アダプターのアドレス \(host) が見つかりません")
        }
        defer { freeaddrinfo(res) }
        var lastError = "接続できません"
        var ai: UnsafeMutablePointer<addrinfo>? = first
        while let a = ai {
            let s = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if s >= 0 {
                var one: Int32 = 1
                setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
                let flags = fcntl(s, F_GETFL, 0)
                _ = fcntl(s, F_SETFL, flags | O_NONBLOCK)
                let c = connect(s, a.pointee.ai_addr, a.pointee.ai_addrlen)
                if c == 0 || errno == EINPROGRESS {
                    var pfd = pollfd(fd: s, events: Int16(POLLOUT), revents: 0)
                    let pr = poll(&pfd, 1, 5000)
                    if pr > 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len)
                        if err == 0 {
                            fd = s
                            return
                        }
                        lastError = "接続できません (\(String(cString: strerror(err))))"
                    } else {
                        lastError = "接続がタイムアウトしました"
                    }
                } else {
                    lastError = "接続できません (\(String(cString: strerror(errno))))"
                }
                Darwin.close(s)
            }
            ai = a.pointee.ai_next
        }
        throw OBDError("\(host):\(port) に\(lastError)。iPhone をアダプターの Wi-Fi につないでください")
    }

    var isAlive: Bool { fd >= 0 }

    func write(_ data: [UInt8]) throws {
        guard fd >= 0 else { throw OBDError("接続が切れています") }
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { p -> Int in
                send(fd, p.baseAddress!.advanced(by: sent), data.count - sent, 0)
            }
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&pfd, 1, 500)
                    continue
                }
                close()
                throw OBDError("送信できません")
            }
            sent += n
        }
    }

    func read(timeoutMs: Int) -> [UInt8] {
        guard fd >= 0 else {
            Thread.sleep(forTimeInterval: Double(min(timeoutMs, 50)) / 1000)
            return []
        }
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pr = poll(&pfd, 1, Int32(timeoutMs))
        if pr <= 0 { return [] }
        var buf = [UInt8](repeating: 0, count: 512)
        let n = buf.withUnsafeMutableBytes { p -> Int in recv(fd, p.baseAddress!, 512, 0) }
        if n == 0 { close(); return [] }   // 相手が切断した
        if n < 0 { return [] }
        return Array(buf[0..<n])
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}

// MARK: - Bluetooth LE

/// 見つかった BLE 機器 (設定画面の一覧用)
struct BleDevice: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
}

/// CoreBluetooth の中央 (セントラル) を 1 つだけ持ち、機器の検索と、接続中の転送路へのイベントの受け渡しをする
final class BLEManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEManager()

    let queue = DispatchQueue(label: "obdmeter.ble")
    private var central: CBCentralManager?
    private let cond = NSCondition()

    /// 検索で見つかった機器 (メインスレッドへ通知する)
    var onDiscover: ((BleDevice) -> Void)?
    private var scanningForUI = false
    /// 接続処理中の転送路
    weak var active: BleTransport?
    /// 接続処理中に探している機器
    private var wanted: UUID?
    private var found: CBPeripheral?

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
    }

    /// Bluetooth が使えるようになるまで待つ。使えなければ理由
    func waitPoweredOn(timeoutSec: Double = 5) -> String? {
        ensureCentral()
        let deadline = Date().addingTimeInterval(timeoutSec)
        cond.lock()
        defer { cond.unlock() }
        while true {
            let st = central?.state ?? .unknown
            switch st {
            case .poweredOn: return nil
            case .poweredOff: return "Bluetooth がオフになっています"
            case .unauthorized: return "Bluetooth の使用が許可されていません (設定アプリ → OBDMeter → Bluetooth)"
            case .unsupported: return "この端末は Bluetooth LE に対応していません"
            default: break
            }
            if !cond.wait(until: deadline) { return "Bluetooth を使えません" }
        }
    }

    // ---- 設定画面の検索 ----

    func startScan() {
        ensureCentral()
        queue.async {
            self.scanningForUI = true
            if self.central?.state == .poweredOn {
                self.central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }
    }

    func stopScan() {
        queue.async {
            self.scanningForUI = false
            if self.wanted == nil { self.central?.stopScan() }
        }
    }

    // ---- 接続 (セッションのスレッドから呼ぶ) ----

    /// 機器 [id] を探す。見つからなければ nil
    func findPeripheral(_ id: UUID, timeoutSec: Double) -> CBPeripheral? {
        var p: CBPeripheral? = nil
        queue.sync {
            p = self.central?.retrievePeripherals(withIdentifiers: [id]).first
        }
        if let p = p { return p }
        cond.lock()
        found = nil
        wanted = id
        cond.unlock()
        queue.async { self.central?.scanForPeripherals(withServices: nil, options: nil) }
        let deadline = Date().addingTimeInterval(timeoutSec)
        cond.lock()
        while found == nil {
            if !cond.wait(until: deadline) { break }
        }
        let result = found
        wanted = nil
        cond.unlock()
        queue.async { if !self.scanningForUI { self.central?.stopScan() } }
        return result
    }

    func connect(_ p: CBPeripheral) {
        queue.async { self.central?.connect(p, options: nil) }
    }

    func cancel(_ p: CBPeripheral) {
        queue.async { self.central?.cancelPeripheralConnection(p) }
    }

    // ---- CBCentralManagerDelegate ----

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        cond.lock()
        cond.broadcast()
        cond.unlock()
        if central.state == .poweredOn && scanningForUI {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        if central.state != .poweredOn { active?.markDisconnected("Bluetooth が使えなくなりました") }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if let w = wanted, peripheral.identifier == w {
            cond.lock()
            found = peripheral
            cond.broadcast()
            cond.unlock()
        }
        if scanningForUI {
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
            if name.isEmpty { return }  // 名前の無い機器 (家電・タグなど) は出さない
            let d = BleDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
            if let cb = onDiscover { DispatchQueue.main.async { cb(d) } }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        active?.didConnect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        active?.markDisconnected("接続できませんでした" + (error.map { " (\($0.localizedDescription))" } ?? ""))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if active?.peripheral?.identifier == peripheral.identifier {
            active?.markDisconnected("アダプターとの接続が切れました")
        }
    }

    // ---- CBPeripheralDelegate ----

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        active?.didDiscoverServices(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        active?.didDiscoverCharacteristics(service)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        active?.didUpdateNotification(characteristic, error: error)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let v = characteristic.value { active?.didReceive([UInt8](v), from: characteristic) }
    }
}

/// Bluetooth LE の ELM327 互換アダプター (OBDLink CX / MX+ / Vgate iCar Pro BLE など) と通信する。
/// 書き込み用と通知用の特性を自動で探す
final class BleTransport: Transport {
    private let deviceId: UUID
    private let deviceName: String
    private let mgr = BLEManager.shared
    private let cond = NSCondition()

    private(set) var peripheral: CBPeripheral?
    private var connected = false
    private var closedReason: String?
    private var pendingServices = 0
    private var servicesDone = false
    private var notifyReady = false
    private var notifyError: String?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var rx: [UInt8] = []

    init(deviceId: UUID, name: String) {
        self.deviceId = deviceId
        self.deviceName = name
    }

    var isAlive: Bool {
        cond.lock(); defer { cond.unlock() }
        return connected && closedReason == nil
    }

    private func waitFor(_ timeoutSec: Double, _ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        cond.lock()
        defer { cond.unlock() }
        while !done() {
            if closedReason != nil { return false }
            if !cond.wait(until: deadline) { return done() }
        }
        return true
    }

    func open() throws {
        if let reason = mgr.waitPoweredOn() { throw OBDError(reason) }
        mgr.active = self
        guard let p = mgr.findPeripheral(deviceId, timeoutSec: 8) else {
            throw OBDError("「\(deviceName)」が見つかりません。アダプターの電源 (車のイグニッション) を確認してください")
        }
        peripheral = p
        mgr.connect(p)
        if !waitFor(12, { self.connected }) {
            mgr.cancel(p)
            throw OBDError(closedReason ?? "「\(deviceName)」に接続できません (タイムアウト)")
        }
        mgr.queue.async { p.discoverServices(nil) }
        if !waitFor(10, { self.servicesDone }) {
            close()
            throw OBDError(closedReason ?? "アダプターのサービスを読み取れません")
        }
        chooseCharacteristics(p)
        guard let n = notifyChar, writeChar != nil else {
            close()
            throw OBDError("「\(deviceName)」は OBD アダプターとして使えません (送受信の特性が見つかりません)")
        }
        mgr.queue.async { p.setNotifyValue(true, for: n) }
        if !waitFor(5, { self.notifyReady || self.notifyError != nil }) || notifyError != nil {
            close()
            throw OBDError(notifyError ?? closedReason ?? "受信の準備ができません")
        }
    }

    /// よく使われるサービス (FFF0 / FFE0 / 18F0 など) を優先して、通知と書き込みの特性を選ぶ
    private func chooseCharacteristics(_ p: CBPeripheral) {
        let preferred = ["FFF0", "FFE0", "18F0", "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2", "BEDA2000-0000-1000-8000-00805F9B34FB"]
        let skip = Set(["1800", "1801", "180A", "180F"])
        let services = (p.services ?? []).filter { !skip.contains($0.uuid.uuidString.uppercased()) }
        let ordered = services.sorted { a, b in
            let ia = preferred.firstIndex(of: a.uuid.uuidString.uppercased()) ?? 99
            let ib = preferred.firstIndex(of: b.uuid.uuidString.uppercased()) ?? 99
            return ia < ib
        }
        for s in ordered {
            let chars = s.characteristics ?? []
            let n = chars.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
            let w = chars.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
            if let n = n, let w = w {
                notifyChar = n
                writeChar = w
                return
            }
        }
    }

    func write(_ data: [UInt8]) throws {
        guard let p = peripheral, let w = writeChar, isAlive else {
            throw OBDError(closedReason ?? "接続が切れています")
        }
        let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let maxLen = max(20, p.maximumWriteValueLength(for: type))
        var i = 0
        while i < data.count {
            let chunk = Data(data[i..<min(data.count, i + maxLen)])
            mgr.queue.async { p.writeValue(chunk, for: w, type: type) }
            i += maxLen
        }
    }

    func read(timeoutMs: Int) -> [UInt8] {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        cond.lock()
        defer { cond.unlock() }
        while rx.isEmpty {
            if closedReason != nil { return [] }
            if !cond.wait(until: deadline) { break }
        }
        let out = rx
        rx.removeAll()
        return out
    }

    func close() {
        if let p = peripheral { mgr.cancel(p) }
        cond.lock()
        if closedReason == nil { closedReason = "切断しました" }
        connected = false
        cond.broadcast()
        cond.unlock()
        if mgr.active === self { mgr.active = nil }
    }

    // ---- BLEManager から (BLE のキューで呼ばれる) ----

    func didConnect(_ p: CBPeripheral) {
        cond.lock()
        if p.identifier == deviceId { connected = true }
        cond.broadcast()
        cond.unlock()
    }

    func markDisconnected(_ reason: String) {
        cond.lock()
        if closedReason == nil { closedReason = reason }
        connected = false
        cond.broadcast()
        cond.unlock()
    }

    func didDiscoverServices(_ p: CBPeripheral) {
        let services = p.services ?? []
        cond.lock()
        pendingServices = services.count
        if services.isEmpty { servicesDone = true; cond.broadcast() }
        cond.unlock()
        for s in services { p.discoverCharacteristics(nil, for: s) }
    }

    func didDiscoverCharacteristics(_ s: CBService) {
        cond.lock()
        pendingServices -= 1
        if pendingServices <= 0 { servicesDone = true }
        cond.broadcast()
        cond.unlock()
    }

    func didUpdateNotification(_ c: CBCharacteristic, error: Error?) {
        cond.lock()
        if c.uuid == notifyChar?.uuid {
            if let e = error { notifyError = "受信の準備ができません (\(e.localizedDescription))" } else { notifyReady = true }
        }
        cond.broadcast()
        cond.unlock()
    }

    func didReceive(_ bytes: [UInt8], from c: CBCharacteristic) {
        cond.lock()
        rx += bytes
        cond.broadcast()
        cond.unlock()
    }
}
