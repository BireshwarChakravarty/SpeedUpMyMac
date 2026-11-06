import AppKit
import SpruceCore

/// Runs root scripts through one compiled, in-process AppleScript instead of a new `osascript`
/// process per step. macOS remembers an administrator authorization for a few minutes within the
/// process that obtained it, so after you enter your password once, the next admin steps (another
/// clean, maintenance, a startup item, an uninstall) go through without asking again. A fresh
/// `osascript` per step was a fresh process, so it asked every single time.
///
/// With Touch ID set up for sudo (Settings → Admin access), a fingerprint replaces the password:
/// the script goes through `sudo` instead, and the password dialog only appears if Touch ID can't
/// be used right now (cancelled, lid closed).
///
/// As before, the script is handed to the handler as a parameter (never spliced into AppleScript
/// source, never written to disk), so there's no quoting to get wrong and nothing to swap.
final class AdminSession: PrivilegeRunner, @unchecked Sendable {
    static let shared = AdminSession()

    /// The system's grace period for a repeated `do shell script … with administrator privileges`.
    static let graceSeconds: TimeInterval = 5 * 60

    private let queue = DispatchQueue(label: "io.spruceapp.admin-session", qos: .userInitiated)
    private var compiled: NSAppleScript?
    private let lock = NSLock()
    private var authorizedAt: Date?

    /// True while a password entered recently should still be honoured without a new prompt.
    var isWarm: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let authorizedAt else { return false }
        return Date().timeIntervalSince(authorizedAt) < AdminSession.graceSeconds - 15
    }

    func run(_ script: PrivilegedScript, reason: String) throws -> ShellResult {
        guard Privilege.currentUserIsAdmin() else { throw PrivilegeError.notAdmin }
        guard !script.isEmpty else { return ShellResult(status: 0, stdout: "", stderr: "") }
        // One script at a time, always on the same thread: NSAppleScript isn't re-entrant.
        return try queue.sync {
            let touchIDSetUp = Tweaks.touchIDForSudoEnabled()
            if let result = TouchIDSudo.run(script, enabled: touchIDSetUp) {
                markAuthorized()
                log("Touch ID", reason: reason, detail: "ran (exit \(result.status))")
                return result
            }
            if touchIDSetUp { log("Touch ID unavailable", reason: reason, detail: TouchIDSudo.lastFailure ?? "unknown") }
            do {
                let result = try execute(script.text, prompt: "Spruce: \(reason)")
                log("Password", reason: reason, detail: "ran (exit \(result.status))")
                return result
            } catch PrivilegeError.cancelled {
                log("Password", reason: reason, detail: "cancelled")
                throw PrivilegeError.cancelled
            } catch {
                // The in-process prompt itself failed (not the script, not a wrong password): use a
                // separate osascript process, which always works but doesn't share the grace period.
                log("Password (in-process failed)", reason: reason, detail: error.localizedDescription)
                let result = try Privilege.appleScriptRunner().run(script, reason: reason)
                log("Password (osascript)", reason: reason, detail: result.succeeded ? "ran" : "failed: \(result.stderr)")
                return result
            }
        }
    }

    private var _lastAuthorization: (path: String, detail: String)?
    /// How the last admin step was authorized, and what happened.
    var lastAuthorization: (path: String, detail: String)? {
        lock.lock(); defer { lock.unlock() }
        return _lastAuthorization
    }

    /// One line per admin step in ~/Library/Logs/Spruce/admin.log, so a failure can be diagnosed.
    private func log(_ path: String, reason: String, detail: String) {
        lock.lock(); _lastAuthorization = (path, detail); lock.unlock()
        let dir = Paths.expand("~/Library/Logs/Spruce")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let file = (dir as NSString).appendingPathComponent("admin.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(path)  \(reason)  —  \(detail)\n"
        if let handle = FileHandle(forWritingAtPath: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
        }
    }

    private func execute(_ text: String, prompt: String) throws -> ShellResult {
        guard let script = prepared() else { throw PrivilegeError.failed("Couldn't prepare the administrator prompt") }

        // Call the `rootrun` handler with (script text, prompt) as parameters.
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(0x6173_6372) /* 'ascr' */,
                                           eventID: AEEventID(0x7073_6272) /* 'psbr' */,
                                           targetDescriptor: .currentProcess(),
                                           returnID: AEReturnID(-1) /* kAutoGenerateReturnID */,
                                           transactionID: AETransactionID(0) /* kAnyTransactionID */)
        event.setDescriptor(NSAppleEventDescriptor(string: "rootrun"), forKeyword: AEKeyword(0x736E_616D) /* 'snam' */)
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: text), at: 1)
        parameters.insert(NSAppleEventDescriptor(string: prompt), at: 2)
        event.setParam(parameters, forKeyword: AEKeyword(0x2D2D_2D2D) /* keyDirectObject '----' */)

        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? Int) ?? 1
            if number == -128 { throw PrivilegeError.cancelled }
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "The administrator step failed"
            // -60005/-60007: wrong password or not allowed. Other negative numbers are AppleScript or
            // Apple Event errors: the prompt mechanism failed, so the caller tries another way.
            if number == -60005 || number == -60007 { return ShellResult(status: Int32(truncatingIfNeeded: number), stdout: "", stderr: message) }
            if number < 0 { throw PrivilegeError.failed("Administrator prompt failed (\(number)): \(message)") }
            // A positive number is the shell's exit status: you authorized, the script failed.
            markAuthorized()
            return ShellResult(status: Int32(truncatingIfNeeded: number), stdout: "", stderr: message)
        }
        markAuthorized()
        return ShellResult(status: 0, stdout: result.stringValue ?? "", stderr: "")
    }

    /// For CI: calls a handler in a compiled script on this session's background queue, the same
    /// way the admin prompt does, minus the password. Returns its output or the error.
    func mechanismSelfTest() -> String {
        queue.sync {
            guard let script = NSAppleScript(source: "on plainrun(cmd)\n return do shell script cmd\nend plainrun") else { return "couldn't create" }
            var error: NSDictionary?
            guard script.compileAndReturnError(&error) else { return "couldn't compile: \(error ?? [:])" }
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(0x6173_6372), eventID: AEEventID(0x7073_6272),
                                               targetDescriptor: .currentProcess(), returnID: AEReturnID(-1),
                                               transactionID: AETransactionID(0))
            event.setDescriptor(NSAppleEventDescriptor(string: "plainrun"), forKeyword: AEKeyword(0x736E_616D))
            let parameters = NSAppleEventDescriptor.list()
            parameters.insert(NSAppleEventDescriptor(string: "echo in-process-ok"), at: 1)
            event.setParam(parameters, forKeyword: AEKeyword(0x2D2D_2D2D))
            let result = script.executeAppleEvent(event, error: &error)
            if let error { return "error \(error[NSAppleScript.errorNumber] ?? "?"): \(error[NSAppleScript.errorMessage] ?? "")" }
            return result.stringValue ?? "no output"
        }
    }

    private func prepared() -> NSAppleScript? {
        if let compiled { return compiled }
        let source = """
        on rootrun(cmd, promptText)
            return do shell script cmd with prompt promptText with administrator privileges without altering line endings
        end rootrun
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        compiled = script
        return script
    }

    private func markAuthorized() {
        lock.lock(); authorizedAt = Date(); lock.unlock()
    }
}
