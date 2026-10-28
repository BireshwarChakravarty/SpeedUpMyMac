import Foundation

/// Result of running an external command.
public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var succeeded: Bool { status == 0 }
}

/// Thin wrapper around `Process`. Commands are always passed as argv arrays, never through a shell,
/// unless a caller explicitly asks for `/bin/sh -c` with a script it built from quoted parts.
public enum Shell {
    /// Runs `executable` with `arguments` and captures output. Returns status 127 if it cannot launch.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 120,
                           environment: [String: String]? = nil) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        // Drain pipes concurrently so a chatty command can't deadlock on a full pipe buffer.
        let outData = DataBox(), errData = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        do {
            try process.run()
        } catch {
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            group.wait()
            return ShellResult(status: 127, stdout: "", stderr: "\(executable): \(error.localizedDescription)")
        }

        let deadline = DispatchTime.now() + timeout
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { process.waitUntilExit(); finished.signal() }
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
        }
        group.wait()
        return ShellResult(status: process.terminationStatus,
                           stdout: String(decoding: outData.data, as: UTF8.self),
                           stderr: String(decoding: errData.data, as: UTF8.self))
    }

    /// Runs a command found on PATH (or common tool locations). Returns nil if the tool isn't installed.
    public static func runTool(_ name: String, _ arguments: [String] = [], timeout: TimeInterval = 120) -> ShellResult? {
        guard let path = which(name) else { return nil }
        return run(path, arguments, timeout: timeout)
    }

    /// Runs a command attached to the caller's terminal (used by the CLI for `sudo` password prompts).
    @discardableResult
    public static func runInteractive(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do { try process.run() } catch { return 127 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static let toolDirs = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin",
                                   "/usr/libexec", "/opt/homebrew/sbin"]

    /// Locates an executable on PATH plus Homebrew's prefixes (GUI apps get a minimal PATH).
    public static func which(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs.append(contentsOf: toolDirs)
        let home = Paths.home
        dirs.append(contentsOf: ["\(home)/.cargo/bin", "\(home)/go/bin", "\(home)/.local/bin", "\(home)/.bun/bin"])
        for dir in dirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// POSIX single-quote escaping for building `/bin/sh` scripts from untrusted strings.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Written by exactly one reader thread, read after `group.wait()`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
