import Foundation
import Testing
@testable import WedgeCore

struct MediaConverterTests {
    private static let ffmpegInstalled = ToolLocator.shared.path(for: "ffmpeg") != nil

    private let wav = FileFormat.format(forExtension: "wav")!
    private let mp3 = FileFormat.format(forExtension: "mp3")!
    private let m4a = FileFormat.format(forExtension: "m4a")!
    private let mp4 = FileFormat.format(forExtension: "mp4")!
    private let webm = FileFormat.format(forExtension: "webm")!

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaConverterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a tiny fixture with ffmpeg itself.
    private func generate(_ name: String, in dir: URL, args: [String]) async throws -> URL {
        let ffmpeg = try #require(ToolLocator.shared.path(for: "ffmpeg"))
        let url = dir.appendingPathComponent(name)
        let out = try await ProcessRunner().run(
            ffmpeg, ["-nostdin", "-y", "-loglevel", "error"] + args + [url.path], timeout: .seconds(60))
        try #require(out.code == 0)
        return url
    }

    private func makeWav(in dir: URL) async throws -> URL {
        try await generate("tone.wav", in: dir, args: ["-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono", "-t", "0.1"])
    }

    private func makeMP4(in dir: URL) async throws -> URL {
        try await generate("clip.mp4", in: dir, args: [
            "-f", "lavfi", "-i", "testsrc=size=16x16:rate=5:duration=0.2",
            "-f", "lavfi", "-i", "anullsrc=r=8000:cl=mono", "-t", "0.2",
            "-pix_fmt", "yuv420p", "-shortest",
        ])
    }

    private func size(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    @Test func supportsMediaPairs() {
        let c = MediaConverter()
        #expect(c.supports(from: wav, to: mp3))
        #expect(c.supports(from: mp4, to: webm))
        #expect(c.supports(from: mp4, to: m4a))
        #expect(!c.supports(from: wav, to: mp4))
        #expect(!c.supports(from: wav, to: wav))
        #expect(!c.supports(from: wav, to: FileFormat.format(forExtension: "png")!))
    }

    @Test(.enabled(if: MediaConverterTests.ffmpegInstalled))
    func wavToMP3ProducesAudio() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try await makeWav(in: dir)
        let result = try await MediaConverter().convert(
            ConversionRequest(input: input, target: mp3), progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "mp3")
        #expect(size(out) > 0)
        #expect(result.bytesWritten > 0)
    }

    @Test func ffmpegArgsRestrictProtocolsAndForceInputDemuxer() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cases: [(name: String, demuxer: String?)] = [
            ("a.wav", "wav"), ("a.mp3", "mp3"), ("a.flac", "flac"), ("a.aac", "aac"),
            ("a.mp4", "mov,mp4,m4a,3gp,3g2,mj2"), ("a.mov", "mov,mp4,m4a,3gp,3g2,mj2"),
            ("a.m4a", "mov,mp4,m4a,3gp,3g2,mj2"), ("a.mkv", "matroska,webm"), ("a.webm", "matroska,webm"),
        ]
        for (name, demuxer) in cases {
            let input = dir.appendingPathComponent(name)
            try Data([0]).write(to: input)
            let recorder = RecordingRunner()
            let converter = MediaConverter(locator: { _ in URL(fileURLWithPath: "/usr/bin/true") }, runner: recorder)
            let target = name.hasSuffix(".mp3") ? wav : mp3
            _ = try? await converter.convert(ConversionRequest(input: input, target: target), progress: { _ in })
            let args = try #require(recorder.lastArgs)
            let i = try #require(args.firstIndex(of: "-i"))
            let wl = try #require(args.firstIndex(of: "-protocol_whitelist"))
            #expect(args[wl + 1] == "file")
            #expect(wl < i)
            let f = try #require(args.firstIndex(of: "-f"))
            #expect(args[f + 1] == demuxer)
            #expect(f < i)
            #expect(args.contains("-nostdin") && args.contains("-y"))
        }
    }

    @Test(.enabled(if: MediaConverterTests.ffmpegInstalled))
    func videoToVideoContainersStillWork() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try await makeMP4(in: dir)
        let mkv = FileFormat.format(forExtension: "mkv")!
        let viaMKV = try await MediaConverter().convert(
            ConversionRequest(input: input, target: mkv), progress: { _ in })
        #expect(size(try #require(viaMKV.outputs.first)) > 0)
        let viaWebM = try await MediaConverter().convert(
            ConversionRequest(input: try #require(viaMKV.outputs.first), target: webm), progress: { _ in })
        #expect(size(try #require(viaWebM.outputs.first)) > 0)
    }

    @Test(.enabled(if: MediaConverterTests.ffmpegInstalled))
    func videoToAudioExtract() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try await makeMP4(in: dir)
        let result = try await MediaConverter().convert(
            ConversionRequest(input: input, target: m4a), progress: { _ in })
        let out = try #require(result.outputs.first)
        #expect(out.pathExtension == "m4a")
        #expect(size(out) > 0)
    }

    @Test(.enabled(if: MediaConverterTests.ffmpegInstalled))
    func existingOutputIsNotOverwritten() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try await makeWav(in: dir)
        let first = try await MediaConverter().convert(
            ConversionRequest(input: input, target: mp3), progress: { _ in })
        let second = try await MediaConverter().convert(
            ConversionRequest(input: input, target: mp3), progress: { _ in })
        #expect(first.outputs.first != second.outputs.first)
        #expect(size(try #require(second.outputs.first)) > 0)
    }

    @Test func missingInputThrowsInputNotFound() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).wav")
        await #expect(throws: WedgeError.inputNotFound(missing)) {
            _ = try await MediaConverter().convert(
                ConversionRequest(input: missing, target: mp3), progress: { _ in })
        }
    }

    @Test func absentFFmpegThrowsToolNotInstalled() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("a.wav")
        try Data([0]).write(to: input)
        let converter = MediaConverter(locator: { _ in nil })
        await #expect(throws: WedgeError.toolNotInstalled(tool: "ffmpeg", installHint: "brew install ffmpeg")) {
            _ = try await converter.convert(ConversionRequest(input: input, target: mp3), progress: { _ in })
        }
    }
}

private final class RecordingRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var args: [String]?
    var lastArgs: [String]? { lock.withLock { args } }
    func run(_ executable: URL, _ args: [String], timeout: Duration) async throws -> ProcessRunner.Output {
        lock.withLock { self.args = args }
        return ProcessRunner.Output(stdout: Data(), stderr: Data(), code: 1)
    }
}
