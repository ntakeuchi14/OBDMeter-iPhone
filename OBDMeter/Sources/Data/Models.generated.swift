// このファイルは tools/gen_models.py で生成しています。直接編集しないでください。
import Foundation

enum GaugeStyle: String, Codable, CaseIterable, Identifiable {
    case ANALOG
    case BAR
    case DIGITAL
    case LAMP
    case CHART
    case TABLE
    case MONITOR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ANALOG: return "アナログ"
        case .BAR: return "バー"
        case .DIGITAL: return "デジタル"
        case .LAMP: return "ランプ"
        case .CHART: return "折れ線グラフ"
        case .TABLE: return "値テーブル"
        case .MONITOR: return "変動監視"
        }
    }
}

enum RingStyle: String, Codable, CaseIterable, Identifiable {
    case NONE
    case LINE
    case BOLD
    case METAL

    var id: String { rawValue }

    var label: String {
        switch self {
        case .NONE: return "なし"
        case .LINE: return "細線"
        case .BOLD: return "太線"
        case .METAL: return "メタル"
        }
    }
}

enum PanelStyle: String, Codable, CaseIterable, Identifiable {
    case FLAT
    case INSET
    case RAISED

    var id: String { rawValue }

    var label: String {
        switch self {
        case .FLAT: return "なし (平ら)"
        case .INSET: return "埋め込み (へこみ)"
        case .RAISED: return "浮き出し"
        }
    }
}

enum LegendPosition: String, Codable, CaseIterable, Identifiable {
    case TOP
    case BOTTOM
    case INSIDE_TOP_LEFT
    case INSIDE_TOP_RIGHT
    case INSIDE_BOTTOM_LEFT
    case INSIDE_BOTTOM_RIGHT
    case HIDDEN

    var id: String { rawValue }

    var label: String {
        switch self {
        case .TOP: return "上"
        case .BOTTOM: return "下"
        case .INSIDE_TOP_LEFT: return "グラフ内 左上"
        case .INSIDE_TOP_RIGHT: return "グラフ内 右上"
        case .INSIDE_BOTTOM_LEFT: return "グラフ内 左下"
        case .INSIDE_BOTTOM_RIGHT: return "グラフ内 右下"
        case .HIDDEN: return "出さない"
        }
    }
}

enum LegendAlign: String, Codable, CaseIterable, Identifiable {
    case START
    case CENTER
    case END

    var id: String { rawValue }

    var label: String {
        switch self {
        case .START: return "左寄せ"
        case .CENTER: return "中央"
        case .END: return "右寄せ"
        }
    }
}

enum BgPattern: String, Codable, CaseIterable, Identifiable {
    case NONE
    case GRID
    case CHECK
    case STRIPE
    case DOT
    case WOOD
    case CARBON
    case HONEYCOMB

    var id: String { rawValue }

    var label: String {
        switch self {
        case .NONE: return "なし"
        case .GRID: return "格子"
        case .CHECK: return "チェック"
        case .STRIPE: return "ストライプ"
        case .DOT: return "ドット"
        case .WOOD: return "木目"
        case .CARBON: return "カーボン"
        case .HONEYCOMB: return "ハニカム"
        }
    }
}

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case SIMULATOR
    case BLE
    case WIFI

    var id: String { rawValue }

    var label: String {
        switch self {
        case .SIMULATOR: return "シミュレーター (車なしで動作確認)"
        case .BLE: return "Bluetooth LE (OBDLink CX / MX+ など)"
        case .WIFI: return "Wi-Fi (ELM327 Wi-Fi など)"
        }
    }
}

