import Foundation

/// Runs command-line tools the way a Terminal would: with Homebrew, .NET and the Python
/// environment on PATH (a Finder-started app only gets /usr/bin:/bin).
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
        var trimmed: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The login shell's PATH plus the usual tool folders, computed once.
    static let searchPath: String = {
        let home = NSHomeDirectory()
        var parts: [String] = []
        let login = run("/bin/zsh", ["-l", "-c", "printf %s \"$PATH\""],
                        env: ["HOME": home, "USER": NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
                        timeout: 8)
        if login.ok { parts += login.output.split(separator: ":").map(String.init) }
        parts += ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/share/dotnet",
                  home + "/.dotnet", home + "/.dotnet/tools", home + "/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }()

    /// The environment for tools; with `python`, its environment's bin folder comes first, as
    /// activating it (or `uv run`) would.
    static func environment(python: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var path = searchPath
        if let python {
            let bin = python.deletingLastPathComponent
            env["VIRTUAL_ENV"] = bin.deletingLastPathComponent
            path = bin + ":" + path
        }
        env["PATH"] = path
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONHOME"] = nil
        env["PYTHONPATH"] = nil
        return env
    }

    /// Runs a tool to the end and returns its exit status with stdout and stderr together. Blocking.
    static func run(_ exe: String, _ args: [String], cwd: String? = nil,
                    env: [String: String]? = nil, timeout: TimeInterval = 120) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        p.environment = env ?? environment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Result(status: -1, output: error.localizedDescription) }

        // Read on another thread so a full pipe can never block the tool.
        let reader = pipe.fileHandleForReading
        let box = DataBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = reader.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
        }
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: box.data, as: UTF8.self))
    }

    static func runAsync(_ exe: String, _ args: [String], cwd: String? = nil,
                         env: [String: String]? = nil, timeout: TimeInterval = 120) async -> Result {
        await Task.detached { run(exe, args, cwd: cwd, env: env, timeout: timeout) }.value
    }

    /// Finds a tool on the search path, like `command -v`.
    static func which(_ tool: String) -> String? {
        for dir in searchPath.split(separator: ":") {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Each line of a pipe as soon as it is written; a carriage return (git's progress) also ends
    /// a line. (`FileHandle.bytes` held lines back until its buffer filled.)
    static func readLines(_ handle: FileHandle, _ onLine: @Sendable (String) async -> Void) async {
        let lines = AsyncStream<String> { cont in
            let splitter = LineSplitter()
            handle.readabilityHandler = { h in
                let data = h.availableData
                if data.isEmpty {   // end of file: the tool and its children have closed the pipe
                    h.readabilityHandler = nil
                    if let rest = splitter.flush() { cont.yield(rest) }
                    cont.finish()
                    return
                }
                for line in splitter.feed(data) { cont.yield(line) }
            }
        }
        for await line in lines { await onLine(line) }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Splits a byte stream into lines. Used only from one handle's readability handler,
/// whose calls never overlap.
final class LineSplitter: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let end = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = buffer[buffer.startIndex..<end]
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
            buffer.removeSubrange(buffer.startIndex...end)
        }
        return lines
    }

    func flush() -> String? {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    }
}

extension String {
    /// `/Users/me/Games` → `~/Games`, for display.
    var tildePath: String { (self as NSString).abbreviatingWithTildeInPath }
    var lastPathComponent: String { (self as NSString).lastPathComponent }
    var deletingLastPathComponent: String { (self as NSString).deletingLastPathComponent }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatDuration(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
}
