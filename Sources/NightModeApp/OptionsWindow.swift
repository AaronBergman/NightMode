import AppKit
import SwiftUI
import NightModeCore

/// The "Dynamic Options" window.
final class OptionsWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let hosting = NSHostingController(rootView: OptionsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "NightMode Dynamic Options"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 700, height: 560)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NightModeDynamicOptions")
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("NightModeDynamicOptions") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show() {
        model.optionsWindowVisible = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.optionsWindowVisible = false
    }
}

public struct OptionsView: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusHeader(model: model)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            PresetsSection(model: model)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            Picker("Section", selection: $model.selectedTab) {
                Text("Ramp").tag(OptionsTab.ramp)
                Text("Schedule").tag(OptionsTab.schedule)
                Text("Brightness").tag(OptionsTab.brightness)
                Text("General").tag(OptionsTab.general)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            Group {
                switch model.selectedTab {
                case .ramp: RampTab(model: model)
                case .schedule: ScheduleTab(model: model)
                case .brightness: BrightnessTab(model: model)
                case .general: GeneralTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 700, idealWidth: 700, maxWidth: .infinity, minHeight: 560, idealHeight: 780, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Header

struct StatusHeader: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let summary = model.summary()
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text(model.isOff ? "Off" : Level.format(model.displayedLevel))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(levelColor)
                    .frame(minWidth: 110, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Label(summary.title, systemImage: summary.symbol)
                        .font(.headline)
                    if let detail = summary.detail {
                        Text(detail).font(.callout).foregroundColor(.secondary)
                    }
                    if !model.backend.isAvailable {
                        Text(model.backend.unavailableReason ?? "Night Shift is not available.")
                            .font(.callout).foregroundColor(.red)
                    }
                }
                Spacer()
                Toggle("On", isOn: Binding(get: { !model.isOff }, set: { model.setOn($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Turn NightMode on or off")
            }
            HStack(spacing: 8) {
                ForEach([-5.0, -1.0], id: \.self) { delta in
                    Button(delta == -5 ? "\u{2212}5" : "\u{2212}1") { model.nudge(delta) }
                        .help("\(Int(-delta))% cooler")
                }
                Slider(value: Binding(get: { model.isOff ? model.evaluation.underlyingLevel : model.displayedLevel },
                                      set: { model.setLevel($0.rounded(), style: .immediate) }),
                       in: 0...100)
                ForEach([1.0, 5.0], id: \.self) { delta in
                    Button("+\(Int(delta))") { model.nudge(delta) }
                        .help("\(Int(delta))% warmer")
                }
                if case .override = model.evaluation.source {
                    Button("Resume Automation") { model.resumeAutomation() }
                }
                if model.state.engine.ramp != nil {
                    Button("Cancel Ramp") { model.cancelRamp() }
                }
            }
            .controlSize(.small)
        }
        .disabled(!model.backend.isAvailable)
    }

    private var levelColor: Color {
        if model.isOff { return .secondary }
        return Color(nsColor: IconRenderer.tintColor(level: model.displayedLevel, dark: colorScheme == .dark))
    }
}

// MARK: - Presets

struct PresetsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommended").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Presets.recommended) { preset in
                    PresetCard(preset: preset, isActive: isActive(preset)) { model.applyPreset(preset) }
                        .disabled(!isAvailable(preset))
                }
            }
            if let undo = model.scheduleUndo {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle")
                    Text("Your daily schedule was replaced by \u{201C}\(undo.presetTitle)\u{201D}.")
                    Button("Undo") { model.undoScheduleReplacement() }
                    Button("Dismiss") { model.dismissScheduleUndo() }
                }
                .font(.callout)
                .controlSize(.small)
            }
        }
    }

    private func isAvailable(_ preset: Preset) -> Bool {
        if case .followBrightness = preset.action { return model.brightnessReader.isSupported && model.backend.isAvailable }
        return model.backend.isAvailable
    }

    private func isActive(_ preset: Preset) -> Bool {
        let engine = model.state.engine
        switch preset.action {
        case .ramp: return false
        case .schedule(let transitions):
            return engine.schedule.isEnabled && AppModel.sameContent(engine.schedule.transitions, transitions)
        case .followBrightness(let curve):
            return engine.brightness.isEnabled && engine.brightness.curve.sortedPoints.map { [$0.brightness, $0.level] }
                == curve.sortedPoints.map { [$0.brightness, $0.level] }
        }
    }
}

struct PresetCard: View {
    let preset: Preset
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: preset.symbol)
                        .foregroundColor(.orange)
                    Text(preset.title).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                    }
                }
                Text(preset.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isActive ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(preset.summary)
    }
}
