#!/usr/bin/env python3
"""保存形式 (Android 版と同じ JSON) のモデルを生成する。
足りない項目は既定値で読み、知らない項目は無視する (kotlinx.serialization の ignoreUnknownKeys と同じ)。
使い方: python3 tools/gen_models.py > OBDMeter/Sources/Data/Models.generated.swift
"""

ENUMS = {
    "GaugeStyle": [("ANALOG","アナログ"),("BAR","バー"),("DIGITAL","デジタル"),("LAMP","ランプ"),("CHART","折れ線グラフ"),("TABLE","値テーブル"),("MONITOR","変動監視")],
    "RingStyle": [("NONE","なし"),("LINE","細線"),("BOLD","太線"),("METAL","メタル")],
    "PanelStyle": [("FLAT","なし (平ら)"),("INSET","埋め込み (へこみ)"),("RAISED","浮き出し")],
    "LegendPosition": [("TOP","上"),("BOTTOM","下"),("INSIDE_TOP_LEFT","グラフ内 左上"),("INSIDE_TOP_RIGHT","グラフ内 右上"),("INSIDE_BOTTOM_LEFT","グラフ内 左下"),("INSIDE_BOTTOM_RIGHT","グラフ内 右下"),("HIDDEN","出さない")],
    "LegendAlign": [("START","左寄せ"),("CENTER","中央"),("END","右寄せ")],
    "BgPattern": [("NONE","なし"),("GRID","格子"),("CHECK","チェック"),("STRIPE","ストライプ"),("DOT","ドット"),("WOOD","木目"),("CARBON","カーボン"),("HONEYCOMB","ハニカム")],
    "ConnectionType": [("SIMULATOR","シミュレーター (車なしで動作確認)"),("BLE","Bluetooth LE (OBDLink CX / MX+ など)"),("WIFI","Wi-Fi (ELM327 Wi-Fi など)")],
}

