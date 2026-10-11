import AppKit
import Combine
import NightModeCore

public enum OptionsTab: String, CaseIterable, Identifiable {
    case ramp, schedule, brightness, general
    public var id: String { rawValue }
}

/// How a new level reaches the screen.
public enum ApplyStyle {
    /// Right away (slider drags).
    case immediate
    /// A very short fade for big jumps (presets, buttons).
    case quick
    /// A gentle fade for big jumps caused by automation (schedule starts, brightness changes, resume).
    case automatic
}

/// A snapshot of the schedule a preset replaced, so it can be undone.
public struct ScheduleUndo: Equatable {
    public var presetTitle: String
    public var transitions: [Transition]
    public var wasEnabled: Bool
}

/// Persists `AppState` as JSON in UserDefaults.
public final class StateStore {
    public static let key = "NightMode.state.v2"
    let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppState? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? AppState.decode(data)
    }

    public func save(_ state: AppState) {
        if let data = try? state.encoded() { defaults.set(data, forKey: Self.key) }
    }
}

/// Owns NightMode's state and keeps the screen in sync with it.
///
/// Timing model: the engine says when its answer could next change (`nextCheck`), and the model
/// sets exactly one timer for that moment (capped at 15 minutes). With nothing scheduled there is
/// no timer at all. Brightness is polled every 2 s only while "Follow brightness" is on (or the
/// options window is open). Sleep, wake, clock and time zone changes trigger a fresh evaluation.
public final class AppModel: ObservableObject {
    @Published public private(set) var state: AppState
    @Published public private(set) var evaluation: Evaluation
    /// What is on screen right now (follows fades).
    @Published public private(set) var displayedLevel: Double = 0
    @Published public private(set) var brightness: Double?
    @Published public private(set) var nightShift: NightShiftStatus?
    @Published public private(set) var loginItem: LoginItemState
    @Published public private(set) var scheduleUndo: ScheduleUndo?
    @Published public var selectedTab: OptionsTab = .ramp
    @Published public var lastError: String?
    /// Shortcuts that could not be registered (taken by another app).
    @Published public var hotKeyFailures: [String] = []

    public let backend: TintBackend
    public let brightnessReader: BrightnessReader
    public let loginItems: LoginItemControlling
    private let store: StateStore?
    private let clock: () -> Date
    private let calendarProvider: () -> Calendar

    private var evaluationTimer: Timer?
    private var brightnessTimer: Timer?
    private var glideTimer: Timer?
    private var glide: Segment?
    private var lastWritten: Double?
    private var lastWriteDate = Date.distantPast
    private var pendingExternalCheck: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timeZoneLocationCache: (id: String, location: NamedLocation?)?
    private var started = false

    /// Set by the options window so brightness readings stay live while it is open.
    public var optionsWindowVisible = false {
        didSet { if optionsWindowVisible { brightness = brightnessReader.read() }; updateBrightnessPolling() }
    }

    /// Called when preferences that affect the menu bar or shortcuts change.
    public var onPreferencesChanged: (() -> Void)?

