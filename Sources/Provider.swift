import Foundation

private let spawnSetsid: Int16 = 0x0400

enum ChildRegistry {
    private static let lock = NSLock()
    private static var children: [ObjectIdentifier: Child] = [:]
    private static var shuttingDown = false
    private static var pendingSpawns = 0

    static func beginSpawn() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !shuttingDown else { return false }
        pendingSpawns += 1
        return true
    }

    static func completeSpawn(_ child: Child?) {
        lock.lock(); defer { lock.unlock() }
        if let child { children[ObjectIdentifier(child)] = child }
        pendingSpawns -= 1
    }

    static func unregister(_ child: Child) {
        lock.lock(); defer { lock.unlock() }
        children.removeValue(forKey: ObjectIdentifier(child))
    }

    static func beginShutdown() -> [Child] {
        lock.lock()
        shuttingDown = true
        while pendingSpawns > 0 {
            lock.unlock()
            usleep(500)
            lock.lock()
        }
        let snap = Array(children.values)
        lock.unlock()
        return snap
    }
}

final class Child {
    let pid: pid_t
    let outFD: Int32
    let errFD: Int32
    private var reaped = false
    private var exitStatus: Int32 = -1
    private let lock = NSLock()
    private let waitLock = NSLock()

    enum SpawnError: Error, CustomStringConvertible {
        case shuttingDown, pipeFailed(Int32), setupFailed(Int32), spawnFailed(Int32)
        var description: String {
            switch self {
            case .shuttingDown:       return "app is shutting down"
            case .pipeFailed(let e):  return "could not create a pipe: \(Self.reason(e))"
            case .setupFailed(let e): return "could not configure the spawn: \(Self.reason(e))"
            case .spawnFailed(let e): return Self.reason(e)
            }
        }
        private static func reason(_ e: Int32) -> String { String(cString: strerror(e)) }
    }

    init(path: String, args: [String], environment: [String: String]) throws {
        guard ChildRegistry.beginSpawn() else { throw SpawnError.shuttingDown }
        var spawnSucceeded = false
        defer { if !spawnSucceeded { ChildRegistry.completeSpawn(nil) } }
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { throw SpawnError.pipeFailed(errno) }
        guard pipe(&errPipe) == 0 else {
            let e = errno
            close(outPipe[0]); close(outPipe[1])
            throw SpawnError.pipeFailed(e)
        }
        func closeAllPipes() {
            close(outPipe[0]); close(outPipe[1]); close(errPipe[0]); close(errPipe[1])
        }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            closeAllPipes(); throw SpawnError.setupFailed(errno)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else {
            closeAllPipes(); throw SpawnError.setupFailed(errno)
        }
        defer { posix_spawnattr_destroy(&attr) }

        var setup: Int32 = 0
        func step(_ result: Int32) { if setup == 0 { setup = result } }
        step(posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0))
        step(posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1))
        step(posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2))
        step(posix_spawn_file_actions_addclose(&actions, outPipe[0]))
        step(posix_spawn_file_actions_addclose(&actions, errPipe[0]))
        step(posix_spawn_file_actions_addclose(&actions, outPipe[1]))
        step(posix_spawn_file_actions_addclose(&actions, errPipe[1]))
        step(posix_spawnattr_setflags(&attr, spawnSetsid))
        guard setup == 0 else { closeAllPipes(); throw SpawnError.setupFailed(setup) }

        var argv: [UnsafeMutablePointer<CChar>?] = ([path] + args).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            for p in argv where p != nil { free(p) }
            for p in envp where p != nil { free(p) }
        }

        var newPid: pid_t = 0
        let rc = posix_spawn(&newPid, path, &actions, &attr, &argv, &envp)
        close(outPipe[1]); close(errPipe[1])
        guard rc == 0 else {
            close(outPipe[0]); close(errPipe[0])
            throw SpawnError.spawnFailed(rc)
        }
        pid = newPid
        outFD = outPipe[0]
        errFD = errPipe[0]
        spawnSucceeded = true
        ChildRegistry.completeSpawn(self)
    }

    func terminate() {
        killpg(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [self] in
            lock.lock(); let gone = reaped; lock.unlock()
            if !gone { killpg(pid, SIGKILL) }
        }
    }

    func kill() {
        lock.lock(); let gone = reaped; lock.unlock()
        if !gone { killpg(pid, SIGKILL) }
    }

    var isReaped: Bool { lock.lock(); defer { lock.unlock() }; return reaped }

    @discardableResult
    func wait() -> Int32 {
        waitLock.lock(); defer { waitLock.unlock() }
        lock.lock()
        if reaped { let s = exitStatus; lock.unlock(); return s }
        lock.unlock()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        lock.lock(); reaped = true; exitStatus = code; lock.unlock()
        ChildRegistry.unregister(self)
        return code
    }

    func closePipes() {
        if outFD >= 0 { close(outFD) }
        if errFD >= 0 { close(errFD) }
    }
}

