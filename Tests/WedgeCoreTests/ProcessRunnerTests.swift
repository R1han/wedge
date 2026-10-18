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
        await #expect(throws: WedgeError.self) {
            try await ProcessRunner().run(URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: .seconds(1))
        }
    }

    @Test func run_largeOutputDoesNotDeadlock() async throws {
        let out = try await ProcessRunner().run(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "head -c 1000000 /dev/zero"])
        #expect(out.stdout.count == 1_000_000)
    }
}