struct GaugeDesign: Codable, Equatable {
    var label: String? = nil
    var min: Double? = nil
    var max: Double? = nil
    var useDefaultWarn: Bool = true
    var warnAbove: Double? = nil
    var warnBelow: Double? = nil
    var decimals: Int? = nil
    var color: Int64? = nil
    var startAngle: Double = -120
    var endAngle: Double = 120
    var counterClockwise: Bool = false
    var majorDivisions: Int? = nil
    var minorDivisions: Int = 0
    var showLabels: Bool = true
    var tickRadius: Double = 1
    var tickColor: Int64? = nil
    var labelColor: Int64? = nil
    var labelSize: Double = 1
    var ring: RingStyle = .NONE
    var ringColor: Int64? = nil
    var ringThickness: Double = 1
    var ringDepth: Double = 0.6
    var ringInner: Double = 0.4
    var showTrack: Bool = true
    var showValueArc: Bool = true
    var arcWidth: Double = 1
    var showRedZone: Bool = true
    var redZoneFrom: Double? = nil
    var redZoneTo: Double? = nil
    var redZoneColor: Int64? = nil
    var showNeedle: Bool = true
    var needleColor: Int64? = nil
    var needleLength: Double = 1
    var needleWidth: Double = 1
    var needleTail: Double = 0.12
    var knobColor: Int64? = nil
    var knobSize: Double = 1
    var showPeak: Bool = false
    var peakColor: Int64? = nil
    var showPeakValue: Bool = false
    var peakTextColor: Int64? = nil
    var peakTextSize: Double = 1
    var peakTextX: Double = 0
    var peakTextY: Double = 0
    var showValue: Bool = true
    var valueColor: Int64? = nil
    var valuePosition: Double = 0.42
    var valueOffsetX: Double = 0
    var valueSize: Double = 1
    var showName: Bool = true
    var showUnit: Bool = true
    var valueFont: String? = nil
    var labelFont: String? = nil
    var backgroundImage: String? = nil
    var imageScale: Double = 1
    var nameOffsetX: Double = 0
    var nameOffsetY: Double = 0
    var nameColor: Int64? = nil
    var unitOffsetX: Double = 0
    var unitOffsetY: Double = 0
    var unitColor: Int64? = nil
    var faceColor: Int64? = nil
    var faceScale: Double = 1
    var panelStyle: PanelStyle = .FLAT
    var panelDepth: Double = 0.6
    var panelGloss: Bool = false
    var needleShadow: Bool = false
    var objectShadow: Bool = false
    var shadowStrength: Double = 1
    var barAngle: Double = 0
    var barSegments: Int = 0
    var barSegmentGap: Double = 0.25
    var barArc: Bool = false
    var barTaper: Double = 0
    var barOffColor: Int64? = nil
    var barZoneColors: Bool = false
    var barMidColor: Int64? = nil
    var barMidFrom: Double? = nil
    var showTicks: Bool = true
    var arcRoundCap: Bool = false
    var trackColor: Int64? = nil
    var arcTipDot: Bool = false
    var arcTipColor: Int64? = nil
    var smoothing: Double = 0.5
    var glow: Double = 0
    var ghostDigits: Bool = false
    var ghostAlpha: Double = 0.15
    var imageOffsetX: Double = 0
    var imageOffsetY: Double = 0
    var showCard: Bool = true
    var lampCondition: String = ""
    var lampOnColor: Int64? = nil
    var lampOffColor: Int64? = nil
    var tableMaxRows: Int = 5
    var tableValueBg: Int64? = nil
    var tableValueImage: String? = nil
    var tableNameRatio: Double = 0.4
    var tableUnitRatio: Double = 0.2
    var tableUnitInline: Bool = false
    var tableNameInline: Bool = false
    var tableNameSize: Double = 1
    var tableUnitSize: Double = 1
    var tableMarginBottom: Double = 0
    var tableMarginRight: Double = 0
    var tableRowGap: Double = 0
    var tableColGap: Double = 0
    var chartSpanSec: Int = 3600
    var historyDays: Int = 1
    var historyMonths: Int = 3
    var historyHours: Int = 0
    var recordIntervalSec: Double = 60
    var recordOnChange: Bool = false
    var chartSkipGaps: Bool = true
    var monitorWindowMs: Int64 = 86400000
    var legendPosition: LegendPosition = .TOP
    var legendAlign: LegendAlign = .START
    var legendScale: Double = 1
    var legendBgAlpha: Double = 0.5
    var recordOnlyWhenShown: Bool = false
    var chartColors: [Int64?] = []

    enum CodingKeys: String, CodingKey {
        case label, min, max, useDefaultWarn, warnAbove, warnBelow, decimals, color, startAngle, endAngle, counterClockwise, majorDivisions, minorDivisions, showLabels, tickRadius, tickColor, labelColor, labelSize, ring, ringColor, ringThickness, ringDepth, ringInner, showTrack, showValueArc, arcWidth, showRedZone, redZoneFrom, redZoneTo, redZoneColor, showNeedle, needleColor, needleLength, needleWidth, needleTail, knobColor, knobSize, showPeak, peakColor, showPeakValue, peakTextColor, peakTextSize, peakTextX, peakTextY, showValue, valueColor, valuePosition, valueOffsetX, valueSize, showName, showUnit, valueFont, labelFont, backgroundImage, imageScale, nameOffsetX, nameOffsetY, nameColor, unitOffsetX, unitOffsetY, unitColor, faceColor, faceScale, panelStyle, panelDepth, panelGloss, needleShadow, objectShadow, shadowStrength, barAngle, barSegments, barSegmentGap, barArc, barTaper, barOffColor, barZoneColors, barMidColor, barMidFrom, showTicks, arcRoundCap, trackColor, arcTipDot, arcTipColor, smoothing, glow, ghostDigits, ghostAlpha, imageOffsetX, imageOffsetY, showCard, lampCondition, lampOnColor, lampOffColor, tableMaxRows, tableValueBg, tableValueImage, tableNameRatio, tableUnitRatio, tableUnitInline, tableNameInline, tableNameSize, tableUnitSize, tableMarginBottom, tableMarginRight, tableRowGap, tableColGap, chartSpanSec, historyDays, historyMonths, historyHours, recordIntervalSec, recordOnChange, chartSkipGaps, monitorWindowMs, legendPosition, legendAlign, legendScale, legendBgAlpha, recordOnlyWhenShown, chartColors
    }
}