enum ProviderLimits {
    static let outputCap = 1 << 20
}

private func capOverflow(_ data: inout Data, cap: Int, onOverflow: () -> Void) -> Bool {
    guard data.count > cap else { return false }
    data.removeLast(data.count - cap)
    onOverflow()
    return true
}

private func readCapped(_ fd: Int32, cap: Int, onOverflow: () -> Void) -> (data: Data, truncated: Bool) {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 16384)
    var truncated = false
    while true {
        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, 16384) }
        if n <= 0 { break }
        if truncated { continue }
        data.append(contentsOf: buf[0..<n])
        truncated = capOverflow(&data, cap: cap, onOverflow: onOverflow)
    }
    return (data, truncated)
}

private func drain(_ fd: Int32, cap: Int = ProviderLimits.outputCap,
                   onOverflow: () -> Void = {}) -> String {
    let (data, truncated) = readCapped(fd, cap: cap, onOverflow: onOverflow)
    let text = String(decoding: data, as: UTF8.self)
    if truncated {
        return text + "\n[output stopped: the provider wrote more than \(cap) bytes]"
    }
    return text
}

enum ProviderEnvironment {
    static let value: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let wanted = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
                      "\(home)/.local/bin", "\(home)/.orbstack/bin",
                      "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var parts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in wanted where !parts.contains(p) { parts.append(p) }
        env["PATH"] = parts.joined(separator: ":")
        env["HOME"] = home
        env["MAESTER"] = "1"
        return env
    }()
}

struct DiscoveredProvider {
    let name: String
    let path: String
    let refusal: String?
    let disabled: Bool
    var live: Bool { !disabled }
}

struct ProviderDiscoveryResult {
    let providers: [DiscoveredProvider]
    let configNotice: String?
}

enum OwnershipCheck {
    static func refusal(path p: String, what: String) -> String? {
        var st = stat()
        guard stat(p, &st) == 0 else { return "cannot stat \(what) \(p)" }
        if st.st_uid != getuid() { return "\(what) is not owned by you (uid \(st.st_uid))" }
        if st.st_mode & UInt16(S_IWGRP | S_IWOTH) != 0 {
            return String(format: "%@ is group/world-writable (%03o)", what,
                          Int(st.st_mode) & 0o777)
        }
        return nil
    }
}

enum ProviderDiscovery {
    static let directory = MaesterConfig.root + "/providers"

    static func refusal(for path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let resolvedDirectory = (resolved as NSString).deletingLastPathComponent

        var checks = [(directory, "install directory"), (resolved, "provider")]
        if resolvedDirectory != directory {
            checks.append((resolvedDirectory, "source directory"))
        }

        for (p, what) in checks {
            if let refusal = OwnershipCheck.refusal(path: p, what: what) { return refusal }
        }
        if access(resolved, X_OK) != 0 { return "not executable" }
        return nil
    }

    static func isBackupArtefact(_ name: String) -> Bool {
        if name.hasSuffix("~") { return true }
        let suffixes = [".bak", ".old", ".orig", ".save", ".swp", ".tmp", ".rej", ".dpkg-old"]
        let lower = name.lowercased()
        return suffixes.contains { lower.hasSuffix($0) }
    }

    static func list() -> ProviderDiscoveryResult {
        let fm = FileManager.default
        let (disabledNames, malformed) = DisabledConfig.readNames()
        let notice = malformed ? "config.json could not be parsed — nothing disabled" : nil

        guard let names = try? fm.contentsOfDirectory(atPath: directory) else {
            return ProviderDiscoveryResult(providers: [], configNotice: notice)
        }
        let providers = names.filter { !$0.hasPrefix(".") && !isBackupArtefact($0) }.sorted().map { name -> DiscoveredProvider in
            let path = directory + "/" + name
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: path, isDirectory: &isDir)
            let isDisabled = disabledNames.contains(name)
            if isDir.boolValue {
                return DiscoveredProvider(name: name, path: path, refusal: "is a directory",
                                          disabled: isDisabled)
            }
            return DiscoveredProvider(name: name, path: path, refusal: refusal(for: path),
                                      disabled: isDisabled)
        }
        return ProviderDiscoveryResult(providers: providers, configNotice: notice)
    }
}

