import SwiftUI
import UIKit

/// 設定画面の部品

struct Head: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 14, weight: .bold)).foregroundColor(GaugeColors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16).padding(.bottom, 4)
    }
}

struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }
}

struct SwitchLine: View {
    let label: String
    let detail: String?
    let value: Bool
    let onChange: (Bool) -> Void

    init(_ label: String, _ detail: String? = nil, _ value: Bool, onChange: @escaping (Bool) -> Void) {
        self.label = label
        self.detail = detail
        self.value = value
        self.onChange = onChange
    }

    var body: some View {
        Toggle(isOn: Binding(get: { value }, set: { onChange($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 15))
                if let d = detail {
                    Text(d).font(.system(size: 12)).foregroundColor(GaugeColors.subText).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SliderLine: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let format: String
    let onChange: (Double) -> Void

    init(_ label: String, _ value: Double, _ range: ClosedRange<Double>, _ format: String, onChange: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.range = range
        self.format = format
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label).font(.system(size: 14))
                Spacer()
                Text(String(format: format, value)).font(.system(size: 13)).foregroundColor(GaugeColors.subText)
            }
            Slider(value: Binding(get: { Swift.min(Swift.max(value, range.lowerBound), range.upperBound) }, set: { onChange($0) }), in: range)
        }
        .padding(.top, 4)
    }
}

/// 横に並べる選択肢
struct Chips<T: Equatable>: View {
    let items: [(T, String)]
    let selected: (T) -> Bool
    let onPick: (T) -> Void

    init(_ items: [(T, String)], selected: @escaping (T) -> Bool, onPick: @escaping (T) -> Void) {
        self.items = items
        self.selected = selected
        self.onPick = onPick
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    let it = items[i]
                    let sel = selected(it.0)
                    Text(it.1)
                        .font(.system(size: 13))
                        .foregroundColor(sel ? GaugeColors.background : GaugeColors.text)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(sel ? GaugeColors.accent : GaugeColors.card, in: Capsule())
                        .overlay(Capsule().stroke(GaugeColors.cardBorder, lineWidth: sel ? 0 : 1))
                        .onTapGesture { onPick(it.0) }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 数値入力。空欄は nil。入力途中 ("-" や "1.") の間は値を確定しない
struct NumberField: View {
    let label: String
    let value: Double?
    let placeholder: Double?
    let onChange: (Double?) -> Void
    @State private var text: String = ""
    @State private var loaded = false

    init(_ label: String, _ value: Double?, _ placeholder: Double?, onChange: @escaping (Double?) -> Void) {
        self.label = label
        self.value = value
        self.placeholder = placeholder
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundColor(GaugeColors.subText)
            TextField(placeholder.map { fmtNumber($0) } ?? "", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, t in
                    let f = t.filter { $0.isNumber || $0 == "." || $0 == "-" }
                    if f != t { text = f; return }
                    if f.isEmpty { onChange(nil) } else if let v = Double(f) { onChange(v) }
                }
        }
        .onAppear {
            if !loaded { text = value.map { fmtNumber($0) } ?? ""; loaded = true }
        }
    }
}

/// 色の丸
struct ColorDot: View {
    let color: Color
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Circle().fill(color)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(selected ? Color.white : GaugeColors.cardBorder, lineWidth: selected ? 3 : 1))
            .onTapGesture(perform: action)
    }
}

let EXTRA_COLORS: [(String, Int64)] = [
    ("黒", 0xFF000000), ("濃いグレー", 0xFF3A3F47), ("グレー", 0xFF8A93A0), ("シルバー", 0xFFC8CDD3),
    ("赤みのオレンジ", 0xFFFF5A36), ("半透明の赤", 0x66FF5A36),
]

/// 色の選択。nil = 既定色
struct ColorLine: View {
    let label: String
    let value: Int64?
    let defaultColor: Color
    var extra: [(String, Int64)] = []
    let onChange: (Int64?) -> Void
    @State private var editing = false

