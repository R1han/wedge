import Foundation
import Testing
@testable import WedgeCore

@Suite struct ProcessRunnerTests {
    @Test func run_capturesStdoutAndZeroExit() async throws {
        let out = try await ProcessRunner().run(URL(fileURLWithPath: "/bin/echo"), ["hi"])
        #expect(String(decoding: out.stdout, as: UTF8.self).contains("hi"))
        #expect(out.code == 0)
    }

    @Test func run_nonzeroExit() async throws {
        let out = try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "exit 3"])
        #expect(out.code == 3)
    }

    @Test func run_timeoutThrows() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await ProcessRunner().run(
                URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: .seconds(1))
            Issue.record("expected timeout to throw")
        } catch let error as WedgeError {
            guard case .toolFailed(let tool, let code, _) = error else {
                Issue.record("wrong error \(error)"); return
            }
            #expect(tool == "sleep")
            #expect(code == -1)
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func run_missingExecutableThrowsToolFailed() async {
        do {
            _ = try await ProcessRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), [])
            Issue.record("expected launch failure")
        } catch let error as WedgeError {
            guard case .toolFailed(_, let code, _) = error else {
                Issue.record("wrong error \(error)"); return
            }
            #expect(code == -1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func run_cancellationThrowsCancelledAndKillsChild() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sleep"), ["5"])
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let error as WedgeError {
            #expect(error == .cancelled)
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func run_fastCommandUnderLongTimeoutNeverTimesOut() async throws {
        for _ in 0..<20 {
            let out = try await ProcessRunner().run(
                URL(fileURLWithPath: "/bin/echo"), ["x"], timeout: .seconds(30))
            #expect(out.code == 0)
        }
    }

    @Test func run_largeOutputDoesNotDeadlock() async throws {
        let out = try await ProcessRunner().run(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "head -c 1000000 /dev/zero"])
        #expect(out.stdout.count == 1_000_000)
    }
}
