import SwiftUI
import AppKit
import ServiceManagement

final class ProviderRunner {
    let name: String
    let path: String

    private let queue: DispatchQueue
    private let onUpdate: (String, Report?, ProviderMessage?, String) -> Void

    private let stopFlag = NSLock()
    private var stoppedFlag = false
    private var isStopped: Bool { stopFlag.lock(); defer { stopFlag.unlock() }; return stoppedFlag }

    private let readerLock = NSLock()
    private var liveReader: StreamReader?

    private var generation = 0
    private var interval: TimeInterval = 5

    private var lastReport: Report?
    private var lastLine: TimeInterval = 0
    private var streamStarted = Date.distantPast
    private var sawLine = false
    private var streamFailures = 0
    private var streamGaveUp = false
    private var gaveUpAt = Date.distantPast
    private var watchdog: DispatchSourceTimer?

    private static let statusTimeout: TimeInterval = 4
    private static let streamSilenceLimit: TimeInterval = 25
    private static let streamRetryAfter: TimeInterval = 120

    init(name: String, path: String,
         onUpdate: @escaping (String, Report?, ProviderMessage?, String) -> Void) {
        self.name = name
        self.path = path
        self.onUpdate = onUpdate
        self.queue = DispatchQueue(label: "com.kishore.maester.provider.\(name)",
                                   qos: .utility)
    }

    func start() { queue.async { [weak self] in self?.poll() } }

