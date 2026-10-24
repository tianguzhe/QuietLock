import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let output: String

    public init(exitCode: Int32, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
}

public protocol CommandExecuting: Sendable {
    func run(executable: String, arguments: [String]) async throws -> CommandResult
}

public struct ProcessCommandExecutor: CommandExecuting {
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                // A single pipe is drained while the child runs, including its stderr.
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: CommandResult(
                        exitCode: process.terminationStatus,
                        output: String(decoding: data, as: UTF8.self)
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public protocol PowerSettingsServing: Sendable {
    func read() async throws -> PowerSnapshot
    func apply(_ preset: LockPreset) async throws
}

/// A sudoers drop-in that lets the current user run exactly the six preset `pmset` commands
/// without a password while QuietLock runs. It also allows removing itself, so quitting can
/// revoke it without another prompt.
public enum PasswordlessAccess {
    public static let path = "/etc/sudoers.d/quietlock"

    /// Returns nil for names that could change the meaning of a sudoers line
    /// (spaces, quotes, commas, `%group`, leading `-`); callers then skip installing the rule.
    public static func rule(for userName: String) -> String? {
        guard let first = userName.unicodeScalars.first,
              CharacterSet.letters.contains(first) || first == "_",
              userName.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) })
        else { return nil }
        let commands = LockPreset.allCases.map { "/usr/bin/pmset -a displaysleep \($0.rawValue)" }
            + ["/bin/rm -f \(path)"]
        return "\(userName) ALL = (root) NOPASSWD: " + commands.joined(separator: ", ")
    }
}

/// Authorization lives in memory, so every launch asks once even if a rule survived a crash.
private actor LaunchAuthorization {
    private(set) var isGranted = false
    func grant() { isGranted = true }
}

public struct SystemPowerSettingsService: PowerSettingsServing {
    private let executor: any CommandExecuting
    private let userName: String
    private let launch = LaunchAuthorization()

    public init(executor: any CommandExecuting = ProcessCommandExecutor(), userName: String = NSUserName()) {
        self.executor = executor
        self.userName = userName
    }

    public func read() async throws -> PowerSnapshot {
        let result: CommandResult
        do {
            result = try await executor.run(executable: "/usr/bin/pmset", arguments: ["-g", "custom"])
        } catch {
            throw PowerSettingsError.readFailed
        }
        guard result.exitCode == 0 else { throw PowerSettingsError.readFailed }
        return try PowerSettingsParser.parse(result.output)
    }

    public func apply(_ preset: LockPreset) async throws {
        let pmset = "/usr/bin/pmset -a displaysleep \(preset.rawValue)"
        // `-n` never prompts: it either matches the rule or fails, and we fall back to one prompt.
        if await launch.isGranted, let remembered = try? await executor.run(
            executable: "/usr/bin/sudo", arguments: ["-n"] + pmset.split(separator: " ").map(String.init)
        ), remembered.exitCode == 0 {
            return
        }
        var command = "\(pmset) || exit 1\n"
        if let rule = PasswordlessAccess.rule(for: userName) {
            // The change itself must not depend on the rule: an invalid rule is discarded by visudo.
            command += """
            q=$(/usr/bin/mktemp /tmp/quietlock.XXXXXX) || exit 0
            /usr/bin/printf '%s\\n' '\(rule)' > "$q" && /usr/sbin/visudo -cf "$q" >/dev/null && \
            /usr/bin/install -m 0440 -o root -g wheel "$q" \(PasswordlessAccess.path)
            /bin/rm -f "$q"
            exit 0
            """
        }
        try await runWithAdministratorPrompt(command,
            prompt: localized("QuietLock needs your permission once. It won't ask again until you quit.",
                               "静锁需要授权一次，本次运行期间调整熄屏时间不再询问密码。"))
        await launch.grant()
    }

    /// Removes the rule through the rule itself; never prompts. Throws `writeFailed` when sudo refuses,
    /// e.g. a rule from another user or an older build without the removal entry.
    public func revokeSessionAccess() async throws {
        let result: CommandResult
        do {
            result = try await executor.run(executable: "/usr/bin/sudo",
                                            arguments: ["-n", "/bin/rm", "-f", PasswordlessAccess.path])
        } catch {
            throw PowerSettingsError.writeFailed
        }
        guard result.exitCode == 0 else { throw PowerSettingsError.writeFailed }
    }

    /// Only commands built above from closed enums and a validated user name reach this shell.
    /// Numeric AppleScript errors are handled inside the script, independent of OS language.
    private func runWithAdministratorPrompt(_ command: String, prompt: String) async throws {
        let script = """
        on run argv
            try
                do shell script (item 2 of argv) with prompt (item 1 of argv) with administrator privileges
                return "QUIETLOCK_OK"
            on error errorMessage number errorNumber
                if errorNumber is -128 then
                    return "QUIETLOCK_CANCELLED"
                end if
                error errorMessage number errorNumber
            end try
        end run
        """
        let result: CommandResult
        do {
            result = try await executor.run(
                executable: "/usr/bin/osascript",
                arguments: ["-e", script, prompt, command]
            )
        } catch {
            throw PowerSettingsError.writeFailed
        }
        let response = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0, response == "QUIETLOCK_CANCELLED" {
            throw PowerSettingsError.authorizationCancelled
        }
        guard result.exitCode == 0, response == "QUIETLOCK_OK" else {
            throw PowerSettingsError.writeFailed
        }
    }
}