struct ExecOutcome {
    let code: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum ProviderExec {
    static func run(path: String, args: [String], timeout: TimeInterval) -> ExecOutcome {
        let child: Child
        do {
            child = try Child(path: path, args: args, environment: ProviderEnvironment.value)
        } catch {
            return ExecOutcome(code: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        var out = "", err = ""
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { out = drain(child.outFD, onOverflow: { child.kill() }); group.leave() }
        group.enter()
        DispatchQueue.global().async { err = drain(child.errFD, onOverflow: { child.kill() }); group.leave() }

        let done = DispatchSemaphore(value: 0)
        var code: Int32 = -1
        DispatchQueue.global().async { code = child.wait(); done.signal() }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            child.kill()
            _ = done.wait(timeout: .now() + 2)
            _ = group.wait(timeout: .now() + 2)
            child.closePipes()
            return ExecOutcome(code: -1, stdout: "", stderr: "", timedOut: true)
        }
        _ = group.wait(timeout: .now() + 2)
        child.closePipes()
        return ExecOutcome(code: code, stdout: out, stderr: err, timedOut: false)
    }
}

final class StreamReader {
    let child: Child
    private var stopped = false
    private let lock = NSLock()

    init(child: Child, onLine: @escaping (String) -> Void, onEnd: @escaping (Int32, String) -> Void) {
        self.child = child
        let fd = child.outFD
        let errFD = child.errFD

        var stderrText = ""
        let errGroup = DispatchGroup()
        errGroup.enter()
        let spawned = child
        DispatchQueue.global().async {
            stderrText = drain(errFD, onOverflow: { spawned.terminate() })
            errGroup.leave()
        }

        let child = self.child
        Thread.detachNewThread { [weak self, child] in
            let stdoutStopped = Self.readLines(fd: fd, child: child, onLine: onLine)
            let code = child.wait()
            _ = errGroup.wait(timeout: .now() + 1)
            child.closePipes()
            let detail = Self.outputDetail(stderrText, stopped: stdoutStopped)
            if !(self?.isStopped ?? true) { onEnd(code, detail) }
        }
    }

    private static func readLines(fd: Int32, child: Child, onLine: @escaping (String) -> Void) -> Bool {
        var pending = Data()
        while let chunk = readChunk(fd) {
            pending.append(chunk)
            if capOverflow(&pending, cap: ProviderLimits.outputCap, onOverflow: { child.kill() }) {
                return true
            }
            publishLines(&pending, onLine: onLine)
        }
        return false
    }

    private static func readChunk(_ fd: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, 65536) }
        guard count > 0 else { return nil }
        return Data(buffer[0..<count])
    }

    private static func publishLines(_ pending: inout Data, onLine: @escaping (String) -> Void) {
        while let newline = pending.firstIndex(of: 0x0a) {
            let lineData = pending[pending.startIndex..<newline]
            pending = pending[(newline + 1)...]
            if let line = String(data: lineData, encoding: .utf8),
               !line.trimmingCharacters(in: .whitespaces).isEmpty {
                onLine(line)
            }
        }
    }

    private static func outputDetail(_ stderr: String, stopped: Bool) -> String {
        guard stopped else { return stderr }
        return stderr + "\n[output stopped: the provider wrote more than \(ProviderLimits.outputCap) bytes]"
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        child.terminate()
    }

    func forceRestart() {
        child.terminate()
    }
}

enum ChildShutdown {
    static let gracePeriod: TimeInterval = 0.2

    static func terminateAll(_ children: [Child], budget: TimeInterval) {
        guard !children.isEmpty else { return }
        for child in children { killpg(child.pid, SIGTERM) }

        let group = DispatchGroup()
        for child in children {
            group.enter()
            DispatchQueue.global().async { _ = child.wait(); group.leave() }
        }
        if group.wait(timeout: .now() + budget) == .timedOut {
            for child in children where !child.isReaped { killpg(child.pid, SIGKILL) }
            _ = group.wait(timeout: .now() + 2)
        }
    }
}
