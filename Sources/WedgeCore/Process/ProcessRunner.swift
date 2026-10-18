import Foundation

/// Runs an external tool from an argument array (never a shell string), capturing
/// stdout and stderr and enforcing a timeout.
public struct ProcessRunner: Sendable {
    public struct Output: Sendable {
        public let stdout: Data
        public let stderr: Data
        public let code: Int32
    }

    public init() {}

    /// Runs `executable` with `args`. A nonzero exit is returned in `Output.code`, not thrown.
    /// Throws `WedgeError.toolFailed` (code -1) on launch failure or timeout, and
    /// `WedgeError.cancelled` if the calling task is cancelled.
    public func run(
        _ executable: URL,
        _ args: [String],
        timeout: Duration = .seconds(120)
    ) async throws -> Output {
        let tool = executable.lastPathComponent
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let (exits, exitSink) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = {
            exitSink.yield($0.terminationStatus)
            exitSink.finish()
        }

        do {
            try process.run()
        } catch {
            throw WedgeError.toolFailed(
                tool: tool, code: -1, message: "failed to launch: \(error.localizedDescription)")
        }

        let state = RunState(process)

        // Drain both pipes concurrently so a chatty child never blocks on a full pipe.
        async let stdout = Self.drain(outPipe.fileHandleForReading)
        async let stderr = Self.drain(errPipe.fileHandleForReading)

        let timer = Task {
            try await Task.sleep(for: timeout)
            state.stop(timedOut: true)
        }

        let code: Int32 = await withTaskCancellationHandler {
            var status: Int32 = -1
            for await value in exits { status = value }
            return status
        } onCancel: {
            state.stop(timedOut: false)
        }
        timer.cancel()

        let (outData, errData) = await (stdout, stderr)

        if state.timedOut {
            throw WedgeError.toolFailed(
                tool: tool, code: -1, message: "timed out after \(timeout)")
        }
        if state.cancelled { throw WedgeError.cancelled }
        return Output(stdout: outData, stderr: errData, code: code)
    }

    private static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                cont.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}

/// Stops a running process (SIGTERM, then SIGKILL after a grace period) and records why.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var _timedOut = false
    private var _cancelled = false

    init(_ process: Process) { self.process = process }

    var timedOut: Bool { lock.withLock { _timedOut } }
    var cancelled: Bool { lock.withLock { _cancelled } }

    func stop(timedOut: Bool) {
        lock.withLock {
            if timedOut { _timedOut = true } else { _cancelled = true }
        }
        guard process.isRunning else { return }
        process.terminate()
        let process = self.process
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
