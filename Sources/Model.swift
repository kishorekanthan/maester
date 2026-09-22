import Foundation

enum HealthState: String, Codable, Comparable {
    case ok, off, warn, error

    var rank: Int {
        switch self {
        case .ok: return 0
        case .off: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    static func < (a: HealthState, b: HealthState) -> Bool { a.rank < b.rank }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HealthState(rawValue: raw) ?? .error
    }
}

struct MetricSpec: Codable, Identifiable, Equatable {
    let id: String
    let label: String?
    let value: Double?
    let unit: String?
    let pct: Double?
    let text: String?

    var formattedNumber: String? {
        guard let v = value else { return nil }
        if abs(v) >= 1000 { return String(format: "%.0f", v) }
        if abs(v) >= 100 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    var display: String {
        if let t = text { return t }
        guard let n = formattedNumber else { return "—" }
        return unit.map { "\(n) \($0)" } ?? n
    }

    var isNumeric: Bool { value != nil }
}

struct ActionSpec: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let terminal: Bool?
    let removes: Bool?

    var retiresItem: Bool { removes ?? false }
}

struct LineSpec: Codable, Equatable {
    let label: String
    let value: String?
    let state: HealthState?
}

struct ItemSpec: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String?
    let state: HealthState?
    let icon: String?
    let metrics: [MetricSpec]?
    let actions: [ActionSpec]?
}

struct Capabilities: Codable, Equatable {
    let stream: Bool?
    let refresh: Double?

    var interval: TimeInterval { min(max(refresh ?? 5, 1), 3600) }
    var streams: Bool { stream ?? false }
}

struct Report: Codable, Equatable {
    let schema: Int
    let title: String
    let state: HealthState
    let summary: String?
    let icon: String?
    let capabilities: Capabilities?
    let lines: [LineSpec]?
    let metrics: [MetricSpec]?
    let items: [ItemSpec]?
    let actions: [ActionSpec]?

    var caps: Capabilities { capabilities ?? Capabilities(stream: false, refresh: 5) }

    static func decode(_ source: String) -> Report? {
        guard let data = source.data(using: .utf8),
              let report = try? JSONDecoder().decode(Report.self, from: data),
              report.schema == 1 else { return nil }
        return report
    }

    func declares(action: String, item: String?) -> Bool {
        spec(action: action, item: item) != nil
    }

    func spec(action: String, item: String?) -> ActionSpec? {
        if let item {
            return items?.first { $0.id == item }?.actions?.first { $0.id == action }
        }
        return actions?.first { $0.id == action }
    }

    func withoutItems(_ ids: Set<String>) -> Report {
        guard let items, items.contains(where: { ids.contains($0.id) }) else { return self }
        return Report(schema: schema, title: title, state: state, summary: summary, icon: icon,
                      capabilities: capabilities, lines: lines, metrics: metrics,
                      items: items.filter { !ids.contains($0.id) }, actions: actions)
    }
}

struct ProviderMessage: Equatable {
    enum Severity { case notice, failure }
    let text: String
    let severity: Severity

    static func notice(_ t: String) -> ProviderMessage { .init(text: t, severity: .notice) }
    static func failure(_ t: String) -> ProviderMessage { .init(text: t, severity: .failure) }
}

struct ProviderState: Identifiable {
    let id: String
    var report: Report?
    var message: ProviderMessage?
    var source: String = ""
    var lastUpdate: Date?
    var disabled: Bool = false
    var refusal: String? = nil

    var state: HealthState {
        guard let message else { return report?.state ?? .off }
        if message.severity == .failure { return .error }
        return max(report?.state ?? .off, .warn)
    }

    var title: String { report?.title ?? id }
}

struct RetiredItem: Hashable {
    let provider: String
    let item: String
}

struct RetirementLedger {
    private var deadlines: [RetiredItem: Date] = [:]

    mutating func retire(_ item: RetiredItem, until deadline: Date) {
        deadlines[item] = deadline
    }

    mutating func restore(provider: String, items: Set<String>) {
        let restored = deadlines.keys.filter { $0.provider == provider && items.contains($0.item) }
        for item in restored { deadlines.removeValue(forKey: item) }
    }

    mutating func release(_ item: RetiredItem, at now: Date) -> Bool {
        guard let deadline = deadlines[item], deadline <= now else { return false }
        deadlines.removeValue(forKey: item)
        return true
    }

    mutating func retiredItems(of provider: String, at now: Date) -> Set<String> {
        let expired = deadlines.filter { $0.value <= now }.map(\.key)
        for item in expired { _ = release(item, at: now) }
        return Set(deadlines.keys.filter { $0.provider == provider }.map(\.item))
    }
}

final class MetricHistory {
    static let capacity = 60

    private var buffers: [String: [Double]] = [:]
    private var touched: Set<String> = []
    private let lock = NSLock()

    static func key(_ provider: String, _ item: String?, _ metric: String) -> String {
        "\(provider)\u{1}\(item ?? "")\u{1}\(metric)"
    }

    func absorb(provider: String, report: Report) {
        lock.lock(); defer { lock.unlock() }
        var live: Set<String> = []

        func take(_ item: String?, _ metrics: [MetricSpec]?) {
            for m in metrics ?? [] {
                guard let v = m.value else { continue }
                let k = Self.key(provider, item, m.id)
                live.insert(k)
                var buf = buffers[k] ?? []
                buf.append(v)
                if buf.count > Self.capacity { buf.removeFirst(buf.count - Self.capacity) }
                buffers[k] = buf
            }
        }
        take(nil, report.metrics)
        for it in report.items ?? [] { take(it.id, it.metrics) }

        let mine = touched.filter { $0.hasPrefix(provider + "\u{1}") }
        for k in mine where !live.contains(k) { buffers.removeValue(forKey: k) }
        touched.subtract(mine)
        touched.formUnion(live)
    }

    func series(_ provider: String, _ item: String?, _ metric: String) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        return buffers[Self.key(provider, item, metric)] ?? []
    }

    func forget(provider: String) {
        lock.lock(); defer { lock.unlock() }
        for k in buffers.keys where k.hasPrefix(provider + "\u{1}") {
            buffers.removeValue(forKey: k)
        }
        touched = touched.filter { !$0.hasPrefix(provider + "\u{1}") }
    }
}