extension GaugeDesign {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GaugeDesign()
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? d.label
        min = (try? c.decodeIfPresent(Double.self, forKey: .min)) ?? d.min
        max = (try? c.decodeIfPresent(Double.self, forKey: .max)) ?? d.max
        useDefaultWarn = (try? c.decodeIfPresent(Bool.self, forKey: .useDefaultWarn)) ?? d.useDefaultWarn
        warnAbove = (try? c.decodeIfPresent(Double.self, forKey: .warnAbove)) ?? d.warnAbove
        warnBelow = (try? c.decodeIfPresent(Double.self, forKey: .warnBelow)) ?? d.warnBelow
        decimals = (try? c.decodeIfPresent(Int.self, forKey: .decimals)) ?? d.decimals
        color = (try? c.decodeIfPresent(Int64.self, forKey: .color)) ?? d.color
        startAngle = (try? c.decodeIfPresent(Double.self, forKey: .startAngle)) ?? d.startAngle
        endAngle = (try? c.decodeIfPresent(Double.self, forKey: .endAngle)) ?? d.endAngle
        counterClockwise = (try? c.decodeIfPresent(Bool.self, forKey: .counterClockwise)) ?? d.counterClockwise
        majorDivisions = (try? c.decodeIfPresent(Int.self, forKey: .majorDivisions)) ?? d.majorDivisions
        minorDivisions = (try? c.decodeIfPresent(Int.self, forKey: .minorDivisions)) ?? d.minorDivisions
        showLabels = (try? c.decodeIfPresent(Bool.self, forKey: .showLabels)) ?? d.showLabels
        tickRadius = (try? c.decodeIfPresent(Double.self, forKey: .tickRadius)) ?? d.tickRadius
        tickColor = (try? c.decodeIfPresent(Int64.self, forKey: .tickColor)) ?? d.tickColor
        labelColor = (try? c.decodeIfPresent(Int64.self, forKey: .labelColor)) ?? d.labelColor
        labelSize = (try? c.decodeIfPresent(Double.self, forKey: .labelSize)) ?? d.labelSize
        ring = (try? c.decodeIfPresent(RingStyle.self, forKey: .ring)) ?? d.ring
        ringColor = (try? c.decodeIfPresent(Int64.self, forKey: .ringColor)) ?? d.ringColor
        ringThickness = (try? c.decodeIfPresent(Double.self, forKey: .ringThickness)) ?? d.ringThickness
        ringDepth = (try? c.decodeIfPresent(Double.self, forKey: .ringDepth)) ?? d.ringDepth
        ringInner = (try? c.decodeIfPresent(Double.self, forKey: .ringInner)) ?? d.ringInner
        showTrack = (try? c.decodeIfPresent(Bool.self, forKey: .showTrack)) ?? d.showTrack
        showValueArc = (try? c.decodeIfPresent(Bool.self, forKey: .showValueArc)) ?? d.showValueArc
        arcWidth = (try? c.decodeIfPresent(Double.self, forKey: .arcWidth)) ?? d.arcWidth
        showRedZone = (try? c.decodeIfPresent(Bool.self, forKey: .showRedZone)) ?? d.showRedZone
        redZoneFrom = (try? c.decodeIfPresent(Double.self, forKey: .redZoneFrom)) ?? d.redZoneFrom
        redZoneTo = (try? c.decodeIfPresent(Double.self, forKey: .redZoneTo)) ?? d.redZoneTo
        redZoneColor = (try? c.decodeIfPresent(Int64.self, forKey: .redZoneColor)) ?? d.redZoneColor
        showNeedle = (try? c.decodeIfPresent(Bool.self, forKey: .showNeedle)) ?? d.showNeedle
        needleColor = (try? c.decodeIfPresent(Int64.self, forKey: .needleColor)) ?? d.needleColor
        needleLength = (try? c.decodeIfPresent(Double.self, forKey: .needleLength)) ?? d.needleLength
        needleWidth = (try? c.decodeIfPresent(Double.self, forKey: .needleWidth)) ?? d.needleWidth
        needleTail = (try? c.decodeIfPresent(Double.self, forKey: .needleTail)) ?? d.needleTail
        knobColor = (try? c.decodeIfPresent(Int64.self, forKey: .knobColor)) ?? d.knobColor
        knobSize = (try? c.decodeIfPresent(Double.self, forKey: .knobSize)) ?? d.knobSize
        showPeak = (try? c.decodeIfPresent(Bool.self, forKey: .showPeak)) ?? d.showPeak
        peakColor = (try? c.decodeIfPresent(Int64.self, forKey: .peakColor)) ?? d.peakColor
        showPeakValue = (try? c.decodeIfPresent(Bool.self, forKey: .showPeakValue)) ?? d.showPeakValue
        peakTextColor = (try? c.decodeIfPresent(Int64.self, forKey: .peakTextColor)) ?? d.peakTextColor
        peakTextSize = (try? c.decodeIfPresent(Double.self, forKey: .peakTextSize)) ?? d.peakTextSize
        peakTextX = (try? c.decodeIfPresent(Double.self, forKey: .peakTextX)) ?? d.peakTextX
        peakTextY = (try? c.decodeIfPresent(Double.self, forKey: .peakTextY)) ?? d.peakTextY
        showValue = (try? c.decodeIfPresent(Bool.self, forKey: .showValue)) ?? d.showValue
        valueColor = (try? c.decodeIfPresent(Int64.self, forKey: .valueColor)) ?? d.valueColor
        valuePosition = (try? c.decodeIfPresent(Double.self, forKey: .valuePosition)) ?? d.valuePosition
        valueOffsetX = (try? c.decodeIfPresent(Double.self, forKey: .valueOffsetX)) ?? d.valueOffsetX
        valueSize = (try? c.decodeIfPresent(Double.self, forKey: .valueSize)) ?? d.valueSize
        showName = (try? c.decodeIfPresent(Bool.self, forKey: .showName)) ?? d.showName
        showUnit = (try? c.decodeIfPresent(Bool.self, forKey: .showUnit)) ?? d.showUnit
        valueFont = (try? c.decodeIfPresent(String.self, forKey: .valueFont)) ?? d.valueFont
        labelFont = (try? c.decodeIfPresent(String.self, forKey: .labelFont)) ?? d.labelFont
        backgroundImage = (try? c.decodeIfPresent(String.self, forKey: .backgroundImage)) ?? d.backgroundImage
        imageScale = (try? c.decodeIfPresent(Double.self, forKey: .imageScale)) ?? d.imageScale
        nameOffsetX = (try? c.decodeIfPresent(Double.self, forKey: .nameOffsetX)) ?? d.nameOffsetX
        nameOffsetY = (try? c.decodeIfPresent(Double.self, forKey: .nameOffsetY)) ?? d.nameOffsetY
        nameColor = (try? c.decodeIfPresent(Int64.self, forKey: .nameColor)) ?? d.nameColor
        unitOffsetX = (try? c.decodeIfPresent(Double.self, forKey: .unitOffsetX)) ?? d.unitOffsetX
        unitOffsetY = (try? c.decodeIfPresent(Double.self, forKey: .unitOffsetY)) ?? d.unitOffsetY
        unitColor = (try? c.decodeIfPresent(Int64.self, forKey: .unitColor)) ?? d.unitColor
        faceColor = (try? c.decodeIfPresent(Int64.self, forKey: .faceColor)) ?? d.faceColor
        faceScale = (try? c.decodeIfPresent(Double.self, forKey: .faceScale)) ?? d.faceScale
        panelStyle = (try? c.decodeIfPresent(PanelStyle.self, forKey: .panelStyle)) ?? d.panelStyle
        panelDepth = (try? c.decodeIfPresent(Double.self, forKey: .panelDepth)) ?? d.panelDepth
        panelGloss = (try? c.decodeIfPresent(Bool.self, forKey: .panelGloss)) ?? d.panelGloss
        needleShadow = (try? c.decodeIfPresent(Bool.self, forKey: .needleShadow)) ?? d.needleShadow
        objectShadow = (try? c.decodeIfPresent(Bool.self, forKey: .objectShadow)) ?? d.objectShadow
        shadowStrength = (try? c.decodeIfPresent(Double.self, forKey: .shadowStrength)) ?? d.shadowStrength
        barAngle = (try? c.decodeIfPresent(Double.self, forKey: .barAngle)) ?? d.barAngle
        barSegments = (try? c.decodeIfPresent(Int.self, forKey: .barSegments)) ?? d.barSegments
        barSegmentGap = (try? c.decodeIfPresent(Double.self, forKey: .barSegmentGap)) ?? d.barSegmentGap
        barArc = (try? c.decodeIfPresent(Bool.self, forKey: .barArc)) ?? d.barArc
        barTaper = (try? c.decodeIfPresent(Double.self, forKey: .barTaper)) ?? d.barTaper
        barOffColor = (try? c.decodeIfPresent(Int64.self, forKey: .barOffColor)) ?? d.barOffColor
        barZoneColors = (try? c.decodeIfPresent(Bool.self, forKey: .barZoneColors)) ?? d.barZoneColors
        barMidColor = (try? c.decodeIfPresent(Int64.self, forKey: .barMidColor)) ?? d.barMidColor
        barMidFrom = (try? c.decodeIfPresent(Double.self, forKey: .barMidFrom)) ?? d.barMidFrom
        showTicks = (try? c.decodeIfPresent(Bool.self, forKey: .showTicks)) ?? d.showTicks
        arcRoundCap = (try? c.decodeIfPresent(Bool.self, forKey: .arcRoundCap)) ?? d.arcRoundCap
        trackColor = (try? c.decodeIfPresent(Int64.self, forKey: .trackColor)) ?? d.trackColor
        arcTipDot = (try? c.decodeIfPresent(Bool.self, forKey: .arcTipDot)) ?? d.arcTipDot
        arcTipColor = (try? c.decodeIfPresent(Int64.self, forKey: .arcTipColor)) ?? d.arcTipColor
        smoothing = (try? c.decodeIfPresent(Double.self, forKey: .smoothing)) ?? d.smoothing
        glow = (try? c.decodeIfPresent(Double.self, forKey: .glow)) ?? d.glow
        ghostDigits = (try? c.decodeIfPresent(Bool.self, forKey: .ghostDigits)) ?? d.ghostDigits
        ghostAlpha = (try? c.decodeIfPresent(Double.self, forKey: .ghostAlpha)) ?? d.ghostAlpha
        imageOffsetX = (try? c.decodeIfPresent(Double.self, forKey: .imageOffsetX)) ?? d.imageOffsetX
        imageOffsetY = (try? c.decodeIfPresent(Double.self, forKey: .imageOffsetY)) ?? d.imageOffsetY
        showCard = (try? c.decodeIfPresent(Bool.self, forKey: .showCard)) ?? d.showCard
        lampCondition = (try? c.decodeIfPresent(String.self, forKey: .lampCondition)) ?? d.lampCondition
        lampOnColor = (try? c.decodeIfPresent(Int64.self, forKey: .lampOnColor)) ?? d.lampOnColor
        lampOffColor = (try? c.decodeIfPresent(Int64.self, forKey: .lampOffColor)) ?? d.lampOffColor
        tableMaxRows = (try? c.decodeIfPresent(Int.self, forKey: .tableMaxRows)) ?? d.tableMaxRows
        tableValueBg = (try? c.decodeIfPresent(Int64.self, forKey: .tableValueBg)) ?? d.tableValueBg
        tableValueImage = (try? c.decodeIfPresent(String.self, forKey: .tableValueImage)) ?? d.tableValueImage
        tableNameRatio = (try? c.decodeIfPresent(Double.self, forKey: .tableNameRatio)) ?? d.tableNameRatio
        tableUnitRatio = (try? c.decodeIfPresent(Double.self, forKey: .tableUnitRatio)) ?? d.tableUnitRatio
        tableUnitInline = (try? c.decodeIfPresent(Bool.self, forKey: .tableUnitInline)) ?? d.tableUnitInline
        tableNameInline = (try? c.decodeIfPresent(Bool.self, forKey: .tableNameInline)) ?? d.tableNameInline
        tableNameSize = (try? c.decodeIfPresent(Double.self, forKey: .tableNameSize)) ?? d.tableNameSize
        tableUnitSize = (try? c.decodeIfPresent(Double.self, forKey: .tableUnitSize)) ?? d.tableUnitSize
        tableMarginBottom = (try? c.decodeIfPresent(Double.self, forKey: .tableMarginBottom)) ?? d.tableMarginBottom
        tableMarginRight = (try? c.decodeIfPresent(Double.self, forKey: .tableMarginRight)) ?? d.tableMarginRight
        tableRowGap = (try? c.decodeIfPresent(Double.self, forKey: .tableRowGap)) ?? d.tableRowGap
        tableColGap = (try? c.decodeIfPresent(Double.self, forKey: .tableColGap)) ?? d.tableColGap
        chartSpanSec = (try? c.decodeIfPresent(Int.self, forKey: .chartSpanSec)) ?? d.chartSpanSec
        historyDays = (try? c.decodeIfPresent(Int.self, forKey: .historyDays)) ?? d.historyDays
        historyMonths = (try? c.decodeIfPresent(Int.self, forKey: .historyMonths)) ?? d.historyMonths
        historyHours = (try? c.decodeIfPresent(Int.self, forKey: .historyHours)) ?? d.historyHours
        recordIntervalSec = (try? c.decodeIfPresent(Double.self, forKey: .recordIntervalSec)) ?? d.recordIntervalSec
        recordOnChange = (try? c.decodeIfPresent(Bool.self, forKey: .recordOnChange)) ?? d.recordOnChange
        chartSkipGaps = (try? c.decodeIfPresent(Bool.self, forKey: .chartSkipGaps)) ?? d.chartSkipGaps
        monitorWindowMs = (try? c.decodeIfPresent(Int64.self, forKey: .monitorWindowMs)) ?? d.monitorWindowMs
        legendPosition = (try? c.decodeIfPresent(LegendPosition.self, forKey: .legendPosition)) ?? d.legendPosition
        legendAlign = (try? c.decodeIfPresent(LegendAlign.self, forKey: .legendAlign)) ?? d.legendAlign
        legendScale = (try? c.decodeIfPresent(Double.self, forKey: .legendScale)) ?? d.legendScale
        legendBgAlpha = (try? c.decodeIfPresent(Double.self, forKey: .legendBgAlpha)) ?? d.legendBgAlpha
        recordOnlyWhenShown = (try? c.decodeIfPresent(Bool.self, forKey: .recordOnlyWhenShown)) ?? d.recordOnlyWhenShown
        chartColors = (try? c.decodeIfPresent([Int64?].self, forKey: .chartColors)) ?? d.chartColors
    }
}