    func refreshNow() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            guard self.reader != nil else { self.poll(); return }
            self.sampleOnce()
        }
    }

    private func sampleOnce() {
        let r = ProviderExec.run(path: path, args: ["status"], timeout: Self.statusTimeout)
        guard !isStopped else { return }
        guard !r.timedOut, r.code == 0, let report = Self.decode(r.stdout) else {
            publish(nil, .notice("refresh did not get a reading — still streaming"), "stream")
            return
        }
        publish(report, nil, "stream")
    }

    func stop() {
        stopFlag.lock(); stoppedFlag = true; stopFlag.unlock()
        readerLock.lock()
        let r = liveReader
        liveReader = nil
        readerLock.unlock()
        r?.stop()
        queue.async { [weak self] in
            self?.generation += 1
            self?.watchdog?.cancel()
            self?.watchdog = nil
        }
    }

    private var reader: StreamReader? {
        get { readerLock.lock(); defer { readerLock.unlock() }; return liveReader }
        set { readerLock.lock(); liveReader = newValue; readerLock.unlock() }
    }

    func recoverFromWake() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            if let r = self.reader {
                r.forceRestart()
            } else {
                self.generation += 1
                self.poll()
            }
        }
    }

    func perform(action: String, item: String?, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isStopped else {
                DispatchQueue.main.async { completion("\(action) cancelled — shutting down") }
                return
            }
            guard self.lastReport?.spec(action: action, item: item) != nil else {
                DispatchQueue.main.async {
                    completion("\(self.name): '\(action)' is no longer declared")
                }
                return
            }
            var args = ["do", action]
            if let item { args.append(item) }
            let r = ProviderExec.run(path: self.path, args: args, timeout: 180)
            let problem = self.problem(from: r, action: action)
            DispatchQueue.main.async { completion(problem) }
            if self.reader == nil { self.poll() }
        }
    }

    private func problem(from r: ExecOutcome, action: String) -> String? {
        if r.timedOut { return "\(name): \(action) timed out" }
        guard r.code != 0 else { return nil }
        let detail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").last.map(String.init) ?? "exit \(r.code)"
        return "\(name): \(action) failed — \(detail)"
    }

    private func publish(_ report: Report?, _ message: ProviderMessage?, _ source: String) {
        if let report { lastReport = report }
        onUpdate(name, report ?? lastReport, message, source)
    }

    private func poll() {
        guard !isStopped else { return }
        let r = ProviderExec.run(path: path, args: ["status"], timeout: Self.statusTimeout)

        if r.timedOut {
            publish(nil, .failure("timed out after \(Int(Self.statusTimeout))s"), "poll")
            scheduleNext(); return
        }
        if r.code != 0 {
            publish(nil, .failure("status exited \(r.code)\(Self.tail(r.stderr))"), "poll")
            scheduleNext(); return
        }
        guard let report = Self.decode(r.stdout) else {
            publish(nil, .failure("bad output — status did not print one JSON report"), "poll")
            scheduleNext(); return
        }

        interval = report.caps.interval
        if streamGaveUp, Date().timeIntervalSince(gaveUpAt) > Self.streamRetryAfter {
            streamGaveUp = false
            streamFailures = 0
        }
        if report.caps.streams && !streamGaveUp {
            publish(report, nil, "stream")
            startStream()
        } else {
            publish(report, nil, streamGaveUp ? "poll (stream gave up)" : "poll")
            scheduleNext()
        }
    }

    private func scheduleNext() {
        guard !isStopped else { return }
        generation += 1
        let g = generation
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self, !self.isStopped, g == self.generation, self.reader == nil else { return }
            self.poll()
        }
    }

    private func startStream() {
        guard !isStopped, reader == nil else { return }
        generation += 1
        do {
            let child = try Child(path: path, args: ["stream"],
                                  environment: ProviderEnvironment.value)
            guard !isStopped else { child.kill(); return }
            sawLine = false
            streamStarted = Date()
            lastLine = ProcessInfo.processInfo.systemUptime
            reader = StreamReader(child: child, onLine: { [weak self] line in
                self?.queue.async { self?.handle(line: line) }
            }, onEnd: { [weak self] code, err in
                self?.queue.async { self?.streamEnded(code: code, stderr: err) }
            })
            startWatchdog()
        } catch {
            streamFailures += 1
            if streamFailures >= 3 { streamGaveUp = true; gaveUpAt = Date() }
            publish(nil, .failure("cannot start stream: \(error)"), "poll")
            scheduleNext()
        }
    }

    private func handle(line: String) {
        guard !isStopped else { return }
        lastLine = ProcessInfo.processInfo.systemUptime
        sawLine = true
        guard let report = Self.decode(line) else {
            publish(nil, .failure("bad output — a stream line was not a valid report"), "stream")
            return
        }
        streamFailures = 0
        interval = report.caps.interval
        publish(report, nil, "stream")
    }

    private func streamEnded(code: Int32, stderr: String) {
        watchdog?.cancel(); watchdog = nil
        reader = nil
        guard !isStopped else { return }

        let ranFor = Date().timeIntervalSince(streamStarted)
        if sawLine && ranFor > 30 {
            streamFailures = 1
        } else {
            streamFailures += 1
        }

        if streamFailures >= 3 {
            streamGaveUp = true
            gaveUpAt = Date()
            publish(nil, .notice("stream failed \(streamFailures) times — polling instead"), "poll")
            scheduleNext()
            return
        }

        let backoff = min(pow(2.0, Double(streamFailures)), 30)
        publish(nil, .notice("stream ended (exit \(code))\(Self.tail(stderr)) — retrying in \(Int(backoff))s"),
                "stream")
        queue.asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self, !self.isStopped, self.reader == nil else { return }
            self.startStream()
        }
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self, let reader = self.reader else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastLine > Self.streamSilenceLimit {
                self.publish(nil, .notice("stream went silent — restarting"), "stream")
                reader.forceRestart()
            }
        }
        t.resume()
        watchdog = t
    }

    private static func decode(_ s: String) -> Report? {
        Report.decode(s)
    }

    private static func tail(_ stderr: String) -> String {
        let last = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").last.map(String.init) ?? ""
        return last.isEmpty ? "" : ": \(last)"
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { openSettings() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Trace.log("login item toggle failed: \(error)")
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

final class IconModel: ObservableObject {
    @Published var state: HealthState = .off

    func set(_ s: HealthState) {
        if s != state { state = s }
    }
}

enum Trace {
    static let on = ProcessInfo.processInfo.environment["MAESTER_DEBUG"] != nil

    static func log(_ message: String) {
        guard on else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        FileHandle.standardError.write(Data("\(fmt.string(from: Date())) \(message)\n".utf8))
    }
}

@MainActor
final class Monitor: ObservableObject {
    static let retirementBudget: TimeInterval = 8

    private var store: [ProviderState] = []
    private var retired = RetirementLedger()
    @Published private(set) var revision = 0

    var providers: [ProviderState] { store.filter { !$0.disabled }.map(withoutRetired) }
    var discovered: [ProviderState] { store }

    private func withoutRetired(_ s: ProviderState) -> ProviderState {
        let ids = retiredItems(of: s.id)
        guard !ids.isEmpty, let report = s.report else { return s }
        var copy = s
        copy.report = report.withoutItems(ids)
        return copy
    }

    @Published private(set) var overall: HealthState = .off
    @Published private(set) var actionError: String?
    @Published private(set) var actionInFlight = false
    @Published private(set) var configNotice: ProviderMessage?

    @Published private(set) var panelVisible = false

    func panelDidAppear() { panelVisible = true; revision &+= 1 }
    func panelDidDisappear() { panelVisible = false }

    let history = MetricHistory()
    let icon = IconModel()

    @Published private(set) var density: Density = DensityConfig.read()

    func setDensity(_ d: Density) {
        guard d != density else { return }
        density = d
        try? DensityConfig.write(d)
    }

    static private(set) weak var current: Monitor?

    private var runners: [String: ProviderRunner] = [:]
    private var busy: Set<String> = []
    private var rescanTimer: Timer?
    private var disabledNames: Set<String> = []

    init() {
        Monitor.current = self
        rescan()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    var headline: String {
        if providers.isEmpty { return "no providers" }
        let bad = providers.filter { $0.state == .error }
        let warn = providers.filter { $0.state == .warn }
        if !bad.isEmpty {
            return bad.count == 1 ? "\(bad[0].title) is in error"
                                  : "\(bad.count) providers in error"
        }
        if !warn.isEmpty {
            return warn.count == 1 ? "\(warn[0].title) needs attention"
                                   : "\(warn.count) providers need attention"
        }
        let off = providers.filter { $0.state == .off }.count
        if off > 0 { return "all clear · \(off) stopped" }
        return "all clear"
    }

    var footprint: String {
        let n = providers.count
        let streaming = providers.filter { $0.source.hasPrefix("stream") }.count
        var s = "\(n) provider\(n == 1 ? "" : "s")"
        if streaming > 0 { s += " · \(streaming) streaming" }
        if let t = providers.compactMap({ $0.lastUpdate }).max() {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm:ss"
            s += " · \(fmt.string(from: t))"
        }
        return s
    }

    func rescan() {
        let result = ProviderDiscovery.list()
        let found = result.providers
        disabledNames = Set(found.filter { $0.disabled }.map { $0.name })
        configNotice = result.configNotice.map { ProviderMessage.notice($0) }
        let names = Set(found.map(\.name))

        for (name, runner) in runners where !names.contains(name) {
            runner.stop()
            runners.removeValue(forKey: name)
            history.forget(provider: name)
        }
        let removed = store.count
        store.removeAll { !names.contains($0.id) }
        if store.count != removed { revision &+= 1 }

        for d in found {
            if let refusal = d.refusal {
                Trace.log("refused \(d.name): \(refusal)")
                runners[d.name]?.stop()
                runners.removeValue(forKey: d.name)
                upsert(ProviderState(id: d.name, report: nil,
                                     message: .failure("refused to load: \(refusal)"),
                                     source: "", lastUpdate: Date(),
                                     disabled: d.disabled, refusal: refusal))
                continue
            }
            if !d.live {
                runners[d.name]?.stop()
                runners.removeValue(forKey: d.name)
                history.forget(provider: d.name)
                upsert(ProviderState(id: d.name, report: nil, message: nil,
                                     source: "", lastUpdate: nil, disabled: true))
                continue
            }
            guard runners[d.name] == nil else { continue }
            let runner = ProviderRunner(name: d.name, path: d.path) { [weak self] name, report, message, source in
                if let report { self?.history.absorb(provider: name, report: report) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.apply(name: name, report: report, message: message, source: source)
                    }
                }
            }
            runners[d.name] = runner
            upsert(ProviderState(id: d.name, report: nil, message: nil,
                                 source: "starting", lastUpdate: nil))
            runner.start()
        }
        recomputeOverall()
    }

    private func upsert(_ s: ProviderState) {
        if let i = store.firstIndex(where: { $0.id == s.id }) {
            store[i] = s
        } else {
            store.append(s)
            store.sort { $0.id < $1.id }
        }
        revision &+= 1
    }

    private func apply(name: String, report: Report?, message: ProviderMessage?, source: String) {
        guard let i = store.firstIndex(where: { $0.id == name }) else { return }
        let wasState = store[i].state
        let wasNotable = Self.notable(store[i])
        store[i].report = report ?? store[i].report
        sweepRetired(provider: name, report: report)
        store[i].message = message
        store[i].source = source
        store[i].lastUpdate = Date()
        recomputeOverall()

        let isNotable = Self.notable(store[i])
        if wasNotable != isNotable {
            Trace.log("provider \(name) state=\(store[i].state.rawValue) source=\(source) " +
                      "items=\(store[i].report?.items?.count ?? 0) " +
                      "note=\(message?.text ?? "-") overall=\(overall.rawValue)")
        }
        if panelVisible || store[i].state != wasState { revision &+= 1 }
    }

    private static func notable(_ p: ProviderState) -> String {
        [p.state.rawValue, p.source, p.message?.text ?? ""].joined(separator: "\u{1}")
    }

    private func recomputeOverall() {
        let worst = store.filter { !$0.disabled }.map(\.state).max() ?? .off
        guard worst != overall else { return }
        Trace.log("icon \(overall.rawValue) -> \(worst.rawValue) (\(worst.menuBarSymbol))")
        overall = worst
        icon.set(worst)
    }

    func refreshNow() {
        rescan()
        for r in runners.values { r.refreshNow() }
    }

    func isBusy(_ provider: String, _ action: String, _ item: String?) -> Bool {
        busy.contains(Self.busyKey(provider, action, item))
    }

    func perform(provider: String, action: String, item: String?) {
        guard let state = store.first(where: { $0.id == provider }),
              let spec = state.report?.spec(action: action, item: item) else {
            actionError = "\(provider): '\(action)' is not a declared action"
            return
        }
        guard let runner = runners[provider] else { return }
        run(runner, provider: provider, spec: spec, item: item)
    }

    private func run(_ runner: ProviderRunner, provider: String, spec: ActionSpec, item: String?) {
        let key = Self.busyKey(provider, spec.id, item)
        busy.insert(key)
        actionInFlight = true
        actionError = nil

        runner.perform(action: spec.id, item: item) { [weak self] problem in
            guard let self else { return }
            self.busy.remove(key)
            self.actionInFlight = !self.busy.isEmpty
            Trace.log("action \(provider).\(spec.id)\(item.map { "/" + $0 } ?? "") -> " +
                      (problem ?? "ok"))
            self.settle(problem, provider: provider, spec: spec, item: item)
        }
    }

    private func settle(_ problem: String?, provider: String, spec: ActionSpec, item: String?) {
        if let problem { actionError = problem; return }
        if let item, spec.retiresItem { retire(provider: provider, item: item) }
    }

    private func retire(provider: String, item: String) {
        let retiredItem = RetiredItem(provider: provider, item: item)
        let deadline = Date() + Self.retirementBudget
        retired.retire(retiredItem, until: deadline)
        revision &+= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retirementBudget) { [weak self] in
            MainActor.assumeIsolated { self?.release(retiredItem, at: deadline) }
        }
    }

    private func release(_ item: RetiredItem, at deadline: Date) {
        if retired.release(item, at: deadline) { revision &+= 1 }
    }

    private func sweepRetired(provider: String, report: Report?) {
        guard let report else { return }
        retired.restore(provider: provider, items: Set(report.items?.map(\.id) ?? []))
    }

    private func retiredItems(of provider: String) -> Set<String> {
        retired.retiredItems(of: provider, at: Date())
    }

    private static func busyKey(_ p: String, _ a: String, _ i: String?) -> String {
        "\(p)\u{1}\(a)\u{1}\(i ?? "")"
    }

    func setDisabled(_ name: String, _ disabled: Bool) {
        var names = disabledNames
        if disabled { names.insert(name) } else { names.remove(name) }
        do {
            try DisabledConfig.write(names.sorted())
        } catch let error as DisabledConfig.WriteError {
            configNotice = .notice(error.errorDescription ?? "config.json is malformed")
            return
        } catch {
            actionError = "could not update config.json: \(error.localizedDescription)"
            return
        }
        rescan()
    }

    func stopAll() {
        rescanTimer?.invalidate()
        for r in runners.values { r.stop() }
        let liveChildren = ChildRegistry.beginShutdown()
        runners.removeAll()
        ChildShutdown.terminateAll(liveChildren, budget: ChildShutdown.gracePeriod)
    }

    func recoverFromWake() {
        rescan()
        for r in runners.values { r.recoverFromWake() }
    }
}

enum ShutdownSignal {
    private static var sources: [DispatchSourceSignal] = []

    static func install() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                MainActor.assumeIsolated { Monitor.current?.stopAll() }
                exit(0)
            }
            src.resume()
            sources.append(src)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let wsnc = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [NSWorkspace.didWakeNotification,
                                           NSWorkspace.screensDidWakeNotification] {
            wsnc.addObserver(self, selector: #selector(handleWake), name: name, object: nil)
        }
    }

    @objc private func handleWake(_ notification: Notification) {
        Trace.log("system wake (\(notification.name.rawValue)) — recovering providers")
        MainActor.assumeIsolated { Monitor.current?.recoverFromWake() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Monitor.current?.stopAll() }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var icon: IconModel

    private func template(_ name: String) -> NSImage? {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size)
        for suffix in ["", "@2x", "@3x"] {
            guard let url = Bundle.main.url(forResource: name + suffix, withExtension: "png",
                                            subdirectory: "menubar"),
                  let rep = NSImageRep(contentsOf: url) else { continue }
            rep.size = size
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }

    var body: some View {
        Group {
            if let image = template(icon.state.menuBarTemplate) {
                Image(nsImage: image)
            } else {
                Image(systemName: Icon.systemName(icon.state.menuBarSymbol))
                    .renderingMode(.template)
            }
        }
        .accessibilityLabel("Maester — \(icon.state.spoken)")
    }
}

struct MaesterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate: AppDelegate
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            MenuBarLabel(icon: monitor.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

ShutdownSignal.install()

if CommandLine.arguments.contains("--providers") {
    ProvidersDiagnostic.printAndExit()
}

if let idx = CommandLine.arguments.firstIndex(of: "--enable") {
    let name = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    EnableDisableDiagnostic.printAndExit(enable: true, name: name)
}

if let idx = CommandLine.arguments.firstIndex(of: "--icon-check") {
    let name = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    IconCheckDiagnostic.printAndExit(name: name)
}

if let idx = CommandLine.arguments.firstIndex(of: "--symbol-check") {
    let symbol = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    SymbolCheckDiagnostic.printAndExit(symbol: symbol)
}

if CommandLine.arguments.contains("--layout-check") {
    LayoutCheckDiagnostic.printAndExit()
}

if CommandLine.arguments.contains("--frame-check") {
    FrameCheckDiagnostic.printAndExit()
}

if CommandLine.arguments.contains("--notice-check") {
    NoticeCheckDiagnostic.printAndExit()
}

if CommandLine.arguments.contains("--density-check") {
    DensityCheckDiagnostic.printAndExit()
}

if CommandLine.arguments.contains("--permission-check") {
    PermissionCheckDiagnostic.printAndExit()
}

if let idx = CommandLine.arguments.firstIndex(of: "--exec-check") {
    let path = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    ExecCheckDiagnostic.printAndExit(path: path)
}

if let idx = CommandLine.arguments.firstIndex(of: "--refresh-check") {
    let path = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    RefreshCheckDiagnostic.printAndExit(path: path)
}

if let idx = CommandLine.arguments.firstIndex(of: "--action-check") {
    let path = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    ActionCheckDiagnostic.printAndExit(path: path)
}

if CommandLine.arguments.contains("--retirement-check") {
    RetirementCheckDiagnostic.printAndExit()
}

if let idx = CommandLine.arguments.firstIndex(of: "--report-check") {
    let report = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    ReportCheckDiagnostic.printAndExit(report: report)
}

if let idx = CommandLine.arguments.firstIndex(of: "--disable") {
    let name = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : nil
    EnableDisableDiagnostic.printAndExit(enable: false, name: name)
}

if let raw = ProcessInfo.processInfo.environment["MAESTER_APPEARANCE"] {
    switch raw {
    case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
    case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    default: break
    }
}

MaesterApp.main()
