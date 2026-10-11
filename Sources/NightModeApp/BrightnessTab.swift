import SwiftUI
import Charts
import NightModeCore

struct BrightnessTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let config = model.state.engine.brightness
        let supported = model.brightnessReader.isSupported
        Form {
            Section {
                Toggle("Follow display brightness", isOn: Binding(get: { config.isEnabled }, set: { model.setBrightnessEnabled($0) }))
                    .disabled(!supported || !model.backend.isAvailable)
                if !supported {
                    Text(model.brightnessReader.unsupportedReason ?? "Display brightness cannot be read on this Mac.")
                        .foregroundColor(.orange)
                } else {
                    LabeledContent("Built-in display brightness now") {
                        Text(model.brightness.map { "\(Int(($0 * 100).rounded()))%" } ?? "not available (lid closed?)").monospacedDigit()
                    }
                    LabeledContent("Tint from the curve") {
                        Text(model.brightness.map { Level.format(config.curve.level(forBrightness: $0)) } ?? "none").monospacedDigit()
                    }
                }
            } footer: {
                Text("The dimmer the screen, the warmer the tint. With Automatically Adjust Brightness on (System Settings > Displays), this follows the light in your room. When the daily schedule is also on, NightMode uses whichever is warmer.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Curve") {
                BrightnessCurveChart(curve: config.curve, current: model.brightness)
                    .equatable()
                    .padding(.top, 8)
                    .frame(height: 178)
                    .opacity(config.isEnabled ? 1 : 0.5)
                ForEach(config.curve.sortedPoints) { point in
                    CurvePointRow(point: binding(for: point.id), canDelete: config.curve.points.count > 2) {
                        var curve = model.state.engine.brightness.curve
                        curve.points.removeAll { $0.id == point.id }
                        model.setCurve(curve)
                    }
                }
                HStack {
                    Button {
                        var curve = model.state.engine.brightness.curve
                        let b = model.brightness ?? 0.5
                        curve.points.append(CurvePoint(brightness: b, level: curve.level(forBrightness: b)))
                        model.setCurve(curve)
                    } label: {
                        Label("Add Point", systemImage: "plus")
                    }
                    .disabled(config.curve.points.count >= 6)
                    Spacer()
                    Button("Reset to Recommended") { model.setCurve(.standard) }
                }
            }

            Section {
                Text("Brightness is checked every 2 seconds while this is on, and changes fade in over a second or two. Below the lowest point and above the highest, the level stays flat. A manual change pauses brightness following until the brightness moves by 15 points or more (or as set in General).")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for id: UUID) -> Binding<CurvePoint> {
        Binding(get: {
            model.state.engine.brightness.curve.points.first { $0.id == id } ?? CurvePoint(id: id, brightness: 0, level: 0)
        }, set: { newValue in
            var curve = model.state.engine.brightness.curve
            guard let index = curve.points.firstIndex(where: { $0.id == id }) else { return }
            curve.points[index] = newValue
            model.setCurve(curve)
        })
    }
}

struct CurvePointRow: View {
    @Binding var point: CurvePoint
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("At brightness")
            Slider(value: Binding(get: { point.brightness * 100 }, set: { point.brightness = ($0.rounded() / 100).clamped01 }), in: 0...100)
                .frame(minWidth: 90)
            Text("\(Int((point.brightness * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            Text("tint")
            Slider(value: Binding(get: { point.level }, set: { point.level = $0.rounded() }), in: 0...100)
                .frame(minWidth: 90)
            Text(Level.format(point.level)).monospacedDigit().frame(width: 40, alignment: .trailing)
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help("Remove this point")
        }
    }
}

struct BrightnessCurveChart: View, Equatable {
    let curve: BrightnessCurve
    let current: Double?

    static func == (a: BrightnessCurveChart, b: BrightnessCurveChart) -> Bool {
        a.curve == b.curve && a.current.map { ($0 * 100).rounded() } == b.current.map { ($0 * 100).rounded() }
    }

    struct Point: Identifiable {
        let x: Double
        let y: Double
        var id: Double { x }
    }

    var body: some View {
        let points = stride(from: 0.0, through: 100.0, by: 2).map { Point(x: $0, y: curve.level(forBrightness: $0 / 100)) }
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Brightness", p.x), y: .value("Tint", p.y))
                    .foregroundStyle(LinearGradient(colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.05)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Brightness", p.x), y: .value("Tint", p.y))
                    .foregroundStyle(Color.orange)
            }
            ForEach(curve.sortedPoints) { p in
                PointMark(x: .value("Brightness", p.brightness * 100), y: .value("Tint", p.level))
                    .foregroundStyle(Color.orange)
                    .symbolSize(40)
            }
            if let current {
                RuleMark(x: .value("Now", current * 100))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top) { Text("now").font(.caption2).foregroundColor(.secondary) }
                PointMark(x: .value("Brightness", current * 100), y: .value("Tint", curve.level(forBrightness: current)))
                    .foregroundStyle(Color.primary)
                    .symbolSize(60)
            }
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("Display brightness")
        .chartYAxisLabel("Tint")
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
