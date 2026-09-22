import Foundation

enum MaesterConfig {
    static let root: String = {
        if let override = ProcessInfo.processInfo.environment["MAESTER_CONFIG_DIR"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.config/maester"
    }()

    static var path: String { root + "/config.json" }
}

enum DisabledConfig {
    struct WriteError: LocalizedError {
        let path: String
        var errorDescription: String? {
            "\(path) is malformed and must be fixed or removed before it can be updated"
        }
    }

    static func readNames() -> (names: Set<String>, malformed: Bool) {
        guard let data = FileManager.default.contents(atPath: MaesterConfig.path), !data.isEmpty else {
            return ([], false)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            return ([], true)
        }
        guard let dict = obj as? [String: Any] else {
            return ([], true)
        }
        guard let raw = dict["disabled"] else {
            return ([], false)
        }
        guard let arr = raw as? [Any] else {
            return ([], true)
        }
        return (Set(arr.compactMap { $0 as? String }), false)
    }

    static func write(_ names: [String]) throws {
        try FileManager.default.createDirectory(atPath: MaesterConfig.root, withIntermediateDirectories: true)
        let path = MaesterConfig.path
        var obj: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path), !data.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let existing = json as? [String: Any] else {
                throw WriteError(path: path)
            }
            obj = existing
        }
        obj["disabled"] = names
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        let tmpPath = "\(path).tmp.\(ProcessInfo.processInfo.globallyUniqueString)"
        try data.write(to: URL(fileURLWithPath: tmpPath))
        if rename(tmpPath, path) != 0 {
            let e = errno
            try? FileManager.default.removeItem(atPath: tmpPath)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
    }
}

enum DensityConfig {
    static func read() -> Density {
        guard let data = FileManager.default.contents(atPath: MaesterConfig.path), !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["density"] as? String else {
            return .comfortable
        }
        return Density(rawValue: raw) ?? .comfortable
    }

    static func write(_ density: Density) throws {
        try FileManager.default.createDirectory(atPath: MaesterConfig.root, withIntermediateDirectories: true)
        let path = MaesterConfig.path
        var obj: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path), !data.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let existing = json as? [String: Any] else {
                throw DisabledConfig.WriteError(path: path)
            }
            obj = existing
        }
        obj["density"] = density.rawValue
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        let tmpPath = "\(path).tmp.\(ProcessInfo.processInfo.globallyUniqueString)"
        try data.write(to: URL(fileURLWithPath: tmpPath))
        if rename(tmpPath, path) != 0 {
            let e = errno
            try? FileManager.default.removeItem(atPath: tmpPath)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
    }
}