struct GaugeConfig: Codable, Equatable {
    var pidKey: String = ""
    var style: GaugeStyle = .ANALOG
    var id: Int64 = 0
    var x: Int = 0
    var y: Int = 0
    var w: Int = 0
    var h: Int = 0
    var design: GaugeDesign = GaugeDesign()
    var fallbackKey: String? = nil
    var floatGroup: Int? = nil
    var layoutGroup: Int64? = nil
    var floatShow: Bool = true
    var chartKeys: [String] = []
    var itemLabels: [String:String] = [:]
    var chartAxis: [String:Bool] = [:]

    enum CodingKeys: String, CodingKey {
        case pidKey, style, id, x, y, w, h, design, fallbackKey, floatGroup, layoutGroup, floatShow, chartKeys, itemLabels, chartAxis
    }
}

extension GaugeConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GaugeConfig()
        pidKey = (try? c.decodeIfPresent(String.self, forKey: .pidKey)) ?? d.pidKey
        style = (try? c.decodeIfPresent(GaugeStyle.self, forKey: .style)) ?? d.style
        id = (try? c.decodeIfPresent(Int64.self, forKey: .id)) ?? d.id
        x = (try? c.decodeIfPresent(Int.self, forKey: .x)) ?? d.x
        y = (try? c.decodeIfPresent(Int.self, forKey: .y)) ?? d.y
        w = (try? c.decodeIfPresent(Int.self, forKey: .w)) ?? d.w
        h = (try? c.decodeIfPresent(Int.self, forKey: .h)) ?? d.h
        design = (try? c.decodeIfPresent(GaugeDesign.self, forKey: .design)) ?? d.design
        fallbackKey = (try? c.decodeIfPresent(String.self, forKey: .fallbackKey)) ?? d.fallbackKey
        floatGroup = (try? c.decodeIfPresent(Int.self, forKey: .floatGroup)) ?? d.floatGroup
        layoutGroup = (try? c.decodeIfPresent(Int64.self, forKey: .layoutGroup)) ?? d.layoutGroup
        floatShow = (try? c.decodeIfPresent(Bool.self, forKey: .floatShow)) ?? d.floatShow
        chartKeys = (try? c.decodeIfPresent([String].self, forKey: .chartKeys)) ?? d.chartKeys
        itemLabels = (try? c.decodeIfPresent([String:String].self, forKey: .itemLabels)) ?? d.itemLabels
        chartAxis = (try? c.decodeIfPresent([String:Bool].self, forKey: .chartAxis)) ?? d.chartAxis
    }
}

