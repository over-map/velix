import Foundation
import os
import QuartzCore

/// M10 performance, in every build (not only DEBUG's `-map-perf`):
/// - launch phases as signposts (Instruments, subsystem `app.velix`, category `perf`) and one line per launch in
///   `Documents/diagnostics/launch.jsonl` (ms from the process start; `tools/ride-report --launch` sums them up);
/// - the map's frame counter, which the ride log's health line reads each minute (fps, slow frames).
@MainActor
enum PerfLog {
    static let signposter = OSSignposter(subsystem: "app.velix", category: "perf")
    nonisolated static let launchFile = CrashReports.directory.appending(path: "launch.jsonl")

    private static var phases: [(name: String, ms: Double)] = []
    private static var rootMs: Double?
    private static var written = false

    /// Times a launch step: a signpost interval and its milliseconds in the launch line.
    static func phase<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        let start = CACurrentMediaTime()
        defer {
            phases.append(("\(name)", (CACurrentMediaTime() - start) * 1000))
            signposter.endInterval(name, state)
        }
        return try body()
    }

    /// The first screen appeared (RootView).
    static func rootAppeared() {
        // Snapshot tests draw RootView inside the test host; those aren't launches.
        guard rootMs == nil, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        rootMs = sinceProcessStart()
        signposter.emitEvent("rootAppeared")
        // No map on screen (onboarding): write without its first frame.
        Task { try? await Task.sleep(for: .seconds(10)); write(mapMs: nil) }
    }

    /// The map drew its first complete frame.
    static func mapReady() {
        guard rootMs != nil, !written else { return }
        signposter.emitEvent("mapReady")
        write(mapMs: sinceProcessStart())
    }

    private static func write(mapMs: Double?) {
        guard !written, let rootMs else { return }
        written = true
        let info = Bundle.main.infoDictionary
        var line: [String: Any] = [
            "t": Int(Date().timeIntervalSince1970),
            "app": "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            // iOS may start the process ahead of the tap ("prewarm"); then the time from the process start isn't the rider's wait.
            "prewarmed": ProcessInfo.processInfo.environment["ActivePrewarm"] == "1",
            "rootMs": Int(rootMs.rounded()),
            "phases": Dictionary(phases.map { ($0.name, Int($0.ms.rounded())) }, uniquingKeysWith: +),
        ]
        if let mapMs { line["mapMs"] = Int(mapMs.rounded()) }
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: .sortedKeys) else { return }
        Task.detached(priority: .utility) { append(data + Data("\n".utf8), to: launchFile) }
    }

    nonisolated private static func append(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Milliseconds since the kernel started this process.
    static func sinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let tv = info.kp_proc.p_un.__p_starttime
        let start = Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000
        return (Date().timeIntervalSince1970 - start) * 1000
    }
}

/// The map's frames, counted from MapLibre's render callbacks (on main). The ride log takes and resets them each minute.
@MainActor
enum MapFrames {
    /// A frame whose render callback took longer than two display refreshes.
    static let slowSeconds = 1.0 / 30
    private static var frames = 0
    private static var slow = 0
    private static var since = CACurrentMediaTime()
    private static var frameStart = CACurrentMediaTime()

    static func willRender() { frameStart = CACurrentMediaTime() }

    static func didRender(fullyRendered: Bool) {
        let t = CACurrentMediaTime() - frameStart
        frames += 1
        if t > slowSeconds { slow += 1 }
        if fullyRendered { PerfLog.mapReady() }
        #if DEBUG
        Perf.add("frame", t)
        #endif
    }

    /// Frames a second and slow frames since the last call.
    static func take() -> (fps: Double, slow: Int) {
        let now = CACurrentMediaTime()
        let out = (fps: now > since ? Double(frames) / (now - since) : 0, slow: slow)
        frames = 0
        slow = 0
        since = now
        return out
    }
}
