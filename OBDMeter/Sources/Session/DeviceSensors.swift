import Foundation
import CoreMotion
import UIKit

/// 端末のセンサー (傾き・加速度・気圧・電池など) の値。表示中か記録中の項目があるときだけ動かす
final class DeviceSensors {
    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let opQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private let lock = NSLock()
    private var _values: [String: Double] = [:]
    private var active = Set<String>()
    private var timer: Timer?

    /// メインスレッドへの通知 (10 回/秒まで)
    var onValues: (([String: Double]) -> Void)?

    /// 最新の値 (どのスレッドからでも読める)
    var values: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return _values
    }

    private func set(_ key: String, _ v: Double?) {
        lock.lock()
        if active.contains(key) { _values[key] = v } else { _values.removeValue(forKey: key) }
        lock.unlock()
    }

    private static let motionKeys: Set<String> = [
        DeviceItems.PITCH, DeviceItems.ROLL, DeviceItems.AZIMUTH, DeviceItems.ACCEL, DeviceItems.ACCEL_X,
        DeviceItems.ACCEL_Y, DeviceItems.ACCEL_Z, DeviceItems.MOTION, DeviceItems.GYRO,
    ]

    /// 使う項目を変える (メインスレッドから呼ぶ)
    func setActive(_ keys: Set<String>) {
        let devKeys = keys.filter { $0.hasPrefix("DEV_") }
        if devKeys == active { return }
        lock.lock()
        active = devKeys
        _values = _values.filter { devKeys.contains($0.key) }
        lock.unlock()

        let needMotion = !devKeys.isDisjoint(with: DeviceSensors.motionKeys)
        if needMotion && !motion.isDeviceMotionActive && motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.05
            let frame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
                ? .xMagneticNorthZVertical : .xArbitraryZVertical
            motion.startDeviceMotionUpdates(using: frame, to: opQueue) { [weak self] m, _ in
                guard let self = self, let m = m else { return }
                self.handle(m)
            }
        } else if !needMotion && motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }

        let needPressure = devKeys.contains(DeviceItems.PRESSURE)
        if needPressure && CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: opQueue) { [weak self] d, _ in
                guard let d = d else { return }
                self?.set(DeviceItems.PRESSURE, d.pressure.doubleValue * 10) // kPa → hPa
            }
        } else {
            altimeter.stopRelativeAltitudeUpdates()
        }

        UIDevice.current.isBatteryMonitoringEnabled = devKeys.contains(DeviceItems.BATTERY)

        timer?.invalidate()
        timer = nil
        if !devKeys.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        } else {
            onValues?([:])
        }
    }

    private func tick() {
        let now = nowMs()
        if active.contains(DeviceItems.SINE) { set(DeviceItems.SINE, DeviceItems.testSignal(DeviceItems.SINE, now)) }
        if active.contains(DeviceItems.SAW) { set(DeviceItems.SAW, DeviceItems.testSignal(DeviceItems.SAW, now)) }
        if active.contains(DeviceItems.BATTERY) {
            let level = UIDevice.current.batteryLevel
            set(DeviceItems.BATTERY, level >= 0 ? Double(level) * 100 : nil)
        }
        onValues?(values)
    }

    private func handle(_ m: CMDeviceMotion) {
        let deg = 180.0 / Double.pi
        // 前後の傾きは画面の上側を持ち上げるとプラス、左右は右側を下げるとプラス
        let g = m.gravity
        let pitch = atan2(-g.y, sqrt(g.x * g.x + g.z * g.z)) * deg
        let roll = atan2(g.x, -g.z) * deg
        set(DeviceItems.PITCH, pitch)
        set(DeviceItems.ROLL, roll)
        var az = -m.attitude.yaw * deg
        if az < 0 { az += 360 }
        set(DeviceItems.AZIMUTH, az)
        let ax = m.userAcceleration.x + g.x
        let ay = m.userAcceleration.y + g.y
        let azz = m.userAcceleration.z + g.z
        set(DeviceItems.ACCEL, sqrt(ax * ax + ay * ay + azz * azz))
        set(DeviceItems.ACCEL_X, ax)
        set(DeviceItems.ACCEL_Y, ay)
        set(DeviceItems.ACCEL_Z, azz)
        let u = m.userAcceleration
        set(DeviceItems.MOTION, sqrt(u.x * u.x + u.y * u.y + u.z * u.z))
        let r = m.rotationRate
        set(DeviceItems.GYRO, sqrt(r.x * r.x + r.y * r.y + r.z * r.z) * deg)
    }
}