struct PageBackground: Codable, Equatable {
    var color: Int64? = nil
    var pattern: BgPattern = .NONE
    var patternColor: Int64? = nil
    var patternScale: Double = 1
    var patternAlpha: Double = 0.35
    var image: String? = nil
    var imageX: Double = 0.5
    var imageY: Double = 0.5
    var imageWidth: Double = 1
    var imageHeight: Double = 1
    var keepAspect: Bool = true
    var imageAlpha: Double = 1

    enum CodingKeys: String, CodingKey {
        case color, pattern, patternColor, patternScale, patternAlpha, image, imageX, imageY, imageWidth, imageHeight, keepAspect, imageAlpha
    }
}

extension PageBackground {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PageBackground()
        color = (try? c.decodeIfPresent(Int64.self, forKey: .color)) ?? d.color
        pattern = (try? c.decodeIfPresent(BgPattern.self, forKey: .pattern)) ?? d.pattern
        patternColor = (try? c.decodeIfPresent(Int64.self, forKey: .patternColor)) ?? d.patternColor
        patternScale = (try? c.decodeIfPresent(Double.self, forKey: .patternScale)) ?? d.patternScale
        patternAlpha = (try? c.decodeIfPresent(Double.self, forKey: .patternAlpha)) ?? d.patternAlpha
        image = (try? c.decodeIfPresent(String.self, forKey: .image)) ?? d.image
        imageX = (try? c.decodeIfPresent(Double.self, forKey: .imageX)) ?? d.imageX
        imageY = (try? c.decodeIfPresent(Double.self, forKey: .imageY)) ?? d.imageY
        imageWidth = (try? c.decodeIfPresent(Double.self, forKey: .imageWidth)) ?? d.imageWidth
        imageHeight = (try? c.decodeIfPresent(Double.self, forKey: .imageHeight)) ?? d.imageHeight
        keepAspect = (try? c.decodeIfPresent(Bool.self, forKey: .keepAspect)) ?? d.keepAspect
        imageAlpha = (try? c.decodeIfPresent(Double.self, forKey: .imageAlpha)) ?? d.imageAlpha
    }
}