    init(_ label: String, _ value: Int64?, _ defaultColor: Color, extra: [(String, Int64)] = [], onChange: @escaping (Int64?) -> Void) {
        self.label = label
        self.value = value
        self.defaultColor = defaultColor
        self.extra = extra
        self.onChange = onChange
    }

    var body: some View {
        let presets = Layout.COLORS + EXTRA_COLORS + extra
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14)).padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ZStack {
                        ColorDot(color: defaultColor, selected: value == nil) { onChange(nil) }
                        Text("既").font(.system(size: 9)).foregroundColor(defaultColor.luminance > 0.5 ? .black : .white).allowsHitTesting(false)
                    }
                    if let v = value, !presets.contains(where: { $0.1 == v }) {
                        ColorDot(color: Color(argb: v), selected: true) { editing = true }
                    }
                    Text("RGB").font(.system(size: 12))
                        .padding(.horizontal, 10).frame(height: 28)
                        .overlay(Capsule().stroke(GaugeColors.cardBorder, lineWidth: 1))
                        .onTapGesture { editing = true }
                    ForEach(presets.indices, id: \.self) { i in
                        ColorDot(color: Color(argb: presets[i].1), selected: value == presets[i].1) { onChange(presets[i].1) }
                    }
                }
                .padding(2)
            }
        }
        .sheet(isPresented: $editing) {
            RgbColorSheet(title: label, initial: value ?? defaultColor.argb) { v in onChange(v); editing = false }
                .presentationDetents([.medium, .large])
        }
    }
}

/// 色を R・G・B と不透明度、またはカラーコードで指定する
struct RgbColorSheet: View {
    let title: String
    let initial: Int64
    let onPick: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var a: Double = 255
    @State private var r: Double = 0
    @State private var g: Double = 0
    @State private var b: Double = 0
    @State private var hex = ""
    @State private var loaded = false

    private var argb: Int64 { (Int64(a) << 24) | (Int64(r) << 16) | (Int64(g) << 8) | Int64(b) }

    private func hexOf() -> String {
        Int64(a) == 255 ? String(format: "%02X%02X%02X", Int(r), Int(g), Int(b)) : String(format: "%02X%02X%02X%02X", Int(a), Int(r), Int(g), Int(b))
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 0) {
                    ZStack { GaugeColors.background; RoundedRectangle(cornerRadius: 8).fill(Color(argb: argb)).padding(6) }
                    ZStack { Color(argb: 0xFFE8EAED); RoundedRectangle(cornerRadius: 8).fill(Color(argb: argb)).padding(6) }
                }
                .frame(height: 50)
                rgbSlider("R", $r, .red)
                rgbSlider("G", $g, .green)
                rgbSlider("B", $b, .blue)
                rgbSlider("不透明", $a, .gray)
                HStack {
                    Text("#")
                    TextField("RRGGBB / AARRGGBB", text: $hex)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: hex) { _, t in
                            let h = t.uppercased().filter { "0123456789ABCDEF".contains($0) }
                            guard let v = Int64(h, radix: 16), h.count == 6 || h.count == 8 else { return }
                            if h == hexOf() { return }
                            a = h.count == 8 ? Double((v >> 24) & 0xFF) : 255
                            r = Double((v >> 16) & 0xFF)
                            g = Double((v >> 8) & 0xFF)
                            b = Double(v & 0xFF)
                        }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("決定") { onPick(argb) } }
            }
        }
        .onAppear {
            if loaded { return }
            loaded = true
            a = Double((initial >> 24) & 0xFF)
            r = Double((initial >> 16) & 0xFF)
            g = Double((initial >> 8) & 0xFF)
            b = Double(initial & 0xFF)
            hex = hexOf()
        }
    }

    private func rgbSlider(_ label: String, _ v: Binding<Double>, _ color: Color) -> some View {
        HStack {
            Text(label).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { v.wrappedValue }, set: { v.wrappedValue = $0.rounded(); hex = hexOf() }), in: 0...255)
                .tint(color)
            Text("\(Int(v.wrappedValue))").frame(width: 36).foregroundColor(GaugeColors.subText)
        }
    }
}

func snap(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
