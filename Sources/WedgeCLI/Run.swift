import ArgumentParser
import Foundation
import WedgeCore

/// Destination for CLI output. The default writes to the process streams; tests pass a
/// capturing instance.
public final class CLIOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""
    private let capture: Bool

    /// A capturing sink (nothing is written to the process streams).
    public init() { capture = true }
    private init(capture: Bool) { self.capture = capture }

    public static let standard = CLIOutput(capture: false)

    public var stdout: String { lock.withLock { out } }
    public var stderr: String { lock.withLock { err } }

    func writeOut(_ text: String) {
        if capture { lock.withLock { out += text + "\n" } } else { print(text) }
    }

    func writeErr(_ text: String) {
        if capture {
            lock.withLock { err += text + "\n" }
        } else {
            FileHandle.standardError.write(Data((text + "\n").utf8))
        }
    }
}

public enum WedgeCLI {
    /// Parses `args` (without the program name), runs the command and returns the process exit code.
    public static func run(_ args: [String], output: CLIOutput = .standard) async -> Int32 {
        do {
            let command = try RootCommand.parseAsRoot(args)
            if let convert = command as? ConvertCommand { return await convert.execute(output: output) }
            if let list = command as? ListCommand { return list.execute(output: output) }
            if var async = command as? AsyncParsableCommand { try await async.run() }
            return 0
        } catch {
            let message = RootCommand.message(for: error)
            let code = RootCommand.exitCode(for: error)
            if !message.isEmpty {
                if code == .success { output.writeOut(message) } else { output.writeErr(message) }
            }
            return code.rawValue
        }
    }

    /// A clear, single-line description of a core error for stderr.
    static func describe(_ error: Error) -> String {
        guard let error = error as? WedgeError else { return "error: \(error.localizedDescription)" }
        switch error {
        case .inputNotFound(let url): return "error: input not found: \(url.path)"
        case .unsupportedConversion(let from, let to): return "error: unsupported conversion: \(from) -> \(to)"
        case .outputExists(let url): return "error: output already exists: \(url.path) (use --force to overwrite)"
        case .resourceLimitExceeded(let detail): return "error: resource limit exceeded: \(detail)"
        case .toolFailed(let tool, let code, let message): return "error: \(tool) failed (exit \(code)): \(message)"
        case .cancelled: return "error: cancelled"
        case .invalidInput(let detail): return "error: invalid input: \(detail)"
        }
    }

    /// Exit code per error kind (usage errors raised by the parser exit 64).
    static func exitCode(for error: Error) -> Int32 {
        guard let error = error as? WedgeError else { return 1 }
        switch error {
        case .inputNotFound: return 66
        case .unsupportedConversion: return 65
        case .outputExists: return 73
        case .resourceLimitExceeded: return 69
        case .toolFailed: return 70
        case .cancelled: return 130
        case .invalidInput: return 65
        }
    }
}