struct Dashboard: Codable, Equatable {
    var id: Int64 = 0
    var name: String = ""
    var columns: Int = 2
    var gauges: [GaugeConfig] = []
    var background: PageBackground = PageBackground()
    var unitScale: Int = 1

    enum CodingKeys: String, CodingKey {
        case id, name, columns, gauges, background, unitScale
    }
}

extension Dashboard {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Dashboard()
        id = (try? c.decodeIfPresent(Int64.self, forKey: .id)) ?? d.id
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? d.name
        columns = (try? c.decodeIfPresent(Int.self, forKey: .columns)) ?? d.columns
        gauges = (try? c.decodeIfPresent([GaugeConfig].self, forKey: .gauges)) ?? d.gauges
        background = (try? c.decodeIfPresent(PageBackground.self, forKey: .background)) ?? d.background
        unitScale = (try? c.decodeIfPresent(Int.self, forKey: .unitScale)) ?? d.unitScale
    }
}

struct CustomPid: Codable, Equatable {
    var id: Int64 = 0
    var name: String = ""
    var shortName: String = ""
    var unit: String = ""
    var mode: String = "22"
    var pid: String = ""
    var header: String = ""
    var canExtAddress: String = ""
    var formula: String = "A"
    var min: Double = 0
    var max: Double = 100
    var decimals: Int = 0
    var warnAbove: Double? = nil
    var warnBelow: Double? = nil
    var slow: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, shortName, unit, mode, pid, header, canExtAddress, formula, min, max, decimals, warnAbove, warnBelow, slow
    }
}