    public init(backend: TintBackend, brightnessReader: BrightnessReader, loginItems: LoginItemControlling,
                store: StateStore?, initialState: AppState? = nil,
                clock: @escaping () -> Date = Date.init,
                calendar: @escaping () -> Calendar = { Calendar.autoupdatingCurrent }) {
        self.backend = backend
        self.brightnessReader = brightnessReader
        self.loginItems = loginItems
        self.store = store
        self.clock = clock
        self.calendarProvider = calendar
        let loaded = initialState ?? store?.load() ?? AppState()
        self.state = loaded
        self.loginItem = loginItems.state
        self.evaluation = Evaluation(level: 0, underlyingLevel: 0, source: .manual, nextCheck: nil, isContinuous: false, pendingRamp: nil)
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    // MARK: - Environment

    public var now: Date { clock() }
    public var calendar: Calendar { calendarProvider() }

    /// The location from the time zone (no permissions needed).
    public var timeZoneLocation: NamedLocation? {
        let id = calendar.timeZone.identifier
        if let cache = timeZoneLocationCache, cache.id == id { return cache.location }
        let location = TimeZoneLocation.location(forTimeZone: id)
        timeZoneLocationCache = (id, location)
        return location
    }

    /// The location used for sunrise and sunset.
    public var effectiveLocation: NamedLocation? { state.prefs.manualLocation ?? timeZoneLocation }

    public var environment: EngineEnvironment {
        EngineEnvironment(calendar: calendar, location: effectiveLocation?.coordinate, brightness: brightness)
    }

    public var isOff: Bool {
        if case .off = evaluation.source { return true }
        return false
    }

    // MARK: - Lifecycle

    /// Reads the current Night Shift state, reconciles without a visible jump, and starts timers.
    public func start() {
        guard !started else { return }
        started = true
        backend.onStatusChange = { [weak self] in self?.scheduleExternalCheck(after: 0.4) }
        brightness = brightnessReader.read()
        nightShift = backend.readStatus()
        let actual = nightShift?.level ?? 0
        let t = now
        let env = environment
        var engine = state.engine
        engine.advance(now: t, env: env)
        let first = engine.evaluate(now: t, env: env)
        switch LaunchReconciliation.decide(evaluation: first, actual: actual, tintWasTurnedOffOnQuit: state.tintWasTurnedOffOnQuit) {
        case .adoptActual:
            if case .off = first.source {
                engine.setLevel(actual, now: t, env: env)
            } else {
                engine.manualLevel = actual
            }
        case .applyEvaluation:
            break
        }
        state.engine = engine
        state.tintWasTurnedOffOnQuit = false
        lastWritten = backend.isAvailable ? actual : nil
        displayedLevel = actual
        installSystemObservers()
        refresh(style: .automatic)
        saveNow()
    }

    /// Finishes any fade, applies the quit preference, and saves.
    public func prepareForQuit() {
        if let glide {
            stopGlide()
            write(glide.to, force: true)
        }
        evaluationTimer?.invalidate()
        brightnessTimer?.invalidate()
        if state.prefs.quitBehavior == .turnTintOff, backend.isAvailable, (lastWritten ?? 0) >= Level.offThreshold {
            backend.apply(level: 0)
            state.tintWasTurnedOffOnQuit = true
        } else {
            state.tintWasTurnedOffOnQuit = false
        }
        saveNow()
    }

    // MARK: - Evaluation loop

    /// Recomputes the level and applies it.
    /// - Parameter checkExternal: first look for changes made outside NightMode (used by timers).
    public func refresh(style: ApplyStyle = .automatic, checkExternal: Bool = false) {
        if checkExternal, checkForExternalChange() { return }
        let t = now
        let env = environment
        var engine = state.engine
        if engine.advance(now: t, env: env) {
            state.engine = engine
            scheduleSave()
        }
        let result = engine.evaluate(now: t, env: env)
        if result != evaluation { evaluation = result }
        applyTarget(result.level, style: style)
        if glide == nil { refreshNightShiftStatus() }
        scheduleNextEvaluation(result.nextCheck, from: t)
        updateBrightnessPolling()
    }

    /// Keeps the cached Night Shift status (shown in the General tab) current after our own writes.
    private func refreshNightShiftStatus() {
        guard backend.isAvailable, let status = backend.readStatus(), status != nightShift else { return }
        nightShift = status
    }

    private func mutate(style: ApplyStyle = .automatic, _ change: (inout EngineState, Date, EngineEnvironment) -> Void) {
        let t = now
        var engine = state.engine
        change(&engine, t, environment)
        state.engine = engine
        scheduleSave()
        refresh(style: style)
    }

    private func scheduleNextEvaluation(_ next: Date?, from t: Date) {
        evaluationTimer?.invalidate()
        evaluationTimer = nil
        guard started, let next else { return }  // nothing scheduled: no timer, no CPU
        let interval = min(15 * 60, max(0.25, next.timeIntervalSince(t)))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh(style: .automatic, checkExternal: true)
        }
        timer.tolerance = min(30, max(0.05, interval * 0.1))
        RunLoop.main.add(timer, forMode: .common)
        evaluationTimer = timer
    }

    // MARK: - Writing to the display