enum EnableDisableDiagnostic {
    static func printAndExit(enable: Bool, name: String?) -> Never {
        guard let name, !name.isEmpty else {
            FileHandle.standardError.write(Data("maester: --\(enable ? "enable" : "disable") requires a provider name\n".utf8))
            exit(1)
        }
        var names = DisabledConfig.readNames().names
        if enable {
            names.remove(name)
        } else {
            names.insert(name)
        }
        do {
            try DisabledConfig.write(names.sorted())
        } catch {
            FileHandle.standardError.write(Data("maester: could not update config.json: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}

enum ProvidersDiagnostic {
    private struct Entry: Codable {
        let name: String
        let enabled: Bool
        let reason: String?
        let detail: String?
    }

    static func printAndExit() -> Never {
        let result = ProviderDiscovery.list()
        let entries = result.providers.map { p -> Entry in
            if let refusal = p.refusal {
                return Entry(name: p.name, enabled: false, reason: "refused", detail: refusal)
            }
            if p.disabled {
                return Entry(name: p.name, enabled: false, reason: "disabled", detail: nil)
            }
            return Entry(name: p.name, enabled: true, reason: "default", detail: nil)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries), let s = String(data: data, encoding: .utf8) {
            print(s)
        } else {
            print("[]")
        }
        exit(0)
    }
}

enum IconCheckDiagnostic {
    private struct Entry: Codable {
        let name: String
        let icon: String?
        let resolved: Bool
    }

    static func printAndExit(name: String?) -> Never {
        guard let name, !name.isEmpty else {
            FileHandle.standardError.write(Data("maester: --icon-check requires a provider name\n".utf8))
            exit(1)
        }
        guard let provider = ProviderDiscovery.list().providers.first(where: { $0.name == name }) else {
            FileHandle.standardError.write(Data("maester: no provider named \(name)\n".utf8))
            exit(1)
        }
        let outcome = ProviderExec.run(path: provider.path, args: ["status"], timeout: 4)
        guard let data = outcome.stdout.data(using: .utf8),
              let report = try? JSONDecoder().decode(Report.self, from: data) else {
            FileHandle.standardError.write(Data("maester: could not read a status report from \(name)\n".utf8))
            exit(1)
        }
        let resolved: Bool
        if let sf = Icon.symbol(report.icon) {
            resolved = Icon.systemSymbolAvailable(sf)
        } else if report.icon != nil {
            resolved = Icon.image(report.icon) != nil
        } else {
            resolved = false
        }
        let entry = Entry(name: name, icon: report.icon, resolved: resolved)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum SymbolCheckDiagnostic {
    private struct Entry: Codable {
        let symbol: String
        let resolved: Bool
    }

    static func printAndExit(symbol: String?) -> Never {
        guard let symbol, !symbol.isEmpty else {
            FileHandle.standardError.write(Data("maester: --symbol-check requires a symbol name\n".utf8))
            exit(1)
        }
        let entry = Entry(symbol: symbol, resolved: Icon.systemSymbolAvailable(symbol))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum LayoutCheckDiagnostic {
    private struct Entry: Codable {
        let columns: Int
        let panelWidth: Double
        let panelHeight: Double
    }

    private static func flag(_ name: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return CommandLine.arguments[idx + 1]
    }

    static func printAndExit() -> Never {
        guard let width = flag("--width").flatMap(Double.init),
              let visibleHeight = flag("--visible-height").flatMap(Double.init),
              let providers = flag("--provider-count").flatMap(Int.init) else {
            FileHandle.standardError.write(Data(
                "maester: --layout-check requires --width, --visible-height and --provider-count\n".utf8))
            exit(1)
        }
        let cols = PanelLayoutMath.columns(providers: providers, screenWidth: CGFloat(width))
        let contentWidth = PanelLayoutMath.contentWidth(columns: cols, screenWidth: CGFloat(width))
        let panelWidth = contentWidth + 2 * PanelLayout.screenInset
        let panelHeight = PanelLayoutMath.panelHeight(contentHeight: .greatestFiniteMagnitude,
                                                       screenHeight: CGFloat(visibleHeight))
        let entry = Entry(columns: cols, panelWidth: Double(panelWidth), panelHeight: Double(panelHeight))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum NoticeCheckDiagnostic {
    private struct Entry: Codable {
        let kind: String?
    }

    private static func boolFlag(_ name: String) -> Bool? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        switch CommandLine.arguments[idx + 1] {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    static func printAndExit() -> Never {
        guard let hasReport = boolFlag("--has-report"),
              let hasMessage = boolFlag("--has-message"),
              let messageIsFailure = boolFlag("--message-is-failure"),
              let reportStateIsOff = boolFlag("--report-state-off"),
              let reportIsEmpty = boolFlag("--report-is-empty") else {
            let msg = "maester: --notice-check requires --has-report --has-message " +
                "--message-is-failure --report-state-off --report-is-empty, each true|false\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
        let kind = NoticeKind.forSection(hasReport: hasReport, hasMessage: hasMessage,
                                          messageIsFailure: messageIsFailure,
                                          reportStateIsOff: reportStateIsOff,
                                          reportIsEmpty: reportIsEmpty)
        let name: String?
        switch kind {
        case .empty: name = "empty"
        case .loading: name = "loading"
        case .error: name = "error"
        case .timedOut: name = "timedOut"
        case nil: name = nil
        }
        let entry = Entry(kind: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum DensityCheckDiagnostic {
    private struct Entry: Codable {
        let density: String
    }

    private static func flag(_ name: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return CommandLine.arguments[idx + 1]
    }

    static func printAndExit() -> Never {
        if let raw = flag("--set") {
            guard let density = Density(rawValue: raw) else {
                FileHandle.standardError.write(Data("maester: --set requires compact|comfortable\n".utf8))
                exit(1)
            }
            do {
                try DensityConfig.write(density)
            } catch {
                FileHandle.standardError.write(Data("maester: could not update config.json: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        let entry = Entry(density: DensityConfig.read().rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum PermissionCheckDiagnostic {
    private struct Entry: Codable {
        let path: String
        let refused: Bool
        let reason: String?
    }

    private static func flag(_ name: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return CommandLine.arguments[idx + 1]
    }

    static func printAndExit() -> Never {
        guard let path = flag("--path"), !path.isEmpty else {
            FileHandle.standardError.write(Data("maester: --permission-check requires --path\n".utf8))
            exit(1)
        }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let parent = (resolved as NSString).deletingLastPathComponent
        let reason = OwnershipCheck.refusal(path: parent, what: "directory")
            ?? OwnershipCheck.refusal(path: resolved, what: "path")
        let entry = Entry(path: path, refused: reason != nil, reason: reason)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

final class ReportCounter {
    private let lock = NSLock()
    private var count = 0

    func bump() { lock.lock(); count += 1; lock.unlock() }

    var value: Int { lock.lock(); defer { lock.unlock() }; return count }

    func waitFor(atLeast target: Int, within seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while value < target, Date() < deadline { usleep(50_000) }
    }
}

enum DiagnosticOutput {
    static func emit<T: Encodable>(_ entry: T) -> Never {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }

    static func requirePath(_ path: String?, flag: String) -> String {
        guard let path, !path.isEmpty else {
            FileHandle.standardError.write(Data("maester: \(flag) requires a provider path\n".utf8))
            exit(1)
        }
        return path
    }

    static func countingRunner(path: String, counter: ReportCounter) -> ProviderRunner {
        ProviderRunner(name: "fixture", path: path) { _, report, _, _ in
            if report != nil { counter.bump() }
        }
    }
}

enum ExecCheckDiagnostic {
    private struct Entry: Codable {
        let code: Int
        let timedOut: Bool
        let stdoutBytes: Int
        let stderrBytes: Int
    }

    static func printAndExit(path: String?) -> Never {
        let path = DiagnosticOutput.requirePath(path, flag: "--exec-check")
        let r = ProviderExec.run(path: path, args: ["status"], timeout: 4)
        DiagnosticOutput.emit(Entry(code: Int(r.code), timedOut: r.timedOut,
                                    stdoutBytes: r.stdout.utf8.count,
                                    stderrBytes: r.stderr.utf8.count))
    }
}

enum RefreshCheckDiagnostic {
    private struct Entry: Codable {
        let beforeRefresh: Int
        let afterRefresh: Int
    }

    static func printAndExit(path: String?) -> Never {
        let path = DiagnosticOutput.requirePath(path, flag: "--refresh-check")
        let counter = ReportCounter()
        let runner = DiagnosticOutput.countingRunner(path: path, counter: counter)
        runner.start()
        counter.waitFor(atLeast: 2, within: 8)
        let before = counter.value
        runner.refreshNow()
        counter.waitFor(atLeast: before + 1, within: 8)
        let after = counter.value
        runner.stop()
        DiagnosticOutput.emit(Entry(beforeRefresh: before, afterRefresh: after))
    }
}

enum ActionCheckDiagnostic {
    private struct Entry: Codable {
        let problem: String?
    }

    static func printAndExit(path: String?) -> Never {
        let path = DiagnosticOutput.requirePath(path, flag: "--action-check")
        let counter = ReportCounter()
        let runner = DiagnosticOutput.countingRunner(path: path, counter: counter)
        runner.start()
        counter.waitFor(atLeast: 2, within: 8)
        let box = ProblemBox()
        runner.perform(action: "doit", item: nil) { box.settle($0) }
        box.waitForSettled(within: 10)
        runner.stop()
        DiagnosticOutput.emit(Entry(problem: box.problem))
    }
}

final class ProblemBox {
    private let lock = NSLock()
    private var settled = false
    private var value: String?

    func settle(_ problem: String?) {
        lock.lock(); value = problem; settled = true; lock.unlock()
    }

    var problem: String? { lock.lock(); defer { lock.unlock() }; return value }

    var isSettled: Bool { lock.lock(); defer { lock.unlock() }; return settled }

    func waitForSettled(within seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while !isSettled, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}

enum RetirementCheckDiagnostic {
    private struct Entry: Codable {
        let hiddenAfterAction: Bool
        let hiddenAfterLiveReport: Bool
        let hiddenAfterDeadline: Bool
    }

    static func printAndExit() -> Never {
        let item = RetiredItem(provider: "fixture", item: "item")
        let now = Date()
        var ledger = RetirementLedger()
        ledger.retire(item, until: now.addingTimeInterval(8))
        let hiddenAfterAction = ledger.retiredItems(of: item.provider, at: now).contains(item.item)
        ledger.restore(provider: item.provider, items: [item.item])
        let hiddenAfterLiveReport = ledger.retiredItems(of: item.provider, at: now).contains(item.item)
        ledger.retire(item, until: now.addingTimeInterval(8))
        let hiddenAfterDeadline = ledger.retiredItems(of: item.provider,
                                                      at: now.addingTimeInterval(8)).contains(item.item)
        let entry = Entry(hiddenAfterAction: hiddenAfterAction,
                          hiddenAfterLiveReport: hiddenAfterLiveReport,
                          hiddenAfterDeadline: hiddenAfterDeadline)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum ReportCheckDiagnostic {
    private struct Entry: Codable {
        let accepted: Bool
    }

    static func printAndExit(report: String?) -> Never {
        guard let report else {
            FileHandle.standardError.write(Data("maester: --report-check requires a JSON report\n".utf8))
            exit(1)
        }
        let entry = Entry(accepted: Report.decode(report) != nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}

enum FrameCheckDiagnostic {
    private struct Entry: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    private static func flag(_ name: String) -> Double? {
        guard let idx = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(idx + 1) else { return nil }
        return Double(CommandLine.arguments[idx + 1])
    }

    static func printAndExit() -> Never {
        guard let cx = flag("--cur-x"), let cy = flag("--cur-y"),
              let cw = flag("--cur-width"), let ch = flag("--cur-height"),
              let targetWidth = flag("--target-width"),
              let vx = flag("--visible-x"), let vy = flag("--visible-y"),
              let vw = flag("--visible-width"), let vh = flag("--visible-height") else {
            let msg = "maester: --frame-check requires --cur-x --cur-y --cur-width --cur-height " +
                "--target-width --visible-x --visible-y --visible-width --visible-height\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(1)
        }
        let current = CGRect(x: cx, y: cy, width: cw, height: ch)
        let visible = CGRect(x: vx, y: vy, width: vw, height: vh)
        let corrected = PanelLayoutMath.clampedFrame(current: current,
                                                       targetWidth: CGFloat(targetWidth),
                                                       visible: visible)
        let entry = Entry(x: Double(corrected.origin.x), y: Double(corrected.origin.y),
                           width: Double(corrected.width), height: Double(corrected.height))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entry), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
        exit(0)
    }
}
