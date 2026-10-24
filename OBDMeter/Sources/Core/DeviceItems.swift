import Foundation

/// 端末 (iPhone) のセンサーで測る項目。車につながなくても値が出るので、メーターやグラフの反応を試すのに使う
enum DeviceItems {
    static let PITCH = "DEV_PITCH"
    static let ROLL = "DEV_ROLL"
    static let AZIMUTH = "DEV_AZIMUTH"
    static let ACCEL = "DEV_ACCEL"
    static let ACCEL_X = "DEV_ACCEL_X"
    static let ACCEL_Y = "DEV_ACCEL_Y"
    static let ACCEL_Z = "DEV_ACCEL_Z"
    static let MOTION = "DEV_MOTION"
    static let GYRO = "DEV_GYRO"
    static let LIGHT = "DEV_LIGHT"
    static let PROXIMITY = "DEV_PROXIMITY"
    static let PRESSURE = "DEV_PRESSURE"
    static let BATTERY = "DEV_BATTERY"
    static let BATTERY_TEMP = "DEV_BATTERY_TEMP"
    static let BATTERY_VOLT = "DEV_BATTERY_VOLT"
    static let SINE = "DEV_TEST_SINE"
    static let SAW = "DEV_TEST_SAW"

    private static func dev(_ key: String, _ name: String, _ short: String, _ unit: String, _ min: Double, _ max: Double,
                            decimals: Int = 0) -> PidDef {
        PidDef(key: key, name: name + " (端末)", shortName: short, unit: unit, min: min, max: max, decimals: decimals, kind: .device)
    }

    /// iPhone で測れる項目 (明るさ・近接・電池の温度と電圧は iPhone では取れないので出さない)
    static let all: [PidDef] = [
        dev(PITCH, "傾き 前後", "前後の傾き", "°", -90, 90),
        dev(ROLL, "傾き 左右", "左右の傾き", "°", -90, 90),
        dev(AZIMUTH, "方位", "方位", "°", 0, 360),
        dev(ACCEL, "加速度 (重力込み)", "加速度", "G", 0, 3, decimals: 2),
        dev(ACCEL_X, "加速度 左右", "加速度 X", "G", -2, 2, decimals: 2),
        dev(ACCEL_Y, "加速度 上下", "加速度 Y", "G", -2, 2, decimals: 2),
        dev(ACCEL_Z, "加速度 前後", "加速度 Z", "G", -2, 2, decimals: 2),
        dev(MOTION, "揺れ (重力を除いた加速度)", "揺れ", "G", 0, 2, decimals: 2),
        dev(GYRO, "回転の速さ", "回転", "°/s", 0, 720),
        dev(PRESSURE, "気圧", "気圧", "hPa", 950, 1050, decimals: 1),
        dev(BATTERY, "バッテリー残量", "電池残量", "%", 0, 100),
        dev(SINE, "テスト信号 サイン波 (10 秒周期)", "サイン波", "", 0, 100),
        dev(SAW, "テスト信号 のこぎり波 (10 秒周期)", "のこぎり波", "", 0, 100),
        // Android 版の設定を読み込んだときに「項目が見つかりません」にならないよう残す (値は出ない)
        dev(LIGHT, "明るさ (iPhone では非対応)", "明るさ", "lx", 0, 1000),
        dev(PROXIMITY, "近接センサー (iPhone では非対応)", "近接", "cm", 0, 10, decimals: 1),
        dev(BATTERY_TEMP, "バッテリー温度 (iPhone では非対応)", "電池温度", "°C", 0, 60, decimals: 1),
        dev(BATTERY_VOLT, "バッテリー電圧 (iPhone では非対応)", "電池電圧", "V", 3, 4.5, decimals: 2),
    ]

    static func isDevice(_ d: PidDef) -> Bool { d.kind == .device }

    /// テスト信号の値 (時刻 [t] ミリ秒、周期 [periodMs])
    static func testSignal(_ key: String, _ t: Int64, periodMs: Int64 = 10_000) -> Double? {
        let phase = Double(t % periodMs) / Double(periodMs)
        switch key {
        case SINE: return 50 + 50 * sin(phase * 2 * Double.pi)
        case SAW: return phase * 100
        default: return nil
        }
    }
}