extension CustomPid {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CustomPid()
        id = (try? c.decodeIfPresent(Int64.self, forKey: .id)) ?? d.id
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? d.name
        shortName = (try? c.decodeIfPresent(String.self, forKey: .shortName)) ?? d.shortName
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? d.unit
        mode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? d.mode
        pid = (try? c.decodeIfPresent(String.self, forKey: .pid)) ?? d.pid
        header = (try? c.decodeIfPresent(String.self, forKey: .header)) ?? d.header
        canExtAddress = (try? c.decodeIfPresent(String.self, forKey: .canExtAddress)) ?? d.canExtAddress
        formula = (try? c.decodeIfPresent(String.self, forKey: .formula)) ?? d.formula
        min = (try? c.decodeIfPresent(Double.self, forKey: .min)) ?? d.min
        max = (try? c.decodeIfPresent(Double.self, forKey: .max)) ?? d.max
        decimals = (try? c.decodeIfPresent(Int.self, forKey: .decimals)) ?? d.decimals
        warnAbove = (try? c.decodeIfPresent(Double.self, forKey: .warnAbove)) ?? d.warnAbove
        warnBelow = (try? c.decodeIfPresent(Double.self, forKey: .warnBelow)) ?? d.warnBelow
        slow = (try? c.decodeIfPresent(Bool.self, forKey: .slow)) ?? d.slow
    }
}

struct FontEntry: Codable, Equatable {
    var id: String = ""
    var name: String = ""
    var file: String = ""
    var sha: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, file, sha
    }
}

extension FontEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FontEntry()
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? d.id
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? d.name
        file = (try? c.decodeIfPresent(String.self, forKey: .file)) ?? d.file
        sha = (try? c.decodeIfPresent(String.self, forKey: .sha)) ?? d.sha
    }
}