    private func applyTarget(_ rawTarget: Double, style: ApplyStyle) {
        let target = Level.clamp(rawTarget)
        let current = displayedLevel
        let delta = abs(target - current)
        let duration: TimeInterval
        switch style {
        case .immediate: duration = 0
        case .quick: duration = delta > 2 ? 0.35 : 0
        case .automatic: duration = delta > 2 ? min(2.5, 0.6 + delta / 60) : 0
        }
        guard duration > 0, started else {
            stopGlide()
            write(target)
            return
        }
        if let glide, abs(glide.to - target) < 0.05 { return }
        glide = Segment(from: current, to: target, start: Date(), duration: duration, easing: .smooth)
        if glideTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.glideTick() }
            RunLoop.main.add(timer, forMode: .common)
            glideTimer = timer
        }
    }

    private func glideTick() {
        guard let glide else { stopGlide(); return }
        let t = Date()
        if t >= glide.end {
            stopGlide()
            write(glide.to, force: true)  // land exactly on the target
            refreshNightShiftStatus()
        } else {
            write(glide.value(at: t))
        }
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glide = nil
    }

    private func write(_ raw: Double, force: Bool = false) {
        let value = Level.clamp(raw)
        if !force, let last = lastWritten {
            let crossesOff = (last < Level.offThreshold) != (value < Level.offThreshold)
            if !crossesOff && abs(last - value) < 0.1 {
                if displayedLevel != value { displayedLevel = value }
                return
            }
        }
        backend.apply(level: value)
        lastWritten = value
        lastWriteDate = Date()
        displayedLevel = value
    }

    // MARK: - Changes made outside NightMode

    private func scheduleExternalCheck(after delay: TimeInterval) {
        pendingExternalCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.checkForExternalChange() }
        pendingExternalCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Compares Night Shift's real state with what NightMode last wrote. Returns true if it acted.
    @discardableResult
    public func checkForExternalChange() -> Bool {
        guard backend.isAvailable, started else { return false }
        let sinceWrite = Date().timeIntervalSince(lastWriteDate)
        if glide != nil || sinceWrite < 1.5 {
            // Our own write may not be visible yet; look again shortly.
            scheduleExternalCheck(after: max(0.2, 1.6 - sinceWrite))
            return false
        }
        guard let status = backend.readStatus() else { return false }
        if status != nightShift { nightShift = status }
        guard let expected = lastWritten else { return false }
        let reaction = ExternalChangePolicy.react(expected: expected, actual: status.level, source: evaluation.source,
                                                  now: now, calendar: calendar,
                                                  systemDayStart: (status.dayStart.hour, status.dayStart.minute))
        switch reaction {
        case .ignore:
            return false
        case .reassert:
            lastWritten = nil
            refresh(style: .automatic)
            return true
        case .adopt(let level):
            lastWritten = level
            displayedLevel = level
            mutate(style: .immediate) { $0.setLevel(level, now: $1, env: $2) }
            return true
        }
    }

    /// Re-reads everything (menu opening, wake).
    public func resync() {
        brightness = brightnessReader.read()
        refresh(style: .automatic, checkExternal: true)
        loginItem = loginItems.state
    }

    // MARK: - Brightness

    private func updateBrightnessPolling() {
        let wanted = started && brightnessReader.isSupported
            && ((state.engine.brightness.isEnabled && state.engine.isOn) || optionsWindowVisible)
        if wanted, brightnessTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.pollBrightness() }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            brightnessTimer = timer
        } else if !wanted, let timer = brightnessTimer {
            timer.invalidate()
            brightnessTimer = nil
        }
    }

    private func pollBrightness() {
        let value = brightnessReader.read()
        let changed: Bool
        switch (value, brightness) {
        case (nil, nil): changed = false
        case let (a?, b?): changed = abs(a - b) >= 0.004
        default: changed = true
        }
        guard changed else { return }
        brightness = value
        if state.engine.brightness.isEnabled { refresh(style: .automatic, checkExternal: true) }
    }

    // MARK: - System events

    private func installSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give the display a moment to come back before reading it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.resync() }
            }
            observers.append((workspace, token))
        }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged,
                                          NSApplication.didChangeScreenParametersNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.timeZoneLocationCache = nil
                self?.resync()
            }
            observers.append((center, token))
        }
    }

    // MARK: - Actions (menu, window, shortcuts)

    public func setLevel(_ level: Double, style: ApplyStyle = .immediate) {
        mutate(style: style) { $0.setLevel(level, now: $1, env: $2) }
    }

    public func nudge(_ delta: Double) {
        mutate(style: .quick) { $0.nudge(by: delta, now: $1, env: $2) }
    }

    public func setOn(_ on: Bool) {
        mutate(style: .quick) { engine, _, _ in engine.setOn(on) }
    }

    public func toggleOn() {
        setOn(isOff)
    }

    public func turnOffForAnHour() {
        mutate(style: .quick) { engine, t, _ in engine.turnOff(for: 3600, now: t) }
    }

    /// - Parameter start: nil means now.
    public func startRamp(origin: Ramp.Origin, to target: Double, minutes: Double, start: Date?, easing: Easing) {
        mutate(style: .automatic) { engine, t, env in
            let begin = max(start ?? t, t)
            engine.startRamp(origin: origin, to: target, start: begin, duration: max(0, minutes) * 60, easing: easing, now: t, env: env)
        }
    }

    /// Starts a ramp from the Ramp tab's form values.
    public func startRampFromDraft() {
        let draft = state.prefs.rampDraft
        var start: Date?
        if !draft.startNow {
            start = nextOccurrence(hour: draft.startHour, minute: draft.startMinute)
        }
        startRamp(origin: draft.fromCurrent ? .current : .fixed(draft.fromLevel), to: draft.toLevel,
                  minutes: draft.minutes, start: start, easing: draft.easing)
    }

    public func nextOccurrence(hour: Int, minute: Int) -> Date {
        let t = now
        let cal = calendar
        return cal.nextDate(after: t, matching: DateComponents(hour: hour, minute: minute, second: 0),
                            matchingPolicy: .nextTime) ?? t
    }

    public func cancelRamp() {
        mutate(style: .quick) { $0.cancelRamp(now: $1, env: $2) }
    }

    public func resumeAutomation() {
        mutate(style: .automatic) { engine, _, _ in engine.resumeAutomation() }
    }

    public func setScheduleEnabled(_ enabled: Bool) {
        mutate(style: .automatic) { $0.setScheduleEnabled(enabled, now: $1, env: $2) }
    }

    public func setBrightnessEnabled(_ enabled: Bool) {
        brightness = brightnessReader.read()
        mutate(style: .automatic) { $0.setBrightnessEnabled(enabled, now: $1, env: $2) }
    }

    public func setTransitions(_ transitions: [Transition]) {
        mutate(style: .automatic) { $0.setTransitions(transitions, now: $1, env: $2) }
    }

    public func setCurve(_ curve: BrightnessCurve) {
        mutate(style: .automatic) { engine, _, _ in engine.brightness.curve = curve }
    }

    public func setPausePolicy(_ policy: PausePolicy) {
        mutate(style: .automatic) { engine, _, env in engine.setPausePolicy(policy, env: env) }
    }

    public func setManualLocation(_ location: NamedLocation?) {
        state.prefs.manualLocation = location
        scheduleSave()
        refresh(style: .automatic)
    }

    public func updatePreferences(_ change: (inout Preferences) -> Void) {
        var prefs = state.prefs
        change(&prefs)
        guard prefs != state.prefs else { return }
        state.prefs = prefs
        scheduleSave()
        onPreferencesChanged?()
    }

    public func applyPreset(_ preset: Preset) {
        switch preset.action {
        case .ramp(let origin, let target, let minutes, let easing):
            updatePreferences { prefs in
                prefs.rampDraft.fromCurrent = true
                prefs.rampDraft.toLevel = target
                prefs.rampDraft.minutes = minutes
                prefs.rampDraft.startNow = true
                prefs.rampDraft.easing = easing
            }
            startRamp(origin: origin, to: target, minutes: minutes, start: nil, easing: easing)
            selectedTab = .ramp
        case .schedule(let transitions):
            let fresh = transitions.map { transition -> Transition in
                var copy = transition
                copy.id = UUID()
                return copy
            }
            let previous = state.engine.schedule
            if !Self.sameContent(previous.transitions, fresh) {
                scheduleUndo = ScheduleUndo(presetTitle: preset.title, transitions: previous.transitions, wasEnabled: previous.isEnabled)
            }
            mutate(style: .automatic) { engine, t, env in
                engine.setTransitions(fresh, now: t, env: env)
                engine.setScheduleEnabled(true, now: t, env: env)
            }
            selectedTab = .schedule
        case .followBrightness(let curve):
            brightness = brightnessReader.read()
            mutate(style: .automatic) { engine, t, env in
                engine.brightness.curve = curve
                engine.setBrightnessEnabled(true, now: t, env: env)
            }
            selectedTab = .brightness
        }
    }

    public func undoScheduleReplacement() {
        guard let undo = scheduleUndo else { return }
        scheduleUndo = nil
        mutate(style: .automatic) { engine, t, env in
            engine.setTransitions(undo.transitions, now: t, env: env)
            engine.setScheduleEnabled(undo.wasEnabled, now: t, env: env)
        }
    }

    public func dismissScheduleUndo() { scheduleUndo = nil }

    public func turnOffSystemNightShiftSchedule() {
        backend.turnOffSystemSchedule()
        nightShift = backend.readStatus()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.set(enabled)
            lastError = nil
        } catch {
            lastError = "Could not change Launch at Login: \(error.localizedDescription)"
        }
        loginItem = loginItems.state
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard store != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        store?.save(state)
    }

    static func sameContent(_ a: [Transition], _ b: [Transition]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in
            var y2 = y
            y2.id = x.id
            return x == y2
        }
    }
}