C = "Int64?"
STRUCTS = [
 ("GaugeDesign", """
label String? nil
min Double? nil
max Double? nil
useDefaultWarn Bool true
warnAbove Double? nil
warnBelow Double? nil
decimals Int? nil
color Int64? nil
startAngle Double -120
endAngle Double 120
counterClockwise Bool false
majorDivisions Int? nil
minorDivisions Int 0
showLabels Bool true
tickRadius Double 1
tickColor Int64? nil
labelColor Int64? nil
labelSize Double 1
ring RingStyle .NONE
ringColor Int64? nil
ringThickness Double 1
ringDepth Double 0.6
ringInner Double 0.4
showTrack Bool true
showValueArc Bool true
arcWidth Double 1
showRedZone Bool true
redZoneFrom Double? nil
redZoneTo Double? nil
redZoneColor Int64? nil
showNeedle Bool true
needleColor Int64? nil
needleLength Double 1
needleWidth Double 1
needleTail Double 0.12
knobColor Int64? nil
knobSize Double 1
showPeak Bool false
peakColor Int64? nil
showPeakValue Bool false
peakTextColor Int64? nil
peakTextSize Double 1
peakTextX Double 0
peakTextY Double 0
showValue Bool true
valueColor Int64? nil
valuePosition Double 0.42
valueOffsetX Double 0
valueSize Double 1
showName Bool true
showUnit Bool true
valueFont String? nil
labelFont String? nil
backgroundImage String? nil
imageScale Double 1
nameOffsetX Double 0
nameOffsetY Double 0
nameColor Int64? nil
unitOffsetX Double 0
unitOffsetY Double 0
unitColor Int64? nil
faceColor Int64? nil
faceScale Double 1
panelStyle PanelStyle .FLAT
panelDepth Double 0.6
panelGloss Bool false
needleShadow Bool false
objectShadow Bool false
shadowStrength Double 1
barAngle Double 0
barSegments Int 0
barSegmentGap Double 0.25
barArc Bool false
barTaper Double 0
barOffColor Int64? nil
barZoneColors Bool false
barMidColor Int64? nil
barMidFrom Double? nil
showTicks Bool true
arcRoundCap Bool false
trackColor Int64? nil
arcTipDot Bool false
arcTipColor Int64? nil
smoothing Double 0.5
glow Double 0
ghostDigits Bool false
ghostAlpha Double 0.15
imageOffsetX Double 0
imageOffsetY Double 0
showCard Bool true
lampCondition String ""
lampOnColor Int64? nil
lampOffColor Int64? nil
tableMaxRows Int 5
tableValueBg Int64? nil
tableValueImage String? nil
tableNameRatio Double 0.4
tableUnitRatio Double 0.2
tableUnitInline Bool false
tableNameInline Bool false
tableNameSize Double 1
tableUnitSize Double 1
tableMarginBottom Double 0
tableMarginRight Double 0
tableRowGap Double 0
tableColGap Double 0
chartSpanSec Int 3600
historyDays Int 1
historyMonths Int 3
historyHours Int 0
recordIntervalSec Double 60
recordOnChange Bool false
chartSkipGaps Bool true
monitorWindowMs Int64 86400000
legendPosition LegendPosition .TOP
legendAlign LegendAlign .START
legendScale Double 1
legendBgAlpha Double 0.5
recordOnlyWhenShown Bool false
chartColors [Int64?] []
"""),
 ("GaugeConfig", """
pidKey String ""
style GaugeStyle .ANALOG
id Int64 0
x Int 0
y Int 0
w Int 0
h Int 0
design GaugeDesign GaugeDesign()
fallbackKey String? nil
floatGroup Int? nil
layoutGroup Int64? nil
floatShow Bool true
chartKeys [String] []
itemLabels [String:String] [:]
chartAxis [String:Bool] [:]
"""),
 ("PageBackground", """
color Int64? nil
pattern BgPattern .NONE
patternColor Int64? nil
patternScale Double 1
patternAlpha Double 0.35
image String? nil
imageX Double 0.5
imageY Double 0.5
imageWidth Double 1
imageHeight Double 1
keepAspect Bool true
imageAlpha Double 1
"""),
 ("Dashboard", """
id Int64 0
name String ""
columns Int 2
gauges [GaugeConfig] []
background PageBackground PageBackground()
unitScale Int 1
"""),
 ("CustomPid", """
id Int64 0
name String ""
shortName String ""
unit String ""
mode String "22"
pid String ""
header String ""
canExtAddress String ""
formula String "A"
min Double 0
max Double 100
decimals Int 0
warnAbove Double? nil
warnBelow Double? nil
slow Bool false
"""),
 ("FontEntry", """
id String ""
name String ""
file String ""
sha String ""
"""),
 ("BackupManifest", """
format String "obdmeter-backup"
version Int 1
appVersion String ""
exportedAt String ""
dashboards [Dashboard] []
customPids [CustomPid] []
fonts [FontEntry] []
pollIntervalsMs [String:Int]? nil
"""),
 ("AppSettings", """
connectionType ConnectionType .SIMULATOR
bleDeviceId String? nil
bleDeviceName String ""
wifiHost String "192.168.0.10"
wifiPort Int 35000
elmProtocol String "6"
elmSingleResponseHint Bool true
autoReconnect Bool true
autoConnect Bool false
alwaysShowToolbar Bool false
waitForVehicle Bool true
waitTimeoutMin Int 15
keepScreenOn Bool true
gridStep Int 4
pollIntervalsMs [String:Int] [:]
lastPageId Int64? nil
"""),
]

out = ["// このファイルは tools/gen_models.py で生成しています。直接編集しないでください。", "import Foundation", ""]
for name, cases in ENUMS.items():
    out.append(f"enum {name}: String, Codable, CaseIterable, Identifiable {{")
    for c, _ in cases:
        out.append(f"    case {c}")
    out.append("")
    out.append("    var id: String { rawValue }")
    out.append("")
    out.append("    var label: String {")
    out.append("        switch self {")
    for c, l in cases:
        out.append(f'        case .{c}: return "{l}"')
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")

for name, spec in STRUCTS:
    fields = []
    for line in spec.strip().splitlines():
        n, t, d = line.split(" ", 2)
        fields.append((n, t, d))
    out.append(f"struct {name}: Codable, Equatable {{")
    for n, t, d in fields:
        if t.endswith("?"):
            out.append(f"    var {n}: {t} = {d}")
        else:
            out.append(f"    var {n}: {t} = {d}")
    out.append("")
    out.append("    enum CodingKeys: String, CodingKey {")
    out.append("        case " + ", ".join(n for n, _, _ in fields))
    out.append("    }")
    out.append("}")
    out.append("")
    out.append(f"extension {name} {{")
    out.append("    init(from decoder: Decoder) throws {")
    out.append("        let c = try decoder.container(keyedBy: CodingKeys.self)")
    out.append(f"        let d = {name}()")
    for n, t, d in fields:
        if t.endswith("?"):
            base = t[:-1]
            out.append(f"        {n} = (try? c.decodeIfPresent({base}.self, forKey: .{n})) ?? d.{n}")
        else:
            out.append(f"        {n} = (try? c.decodeIfPresent({t}.self, forKey: .{n})) ?? d.{n}")
    out.append("    }")
    out.append("}")
    out.append("")

print("\n".join(out))