struct BackupManifest: Codable, Equatable {
    var format: String = "obdmeter-backup"
    var version: Int = 1
    var appVersion: String = ""
    var exportedAt: String = ""
    var dashboards: [Dashboard] = []
    var customPids: [CustomPid] = []
    var fonts: [FontEntry] = []
    var pollIntervalsMs: [String:Int]? = nil

    enum CodingKeys: String, CodingKey {
        case format, version, appVersion, exportedAt, dashboards, customPids, fonts, pollIntervalsMs
    }
}

extension BackupManifest {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BackupManifest()
        format = (try? c.decodeIfPresent(String.self, forKey: .format)) ?? d.format
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? d.version
        appVersion = (try? c.decodeIfPresent(String.self, forKey: .appVersion)) ?? d.appVersion
        exportedAt = (try? c.decodeIfPresent(String.self, forKey: .exportedAt)) ?? d.exportedAt
        dashboards = (try? c.decodeIfPresent([Dashboard].self, forKey: .dashboards)) ?? d.dashboards
        customPids = (try? c.decodeIfPresent([CustomPid].self, forKey: .customPids)) ?? d.customPids
        fonts = (try? c.decodeIfPresent([FontEntry].self, forKey: .fonts)) ?? d.fonts
        pollIntervalsMs = (try? c.decodeIfPresent([String:Int].self, forKey: .pollIntervalsMs)) ?? d.pollIntervalsMs
    }
}

struct AppSettings: Codable, Equatable {
    var connectionType: ConnectionType = .SIMULATOR
    var bleDeviceId: String? = nil
    var bleDeviceName: String = ""
    var wifiHost: String = "192.168.0.10"
    var wifiPort: Int = 35000
    var elmProtocol: String = "6"
    var elmSingleResponseHint: Bool = true
    var autoReconnect: Bool = true
    var autoConnect: Bool = false
    var alwaysShowToolbar: Bool = false
    var waitForVehicle: Bool = true
    var waitTimeoutMin: Int = 15
    var keepScreenOn: Bool = true
    var gridStep: Int = 4
    var pollIntervalsMs: [String:Int] = [:]
    var lastPageId: Int64? = nil

    enum CodingKeys: String, CodingKey {
        case connectionType, bleDeviceId, bleDeviceName, wifiHost, wifiPort, elmProtocol, elmSingleResponseHint, autoReconnect, autoConnect, alwaysShowToolbar, waitForVehicle, waitTimeoutMin, keepScreenOn, gridStep, pollIntervalsMs, lastPageId
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        connectionType = (try? c.decodeIfPresent(ConnectionType.self, forKey: .connectionType)) ?? d.connectionType
        bleDeviceId = (try? c.decodeIfPresent(String.self, forKey: .bleDeviceId)) ?? d.bleDeviceId
        bleDeviceName = (try? c.decodeIfPresent(String.self, forKey: .bleDeviceName)) ?? d.bleDeviceName
        wifiHost = (try? c.decodeIfPresent(String.self, forKey: .wifiHost)) ?? d.wifiHost
        wifiPort = (try? c.decodeIfPresent(Int.self, forKey: .wifiPort)) ?? d.wifiPort
        elmProtocol = (try? c.decodeIfPresent(String.self, forKey: .elmProtocol)) ?? d.elmProtocol
        elmSingleResponseHint = (try? c.decodeIfPresent(Bool.self, forKey: .elmSingleResponseHint)) ?? d.elmSingleResponseHint
        autoReconnect = (try? c.decodeIfPresent(Bool.self, forKey: .autoReconnect)) ?? d.autoReconnect
        autoConnect = (try? c.decodeIfPresent(Bool.self, forKey: .autoConnect)) ?? d.autoConnect
        alwaysShowToolbar = (try? c.decodeIfPresent(Bool.self, forKey: .alwaysShowToolbar)) ?? d.alwaysShowToolbar
        waitForVehicle = (try? c.decodeIfPresent(Bool.self, forKey: .waitForVehicle)) ?? d.waitForVehicle
        waitTimeoutMin = (try? c.decodeIfPresent(Int.self, forKey: .waitTimeoutMin)) ?? d.waitTimeoutMin
        keepScreenOn = (try? c.decodeIfPresent(Bool.self, forKey: .keepScreenOn)) ?? d.keepScreenOn
        gridStep = (try? c.decodeIfPresent(Int.self, forKey: .gridStep)) ?? d.gridStep
        pollIntervalsMs = (try? c.decodeIfPresent([String:Int].self, forKey: .pollIntervalsMs)) ?? d.pollIntervalsMs
        lastPageId = (try? c.decodeIfPresent(Int64.self, forKey: .lastPageId)) ?? d.lastPageId
    }
}

